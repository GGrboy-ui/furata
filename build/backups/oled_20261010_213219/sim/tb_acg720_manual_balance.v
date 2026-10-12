`timescale 1ns/1ps
module tb_acg720_manual_balance;
 reg clk=0,rst_n=0; reg [3:0] key_n=4'hf;
 wire stby,pwm,in1,in2;
 acg720_top #(.CLK_HZ(100000),.BAUD(1000),.PWM_HZ(1000),.KEY_DEBOUNCE_MS(1),
   .PULSE_MS(2),.CHECK_MS(2),.SWING_TIMEOUT_MS(10)) dut(
   .clk(clk),.rst_n(rst_n),.uart_rx(1'b1),.enc_a(1'b0),.enc_b(1'b0),.board_adc_dout(1'b0),
   .key1_n(key_n[0]),.key2_n(key_n[1]),.key3_n(key_n[2]),.key4_n(key_n[3]),
   .stby_fpga(stby),.pwm_a(pwm),.ain1(in1),.ain2(in2));
 always #5 clk=~clk;
 task cycles; input integer n; begin repeat(n) @(negedge clk); end endtask
 task press; input integer k; begin key_n[k]=0;cycles(110);key_n[k]=1;cycles(110);end endtask
 task sample_tick; begin
   force dut.sample_valid=1'b1;cycles(1);force dut.sample_valid=1'b0;cycles(4);
 end endtask
 task off; begin
   if(stby!==0 || pwm!==0 || in1!==0 || in2!==0) $fatal(1,"FAIL: motor not inhibited");
 end endtask
 initial begin
   $dumpfile("tb_acg720_manual_balance.vcd");$dumpvars(0,tb_acg720_manual_balance);
   // Synthetic samples verify electrical/control behavior, not mechanical stability.
   force dut.sample_ready=1'b1;force dut.sample_valid=1'b0;
   force dut.sample=12'd1011;force dut.sensor_fault=4'd0;force dut.position=32'sd123;
   cycles(3);rst_n=1;cycles(140);
   force dut.sample_ready=1'b0;press(2);off;
   if(dut.state!==0) $fatal(1,"FAIL: K3 accepted before sensor ready");
   force dut.sample_ready=1'b1;force dut.sample=12'd3000;press(2);off;
   if(dut.state!==0) $fatal(1,"FAIL: K3 accepted outside upright window");
   force dut.sample=12'd1011;repeat(10) sample_tick;cycles(30);off;
   if(dut.state!==0) $fatal(1,"FAIL: rejected K3 request was queued");
   press(2);
   if(dut.state!==4 || dut.core.origin!==123 || dut.relative_position!==0 ||
      dut.command_q!==0 || stby!==1 || dut.motor_ready!==0 || pwm!==0)
     $fatal(1,"FAIL: direct K3 capture/origin/no-pulse/wake behavior");
   repeat(30) sample_tick;cycles(2200);
   if(dut.state!==4 || dut.core_fault!==0 || dut.position_goal_q!==0 ||
      dut.position_target_q!==0 || dut.command_q!==0 || pwm!==0 || dut.motor_ready!==1)
     $fatal(1,"FAIL: centered balance failed or inherited swing timeout");
   force dut.sample=12'd1021;repeat(10) sample_tick;cycles(2200);
   if(dut.command_q>=0 || dut.pwm_command<=0 || pwm===1'bx || dut.motor.duty_q===0 ||
      in1!==1 || in2!==0) $fatal(1,"FAIL: positive angle error did not reach motor");
   force dut.sample=12'd1001;repeat(20) sample_tick;cycles(2200);
   if(dut.command_q<=0 || dut.pwm_command>=0 || dut.motor.duty_q===0 ||
      in1!==0 || in2!==1) $fatal(1,"FAIL: opposite angle error did not reverse motor");
   force dut.sample=12'd1011;force dut.position=32'sd143;repeat(60) sample_tick;
   if(dut.core.position_out===0 || dut.relative_position!==20)
     $fatal(1,"FAIL: position hold did not engage outer loop");
   press(2);
   if(dut.core.origin!==123 || dut.position_goal_q!==0 || dut.position_target_q!==0)
     $fatal(1,"FAIL: repeated K3 re-zeroed origin or moved target");
   // K4 stops even while K3 remains held; no automatic re-start.
   key_n[2]=0;cycles(110);press(3);cycles(2200);off;
   if(dut.state!==0 || dut.fault_latched || dut.core.angle_pid.out_q!==0 ||
      dut.core.position_pid.out_q!==0) $fatal(1,"FAIL: K4 reset or held K3 restart");
   key_n[2]=1;cycles(110);force dut.position=32'sd123;
   press(0);press(2);
   if(dut.state!==1) $fatal(1,"FAIL: K3 interrupted swing-up");
   press(3);press(2);cycles(2200);
   force dut.uart_stop_cmd=1'b1;#1;off;cycles(3);release dut.uart_stop_cmd;
   cycles(200);off;if(dut.state!==0) $fatal(1,"FAIL: UART stop failed");
   press(2);force dut.sample=12'd1511;sample_tick;cycles(4);off;
   if(dut.state!==5 || dut.fault_code!==5) $fatal(1,"FAIL: angle limit not latched");
   force dut.sample=12'd1011;press(2);off;
   if(dut.state!==5) $fatal(1,"FAIL: K3 bypassed fault latch");
   press(3);press(2);force dut.position=32'sd4204;#1;off;cycles(4);
   if(dut.state!==5 || dut.fault_code!==7) $fatal(1,"FAIL: position limit not latched");
   force dut.position=32'sd123;press(3);press(2);
   force dut.sensor_fault=4'd4;#1;off;cycles(4);press(2);off;
   if(dut.state!==5 || dut.fault_code!==4) $fatal(1,"FAIL: sensor fault not retained");
   force dut.sensor_fault=4'd0;press(3);
   key_n=4'b0011;cycles(110);key_n=4'hf;cycles(110);off;
   if(dut.state!==0) $fatal(1,"FAIL: simultaneous K3/K4 reset priority");
   press(2);if(dut.state!==4) $fatal(1,"FAIL: fresh K3 after recovery failed");
   $display("TEST PASSED: tb_acg720_manual_balance (K3 direct PID, admission, hold, stop and faults)");
   $finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: manual balance test timeout");end
endmodule
