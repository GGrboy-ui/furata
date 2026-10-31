`timescale 1ns/1ps
module tb_encoder_control_velocity;
 reg clk=0,rst_n=0,a=0,b=0,tick=0;always #5 clk=~clk;
 integer t=0,i;wire signed [31:0] position,velocity;
 encoder_qei #(.CLK_HZ(10000),.VEL_TIMEOUT_CLKS(10000)) dut(.clk(clk),.rst_n(rst_n),
  .enc_a(a),.enc_b(b),.tick_speed(tick),.position(position),.control_velocity_q(velocity));
 always @(negedge clk)begin if(t==9)begin t=0;tick=1;end else begin t=t+1;tick=0;end end
 task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
 task forward;begin case({a,b})0:{a,b}=1;1:{a,b}=3;3:{a,b}=2;2:{a,b}=0;endcase clocks(500);end endtask
 initial begin
  $dumpfile("tb_encoder_control_velocity.vcd");$dumpvars(1,tb_encoder_control_velocity);
  clocks(5);rst_n=1;clocks(20);
  // A diagonal jump is invalid: it establishes neither position nor speed.
  {a,b}=3;clocks(500);{a,b}=0;clocks(500);
  if(position!=0||velocity!=0||dut.control_speed.have_edge)$fatal(1,"FAIL: illegal transition fed control speed");
  forward;if(velocity!=0)$fatal(1,"FAIL: first valid edge creates speed");
  repeat(20)forward;
  if(position!=21||velocity<1250000||velocity>1350000)$fatal(1,"FAIL: QEI control speed scale %0d pos %0d",velocity,position);
  clocks(10100);if(velocity!=0)$fatal(1,"FAIL: stopped control speed");
  $display("TEST PASSED: tb_encoder_control_velocity (real A/B synchronization, invalid transitions, position, speed units, timeout)");$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: QEI speed timeout");end
endmodule
