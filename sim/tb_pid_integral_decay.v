`timescale 1ns/1ps
module tb_pid_integral_decay;
 localparam signed [31:0] Q=65536;
 reg clk=0,rst_n=0,clear=0,tick=0;
 reg signed [31:0] target=0,actual=0;
 wire signed [31:0] out_i,out_plain,out_pd;
 wire valid;
 always #5 clk=~clk;
 pid_fixed #(.KP(0),.KI(Q),.KD(0),.I_LIMIT(16*Q),
   .I_DECAY_BAND_Q(2*Q),.I_DECAY_RETAIN_PERCENT(75)) dut (
   .clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),.target_q(target),.actual_q(actual),.out_q(out_i),.valid(valid));
 pid_fixed #(.KP(0),.KI(Q),.KD(0),.I_LIMIT(16*Q)) plain (
   .clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),.target_q(target),.actual_q(actual),.out_q(out_plain));
 pid_fixed #(.KP(Q),.KI(0),.KD(Q),.I_DECAY_BAND_Q(2*Q)) pd (
   .clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),.target_q(target),.actual_q(actual),.out_q(out_pd));
 reg signed [31:0] old_error=0,plain_expected=0;
 reg signed [63:0] wide;
 task step;
   input signed [31:0] error_value,expected;
   reg signed [31:0] pd_expected,old_out;
   begin
     @(negedge clk);target=error_value+actual;tick=1;old_out=out_i;
     wide=$signed(plain_expected)+$signed(error_value);
     plain_expected=wide>16*Q ? 16*Q : wide< -16*Q ? -16*Q : wide;
     pd_expected=error_value+error_value-old_error;old_error=error_value;
     @(posedge clk);#1;if(valid || out_i!==old_out) $fatal(1,"FAIL: early result");
     @(negedge clk);tick=0;
     @(posedge clk);#1;
     if(!valid || out_i!==expected || out_plain!==plain_expected || out_pd!==pd_expected)
       $fatal(1,"FAIL: e=%0d I=%0d expected=%0d plain=%0d/%0d PD=%0d/%0d",error_value,out_i,expected,out_plain,plain_expected,out_pd,pd_expected);
     repeat(3) @(negedge clk);
     if(out_i!==expected) $fatal(1,"FAIL: decay outside tick");
   end
 endtask
 task reset_i;
   begin
     @(negedge clk);clear=1;tick=1;
     @(negedge clk);clear=0;tick=0;old_error=0;plain_expected=0;
     @(negedge clk);if(out_i!==0 || valid) $fatal(1,"FAIL: clear priority");
   end
 endtask
 integer n;
 initial begin
   $dumpfile("tb_pid_integral_decay.vcd");$dumpvars(0,tb_pid_integral_decay);
   repeat(3) @(negedge clk);rst_n=1;
   step(8*Q,8*Q);step(0,6*Q);step(2*Q,9*Q/2);step(-2*Q,27*Q/8);
   step(2*Q+1,43*Q/8+1); // immediately outside band resumes accumulation
   reset_i;
   step(-8*Q,-8*Q);step(0,-6*Q);step(-2*Q,-9*Q/2);step(2*Q,-27*Q/8);
   reset_i;
   actual=100*Q;step(3*Q,3*Q);step(Q/2,9*Q/4); // live target, not absolute position
   reset_i;actual=0;
   step(16*Q,16*Q);step(3*Q,16*Q);step(0,12*Q); // limit then decay
   for(n=0;n<60;n=n+1) begin
     wide=$signed(out_i)*3;step(0,wide/4);
   end
   if(out_i!==0) $fatal(1,"FAIL: positive quantization residue");
   reset_i;step(-16*Q,-16*Q);
   for(n=0;n<60;n=n+1) begin
     wide=$signed(out_i)*3;step(0,wide/4);
   end
   if(out_i!==0) $fatal(1,"FAIL: negative quantization residue");
   rst_n=0;#1;if(out_i!==0 || valid) $fatal(1,"FAIL: reset");
   $display("TEST PASSED: tb_pid_integral_decay");$finish;
 end
 initial begin #100000;$fatal(1,"FAIL: timeout");end
endmodule
