`timescale 1ns/1ps
// Deliberately slow test clock relative to the 1ms tick: several measurements
// can arrive while the sequential divider is still busy.
module tb_velocity_reversal_jobs;
 reg clk=0,rst_n=0,tick=0,edge_valid=0,negative=0;always #5 clk=~clk;
 integer timer=0;wire signed [31:0] velocity;
 velocity_feedback #(.CLK_HZ(10000)) dut(.clk(clk),.rst_n(rst_n),.tick_ms(tick),.edge_valid(edge_valid),.edge_negative(negative),.velocity_q(velocity));
 always @(negedge clk)begin if(timer==9)begin timer=0;tick=1;end else begin timer=timer+1;tick=0;end end
 task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
 task edge_at;input integer n,rev;begin clocks(n-1);negative=rev;edge_valid=1;clocks(1);edge_valid=0;end endtask
 initial begin
  $dumpfile("tb_velocity_reversal_jobs.vcd");$dumpvars(1,tb_velocity_reversal_jobs);
  clocks(5);rst_n=1;edge_at(25,0);edge_at(20,0);wait(dut.start);clocks(2);
  if(!dut.busy||!dut.job_valid||dut.pending_negative)$fatal(1,"FAIL: fixture did not launch positive division");
  edge_at(1,1);wait(dut.fresh_batch);clocks(2);
  if(!dut.busy||dut.job_valid)$fatal(1,"FAIL: reversal failed to invalidate pending positive job");
  edge_at(10,0);edge_at(10,1);clocks(40);
  if(dut.raw_q>0)$fatal(1,"FAIL: invalidated old job republished after several reversals");
  clocks(200);if(dut.raw_q>=0||velocity>=0)$fatal(1,"FAIL: latest negative measurement not published");
  clocks(10050);if(dut.raw_q!=0||velocity!=0)$fatal(1,"FAIL: timeout allowed stale job/history");
  $display("TEST PASSED: tb_velocity_reversal_jobs (in-flight cancellation, several reversals during division, latest signed result, timeout)");$finish;
 end
 initial begin #2000000;$fatal(1,"FAIL: reversal job timeout");end
endmodule
