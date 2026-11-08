// Top level (assumed interface -- replace by the TA NTT_TOP when integrating).
module NTT_TOP (
    input         clk1,
    input         clk2,
    input         clk3,
    input         rst_n,
    input         in_valid,
    input  [31:0] in_data,
    output        out_valid,
    output [15:0] out_data
);
    wire        hs_sready, hs_sidle, hs_sdone, hs_dbusy, hs_dvalid;
    wire [31:0] hs_din, hs_dout;
    wire        f_winc, f_wfull, f_rinc, f_rempty;
    wire [15:0] f_wdata, f_rdata;

    CLK_1_MODULE u_clk1 (
        .clk(clk1), .rst_n(rst_n), .in_valid(in_valid), .in_data(in_data),
        .sidle(hs_sidle), .sdone(hs_sdone), .sready(hs_sready), .din(hs_din)
    );

    Handshake_syn #(.WIDTH(32)) u_Handshake_syn (
        .sclk(clk1), .dclk(clk2), .rst_n(rst_n),
        .sready(hs_sready), .din(hs_din), .sidle(hs_sidle), .sdone(hs_sdone),
        .dbusy(hs_dbusy), .dvalid(hs_dvalid), .dout(hs_dout)
    );

    CLK_2_MODULE u_clk2 (
        .clk(clk2), .rst_n(rst_n),
        .dvalid(hs_dvalid), .dout(hs_dout), .dbusy(hs_dbusy),
        .wfull(f_wfull), .winc(f_winc), .wdata(f_wdata)
    );

    FIFO_syn #(.WIDTH(16), .WORDS(64)) u_FIFO_syn (
        .wclk(clk2), .rclk(clk3), .rst_n(rst_n),
        .winc(f_winc), .wdata(f_wdata), .wfull(f_wfull),
        .rinc(f_rinc), .rdata(f_rdata), .rempty(f_rempty)
    );

    CLK_3_MODULE u_clk3 (
        .clk(clk3), .rst_n(rst_n),
        .rempty(f_rempty), .rdata(f_rdata), .rinc(f_rinc),
        .out_valid(out_valid), .out_data(out_data)
    );
endmodule
