`timescale 1ns/1ps
module tb_acg720_balance_boost;
 reg clk=0,rst_n=0,enc_a=0,enc_b=0;
 wire stby,pwm,in1,in2;
 // Nondefault calibration-based half-width and increment verify top-to-core
 // forwarding. 3 degrees maps to floor(30*4095/3330)=36 ADC codes.
 acg720_top #(.CENTER(1005),.ENCODER_INVERT(1),.CLK_HZ(100000),.BAUD(1000),.PWM_HZ(1000),
   .BALANCE_BOOST_RANGE_TENTHS(30),.BALANCE_BOOST_MAX_PERCENT(3)) dut (
   .clk(clk),.rst_n(rst_n),.uart_rx(1'b1),.enc_a(enc_a),.enc_b(enc_b),.board_adc_dout(1'b0),
   .key1_n(1'b1),.key2_n(1'b1),.key3_n(1'b1),.key4_n(1'b1),
   .stby_fpga(stby),.pwm_a(pwm),.ain1(in1),.ain2(in2));
 defparam dut.core.ANGLE_KP=65536;
 defparam dut.core.ANGLE_KI=0;
 defparam dut.core.ANGLE_KD=0;
 defparam dut.core.POSITION_KP=0;
 defparam dut.core.POSITION_KI=0;
 defparam dut.core.POSITION_KD=0;
 always #5 clk=~clk;
 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task tick;begin force dut.sample_valid=1'b1;cycles(1);force dut.sample_valid=1'b0;cycles(5);end endtask
 task window;begin repeat(5) tick;end endtask
 task edge_step;input integer dir;begin
   case({enc_a,enc_b})
     0:{enc_a,enc_b}=(dir>0)?2'b01:2'b10;
     1:{enc_a,enc_b}=(dir>0)?2'b11:2'b00;
     3:{enc_a,enc_b}=(dir>0)?2'b10:2'b01;
     2:{enc_a,enc_b}=(dir>0)?2'b00:2'b11;
   endcase
   cycles(8);
 end endtask
 task expect_q;input integer expected;begin
   if(dut.command_q!==expected) $fatal(1,"FAIL: board expected command Q=%0d got %0d",expected,dut.command_q);
 end endtask

 initial begin
   $dumpfile("tb_acg720_balance_boost.vcd");$dumpvars(0,tb_acg720_balance_boost);
   if(dut.core.BALANCE_BOOST_RANGE_CODES!==36 || dut.core.BALANCE_BOOST_MAX_PERCENT!==3)
     $fatal(1,"FAIL: board compensation parameter conversion/forwarding");
   force dut.sample_ready=1'b1;force dut.sample_valid=1'b0;
   force dut.sensor_fault=4'd0;force dut.sample=12'd1005;
   cycles(3);rst_n=1;cycles(30);
   repeat(4) edge_step(1);
   force dut.balance_cmd=1'b1;cycles(1);release dut.balance_cmd;cycles(3);
   force dut.sample=12'd987;cycles(3);window;expect_q(1277952); // +18+1.5 percent
   if(dut.core.origin!==-4 || !stby || dut.wake_done || pwm || in1 || in2)
     $fatal(1,"FAIL: capture origin or two-millisecond driver wake gate");
   cycles(4000);
   if(dut.pwm_command!==-19 || dut.requested_pwm!==19 || dut.actual_pwm!==19 || in1!==0 || in2!==1)
     $fatal(1,"FAIL: compensation command did not reach inverted motor and telemetry");
   repeat(3) edge_step(1);window;expect_q(1277952);
   if(dut.raw_position!==7 || dut.position!==-7)
     $fatal(1,"FAIL: real encoder/inversion path not exercised");
   repeat(4) edge_step(-1);window;expect_q(1277952);

   force dut.sample=12'd1023;cycles(3);window;expect_q(-1277952);cycles(4000);
   if(dut.pwm_command!==19 || dut.actual_pwm!==-19 || in1!==1 || in2!==0)
     $fatal(1,"FAIL: negative compensation motor direction");
   force dut.sample=12'd1004;cycles(3);window;expect_q(70997); // +1+1/12 percent
   force dut.sample=12'd969;cycles(3);window;expect_q(2555904); // inclusive 36-code edge
   force dut.sample=12'd968;cycles(3);window;expect_q(2424832); // 37 codes: base only
   force dut.sample=12'd1005;cycles(3);window;expect_q(0);cycles(4000);
   if(dut.actual_pwm!==0) $fatal(1,"FAIL: center command retained motor torque");

   force dut.sample=12'd987;cycles(3);window;expect_q(1277952);
   force dut.sensor_fault=4'd3;#1;
   if(stby || pwm || in1 || in2) $fatal(1,"FAIL: sensor fault did not immediately inhibit motor");
   cycles(3);expect_q(0);
   if(dut.core.boost_magnitude_q!==0) $fatal(1,"FAIL: sensor fault retained compensation");
   force dut.sensor_fault=4'd0;
   force dut.key_press=4'b1000;cycles(1);
   if(dut.command_q!==0 || dut.core.boost_magnitude_q!==0 || stby || pwm || in1 || in2)
     $fatal(1,"FAIL: K4 reset did not clear compensation and inhibit motor");
   release dut.key_press;cycles(30);
   force dut.balance_cmd=1'b1;cycles(1);release dut.balance_cmd;cycles(3);window;expect_q(1277952);
   cycles(4000);
   force dut.key_press=4'b1000;cycles(1);
   if(dut.command_q!==0 || dut.core.boost_magnitude_q!==0 || stby || pwm || in1 || in2)
     $fatal(1,"FAIL: K4 while balancing retained active motor state");
   release dut.key_press;cycles(30);
   if(dut.state!==0 || dut.raw_position!==3) $fatal(1,"FAIL: K4 re-entry state or QEI preservation");
   $display("TEST PASSED: tb_acg720_balance_boost (calibration parameters, QEI independence, wake, fractions, motor/telemetry, boundaries, fault, K4)");
   $finish;
 end
 initial begin #2000000;$fatal(1,"FAIL: board compensation timeout");end
endmodule
