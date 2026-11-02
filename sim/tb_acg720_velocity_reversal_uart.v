`timescale 1ns/1ps
module tb_acg720_velocity_reversal_uart;
reg clk=0,rst_n=0,rx=1,a=0,b=0,tick=0;always #5 clk=~clk;
integer timer=0,j,k,len=0,frames=0,actual=0,i;reg [7:0] c,line[0:127];wire tx;
acg720_top #(.CLK_HZ(1000000),.BAUD(100000)) dut(.clk(clk),.rst_n(rst_n),.uart_rx(rx),.enc_a(a),.enc_b(b),.board_adc_dout(1'b0),.key1_n(1'b1),.key2_n(1'b1),.key3_n(1'b1),.key4_n(1'b1),.uart_tx(tx));
always @(negedge clk)begin if(timer==999)begin timer=0;tick=1;end else begin timer=timer+1;tick=0;end end
task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
task forward;begin case({a,b})0:{a,b}=1;1:{a,b}=3;3:{a,b}=2;2:{a,b}=0;endcase clocks(10000);end endtask
task reverse;begin case({a,b})0:{a,b}=2;2:{a,b}=3;3:{a,b}=1;1:{a,b}=0;endcase clocks(10000);end endtask
 task byte_send;input [7:0] v;integer i;begin rx=0;clocks(10);for(i=0;i<8;i=i+1)begin rx=v[i];clocks(10);end rx=1;clocks(20);end endtask
task command;input string v;integer i;begin for(i=0;i<v.len();i=i+1)byte_send(v[i]);end endtask
function integer hex;input [7:0] v;begin hex=v<="9" ? v-"0":v-"A"+10;end endfunction
initial forever begin
@(negedge tx);#50;for(k=0;k<8;k=k+1)begin #100;c[k]=tx;end #100;
$write("%c",c);line[len]=c;
if(c==10)begin
if(line[1]=="W")begin
actual=0;for(j=0;j<8;j=j+1)actual=(actual<<4)|hex(line[84+j]);frames=frames+1;
end
len=0;
end else len=len+1;
end
initial begin
$dumpfile("tb_acg720_velocity_reversal_uart.vcd");$dumpvars(1,tb_acg720_velocity_reversal_uart);
force dut.sample_ready=1;force dut.sensor_fault=0;force dut.sample=12'd3124;force dut.sample_valid=tick;
clocks(5);rst_n=1;clocks(1000);repeat(12)forward;
$display("BOARD actual pos=%0d feedbackQ=%0d",dut.raw_position,dut.raw_control_velocity_q);
if(dut.raw_position!=12||dut.raw_control_velocity_q<=0)$fatal(1,"FAIL: real AB board feedback");
command("@TV3\n");clocks(4000);command("@TVS\n");clocks(14000);
if(frames!=1||actual<=0)$fatal(1,"FAIL: feedback lost in physical UART actual=%0d frames=%0d",actual,frames);
for(i=0;i<40;i=i+1)begin if(i%2==0)reverse;else forward;end
 if(dut.raw_position!=12)$fatal(1,"FAIL: alternating position changed net coordinate");
 command("@TVS\n");clocks(14000);
 if(frames!=2||actual==0)$fatal(1,"FAIL: alternating AB feedback lost in physical UART actual=%0d frames=%0d",actual,frames);
 $display("TEST PASSED: tb_acg720_velocity_reversal_uart (real AB, signed reversing feedback, position retained, physical W UART)");$finish;
end
initial begin #10000000;$fatal(1,"FAIL: board timeout");end
endmodule
