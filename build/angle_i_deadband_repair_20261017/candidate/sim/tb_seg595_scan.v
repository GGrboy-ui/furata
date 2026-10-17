`timescale 1ns/1ps
module tb_seg595_scan;
    reg clk=0,rst_n=0;
    reg [63:0] segments=64'h0123456789abcdef;
    wire sclk,rclk,dio;
    seg595_scan #(.CLK_HZ(100000),.SERIAL_HZ(10000)) dut (
        .clk(clk),.rst_n(rst_n),.segments(segments),.sclk(sclk),.rclk(rclk),.dio(dio));
    always #5 clk=~clk;
    reg [15:0] shifted=0;
    integer bits=0,words=0,on_words=0,expected_digit=0;
    reg [63:0] expected_frame=64'h0123456789abcdef;
    reg [15:0] expected_word;
    time latch_start;
    always @(posedge sclk) if(rst_n) begin shifted={shifted[14:0],dio}; bits=bits+1; end
    always @(dio) if(rst_n && sclk) $fatal(1,"FAIL: serial data changed while SCLK high");
    always @(posedge rclk) if(rst_n) begin
        latch_start=$time;
        if(bits!=16) $fatal(1,"FAIL: latch after %0d clocks",bits);
        if((words%2)==0) begin
            if(shifted!==16'hff00) $fatal(1,"FAIL: missing blank transfer: %h",shifted);
        end else begin
            if(expected_digit==0) expected_frame=segments;
            expected_word={expected_frame[expected_digit*8+:8],(8'b1<<expected_digit)};
            if(shifted!==expected_word) $fatal(1,"FAIL: serial word %h expected %h",shifted,expected_word);
            // Change the entire display mid-frame. Remaining digits must use
            // the previous snapshot until digit 0 starts the next frame.
            if(on_words==3) segments=64'hfedcba9876543210;
            expected_digit=(expected_digit+1)%8; on_words=on_words+1;
        end
        words=words+1; bits=0; shifted=0;
    end
    always @(negedge rclk) if(rst_n && words!=0)
        if($time-latch_start<50) $fatal(1,"FAIL: RCLK pulse too narrow");
    initial begin
        $dumpfile("tb_seg595_scan.vcd"); $dumpvars(0,tb_seg595_scan);
        repeat(3) @(negedge clk); rst_n=1;
        wait(on_words>=24); @(negedge clk); rst_n=0; #1;
        if(sclk!==0 || rclk!==0 || dio!==0) $fatal(1,"FAIL: reset did not idle display bus");
        $display("TEST PASSED: tb_seg595_scan (wire bit order, polarity, blanking, frame snapshot, pulse width)");
        $finish;
    end
    initial begin #200000; $fatal(1,"FAIL: serializer timeout"); end
endmodule
