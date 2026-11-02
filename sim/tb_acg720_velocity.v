`timescale 1ns/1ps
// Protocol/datapath integration fixture; not a mechanical plant model.
module tb_acg720_velocity;
 reg clk=0,rst_n=0,rx=1,sample_tick=0;always #5 clk=~clk;
 reg [3:0] keys=15;reg signed [31:0] position=500,measured=0;
 wire tx;integer i,length=0,caps=0,pos_caps=0,reports=0,last_code=-1,pos_reports=0,pos_code=-1,file,m,n;
 reg [7:0] line[0:127],decoded;
 acg720_top #(.CENTER(1000),.CLK_HZ(1000000),.BAUD(100000),.KEY_DEBOUNCE_MS(1)) dut(
  .clk(clk),.rst_n(rst_n),.uart_rx(rx),.enc_a(1'b0),.enc_b(1'b0),.board_adc_dout(1'b0),
  .key1_n(keys[0]),.key2_n(keys[1]),.key3_n(keys[2]),.key4_n(keys[3]),.uart_tx(tx));
 task clocks;input integer count;begin repeat(count)@(negedge clk);end endtask
 task byte_send;input [7:0] value;integer j;begin rx=0;clocks(10);for(j=0;j<8;j=j+1)begin rx=value[j];clocks(10);end rx=1;clocks(20);end endtask
 task command;input string text;integer j;begin for(j=0;j<text.len();j=j+1)byte_send(text[j]);end endtask
 task ms;begin sample_tick=1;clocks(1);sample_tick=0;clocks(350);if(^dut.angle_target_offset_q===1'bx||^dut.command_q===1'bx)$fatal(1,"FAIL: unknown controller output");end endtask
 task key2;begin keys[1]=0;clocks(1100);keys[1]=1;clocks(1100);end endtask
 task key1;begin keys[0]=0;clocks(1100);keys[0]=1;clocks(1100);end endtask
 task key3;begin keys[2]=0;clocks(1100);keys[2]=1;clocks(1100);end endtask
 function integer hex;input [7:0] c;begin hex=c<="9"?c-"0":c-"A"+10;end endfunction
 initial forever begin
  @(negedge tx);#50;if(tx!==0)$fatal(1,"FAIL: UART start");
  for(i=0;i<8;i=i+1)begin #100;decoded[i]=tx;end
  #100;if(tx!==1)$fatal(1,"FAIL: UART stop");
  $fwrite(file,"%c",decoded);line[length]=decoded;
  if(decoded==10)begin
   if(line[length-1]!=13)$fatal(1,"FAIL: CRLF");
   if(line[0]=="T")begin if(length!=54)$fatal(1,"FAIL: telemetry interleave");end
   else if(line[1]=="P")begin
    if(length!=45)$fatal(1,"FAIL: POS frame length %0d",length);
    pos_reports=pos_reports+1;pos_code=hex(line[8])*16+hex(line[9]);
   end else if(line[1]=="W")begin
    if(length!=116)$fatal(1,"FAIL: VEL3 length %0d",length);
    reports=reports+1;last_code=hex(line[8])*16+hex(line[9]);
   end else if(line[1]=="I"&&line[3]=="P")begin
    if(length!=8)$fatal(1,"FAIL: POS capability length");pos_caps=pos_caps+1;
   end else if(line[1]=="V")begin
    if(length!=97&&length!=102)$fatal(1,"FAIL: VEL frame length %0d",length);
    if(length==102 && hex(line[97])*4096+hex(line[98])*256+hex(line[99])*16+hex(line[100])!=dut.speed_friction_t)$fatal(1,"FAIL: t readback mismatch");
    reports=reports+1;last_code=hex(line[8])*16+hex(line[9]);
   end else if(line[1]=="I"&&line[3]=="V")begin
    if(length!=((line[6]=="2"||line[6]=="3")?28:23))$fatal(1,"FAIL: capability length %0d",length);caps=caps+1;
   end else if(line[1]=="T")begin if(length!=88)$fatal(1,"FAIL: TRJ framing");end
   else if(line[1]=="R")begin if(length!=33)$fatal(1,"FAIL: ARM framing");end
   else $fatal(1,"FAIL: unknown frame");
   length=0;
  end else begin length=length+1;if(length>127)$fatal(1,"FAIL: line overflow");end
 end
 task response;input integer previous;begin wait(reports>previous);clocks(50);end endtask
 integer before_report,old_pos;reg signed [31:0] saved_output,saved_origin,saved_goal;
 initial begin
  $dumpfile("tb_acg720_velocity.vcd");$dumpvars(1,tb_acg720_velocity);
  file=$fopen("velocity_serial.log","wb");
  force dut.sample_ready=1;force dut.sample_valid=sample_tick;force dut.sample=12'd1000;
  force dut.sensor_fault=0;force dut.raw_position=position;force dut.raw_control_velocity_q=measured;
  force dut.display_angle_valid=1;force dut.displayed_angle=0;
  clocks(4);rst_n=1;clocks(30);
  if(dut.outer_speed||dut.speed_period_ms!=20)$fatal(1,"FAIL: power-on position defaults");
  clocks(1100);key2;if(dut.state!=0||dut.outer_speed)$fatal(1,"FAIL: K2 started STOP motor");key3;if(dut.state!=4)$fatal(1,"FAIL: position balance");
  repeat(50)ms;
  if(dut.core.speed_out!=0)$fatal(1,"FAIL: inactive speed PI output");
  command("@T,40,1,1000,0,1,1,+10\n");clocks(2000);
  if(!dut.trajectory_busy||!dut.trajectory_selected||dut.trajectory_event_code!=1)$fatal(1,"FAIL: position mode rejected trajectory");
  repeat(250)ms;key2;
  if(dut.outer_speed||dut.core.speed_out!=0||dut.core.position_out==0||dut.angle_target_offset_q!= -dut.core.position_out)$fatal(1,"FAIL: profile bypassed position PID or K2 switched during trajectory");
  byte_send("X");clocks(15000);key3;
  command("@M,30,+10\n");wait(dut.arm_busy);repeat(50)ms;
  if(dut.core.speed_out!=0||dut.angle_target_offset_q==0)$fatal(1,"FAIL: position outer loop ARM feedback");
  byte_send("X");clocks(15000);
  byte_send("P");command("@TVI\n");wait(caps==1);
  before_report=reports;command("@TVQ\n");response(before_report);
  command("@TV2\n");wait(caps==2);
  repeat(200)ms;before_report=reports;command("@TVR\n");response(before_report);
  command("@TPI\n");wait(pos_caps==1);command("@TV3\n");wait(caps==3);
  old_pos=pos_reports;command("@TPQ\n");wait(pos_reports>old_pos);
  if(pos_code!=0||dut.actual_position_ms!=50||dut.position_kp_q!=dut.core.POSITION_KP||dut.position_ki_q!=dut.core.POSITION_KI||dut.position_kd_q!=dut.core.POSITION_KD)$fatal(1,"FAIL: new position query defaults");
  repeat(200)ms;before_report=reports;command("@TVS\n");response(before_report);
  if(dut.speed_friction_t!=0)$fatal(1,"FAIL: t default");
  before_report=reports;command("@TVC,1,0,30,0,0,0\n");response(before_report);
  if(last_code!=4||dut.outer_speed||dut.speed_period_ms!=30||dut.speed_kp_q!=0)$fatal(1,"FAIL: atomic position-mode config");
  before_report=reports;command("@TVC,2,1,4,65536,0,32768\n");response(before_report);
  if(last_code!=18||dut.outer_speed||dut.speed_period_ms!=30)$fatal(1,"FAIL: invalid config partially applied");
  before_report=reports;command("@TVE,3,20,65536,0,0,32768,7\n");response(before_report);
  if(last_code!=4||dut.outer_speed||dut.speed_kp_q!=65536||dut.speed_friction_t!=7)$fatal(1,"FAIL: speed mode config");
  before_report=reports;command("@TVE,5,30,0,0,0,0,51\n");response(before_report);
  if(last_code!=18||dut.outer_speed||dut.speed_friction_t!=7||dut.speed_kp_q!=65536)$fatal(1,"FAIL: invalid t partially applied config");
  before_report=reports;command("@TVE,29,25,8192,1638,1966,39322,9\n");response(before_report);
  old_pos=pos_reports;command("@TPC,30,30,65536,1311,2621\n");wait(pos_reports>old_pos);
  if(pos_code!=4||dut.position_kp_q!=65536||dut.position_ki_q!=1311||dut.position_kd_q!=2621||dut.actual_position_ms!=30||dut.speed_period_ms!=25||dut.speed_kp_q!=8192||dut.speed_ki_q!=1638||dut.speed_kd_q!=1966||dut.speed_kpos_q!=39322||dut.speed_friction_t!=9)$fatal(1,"FAIL: position config leaked into speed bank");
  before_report=reports;command("@TVE,31,20,65536,0,0,32768,7\n");response(before_report);
  if(dut.position_kp_q!=65536||dut.position_ki_q!=1311||dut.position_kd_q!=2621||dut.actual_position_ms!=30)$fatal(1,"FAIL: speed config leaked into position bank");
  old_pos=pos_reports;command("@TPC,34,30,65536,0,0\n");wait(pos_reports>old_pos);
  if(dut.speed_period_ms!=20||dut.speed_kp_q!=65536||dut.speed_ki_q!=0||dut.speed_kd_q!=0||dut.speed_kpos_q!=32768||dut.speed_friction_t!=7)$fatal(1,"FAIL: position restore changed speed bank");
  old_pos=pos_reports;command("@TPC,32,10,4194305,0,0\n");wait(pos_reports>old_pos);
  if(pos_code!=18||dut.position_kp_q!=65536||dut.actual_position_ms!=30)$fatal(1,"FAIL: bad position config partially applied");
  key3;if(dut.state!=4||dut.outer_speed)$fatal(1,"FAIL: manual balance must choose position");
  saved_origin=dut.core.origin;saved_goal=dut.position_goal_q;
  key2;if(!dut.outer_speed||dut.handover_remaining==0||dut.core.origin!=saved_origin||dut.position_goal_q!=saved_goal)$fatal(1,"FAIL: K2 transfer origin/goal");
  key2;repeat(200)ms;
  if(dut.handover_remaining!=0||dut.applied_friction_t!=7)$fatal(1,"FAIL: handover end/t");
  force dut.command_q=32'sd655360;clocks(8);
  if(dut.requested_pwm!=12)$fatal(1,"FAIL: positive velocity t not applied");
  force dut.command_q=-32'sd655360;clocks(8);
  if(dut.requested_pwm!=-12)$fatal(1,"FAIL: negative velocity t not applied");
  force dut.command_q=0;clocks(8);
  if(dut.requested_pwm!=0)$fatal(1,"FAIL: zero request got t");
  release dut.command_q;
  before_report=reports;command("@TVD,4,0,30,0,0,0,8\n");response(before_report);
  if(last_code!=17||!dut.outer_speed||dut.speed_period_ms!=20||dut.speed_friction_t!=7)$fatal(1,"FAIL: running config accepted");
  command("@TC,21,10\n");clocks(15000);
  if(dut.actual_position_ms!=30||dut.speed_period_ms!=20)$fatal(1,"FAIL: running legacy position period accepted");
  old_pos=pos_reports;command("@TPC,33,10,0,0,0\n");wait(pos_reports>old_pos);if(pos_code!=17||dut.position_kp_q!=65536)$fatal(1,"FAIL: running position setting accepted");
  repeat(20)ms;saved_output=dut.core.speed_out;measured=65536;repeat(20)ms;
  if(dut.core.speed_out>=saved_output||dut.core.position_pid.integral_q!=0)$fatal(1,"FAIL: measured speed not in selected feedback");
  measured=0;
  command("@T,41,1,1000,0,1,1,+10\n");clocks(2000);
  if(dut.trajectory_busy||dut.trajectory_event_code!=17)$fatal(1,"FAIL: speed mode accepted position-only trajectory");
  byte_send("X");clocks(15000);key3;
  // Four position-PID profiles through the physical UART, with integer position following
  // injected only to exercise completion/hold, never to claim tracking quality.
  for(m=1;m<=4;m=m+1)begin
   if(m==3)command("@T,13,3,1000,20,1,2,+10,-10\n");
   else command($sformatf("@T,%0d,%0d,1000,0,1,1,+10\n",10+m,m));
   wait(dut.trajectory_phase==2);n=0;
   while(dut.trajectory_phase==2)begin
    ms;position=500+($signed(dut.position_target_q)>>>16);n=n+1;
    if(dut.reference_velocity_q!==dut.trajectory_velocity_q)$fatal(1,"FAIL: reference velocity disconnected");
    if(dut.outer_speed||dut.core.speed_out!=0||dut.angle_target_offset_q!= -dut.core.position_out)$fatal(1,"FAIL: mode %0d not using position PID",m);
    if(n>2200)$fatal(1,"FAIL: trajectory deadline mode %0d",m);
   end
   position=500+($signed(dut.trajectory_goal_q)>>>16);repeat(220)ms;
   if(dut.trajectory_phase!=4||dut.reference_velocity_q!=0)$fatal(1,"FAIL: finish/zero-speed hold mode %0d",m);
  end
  key2;repeat(200)ms;
  command("@M,1,+10\n");wait(dut.arm_busy);repeat(30)ms;
  if(dut.reference_velocity_q==0||dut.reference_velocity_q!==dut.legacy_velocity_q)$fatal(1,"FAIL: ARM ramp reference");
  byte_send("X");clocks(15000);
  if(dut.state!=0||dut.motor_ready||dut.speed_period_ms!=20||!dut.outer_speed)$fatal(1,"FAIL: X stop/config persistence");
  keys[3]=0;clocks(1100);keys[3]=1;clocks(1100);
  if(!dut.outer_speed||dut.speed_kp_q!=65536||dut.speed_friction_t!=7)$fatal(1,"FAIL: K4 lost config");
  before_report=reports;command("@TVE,35,20,65536,0,1966,32768,7\n");response(before_report);
  before_report=reports;command("@TVC,7,1,20,65536,0,32768\n");response(before_report);
  if(last_code!=4||dut.speed_friction_t!=7||dut.speed_kd_q!=1966)$fatal(1,"FAIL: legacy VEL1 config erased t/Kd");
  before_report=reports;command("@TVD,36,1,20,65536,0,32768,7\n");response(before_report);
  if(last_code!=4||dut.speed_kd_q!=1966)$fatal(1,"FAIL: legacy VEL2 config erased Kd");
  before_report=reports;command("@TVD,8,0,20,65536,0,32768,7\n");response(before_report);
  if(last_code!=17||!dut.outer_speed)$fatal(1,"FAIL: legacy mode changed key-owned state");
  key3;if(dut.outer_speed)$fatal(1,"FAIL: K3 did not restore position");force dut.command_q=32'sd655360;clocks(8);
  if(dut.requested_pwm!=5)$fatal(1,"FAIL: t affected position mode");
  release dut.command_q;byte_send("X");clocks(15000);
  command("@TVE,9,5,0,0,0,0,0X");clocks(15000);
  if(dut.outer_speed||dut.speed_friction_t!=7)$fatal(1,"FAIL: incomplete packet mutated config");
  rst_n=0;clocks(5);
  if(dut.outer_speed||dut.speed_period_ms!=20||dut.speed_kp_q!=6554||dut.speed_kd_q!=0||dut.speed_friction_t!=0||dut.position_kp_q!=dut.core.POSITION_KP||dut.position_ki_q!=dut.core.POSITION_KI||dut.position_kd_q!=dut.core.POSITION_KD)$fatal(1,"FAIL: system reset position defaults");
  $fclose(file);$display("TEST PASSED: tb_acg720_velocity (physical UART/T, VEL1, atomic config, two modes, feedback, four trajectories, ARM, X/K4, reset)");$finish;
 end
 initial begin #80000000;$fatal(1,"FAIL: velocity integration timeout");end
endmodule
