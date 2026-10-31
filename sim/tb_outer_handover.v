`timescale 1ns/1ps
module tb_outer_handover;
 reg clk=0,rst_n=0,clear=0,tick_ms=0,start=0;always #5 clk=~clk;
 reg signed [31:0] position_out=6553600,speed_out=-1572864;
 reg [15:0] friction_t=200;wire [7:0] remaining_ms;wire signed [31:0] out_q;wire [15:0] applied_t;
 integer i,saved;
 outer_handover dut(.*);
 task ms;begin tick_ms=1;@(negedge clk);tick_ms=0;repeat(300)@(negedge clk);end endtask
 initial begin
  $dumpfile("tb_outer_handover.vcd");$dumpvars(1,tb_outer_handover);
  repeat(3)@(negedge clk);rst_n=1;start=1;@(negedge clk);start=0;
  if(out_q!=position_out||remaining_ms!=200||applied_t!=0)$fatal(1,"FAIL: seamless capture");
  saved=out_q;
  for(i=1;i<=200;i=i+1)begin ms;if(remaining_ms!=200-i||applied_t!=i||out_q>saved)$fatal(1,"FAIL: handover step %0d",i);saved=out_q;end
  if(out_q!=speed_out)$fatal(1,"FAIL: transfer endpoint");
  start=1;@(negedge clk);start=0;tick_ms=1;@(negedge clk);tick_ms=0;repeat(5)@(negedge clk);clear=1;repeat(3)@(negedge clk);clear=0;repeat(300)@(negedge clk);
  if(out_q!=0||remaining_ms!=0||applied_t!=0)$fatal(1,"FAIL: cancel stale division");
  $display("TEST PASSED: tb_outer_handover (200ms, target continuity, friction ramp, inherited position range, cancellation)");$finish;
 end
 initial begin #2000000;$fatal(1,"FAIL: handover timeout");end
endmodule
