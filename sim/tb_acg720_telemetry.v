`timescale 1ns/1ps
module tb_acg720_telemetry;
    reg clk=0, rst_n=0, rx=1;
    reg [3:0] keys=4'hf;
    wire stby, pwm, in1, in2;
    integer snapshots=0, ramp_snapshots=0;
    reg signed [15:0] expected_actual;
    acg720_top #(.CENTER(1011),.CLK_HZ(1000000),.BAUD(100000),.PWM_HZ(400),.KEY_DEBOUNCE_MS(1)) dut (
        .clk(clk),.rst_n(rst_n),.uart_rx(rx),.enc_a(1'b0),.enc_b(1'b0),.board_adc_dout(1'b0),
        .key1_n(keys[0]),.key2_n(keys[1]),.key3_n(keys[2]),.key4_n(keys[3]),
        .stby_fpga(stby),.pwm_a(pwm),.ain1(in1),.ain2(in2));
    always #5 clk=~clk;
    task cycles; input integer n; integer k;
        begin for(k=0;k<n;k=k+1) @(negedge clk); end
    endtask
    task send_byte; input [7:0] value; integer k;
        begin
            rx=0; cycles(10);
            for(k=0;k<8;k=k+1) begin rx=value[k]; cycles(10); end
            rx=1; cycles(20);
        end
    endtask
    // Check actual applied counts during slew and after inhibit. Pin level is not duty.
    always @(negedge clk) if(dut.telemetry.phase==1 && dut.telemetry.convert_left==16) begin
        snapshots=snapshots+1;
        if(dut.telemetry.angle_binary!==16'd0)
            $fatal(1,"FAIL: telemetry did not use real averaged display angle");
        if(dut.telemetry.request_binary!==((dut.requested_pwm<0) ? -dut.requested_pwm : dut.requested_pwm) ||
           dut.telemetry.actual_binary!==((dut.actual_pwm<0) ? -dut.actual_pwm : dut.actual_pwm) ||
           dut.telemetry.request_negative!==(dut.requested_pwm<0) ||
           dut.telemetry.actual_negative!==(dut.actual_pwm<0))
            $fatal(1,"FAIL: PWM snapshot differs from same-cycle counts");
        if(dut.motor_ready && dut.actual_pwm>0 && dut.actual_pwm<dut.requested_pwm)
            ramp_snapshots=ramp_snapshots+1;
        if(!dut.motor_ready && dut.actual_pwm!==0)
            $fatal(1,"FAIL: telemetry reports applied duty while inhibited");
    end
    initial begin
        $dumpfile("tb_acg720_telemetry.vcd"); $dumpvars(0,tb_acg720_telemetry);
        force dut.sample_ready=1'b1; force dut.sensor_fault=4'd0;
        force dut.sample=12'd1011;
        cycles(4); rst_n=1; cycles(20000);
        if(!dut.display_angle_valid || dut.displayed_angle!==0)
            $fatal(1,"FAIL: real display average did not become valid");
        send_byte("P"); cycles(12000);
        if(dut.state!==0 || stby!==0 || snapshots<2)
            $fatal(1,"FAIL: P started motor or failed to sample stopped display");
        keys[1]=0; cycles(1100); keys[1]=1; cycles(1100);
        cycles(40000);
        if(dut.state!==6 || dut.requested_pwm!==500 || dut.pwm_command!==-500 ||
           dut.actual_pwm!==$signed(dut.motor.duty_q) || ramp_snapshots==0)
            $fatal(1,"FAIL: inverted motor request/applied slew telemetry: state=%d request=%d pwm_command=%d actual=%d duty=%d ramps=%d",dut.state,dut.requested_pwm,dut.pwm_command,dut.actual_pwm,dut.motor.duty_q,ramp_snapshots);
        send_byte("Q"); cycles(6000);
        if(dut.state!==6 || stby!==1 || dut.telemetry.enabled)
            $fatal(1,"FAIL: Q stopped the motor");
        send_byte("P"); cycles(6000);
        // Reversal telemetry follows the old actual direction until slew reaches zero.
        force dut.command_q=-32'sd1310720;
        cycles(5);
        if(dut.requested_pwm!==-500 || dut.actual_pwm<=0)
            $fatal(1,"FAIL: request/actual signs during reversal");
        repeat(100000) begin
            cycles(1);
            expected_actual=dut.motor_ready ?
                (dut.motor.dir_q ? $signed(dut.motor.duty_q) : -$signed(dut.motor.duty_q)) : 16'sd0;
            if(dut.actual_pwm!==expected_actual)
                $fatal(1,"FAIL: reversal telemetry did not follow actual duty/direction");
        end
        if(dut.actual_pwm>=0) $fatal(1,"FAIL: reversed duty never reached negative control sign");
        release dut.command_q;
        force dut.sensor_fault=4'd4; #1;
        if(stby!==0 || pwm!==0 || dut.actual_pwm!==0)
            $fatal(1,"FAIL: immediate fault inhibition not reflected in actual duty");
        cycles(1000); force dut.sensor_fault=4'd0;
        keys[3]=0; cycles(1100); keys[3]=1; cycles(1100);
        if(dut.state!==0 || !dut.telemetry.enabled || dut.actual_pwm!==0)
            $fatal(1,"FAIL: K4 reset telemetry or left applied duty");
        cycles(10000);
        send_byte("D"); cycles(6000);
        if(!dut.display_raw || !dut.telemetry.enabled)
            $fatal(1,"FAIL: raw-display command disturbed telemetry");
        send_byte("S"); cycles(1000);
        if(dut.state!==1) $fatal(1,"FAIL: S command lost while streaming");
        send_byte("X"); cycles(100);
        if(dut.state!==0 || stby!==0 || dut.actual_pwm!==0 || !dut.telemetry.enabled)
            $fatal(1,"FAIL: X stop lost or stopped telemetry");
        $display("TEST PASSED: tb_acg720_telemetry (display average, PWM slew/sign, motor safety, independent P/Q)");
        $finish;
    end
    initial begin #4000000; $fatal(1,"FAIL: board telemetry timeout"); end
endmodule
