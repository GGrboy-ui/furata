`timescale 1ns/1ps
module tb_acg720_oled;
    reg clk=0,rst_n=0,enc_a=0,enc_b=0,ack_enable=1;
    reg [3:0] key_n=4'hf;
    tri1 scl,sda;
    wire stby,pwm,in1,in2,active;
    always #5 clk=~clk;
    // This fixture checks the inverted encoder coordinate independently of bench wiring.
    acg720_top #(.ENCODER_INVERT(1),.CLK_HZ(1_000_000),.BAUD(10000),.PWM_HZ(1000),
        .KEY_DEBOUNCE_MS(1),.OLED_POWER_WAIT_MS(1),.OLED_REFRESH_MS(1)) dut (
        .clk(clk),.rst_n(rst_n),.uart_rx(1'b1),.enc_a(enc_a),.enc_b(enc_b),
        .board_adc_dout(1'b0),.key1_n(key_n[0]),.key2_n(key_n[1]),
        .key3_n(key_n[2]),.key4_n(key_n[3]),.stby_fpga(stby),.pwm_a(pwm),
        .ain1(in1),.ain2(in2),.oled_scl(scl),.oled_sda(sda));
    model_oled_i2c slave(.scl(scl),.sda(sda),.ack_enable(ack_enable),.stretch(1'b0),.active(active));
    task cycles; input integer n; begin repeat(n) @(negedge clk); end endtask
    task press; input integer k; begin key_n[k]=0;cycles(1010);key_n[k]=1;cycles(1010);end endtask
    task forward;
        begin
            enc_b=1;cycles(10);enc_a=1;cycles(10);
            enc_b=0;cycles(10);enc_a=0;cycles(10);
        end
    endtask
    task next_frame;
        begin
            wait(dut.oled.state==4); wait(dut.oled_frame_done); #1;
        end
    endtask
    task assert_counts;
        input [39:0] raw_bcd,pos_bcd,rel_bcd;
        input raw_sign,pos_sign,rel_sign;
        begin
            if (dut.oled.bcd_raw!==raw_bcd || dut.oled.bcd_pos!==pos_bcd ||
                dut.oled.bcd_rel!==rel_bcd || dut.oled.sign_raw!==raw_sign ||
                dut.oled.sign_pos!==pos_sign || dut.oled.sign_rel!==rel_sign)
                $fatal(1,"FAIL: QEI->OLED signed count snapshot");
        end
    endtask
    initial begin
        $dumpfile("tb_acg720_oled.vcd");
        $dumpvars(0,clk,rst_n,enc_a,enc_b,scl,sda,stby,pwm,
            dut.raw_position,dut.position,dut.relative_position,dut.state,
            dut.oled_error,dut.oled_frame_done);
        force dut.sample_ready=1'b1;force dut.sample_valid=1'b0;
        force dut.sample=12'd1011;force dut.sensor_fault=4'd0;
        cycles(5);rst_n=1;cycles(20);
        repeat(3) forward;
        if(dut.raw_position!==12 || dut.position!==-12) $fatal(1,"FAIL: real AB decode/polarity");
        next_frame;assert_counts(40'h12,40'h12,40'h12,0,1,1);
        press(2);
        if(dut.state!==4 || dut.core.origin!==-12 || dut.relative_position!==0)
            $fatal(1,"FAIL: K3 position origin");
        next_frame;assert_counts(40'h12,40'h12,0,0,1,0);
        repeat(102) forward;next_frame;assert_counts(40'h420,40'h420,40'h408,0,1,1);
        forward;next_frame;assert_counts(40'h424,40'h424,40'h412,0,1,1);
        press(3);
        if(dut.state!==0 || stby!==0 || dut.raw_position!==424 || dut.relative_position!==-424)
            $fatal(1,"FAIL: K4 motor reset/count retention");
        next_frame;assert_counts(40'h424,40'h424,40'h424,0,1,1);
        ack_enable=0;wait(dut.oled_error);press(1);cycles(20000);
        if(dut.state!==6 || stby!==1 || dut.motor_ready!==1 || dut.motor.duty_q==0 || dut.fault_latched)
            $fatal(1,"FAIL: missing OLED blocked motor test");
        press(3);press(2);cycles(3000);
        if(dut.state!==4 || stby!==1 || dut.relative_position!==0 || dut.oled_error!==1)
            $fatal(1,"FAIL: missing OLED blocked K3");
        force dut.sensor_fault=4'd4;#1;
        if(stby!==0 || pwm!==0 || in1!==0 || in2!==0)
            $fatal(1,"FAIL: OLED changed safety shutdown");
        $display("PASS: AB->RAW/POS/REL, K3 capture, K4 retention, unplugged motor modes and safety");
        $finish;
    end
    initial begin #20000000;$fatal(1,"FAIL: board OLED test timeout");end
endmodule
