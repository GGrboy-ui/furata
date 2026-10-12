`timescale 1ns/1ps
module tb_uart_telemetry_position;
 localparam integer DIV=50000000/115200, BIT_NS=DIV*20;
 reg clk=0,rst_n=0,rx=1;
 reg signed [15:0] arm=203,target=0,error=-203,offset=-125;
 wire tx;
 wire [7:0] received_byte,tx_data;
 wire received_valid,tx_valid,tx_ready,active;
 integer count=0,bytes=0,serial_file,k;
 reg [439:0] frame=0;
 reg [7:0] decoded;
 reg collecting=0;
 uart_commands #(.CLK_HZ(50000000),.BAUD(115200),.TELEMETRY(1)) uart (
   .clk(clk),.rst_n(rst_n),.rx(rx),.tx(tx),.received_byte(received_byte),.received_valid(received_valid),
   .tx_data(tx_data),.tx_valid(tx_valid),.tx_frame_active(active),.tx_ready(tx_ready));
 uart_telemetry #(.CLK_HZ(50000000),.POSITION_FIELDS(1)) dut (
   .clk(clk),.rst_n(rst_n),.received_byte(received_byte),.received_valid(received_valid),
   .angle_tenths(-16'sd123),.angle_valid(1'b1),.requested_pwm(-16'sd2500),.actual_pwm(-16'sd17),
   .arm_position(arm),.position_target(target),.position_error(error),.target_offset_adc_tenths(offset),
   .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),.frame_active(active));
 always #10 clk=~clk;
 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task command;input [7:0] v;integer j;begin
   rx=0;cycles(DIV);for(j=0;j<8;j=j+1) begin rx=v[j];cycles(DIV);end
   rx=1;cycles(DIV*2);
 end endtask
 initial forever begin
   @(negedge tx);#(BIT_NS/2);if(tx!==0) $fatal(1,"FAIL: start bit");
   for(k=0;k<8;k=k+1) begin #BIT_NS;decoded[k]=tx;end
   #BIT_NS;if(tx!==1) $fatal(1,"FAIL: stop bit");
   $fwrite(serial_file,"%c",decoded);
   if(decoded=="T") begin frame=0;bytes=0;collecting=1;end
   if(collecting) begin frame={frame[431:0],decoded};bytes=bytes+1;end
   if(collecting && decoded==10) begin
     if(bytes!=55) $fatal(1,"FAIL: extended frame length=%0d",bytes);
     case(count)
       0:if(frame!=={"T,00000000,-012.3,-2500,-0017,+0203,+0000,-0203,-0125",8'h0d,8'h0a}) $fatal(1,"FAIL: extended initial snapshot [%s]",frame);
       1:if(frame!=={"T,00000001,-012.3,-2500,-0017,-0204,+0005,-0199,+1000",8'h0d,8'h0a}) $fatal(1,"FAIL: extended changed snapshot [%s]",frame);
       2:if(frame!=={"T,00000002,-012.3,-2500,-0017,-0204,+0005,-0199,+1000",8'h0d,8'h0a}) $fatal(1,"FAIL: missing default-baud sequence [%s]",frame);
     endcase
     count=count+1;bytes=0;frame=0;collecting=0;
   end
 end
 initial begin
   $dumpfile("tb_uart_telemetry_position.vcd");$dumpvars(0,clk,rst_n,rx,tx,count);
   serial_file=$fopen("telemetry_position_serial.log","wb");
   cycles(4);rst_n=1;cycles(10);command("P");
   wait(active);cycles(100);arm=-204;target=5;error=-199;offset=1000;
   wait(count==2);wait(!active);wait(active);command("Q");wait(count==3);cycles(250000);
   if(count!=3 || dut.enabled) $fatal(1,"FAIL: Q drain");
   $fclose(serial_file);$display("TEST PASSED: tb_uart_telemetry_position (55 physical bytes, signed metadata, snapshot, 200 Hz at 115200, Q drain)");$finish;
 end
 initial begin #100000000;$fatal(1,"FAIL: extended serial timeout");end
endmodule
