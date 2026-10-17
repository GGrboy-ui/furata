`timescale 1ns/1ps
module tb_acg720_calibration;
    reg clk=0, rst_n=0;
    reg [3:0] key_n=15;
    reg [7:0] injected_byte=0;
    reg injected_valid=0;
    reg signed [31:0] encoder_position=0;
    wire pwm,stby;
    acg720_top #(.CLK_HZ(100000),.BAUD(10000),.PWM_HZ(1000),
        .KEY_DEBOUNCE_MS(1),.CALIBRATION_BUILD_ID(32'h12345678)) dut (
        .clk(clk),.rst_n(rst_n),.uart_rx(1'b1),.enc_a(1'b0),.enc_b(1'b0),
        .board_adc_dout(1'b0),.key1_n(key_n[0]),.key2_n(key_n[1]),
        .key3_n(key_n[2]),.key4_n(key_n[3]),.pwm_a(pwm),.stby_fpga(stby));
    always #5 clk=~clk;
    // This accelerated model uses 1 kHz PWM. One wait period here is longer
    // than eight periods at the real board's 20 kHz; retain the production 8.
    defparam dut.motor.DEAD_CYCLES=1;
    task cycles(input integer n); integer j; begin
        for(j=0;j<n;j=j+1) @(negedge clk);
    end endtask
    function [7:0] crc_byte(input [7:0] c,input [7:0] b);
        reg [7:0] v; integer k; begin v=c^b;
            for(k=0;k<8;k=k+1) v=v[7] ? (v<<1)^8'h07 : v<<1;
            crc_byte=v;
        end
    endfunction
    function [7:0] hexchar(input [3:0] n);
        begin hexchar=n<10 ? 8'h30+n : 8'h41+n-10; end
    endfunction
    task put(input [7:0] b); begin
        injected_byte=b; injected_valid=1; cycles(1);
        injected_valid=0; cycles(2);
    end endtask
    task frame(input string body); reg [7:0] c; integer j; begin
        c=0; put(8'h21);
        for(j=0;j<body.len();j=j+1) begin put(body[j]); c=crc_byte(c,body[j]); end
        put(8'h2c); put(hexchar(c[7:4])); put(hexchar(c[3:0])); put(8'h0a); cycles(8);
    end endtask
    task resting; integer j; begin
        for(j=0;j<21;j=j+1) begin frame("h,1"); cycles(5000); end
    end endtask
    task off; begin
        if(stby!==0 || pwm!==0) $fatal(1,"FAIL: calibration output not inhibited");
    end endtask
    initial begin
        $dumpfile("tb_acg720_calibration.vcd"); $dumpvars(0,tb_acg720_calibration);
        force dut.received_byte=injected_byte; force dut.received_valid=injected_valid;
        force dut.sample_ready=1'b1; force dut.sample=12'd3000;
        force dut.sample_valid=1'b0; force dut.sensor_fault=4'd0;
        force dut.position=encoder_position;
        cycles(4); rst_n=1; cycles(100500); off;
        put("!"); put("i"); put(10); cycles(100);
        if(!dut.calibration_stream) $fatal(1,"FAIL: capability query did not select calibration stream");
        frame("c,1,408,150,1");
        if(!dut.calibration_session) $fatal(1,"FAIL: session configuration rejected");
        put("S"); key_n[1]=0; cycles(110); key_n[1]=1; cycles(110);
        if(dut.state!==0) $fatal(1,"FAIL: regular start entered during calibration session");
        frame("b,1,1,7,1"); cycles(600);
        if(dut.state!==6 || !dut.core_calibration_test || dut.actual_pwm!==16'sd7 ||
            dut.requested_pwm!==16'sd7 || dut.command_q==32'sd1310720)
            $fatal(1,"FAIL: exact-count path actual=%0d state=%0d phase=%0d result=%0d active=%b session=%b drive=%b command=%0d rest=%0d quiet=%0d",dut.actual_pwm,dut.state,dut.calibration_phase,dut.calibration_result,dut.calibration_active,dut.calibration_session,dut.calibration_drive,dut.command_q,dut.calibration.rest_ms,dut.calibration.quiet_ms);
        encoder_position=2; cycles(12); off; cycles(10);
        if(dut.state!==0 || dut.calibration_result!==1 || !dut.calibration_session)
            $fatal(1,"FAIL: successful test did not return STOP/session");
        cycles(300); off;
        resting; frame("b,1,2,-7,1"); cycles(600);
        if(dut.actual_pwm!==-16'sd7) $fatal(1,"FAIL: negative exact-count path");
        encoder_position=0; cycles(12); off; cycles(10);
        if(dut.calibration_result!==1 || dut.state!==0) $fatal(1,"FAIL: negative completion");
        resting; frame("b,1,3,7,1"); cycles(600);
        put("!"); put("b"); put(","); put("X"); cycles(12); off;
        if(dut.calibration_session || dut.state!==0) $fatal(1,"FAIL: X inside partial frame");
        cycles(100500); frame("c,2,408,150,1"); frame("b,2,1,7,1"); cycles(600);
        encoder_position=18; #1; off; cycles(12);
        if(dut.calibration_result!==5 || dut.calibration_session) $fatal(1,"FAIL: fixed-session travel limit");
        encoder_position=0; cycles(100500);
        frame("c,3,408,150,1"); frame("b,3,1,7,1"); cycles(15000); off;
        if(dut.state!==0 || dut.calibration_result!==3) $fatal(1,"FAIL: ADC-independent deadline");
        // Legacy K2 still uses the user's fixed 20% once the session is exited.
        frame("e,3"); key_n[1]=0; cycles(110); key_n[1]=1; cycles(110); cycles(2200);
        if(dut.state!==6 || dut.core_calibration_test || dut.actual_pwm!==16'sd20)
            $fatal(1,"FAIL: legacy K2 regression");
        key_n[3]=0; cycles(110); key_n[3]=1; cycles(110); off;
        $display("TEST PASSED: tb_acg720_calibration"); $finish;
    end
    initial begin #20000000; $fatal(1,"FAIL: calibration integration timeout"); end
endmodule
