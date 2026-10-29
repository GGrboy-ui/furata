`timescale 1ns/1ps
module decay_percent_case #(
 parameter integer PERCENT=30, FIRST=322122547, SECOND=96636764
)(output reg done=0);
 reg clk=0,rst_n=0,clear=0,tick=0;
 reg signed [31:0] target=0;
 wire signed [31:0] result;
 wire valid;
 always #5 clk=~clk;
 pid_fixed #(.KP(0),.KI(65536),.KD(0),.OUT_LIMIT(2147483647),
   .I_LIMIT(1073741824),.I_DECAY_BAND_Q(131072),
   .I_DECAY_RETAIN_PERCENT(PERCENT)) dut (
   .clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),
   .target_q(target),.actual_q(32'sd0),.out_q(result),.valid(valid));
 task step;
   input signed [31:0] error_value,expected;
   begin
     @(negedge clk);target=error_value;tick=1;
     @(negedge clk);tick=0;
     @(posedge clk);#1;
     if(!valid || result!==expected)
       $fatal(1,"FAIL: retain=%0d error=%0d result=%0d expected=%0d",PERCENT,error_value,result,expected);
     repeat(3) @(negedge clk);
     if(result!==expected) $fatal(1,"FAIL: decay without tick");
   end
 endtask
 initial begin
   repeat(3) @(negedge clk);rst_n=1;
   step(1073741824,1073741824); // maximum stored I detects product overflow
   step(131072,FIRST);step(-131072,SECOND); // inclusive boundaries, no new error
   @(negedge clk);clear=1;
   @(negedge clk);clear=0;
   step(-1073741824,-1073741824);
   step(-131072,-FIRST);step(131072,-SECOND); // exact sign symmetry
   done=1;
 end
endmodule

module tb_pid_integral_decay_percent;
 wire [6:0] done;
 decay_percent_case #(0,0,0) p0(done[0]);
 decay_percent_case #(30,322122547,96636764) p30(done[1]);
 decay_percent_case #(50,536870912,268435456) p50(done[2]);
 decay_percent_case #(75,805306368,603979776) p75(done[3]);
 decay_percent_case #(100,1073741824,1073741824) p100(done[4]);
 decay_percent_case #(-10,0,0) below_range(done[5]);
 decay_percent_case #(110,1073741824,1073741824) above_range(done[6]);
 initial begin
   $dumpfile("tb_pid_integral_decay_percent.vcd");$dumpvars(0,tb_pid_integral_decay_percent);
   wait(&done);$display("TEST PASSED: tb_pid_integral_decay_percent");$finish;
 end
 initial begin #100000;$fatal(1,"FAIL: timeout");end
endmodule
