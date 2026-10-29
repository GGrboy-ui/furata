`timescale 1ns/1ps
module tb_control_integral_deadband;
 localparam signed [31:0] Q=65536;
 reg clk=0,rst_n=0,sample_valid=0,balance_cmd=0,stop_cmd=0;
 reg [11:0] sample=1007;
 reg signed [31:0] position_target_q=0;
 wire signed [31:0] command_q,legacy_command_q,offset_q;
 wire [2:0] state;
 always #5 clk=~clk;
 // I-only fixtures make an extra integrated ADC code visible as one output unit.
 // The position I is deliberately enabled to check that its deadband stays disabled.
 control_core #(.CENTER(1007),.ANGLE_KP(0),.ANGLE_KI(Q),.ANGLE_KD(0),
   .ANGLE_I_DEADBAND_Q(Q),.POSITION_I_DECAY_BAND_Q(0),
   .POSITION_KP(0),.POSITION_KI(Q),.POSITION_KD(0),.BALANCE_BOOST_MAX_PERCENT(0)) dut (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),.sample(sample),
   .position(32'sd0),.position_target_q(position_target_q),.start_cmd(1'b0),.motor_test_cmd(1'b0),
   .balance_cmd(balance_cmd),.stop_cmd(stop_cmd),.permit(1'b1),.fault_latched(1'b0),
   .command_q(command_q),.state(state),.angle_target_offset_q(offset_q));
 control_core #(.CENTER(1007),.ANGLE_KP(0),.ANGLE_KI(Q),.ANGLE_KD(0),.ANGLE_I_DEADBAND_Q(0),
   .POSITION_I_DECAY_BAND_Q(0),
   .POSITION_KP(0),.POSITION_KI(Q),.POSITION_KD(0),.BALANCE_BOOST_MAX_PERCENT(0)) legacy (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),.sample(sample),
   .position(32'sd0),.position_target_q(position_target_q),.start_cmd(1'b0),.motor_test_cmd(1'b0),
   .balance_cmd(balance_cmd),.stop_cmd(stop_cmd),.permit(1'b1),.fault_latched(1'b0),
   .command_q(legacy_command_q));
 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task sample_tick;begin sample_valid=1;cycles(1);sample_valid=0;cycles(120);end endtask
 task angle_step;
   input [11:0] adc;
   input signed [31:0] expected,expected_legacy;
   begin
     sample=adc;cycles(3);repeat(5) sample_tick;
     if(command_q!==expected || legacy_command_q!==expected_legacy)
       $fatal(1,"FAIL: adc=%0d angle I=%0d/%0d legacy=%0d/%0d",adc,
         command_q,expected,legacy_command_q,expected_legacy);
   end
 endtask
 initial begin
   $dumpfile("tb_control_integral_deadband.vcd");$dumpvars(0,tb_control_integral_deadband);
   cycles(3);rst_n=1;cycles(120);balance_cmd=1;cycles(1);balance_cmd=0;cycles(3);
   if(state!==4) $fatal(1,"FAIL: manual balance admission");
   angle_step(1006,0,Q);           // +1: inclusive deadband; legacy still integrates.
   angle_step(1005,2*Q,3*Q);      // +2: full error integrates, without subtracting the band.
   angle_step(1007,2*Q,3*Q);      // zero: accumulated I is retained.
   angle_step(1008,2*Q,2*Q);      // -1: inclusive deadband.
   angle_step(1009,0,0);          // -2: normal integration resumes.
   // Inject outer-loop outputs at their interface to isolate live-target handling.
   force dut.position_out=-3*Q;force legacy.position_out=-3*Q;
   angle_step(1009,0,Q);          // +1 from target 1010, although ADC is CENTER+2.
   force dut.position_out=-3*Q-Q/2;force legacy.position_out=-3*Q-Q/2;
   angle_step(1010,0,3*Q/2);      // +0.5 from fractional target 1010.5.
   force dut.position_out=-Q-Q/2;force legacy.position_out=-Q-Q/2;
   angle_step(1007,3*Q/2,3*Q);    // +1.5 from target, although ADC equals CENTER.
   force dut.position_out=3*Q;force legacy.position_out=3*Q;
   angle_step(1005,3*Q/2,2*Q);    // -1 relative to target 1004.
   stop_cmd=1;cycles(1);stop_cmd=0;cycles(3);
   if(state!==0 || command_q!==0 || dut.angle_pid.out_q!==0)
     $fatal(1,"FAIL: stopping did not clear angle integral");
   release dut.position_out;release legacy.position_out;
   sample=1007;cycles(3);balance_cmd=1;cycles(1);balance_cmd=0;cycles(3);
   position_target_q=Q/2;cycles(120);repeat(50) sample_tick;
   if(offset_q!==-Q/2) $fatal(1,"FAIL: angle deadband suppressed position integration");
   angle_step(1007,0,-Q/2);
   rst_n=0;cycles(1);
   if(command_q!==0 || dut.angle_pid.out_q!==0) $fatal(1,"FAIL: reset did not clear integral");
   $display("TEST PASSED: tb_control_integral_deadband (angle-only wiring, live fractional target, disable, stop/reset)");
   $finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: control integral deadband timeout");end
endmodule
