`timescale 1ns/1ps
module tb_angle_display_data;
    reg clk=0, rst_n=0, valid=0, ready=0, raw=0;
    reg [11:0] sample=2098;
    reg [3:0] sensor_fault=0, fault=0;
    reg [2:0] state=0;
    wire [63:0] segments, inverted_segments;
    wire signed [15:0] angle, inverted_angle;
    wire [11:0] adc, inverted_adc;
    wire angle_valid, inverted_valid;
    angle_display_data #(.AVERAGE_LOG2(0)) dut (
        .clk(clk),.rst_n(rst_n),.sample(sample),.sample_valid(valid),.sample_ready(ready),
        .sensor_fault(sensor_fault),.control_state(state),.fault_code(fault),.raw_mode(raw),
        .segments(segments),.angle_tenths(angle),.display_adc(adc),.angle_valid(angle_valid));
    angle_display_data #(.ADC_ZERO(2000),.ADC_SPAN(4000),.INVERT(1),.AVERAGE_LOG2(0)) inverse (
        .clk(clk),.rst_n(rst_n),.sample(sample),.sample_valid(valid),.sample_ready(ready),
        .sensor_fault(sensor_fault),.control_state(state),.fault_code(fault),.raw_mode(raw),
        .segments(inverted_segments),.angle_tenths(inverted_angle),
        .display_adc(inverted_adc),.angle_valid(inverted_valid));
    reg avg_valid=0;
    reg [11:0] avg_sample=1000;
    wire [63:0] avg_segments;
    wire signed [15:0] avg_angle;
    wire [11:0] avg_adc;
    wire avg_ready;
    angle_display_data #(.ADC_ZERO(1000),.ADC_SPAN(1000),.RANGE_TENTHS(1000),.AVERAGE_LOG2(2)) averaged (
        .clk(clk),.rst_n(rst_n),.sample(avg_sample),.sample_valid(avg_valid),.sample_ready(ready),
        .sensor_fault(4'd0),.control_state(3'd0),.fault_code(4'd0),.raw_mode(1'b0),
        .segments(avg_segments),.angle_tenths(avg_angle),.display_adc(avg_adc),.angle_valid(avg_ready));
    always #5 clk=~clk;
    integer i, expected, difference, inv_expected, errors=0;
    task cycles; input integer n; integer k; begin repeat(n) @(negedge clk); end endtask
    task send_sample; input [11:0] value; begin
        @(negedge clk); sample=value; valid=1;
        @(negedge clk); valid=0; cycles(65);
    end endtask
    initial begin
        $dumpfile("tb_angle_display_data.vcd");
        $dumpvars(0,clk,rst_n,sample,segments,angle,adc,angle_valid,avg_angle,avg_adc);
        cycles(3); rst_n=1; cycles(3);
        if (segments[39:0]!=={5{8'hbf}} || angle_valid) $fatal(1,"FAIL: unsampled input looks valid");
        ready=1;
        // Exhaustive ADC range: independent arithmetic oracle checks the serial
        // divider, rounding, signed direction and BCD conversion for every code.
        for(i=0;i<4096;i=i+1) begin
            send_sample(i);
            difference=i-2098;
            expected=((difference<0 ? -difference : difference)*3330+2047)/4095;
            if(difference<0) expected=-expected;
            difference=i-2000;
            inv_expected=((difference<0 ? -difference : difference)*3330+2000)/4000;
            if(difference>=0) inv_expected=-inv_expected;
            if(angle!==expected || adc!==i || inverted_angle!==inv_expected) begin
                $display("FAIL: ADC=%0d angle=%0d/%0d inverse=%0d/%0d",i,angle,expected,inverted_angle,inv_expected);
                errors=errors+1;
            end
            if(dut.bcd_adc!==( ((i/1000)<<12) | (((i/100)%10)<<8) | (((i/10)%10)<<4) | (i%10)))
                $fatal(1,"FAIL: raw ADC decimal conversion at %0d",i);
            if(angle_valid!==(i!=0 && i!=4095)) $fatal(1,"FAIL: rail validity at %0d",i);
        end
        send_sample(2098);
        if(segments!==64'hc0c0ffffc0c040c0) $fatal(1,"FAIL: zero glyph, sign or decimal point: %h",segments);
        send_sample(991);
        if(angle!==-16'sd900 || segments!==64'hc0c0ffbfc09040c0)
            $fatal(1,"FAIL: -90.0 degree rendering: %h",segments);
        raw=1; send_sample(3205);
        if(segments!==64'hc0c0ffffb0a4c092) $fatal(1,"FAIL: decimal ADC 3205 rendering: %h",segments);
        raw=0; state=5; fault=4; sensor_fault=4; cycles(2);
        if(angle_valid || segments!==64'h9299ffbfbfbfbfbf) $fatal(1,"FAIL: fault display/invalid angle: %h",segments);
        raw=1; send_sample(0);
        if(segments!==64'h9299ffffc0c0c0c0) $fatal(1,"FAIL: raw rail diagnosis hidden: %h",segments);
        sensor_fault=0; state=0; fault=0;
        // Averaging must not publish a partial window; average is exactly 1001.
        for(i=0;i<4;i=i+1) begin
            @(negedge clk); avg_sample=(i==3) ? 1004 : 1000; avg_valid=1;
            @(negedge clk); avg_valid=0; cycles(2);
            if(i<3 && avg_ready) $fatal(1,"FAIL: partial average was displayed");
        end
        cycles(65);
        if(avg_adc!==1001 || avg_angle!==1 || !avg_ready) $fatal(1,"FAIL: four-sample display average");
        rst_n=0; #1;
        if(angle_valid || segments[39:0]!=={5{8'hbf}}) $fatal(1,"FAIL: reset retained stale angle");
        if(errors!=0) $fatal(1,"FAIL: %0d arithmetic errors",errors);
        $display("TEST PASSED: tb_angle_display_data (4096 ADC codes, calibration, sign, averaging, faults)");
        $finish;
    end
    initial begin #5000000; $fatal(1,"FAIL: angle display timeout"); end
endmodule
