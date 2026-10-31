`timescale 1ns/1ps
module tb_acg720_handover_safety;
 reg clk=0,rst_n=0,sample_tick=0;always #5 clk=~clk;
 reg [3:0] keys=15;reg signed [31:0] position=100;
 wire stby,pwm;integer saved_i;reg signed [31:0] saved_origin,saved_goal,saved_out;
 acg720_top #(.CLK_HZ(1000000),.BAUD(100000),.CENTER(3124),.KEY_DEBOUNCE_MS(1),.PULSE_MS(2),.CHECK_MS(2)) dut(.clk(clk),.rst_n(rst_n),.uart_rx(1'b1),.enc_a(1'b0),.enc_b(1'b0),.board_adc_dout(1'b0),.key1_n(keys[0]),.key2_n(keys[1]),.key3_n(keys[2]),.key4_n(keys[3]),.stby_fpga(stby),.pwm_a(pwm));
 task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
 task press;input integer k;begin keys[k]=0;clocks(1100);keys[k]=1;clocks(1100);end endtask
 task ms;begin sample_tick=1;clocks(1);sample_tick=0;clocks(350);if(^dut.command_q===1'bx)$fatal(1,"FAIL: unknown controller");end endtask
 initial begin
  $dumpfile("tb_acg720_handover_safety.vcd");$dumpvars(1,tb_acg720_handover_safety);
  force dut.sample_ready=1;force dut.sample_valid=sample_tick;force dut.sample=12'd3124;force dut.sensor_fault=0;force dut.raw_position=position;
  clocks(4);rst_n=1;clocks(1200);press(1);if(dut.state!=0||dut.outer_speed)$fatal(1,"FAIL: K2 STOP action");
  press(0);press(1);if(dut.outer_speed||dut.state==0)$fatal(1,"FAIL: K2 swing-up action");repeat(8)ms;if(dut.state!=4||dut.outer_speed)$fatal(1,"FAIL: K1 position capture");
  force dut.arm_busy=1;press(1);release dut.arm_busy;if(dut.outer_speed)$fatal(1,"FAIL: K2 during ARM");clocks(300);if(dut.outer_speed)$fatal(1,"FAIL: queued K2");
  force dut.trajectory_busy=1;press(1);release dut.trajectory_busy;if(dut.outer_speed)$fatal(1,"FAIL: K2 during profile");
  position=97;repeat(60)ms;saved_i=dut.core.angle_pid.integral_q;saved_origin=dut.core.origin;saved_goal=dut.position_goal_q;saved_out=dut.core.position_out;
  if(saved_i==0||saved_out==0)$fatal(1,"FAIL: fixture did not establish controller history");
  press(1);if(!dut.outer_speed||dut.handover_remaining!=200||dut.core.transfer.out_q!=saved_out||dut.core.origin!=saved_origin||dut.position_goal_q!=saved_goal||dut.core.angle_pid.integral_q!=saved_i)$fatal(1,"FAIL: handover changed origin/goal/inner history or old output");
  repeat(20)ms;press(1);if(dut.handover_remaining!=180)$fatal(1,"FAIL: repeated K2 restarted transfer");
  force dut.uart_stop_cmd=1;#1;if(stby||pwm)$fatal(1,"FAIL: X delayed output inhibition");clocks(3);release dut.uart_stop_cmd;clocks(5);
  if(dut.state!=0||dut.handover_remaining!=0||!dut.outer_speed)$fatal(1,"FAIL: X transfer cancel/last mode");
  press(0);if(dut.outer_speed)$fatal(1,"FAIL: K1 after speed did not force position");repeat(8)ms;
  press(1);if(!dut.outer_speed||dut.handover_remaining==0)$fatal(1,"FAIL: second transfer");press(3);
  if(dut.state!=0||dut.handover_remaining!=0||!dut.outer_speed||stby||pwm)$fatal(1,"FAIL: K4 transfer cancel");
  press(2);if(dut.state!=4||dut.outer_speed)$fatal(1,"FAIL: K3 must choose position");
  press(1);if(!dut.outer_speed||dut.handover_remaining==0)$fatal(1,"FAIL: fault transfer fixture");
  force dut.sensor_fault=4'd4;#1;if(stby||pwm)$fatal(1,"FAIL: fault delayed motor inhibition");clocks(4);
  if(dut.state!=5||dut.handover_remaining!=0||!dut.fault_latched)$fatal(1,"FAIL: fault did not cancel transfer");
  $display("TEST PASSED: tb_acg720_handover_safety (K1/K3 position, K2 idle-only/no queue, goal/origin/angle history preserved, 200ms, X/K4/fault interruption)");$finish;
 end
 initial begin #10000000;$fatal(1,"FAIL: key transfer timeout");end
endmodule
