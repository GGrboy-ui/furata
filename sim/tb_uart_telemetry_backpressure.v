`timescale 1ns/1ps
module tb_uart_telemetry_backpressure;
    reg clk=0,rst_n=0,received_valid=0,tx_ready=0;
    reg [7:0] received_byte=0;
    reg signed [15:0] angle=16'sd1,requested=16'sd42,actual=-16'sd42;
    wire [7:0] tx_data;
    wire tx_valid, frame_active;
    reg [247:0] frames[0:3],line=0;
    integer count=0, bytes=0;
    uart_telemetry #(.CLK_HZ(100000)) dut (
        .clk(clk),.rst_n(rst_n),.received_byte(received_byte),.received_valid(received_valid),
        .angle_tenths(angle),.angle_valid(1'b1),.requested_pwm(requested),.actual_pwm(actual),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),.frame_active(frame_active));
    always #5 clk=~clk;
    always @(posedge clk) if(tx_valid && tx_ready) begin
        line={line[239:0],tx_data}; bytes=bytes+1;
        if(tx_data==10) begin
            if(bytes!=31) $fatal(1,"FAIL: stalled frame length");
            frames[count]=line; count=count+1; bytes=0; line=0;
        end
    end
    task cycles; input integer n; integer k;
        begin for(k=0;k<n;k=k+1) @(negedge clk); end
    endtask
    task command; input [7:0] value;
        begin received_byte=value; received_valid=1; cycles(1); received_valid=0; end
    endtask
    initial begin
        $dumpfile("tb_uart_telemetry_backpressure.vcd"); $dumpvars(0,tb_uart_telemetry_backpressure);
        cycles(4);rst_n=1;cycles(4);command("P");
        wait(tx_valid);cycles(1000);
        if(tx_data!=="T" || dut.byte_index!==0 || dut.sequence_q!==3)
            $fatal(1,"FAIL: backpressure stability/sequence gaps");
        angle=-16'sd9999;requested=-16'sd2500;actual=16'sd2500;
        tx_ready=1;wait(count==1);cycles(2);
        if(frames[0]!=={"T,00000000,+000.1,+0042,-0042",8'h0d,8'h0a})
            $fatal(1,"FAIL: stalled snapshot changed");
        wait(count==2);cycles(2);command("Q");cycles(1000);
        if(frames[1]!=={"T,00000003,-999.9,-2500,+2500",8'h0d,8'h0a} || count!=2)
            $fatal(1,"FAIL: overload gap or boundary encoding");
        $display("TEST PASSED: tb_uart_telemetry_backpressure (stable bytes, snapshot, busy gaps, signed limits)");
        $finish;
    end
    initial begin #100000; $fatal(1,"FAIL: backpressure timeout"); end
endmodule
