`timescale 1ns/1ps
`ifndef NPAT
  `define NPAT 100
`endif
`ifndef CLK3_PERIOD
  `define CLK3_PERIOD 20.7
`endif
module PATTERN (
    input             clk1,
    input             clk3,
    output reg        rst_n,
    output reg        in_valid,
    output reg [31:0] in_data,
    input             out_valid,
    input      [15:0] out_data
);
    parameter NPAT = `NPAT;
    parameter MAX_CYCLES = 5000;     // clk3 cycles allowed for the latency

    reg [31:0] in_mem  [0:16*NPAT-1];
    reg [15:0] out_mem [0:128*NPAT-1];

    integer pat, i, cnt, err_total, k;
    integer lat_cycles;
    real t_fall, t_last_fall, lat_ns, lat_sum_ns, lat_max_ns, lat_min_ns;
    reg    fail;
    real   t_ov_fall;
    always @(negedge out_valid) t_ov_fall = $realtime;

    initial begin
        $readmemh("pattern_in.dat",  in_mem);
        $readmemh("pattern_out.dat", out_mem);
    end

    // ---- monitor: outputs must be zero when out_valid is low / in_valid is high ----
    always @(negedge clk3) begin
        if (rst_n === 1'b1) begin
            if (out_valid === 1'b0 && out_data !== 16'd0) begin
                $display("[FAIL] out_data not zero while out_valid low (t=%0t)", $time);
                fail = 1;
            end
            if (in_valid === 1'b1 && (out_valid !== 1'b0)) begin
                $display("[FAIL] out_valid high while in_valid high (t=%0t)", $time);
                fail = 1;
            end
        end
    end

    task fail_exit;
        begin
            $display("==== SIMULATION FAILED (clk3=%0.1fns) ====", `CLK3_PERIOD);
            $finish;
        end
    endtask

    initial begin
        fail = 0; err_total = 0;
        lat_sum_ns = 0; lat_max_ns = 0; lat_min_ns = 1e9;
        rst_n = 1'b1; in_valid = 1'b0; in_data = 32'bx;
        #3;
        rst_n = 1'b0;
        #50;
        if (out_valid !== 1'b0 || out_data !== 16'd0) begin
            $display("[FAIL] outputs not reset"); fail_exit;
        end
        rst_n = 1'b1;
        repeat (3) @(negedge clk1);

        for (pat = 0; pat < NPAT; pat = pat + 1) begin
            // ---- drive 16 input cycles ----
            @(negedge clk1);
            for (i = 0; i < 16; i = i + 1) begin
                in_valid = 1'b1;
                in_data  = in_mem[16*pat + i];
                @(negedge clk1);
            end
            in_valid = 1'b0;
            in_data  = 32'bx;
            t_fall   = $realtime;

            // ---- collect 128 outputs ----
            cnt = 0;
            lat_cycles = 0;
            while (cnt < 128) begin
                @(negedge clk3);
                lat_cycles = lat_cycles + 1;
                if (out_valid === 1'b1) begin
                    if (out_data !== out_mem[128*pat + cnt]) begin
                        if (err_total < 10)
                            $display("[ERR] pat %0d idx %0d got %h exp %h", pat, cnt, out_data, out_mem[128*pat+cnt]);
                        err_total = err_total + 1;
                        fail = 1;
                    end
                    cnt = cnt + 1;
                    t_last_fall = $realtime;
                end
                if (lat_cycles > MAX_CYCLES) begin
                    $display("[FAIL] timeout in pattern %0d (got %0d outputs)", pat, cnt);
                    fail_exit;
                end
            end
            // falling edge of out_valid for the last output = next clk3 negedge-based sample
            @(negedge clk3);
            if (out_valid !== 1'b0) begin
                $display("[FAIL] more than 128 outputs in pattern %0d", pat);
                fail = 1;
            end
            lat_ns = t_ov_fall - t_fall;
            lat_sum_ns = lat_sum_ns + lat_ns;
            if (lat_ns > lat_max_ns) lat_max_ns = lat_ns;
            if (lat_ns < lat_min_ns) lat_min_ns = lat_ns;
            if (fail) fail_exit;

            // next input 1..3 clk1 cycles after the 128th output
            k = 1 + ($urandom % 3);
            repeat (k) @(negedge clk1);
        end

        $display("==== ALL %0d PATTERNS PASSED (clk3=%0.1fns) ====", NPAT, `CLK3_PERIOD);
        $display("LATENCY_NS min=%0.1f avg=%0.1f max=%0.1f  (clk3 cycles avg=%0.1f)",
                 lat_min_ns, lat_sum_ns/NPAT, lat_max_ns, lat_sum_ns/NPAT/`CLK3_PERIOD);
        $finish;
    end
endmodule
