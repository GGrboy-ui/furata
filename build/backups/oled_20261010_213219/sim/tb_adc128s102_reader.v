`timescale 1ns/1ps
module tb_adc128s102_reader;
  reg clk=0,rst_n=0,start=0,dout=0; reg [2:0] channel=3'd0;
  wire cs_n,sclk,din,busy; wire [11:0] data; wire valid;
  adc128s102_reader #(.HALF_DIV(1)) dut(.clk(clk),.rst_n(rst_n),.start(start),.channel(channel),.dout(dout),.cs_n(cs_n),.sclk(sclk),.din(din),.busy(busy),.data(data),.valid(valid));
  always #5 clk=~clk;
  reg [15:0] shreg; integer bitn=0,frames=0,errors=0;
  reg [15:0] command_bits=0;
  integer command_clocks=0;
  always @(negedge cs_n) begin command_bits=0; command_clocks=0; end
  always @(posedge sclk) if(!cs_n) begin
    command_bits={command_bits[14:0],din}; command_clocks=command_clocks+1;
  end
  always @(posedge cs_n) if(rst_n && command_clocks==16) begin
    if(command_bits[13:11]!==channel) begin
      $display("FAIL: channel address bits: %h (channel %0d)",command_bits,channel); errors=errors+1;
    end
    frames=frames+1;
  end
  // Return a deterministic result on each 16-clock frame. DOUT is changed before
  // the reader's rising sample edge, so the bit order is independently observable.
  always @(negedge sclk or posedge cs_n) begin
    if(cs_n) begin bitn=0; shreg=16'h0000; end
    else begin
      if(bitn==0) shreg=16'h0A5C;
      dout <= shreg[15-bitn];
      if(bitn<16) bitn=bitn+1;
    end
  end
  initial begin
    $dumpfile("tb_adc128s102_reader.vcd"); $dumpvars(0,tb_adc128s102_reader);
    #17 rst_n=1; #13; channel=3'd5;
    @(negedge clk); start=1; @(negedge clk); start=0;
    wait(valid); #1;
    if(data!==12'hA5C) begin $display("FAIL: ADC data/bit order=%h",data); errors=errors+1; end
    if(cs_n!==1'b1 || busy) begin $display("FAIL: frame did not terminate cleanly"); errors=errors+1; end
    if(frames!=2) begin $display("FAIL: expected two complete ADC frames"); errors=errors+1; end
    // reset must interrupt an active frame and return safe bus levels
    @(negedge clk); start=1; @(negedge clk); start=0;
    #20; rst_n=0; #1;
    if(cs_n!==1'b1 || sclk!==1'b1 || busy) begin $display("FAIL: reset did not abort frame"); errors=errors+1; end
    if(errors==0) $display("TEST PASSED: tb_adc128s102_reader"); else $display("TEST FAILED: tb_adc128s102_reader (%0d error(s))",errors);
    $finish;
  end
  initial begin
    #100000;
    $display("TEST FAILED: tb_adc128s102_reader (timeout)");
    $finish;
  end
endmodule
