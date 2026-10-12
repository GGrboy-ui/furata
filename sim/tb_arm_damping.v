`timescale 1ns/1ps
module tb_arm_damping;
 reg clk=0,rst_n=0,sample_valid=0,balance_cmd=0,start_cmd=0,motor_test_cmd=0;
 reg stop_cmd=0,permit=1,fault_latched=0;
 reg [11:0] sample=1014;
 reg signed [31:0] position=1234;
 wire signed [31:0] command_q,disabled_q;
 wire [2:0] state;
 always #5 clk=~clk;
 control_core #(.START_PERCENT(63),.ARM_DAMPING_KD(65536),.ANGLE_KP(65536),.ANGLE_KI(0),.ANGLE_KD(0),
   .POSITION_KP(0),.POSITION_KI(0),.POSITION_KD(0)) dut (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),
   .sample(sample),.position(position),.position_target_q(32'sd0),
   .start_cmd(start_cmd),.motor_test_cmd(motor_test_cmd),.balance_cmd(balance_cmd),
   .stop_cmd(stop_cmd),.permit(permit),.fault_latched(fault_latched),.command_q(command_q),.state(state));
 control_core #(.START_PERCENT(63),.ANGLE_KP(65536),.ANGLE_KI(0),.ANGLE_KD(0),.ARM_DAMPING_KD(0),
   .POSITION_KP(0),.POSITION_KI(0),.POSITION_KD(0)) disabled (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),
   .sample(sample),.position(position),.position_target_q(32'sd0),
   .start_cmd(start_cmd),.motor_test_cmd(motor_test_cmd),.balance_cmd(balance_cmd),
   .stop_cmd(stop_cmd),.permit(permit),.fault_latched(fault_latched),.command_q(disabled_q));
 task cycles; input integer n; begin repeat(n) @(negedge clk); end endtask
 task tick; begin sample_valid=1;cycles(1);sample_valid=0;cycles(3);end endtask
 task window; begin repeat(5) tick;end endtask
 task expect_command; input integer percent; begin
   if(command_q!==percent*65536) $fatal(1,"FAIL: expected %0d%% got Q=%0d",percent,command_q);
 end endtask
 task stop; begin stop_cmd=1;#1;expect_command(0);cycles(3);stop_cmd=0;cycles(3);end endtask
 task enter_balance; begin balance_cmd=1;cycles(1);balance_cmd=0;cycles(3);
   if(state!==4) $fatal(1,"FAIL: balance admission");end endtask
 initial begin
   $dumpfile("tb_arm_damping.vcd");$dumpvars(0,tb_arm_damping);
   cycles(3);rst_n=1;cycles(3);enter_balance;
   window;expect_command(0); // nonzero origin cannot create a speed kick
   position=1237;repeat(4) tick;expect_command(0);tick;expect_command(-3);
   if(disabled_q!==0) $fatal(1,"FAIL: zero gain did not disable damping");
   position=1233;window;expect_command(4);
   window;expect_command(0); // no stale period-based speed after stopping
   position=1333;window;expect_command(-20);
   position=1133;window;expect_command(20);
   sample=1004;position=1137;window;expect_command(6); // +10 angle -4 damping
   if(disabled_q!==10*65536) $fatal(1,"FAIL: disabled path changed angle PID");
   sample=814;position=1136;window;expect_command(100);
   sample=1214;position=1137;window;expect_command(-100);
   permit=0;#1;expect_command(0);cycles(3);
   if(dut.arm_damping_q!==0) $fatal(1,"FAIL: permit loss retained damping");
   permit=1;sample=1014;stop;
   position=-200000;cycles(3);enter_balance;window;expect_command(0);
   position=-199998;window;expect_command(-2);
   fault_latched=1;#1;expect_command(0);cycles(3);
   if(dut.arm_damping_q!==0 || state!==5) $fatal(1,"FAIL: fault clear");
   fault_latched=0;cycles(3);
   // Counter wrap must be a small signed displacement, not a saturated impulse.
   position=32'sh7fffffff;cycles(3);enter_balance;
   position=32'sh80000001;window;expect_command(-2);
   position=32'sh7fffffff;window;expect_command(2);stop;
   motor_test_cmd=1;cycles(1);motor_test_cmd=0;
   position=0;window;expect_command(20);stop;
   start_cmd=1;cycles(1);start_cmd=0;window;expect_command(63);stop;
   // Swing capture establishes a fresh baseline, just like manual balance.
   start_cmd=1;cycles(1);start_cmd=0;
   repeat(281) tick;
   if(state!==4) $fatal(1,"FAIL: automatic swing capture");
   window;expect_command(0);
   position=3;window;expect_command(-3);
   rst_n=0;cycles(2);expect_command(0);
   $display("TEST PASSED: tb_arm_damping (sign, cadence, limits, mix, stop, wrap, modes)");$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: damping timeout");end
endmodule
