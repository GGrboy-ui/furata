`timescale 1ns/1ps
module tb_control_position_linear;
 reg clk=0,rst_n=0,sample_valid=0,balance_cmd=0,stop_cmd=0;
 reg signed [31:0] position=1234,target=0;
 wire signed [31:0] relative_position,error_q,offset_q,derivative_offset_q,command_q;
 wire [3:0] fault;
 wire [2:0] state;
 // Separate P-only and D-only loops distinguish accumulated feedback from
 // a shortest-path error and from a derivative that still wraps each turn.
 control_core #(.POSITION_KP(4096),.POSITION_KI(0),.POSITION_KD(0),
   .ANGLE_KP(0),.ANGLE_KI(0),.ANGLE_KD(0)) dut(
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),.sample(12'd1014),
   .position(position),.position_target_q(target),.start_cmd(1'b0),.balance_cmd(balance_cmd),
   .motor_test_cmd(1'b0),.stop_cmd(stop_cmd),.permit(1'b1),.fault_latched(1'b0),
   .relative_position(relative_position),.position_error_q(error_q),.angle_target_offset_q(offset_q),
   .request_fault(fault),.state(state),.command_q(command_q));
 control_core #(.POSITION_KP(0),.POSITION_KI(0),.POSITION_KD(65536),
   .ANGLE_KP(0),.ANGLE_KI(0),.ANGLE_KD(0)) derivative_dut(
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),.sample(12'd1014),
   .position(position),.position_target_q(target),.start_cmd(1'b0),.balance_cmd(balance_cmd),
   .motor_test_cmd(1'b0),.stop_cmd(stop_cmd),.permit(1'b1),.fault_latched(1'b0),
   .angle_target_offset_q(derivative_offset_q));
 always #5 clk=~clk;
 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task sample_tick;begin sample_valid=1;cycles(1);sample_valid=0;cycles(4);end endtask
 task position_step;begin repeat(50) sample_tick;end endtask
 task check;input integer displacement;reg signed [31:0] expected_offset;begin
   position=1234+displacement;cycles(3);
   if(relative_position!==displacement || error_q!==-displacement*65536)
     $fatal(1,"FAIL: relative=%0d error=%0d displacement=%0d",relative_position,error_q,displacement);
   position_step;
   expected_offset=displacement*4096;
   if(expected_offset>100*65536) expected_offset=100*65536;
   if(expected_offset< -100*65536) expected_offset=-100*65536;
   if(offset_q!==expected_offset) $fatal(1,"FAIL: accumulated P offset=%0d expected=%0d",offset_q,expected_offset);
 end endtask
 initial begin
   $dumpfile("tb_control_position_linear.vcd");$dumpvars(0,tb_control_position_linear);
   cycles(3);rst_n=1;cycles(3);balance_cmd=1;cycles(1);balance_cmd=0;cycles(3);
   if(state!==4 || relative_position!==0 || error_q!==0) $fatal(1,"FAIL: captured origin");
   check(408);
   if(derivative_offset_q!==100*65536) $fatal(1,"FAIL: full-turn derivative wrapped to zero");
   position_step;
   if(derivative_offset_q!==0) $fatal(1,"FAIL: stationary accumulated position generated derivative");
   check(409);if(derivative_offset_q!==65536) $fatal(1,"FAIL: forward one-count derivative");
   check(407);if(derivative_offset_q!==-2*65536) $fatal(1,"FAIL: reverse two-count derivative");
   check(203);check(204);
   if(derivative_offset_q!==65536) $fatal(1,"FAIL: half-turn crossing discontinuity");
   check(-408);check(-409);check(816);check(-816);
   // Return to the same accumulated coordinate, including after multiple turns.
   check(0);if(offset_q!==0) $fatal(1,"FAIL: return to captured origin");
   target=408*65536;position=1234+408;cycles(3);
   if(error_q!==0) $fatal(1,"FAIL: full-turn target not reached");
   position=1234;cycles(3);
   if(error_q!==408*65536) $fatal(1,"FAIL: full-turn target discarded");
   target=408*65536+32768;cycles(3);
   if(error_q!==408*65536+32768) $fatal(1,"FAIL: fractional multi-turn target");
   target=-408*65536-32768;cycles(3);
   if(error_q!==-408*65536-32768) $fatal(1,"FAIL: negative fractional multi-turn target");
   // A target change cannot move the travel-protection origin.
   target=4080*65536;position=1234+4080;cycles(3);
   if(fault!==0 || error_q!==0) $fatal(1,"FAIL: positive inclusive travel boundary");
   position=1234+4081;cycles(3);
   if(fault!==7 || error_q!==-65536) $fatal(1,"FAIL: positive travel protection");
   target=-4080*65536;position=1234-4080;cycles(3);
   if(fault!==0 || error_q!==0) $fatal(1,"FAIL: negative inclusive travel boundary");
   position=1234-4081;cycles(3);
   if(fault!==7 || error_q!==65536) $fatal(1,"FAIL: negative travel protection");
   target=0;position=1234+408*11;cycles(3);
   if(relative_position!==4488 || fault!==7) $fatal(1,"FAIL: full turns hid travel protection");
   // Extreme stopped/faulted readings must saturate, never flip error sign.
   position=1234+40000;cycles(3);
   if(relative_position!==40000 || error_q!==32'sh80000000 || fault!==7)
     $fatal(1,"FAIL: negative Q16.16 saturation");
   position=1234-40000;cycles(3);
   if(relative_position!==-40000 || error_q!==32'sh7fffffff || fault!==7)
     $fatal(1,"FAIL: positive Q16.16 saturation");
   position=32'sh80000000;cycles(3);
   if(relative_position!==32'sh80000000 || error_q!==32'sh7fffffff || fault!==7)
     $fatal(1,"FAIL: wide relative subtraction overflow");
   // Stopping and entering balance again captures a fresh origin once.
   stop_cmd=1;cycles(1);stop_cmd=0;position=-9000;cycles(3);
   balance_cmd=1;cycles(1);balance_cmd=0;cycles(3);
   if(relative_position!==0 || error_q!==0 || fault!==0) $fatal(1,"FAIL: recapture origin");
   position=-9000-408;cycles(3);
   if(relative_position!==-408 || error_q!==408*65536) $fatal(1,"FAIL: recaptured multi-turn feedback");
   position_step;
   if(command_q!==0) $fatal(1,"FAIL: position movement injected an independent motor correction");
   $display("TEST PASSED: tb_control_position_linear (multi-turn P/D, target fractions, origin, limits, saturation)");$finish;
 end
 initial begin #2000000;$fatal(1,"FAIL: linear position control timeout");end
endmodule
