`timescale 1ns/1ps
module tb_speed_derivative;
 reg clk=0,rst_n=0,clear=0,tick=0;always #5 clk=~clk;
 reg [15:0] period_ms=20;
 reg signed [31:0] kp_q=0,ki_q=0,kd_q=655,kpos_q=0,position_error_q=0,reference_q=0,actual_q=0;
 wire signed [31:0] target_q,out_q;wire valid;integer i,saved;
 speed_outer dut(.*);
 task step;begin @(negedge clk);tick=1;@(negedge clk);tick=0;wait(valid);@(negedge clk);end endtask
 task reset_d;begin clear=1;repeat(3)@(negedge clk);clear=0;end endtask
 initial begin
  $dumpfile("tb_speed_derivative.vcd");$dumpvars(1,tb_speed_derivative);
  repeat(3)@(negedge clk);rst_n=1;actual_q=655360;step;
  if(out_q!=0)$fatal(1,"FAIL: first derivative sample kick");
  actual_q=720896;step;if(out_q> -10900||out_q< -10930)$fatal(1,"FAIL: filtered measured derivative sign/dt %0d",out_q);
  for(i=0;i<49;i=i+1)begin actual_q=actual_q+65536;step;end
  saved=out_q;if(saved> -32650||saved< -32800)$fatal(1,"FAIL: steady acceleration D %0d",saved);
  reset_d;period_ms=100;actual_q=0;step;for(i=0;i<10;i=i+1)begin actual_q=actual_q+327680;step;end
  if(out_q-saved>100||saved-out_q>100)$fatal(1,"FAIL: D time normalization");
  reset_d;actual_q=0;step;reference_q=655360;step;if(out_q!=0)$fatal(1,"FAIL: setpoint derivative kick");
  kd_q=0;kp_q=65536;actual_q=0;step;if(out_q!=655360)$fatal(1,"FAIL: zero KD changed P");
  reset_d;kd_q=1048576;kp_q=0;actual_q=32'sh80000000;step;actual_q=32'sh7fffffff;step;
  if(out_q!=-1572864)$fatal(1,"FAIL: D overflow/limit %0d",out_q);
  // D alone can push the total into saturation: I must freeze in both signs.
  reset_d;period_ms=20;kp_q=0;ki_q=65536;kd_q=65536;reference_q=1310720;actual_q=0;step;saved=dut.integral_q;
  actual_q=-655360;step;if(out_q!=1572864||dut.integral_q!=saved)$fatal(1,"FAIL: positive D saturation winds I");
  reset_d;reference_q=-1310720;actual_q=0;step;saved=dut.integral_q;
  actual_q=655360;step;if(out_q!=-1572864||dut.integral_q!=saved)$fatal(1,"FAIL: negative D saturation winds I");
  // After a clear, the old saturated derivative cannot affect a stationary sample.
  reset_d;actual_q=0;reference_q=0;step;if(out_q!=0||dut.integral_q!=0)$fatal(1,"FAIL: D saturation recovery");
  $display("TEST PASSED: tb_speed_derivative (measurement D, filter, first sample, period scaling, setpoint kick, zero KD, overflow, D anti-windup and recovery)");$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: derivative timeout");end
endmodule
