`timescale 1ns/1ps
module tb_position_period;
 reg clk=0,rst_n=0,request=0,allowed=1,update=0;
 reg [2:0] state=0;reg [15:0] requested=50;
 wire [15:0] actual;wire pending,reply;wire [7:0] code;
 position_period dut(.clk(clk),.rst_n(rst_n),.request(request),.allowed(allowed),.position_update(update),
  .control_state(state),.requested_ms(requested),.actual_ms(actual),.pending(pending),.reply(reply),.code(code));
 always #5 clk=~clk;
 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task set_period;input integer n;begin requested=n;request=1;cycles(1);request=0;end endtask
 initial begin
  $dumpfile("tb_position_period.vcd");$dumpvars(0,tb_position_period);
  cycles(3);rst_n=1;cycles(2);if(actual!=50)$fatal(1,"FAIL: default");
  set_period(1);if(actual!=1||code!=4)$fatal(1,"FAIL: minimum");
  set_period(1000);if(actual!=1000)$fatal(1,"FAIL: maximum");
  set_period(0);if(actual!=1000||code!=18)$fatal(1,"FAIL: zero accepted");
  set_period(1001);if(actual!=1000||code!=18)$fatal(1,"FAIL: overflow accepted");
  state=4;set_period(20);cycles(30);if(actual!=1000||!pending)$fatal(1,"FAIL: applied before boundary");
  update=1;cycles(1);update=0;if(actual!=20||pending||code!=4)$fatal(1,"FAIL: boundary apply");
  set_period(100);cycles(2);update=1;cycles(1);update=0;if(actual!=100)$fatal(1,"FAIL: longer boundary");
  state=0;cycles(2);state=4;cycles(2);if(actual!=100)$fatal(1,"FAIL: STOP lost period");
  allowed=0;set_period(5);if(actual!=100||code!=17)$fatal(1,"FAIL: locked state");
  rst_n=0;cycles(1);if(actual!=50)$fatal(1,"FAIL: system reset");
  $display("TEST PASSED: tb_position_period");$finish;
 end
endmodule
