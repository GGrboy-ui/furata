`timescale 1ns/1ps
module tb_acg720_arm_damping;
 reg clk=0,rst_n=0,enc_a=0,enc_b=0;
 wire stby,pwm,in1,in2;
 // Fractional gain and a nondefault limit verify board-to-core parameter wiring.
 acg720_top #(.CENTER(1005),.ENCODER_INVERT(1),.CLK_HZ(100000),.BAUD(1000),.PWM_HZ(1000),
   .ARM_DAMPING_KD(32768),.ARM_DAMPING_LIMIT_PERCENT(3)) dut (
   .clk(clk),.rst_n(rst_n),.uart_rx(1'b1),.enc_a(enc_a),.enc_b(enc_b),.board_adc_dout(1'b0),
   .key1_n(1'b1),.key2_n(1'b1),.key3_n(1'b1),.key4_n(1'b1),
   .stby_fpga(stby),.pwm_a(pwm),.ain1(in1),.ain2(in2));
 defparam dut.core.ANGLE_KP=0;
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
 initial begin
   $dumpfile("tb_acg720_arm_damping.vcd");$dumpvars(0,tb_acg720_arm_damping);
   force dut.sample_ready=1'b1;force dut.sample_valid=1'b0;
   force dut.sensor_fault=4'd0;force dut.sample=12'd1005;
   cycles(3);rst_n=1;cycles(30);
   repeat(4) edge_step(1); // movement before capture cannot contribute damping
   force dut.balance_cmd=1'b1;cycles(1);release dut.balance_cmd;cycles(300);
   window;
   if(dut.command_q!==0 || dut.core.origin!==-4) $fatal(1,"FAIL: initial capture");
   repeat(3) edge_step(1);window;
   if(dut.raw_position!==7 || dut.position!==-7 || dut.command_q!==98304)
     $fatal(1,"FAIL: encoder inversion/fractional damping");
   edge_step(1);window; // +1 raw -> +0.5 percent, no premature truncation
   if(dut.command_q!==32768) $fatal(1,"FAIL: fractional single count");
   repeat(4) edge_step(1);window;cycles(4000);
   if(dut.command_q!==2*65536 || dut.pwm_command!==-2 || dut.requested_pwm!==2 ||
      dut.actual_pwm!==2 || in1!==0 || in2!==1 || !stby)
     $fatal(1,"FAIL: positive logical damping did not reach inverted motor/telemetry");
   repeat(4) edge_step(-1);window;cycles(4000);
   if(dut.command_q!==-2*65536 || dut.actual_pwm!==-2 || in1!==1 || in2!==0)
     $fatal(1,"FAIL: reverse damping did not reach motor");
   repeat(8) edge_step(-1);window;
   if(dut.command_q!==-3*65536) $fatal(1,"FAIL: top damping limit ignored");
   window;cycles(4000);
   if(dut.command_q!==0 || dut.actual_pwm!==0) $fatal(1,"FAIL: stopped arm retained torque");
   repeat(4) edge_step(1);window;
   force dut.key_press=4'b1000;cycles(1);
   if(dut.command_q!==0 || dut.core.arm_damping_q!==0 || stby || pwm || in1 || in2)
     $fatal(1,"FAIL: K4 did not clear damping and inhibit motor");
   release dut.key_press;cycles(30);
   $display("TEST PASSED: tb_acg720_arm_damping (QEI, inversion, fractional gain, motor, telemetry, K4)");$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: board damping timeout");end
endmodule
