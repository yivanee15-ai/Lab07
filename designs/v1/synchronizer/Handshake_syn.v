// 4-phase handshake synchronizer, clk1 (sclk) -> clk2 (dclk).
// Source side keeps din stable from sreq rising until sack rising (CLK_1_MODULE obeys this).
module Handshake_syn #(parameter WIDTH = 32) (
    input              sclk,
    input              dclk,
    input              rst_n,
    // source side (sclk)
    input              sready,
    input  [WIDTH-1:0] din,
    output             sidle,
    output             flag_handshake_to_clk1,   // carries the synchronised acknowledge (sack)
    input              flag_clk1_to_handshake,
    output             flag_handshake_to_clk2,
    input              flag_clk2_to_handshake,
    // destination side (dclk)
    input              dbusy,
    output reg         dvalid,
    output reg [WIDTH-1:0] dout
);
    wire sdone;
    assign flag_handshake_to_clk1 = sdone;
    assign flag_handshake_to_clk2 = 1'b0;
    reg  sreq;
    wire dreq;
    reg  dack;
    wire sack;

    NDFF_syn u_req_sync (.D(sreq), .clk(dclk), .rst_n(rst_n), .Q(dreq));
    NDFF_syn u_ack_sync (.D(dack), .clk(sclk), .rst_n(rst_n), .Q(sack));

    assign sidle = ~sreq & ~sack;
    assign sdone = sack;

    // source control
    always @(posedge sclk or negedge rst_n) begin
        if (!rst_n)                sreq <= 1'b0;
        else if (sack)             sreq <= 1'b0;
        else if (sidle & sready)   sreq <= 1'b1;
    end

    // destination control
    always @(posedge dclk or negedge rst_n) begin
        if (!rst_n) begin
            dack   <= 1'b0;
            dvalid <= 1'b0;
            dout   <= {WIDTH{1'b0}};
        end else begin
            dvalid <= 1'b0;
            if (dreq & ~dack & ~dbusy) begin
                dack   <= 1'b1;
                dvalid <= 1'b1;
                dout   <= din;
            end else if (~dreq) begin
                dack <= 1'b0;
            end
        end
    end
endmodule
