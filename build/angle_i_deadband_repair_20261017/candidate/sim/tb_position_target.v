`timescale 1ns/1ps
module tb_position_target;
 reg clk=0,rst_n=0,enable=0,tick_ms=0; reg [2:0] move_cmd=0;
 wire signed [31:0] goal_q,target_q,rev_goal,rev_target;
 reg signed [31:0] last_q; integer i;
 position_target #(.POSITION_LIMIT_COUNTS(500)) dut(
   .clk(clk),.rst_n(rst_n),.enable(enable),.tick_ms(tick_ms),.move_cmd(move_cmd),.goal_q(goal_q),.target_q(target_q));
 position_target #(.POSITION_LIMIT_COUNTS(500),.CW_POSITIVE(0)) reverse(
   .clk(clk),.rst_n(rst_n),.enable(enable),.tick_ms(tick_ms),.move_cmd(move_cmd),.goal_q(rev_goal),.target_q(rev_target));
 always #5 clk=~clk;
 task command; input [2:0] c;
   begin @(negedge clk); move_cmd=c; @(negedge clk); move_cmd=0; end
 endtask
 task tick;
   begin
     last_q=target_q;
     @(negedge clk); tick_ms=1; @(negedge clk); tick_ms=0;
     if(target_q-last_q>2228 || last_q-target_q>2228) $fatal(1,"FAIL: trajectory rate limit");
     if(target_q!==-rev_target || goal_q!==-rev_goal) $fatal(1,"FAIL: CW polarity parameter");
   end
 endtask
 initial begin
   $dumpfile("tb_position_target.vcd"); $dumpvars(0,tb_position_target);
   repeat(2) @(negedge clk); rst_n=1;
   command(1); if(goal_q!==0) $fatal(1,"FAIL: accepted movement while disabled");
   enable=1; command(1);
   if(goal_q!==742741 || target_q!==0) $fatal(1,"FAIL: 10 degrees must retain fractional counts");
   repeat(340) tick;
   if(target_q!==742741) $fatal(1,"FAIL: small move did not arrive exactly");
   command(2); repeat(340) tick;
   if(goal_q!==0 || target_q!==0) $fatal(1,"FAIL: opposite moves must cancel");
   command(4);
   if(goal_q!==26738688) $fatal(1,"FAIL: full turn wrapped or has wrong count");
   repeat(12010) tick;
   if(target_q!==26738688) $fatal(1,"FAIL: full turn target did not finish");
   command(3); command(7);
   if(goal_q!==26738688) $fatal(1,"FAIL: simultaneous commands were accepted");
   command(4);
   if(goal_q!==32768000) $fatal(1,"FAIL: positive travel limit");
   for(i=0;i<100;i=i+1) command(2);
   if(goal_q!==-32768000) $fatal(1,"FAIL: negative travel limit");
   enable=0; @(negedge clk);
   if(goal_q!==0 || target_q!==0) $fatal(1,"FAIL: stop/fault did not cancel target");
   enable=1;
   for(i=0;i<36;i=i+1) command(1);
   if(goal_q!==26738676) $fatal(1,"FAIL: repeated 10 degree moves lost fractions");
   rst_n=0; #1;
   if(goal_q!==0 || target_q!==0) $fatal(1,"FAIL: target reset");
   $display("TEST PASSED: tb_position_target"); $finish;
 end
 initial begin #1000000; $fatal(1,"FAIL: target test timeout"); end
endmodule
