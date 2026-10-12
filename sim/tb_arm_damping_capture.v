`timescale 1ns/1ps
module tb_arm_damping_capture;
 reg clk=0,rst_n=0,sample_valid=0,start_cmd=0,balance_cmd=0,stop_cmd=0;
 reg sample_ready=1;
 reg [11:0] sample=1014;
 reg signed [31:0] position=1000;
 wire signed [31:0] command_q;
 wire [2:0] state;
 integer k;
 always #5 clk=~clk;
 control_core #(.CENTER(1014),.CAPTURE_RANGE(100),.START_PERCENT(63),
   .PULSE_MS(4),.CHECK_MS(2),.ANGLE_MS(5),.ARM_DAMPING_KD(65536),
   .ANGLE_KP(0),.ANGLE_KI(0),.ANGLE_KD(0),
   .POSITION_KP(0),.POSITION_KI(0),.POSITION_KD(0)) dut (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(sample_ready),
   .sample(sample),.position(position),.position_target_q(32'sd0),
   .start_cmd(start_cmd),.motor_test_cmd(1'b0),.balance_cmd(balance_cmd),
   .stop_cmd(stop_cmd),.permit(1'b1),.fault_latched(1'b0),.command_q(command_q),.state(state));
 task cycles; input integer n; begin repeat(n) @(negedge clk);end endtask
 task tick; begin sample_valid=1;cycles(1);sample_valid=0;cycles(3);end endtask
 task check_swing;begin
   if(dut.arm_damping_enable || dut.arm_damping_q!==0 || dut.arm_damping_applied_q!==0)
     $fatal(1,"FAIL: damping enabled before capture, state=%0d",state);
   case(state)
     1:if(command_q!==63*65536) $fatal(1,"FAIL: PUSH reduced by damping");
     2:if(command_q!==-63*65536) $fatal(1,"FAIL: PULL reduced by damping");
     3:if(command_q!==0) $fatal(1,"FAIL: WAIT_PEAK braking");
     default:$fatal(1,"FAIL: expected swing state");
   endcase
 end endtask
 initial begin
   $dumpfile("tb_arm_damping_capture.vcd");$dumpvars(0,tb_arm_damping_capture);
   cycles(3);rst_n=1;cycles(3);start_cmd=1;cycles(1);start_cmd=0;
   // Large encoder motion, including angle crossings, cannot modify either pulse.
   for(k=0;k<8;k=k+1) begin
     position=position+30;sample=(k%2==0)?1014:1400;cycles(2);check_swing;tick;check_swing;
   end
   // An outside sample followed by one inside check is not a completed capture.
   sample=1400;
   for(k=0;k<4;k=k+1) begin position=position-20;tick;check_swing;end
   sample=1014;
   repeat(2) begin position=position+20;tick;check_swing;end
   position=position+20;tick;check_swing;
   position=position+20;tick;
   if(state!==4 || !dut.arm_damping_enable || command_q!==0)
     $fatal(1,"FAIL: balance capture must start with zero damping history");
   // First complete balance window contains only post-capture displacement.
   repeat(4) begin position=position+1;tick;
     if(command_q!==0) $fatal(1,"FAIL: premature first damping output");end
   position=position+1;tick;
   if(command_q!==-5*65536) $fatal(1,"FAIL: first captured-window damping");
   // Boundaries are exclusive. Inhibit immediately, before sample_valid/fault latch.
   sample=1114;#1;
   if(dut.arm_damping_enable || command_q!==0) $fatal(1,"FAIL: upper boundary retained damping");
   cycles(2);
   if(dut.arm_damping_q!==0 || dut.arm_sample_pending) $fatal(1,"FAIL: outside history not cleared");
   sample=914;#1;
   if(dut.arm_damping_enable) $fatal(1,"FAIL: lower boundary admitted damping");
   sample=1014;cycles(2);
   position=position-3;repeat(5) tick;
   if(command_q!==3*65536) $fatal(1,"FAIL: reverse damping inside window");
   sample_ready=0;#1;
   if(command_q!==0) $fatal(1,"FAIL: invalid sensor retained damping");
   cycles(2);sample_ready=1;
   stop_cmd=1;cycles(2);stop_cmd=0;position=100;cycles(2);
   balance_cmd=1;cycles(1);balance_cmd=0;
   if(state!==4 || command_q!==0) $fatal(1,"FAIL: manual capture baseline");
   position=position+2;repeat(5) tick;
   if(command_q!==-2*65536) $fatal(1,"FAIL: manual balance damping");
   $display("TEST PASSED: tb_arm_damping_capture (moving swing, crossings, capture, boundary gating, manual entry)");$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: capture damping timeout");end
endmodule
