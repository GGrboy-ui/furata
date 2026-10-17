`timescale 1ns/1ps
module tb_acg720_top;
 reg clk=0,rst_n=0,uart_rx=1,enc_a=0,enc_b=0,board_adc_dout=0;
 wire uart_tx,pwm_a,ain1,ain2,stby_fpga,dbg_tick,board_adc_cs_n,board_adc_din,board_adc_sclk;
 integer errors=0;
 acg720_top #(.CLK_HZ(100000),.PWM_HZ(1000),.ADC_HALF_DIV(1),.SWING_TIMEOUT_MS(100)) dut(
   .clk(clk),.rst_n(rst_n),.uart_rx(uart_rx),.enc_a(enc_a),.enc_b(enc_b),
   .key1_n(1'b1),.key2_n(1'b1),.key3_n(1'b1),.key4_n(1'b1),
   .board_adc_dout(board_adc_dout),.uart_tx(uart_tx),.pwm_a(pwm_a),.ain1(ain1),.ain2(ain2),.stby_fpga(stby_fpga),
   .dbg_tick(dbg_tick),.board_adc_cs_n(board_adc_cs_n),.board_adc_din(board_adc_din),.board_adc_sclk(board_adc_sclk));
 always #5 clk=~clk;
 task cycles; input integer n; integer i; begin for(i=0;i<n;i=i+1) @(posedge clk); end endtask
 initial begin
   $dumpfile("tb_acg720_top.vcd"); $dumpvars(0,tb_acg720_top);
   cycles(3); rst_n=1; cycles(100);
   if(board_adc_cs_n!==1'b1 || board_adc_sclk!==1'b1) begin $display("FAIL: ADC bus not idle after reset"); errors=errors+1; end
   wait(dut.sample_ready); @(negedge clk); force dut.start_cmd=1'b1;
   @(posedge clk); #1; release dut.start_cmd; cycles(3);
   #1;
   if(stby_fpga!==1'b1 || dut.motor_ready!==1'b0 || pwm_a!==1'b0 || ain1!==1'b0 || ain2!==1'b0) begin
     $display("FAIL: STBY must rise before PWM/IN are released"); errors=errors+1;
   end
   cycles(190); #1;
   if(dut.motor_ready!==1'b0 || pwm_a!==1'b0 || ain1!==1'b0 || ain2!==1'b0) begin
     $display("FAIL: motor outputs released before 2 ms wake"); errors=errors+1;
   end
   cycles(20); #1;
   if(stby_fpga!==1'b1 || dut.motor_ready!==1'b1) begin
     $display("FAIL: motor did not become ready after 2 ms wake"); errors=errors+1;
   end
   // Exercise the remaining immediate shutdown paths without external feedback.
   @(negedge clk); force dut.stop_cmd=1'b1; #1;
   if(stby_fpga!==0 || pwm_a!==0 || ain1!==0 || ain2!==0) begin
     $display("FAIL: stop command did not immediately gate motor outputs"); errors=errors+1;
   end
   release dut.stop_cmd;
   force dut.internal_fault=4'd4; #1;
   if(stby_fpga!==1'b0 || dut.motor_ready!==1'b0 || pwm_a!==1'b0 || ain1!==1'b0 || ain2!==1'b0) begin
     $display("FAIL: internal fault did not immediately gate motor outputs"); errors=errors+1;
   end
   force dut.command_q=32'sd2293760; cycles(3); #1;
   if(dut.pwm_command!==-16'sd35) begin $display("FAIL: +35 percent conversion=%0d",dut.pwm_command); errors=errors+1; end
   force dut.command_q=-32'sd2293760; cycles(3); #1;
   if(dut.pwm_command!==16'sd35) begin $display("FAIL: -35 percent conversion=%0d",dut.pwm_command); errors=errors+1; end
   force dut.command_q=32'sd9830400; cycles(3); #1;
   if(dut.pwm_command!==-16'sd100) begin $display("FAIL: command saturation=%0d",dut.pwm_command); errors=errors+1; end
   release dut.command_q;
   cycles(2); #1;
   if(dut.fault_latched!==1 || dut.fault_code!==4) begin
     $display("FAIL: board internal fault did not latch"); errors=errors+1;
   end
   release dut.internal_fault; cycles(2); #1;
   if(stby_fpga!==0 || pwm_a!==0 || ain1!==0 || ain2!==0) begin
     $display("FAIL: outputs restarted after fault removal"); errors=errors+1;
   end
   @(negedge clk); rst_n=0; #1;
   if(stby_fpga!==0 || pwm_a!==0 || ain1!==0 || ain2!==0) begin
     $display("FAIL: reset did not gate motor outputs"); errors=errors+1;
   end
   if(errors==0) $display("TEST PASSED: tb_acg720_top"); else $display("TEST FAILED: tb_acg720_top (%0d error(s))",errors);
   $finish;
 end
 initial begin #1000000; $fatal(1,"FAIL: board test timeout"); end
endmodule
