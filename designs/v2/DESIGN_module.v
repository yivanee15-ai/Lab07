// V2 : latency oriented design.
//  CLK_1 : 16-word shift-register buffer, handshake transfers start as soon as word 0 arrives.
//  CLK_2 : 7-stage radix-2 SDF (single-path delay feedback) NTT pipeline.  All stages are
//          clocked by one global "advance" enable; the stream position of every stage is a
//          pure function of a global tick counter g, so no per-stage valid bits are needed.
//          Stage 1 needs no multiplier (input coefficients are 4 bit -> 16 entry LUT) and keeps
//          the raw 4+4 bit pairs; stages 2..7 contain a 2-cycle Montgomery multiplier.
//          The first output leaves the pipeline a few ticks after the last input sample.
//  CLK_3 : pop the FIFO and align out_valid / out_data.

// ------------------------------------------------------------------ CLK_1
module CLK_1_MODULE (
    input         clk,
    input         rst_n,
    input         in_valid,
    input  [31:0] in_data,
    input         out_idle,                 // sidle of the handshake
    output        out_valid,                // sready
    output [31:0] out_data,                 // din
    input         flag_handshake_to_clk1,   // synchronised acknowledge (sdone)
    output        flag_clk1_to_handshake
);
    wire        sidle = out_idle;
    wire        sdone = flag_handshake_to_clk1;
    wire        sready;
    wire [31:0] din;
    assign out_valid = sready;
    assign out_data  = din;
    assign flag_clk1_to_handshake = 1'b0;
    reg [31:0] sr [0:15];      // sr[15] = newest word
    reg [4:0]  n;              // words received
    reg [4:0]  sc;             // words handed to the handshake
    integer i;

    always @(posedge clk) begin
        if (in_valid) begin
            for (i = 0; i < 15; i = i + 1) sr[i] <= sr[i+1];
            sr[15] <= in_data;
        end
    end

    // The word is popped when the acknowledge (sdone) is seen rising, so din stays stable from the moment the
    // request is raised until the acknowledge has arrived (Jasper data-stability check on din).
    reg  sdone_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sdone_q <= 1'b0;
        else        sdone_q <= sdone;
    end
    wire pending = (sc < n);
    wire accept  = sdone & ~sdone_q;

    // position of word "sc" inside the shift register: 16 - n + sc  (mod 16)
    wire [3:0] idx = sc[3:0] - n[3:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n  <= 5'd0;
            sc <= 5'd0;
        end else if (sc == 5'd16) begin
            n  <= 5'd0;
            sc <= 5'd0;
        end else begin
            if (in_valid) n <= n + 5'd1;
            if (accept)   sc <= sc + 5'd1;
        end
    end

    assign sready = pending;
    wire [31:0] din_nxt;
    assign din_nxt = sr[idx];
    // din is the next word while the handshake is idle and a registered copy of it as soon as a transfer is
    // running, so din cannot change between the request and the end of the 4-phase handshake whatever the
    // input does (Jasper data-stability check).  No extra latency: the first idle cycle already shows the new word.
    reg  [31:0] dr;
    always @(posedge clk) dr <= din;
    assign din = sidle ? din_nxt : dr;

endmodule

// ------------------------------------------------------------------ CLK_2
module CLK_2_MODULE (
    input         clk,
    input         rst_n,
    input         in_valid,                 // dvalid
    input  [31:0] in_data,                  // dout
    input         fifo_full,                // wfull
    output        out_valid,                // winc
    output [15:0] out_data,                 // wdata
    output        busy,                     // dbusy
    input         flag_handshake_to_clk2,
    output        flag_clk2_to_handshake,
    input         flag_fifo_to_clk2,
    output        flag_clk2_to_fifo
);
    wire        dvalid = in_valid;
    wire [31:0] dout   = in_data;
    wire        wfull  = fifo_full;
    wire        winc;
    wire [15:0] wdata;
    wire        dbusy;
    assign out_valid = winc;
    assign out_data  = wdata;
    assign busy      = dbusy;
    assign flag_clk2_to_handshake = 1'b0;
    assign flag_clk2_to_fifo      = 1'b0;
    // stage latencies in ticks (stage 1: 1 register, stages 2..7: 2 multiplier regs + 1 output reg)
    localparam D2 = 64 + 1;
    localparam D3 = D2 + 32 + 3;
    localparam D4 = D3 + 16 + 3;
    localparam D5 = D4 + 8  + 3;
    localparam D6 = D5 + 4  + 3;
    localparam D7 = D6 + 2  + 3;
    localparam D8 = D7 + 1  + 3;      // first output position leaves stage 7 here
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
    wire [13:0] y1, y2, y3, y4, y5, y6, y7;

    SDF_STAGE1 u_s1 (.clk(clk), .adv(adv), .g(g), .x_in(xin), .y_out(y1));
    SDF_STAGE #(.S(2), .DOFF(D2)) u_s2 (.clk(clk), .adv(adv), .g(g), .x_in(y1), .y_out(y2));
    SDF_STAGE #(.S(3), .DOFF(D3)) u_s3 (.clk(clk), .adv(adv), .g(g), .x_in(y2), .y_out(y3));
    SDF_STAGE #(.S(4), .DOFF(D4)) u_s4 (.clk(clk), .adv(adv), .g(g), .x_in(y3), .y_out(y4));
    SDF_STAGE #(.S(5), .DOFF(D5)) u_s5 (.clk(clk), .adv(adv), .g(g), .x_in(y4), .y_out(y5));
    SDF_STAGE #(.S(6), .DOFF(D6)) u_s6 (.clk(clk), .adv(adv), .g(g), .x_in(y5), .y_out(y6));
    SDF_STAGE #(.S(7), .DOFF(D7)) u_s7 (.clk(clk), .adv(adv), .g(g), .x_in(y6), .y_out(y7));

    assign wdata = {2'b00, y7};
endmodule

// ------------------------------------------------------------------ stage 1
// Input samples are 4 bit.  The delay line stores {x[j+64], x[j]} (8 bit); both the sum and
// the difference are re-computed from it, so no 14 bit values are buffered here.
module SDF_STAGE1 (
    input         clk,
    input         adv,
    input  [8:0]  g,
    input  [3:0]  x_in,
    output reg [13:0] y_out
);
    localparam Q = 14'd12289;

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

    function [13:0] mont;       // Montgomery product, normalised
        input [13:0] a;
        input [13:0] b;
        reg [27:0] x;
        reg [15:0] y;
        reg [30:0] t;
        reg [14:0] z;
        begin
            x = a * b;
            y = (x[15:0] * 16'd12287);
            t = x + y * 15'd12289;
            z = t[30:16];
            mont = (z >= Q) ? z - Q : z;
        end
    endfunction

    function [13:0] lut;        // v = mont(x, GMb[1]) for a 4 bit x
        input [3:0] x;
        begin
            lut = mont({10'd0, x}, gmb(7'd1));
        end
    endfunction

    reg [7:0] sr [0:63];
    integer i;
    wire [7:0] head = sr[63];
    wire       phi  = g[6];                 // 1 : second half of the 128 sample frame
    wire [3:0] xv   = phi ? x_in : head[7:4];
    wire [13:0] v   = lut(xv);
    wire [13:0] u   = {10'd0, head[3:0]};
    wire [14:0] s   = {1'b0, u} + {1'b0, v};
    wire [13:0] sum = (s >= {1'b0, Q}) ? s[13:0] - Q : s[13:0];
    wire [14:0] d   = {1'b0, u} - {1'b0, v};
    wire [13:0] dif = d[14] ? d[13:0] + Q : d[13:0];

    always @(posedge clk) begin
        if (adv) begin
            for (i = 63; i > 0; i = i - 1) sr[i] <= sr[i-1];
            sr[0]  <= phi ? {x_in, head[3:0]} : {4'd0, x_in};
            y_out  <= phi ? sum : dif;
        end
    end
endmodule

// ------------------------------------------------------------------ stages 2..7
module SDF_STAGE #(
    parameter S    = 2,
    parameter DOFF = 0            // tick at which input position 0 is presented
) (
    input         clk,
    input         adv,
    input  [8:0]  g,
    input  [13:0] x_in,
    output reg [13:0] y_out
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
    reg        phi_r, phi_m1, phi_m2;
    always @(posedge clk) begin
        if (adv) begin
            w_r    <= w_n;
            phi_r  <= phi_n;
            phi_m1 <= phi_r;
            phi_m2 <= phi_m1;
        end
    end

    // ---- Montgomery multiplier, 2 register levels ----
    reg [27:0] p1;
    reg [13:0] p2;
    wire [27:0] prod = x_in * w_r;

    wire [15:0] y   = {(4'd3 * p1[3:0]) , 12'd0} - p1[15:0];
    wire [29:0] yq  = {14'd0, y} + {2'd0, y, 12'd0} + {1'd0, y, 13'd0};
    wire [30:0] tt  = {3'd0, p1} + {1'd0, yq};
    wire [14:0] zz  = tt[30:16];
    wire [13:0] zn  = (zz >= {1'b0, Q}) ? zz[13:0] - Q : zz[13:0];

    // ---- butterfly with the delay line ----
    wire [13:0] head;
    wire [14:0] s   = {1'b0, head} + {1'b0, p2};
    wire [13:0] sum = (s >= {1'b0, Q}) ? s[13:0] - Q : s[13:0];
    wire [14:0] d   = {1'b0, head} - {1'b0, p2};
    wire [13:0] dif = d[14] ? d[13:0] + Q : d[13:0];
    wire [13:0] sr_in = phi_m2 ? dif : p2;

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
    endgenerate

    always @(posedge clk) begin
        if (adv) begin
            p1    <= prod;
            p2    <= zn;
            y_out <= phi_m2 ? sum : head;
        end
    end
endmodule

// ------------------------------------------------------------------ CLK_3
module CLK_3_MODULE (
    input         clk,
    input         rst_n,
    input         fifo_empty,               // rempty
    input  [15:0] fifo_rdata,               // rdata
    output        fifo_rinc,                // rinc
    output        out_valid,
    output [15:0] out_data,
    input         flag_fifo_to_clk3,
    output        flag_clk3_to_fifo
);
    wire        rempty = fifo_empty;
    wire [15:0] rdata  = fifo_rdata;
    wire        rinc;
    assign fifo_rinc = rinc;
    assign flag_clk3_to_fifo = 1'b0;
    reg v1, v2;
    assign rinc = ~rempty;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1 <= 1'b0;
            v2 <= 1'b0;
        end else begin
            v1 <= rinc;
            v2 <= v1;
        end
    end
    assign out_valid = v2;
    assign out_data  = v2 ? rdata : 16'd0;
endmodule
