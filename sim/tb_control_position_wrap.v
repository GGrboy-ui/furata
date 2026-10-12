`timescale 1ns/1ps
module tb_control_position_wrap;
 reg clk=0,rst_n=0,sample_valid=0,balance_cmd=0;
 reg signed [31:0] position=1234,target=0;
 wire signed [31:0] relative_position,error_q,offset_q;
 wire [3:0] fault;
 wire [2:0] state;
 control_core #(.COUNTS_PER_REV(408),.POSITION_KP(65536),.POSITION_KI(0),.POSITION_KD(0),
   .ANGLE_KP(0),.ANGLE_KI(0),.ANGLE_KD(0),.ARM_DAMPING_KD(65536)) dut(
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),.sample(12'd1014),
   .position(position),.position_target_q(target),.start_cmd(1'b0),.balance_cmd(balance_cmd),
   .motor_test_cmd(1'b0),.stop_cmd(1'b0),.permit(1'b1),.fault_latched(1'b0),
   .relative_position(relative_position),.position_error_q(error_q),.angle_target_offset_q(offset_q),
   .request_fault(fault),.state(state));
 always #5 clk=~clk;
 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task sample_tick;begin sample_valid=1;cycles(1);sample_valid=0;cycles(120);end endtask
 task check;input integer displacement;input integer expected;begin
   position=1234+displacement;cycles(120);
   if(relative_position!==expected || error_q!==-expected*65536)
     $fatal(1,"FAIL: relative=%0d error=%0d displacement=%0d",relative_position,error_q,displacement);
   repeat(50) sample_tick;
 end endtask
 initial begin
   $dumpfile("tb_control_position_wrap.vcd");$dumpvars(0,tb_control_position_wrap);
   cycles(3);rst_n=1;cycles(120);balance_cmd=1;cycles(1);balance_cmd=0;cycles(120);
   if(state!==4 || relative_position!==0) $fatal(1,"FAIL: captured origin");
   check(408,0);if(offset_q!==0) $fatal(1,"FAIL: full turn retained position demand");
   check(-408,0);if(offset_q!==0) $fatal(1,"FAIL: reverse full turn retained demand");
   check(409,1);if(offset_q!==65536) $fatal(1,"FAIL: target angle offset sign/units");
   check(407,-1);if(offset_q!==-65536) $fatal(1,"FAIL: shortest reverse offset");
   target=10*65536;position=1234+408+10;cycles(120);
   if(error_q!==0) $fatal(1,"FAIL: nonzero target not circular");
   target=408*65536+32768;position=1234;cycles(120);
   if(error_q!==32768) $fatal(1,"FAIL: fractional multi-turn target");
   target=0;position=1234+407;cycles(120);repeat(5) sample_tick;
   position=1234+408;cycles(120);repeat(5) sample_tick;
   if(dut.arm_damping_q!==65536) $fatal(1,"FAIL: position wrap injected speed damping kick");
   position=1234+408*11;cycles(120);
   if(relative_position!==0 || fault!==7) $fatal(1,"FAIL: circular coordinate hid travel protection");
   $display("TEST PASSED: tb_control_position_wrap (captured origin, +/-turn, targets, offset, speed and travel)");$finish;
 end
 initial begin #2000000;$fatal(1,"FAIL: circular control timeout");end
endmodule
