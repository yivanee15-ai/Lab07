// SRAM: port A = write (CKA = wclk), port B = read (CKB = rclk, DOB).
// Asynchronous FIFO (gray pointers, 2-FF synchronizers) on top of the TA dual-port SRAM.
// Read data appears 1 rclk cycle after the pop: the SRAM is addressed with the NEXT head pointer, the
// SRAM output is re-timed by one extra flop, and the empty flag is combinational (no extra latency).
module FIFO_syn #(parameter WIDTH = 16, parameter WORDS = 64) (
    input              wclk,
    input              rclk,
    input              rst_n,
    // write side (wclk)
    input              winc,
    input  [WIDTH-1:0] wdata,
    output reg         wfull,
    // read side (rclk)
    input              rinc,
    output reg [WIDTH-1:0] rdata,
    output             rempty,
    output             flag_fifo_to_clk2,
    input              flag_clk2_to_fifo,
    output             flag_fifo_to_clk3,
    input              flag_clk3_to_fifo
);
    assign flag_fifo_to_clk2 = 1'b0;
    assign flag_fifo_to_clk3 = 1'b0;
    localparam AW = 6;   // log2(WORDS)

    reg  [AW:0] wbin, rbin;
    reg  [AW:0] wptr, rptr;      // gray coded
    wire [AW:0] wptr_s, rptr_s;  // synchronized to the other domain

    NDFF_BUS_syn #(AW+1) u_w2r (.D(wptr), .clk(rclk), .rst_n(rst_n), .Q(wptr_s));
    NDFF_BUS_syn #(AW+1) u_r2w (.D(rptr), .clk(wclk), .rst_n(rst_n), .Q(rptr_s));

    // ---------------- write side ----------------
    wire         wen       = winc & ~wfull;
    wire [AW:0]  wbin_nxt  = wbin + {{AW{1'b0}}, wen};
    wire [AW:0]  wgray_nxt = (wbin_nxt >> 1) ^ wbin_nxt;
    wire         wfull_nxt = (wgray_nxt == {~rptr_s[AW:AW-1], rptr_s[AW-2:0]});

    always @(posedge wclk or negedge rst_n) begin
        if (!rst_n) begin
            wbin  <= 0;
            wptr  <= 0;
            wfull <= 1'b0;
        end else begin
            wbin  <= wbin_nxt;
            wptr  <= wgray_nxt;
            wfull <= wfull_nxt;
        end
    end

    // ---------------- read side ----------------
    wire         ren       = rinc & ~rempty;
    wire [AW:0]  rbin_nxt  = rbin + {{AW{1'b0}}, ren};
    wire [AW:0]  rgray_nxt = (rbin_nxt >> 1) ^ rbin_nxt;
    assign       rempty    = (rptr == wptr_s);

    always @(posedge rclk or negedge rst_n) begin
        if (!rst_n) begin
            rbin   <= 0;
            rptr   <= 0;
        end else begin
            rbin   <= rbin_nxt;
            rptr   <= rgray_nxt;
        end
    end

    // ---------------- SRAM ----------------
    wire [WIDTH-1:0] sram_q;
    wire [AW-1:0] waddr = wbin[AW-1:0];
    wire [AW-1:0] raddr = rbin_nxt[AW-1:0];   // next head

    DUAL_64X16X1BM1 u_dual_sram (
        .CKA(wclk), .CKB(rclk),
        .WEAN(~wen), .WEBN(1'b1),
        .CSA(1'b1), .CSB(1'b1),
        .OEA(1'b1), .OEB(1'b1),
        .A0(waddr[0]), .A1(waddr[1]), .A2(waddr[2]), .A3(waddr[3]), .A4(waddr[4]), .A5(waddr[5]),
        .B0(raddr[0]), .B1(raddr[1]), .B2(raddr[2]), .B3(raddr[3]), .B4(raddr[4]), .B5(raddr[5]),
        .DIA0(wdata[0]), .DIA1(wdata[1]), .DIA2(wdata[2]), .DIA3(wdata[3]),
        .DIA4(wdata[4]), .DIA5(wdata[5]), .DIA6(wdata[6]), .DIA7(wdata[7]),
        .DIA8(wdata[8]), .DIA9(wdata[9]), .DIA10(wdata[10]), .DIA11(wdata[11]),
        .DIA12(wdata[12]), .DIA13(wdata[13]), .DIA14(wdata[14]), .DIA15(wdata[15]),
        .DIB0(1'b0), .DIB1(1'b0), .DIB2(1'b0), .DIB3(1'b0), .DIB4(1'b0), .DIB5(1'b0), .DIB6(1'b0), .DIB7(1'b0),
        .DIB8(1'b0), .DIB9(1'b0), .DIB10(1'b0), .DIB11(1'b0), .DIB12(1'b0), .DIB13(1'b0), .DIB14(1'b0), .DIB15(1'b0),
        .DOA0(), .DOA1(), .DOA2(), .DOA3(), .DOA4(), .DOA5(), .DOA6(), .DOA7(),
        .DOA8(), .DOA9(), .DOA10(), .DOA11(), .DOA12(), .DOA13(), .DOA14(), .DOA15(),
        .DOB0(sram_q[0]), .DOB1(sram_q[1]), .DOB2(sram_q[2]), .DOB3(sram_q[3]),
        .DOB4(sram_q[4]), .DOB5(sram_q[5]), .DOB6(sram_q[6]), .DOB7(sram_q[7]),
        .DOB8(sram_q[8]), .DOB9(sram_q[9]), .DOB10(sram_q[10]), .DOB11(sram_q[11]),
        .DOB12(sram_q[12]), .DOB13(sram_q[13]), .DOB14(sram_q[14]), .DOB15(sram_q[15])
    );

    // extra flop stage so the SRAM data is re-timed in the rclk domain
    always @(posedge rclk or negedge rst_n) begin
        if (!rst_n) rdata <= {WIDTH{1'b0}};
        else        rdata <= sram_q;
    end
endmodule
