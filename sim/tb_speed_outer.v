`timescale 1ns/1ps
module tb_speed_outer;
 reg clk=0,rst_n=0,clear=0,tick=0;always #5 clk=~clk;
 reg [15:0] dt=20;
 reg signed [31:0] kp=0,ki=65536,kpos=0,ep=0,reference=655360,actual=0;
 wire signed [31:0] target,out;wire valid;
 speed_outer dut(.clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),.period_ms(dt),
  .kp_q(kp),.ki_q(ki),.kd_q(32'sd0),.kpos_q(kpos),.position_error_q(ep),.reference_q(reference),.actual_q(actual),
  .target_q(target),.out_q(out),.valid(valid));
 task step;begin @(negedge clk);tick=1;@(negedge clk);tick=0;wait(valid);@(negedge clk);end endtask
 task reset_pi;begin clear=1;repeat(3)@(negedge clk);clear=0;end endtask
 integer saved;
 initial begin
  $dumpfile("tb_speed_outer.vcd");$dumpvars(1,tb_speed_outer);
  repeat(3)@(negedge clk);rst_n=1;
  repeat(50)step;
  if(out<655300||out>655400)$fatal(1,"FAIL: 20ms integral per second %0d",out);
  saved=out;reset_pi;dt=100;repeat(10)step;
  if(out-saved>50||saved-out>50)$fatal(1,"FAIL: physical KI period invariance");
  reset_pi;kp=65536;ki=65536;actual=-65536000;reference=0;repeat(8)step;
  if(out!=1572864||dut.integral_q!=0)$fatal(1,"FAIL: saturation/windup %0d I=%0d",out,dut.integral_q);
  actual=65536000;step;if(out!= -1572864)$fatal(1,"FAIL: reverse braking sign");
  actual=0;step;if(out!=0)$fatal(1,"FAIL: anti-windup recovery");
  kpos=32768;ep=655360;ki=0;step;
  if(target!=327680||out!=327680)$fatal(1,"FAIL: position correction %0d %0d",target,out);
  ep=32'sh7fffffff;reference=32'sh7fffffff;step;
  if(target!=2228224||out!=1572864)$fatal(1,"FAIL: positive limits/overflow %0d",target);
  ep=32'sh80000000;reference=32'sh80000000;actual=32'sh7fffffff;step;
  if(target!= -2228224||out!= -1572864)$fatal(1,"FAIL: negative limits/overflow");
  // A sample is immutable even if the external sensor changes during the pipeline.
  reset_pi;ep=0;reference=65536;actual=0;kp=65536;
  @(negedge clk);tick=1;@(negedge clk);tick=0;actual=6553600;wait(valid);@(negedge clk);
  if(out!=65536)$fatal(1,"FAIL: mixed-time PI input");
  reset_pi;if(out!=0||target!=0||dut.stage!=0)$fatal(1,"FAIL: clear cancels in-flight arithmetic");
  $display("TEST PASSED: tb_speed_outer (time-scaled I, sign, limits, anti-windup, position correction, extrema, immutable sample, clear)");$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: speed PI timeout");end
endmodule
