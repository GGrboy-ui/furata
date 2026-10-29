`timescale 1ns/1ps
module tb_control_integral_decay;
 localparam signed [31:0] Q=65536;
 reg clk=0,rst_n=0,sample_valid=0,balance_cmd=0,stop_cmd=0;
 reg signed [31:0] position=100,target=0;
 wire signed [31:0] offset;
 wire [2:0] state;
 always #5 clk=~clk;
 control_core #(.CENTER(1007),.POSITION_KP(0),.POSITION_KI(Q),.POSITION_KD(0),
   .ANGLE_KP(0),.ANGLE_KI(0),.ANGLE_KD(0),.BALANCE_BOOST_MAX_PERCENT(0)) dut (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(1'b1),.sample(12'd1007),
   .position(position),.position_target_q(target),.start_cmd(1'b0),.motor_test_cmd(1'b0),
   .balance_cmd(balance_cmd),.stop_cmd(stop_cmd),.permit(1'b1),.fault_latched(1'b0),
   .state(state),.angle_target_offset_q(offset));
 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task samples;input integer n;begin repeat(n) begin sample_valid=1;cycles(1);sample_valid=0;cycles(120);end end endtask
 task check;input signed [31:0] expected;begin
   if(offset!==expected) $fatal(1,"FAIL: position I offset=%0d expected=%0d",offset,expected);
 end endtask
 task start;begin balance_cmd=1;cycles(1);balance_cmd=0;cycles(120);if(state!==4) $fatal(1,"FAIL: admission");end endtask
 integer i;
 initial begin
   $dumpfile("tb_control_integral_decay.vcd");$dumpvars(0,tb_control_integral_decay);
   cycles(3);rst_n=1;cycles(120);start;
   position=92;cycles(120);samples(50);check(-8*Q);
   position=100;cycles(120);samples(49);check(-8*Q);samples(1);check(-157286);
   position=98;cycles(120);samples(50);check(-47185);
   position=102;cycles(120);samples(50);check(-14155);
   position=97;cycles(120);samples(50);check(-210763); // outside restores normal I
   // Target-relative classification and circular wrap are both used.
   target=8*Q;position=106;cycles(120);samples(50);check(-63228);
   target=0;position=508;cycles(120);samples(50);check(-18968);
   stop_cmd=1;cycles(1);stop_cmd=0;cycles(120);check(0);
   start;position=516;cycles(120);samples(50);check(8*Q); // negative accumulated I
   position=508;cycles(120);samples(50);check(157286);
   samples(50);check(47185); // 9% remains after 100 ms, with truncation
   samples(50);check(14155); // 2.7% remains after 150 ms
   for(i=0;i<15;i=i+1) samples(50);
   check(0); // signed truncation must eventually remove the residual
   rst_n=0;cycles(1);check(0);
   $display("TEST PASSED: tb_control_integral_decay");$finish;
 end
 initial begin #30000000;$fatal(1,"FAIL: timeout");end
endmodule
