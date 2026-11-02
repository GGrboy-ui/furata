`timescale 1ns/1ps
module tb_velocity_feedback;
 reg clk=0,rst_n=0,tick=0,edge_valid=0,negative=0;always #5 clk=~clk;
 integer ms_clock=0;wire signed [31:0] velocity;
 velocity_feedback #(.CLK_HZ(100000)) dut(.clk(clk),.rst_n(rst_n),.tick_ms(tick),
  .edge_valid(edge_valid),.edge_negative(negative),.velocity_q(velocity));
 always @(negedge clk) begin
  if(ms_clock==99)begin ms_clock=0;tick=1;end else begin ms_clock=ms_clock+1;tick=0;end
 end
 task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
 task edge_at;input integer interval;input integer reverse;begin
  clocks(interval-1);negative=reverse;edge_valid=1;clocks(1);edge_valid=0;
 end endtask
 integer saved;
 initial begin
  $dumpfile("tb_velocity_feedback.vcd");$dumpvars(1,tb_velocity_feedback);
  clocks(5);rst_n=1;
  edge_at(2500,0);clocks(100);if(velocity!=0)$fatal(1,"FAIL: first edge invented a period");
  edge_at(2400,0);repeat(20)edge_at(2500,0);
  if(velocity<2550000||velocity>2670000)$fatal(1,"FAIL: period scale/40ms filter %0d",velocity);
  saved=velocity;clocks(15000);
  if(velocity<=0||velocity>=saved/2)$fatal(1,"FAIL: no-edge age decay %0d vs %0d",velocity,saved);
  edge_at(1,1);clocks(5);if(velocity<=0)$fatal(1,"FAIL: reversal erased filter history");
  repeat(20)edge_at(5000,1);
  if(velocity> -1250000||velocity< -1350000)$fatal(1,"FAIL: low-speed reverse measurement %0d",velocity);
  clocks(100200);if(velocity!=0)$fatal(1,"FAIL: timeout did not force exact zero");
  // Divider completion from the previous direction cannot republish after reversal.
  edge_at(1,0);edge_at(500,0);wait(dut.start);edge_at(2,1);
  wait(dut.fresh_batch);clocks(2);
  if(dut.job_valid && !dut.pending_negative)$fatal(1,"FAIL: old positive job remained valid after reverse batch");
  clocks(200);if(dut.raw_q>0)$fatal(1,"FAIL: stale positive divider result survived reversal");
  rst_n=0;clocks(2);if(velocity!=0)$fatal(1,"FAIL: reset");
  $display("TEST PASSED: tb_velocity_feedback (first edge, units, low speed, decay, continuous reversal, stale cancellation, timeout)");$finish;
 end
 initial begin #10000000;$fatal(1,"FAIL: estimator timeout");end
endmodule
