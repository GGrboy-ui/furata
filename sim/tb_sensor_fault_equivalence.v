`timescale 1ns/1ps
module tb_sensor_fault_equivalence;
 reg clk=0,rst_n=0,dout=0,fake_busy=0,fake_valid=0;reg [11:0] fake_data=0;
 wire cs_n,sclk,din,sample_valid,ready;wire [11:0] sample;wire [3:0] error_code;
 sensor_if #(.CLK_HZ(100000),.RAIL_LIMIT_SAMPLES(3)) dut(.*);
 always #5 clk=~clk;
 always @(posedge clk) if(rst_n) begin #1;
  if(error_code!==(dut.frame_age>=500 ? 4'd5:dut.age>=500 ? 4'd3:dut.rails>=3 ? 4'd4:4'd0))$fatal(1,"FAIL: fault cycle changed");
 end
 task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
 task sample_value;input [11:0] x;begin fake_data=x;fake_valid=1;clocks(1);fake_valid=0;clocks(2);end endtask
 initial begin
  $dumpfile("tb_sensor_fault_equivalence.vcd");$dumpvars(1,tb_sensor_fault_equivalence);
  force dut.busy=fake_busy;force dut.adc_valid=fake_valid;force dut.adc_data=fake_data;
  clocks(3);rst_n=1;clocks(510);if(error_code!=3)$fatal(1,"FAIL: age timeout");
  sample_value(1000);sample_value(0);sample_value(0);sample_value(0);if(error_code!=4)$fatal(1,"FAIL: rails");
  sample_value(1000);fake_busy=1;clocks(510);if(error_code!=5)$fatal(1,"FAIL: SPI timeout priority");
  fake_busy=0;sample_value(1000);if(error_code!=0)$fatal(1,"FAIL: recovery");
  $display("TEST PASSED: tb_sensor_fault_equivalence (exact timeout/rail cycles, priorities and recovery)");$finish;
 end
endmodule
