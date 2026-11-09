// V5 : area optimised, radix-8 front end (V4 +)
//  * stages 1..3 are merged into one radix-8 front end on the raw 4 bit samples (8 circulating 16 x 4 bit
//    rows, 7 constant tables stored as magnitude + sign, 8 operand adder tree).  Only stages 4..7 need a
//    multiplier.

// ------------------------------------------------------------------ CLK_1
module CLK_1_MODULE (
    input         clk,
    input         rst_n,
    input         in_valid,
    input  [31:0] in_data,
    input         sidle,
    input         sdone,
    output        sready,
    output [31:0] din
);
    // Ring of RING (14) words that rotates every cycle.  While in_valid is high the new word enters at the tail;
    // afterwards the head recirculates.  The two oldest words are overwritten by words 14 and 15, which is
    // safe because they have long been handed to the handshake by then (checked by a simulation assertion).
    // idx always points at the position of the next word to send.
    localparam RING = 14;
    reg [31:0] r [0:RING-1];
    reg [4:0]  n;              // words received
    reg [4:0]  sc;             // words handed to the handshake
    reg [3:0]  idx;
    integer i;

    always @(posedge clk) begin
        for (i = 0; i < RING-1; i = i + 1) r[i] <= r[i+1];
        r[RING-1] <= in_valid ? in_data : r[0];
    end

    wire pending = (sc < n);
    wire accept  = pending & sidle;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n   <= 5'd0;
            sc  <= 5'd0;
            idx <= 4'd0;
        end else if (sc == 5'd16) begin
            n  <= 5'd0;
            sc <= 5'd0;
        end else begin
            if (in_valid) n <= n + 5'd1;
            if (accept)   sc <= sc + 5'd1;
            if (in_valid && n == 5'd0) idx <= RING - 1;
            else if (!accept)          idx <= (idx == 4'd0) ? RING - 1 : idx - 4'd1;   // accept: next word is one position up, ring moves one down
        end
    end

    // simulation only: the word about to be overwritten must already have been sent
    // synopsys translate_off
    always @(posedge clk) begin
        if (rst_n && in_valid && n >= RING && sc + RING < n + 1)
            $display("[ASSERT] ring overrun at %0t", $time);
    end
    // synopsys translate_on

    assign sready = pending;
    assign din    = r[idx];
endmodule

// ------------------------------------------------------------------ CLK_2
module CLK_2_MODULE (
    input         clk,
    input         rst_n,
    input         dvalid,
    input  [31:0] dout,
    output        dbusy,
    input         wfull,
    output        winc,
    output [15:0] wdata
);
    // The radix-8 front end presents stream position q at tick 112+q (registered output -> seen at 113+q).
    // stages 4..6 : product/y register + output register (2 ticks); stage 7 : 1 tick, feeds the FIFO.
    localparam F8_PIPE = 0;           // 1 : one extra register level inside the radix-8 front end (+1 tick)
    localparam D4 = 113 + F8_PIPE;
    localparam D5 = D4 + 8  + 2;
    localparam D6 = D5 + 4  + 2;
    localparam D7 = D6 + 2  + 2;
    localparam D8 = D7 + 1  + 1;      // first output position is presented on y7 here
    localparam GEND = D8 + 127;

    reg  [8:0] g;                // global tick counter
    reg  [4:0] wi;               // words received from the handshake

    wire [4:0] wi_nxt = wi + {4'd0, dvalid};
    wire       in_ph  = (g[8:7] == 2'b00);
    wire       have   = (wi_nxt > {1'b0, g[6:3]});
    wire       adv    = (~in_ph | have) & ~wfull;

    assign dbusy = in_ph & (wi > {1'b0, g[6:3]});

    wire       out_win = (g >= D8) & (g <= GEND);
    assign winc  = out_win & ~wfull;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            g  <= 9'd0;
            wi <= 5'd0;
        end else begin
            wi <= wi_nxt;
            if (adv) begin
                if (g == GEND) begin
                    g  <= 9'd0;
                    wi <= 5'd0;
                end else g <= g + 9'd1;
            end
        end
    end

    wire [3:0]  xin = dout >> {g[2:0], 2'b00};
    wire [13:0] y3, y4, y5, y6, y7;

    FRONT8 #(.PIPE(F8_PIPE)) u_f8 (.clk(clk), .adv(adv), .g(g), .x_in(xin), .y_out(y3));
    SDF_STAGE #(.S(4), .DOFF(D4)) u_s4 (.clk(clk), .adv(adv), .g(g), .x_in(y3), .y_out(y4));
    SDF_STAGE #(.S(5), .DOFF(D5)) u_s5 (.clk(clk), .adv(adv), .g(g), .x_in(y4), .y_out(y5));
    SDF_STAGE #(.S(6), .DOFF(D6)) u_s6 (.clk(clk), .adv(adv), .g(g), .x_in(y5), .y_out(y6));
    SDF_STAGE #(.S(7), .DOFF(D7), .OREG(0)) u_s7 (.clk(clk), .adv(adv), .g(g), .x_in(y6), .y_out(y7));

    assign wdata = {2'b00, y7};
endmodule

// ------------------------------------------------------------------ stages 1..3 (radix-8 front end)
// y[16k+p] = x[p] + sum_{i=1..7} C[k][i] * x[p+16i]   (mod Q),  p = 0..15, k = 0..7
// Row i holds x[16i .. 16i+15] and rotates once per tick, so at tick t >= 112 the eight row heads are
// x[p], x[p+16], ..., x[p+112] with p = (t-112) mod 16 ; k = (t-112) / 16.  During k = 0 the last operand
// is taken straight from the input stream.
module FRONT8 #(parameter PIPE = 0) (
    input         clk,
    input         adv,
    input  [8:0]  g,
    input  [3:0]  x_in,
    output reg [13:0] y_out
);
    localparam Q = 14'd12289;

    // ---- BEGIN_F8_LUT (generated by tools/gen_rom.py, do not edit)
    // radix-8 front end: t_i(k,x) = C[k][i]*x mod Q  (i = 1..7), k = output block (3 bit);
    // implemented as magnitude table + sign (the value Q is equivalent to 0 modulo Q)
    function [13:0] t1;
        input [2:0] k;
        input [3:0] x;
        reg [1:0] sel;
        reg        sg;
        reg [13:0] m;
        begin
            case (k)
                3'd0: begin sel = 2'd1; sg = 1'b1; end
                3'd1: begin sel = 2'd1; sg = 1'b0; end
                3'd2: begin sel = 2'd0; sg = 1'b0; end
                3'd3: begin sel = 2'd0; sg = 1'b1; end
                3'd4: begin sel = 2'd3; sg = 1'b0; end
                3'd5: begin sel = 2'd3; sg = 1'b1; end
                3'd6: begin sel = 2'd2; sg = 1'b1; end
                3'd7: begin sel = 2'd2; sg = 1'b0; end
                default: begin sel = 2'd0; sg = 1'b0; end
            endcase
            case ({sel, x})
                {2'd0, 4'd0}: m = 14'd0;
                {2'd0, 4'd1}: m = 14'd722;
                {2'd0, 4'd2}: m = 14'd1444;
                {2'd0, 4'd3}: m = 14'd2166;
                {2'd0, 4'd4}: m = 14'd2888;
                {2'd0, 4'd5}: m = 14'd3610;
                {2'd0, 4'd6}: m = 14'd4332;
                {2'd0, 4'd7}: m = 14'd5054;
                {2'd0, 4'd8}: m = 14'd5776;
                {2'd0, 4'd9}: m = 14'd6498;
                {2'd0, 4'd10}: m = 14'd7220;
                {2'd0, 4'd11}: m = 14'd7942;
                {2'd0, 4'd12}: m = 14'd8664;
                {2'd0, 4'd13}: m = 14'd9386;
                {2'd0, 4'd14}: m = 14'd10108;
                {2'd0, 4'd15}: m = 14'd10830;
                {2'd1, 4'd0}: m = 14'd0;
                {2'd1, 4'd1}: m = 14'd1305;
                {2'd1, 4'd2}: m = 14'd2610;
                {2'd1, 4'd3}: m = 14'd3915;
                {2'd1, 4'd4}: m = 14'd5220;
                {2'd1, 4'd5}: m = 14'd6525;
                {2'd1, 4'd6}: m = 14'd7830;
                {2'd1, 4'd7}: m = 14'd9135;
                {2'd1, 4'd8}: m = 14'd10440;
                {2'd1, 4'd9}: m = 14'd11745;
                {2'd1, 4'd10}: m = 14'd761;
                {2'd1, 4'd11}: m = 14'd2066;
                {2'd1, 4'd12}: m = 14'd3371;
                {2'd1, 4'd13}: m = 14'd4676;
                {2'd1, 4'd14}: m = 14'd5981;
                {2'd1, 4'd15}: m = 14'd7286;
                {2'd2, 4'd0}: m = 14'd0;
                {2'd2, 4'd1}: m = 14'd4134;
                {2'd2, 4'd2}: m = 14'd8268;
                {2'd2, 4'd3}: m = 14'd113;
                {2'd2, 4'd4}: m = 14'd4247;
                {2'd2, 4'd5}: m = 14'd8381;
                {2'd2, 4'd6}: m = 14'd226;
                {2'd2, 4'd7}: m = 14'd4360;
                {2'd2, 4'd8}: m = 14'd8494;
                {2'd2, 4'd9}: m = 14'd339;
                {2'd2, 4'd10}: m = 14'd4473;
                {2'd2, 4'd11}: m = 14'd8607;
                {2'd2, 4'd12}: m = 14'd452;
                {2'd2, 4'd13}: m = 14'd4586;
                {2'd2, 4'd14}: m = 14'd8720;
                {2'd2, 4'd15}: m = 14'd565;
                {2'd3, 4'd0}: m = 14'd0;
                {2'd3, 4'd1}: m = 14'd5736;
                {2'd3, 4'd2}: m = 14'd11472;
                {2'd3, 4'd3}: m = 14'd4919;
                {2'd3, 4'd4}: m = 14'd10655;
                {2'd3, 4'd5}: m = 14'd4102;
                {2'd3, 4'd6}: m = 14'd9838;
                {2'd3, 4'd7}: m = 14'd3285;
                {2'd3, 4'd8}: m = 14'd9021;
                {2'd3, 4'd9}: m = 14'd2468;
                {2'd3, 4'd10}: m = 14'd8204;
                {2'd3, 4'd11}: m = 14'd1651;
                {2'd3, 4'd12}: m = 14'd7387;
                {2'd3, 4'd13}: m = 14'd834;
                {2'd3, 4'd14}: m = 14'd6570;
                {2'd3, 4'd15}: m = 14'd17;
                default: m = 14'd0;
            endcase
            t1 = sg ? (14'd12289 - m) : m;
        end
    endfunction
    function [13:0] t2;
        input [2:0] k;
        input [3:0] x;
        reg [0:0] sel;
        reg        sg;
        reg [13:0] m;
        begin
            case (k)
                3'd0: begin sel = 1'd1; sg = 1'b1; end
                3'd1: begin sel = 1'd1; sg = 1'b1; end
                3'd2: begin sel = 1'd1; sg = 1'b0; end
                3'd3: begin sel = 1'd1; sg = 1'b0; end
                3'd4: begin sel = 1'd0; sg = 1'b0; end
                3'd5: begin sel = 1'd0; sg = 1'b0; end
                3'd6: begin sel = 1'd0; sg = 1'b1; end
                3'd7: begin sel = 1'd0; sg = 1'b1; end
                default: begin sel = 1'd0; sg = 1'b0; end
            endcase
            case ({sel, x})
                {1'd0, 4'd0}: m = 14'd0;
                {1'd0, 4'd1}: m = 14'd4043;
                {1'd0, 4'd2}: m = 14'd8086;
                {1'd0, 4'd3}: m = 14'd12129;
                {1'd0, 4'd4}: m = 14'd3883;
                {1'd0, 4'd5}: m = 14'd7926;
                {1'd0, 4'd6}: m = 14'd11969;
                {1'd0, 4'd7}: m = 14'd3723;
                {1'd0, 4'd8}: m = 14'd7766;
                {1'd0, 4'd9}: m = 14'd11809;
                {1'd0, 4'd10}: m = 14'd3563;
                {1'd0, 4'd11}: m = 14'd7606;
                {1'd0, 4'd12}: m = 14'd11649;
                {1'd0, 4'd13}: m = 14'd3403;
                {1'd0, 4'd14}: m = 14'd7446;
                {1'd0, 4'd15}: m = 14'd11489;
                {1'd1, 4'd0}: m = 14'd0;
                {1'd1, 4'd1}: m = 14'd5146;
                {1'd1, 4'd2}: m = 14'd10292;
                {1'd1, 4'd3}: m = 14'd3149;
                {1'd1, 4'd4}: m = 14'd8295;
                {1'd1, 4'd5}: m = 14'd1152;
                {1'd1, 4'd6}: m = 14'd6298;
                {1'd1, 4'd7}: m = 14'd11444;
                {1'd1, 4'd8}: m = 14'd4301;
                {1'd1, 4'd9}: m = 14'd9447;
                {1'd1, 4'd10}: m = 14'd2304;
                {1'd1, 4'd11}: m = 14'd7450;
                {1'd1, 4'd12}: m = 14'd307;
                {1'd1, 4'd13}: m = 14'd5453;
                {1'd1, 4'd14}: m = 14'd10599;
                {1'd1, 4'd15}: m = 14'd3456;
                default: m = 14'd0;
            endcase
            t2 = sg ? (14'd12289 - m) : m;
        end
    endfunction
    function [13:0] t3;
        input [2:0] k;
        input [3:0] x;
        reg [1:0] sel;
        reg        sg;
        reg [13:0] m;
        begin
            case (k)
                3'd0: begin sel = 2'd3; sg = 1'b0; end
                3'd1: begin sel = 2'd3; sg = 1'b1; end
                3'd2: begin sel = 2'd2; sg = 1'b0; end
                3'd3: begin sel = 2'd2; sg = 1'b1; end
                3'd4: begin sel = 2'd1; sg = 1'b0; end
                3'd5: begin sel = 2'd1; sg = 1'b1; end
                3'd6: begin sel = 2'd0; sg = 1'b0; end
                3'd7: begin sel = 2'd0; sg = 1'b1; end
                default: begin sel = 2'd0; sg = 1'b0; end
            endcase
            case ({sel, x})
                {2'd0, 4'd0}: m = 14'd0;
                {2'd0, 4'd1}: m = 14'd722;
                {2'd0, 4'd2}: m = 14'd1444;
                {2'd0, 4'd3}: m = 14'd2166;
                {2'd0, 4'd4}: m = 14'd2888;
                {2'd0, 4'd5}: m = 14'd3610;
                {2'd0, 4'd6}: m = 14'd4332;
                {2'd0, 4'd7}: m = 14'd5054;
                {2'd0, 4'd8}: m = 14'd5776;
                {2'd0, 4'd9}: m = 14'd6498;
                {2'd0, 4'd10}: m = 14'd7220;
                {2'd0, 4'd11}: m = 14'd7942;
                {2'd0, 4'd12}: m = 14'd8664;
                {2'd0, 4'd13}: m = 14'd9386;
                {2'd0, 4'd14}: m = 14'd10108;
                {2'd0, 4'd15}: m = 14'd10830;
                {2'd1, 4'd0}: m = 14'd0;
                {2'd1, 4'd1}: m = 14'd1305;
                {2'd1, 4'd2}: m = 14'd2610;
                {2'd1, 4'd3}: m = 14'd3915;
                {2'd1, 4'd4}: m = 14'd5220;
                {2'd1, 4'd5}: m = 14'd6525;
                {2'd1, 4'd6}: m = 14'd7830;
                {2'd1, 4'd7}: m = 14'd9135;
                {2'd1, 4'd8}: m = 14'd10440;
                {2'd1, 4'd9}: m = 14'd11745;
                {2'd1, 4'd10}: m = 14'd761;
                {2'd1, 4'd11}: m = 14'd2066;
                {2'd1, 4'd12}: m = 14'd3371;
                {2'd1, 4'd13}: m = 14'd4676;
                {2'd1, 4'd14}: m = 14'd5981;
                {2'd1, 4'd15}: m = 14'd7286;
                {2'd2, 4'd0}: m = 14'd0;
                {2'd2, 4'd1}: m = 14'd4134;
                {2'd2, 4'd2}: m = 14'd8268;
                {2'd2, 4'd3}: m = 14'd113;
                {2'd2, 4'd4}: m = 14'd4247;
                {2'd2, 4'd5}: m = 14'd8381;
                {2'd2, 4'd6}: m = 14'd226;
                {2'd2, 4'd7}: m = 14'd4360;
                {2'd2, 4'd8}: m = 14'd8494;
                {2'd2, 4'd9}: m = 14'd339;
                {2'd2, 4'd10}: m = 14'd4473;
                {2'd2, 4'd11}: m = 14'd8607;
                {2'd2, 4'd12}: m = 14'd452;
                {2'd2, 4'd13}: m = 14'd4586;
                {2'd2, 4'd14}: m = 14'd8720;
                {2'd2, 4'd15}: m = 14'd565;
                {2'd3, 4'd0}: m = 14'd0;
                {2'd3, 4'd1}: m = 14'd5736;
                {2'd3, 4'd2}: m = 14'd11472;
                {2'd3, 4'd3}: m = 14'd4919;
                {2'd3, 4'd4}: m = 14'd10655;
                {2'd3, 4'd5}: m = 14'd4102;
                {2'd3, 4'd6}: m = 14'd9838;
                {2'd3, 4'd7}: m = 14'd3285;
                {2'd3, 4'd8}: m = 14'd9021;
                {2'd3, 4'd9}: m = 14'd2468;
                {2'd3, 4'd10}: m = 14'd8204;
                {2'd3, 4'd11}: m = 14'd1651;
                {2'd3, 4'd12}: m = 14'd7387;
                {2'd3, 4'd13}: m = 14'd834;
                {2'd3, 4'd14}: m = 14'd6570;
                {2'd3, 4'd15}: m = 14'd17;
                default: m = 14'd0;
            endcase
            t3 = sg ? (14'd12289 - m) : m;
        end
    endfunction
    function [13:0] t4;
        input [2:0] k;
        input [3:0] x;
        reg [0:0] sel;
        reg        sg;
        reg [13:0] m;
        begin
            case (k)
                3'd0: begin sel = 1'd0; sg = 1'b1; end
                3'd1: begin sel = 1'd0; sg = 1'b1; end
                3'd2: begin sel = 1'd0; sg = 1'b1; end
                3'd3: begin sel = 1'd0; sg = 1'b1; end
                3'd4: begin sel = 1'd0; sg = 1'b0; end
                3'd5: begin sel = 1'd0; sg = 1'b0; end
                3'd6: begin sel = 1'd0; sg = 1'b0; end
                3'd7: begin sel = 1'd0; sg = 1'b0; end
                default: begin sel = 1'd0; sg = 1'b0; end
            endcase
            case ({sel, x})
                {1'd0, 4'd0}: m = 14'd0;
                {1'd0, 4'd1}: m = 14'd1479;
                {1'd0, 4'd2}: m = 14'd2958;
                {1'd0, 4'd3}: m = 14'd4437;
                {1'd0, 4'd4}: m = 14'd5916;
                {1'd0, 4'd5}: m = 14'd7395;
                {1'd0, 4'd6}: m = 14'd8874;
                {1'd0, 4'd7}: m = 14'd10353;
                {1'd0, 4'd8}: m = 14'd11832;
                {1'd0, 4'd9}: m = 14'd1022;
                {1'd0, 4'd10}: m = 14'd2501;
                {1'd0, 4'd11}: m = 14'd3980;
                {1'd0, 4'd12}: m = 14'd5459;
                {1'd0, 4'd13}: m = 14'd6938;
                {1'd0, 4'd14}: m = 14'd8417;
                {1'd0, 4'd15}: m = 14'd9896;
                default: m = 14'd0;
            endcase
            t4 = sg ? (14'd12289 - m) : m;
        end
    endfunction
    function [13:0] t5;
        input [2:0] k;
        input [3:0] x;
        reg [1:0] sel;
        reg        sg;
        reg [13:0] m;
        begin
            case (k)
                3'd0: begin sel = 2'd0; sg = 1'b0; end
                3'd1: begin sel = 2'd0; sg = 1'b1; end
                3'd2: begin sel = 2'd1; sg = 1'b0; end
                3'd3: begin sel = 2'd1; sg = 1'b1; end
                3'd4: begin sel = 2'd2; sg = 1'b0; end
                3'd5: begin sel = 2'd2; sg = 1'b1; end
                3'd6: begin sel = 2'd3; sg = 1'b0; end
                3'd7: begin sel = 2'd3; sg = 1'b1; end
                default: begin sel = 2'd0; sg = 1'b0; end
            endcase
            case ({sel, x})
                {2'd0, 4'd0}: m = 14'd0;
                {2'd0, 4'd1}: m = 14'd722;
                {2'd0, 4'd2}: m = 14'd1444;
                {2'd0, 4'd3}: m = 14'd2166;
                {2'd0, 4'd4}: m = 14'd2888;
                {2'd0, 4'd5}: m = 14'd3610;
                {2'd0, 4'd6}: m = 14'd4332;
                {2'd0, 4'd7}: m = 14'd5054;
                {2'd0, 4'd8}: m = 14'd5776;
                {2'd0, 4'd9}: m = 14'd6498;
                {2'd0, 4'd10}: m = 14'd7220;
                {2'd0, 4'd11}: m = 14'd7942;
                {2'd0, 4'd12}: m = 14'd8664;
                {2'd0, 4'd13}: m = 14'd9386;
                {2'd0, 4'd14}: m = 14'd10108;
                {2'd0, 4'd15}: m = 14'd10830;
                {2'd1, 4'd0}: m = 14'd0;
                {2'd1, 4'd1}: m = 14'd1305;
                {2'd1, 4'd2}: m = 14'd2610;
                {2'd1, 4'd3}: m = 14'd3915;
                {2'd1, 4'd4}: m = 14'd5220;
                {2'd1, 4'd5}: m = 14'd6525;
                {2'd1, 4'd6}: m = 14'd7830;
                {2'd1, 4'd7}: m = 14'd9135;
                {2'd1, 4'd8}: m = 14'd10440;
                {2'd1, 4'd9}: m = 14'd11745;
                {2'd1, 4'd10}: m = 14'd761;
                {2'd1, 4'd11}: m = 14'd2066;
                {2'd1, 4'd12}: m = 14'd3371;
                {2'd1, 4'd13}: m = 14'd4676;
                {2'd1, 4'd14}: m = 14'd5981;
                {2'd1, 4'd15}: m = 14'd7286;
                {2'd2, 4'd0}: m = 14'd0;
                {2'd2, 4'd1}: m = 14'd4134;
                {2'd2, 4'd2}: m = 14'd8268;
                {2'd2, 4'd3}: m = 14'd113;
                {2'd2, 4'd4}: m = 14'd4247;
                {2'd2, 4'd5}: m = 14'd8381;
                {2'd2, 4'd6}: m = 14'd226;
                {2'd2, 4'd7}: m = 14'd4360;
                {2'd2, 4'd8}: m = 14'd8494;
                {2'd2, 4'd9}: m = 14'd339;
                {2'd2, 4'd10}: m = 14'd4473;
                {2'd2, 4'd11}: m = 14'd8607;
                {2'd2, 4'd12}: m = 14'd452;
                {2'd2, 4'd13}: m = 14'd4586;
                {2'd2, 4'd14}: m = 14'd8720;
                {2'd2, 4'd15}: m = 14'd565;
                {2'd3, 4'd0}: m = 14'd0;
                {2'd3, 4'd1}: m = 14'd5736;
                {2'd3, 4'd2}: m = 14'd11472;
                {2'd3, 4'd3}: m = 14'd4919;
                {2'd3, 4'd4}: m = 14'd10655;
                {2'd3, 4'd5}: m = 14'd4102;
                {2'd3, 4'd6}: m = 14'd9838;
                {2'd3, 4'd7}: m = 14'd3285;
                {2'd3, 4'd8}: m = 14'd9021;
                {2'd3, 4'd9}: m = 14'd2468;
                {2'd3, 4'd10}: m = 14'd8204;
                {2'd3, 4'd11}: m = 14'd1651;
                {2'd3, 4'd12}: m = 14'd7387;
                {2'd3, 4'd13}: m = 14'd834;
                {2'd3, 4'd14}: m = 14'd6570;
                {2'd3, 4'd15}: m = 14'd17;
                default: m = 14'd0;
            endcase
            t5 = sg ? (14'd12289 - m) : m;
        end
    endfunction
    function [13:0] t6;
        input [2:0] k;
        input [3:0] x;
        reg [0:0] sel;
        reg        sg;
        reg [13:0] m;
        begin
            case (k)
                3'd0: begin sel = 1'd0; sg = 1'b0; end
                3'd1: begin sel = 1'd0; sg = 1'b0; end
                3'd2: begin sel = 1'd0; sg = 1'b1; end
                3'd3: begin sel = 1'd0; sg = 1'b1; end
                3'd4: begin sel = 1'd1; sg = 1'b1; end
                3'd5: begin sel = 1'd1; sg = 1'b1; end
                3'd6: begin sel = 1'd1; sg = 1'b0; end
                3'd7: begin sel = 1'd1; sg = 1'b0; end
                default: begin sel = 1'd0; sg = 1'b0; end
            endcase
            case ({sel, x})
                {1'd0, 4'd0}: m = 14'd0;
                {1'd0, 4'd1}: m = 14'd4043;
                {1'd0, 4'd2}: m = 14'd8086;
                {1'd0, 4'd3}: m = 14'd12129;
                {1'd0, 4'd4}: m = 14'd3883;
                {1'd0, 4'd5}: m = 14'd7926;
                {1'd0, 4'd6}: m = 14'd11969;
                {1'd0, 4'd7}: m = 14'd3723;
                {1'd0, 4'd8}: m = 14'd7766;
                {1'd0, 4'd9}: m = 14'd11809;
                {1'd0, 4'd10}: m = 14'd3563;
                {1'd0, 4'd11}: m = 14'd7606;
                {1'd0, 4'd12}: m = 14'd11649;
                {1'd0, 4'd13}: m = 14'd3403;
                {1'd0, 4'd14}: m = 14'd7446;
                {1'd0, 4'd15}: m = 14'd11489;
                {1'd1, 4'd0}: m = 14'd0;
                {1'd1, 4'd1}: m = 14'd5146;
                {1'd1, 4'd2}: m = 14'd10292;
                {1'd1, 4'd3}: m = 14'd3149;
                {1'd1, 4'd4}: m = 14'd8295;
                {1'd1, 4'd5}: m = 14'd1152;
                {1'd1, 4'd6}: m = 14'd6298;
                {1'd1, 4'd7}: m = 14'd11444;
                {1'd1, 4'd8}: m = 14'd4301;
                {1'd1, 4'd9}: m = 14'd9447;
                {1'd1, 4'd10}: m = 14'd2304;
                {1'd1, 4'd11}: m = 14'd7450;
                {1'd1, 4'd12}: m = 14'd307;
                {1'd1, 4'd13}: m = 14'd5453;
                {1'd1, 4'd14}: m = 14'd10599;
                {1'd1, 4'd15}: m = 14'd3456;
                default: m = 14'd0;
            endcase
            t6 = sg ? (14'd12289 - m) : m;
        end
    endfunction
    function [13:0] t7;
        input [2:0] k;
        input [3:0] x;
        reg [1:0] sel;
        reg        sg;
        reg [13:0] m;
        begin
            case (k)
                3'd0: begin sel = 2'd2; sg = 1'b1; end
                3'd1: begin sel = 2'd2; sg = 1'b0; end
                3'd2: begin sel = 2'd3; sg = 1'b0; end
                3'd3: begin sel = 2'd3; sg = 1'b1; end
                3'd4: begin sel = 2'd0; sg = 1'b0; end
                3'd5: begin sel = 2'd0; sg = 1'b1; end
                3'd6: begin sel = 2'd1; sg = 1'b1; end
                3'd7: begin sel = 2'd1; sg = 1'b0; end
                default: begin sel = 2'd0; sg = 1'b0; end
            endcase
            case ({sel, x})
                {2'd0, 4'd0}: m = 14'd0;
                {2'd0, 4'd1}: m = 14'd722;
                {2'd0, 4'd2}: m = 14'd1444;
                {2'd0, 4'd3}: m = 14'd2166;
                {2'd0, 4'd4}: m = 14'd2888;
                {2'd0, 4'd5}: m = 14'd3610;
                {2'd0, 4'd6}: m = 14'd4332;
                {2'd0, 4'd7}: m = 14'd5054;
                {2'd0, 4'd8}: m = 14'd5776;
                {2'd0, 4'd9}: m = 14'd6498;
                {2'd0, 4'd10}: m = 14'd7220;
                {2'd0, 4'd11}: m = 14'd7942;
                {2'd0, 4'd12}: m = 14'd8664;
                {2'd0, 4'd13}: m = 14'd9386;
                {2'd0, 4'd14}: m = 14'd10108;
                {2'd0, 4'd15}: m = 14'd10830;
                {2'd1, 4'd0}: m = 14'd0;
                {2'd1, 4'd1}: m = 14'd1305;
                {2'd1, 4'd2}: m = 14'd2610;
                {2'd1, 4'd3}: m = 14'd3915;
                {2'd1, 4'd4}: m = 14'd5220;
                {2'd1, 4'd5}: m = 14'd6525;
                {2'd1, 4'd6}: m = 14'd7830;
                {2'd1, 4'd7}: m = 14'd9135;
                {2'd1, 4'd8}: m = 14'd10440;
                {2'd1, 4'd9}: m = 14'd11745;
                {2'd1, 4'd10}: m = 14'd761;
                {2'd1, 4'd11}: m = 14'd2066;
                {2'd1, 4'd12}: m = 14'd3371;
                {2'd1, 4'd13}: m = 14'd4676;
                {2'd1, 4'd14}: m = 14'd5981;
                {2'd1, 4'd15}: m = 14'd7286;
                {2'd2, 4'd0}: m = 14'd0;
                {2'd2, 4'd1}: m = 14'd4134;
                {2'd2, 4'd2}: m = 14'd8268;
                {2'd2, 4'd3}: m = 14'd113;
                {2'd2, 4'd4}: m = 14'd4247;
                {2'd2, 4'd5}: m = 14'd8381;
                {2'd2, 4'd6}: m = 14'd226;
                {2'd2, 4'd7}: m = 14'd4360;
                {2'd2, 4'd8}: m = 14'd8494;
                {2'd2, 4'd9}: m = 14'd339;
                {2'd2, 4'd10}: m = 14'd4473;
                {2'd2, 4'd11}: m = 14'd8607;
                {2'd2, 4'd12}: m = 14'd452;
                {2'd2, 4'd13}: m = 14'd4586;
                {2'd2, 4'd14}: m = 14'd8720;
                {2'd2, 4'd15}: m = 14'd565;
                {2'd3, 4'd0}: m = 14'd0;
                {2'd3, 4'd1}: m = 14'd5736;
                {2'd3, 4'd2}: m = 14'd11472;
                {2'd3, 4'd3}: m = 14'd4919;
                {2'd3, 4'd4}: m = 14'd10655;
                {2'd3, 4'd5}: m = 14'd4102;
                {2'd3, 4'd6}: m = 14'd9838;
                {2'd3, 4'd7}: m = 14'd3285;
                {2'd3, 4'd8}: m = 14'd9021;
                {2'd3, 4'd9}: m = 14'd2468;
                {2'd3, 4'd10}: m = 14'd8204;
                {2'd3, 4'd11}: m = 14'd1651;
                {2'd3, 4'd12}: m = 14'd7387;
                {2'd3, 4'd13}: m = 14'd834;
                {2'd3, 4'd14}: m = 14'd6570;
                {2'd3, 4'd15}: m = 14'd17;
                default: m = 14'd0;
            endcase
            t7 = sg ? (14'd12289 - m) : m;
        end
    endfunction
    // ---- END_F8_LUT

    reg [3:0] row [0:7][0:15];
    integer i, j;

    wire       in_ph = (g[8:7] == 2'b00);
    wire [2:0] win   = g[6:4];                 // which row is being loaded (input phase)
    wire [3:0] k4    = g[7:4] - 4'd7;          // output block (valid for 112 <= g < 240)
    wire [2:0] k     = k4[2:0];

    wire [3:0] h0 = row[0][15];
    wire [3:0] h1 = row[1][15];
    wire [3:0] h2 = row[2][15];
    wire [3:0] h3 = row[3][15];
    wire [3:0] h4 = row[4][15];
    wire [3:0] h5 = row[5][15];
    wire [3:0] h6 = row[6][15];
    wire [3:0] h7 = (k4 == 4'd0) ? x_in : row[7][15];

    always @(posedge clk) begin
        if (adv) begin
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 15; j > 0; j = j - 1) row[i][j] <= row[i][j-1];
                row[i][0] <= (in_ph && win == i) ? x_in : row[i][15];
            end
        end
    end

    // operand sums; with PIPE = 1 they are registered in two halves before the final addition / reduction
    wire [18:0] s_lo = {15'd0, h0} + {5'd0, t1(k, h1)} + {5'd0, t2(k, h2)} + {5'd0, t3(k, h3)};
    wire [18:0] s_hi = {5'd0, t4(k, h4)} + {5'd0, t5(k, h5)} + {5'd0, t6(k, h6)} + {5'd0, t7(k, h7)};
    reg  [17:0] s_lo_r, s_hi_r;
    always @(posedge clk) begin
        if (adv) begin
            s_lo_r <= s_lo[17:0];
            s_hi_r <= s_hi[17:0];
        end
    end
    wire [18:0] s = (PIPE != 0) ? ({1'b0, s_lo_r} + {1'b0, s_hi_r}) : (s_lo + s_hi);   // < 7Q + 15
    wire [13:0] yv = (s >= 19'd86023) ? s - 19'd86023 :
                     (s >= 19'd73734) ? s - 19'd73734 :
                     (s >= 19'd61445) ? s - 19'd61445 :
                     (s >= 19'd49156) ? s - 19'd49156 :
                     (s >= 19'd36867) ? s - 19'd36867 :
                     (s >= 19'd24578) ? s - 19'd24578 :
                     (s >= 19'd12289) ? s - 19'd12289 : s[13:0];

    always @(posedge clk) if (adv) y_out <= yv;
endmodule

// ------------------------------------------------------------------ stages 2..7
// Pipeline of one stage (all registers are enabled by "adv"):
//   y_in --(x_in * w)--> [p1 : 12 bit high part, 16 bit Montgomery factor y, nz flag]
//        --(reduce + butterfly with delay line head)--> [y_out]
// Montgomery reduction with Q = 12289 = 3*2^12 + 1, Q0I = 12287 = 3*2^12 - 1:
//   y  = (3*x[3:0] mod 16) << 12  -  x[15:0]            (mod 2^16)
//   z  = x[27:16] + ((3*y + y[15:12]) >> 4) + (x[15:0] != 0)       in [0, 1.19 Q)
module SDF_STAGE #(
    parameter S    = 2,
    parameter DOFF = 0,           // tick at which input position 0 is presented
    parameter OREG = 1            // 1 : registered output, 0 : combinational output
) (
    input         clk,
    input         adv,
    input  [8:0]  g,
    input  [13:0] x_in,
    output [13:0] y_out
);
    localparam Q   = 14'd12289;
    localparam HT  = 1 << (7 - S);
    localparam MONT_ONE = 14'd4091;           // R mod Q  (Montgomery "1")

    // ---- BEGIN_GMB_ROM (generated by tools/gen_rom.py, do not edit)
    function [13:0] gmb;
        input [6:0] k;
        begin
            case (k)
                7'd1: gmb = 14'd7888;
                7'd2: gmb = 14'd11060;
                7'd3: gmb = 14'd11208;
                7'd4: gmb = 14'd6960;
                7'd5: gmb = 14'd4342;
                7'd6: gmb = 14'd6275;
                7'd7: gmb = 14'd9759;
                7'd8: gmb = 14'd1591;
                7'd9: gmb = 14'd6399;
                7'd10: gmb = 14'd9477;
                7'd11: gmb = 14'd5266;
                7'd12: gmb = 14'd586;
                7'd13: gmb = 14'd5825;
                7'd14: gmb = 14'd7538;
                7'd15: gmb = 14'd9710;
                7'd16: gmb = 14'd1134;
                7'd17: gmb = 14'd6407;
                7'd18: gmb = 14'd1711;
                7'd19: gmb = 14'd965;
                7'd20: gmb = 14'd7099;
                7'd21: gmb = 14'd7674;
                7'd22: gmb = 14'd3743;
                7'd23: gmb = 14'd6442;
                7'd24: gmb = 14'd10414;
                7'd25: gmb = 14'd8100;
                7'd26: gmb = 14'd1885;
                7'd27: gmb = 14'd1688;
                7'd28: gmb = 14'd1364;
                7'd29: gmb = 14'd10329;
                7'd30: gmb = 14'd10164;
                7'd31: gmb = 14'd9180;
                7'd32: gmb = 14'd12210;
                7'd33: gmb = 14'd6240;
                7'd34: gmb = 14'd997;
                7'd35: gmb = 14'd117;
                7'd36: gmb = 14'd4783;
                7'd37: gmb = 14'd4407;
                7'd38: gmb = 14'd1549;
                7'd39: gmb = 14'd7072;
                7'd40: gmb = 14'd2829;
                7'd41: gmb = 14'd6458;
                7'd42: gmb = 14'd4431;
                7'd43: gmb = 14'd8877;
                7'd44: gmb = 14'd7144;
                7'd45: gmb = 14'd2564;
                7'd46: gmb = 14'd5664;
                7'd47: gmb = 14'd4042;
                7'd48: gmb = 14'd12189;
                7'd49: gmb = 14'd432;
                7'd50: gmb = 14'd10751;
                7'd51: gmb = 14'd1237;
                7'd52: gmb = 14'd7610;
                7'd53: gmb = 14'd1534;
                7'd54: gmb = 14'd3983;
                7'd55: gmb = 14'd7863;
                7'd56: gmb = 14'd2181;
                7'd57: gmb = 14'd6308;
                7'd58: gmb = 14'd8720;
                7'd59: gmb = 14'd6570;
                7'd60: gmb = 14'd4843;
                7'd61: gmb = 14'd1690;
                7'd62: gmb = 14'd14;
                7'd63: gmb = 14'd3872;
                7'd64: gmb = 14'd5569;
                7'd65: gmb = 14'd9368;
                7'd66: gmb = 14'd12163;
                7'd67: gmb = 14'd2019;
                7'd68: gmb = 14'd7543;
                7'd69: gmb = 14'd2315;
                7'd70: gmb = 14'd4673;
                7'd71: gmb = 14'd7340;
                7'd72: gmb = 14'd1553;
                7'd73: gmb = 14'd1156;
                7'd74: gmb = 14'd8401;
                7'd75: gmb = 14'd11389;
                7'd76: gmb = 14'd1020;
                7'd77: gmb = 14'd2967;
                7'd78: gmb = 14'd10772;
                7'd79: gmb = 14'd7045;
                7'd80: gmb = 14'd3316;
                7'd81: gmb = 14'd11236;
                7'd82: gmb = 14'd5285;
                7'd83: gmb = 14'd11578;
                7'd84: gmb = 14'd10637;
                7'd85: gmb = 14'd10086;
                7'd86: gmb = 14'd9493;
                7'd87: gmb = 14'd6180;
                7'd88: gmb = 14'd9277;
                7'd89: gmb = 14'd6130;
                7'd90: gmb = 14'd3323;
                7'd91: gmb = 14'd883;
                7'd92: gmb = 14'd10469;
                7'd93: gmb = 14'd489;
                7'd94: gmb = 14'd1502;
                7'd95: gmb = 14'd2851;
                7'd96: gmb = 14'd11061;
                7'd97: gmb = 14'd9729;
                7'd98: gmb = 14'd2742;
                7'd99: gmb = 14'd12241;
                7'd100: gmb = 14'd4970;
                7'd101: gmb = 14'd10481;
                7'd102: gmb = 14'd10078;
                7'd103: gmb = 14'd1195;
                7'd104: gmb = 14'd730;
                7'd105: gmb = 14'd1762;
                7'd106: gmb = 14'd3854;
                7'd107: gmb = 14'd2030;
                7'd108: gmb = 14'd5892;
                7'd109: gmb = 14'd10922;
                7'd110: gmb = 14'd9020;
                7'd111: gmb = 14'd5274;
                7'd112: gmb = 14'd9179;
                7'd113: gmb = 14'd3604;
                7'd114: gmb = 14'd3782;
                7'd115: gmb = 14'd10206;
                7'd116: gmb = 14'd3180;
                7'd117: gmb = 14'd3467;
                7'd118: gmb = 14'd4668;
                7'd119: gmb = 14'd2446;
                7'd120: gmb = 14'd7613;
                7'd121: gmb = 14'd9386;
                7'd122: gmb = 14'd834;
                7'd123: gmb = 14'd7703;
                7'd124: gmb = 14'd6836;
                7'd125: gmb = 14'd3403;
                7'd126: gmb = 14'd5351;
                7'd127: gmb = 14'd12276;
                default: gmb = 14'd0;
            endcase
        end
    endfunction
    // ---- END_GMB_ROM

    // position (in the 128 sample frame) of the sample presented at the NEXT tick
    wire [7:0] q_nxt = g[7:0] + 8'd1 - DOFF[7:0];
    wire       phi_n = q_nxt[7-S];
    wire [6:0] blk_n = q_nxt[6:0] >> (8 - S);
    wire [13:0] w_n  = phi_n ? gmb((7'd1 << (S-1)) + blk_n) : MONT_ONE;

    reg [13:0] w_r;
    reg        phi_r, phi_b;
    always @(posedge clk) begin
        if (adv) begin
            w_r   <= w_n;
            phi_r <= phi_n;
            phi_b <= phi_r;
        end
    end

    // ---- level 1 : product and Montgomery factor ----
    wire [27:0] prod = x_in * w_r;
    wire [15:0] y    = {(4'd3 * prod[3:0]), 12'd0} - prod[15:0];
    reg  [11:0] p_xh;
    reg  [15:0] p_y;
    reg         p_nz;
    always @(posedge clk) begin
        if (adv) begin
            p_xh <= prod[27:16];
            p_y  <= y;
            p_nz <= |prod[15:0];
        end
    end

    // ---- level 2 : reduction + butterfly ----
    wire [17:0] t3 = {2'd0, p_y} + {1'd0, p_y, 1'd0} + {14'd0, p_y[15:12]};
    wire [13:0] z  = {2'd0, p_xh} + t3[17:4] + {13'd0, p_nz};      // 0 <= z < 1.19 Q

    wire [13:0] head;
    wire [15:0] s  = {2'd0, head} + {2'd0, z};
    wire [15:0] s1 = s - {2'd0, Q};
    wire [15:0] s2 = s - {1'd0, Q, 1'd0};
    wire [13:0] sum = (!s2[15]) ? s2[13:0] : (!s1[15]) ? s1[13:0] : s[13:0];
    wire [15:0] d  = {2'd0, head} - {2'd0, z};
    wire [15:0] d1 = d + {2'd0, Q};
    wire [15:0] d2 = d + {1'd0, Q, 1'd0};
    wire [13:0] dif = (!d[15]) ? d[13:0] : (!d1[15]) ? d1[13:0] : d2[13:0];

    // phase 0 : the (normalised) unmultiplied sample goes into the delay line, the stored
    //           difference leaves; phase 1 : butterfly
    wire [13:0] zn   = (z >= Q) ? z - Q : z;
    wire [13:0] sr_in = phi_b ? dif : zn;
    wire [13:0] y_nxt = phi_b ? sum : head;

    generate
        if (HT == 1) begin : g_sr1
            reg [13:0] r;
            assign head = r;
            always @(posedge clk) if (adv) r <= sr_in;
        end else begin : g_srn
            reg [13:0] r [0:HT-1];
            integer k;
            assign head = r[HT-1];
            always @(posedge clk) begin
                if (adv) begin
                    for (k = HT-1; k > 0; k = k - 1) r[k] <= r[k-1];
                    r[0] <= sr_in;
                end
            end
        end
        if (OREG) begin : g_oreg
            reg [13:0] yr;
            always @(posedge clk) if (adv) yr <= y_nxt;
            assign y_out = yr;
        end else begin : g_ocomb
            assign y_out = y_nxt;
        end
    endgenerate
endmodule

// ------------------------------------------------------------------ CLK_3
module CLK_3_MODULE (
    input         clk,
    input         rst_n,
    input         rempty,
    input  [15:0] rdata,
    output        rinc,
    output        out_valid,
    output [15:0] out_data
);
    reg v1;
    assign rinc = ~rempty;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) v1 <= 1'b0;
        else        v1 <= rinc;
    end
    assign out_valid = v1;
    assign out_data  = v1 ? rdata : 16'd0;
endmodule
