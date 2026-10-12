`timescale 1ns/1ps
module tb_safety_monitor;
 reg clk=0,rst_n=0,clear_fault=0,running=0;
 reg [3:0] internal_fault=0;
 wire permit,latched; wire [3:0] code; integer errors=0;
 safety_monitor dut(.clk(clk),.rst_n(rst_n),.clear_fault(clear_fault),.running(running),
   .internal_fault(internal_fault),.permit(permit),.latched(latched),.code(code));
 always #5 clk=~clk;
 task cycles; input integer n; integer i;
   begin for(i=0;i<n;i=i+1) begin @(posedge clk); #1; end end
 endtask
 initial begin
   $dumpfile("tb_safety_monitor.vcd"); $dumpvars(0,tb_safety_monitor);
   cycles(2);
   if(permit!==0 || latched!==0 || code!==0) begin $display("FAIL: reset state"); errors=errors+1; end
   @(negedge clk); rst_n=1; cycles(2);
   if(permit!==0) begin $display("FAIL: startup hold too short"); errors=errors+1; end
   cycles(1);
   if(permit!==1) begin $display("FAIL: permit did not release after startup"); errors=errors+1; end
   @(negedge clk); running=1; internal_fault=4'd4; cycles(1);
   if(latched!==1 || code!==4 || permit!==0) begin $display("FAIL: internal fault not latched"); errors=errors+1; end
   @(negedge clk); internal_fault=0; clear_fault=1; cycles(2);
   if(latched!==1 || code!==4 || permit!==0) begin $display("FAIL: running clear removed latch"); errors=errors+1; end
   @(negedge clk); running=0; internal_fault=4'd6; cycles(2);
   if(latched!==1 || code!==6 || permit!==0) begin $display("FAIL: active fault lost priority over clear"); errors=errors+1; end
   @(negedge clk); clear_fault=0; internal_fault=0; cycles(2);
   if(latched!==1 || permit!==0) begin $display("FAIL: latch cleared without command"); errors=errors+1; end
   @(negedge clk); clear_fault=1; cycles(1);
   if(latched!==0 || code!==0 || permit!==1) begin $display("FAIL: stopped clear did not re-arm"); errors=errors+1; end
   @(negedge clk); clear_fault=0; rst_n=0; #1;
   if(permit!==0 || latched!==0 || code!==0) begin $display("FAIL: asynchronous reset"); errors=errors+1; end
   if(errors==0) $display("TEST PASSED: tb_safety_monitor"); else $fatal(1,"TEST FAILED: tb_safety_monitor (%0d error(s))",errors);
   $finish;
 end
 initial begin #10000; $fatal(1,"FAIL: safety test timeout"); end
endmodule
