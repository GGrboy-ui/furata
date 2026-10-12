`timescale 1ns/1ps
module tb_acg720_display;
    reg clk=0,rst_n=0,uart_rx=1,adc_dout=0;
    reg [11:0] adc_sample=1014;
    wire uart_tx,pwm_a,ain1,ain2,stby,cs_n,din,sclk,seg_sclk,seg_rclk,seg_dio;
    acg720_top #(.CLK_HZ(100000),.BAUD(10000),.PWM_HZ(1000),.ADC_HALF_DIV(1)) dut (
        .clk(clk),.rst_n(rst_n),.uart_rx(uart_rx),.enc_a(1'b0),.enc_b(1'b0),
        .key1_n(1'b1),.key2_n(1'b1),.key3_n(1'b1),.key4_n(1'b1),
        .board_adc_dout(adc_dout),.uart_tx(uart_tx),.pwm_a(pwm_a),.ain1(ain1),.ain2(ain2),
        .stby_fpga(stby),.dbg_tick(),.board_adc_cs_n(cs_n),.board_adc_din(din),.board_adc_sclk(sclk),
        .seg7_sclk(seg_sclk),.seg7_rclk(seg_rclk),.seg7_dio(seg_dio));
    always #5 clk=~clk;
    integer adc_bit=0;
    always @(posedge cs_n) adc_bit=0;
    always @(negedge sclk) if(!cs_n) begin
        adc_dout<=(adc_bit<4) ? 0 : adc_sample[15-adc_bit];
        adc_bit=adc_bit+1;
    end
    task cycles; input integer n; begin repeat(n) @(negedge clk); end endtask
    task command; input [7:0] value; input good_stop; integer bitn; begin
        @(negedge clk); uart_rx=0; cycles(10);
        for(bitn=0;bitn<8;bitn=bitn+1) begin uart_rx=value[bitn]; cycles(10); end
        uart_rx=good_stop; cycles(10); uart_rx=1; cycles(30);
    end endtask
    initial begin
        $dumpfile("tb_acg720_display.vcd");
        $dumpvars(0,clk,rst_n,uart_rx,cs_n,sclk,seg_sclk,seg_rclk,seg_dio,stby);
        cycles(3); rst_n=1; cycles(2100);
        if(dut.sample!==1014 || dut.displayed_angle!==0 || !dut.display_angle_valid)
            $fatal(1,"FAIL: ADC serial input did not reach angle display");
        if(stby!==0 || pwm_a!==0 || ain1!==0 || ain2!==0) $fatal(1,"FAIL: display enabled motor at boot");
        command("D",1);
        if(!dut.display_raw || stby!==0) $fatal(1,"FAIL: D mode/motor isolation");
        if(dut.display_segments[31:0]!==32'hf9c0f999) $fatal(1,"FAIL: raw ADC 1014 glyphs");
        command("A",0);
        if(!dut.display_raw) $fatal(1,"FAIL: bad UART stop bit changed display mode");
        command("A",1);
        if(dut.display_raw || stby!==0) $fatal(1,"FAIL: A mode/motor isolation");
        adc_sample=2121; cycles(3300);
        if(dut.displayed_angle!==900) $fatal(1,"FAIL: angle not refreshed while controller stopped");
        // Persistent ADC rail input should latch fault 4, visible at the left,
        // while raw mode remains usable for diagnosis and motor stays disabled.
        adc_sample=0; cycles(52500);
        if(!dut.fault_latched || dut.fault_code!==4 || stby!==0) $fatal(1,"FAIL: ADC rail fault not preserved");
        if(dut.display_segments!==64'h9299ffbfbfbfbfbf) $fatal(1,"FAIL: fault 4 not visible");
        command("D",1);
        if(dut.display_segments!==64'h9299ffffc0c0c0c0) $fatal(1,"FAIL: rail ADC not visible in raw mode");
        adc_sample=1014; cycles(2200); command("X",1); command("C",1);
        if(dut.fault_latched || stby!==0) $fatal(1,"FAIL: stopped clear command changed by display integration");
        command("S",1); cycles(220);
        if(stby!==1) $fatal(1,"FAIL: original start path broken");
        command("X",1);
        if(stby!==0 || pwm_a!==0) $fatal(1,"FAIL: original stop path broken");
        $display("TEST PASSED: tb_acg720_display (ADC-to-display, UART A/D, faults, S/X/C, motor isolation)");
        $finish;
    end
    initial begin #1000000; $fatal(1,"FAIL: display integration timeout"); end
endmodule
