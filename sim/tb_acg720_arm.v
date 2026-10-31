`timescale 1ns/1ps
module tb_acg720_arm;
 reg clk=0,rst_n=0,rx=1,sample_tick=0;
 reg [3:0] keys=4'hf;
 reg signed [31:0] absolute_position=1234;
 wire tx;
 reg [7:0] line[0:80];reg [7:0] decoded;
 integer length=0,k,capabilities=0,reports=0,telemetry=0,last_code=-1;
 integer serial_file;
 acg720_top #(.CENTER(1000),.DEFAULT_OUTER_SPEED(0),.CLK_HZ(1000000),.BAUD(100000),.KEY_DEBOUNCE_MS(1)) dut(
   .clk(clk),.rst_n(rst_n),.uart_rx(rx),.enc_a(1'b0),.enc_b(1'b0),.board_adc_dout(1'b0),
   .key1_n(keys[0]),.key2_n(keys[1]),.key3_n(keys[2]),.key4_n(keys[3]),.uart_tx(tx));
 always #5 clk=~clk;
 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task send_byte;input [7:0] c;integer j;begin
   rx=0;cycles(10);for(j=0;j<8;j=j+1) begin rx=c[j];cycles(10);end rx=1;cycles(20);
 end endtask
 task command;input [255:0] text;input integer n;integer j;begin
   for(j=n-1;j>=0;j=j-1) send_byte(text[j*8+:8]);
 end endtask
 task tick;begin sample_tick=1;cycles(1);sample_tick=0;cycles(1);end endtask
 function integer hex;input [7:0] c;begin hex=c<="9"?c-"0":c-"A"+10;end endfunction
 initial forever begin
   @(negedge tx);#50;if(tx!==0) $fatal(1,"FAIL: UART start");
   for(k=0;k<8;k=k+1) begin #100;decoded[k]=tx;end
   #100;if(tx!==1) $fatal(1,"FAIL: UART stop");
   $fwrite(serial_file,"%c",decoded);line[length]=decoded;
   if(decoded==10) begin
     if(line[length-1]!=13) $fatal(1,"FAIL: missing CR");
     if(line[0]=="T") begin
       if(length!=54) $fatal(1,"FAIL: telemetry interrupted by response, length=%0d",length);
       telemetry=telemetry+1;
     end else if(line[0]=="@" && line[1]=="I") begin
       if(length!=23) $fatal(1,"FAIL: capability interrupted");capabilities=capabilities+1;
     end else if(line[0]=="@" && line[1]=="R") begin
       if(length!=33) $fatal(1,"FAIL: response interrupted");
       last_code=hex(line[8])*16+hex(line[9]);reports=reports+1;
     end else $fatal(1,"FAIL: unexpected echo/line prefix %c",line[0]);
     length=0;
   end else begin length=length+1;if(length>79) $fatal(1,"FAIL: line overflow");end
 end
 initial begin
   $dumpfile("tb_acg720_arm.vcd");$dumpvars(0,clk,rst_n,rx,tx,absolute_position,sample_tick,dut.state,dut.arm_busy);
   serial_file=$fopen("arm_serial.log","wb");
   force dut.sample_ready=1'b1;force dut.sample_valid=sample_tick;
   force dut.sample=12'd1007;force dut.sensor_fault=4'd0;force dut.raw_position=absolute_position;
   force dut.display_angle_valid=1'b1;force dut.displayed_angle=16'sd0;
   cycles(4);rst_n=1;cycles(30);
   send_byte("P");wait(dut.telemetry_active);command("@I\n",3);
   wait(capabilities==1);cycles(100);
   command("@Q\n",3);wait(reports==1);cycles(100);
   if(!dut.telemetry.enabled || dut.state!==0) $fatal(1,"FAIL: query changed telemetry/control");
   // Embedded legacy S/C/D cannot escape an invalid framed command.
   command("@M,1,+60SCD\n",12);cycles(13000);
   if(dut.state!==0 || dut.display_raw) $fatal(1,"FAIL: legacy packet injection");
   keys[2]=0;cycles(1100);keys[2]=1;cycles(1100);
   if(dut.state!==4 || dut.relative_position!==0) $fatal(1,"FAIL: K3 capture");
   command("@M,1,+600\n",10);cycles(12000);
   if(!dut.arm_busy || dut.position_goal_q!==68*65536 || dut.state!==4)
     $fatal(1,"FAIL: accepted relative move during stream");
   command("@M,2,-400\n",10);cycles(12000);
   if(last_code!=16 || dut.position_goal_q!==68*65536) $fatal(1,"FAIL: busy rejection");
   // Allow the registered protocol coordinate to settle before 200 arrival samples.
   repeat(2100) tick;absolute_position=1302;cycles(2);repeat(200) tick;cycles(12000);
   if(dut.arm_busy || last_code!=2) $fatal(1,"FAIL: board arrival");
   command("@M,2,-400\n",10);cycles(12000);
   if(dut.position_goal_q!==1485483) $fatal(1,"FAIL: board -40 relative target");
   // K4 cancels the move without clearing raw encoder count.
   keys[3]=0;cycles(1100);keys[3]=1;cycles(13000);
   if(dut.arm_busy || dut.state!==0 || dut.raw_position!==1302 || last_code!=3)
     $fatal(1,"FAIL: K4 cancellation/state retention");
   keys[2]=0;cycles(1100);keys[2]=1;cycles(1100);
   command("@M,3,+3600\n",11);cycles(12000);
   if(!dut.arm_busy || dut.position_goal_q!==408*65536) $fatal(1,"FAIL: board full turn");
   command("@M,4,+6X",8);cycles(12000);
   if(dut.arm_busy || dut.state!==0 || last_code!=3) $fatal(1,"FAIL: X inside packet did not stop");
   if(!dut.telemetry.enabled || telemetry<8) $fatal(1,"FAIL: response starved telemetry");
   command("@Q\n",3);cycles(12000);if(!dut.telemetry.enabled) $fatal(1,"FAIL: Q query leaked to legacy Q");
   send_byte("Q");cycles(12000);if(dut.telemetry.enabled) $fatal(1,"FAIL: legacy Q stopped working");
   $fclose(serial_file);
   $display("TEST PASSED: tb_acg720_arm (physical bidirectional UART, telemetry arbitration, K3/K4/X, framed legacy isolation, relative moves)");$finish;
 end
 initial begin #12000000;$fatal(1,"FAIL: board arm timeout");end
endmodule
