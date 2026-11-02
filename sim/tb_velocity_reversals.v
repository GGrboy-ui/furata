`timescale 1ns/1ps
module tb_velocity_reversals;
 reg clk=0,rst_n=0,tick=0,edge_valid=0,negative=0;always #5 clk=~clk;
 integer timer=0,i,nonzero=0;reg signed [31:0] previous;
 wire signed [31:0] velocity;
 velocity_feedback #(.CLK_HZ(100000)) dut(.clk(clk),.rst_n(rst_n),.tick_ms(tick),.edge_valid(edge_valid),.edge_negative(negative),.velocity_q(velocity));
 always @(negedge clk)begin if(timer==99)begin timer=0;tick=1;end else begin timer=timer+1;tick=0;end end
 task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
 task edge_at;input integer n,rev;begin clocks(n-1);negative=rev;edge_valid=1;clocks(1);edge_valid=0;end endtask
 task reset_est;begin rst_n=0;clocks(3);rst_n=1;clocks(3);end endtask
 initial begin
  $dumpfile("tb_velocity_reversals.vcd");$dumpvars(1,tb_velocity_reversals);
  clocks(5);rst_n=1;
  // One count per direction: old implementation never established a period.
  for(i=0;i<40;i=i+1)begin edge_at(2500,i%2);clocks(300);if(velocity!=0)nonzero=nonzero+1;end
  if(nonzero<30)$fatal(1,"FAIL: frequent reversals collapsed to zero %0d",nonzero);
  // Establish a positive speed, then verify reversal preserves continuity and
  // becomes negative without waiting for a second same-direction reverse edge.
  reset_est;repeat(20)edge_at(2500,0);previous=velocity;
  edge_at(2500,1);clocks(3);if(velocity<=0||velocity<previous*3/4)$fatal(1,"FAIL: forced zero at reversal");
  clocks(500);if(dut.raw_q>=0)$fatal(1,"FAIL: first reverse batch did not update sign");
  clocks(5000);if(velocity>=0)$fatal(1,"FAIL: filter did not cross zero");
  // Forward/back pulses inside one ms cancel; they cannot invent a huge speed.
  reset_est;wait(tick);clocks(5);edge_at(2,0);edge_at(2,1);clocks(500);
  if(dut.have_edge||velocity!=0)$fatal(1,"FAIL: net-zero bounce invented motion");
  // Include an edge coincident with tick exactly once.
  reset_est;wait(tick);edge_valid=1;negative=0;clocks(1);edge_valid=0;clocks(4);
  if(!dut.have_edge||dut.period_steps!=1)$fatal(1,"FAIL: tick boundary edge missing/doubled");
  // Multiple counts every ms must not perpetually invalidate every division.
  reset_est;
  for(i=0;i<250;i=i+1)begin edge_at(50,0);edge_at(50,0);end
  if(dut.raw_q<130000000||dut.raw_q>132000000||velocity<128000000)$fatal(1,"FAIL: two-count continuous windows %0d %0d",dut.raw_q,velocity);
  // Stop timeout also clears queued results; a new first edge cannot resurrect IIR.
  clocks(100300);if(velocity!=0||dut.raw_q!=0)$fatal(1,"FAIL: stop timeout");
  edge_at(100,1);clocks(500);if(velocity!=0)$fatal(1,"FAIL: timeout restarted from stale history");
  $display("TEST PASSED: tb_velocity_reversals (single-count alternating reversals, continuous zero crossing, first reverse response, sub-ms bounce, tick edge, multi-count windows, timeout)");$finish;
 end
 initial begin #20000000;$fatal(1,"FAIL: reversal estimator timeout");end
endmodule
