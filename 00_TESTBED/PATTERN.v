`ifdef RTL
	`define CYCLE_TIME_clk1 14.1
	`define CYCLE_TIME_clk2 10.1
	`ifdef CLK3_PERIOD
		`define CYCLE_TIME_clk3 `CLK3_PERIOD	// RTL demo: 3.1 / 4.1 / 11.1 / 20.7
	`else
		`define CYCLE_TIME_clk3 20.7
	`endif
`endif
`ifdef GATE
	`define CYCLE_TIME_clk1 14.1
	`define CYCLE_TIME_clk2 10.1
	`define CYCLE_TIME_clk3 20.7
`endif
`ifndef NPAT
	`define NPAT 100
`endif

module PATTERN(
	clk1,
	clk2,
	clk3,
	rst_n,
	in_valid,
	in_data,
	out_valid,
	out_data
);

//---------------------------------------------------------------------
//   PORT DECLARATION          
//---------------------------------------------------------------------
output reg        clk1, clk2, clk3;
output reg        rst_n;
output reg        in_valid;
output reg [31:0] in_data;

input             out_valid;
input      [15:0] out_data;


//---------------------------------------------------------------------
//   PARAMETER & INTEGER
//---------------------------------------------------------------------
real	CYCLE_clk1 = `CYCLE_TIME_clk1;
real	CYCLE_clk2 = `CYCLE_TIME_clk2;
real	CYCLE_clk3 = `CYCLE_TIME_clk3;
integer total_latency;

parameter NPAT       = `NPAT;
parameter MAX_CYCLES = 5000;        // latency limit in clk3 cycles

integer pat, i, cnt, k, seed, err_total, lat_cycles;
real    lat_ns, lat_sum_ns, lat_max_ns;
real    ph1, ph2, ph3;

//---------------------------------------------------------------------
//   REG & WIRE
//---------------------------------------------------------------------
reg [31:0] in_mem  [0:16*NPAT-1];
reg [15:0] out_mem [0:128*NPAT-1];
real       t_in_fall, t_out_fall;
reg        fail_flag;

//---------------------------------------------------------------------
//  CLOCK   (optional random initial phases: +seed=<n>)
//---------------------------------------------------------------------
initial begin
	clk1 = 0; clk2 = 0; clk3 = 0;
	ph1 = 0; ph2 = 0; ph3 = 0;
	if ($value$plusargs("seed=%d", seed)) begin
		ph1 = ($urandom(seed) % 1000) / 1000.0 * CYCLE_clk1;
		ph2 = ($urandom % 1000) / 1000.0 * CYCLE_clk2;
		ph3 = ($urandom % 1000) / 1000.0 * CYCLE_clk3;
	end
	fork
		begin #ph1; forever #(CYCLE_clk1/2.0) clk1 = ~clk1; end
		begin #ph2; forever #(CYCLE_clk2/2.0) clk2 = ~clk2; end
		begin #ph3; forever #(CYCLE_clk3/2.0) clk3 = ~clk3; end
	join
end

always @(negedge out_valid) t_out_fall = $realtime;

//---------------------------------------------------------------------
//  INITIAL
//---------------------------------------------------------------------
initial begin
	$readmemh("pattern_in.dat",  in_mem);
	$readmemh("pattern_out.dat", out_mem);
	fail_flag = 0; err_total = 0; total_latency = 0;
	lat_sum_ns = 0; lat_max_ns = 0;
	rst_n = 1'b1; in_valid = 1'b0; in_data = 32'bx;

	reset_task;

	for (pat = 0; pat < NPAT; pat = pat + 1) begin
		input_task;
		wait_out_task;
		// next input 1..3 clk1 cycles after the 128th output
		k = 1 + ($urandom % 3);
		repeat (k) @(negedge clk1);
	end
	YOU_PASS_task;
end

// out_data must be zero while out_valid is low, out_valid must be low while in_valid is high
always @(negedge clk3) begin
	if (rst_n === 1'b1) begin
		if (out_valid === 1'b0 && out_data !== 16'd0) begin
			$display("[FAIL] out_data is not zero while out_valid is low (t=%0t)", $time);
			FAIL_task;
		end
		if (in_valid === 1'b1 && out_valid !== 1'b0) begin
			$display("[FAIL] out_valid is high while in_valid is high (t=%0t)", $time);
			FAIL_task;
		end
	end
end

//---------------------------------------------------------------------
//  TASK
//---------------------------------------------------------------------
task reset_task; begin
	#3;
	rst_n = 1'b0;
	#50;
	if (out_valid !== 1'b0 || out_data !== 16'd0) begin
		$display("[FAIL] outputs are not reset");
		FAIL_task;
	end
	rst_n = 1'b1;
	repeat (3) @(negedge clk1);
end endtask

task input_task; begin
	@(negedge clk1);
	for (i = 0; i < 16; i = i + 1) begin
		in_valid = 1'b1;
		in_data  = in_mem[16*pat + i];
		@(negedge clk1);
	end
	in_valid  = 1'b0;
	in_data   = 32'bx;
	t_in_fall = $realtime;
end endtask

task wait_out_task; begin
	cnt = 0;
	lat_cycles = 0;
	while (cnt < 128) begin
		@(negedge clk3);
		lat_cycles = lat_cycles + 1;
		if (out_valid === 1'b1) begin
			if (out_data !== out_mem[128*pat + cnt]) begin
				if (err_total < 10)
					$display("[ERR] pat %0d idx %0d got %h exp %h", pat, cnt, out_data, out_mem[128*pat + cnt]);
				err_total = err_total + 1;
				FAIL_task;
			end
			cnt = cnt + 1;
		end
		if (lat_cycles > MAX_CYCLES) begin
			$display("[FAIL] latency exceeds %0d clk3 cycles in pattern %0d (got %0d outputs)", MAX_CYCLES, pat, cnt);
			FAIL_task;
		end
	end
	@(negedge clk3);
	if (out_valid !== 1'b0) begin
		$display("[FAIL] more than 128 outputs in pattern %0d", pat);
		FAIL_task;
	end
	// latency: falling edge of in_valid -> falling edge of the last out_valid, in clk3 cycles
	lat_ns = t_out_fall - t_in_fall;
	lat_sum_ns = lat_sum_ns + lat_ns;
	if (lat_ns > lat_max_ns) lat_max_ns = lat_ns;
	total_latency = $rtoi(lat_max_ns / CYCLE_clk3 + 0.999);
end endtask

task FAIL_task; begin
	$display("*************************************************************************");
	$display("*                         Wrong Answer                                  *");
	$display("*                (clk3 period = %.1f ns, pattern %0d)                *", CYCLE_clk3, pat);
	$display("*************************************************************************");
	$finish;
end endtask

task YOU_PASS_task; begin
    $display("*************************************************************************");
    $display("*                         Congratulations!                              *");
    $display("*                Your execution cycles = %5d cycles          *", total_latency);
    $display("*                Your clock period = %.1f ns          *", CYCLE_clk3);
    $display("*                Total Latency = %.1f ns          *", total_latency*CYCLE_clk3);
    $display("*************************************************************************");
    $display("LATENCY_NS avg=%0.1f max=%0.1f (clk3 cycles avg=%0.1f)", lat_sum_ns/NPAT, lat_max_ns, lat_sum_ns/NPAT/CYCLE_clk3);
    $finish;
end endtask


endmodule
