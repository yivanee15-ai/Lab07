// Asynchronous FIFO (gray pointers, 2-FF synchronizers) on top of the TA dual-port SRAM.
// Read data has a fixed latency of 2 rclk cycles after the pop (SRAM output + 1 sync flop).
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
    output reg         rempty
);
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
    wire         rempty_nxt = (rgray_nxt == wptr_s);

    always @(posedge rclk or negedge rst_n) begin
        if (!rst_n) begin
            rbin   <= 0;
            rptr   <= 0;
            rempty <= 1'b1;
        end else begin
            rbin   <= rbin_nxt;
            rptr   <= rgray_nxt;
            rempty <= rempty_nxt;
        end
    end

    // ---------------- SRAM ----------------
    wire [WIDTH-1:0] sram_q;
    wire [AW-1:0] waddr = wbin[AW-1:0];
    wire [AW-1:0] raddr = rbin[AW-1:0];

    DUAL_64X16X1BM1 u_dual_sram (
        .CKA(rclk), .CKB(wclk),
        .WEAN(1'b1), .WEBN(~wen),
        .CSA(1'b1), .CSB(1'b1),
        .OEA(1'b1), .OEB(1'b1),
        .A0(raddr[0]), .A1(raddr[1]), .A2(raddr[2]), .A3(raddr[3]), .A4(raddr[4]), .A5(raddr[5]),
        .B0(waddr[0]), .B1(waddr[1]), .B2(waddr[2]), .B3(waddr[3]), .B4(waddr[4]), .B5(waddr[5]),
        .DIA0(1'b0), .DIA1(1'b0), .DIA2(1'b0), .DIA3(1'b0), .DIA4(1'b0), .DIA5(1'b0), .DIA6(1'b0), .DIA7(1'b0),
        .DIA8(1'b0), .DIA9(1'b0), .DIA10(1'b0), .DIA11(1'b0), .DIA12(1'b0), .DIA13(1'b0), .DIA14(1'b0), .DIA15(1'b0),
        .DIB0(wdata[0]), .DIB1(wdata[1]), .DIB2(wdata[2]), .DIB3(wdata[3]),
        .DIB4(wdata[4]), .DIB5(wdata[5]), .DIB6(wdata[6]), .DIB7(wdata[7]),
        .DIB8(wdata[8]), .DIB9(wdata[9]), .DIB10(wdata[10]), .DIB11(wdata[11]),
        .DIB12(wdata[12]), .DIB13(wdata[13]), .DIB14(wdata[14]), .DIB15(wdata[15]),
        .DOA0(sram_q[0]), .DOA1(sram_q[1]), .DOA2(sram_q[2]), .DOA3(sram_q[3]),
        .DOA4(sram_q[4]), .DOA5(sram_q[5]), .DOA6(sram_q[6]), .DOA7(sram_q[7]),
        .DOA8(sram_q[8]), .DOA9(sram_q[9]), .DOA10(sram_q[10]), .DOA11(sram_q[11]),
        .DOA12(sram_q[12]), .DOA13(sram_q[13]), .DOA14(sram_q[14]), .DOA15(sram_q[15]),
        .DOB0(), .DOB1(), .DOB2(), .DOB3(), .DOB4(), .DOB5(), .DOB6(), .DOB7(),
        .DOB8(), .DOB9(), .DOB10(), .DOB11(), .DOB12(), .DOB13(), .DOB14(), .DOB15()
    );

    // extra flop stage so the SRAM data is re-timed in the rclk domain
    always @(posedge rclk or negedge rst_n) begin
        if (!rst_n) rdata <= {WIDTH{1'b0}};
        else        rdata <= sram_q;
    end
endmodule
