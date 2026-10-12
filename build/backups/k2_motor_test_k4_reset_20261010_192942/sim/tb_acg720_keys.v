`timescale 1ns/1ps
module tb_acg720_keys;
 reg clk=0,rst_n=0; reg [3:0] key_n=4'hf;
 wire stby_fpga,pwm_a,ain1,ain2;
 integer i;
 acg720_top #(.CLK_HZ(100000),.BAUD(1000),.PWM_HZ(1000),.KEY_DEBOUNCE_MS(1),
     .PULSE_MS(2),.CHECK_MS(2),.SWING_TIMEOUT_MS(100)) dut(
   .clk(clk),.rst_n(rst_n),.uart_rx(1'b1),.enc_a(1'b0),.enc_b(1'b0),.board_adc_dout(1'b0),
   .key1_n(key_n[0]),.key2_n(key_n[1]),.key3_n(key_n[2]),.key4_n(key_n[3]),
   .stby_fpga(stby_fpga),.pwm_a(pwm_a),.ain1(ain1),.ain2(ain2));
 always #5 clk=~clk;
 task cycles; input integer n; integer j;
   begin for(j=0;j<n;j=j+1) @(negedge clk); end
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
 initial begin
   $dumpfile("tb_acg720_keys.vcd"); $dumpvars(0,tb_acg720_keys);
   // Synthetic sensor data exercises the key->core->position PID path.
   // Physical ADC framing is covered by its own test; this is not a plant model.
   force dut.sample_ready=1'b1;
   force dut.sample=12'd1014;
   force dut.sample_valid=1'b0;
   force dut.sensor_fault=4'd0;
   cycles(3); rst_n=1; cycles(140);
   press(1); press(2); press(3);
   if(dut.state!==0 || dut.position_goal_q!==0) $fatal(1,"FAIL: move key started from STOP");
   press(0);
   if(dut.state!==1) $fatal(1,"FAIL: KEY1 did not start swing-up");
   press(3);
   if(dut.position_goal_q!==0) $fatal(1,"FAIL: move queued during swing-up");
   repeat(8) sample_tick;
   if(dut.state!==4) $fatal(1,"FAIL: swing-up did not capture BALANCE");
   cycles(3); press(1);
   if(dut.position_goal_q!==742741) $fatal(1,"FAIL: KEY2 mapping");
   repeat(60) sample_tick;
   if(dut.position_target_q<=0 || dut.core.position_out===0) $fatal(1,"FAIL: position target did not reach PID");
   press(2);
   if(dut.position_goal_q!==0) $fatal(1,"FAIL: KEY3 mapping");
   press(3);
   if(dut.position_goal_q!==26738688) $fatal(1,"FAIL: KEY4 must request one full turn");
   key_n[3]=0; cycles(110); // second KEY4, then hold without repeating
   cycles(400);
   if(dut.position_goal_q!==53477376) $fatal(1,"FAIL: held KEY4 repeated");
   key_n[3]=1; cycles(110);
   press(0);
   if(dut.state!==4 || dut.position_goal_q!==53477376) $fatal(1,"FAIL: KEY1 restarted an active run");
   force dut.stop_cmd=1'b1; cycles(2); release dut.stop_cmd; cycles(2);
   if(dut.state!==0 || dut.position_goal_q!==0 || dut.position_target_q!==0 || stby_fpga!==0)
     $fatal(1,"FAIL: stop did not cancel motion");
   press(0); repeat(8) sample_tick; cycles(3);
   if(dut.state!==4) $fatal(1,"FAIL: re-start did not balance");
   // The measured upright value must balance, while the old reference value
   // must trigger and latch fault 5 after entering BALANCE.
   force dut.sample=12'd2098; sample_tick; cycles(3);
   if(dut.state!==5 || dut.fault_code!==5 || stby_fpga!==0 || pwm_a!==0)
     $fatal(1,"FAIL: old center did not trip balance-range protection");
   force dut.sample=12'd1014; press(0);
   if(dut.state!==5 || dut.fault_code!==5 || stby_fpga!==0)
     $fatal(1,"FAIL: valid angle/KEY1 bypassed fault latch");
   force dut.clear_cmd=1'b1; cycles(2); release dut.clear_cmd; cycles(3);
   if(dut.state!==0 || dut.fault_latched || stby_fpga!==0)
     $fatal(1,"FAIL: stopped clear did not re-arm calibrated controller");
   press(0); repeat(8) sample_tick; cycles(3);
   if(dut.state!==4 || dut.core_fault!==0)
     $fatal(1,"FAIL: measured center did not balance after re-arm");
   // Strict capture bounds: 515 and 1513 are inside; 1514 is outside.
   force dut.sample=12'd515; sample_tick; cycles(3);
   force dut.sample=12'd1513; sample_tick; cycles(3);
   if(dut.state!==4 || dut.fault_latched)
     $fatal(1,"FAIL: valid calibrated capture bounds tripped protection");
   force dut.sample=12'd1514; sample_tick; cycles(3);
   if(dut.state!==5 || dut.fault_code!==5 || stby_fpga!==0)
     $fatal(1,"FAIL: calibrated upper bound did not trip protection");
   force dut.sample=12'd1014;
   force dut.clear_cmd=1'b1; cycles(2); release dut.clear_cmd; cycles(3);
   press(0); repeat(8) sample_tick; cycles(3);
   if(dut.state!==4) $fatal(1,"FAIL: calibrated restart failed");
   press(1); force dut.sensor_fault=4'd4; cycles(3); press(3);
   if(dut.position_goal_q!==0 || stby_fpga!==0 || pwm_a!==0 || ain1!==0 || ain2!==0)
     $fatal(1,"FAIL: fault did not inhibit movement and motor");
   $display("TEST PASSED: tb_acg720_keys"); $finish;
 end
 initial begin #1000000; $fatal(1,"FAIL: board key test timeout"); end
endmodule
