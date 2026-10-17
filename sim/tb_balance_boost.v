`timescale 1ns/1ps
// Exercise the command interface with real PID results, including a D-term
// braking command whose sign opposes the instantaneous angle error.
module tb_balance_boost;
 reg clk=0,rst_n=0,sample_valid=0,balance_cmd=0;
 reg [11:0] sample=999;
 reg signed [31:0] position=1234;
 wire signed [31:0] command_q,range_off_q,max_off_q,zero_q,limit_q,brake_q,shift_q;
 wire [2:0] state;
 wire signed [31:0] shift_offset_q;
 always #5 clk=~clk;

 control_core #(.CENTER(999),.ANGLE_KP(65536),.ANGLE_KI(0),.ANGLE_KD(0),
   .POSITION_KP(0),.POSITION_KI(0),.POSITION_KD(0)) dut (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),
   .sample(sample),.position(position),.position_target_q(32'sd0),
   .start_cmd(1'b0),.motor_test_cmd(1'b0),.balance_cmd(balance_cmd),
   .stop_cmd(1'b0),.permit(1'b1),.fault_latched(1'b0),.command_q(command_q),.state(state));
 control_core #(.CENTER(999),.BALANCE_BOOST_RANGE_CODES(0),
   .ANGLE_KP(65536),.ANGLE_KI(0),.ANGLE_KD(0),
   .POSITION_KP(0),.POSITION_KI(0),.POSITION_KD(0)) range_off (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),
   .sample(sample),.position(position),.position_target_q(32'sd0),
   .start_cmd(1'b0),.motor_test_cmd(1'b0),.balance_cmd(balance_cmd),
   .stop_cmd(1'b0),.permit(1'b1),.fault_latched(1'b0),.command_q(range_off_q));
 control_core #(.CENTER(999),.BALANCE_BOOST_MAX_PERCENT(0),
   .ANGLE_KP(65536),.ANGLE_KI(0),.ANGLE_KD(0),
   .POSITION_KP(0),.POSITION_KI(0),.POSITION_KD(0)) max_off (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),
   .sample(sample),.position(position),.position_target_q(32'sd0),
   .start_cmd(1'b0),.motor_test_cmd(1'b0),.balance_cmd(balance_cmd),
   .stop_cmd(1'b0),.permit(1'b1),.fault_latched(1'b0),.command_q(max_off_q));
 control_core #(.CENTER(999),.ANGLE_KP(0),.ANGLE_KI(0),.ANGLE_KD(0),
   .POSITION_KP(0),.POSITION_KI(0),.POSITION_KD(0)) zero_pid (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),
   .sample(sample),.position(position),.position_target_q(32'sd0),
   .start_cmd(1'b0),.motor_test_cmd(1'b0),.balance_cmd(balance_cmd),
   .stop_cmd(1'b0),.permit(1'b1),.fault_latched(1'b0),.command_q(zero_q));
 control_core #(.CENTER(999),.ANGLE_KP(262144),.ANGLE_KI(0),.ANGLE_KD(0),
   .POSITION_KP(0),.POSITION_KI(0),.POSITION_KD(0)) saturated (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),
   .sample(sample),.position(position),.position_target_q(32'sd0),
   .start_cmd(1'b0),.motor_test_cmd(1'b0),.balance_cmd(balance_cmd),
   .stop_cmd(1'b0),.permit(1'b1),.fault_latched(1'b0),.command_q(limit_q));
 control_core #(.CENTER(999),.ANGLE_KP(65536),.ANGLE_KI(0),.ANGLE_KD(65536),
   .POSITION_KP(0),.POSITION_KI(0),.POSITION_KD(0)) braking (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),
   .sample(sample),.position(position),.position_target_q(32'sd0),
   .start_cmd(1'b0),.motor_test_cmd(1'b0),.balance_cmd(balance_cmd),
   .stop_cmd(1'b0),.permit(1'b1),.fault_latched(1'b0),.command_q(brake_q));
 control_core #(.CENTER(999),.ANGLE_KP(65536),.ANGLE_KI(0),.ANGLE_KD(0),
   .POSITION_KP(65536),.POSITION_KI(0),.POSITION_KD(0)) shifted_target (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),
   .sample(sample),.position(position),.position_target_q(32'sd0),
   .start_cmd(1'b0),.motor_test_cmd(1'b0),.balance_cmd(balance_cmd),
   .stop_cmd(1'b0),.permit(1'b1),.fault_latched(1'b0),.command_q(shift_q),
   .angle_target_offset_q(shift_offset_q));

 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task tick;begin sample_valid=1;cycles(1);sample_valid=0;cycles(3);end endtask
 task window;begin repeat(5) tick;end endtask
 task point;
   input integer adc;
   input integer expected_q;
   integer base_q;
   begin
     sample=adc;cycles(3);window;
     base_q=(999-adc)*65536;
     if(command_q!==expected_q)
       $fatal(1,"FAIL: ADC=%0d expected command Q=%0d got %0d",adc,expected_q,command_q);
     if(range_off_q!==base_q || max_off_q!==base_q)
       $fatal(1,"FAIL: a zero compensation parameter changed the original PID");
     if(zero_q!==0) $fatal(1,"FAIL: zero PID produced compensation torque");
   end
 endtask

 initial begin
   $dumpfile("tb_balance_boost.vcd");$dumpvars(0,tb_balance_boost);
   cycles(3);rst_n=1;cycles(120);balance_cmd=1;cycles(1);balance_cmd=0;cycles(120);
   if(state!==4) $fatal(1,"FAIL: manual balance admission");
   point(999,0);
   // 1 code retains the fractional 0.208328 percent increment in Q16.16.
   point(1000,-79189);point(998,79189);
   point(1011,-950272);point(987,950272); // +/-12: 12+2.5 percent
   point(1023,-1900544);
   if(limit_q!==-6553600) $fatal(1,"FAIL: negative 96+5 percent did not saturate at -100");
   point(975,1900544);
   if(limit_q!==6553600) $fatal(1,"FAIL: positive 96+5 percent did not saturate at +100");
   point(1024,-1638400);point(974,1638400); // +/-25: compensation removed

   // Error changes from -12 to -1. The real D term commands +10 percent;
   // compensation must follow that command even though ADC remains above center.
   point(1011,-950272);point(1000,-79189);
   if(brake_q!==669013) $fatal(1,"FAIL: positive braking command received wrong compensation sign");
   point(987,950272);point(998,79189);
   if(brake_q!==-669013) $fatal(1,"FAIL: negative braking command received wrong compensation sign");

   point(1011,-950272);
   position=position+3;cycles(120);window;
   if(command_q!==-950272) $fatal(1,"FAIL: encoder movement changed angle-only torque");
   position=position-7;cycles(120);window;window;
   if(command_q!==-950272) $fatal(1,"FAIL: reverse or stopped encoder changed angle-only torque");

   // The position loop moves its angle target one code, but boost distance
   // remains zero because the measured ADC is exactly at fixed CENTER.
   position=1235;sample=999;cycles(120);repeat(60) tick;
   if(shift_offset_q!==65536 || shift_q!==65536 || shifted_target.boost_magnitude_q!==0)
     $fatal(1,"FAIL: compensation distance followed position-adjusted target");
   $display("TEST PASSED: tb_balance_boost (linear boundaries, fractions, zero options, braking sign, saturation, encoder independence, fixed center)");
   $finish;
 end
 initial begin #2000000;$fatal(1,"FAIL: balance compensation timeout");end
endmodule
