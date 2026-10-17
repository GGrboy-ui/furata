`timescale 1ns/1ps
module tb_balance_boost_capture;
 reg clk=0,rst_n=0,sample_valid=0,start_cmd=0,balance_cmd=0,motor_test_cmd=0,stop_cmd=0;
 reg sample_ready=1,permit=1,fault_latched=0;
 reg [11:0] sample=999;
 reg signed [31:0] position=1000;
 wire signed [31:0] command_q;
 wire [2:0] state;
 wire angle_update;
 always #5 clk=~clk;
 control_core #(.CENTER(999),.CAPTURE_RANGE(100),.START_PERCENT(63),
   .PULSE_MS(4),.CHECK_MS(2),.ANGLE_MS(5),
   .ANGLE_KP(65536),.ANGLE_KI(0),.ANGLE_KD(0),
   .POSITION_KP(0),.POSITION_KI(0),.POSITION_KD(0)) dut (
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(sample_ready),
   .sample(sample),.position(position),.position_target_q(32'sd0),
   .start_cmd(start_cmd),.motor_test_cmd(motor_test_cmd),.balance_cmd(balance_cmd),
   .stop_cmd(stop_cmd),.permit(permit),.fault_latched(fault_latched),
   .command_q(command_q),.state(state),.angle_update(angle_update));

 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task tick;begin sample_valid=1;cycles(1);sample_valid=0;cycles(3);end endtask
 task window;begin repeat(5) tick;end endtask
 task expect_q;input integer expected;begin
   if(command_q!==expected) $fatal(1,"FAIL: state=%0d expected command Q=%0d got %0d",state,expected,command_q);
 end endtask
 task clear_check;begin
   if(dut.boost_magnitude_q!==0 || dut.boost_sample_pending)
     $fatal(1,"FAIL: compensation result or pending sample survived inhibition");
 end endtask
 task stop;begin stop_cmd=1;#1;expect_q(0);cycles(3);stop_cmd=0;cycles(3);clear_check;end endtask
 task enter_balance;begin
   balance_cmd=1;cycles(1);balance_cmd=0;cycles(3);
   if(state!==4) $fatal(1,"FAIL: manual balance admission");
   expect_q(0);clear_check;
 end endtask
 task swing_check;begin
   clear_check;
   case(state)
     1:expect_q(63*65536);
     2:expect_q(-63*65536);
     3:expect_q(0);
     default:$fatal(1,"FAIL: expected swing mode, state=%0d",state);
   endcase
 end endtask

 initial begin
   $dumpfile("tb_balance_boost_capture.vcd");$dumpvars(0,tb_balance_boost_capture);
   cycles(3);rst_n=1;cycles(120);enter_balance;window;expect_q(0);
   sample=1011;repeat(4) tick;expect_q(0);
   // Change the live sensor on angle_tick itself. Its registered value is
   // still 1011, so the PID and compensation must both capture that value.
   sample=1023;sample_valid=1;
   @(posedge clk);#1;expect_q(0);
   if(angle_update) $fatal(1,"FAIL: result published on the capture clock");
   @(negedge clk);sample_valid=0;
   @(posedge clk);#1;
   if(!angle_update || command_q!==-950272 || dut.boost_magnitude_q!==163840)
     $fatal(1,"FAIL: PID and compensation did not publish the same registered sample");
   cycles(3);window;expect_q(-1900544);
   // A new sensor value between updates cannot change a published command.
   sample=1024;cycles(3);expect_q(-1900544);window;expect_q(-1638400);

   sample=1011;cycles(3);window;expect_q(-950272);
   sample_ready=0;#1;expect_q(-786432);cycles(3);clear_check;
   sample_ready=1;cycles(3);expect_q(-786432);window;expect_q(-950272);
   permit=0;#1;expect_q(0);cycles(3);clear_check;
   permit=1;cycles(3);expect_q(-786432);window;expect_q(-950272);

   // Stop between capture and publication must cancel the pending increment.
   repeat(4) tick;sample_valid=1;cycles(1);sample_valid=0;
   stop_cmd=1;#1;expect_q(0);cycles(3);clear_check;
   stop_cmd=0;cycles(3);sample=999;cycles(3);enter_balance;window;expect_q(0);
   sample=987;cycles(3);window;expect_q(950272);
   fault_latched=1;#1;expect_q(0);cycles(3);clear_check;
   if(state!==5) $fatal(1,"FAIL: latched fault did not enter FAULT");
   fault_latched=0;cycles(3);
   if(state!==0) $fatal(1,"FAIL: cleared fault did not return to STOP");

   sample=1011;cycles(3);motor_test_cmd=1;cycles(1);motor_test_cmd=0;
   position=position+30;window;expect_q(20*65536);clear_check;stop;
   start_cmd=1;cycles(1);start_cmd=0;swing_check;
   // Angle inside the compensation band and encoder motion cannot modify
   // PUSH/PULL; only the first complete balance window gets an increment.
   repeat(3) begin position=position+30;tick;swing_check;end
   tick;swing_check;
   repeat(4) begin position=position-20;tick;swing_check;end
   repeat(3) begin position=position+20;tick;swing_check;end
   tick;
   if(state!==4) $fatal(1,"FAIL: automatic swing capture");
   expect_q(0);clear_check;
   repeat(4) begin position=position+1;tick;expect_q(0);end
   tick;expect_q(-950272);
   stop;sample=999;cycles(3);enter_balance;window;expect_q(0);
   sample=1011;cycles(3);window;expect_q(-950272);
   rst_n=0;#1;expect_q(0);cycles(2);clear_check;
   $display("TEST PASSED: tb_balance_boost_capture (measurement alignment, publication, sensor/permit gates, pending stop, fault, modes, re-entry, reset)");
   $finish;
 end
 initial begin #2000000;$fatal(1,"FAIL: compensation capture timeout");end
endmodule
