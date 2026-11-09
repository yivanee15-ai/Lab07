// Behavioural stand-in for the Faraday DUAL_64X16X1BM1 (64 x 16, dual port).  Mimics the behaviour of the real
// model that matters for this lab:  synchronous read/write on the rising clock edge, WEAN/WEBN active low,
// CSA/CSB/OEA/OEB active high, output goes unknown for TOH (0.74 ns) after the clock when the address changes,
// and a read of an address written by the other port less than Tw2r (1.62 ns) earlier returns X with the
// "MEM_Warning" message.  Replace by the TA file for the real flow.
`timescale 1ns/1ps
module DUAL_64X16X1BM1 (
    input  A0,
    input  A1,
    input  A2,
    input  A3,
    input  A4,
    input  A5,
    output DOA0,
    output DOA1,
    output DOA2,
    output DOA3,
    output DOA4,
    output DOA5,
    output DOA6,
    output DOA7,
    output DOA8,
    output DOA9,
    output DOA10,
    output DOA11,
    output DOA12,
    output DOA13,
    output DOA14,
    output DOA15,
    input  DIA0,
    input  DIA1,
    input  DIA2,
    input  DIA3,
    input  DIA4,
    input  DIA5,
    input  DIA6,
    input  DIA7,
    input  DIA8,
    input  DIA9,
    input  DIA10,
    input  DIA11,
    input  DIA12,
    input  DIA13,
    input  DIA14,
    input  DIA15,
    input  B0,
    input  B1,
    input  B2,
    input  B3,
    input  B4,
    input  B5,
    output DOB0,
    output DOB1,
    output DOB2,
    output DOB3,
    output DOB4,
    output DOB5,
    output DOB6,
    output DOB7,
    output DOB8,
    output DOB9,
    output DOB10,
    output DOB11,
    output DOB12,
    output DOB13,
    output DOB14,
    output DOB15,
    input  DIB0,
    input  DIB1,
    input  DIB2,
    input  DIB3,
    input  DIB4,
    input  DIB5,
    input  DIB6,
    input  DIB7,
    input  DIB8,
    input  DIB9,
    input  DIB10,
    input  DIB11,
    input  DIB12,
    input  DIB13,
    input  DIB14,
    input  DIB15,
    input  WEAN,
    input  WEBN,
    input  CKA,
    input  CKB,
    input  CSA,
    input  CSB,
    input  OEA,
    input  OEB
);
    parameter TOH = 0.74, TW2R = 1.62;
    reg [15:0] mem [0:63];
    reg [15:0] qa, qb;
    reg [5:0]  last_a_addr, last_b_addr;
    reg        last_a_we, last_b_we;
    real       t_a, t_b;
    wire [5:0] addra = {A5,A4,A3,A2,A1,A0};
    wire [5:0] addrb = {B5,B4,B3,B2,B1,B0};
    wire [15:0] dia = {DIA15,DIA14,DIA13,DIA12,DIA11,DIA10,DIA9,DIA8,DIA7,DIA6,DIA5,DIA4,DIA3,DIA2,DIA1,DIA0};
    wire [15:0] dib = {DIB15,DIB14,DIB13,DIB12,DIB11,DIB10,DIB9,DIB8,DIB7,DIB6,DIB5,DIB4,DIB3,DIB2,DIB1,DIB0};
    initial begin t_a = -100.0; t_b = -100.0; last_a_we = 0; last_b_we = 0; end

    always @(posedge CKA) begin
        if (CSA) begin
            if (!WEAN) mem[addra] = dia;
            qa <= mem[addra];
            last_a_addr = addra; last_a_we = !WEAN; t_a = $realtime;
        end
    end
    reg [15:0] nb;
    always @(posedge CKB) begin
        if (CSB) begin
            if (!WEBN) mem[addrb] = dib;
            if (addrb === last_a_addr && last_a_we && ($realtime - t_a) < TW2R) begin
                $display("** MEM_Warning: Read and Write the same Address, DO is unknown (%0t) in clock of %m", $time);
                nb = 16'bx;
            end else
                nb = mem[addrb];
            qb <= 16'bx;
            qb <= #(TOH) nb;
            last_b_addr = addrb; last_b_we = !WEBN; t_b = $realtime;
        end
    end
    assign DOA0 = OEA ? qa[0] : 1'bz;
    assign DOA1 = OEA ? qa[1] : 1'bz;
    assign DOA2 = OEA ? qa[2] : 1'bz;
    assign DOA3 = OEA ? qa[3] : 1'bz;
    assign DOA4 = OEA ? qa[4] : 1'bz;
    assign DOA5 = OEA ? qa[5] : 1'bz;
    assign DOA6 = OEA ? qa[6] : 1'bz;
    assign DOA7 = OEA ? qa[7] : 1'bz;
    assign DOA8 = OEA ? qa[8] : 1'bz;
    assign DOA9 = OEA ? qa[9] : 1'bz;
    assign DOA10 = OEA ? qa[10] : 1'bz;
    assign DOA11 = OEA ? qa[11] : 1'bz;
    assign DOA12 = OEA ? qa[12] : 1'bz;
    assign DOA13 = OEA ? qa[13] : 1'bz;
    assign DOA14 = OEA ? qa[14] : 1'bz;
    assign DOA15 = OEA ? qa[15] : 1'bz;
    assign DOB0 = OEB ? qb[0] : 1'bz;
    assign DOB1 = OEB ? qb[1] : 1'bz;
    assign DOB2 = OEB ? qb[2] : 1'bz;
    assign DOB3 = OEB ? qb[3] : 1'bz;
    assign DOB4 = OEB ? qb[4] : 1'bz;
    assign DOB5 = OEB ? qb[5] : 1'bz;
    assign DOB6 = OEB ? qb[6] : 1'bz;
    assign DOB7 = OEB ? qb[7] : 1'bz;
    assign DOB8 = OEB ? qb[8] : 1'bz;
    assign DOB9 = OEB ? qb[9] : 1'bz;
    assign DOB10 = OEB ? qb[10] : 1'bz;
    assign DOB11 = OEB ? qb[11] : 1'bz;
    assign DOB12 = OEB ? qb[12] : 1'bz;
    assign DOB13 = OEB ? qb[13] : 1'bz;
    assign DOB14 = OEB ? qb[14] : 1'bz;
    assign DOB15 = OEB ? qb[15] : 1'bz;
endmodule
