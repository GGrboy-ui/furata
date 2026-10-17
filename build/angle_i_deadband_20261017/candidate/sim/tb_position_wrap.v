`timescale 1ns/1ps
module tb_position_wrap;
 reg clk=0,rst_n=0;
 reg signed [49:0] value_q=0;
 wire signed [31:0] wrapped_q;
 wire valid;
 position_wrap #(.COUNTS_PER_REV(408)) dut(.clk(clk),.rst_n(rst_n),.value_q(value_q),.wrapped_q(wrapped_q),.valid(valid));
 reg signed [31:0] derivative_target=0;
 reg tick=0,clear=1;
 wire signed [31:0] derivative;
 pid_fixed #(.KP(0),.KI(0),.KD(65536),.DELTA_WRAP_Q(408*65536)) dpid (
   .clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),.target_q(derivative_target),.actual_q(32'sd0),.out_q(derivative));
 always #5 clk=~clk;
 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task check;input signed [49:0] v;input signed [31:0] expected;
   begin value_q=v;cycles(120);if(!valid || wrapped_q!==expected)
     $fatal(1,"FAIL: modulo input=%0d got=%0d expected=%0d",v,wrapped_q,expected);end
 endtask
 task derivative_tick;input signed [31:0] v;begin derivative_target=v;tick=1;cycles(1);tick=0;cycles(3);end endtask
 initial begin
   $dumpfile("tb_position_wrap.vcd");$dumpvars(0,tb_position_wrap);
   cycles(3);rst_n=1;
   check(0,0);check(408*50'sd65536,0);check(-408*50'sd65536,0);
   check(409*50'sd65536,65536);check(-409*50'sd65536,-65536);
   check(203*50'sd65536,203*65536);check(204*50'sd65536,-204*65536);
   check(-204*50'sd65536,-204*65536);check(-205*50'sd65536,203*65536);
   check(408*50'sd65536+32768,32768);check(-408*50'sd65536-32768,-32768);
   check(408*50'sd65536*10000+65536,65536);
   check(-408*50'sd65536*10000-65536,-65536);
   // Latest input wins after a division that was already in flight.
   value_q=99*65536;cycles(10);value_q=-77*65536;cycles(120);
   if(wrapped_q!==-77*65536) $fatal(1,"FAIL: changed input lost during division");
   clear=0;derivative_tick(203*65536);derivative_tick(-204*65536);
   if(derivative!==65536) $fatal(1,"FAIL: positive boundary generated one-turn derivative kick");
   derivative_tick(203*65536);
   if(derivative!==-65536) $fatal(1,"FAIL: negative boundary generated derivative kick");
   rst_n=0;cycles(2);if(valid || wrapped_q!==0) $fatal(1,"FAIL: reset");
   $display("TEST PASSED: tb_position_wrap (turns, boundaries, fractions, updates and circular derivative)");$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: modulo timeout");end
endmodule
