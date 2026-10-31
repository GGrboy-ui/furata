`timescale 1ns/1ps
module tb_pwm_friction;
 reg clk=0,rst_n=0,active=0,negative=0;
 reg [15:0] magnitude=0,t_counts=0;
 wire signed [15:0] command;
 integer i,expected;
 always #5 clk=~clk;
 pwm_friction dut(.*);
 task check;
 input integer base,t,enabled,neg;
 begin
  @(negedge clk);magnitude=base;t_counts=t;active=enabled;negative=neg;
  repeat(4)@(negedge clk);
  expected=base+(enabled?t:0);if(expected>2500)expected=2500;if(neg)expected=-expected;
  if(command!==expected)$fatal(1,"FAIL: PWM base=%0d t=%0d active=%0d neg=%0d got=%0d expected=%0d",base,t,enabled,neg,command,expected);
 end endtask
 initial begin
  $dumpfile("tb_pwm_friction.vcd");$dumpvars(1,tb_pwm_friction);
  repeat(2)@(negedge clk);rst_n=1;
  check(100,20,1,0);check(100,20,1,1);check(0,20,0,0);check(0,20,1,1);
  check(100,20,0,0);check(100,0,1,1);check(2499,20,1,0);check(2499,20,1,1);
  check(65535,65535,1,1);
  for(i=0;i<1000;i=i+1)check($urandom_range(0,65535),$urandom_range(0,65535),$urandom_range(0,1),$urandom_range(0,1));
  rst_n=0;#1;if(command!==0)$fatal(1,"FAIL: async reset");
  $display("TEST PASSED: tb_pwm_friction (both signs, braking, zero and sub-count requests, disabled, t=0, saturation, wide addition, random, reset)");$finish;
 end
endmodule
