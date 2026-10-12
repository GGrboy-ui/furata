`timescale 1ns/1ps
// Independent Q16.16 reference: expected = clamp((KP*e + KI*sum(e))/2^16).
// The DUT's internal integral and derivative registers are not read by this test.
module tb_pid_fixed;
  reg clk=0,rst_n=0,clear=0,tick=0; reg signed [31:0] target=0,actual=0;
  wire signed [31:0] out; wire valid; integer errors=0;
  pid_fixed #(.KP(32'sd65536),.KI(32'sd32768),.KD(32'sd0),.OUT_LIMIT(32'sd131072),.I_LIMIT(32'sd262144)) dut(.clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),.target_q(target),.actual_q(actual),.out_q(out),.valid(valid));
  always #5 clk=~clk;
  task step; begin
    tick=1; @(posedge clk); #1; tick=0;
    if(valid!==1'b0) begin $display("FAIL: PID output updated before pipeline completed"); errors=errors+1; end
    @(posedge clk); #1;
    if(valid!==1'b1) begin $display("FAIL: PID valid missing after pipeline completed"); errors=errors+1; end
  end endtask
  initial begin
    $dumpfile("tb_pid_fixed.vcd"); $dumpvars(0,tb_pid_fixed);
    #12 rst_n=1; target=32'sd65536; actual=0; step;
    if(out!==32'sd98304 || !valid) begin $display("FAIL: first PID output=%0d",out); errors=errors+1; end
    step;
    if(out!==32'sd131072) begin $display("FAIL: output saturation/integral=%0d",out); errors=errors+1; end
    actual=32'sd262144; step;
    if(out!==-32'sd131072) begin $display("FAIL: negative output clamp=%0d",out); errors=errors+1; end
    clear=1; @(posedge clk); #1; clear=0;
    if(out!==0) begin $display("FAIL: clear did not zero output"); errors=errors+1; end
    if(errors==0) $display("TEST PASSED: tb_pid_fixed"); else $display("TEST FAILED: tb_pid_fixed (%0d error(s))",errors);
    $finish;
  end
endmodule
