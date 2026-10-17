`timescale 1ns/1ps
module tb_acg720_motor_test;
 reg clk=0,rst_n=0; reg [3:0] key_n=4'hf;
 wire stby_fpga,pwm_a,ain1,ain2;
 integer j,high_count;
 acg720_top #(.CLK_HZ(100000),.BAUD(1000),.PWM_HZ(1000),.KEY_DEBOUNCE_MS(1),
     .SWING_TIMEOUT_MS(10)) dut(
   .clk(clk),.rst_n(rst_n),.uart_rx(1'b1),.enc_a(1'b0),.enc_b(1'b0),.board_adc_dout(1'b0),
   .key1_n(key_n[0]),.key2_n(key_n[1]),.key3_n(key_n[2]),.key4_n(key_n[3]),
   .stby_fpga(stby_fpga),.pwm_a(pwm_a),.ain1(ain1),.ain2(ain2));
 always #5 clk=~clk;
 task cycles; input integer n; integer k;
   begin for(k=0;k<n;k=k+1) @(negedge clk); end
 endtask
 task press; input integer k;
   begin key_n[k]=0; cycles(110); key_n[k]=1; cycles(110); end
 endtask
 task sample_tick;
   begin
     force dut.sample_valid=1'b1; cycles(1);
     force dut.sample_valid=1'b0; cycles(4);
   end
 endtask
 task check_off;
   begin
     if(stby_fpga!==0 || pwm_a!==0 || ain1!==0 || ain2!==0)
       $fatal(1,"FAIL: motor outputs were not inhibited");
   end
 endtask
 always @(posedge clk) if(rst_n && dut.key_press[3]) begin
   #1; check_off;
 end
 initial begin
   $dumpfile("tb_acg720_motor_test.vcd"); $dumpvars(0,tb_acg720_motor_test);
   // Angle deliberately outside BALANCE's window; this is not a plant model.
   force dut.sample_ready=1'b1;
   force dut.sample=12'd3000;
   force dut.sample_valid=1'b0;
   force dut.sensor_fault=4'd0;
   cycles(3); rst_n=1; cycles(140); check_off;
   force dut.sample_ready=1'b0; press(1);
   if(dut.state!==0) $fatal(1,"FAIL: KEY2 started without sensor readiness");
   force dut.sample_ready=1'b1; cycles(30);
   if(dut.state!==0) $fatal(1,"FAIL: an ignored start was queued");
   press(1);
   if(dut.state!==6 || stby_fpga!==1 || dut.motor_ready!==0 || pwm_a!==0)
     $fatal(1,"FAIL: KEY2 start/wake sequencing");
   if(dut.command_q!==32'sd1310720) $fatal(1,"FAIL: KEY2 command is not 20 percent");
   cycles(60);
   if(dut.motor_ready!==0 || pwm_a!==0) $fatal(1,"FAIL: PWM released before wake delay");
   cycles(2200);
   if(dut.motor_ready!==1 || dut.pwm_command!==-16'sd20 || dut.motor.duty_q!==20 ||
      ain1!==0 || ain2!==1 || dut.position_goal_q!==0 || dut.position_target_q!==0)
     $fatal(1,"FAIL: fixed duty/direction/target");
   high_count=0;
   for(j=0;j<2000;j=j+1) begin cycles(1); if(pwm_a) high_count=high_count+1; end
   if(high_count!==400) $fatal(1,"FAIL: measured PWM high clocks=%0d, expected 400/2000",high_count);
   repeat(30) sample_tick;
   press(0); press(2);
   if(dut.state!==6 || dut.core_fault!==0 || dut.command_q!==32'sd1310720 ||
      dut.core.angle_pid.out_q!==0 || dut.core.position_pid.out_q!==0)
     $fatal(1,"FAIL: angle/start/position key or swing timeout changed test mode");
   // A held K2 cannot automatically restart after K4.
   key_n[1]=0; cycles(110); press(3); cycles(2000); check_off;
   if(dut.state!==0 || dut.fault_code!==0 || dut.motor.duty_q!==0 || dut.wake_count!==0)
     $fatal(1,"FAIL: KEY4 reset or held KEY2 re-start");
   key_n[1]=1; cycles(110);
   key_n=4'b0100; cycles(110); key_n=4'hf; cycles(110); check_off;
   if(dut.state!==0) $fatal(1,"FAIL: reset lost priority over start keys");
   press(1); cycles(2200);
   if(dut.state!==6 || dut.motor.duty_q!==20) $fatal(1,"FAIL: fresh KEY2 failed after reset");
   force dut.uart_stop_cmd=1'b1; #1; check_off;
   cycles(3); release dut.uart_stop_cmd; cycles(200); check_off;
   if(dut.state!==0) $fatal(1,"FAIL: UART stop did not cancel test mode");
   press(1); cycles(2200);
   force dut.position=32'sd4081; #1; check_off; cycles(4);
   if(dut.state!==5 || dut.fault_code!==7) $fatal(1,"FAIL: test travel limit not latched");
   release dut.position; press(1); check_off;
   if(dut.state!==5) $fatal(1,"FAIL: KEY2 cleared travel fault");
   press(3); press(1); cycles(2200);
   force dut.sensor_fault=4'd4; #1; check_off; cycles(4);
   if(dut.state!==5 || dut.fault_code!==4) $fatal(1,"FAIL: test sensor fault not latched");
   force dut.sensor_fault=4'd0; cycles(200); check_off;
   press(3); cycles(200); check_off;
   if(dut.state!==0 || dut.fault_latched || dut.fault_code!==0)
     $fatal(1,"FAIL: KEY4 did not restore 00 after repaired fault");
   $display("TEST PASSED: tb_acg720_motor_test (20 percent PWM, reset, stop and fault paths)");
   $finish;
 end
 initial begin #1000000; $fatal(1,"FAIL: motor key test timeout"); end
endmodule
