`timescale 1ns/1ps
module tb_key_input;
 reg clk=0,rst_n=0; reg [3:0] key_n=4'b1110;
 wire [3:0] press; integer n0=0,n1=0,n2=0,n3=0;
 key_input #(.DEBOUNCE_CYCLES(4)) dut(.clk(clk),.rst_n(rst_n),.key_n(key_n),.press(press));
 always #5 clk=~clk;
 always @(posedge clk) begin
   #1;
   if(press[0]) n0=n0+1;
   if(press[1]) n1=n1+1;
   if(press[2]) n2=n2+1;
   if(press[3]) n3=n3+1;
 end
 task cycles; input integer n; integer i;
   begin for(i=0;i<n;i=i+1) @(negedge clk); end
 endtask
 initial begin
   $dumpfile("tb_key_input.vcd"); $dumpvars(0,tb_key_input);
   cycles(2); rst_n=1; cycles(20);
   if(n0!=0) $fatal(1,"FAIL: held key started on reset release");
   key_n=4'hf; cycles(10);
   key_n[0]=0; cycles(2); key_n[0]=1; cycles(2);
   key_n[0]=0; cycles(2); key_n[0]=1; cycles(10);
   if(n0!=0) $fatal(1,"FAIL: contact bounce generated a press");
   key_n[0]=0; cycles(30);
   if(n0!=1) $fatal(1,"FAIL: long press must trigger once");
   key_n[0]=1; cycles(2); key_n[0]=0; cycles(20);
   if(n0!=1) $fatal(1,"FAIL: release bounce re-armed key");
   key_n[0]=1; cycles(10); key_n[0]=0; cycles(10);
   if(n0!=2) $fatal(1,"FAIL: stable release did not re-arm");
   key_n=4'b0000; cycles(12);
   if(n0!=2 || n1!=1 || n2!=1 || n3!=1) $fatal(1,"FAIL: independent keys");
   rst_n=0; cycles(2); rst_n=1; cycles(20);
   if(n0!=2 || n1!=1 || n2!=1 || n3!=1) $fatal(1,"FAIL: reset while held");
   $display("TEST PASSED: tb_key_input"); $finish;
 end
 initial begin #10000; $fatal(1,"FAIL: key test timeout"); end
endmodule
