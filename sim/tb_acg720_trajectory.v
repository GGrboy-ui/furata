`timescale 1ns/1ps
module tb_acg720_trajectory;
 reg clk=0,rst_n=0,rx=1,sample_tick=0;
 reg [3:0] keys=15;reg signed [31:0] position=1234;
 wire tx;integer i,length=0,capabilities=0,arm_caps=0,reports=0,last_code=-1,telemetry=0,file;
 reg [7:0] line[0:127],decoded;
 acg720_top #(.CENTER(1000),.DEFAULT_OUTER_SPEED(0),.CLK_HZ(1000000),.BAUD(100000),.KEY_DEBOUNCE_MS(1)) dut(
  .clk(clk),.rst_n(rst_n),.uart_rx(rx),.enc_a(1'b0),.enc_b(1'b0),.board_adc_dout(1'b0),
  .key1_n(keys[0]),.key2_n(keys[1]),.key3_n(keys[2]),.key4_n(keys[3]),.uart_tx(tx));
 always #5 clk=~clk;
 task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
 task byte_send;input [7:0] value;integer j;begin rx=0;clocks(10);for(j=0;j<8;j=j+1)begin rx=value[j];clocks(10);end rx=1;clocks(20);end endtask
 task command;input string text;integer j;begin for(j=0;j<text.len();j=j+1)byte_send(text[j]);end endtask
 task ms;begin sample_tick=1;clocks(1);sample_tick=0;clocks(350);end endtask
 task key2;begin keys[1]=0;clocks(1100);keys[1]=1;clocks(1100);end endtask
 task key3;begin keys[2]=0;clocks(1100);keys[2]=1;clocks(1100);end endtask
 function integer hex;input [7:0] c;begin hex=c<="9"?c-"0":c-"A"+10;end endfunction
 initial forever begin
  @(negedge tx);#50;if(tx!==0)$fatal(1,"FAIL: UART start");
  for(i=0;i<8;i=i+1)begin #100;decoded[i]=tx;end
  #100;if(tx!==1)$fatal(1,"FAIL: UART stop");
  $fwrite(file,"%c",decoded);line[length]=decoded;
  if(decoded==10)begin
   if(line[length-1]!=13)$fatal(1,"FAIL: missing CR");
   if(line[0]=="T")begin if(length!=54)$fatal(1,"FAIL: T frame interleaved");telemetry=telemetry+1;end
   else if(line[0]=="@"&&line[1]=="I")begin
    if(line[3]=="T")begin if(length!=28)$fatal(1,"FAIL: TRJ capability length %0d",length);capabilities=capabilities+1;end
    else begin if(length!=23)$fatal(1,"FAIL: ARM capability length");arm_caps=arm_caps+1;end
   end else if(line[0]=="@"&&line[1]=="V")begin
    if(length!=97)$fatal(1,"FAIL: VEL status length");
   end else if(line[0]=="@"&&line[1]=="W")begin
    if(length!=116)$fatal(1,"FAIL: VEL3 status length");
   end else if(line[0]=="@"&&line[1]=="T")begin
    if(length!=88)$fatal(1,"FAIL: TRJ status interleaved/length %0d",length);
    reports=reports+1;last_code=hex(line[8])*16+hex(line[9]);
   end else if(line[0]=="@"&&line[1]=="R")begin if(length!=33)$fatal(1,"FAIL: ARM report length");end
   else $fatal(1,"FAIL: unexpected serial line");
   length=0;
  end else begin length=length+1;if(length>127)$fatal(1,"FAIL: overflow");end
 end
 reg signed [31:0] saved_i,saved_previous;
 initial begin
  $dumpfile("tb_acg720_trajectory.vcd");$dumpvars(0,clk,rx,tx,sample_tick,position,dut.actual_position_ms,dut.trajectory_phase,dut.position_target_q,dut.state);
  file=$fopen("trajectory_serial.log","wb");
  force dut.sample_ready=1;force dut.sample_valid=sample_tick;force dut.sample=12'd1007;
  force dut.sensor_fault=0;force dut.raw_position=position;force dut.display_angle_valid=1;force dut.displayed_angle=0;
  clocks(4);rst_n=1;clocks(30);
  byte_send("P");wait(dut.telemetry_active);command("@TI\n");wait(capabilities==1);
  command("@I\n");wait(arm_caps==1);clocks(100);
  command("@T,1,1,1000,0,1,1,+50SCD\n");clocks(13000);
  if(dut.state!=0 || dut.display_raw)$fatal(1,"FAIL: framed legacy injection");
  command("@T,91,1,");clocks(200050);command("SCDQ\n");clocks(13000);
  if(dut.state!=0 || dut.display_raw || !dut.telemetry.enabled)$fatal(1,"FAIL: expired packet tail escaped quarantine");
  command("@TC,1,20\n");wait(last_code==4);clocks(100);
  if(dut.actual_position_ms!=20||last_code!=4)$fatal(1,"FAIL: stopped period write");
  key3;if(dut.state!=4||dut.relative_position!=0)$fatal(1,"FAIL: K3 origin");
  position=1226;command("@TC,2,5\n");clocks(13000);
  if(dut.period_pending||dut.actual_position_ms!=20||last_code!=17)$fatal(1,"FAIL: running period allowed");
  repeat(20)ms;saved_i=dut.core.position_pid.integral_q;saved_previous=dut.core.position_pid.previous_q;
  if(saved_i==0||saved_previous!=8*65536)$fatal(1,"FAIL: PID boundary history");
  repeat(19)ms;
  if(dut.core.position_pid.integral_q!=saved_i)$fatal(1,"FAIL: extra PID update");
  ms;if(dut.core.position_pid.integral_q==saved_i)$fatal(1,"FAIL: original interval absent");
  byte_send("X");clocks(13000);
  command("@TC,20,5\n");clocks(13000);
  command("@TVE,21,20,6554,1311,0,32768,0\n");clocks(15000);
  position=1234;key3;key2;repeat(200)ms;
  if(!dut.outer_speed)$fatal(1,"FAIL: speed entry required for trajectory");command("@T,3,1,1000,0,1,1,+50\n");wait(dut.trajectory_phase==2);wait(last_code==1);clocks(100);
  if(!dut.trajectory_selected||last_code!=1)$fatal(1,"FAIL: task selection/ACK");
  command("@TC,4,50\n");wait(last_code==17);clocks(100);if(dut.actual_position_ms!=5||last_code!=17)$fatal(1,"FAIL: period changed while moving");
  command("@M,1,+100\n");clocks(5000);if(dut.arm_busy)$fatal(1,"FAIL: ARM1 interlock");
  repeat(1000)ms;if(dut.trajectory_phase!=3)$fatal(1,"FAIL: reference deadline");
  // Protocol coordinates are registered; allow the first coincident sample to settle.
  position=1240;repeat(201)ms;clocks(13000);
  if(dut.trajectory_busy||last_code!=2||dut.position_target_q!=dut.trajectory_goal_q)$fatal(1,"FAIL: actual arrival/hold");
  command("@T,5,4,1000,0,1,1,-50\n");wait(dut.trajectory_phase==2);repeat(10)ms;
  keys[3]=0;clocks(1100);keys[3]=1;wait(last_code==3);clocks(100);
  if(dut.actual_position_ms!=5||dut.trajectory_busy||dut.state!=0||last_code!=3||dut.motor_ready)$fatal(1,"FAIL: K4 cancellation/config persistence");
  key3;key2;repeat(200)ms;command("@T,6,2,1000,0,2,1,+10\n");wait(dut.trajectory_phase==2);
  command("@T,7,1,1000,0,1,1,+5X");clocks(14000);
  if(dut.trajectory_busy||dut.state!=0||dut.motor_ready||dut.actual_position_ms!=5)$fatal(1,"FAIL: X inside packet");
  command("@TQ\n");repeat(200)ms;command("@TQ\n");clocks(13000);
  if(!dut.telemetry.enabled||telemetry<5)$fatal(1,"FAIL: status leaked legacy Q or starved telemetry");
  byte_send("Q");clocks(6000);if(dut.telemetry.enabled)$fatal(1,"FAIL: legacy Q");
  rst_n=0;clocks(10);if(dut.actual_position_ms!=50)$fatal(1,"FAIL: power reset default");
  $fclose(file);$display("TEST PASSED: tb_acg720_trajectory (physical UART, both protocols/T, period/PID boundary, K4 persistence, task interlocks, deadlines, actual settle, X, reset)");$finish;
 end
 initial begin #30000000;$fatal(1,"FAIL: board trajectory timeout");end
endmodule
