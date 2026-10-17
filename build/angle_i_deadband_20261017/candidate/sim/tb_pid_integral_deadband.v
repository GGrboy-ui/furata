`timescale 1ns/1ps
// Output-based fixtures: I-only exposes held accumulation, P/D-only prove that
// the deadband does not suppress either of those two control actions.
module tb_pid_integral_deadband;
 localparam signed [31:0] Q=65536, LIMIT=100*Q;
 reg clk=0,rst_n=0,clear=0,tick=0;
 reg signed [31:0] target=0,actual=0;
 wire signed [31:0] held_i,plain_i,negative_i,p_only,d_only;
 wire held_valid,plain_valid,negative_valid,p_valid,d_valid;
 always #5 clk=~clk;
 pid_fixed #(.KP(0),.KI(Q),.KD(0),.I_LIMIT(4*Q),.I_DEADBAND_Q(Q)) integral_dut (
   .clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),.target_q(target),.actual_q(actual),
   .out_q(held_i),.valid(held_valid));
 // Omit the parameter to verify that the generic module defaults to disabled.
 pid_fixed #(.KP(0),.KI(Q),.KD(0),.I_LIMIT(4*Q)) plain_dut (
   .clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),.target_q(target),.actual_q(actual),
   .out_q(plain_i),.valid(plain_valid));
 pid_fixed #(.KP(0),.KI(Q),.KD(0),.I_LIMIT(4*Q),.I_DEADBAND_Q(-Q)) negative_dut (
   .clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),.target_q(target),.actual_q(actual),
   .out_q(negative_i),.valid(negative_valid));
 pid_fixed #(.KP(Q),.KI(0),.KD(0),.I_DEADBAND_Q(Q)) proportional_dut (
   .clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),.target_q(target),.actual_q(actual),
   .out_q(p_only),.valid(p_valid));
 pid_fixed #(.KP(0),.KI(0),.KD(Q),.I_DEADBAND_Q(Q)) derivative_dut (
   .clk(clk),.rst_n(rst_n),.clear(clear),.tick(tick),.target_q(target),.actual_q(actual),
   .out_q(d_only),.valid(d_valid));
 function signed [31:0] clipped;
   input signed [31:0] value;
   begin clipped=(value>LIMIT) ? LIMIT : (value< -LIMIT) ? -LIMIT : value;end
 endfunction
 task check_zero;
   begin
     if(held_i!==0 || plain_i!==0 || negative_i!==0 || p_only!==0 || d_only!==0 ||
        held_valid!==0 || plain_valid!==0 || negative_valid!==0 || p_valid!==0 || d_valid!==0)
       $fatal(1,"FAIL: reset/clear did not clear outputs and pending validity");
   end
 endtask
 task step;
   input signed [31:0] expected_error,expected_held,expected_plain,expected_delta;
   reg signed [31:0] previous_output;
   begin
     @(negedge clk);previous_output=held_i;tick=1;
     @(posedge clk);#1;
     if(held_valid!==0 || plain_valid!==0 || negative_valid!==0 || p_valid!==0 || d_valid!==0 ||
        held_i!==previous_output) $fatal(1,"FAIL: deadband changed the capture/result pipeline");
     @(negedge clk);tick=0;
     @(posedge clk);#1;
     if(!held_valid || !plain_valid || !negative_valid || !p_valid || !d_valid)
       $fatal(1,"FAIL: missing PID result validity");
     if(held_i!==expected_held || plain_i!==expected_plain || negative_i!==expected_plain)
       $fatal(1,"FAIL: e=%0d held=%0d/%0d plain=%0d negative=%0d/%0d",
         expected_error,held_i,expected_held,plain_i,negative_i,expected_plain);
     if(p_only!==clipped(expected_error) || d_only!==clipped(expected_delta))
       $fatal(1,"FAIL: deadband suppressed P/D: e=%0d P=%0d D=%0d expected delta=%0d",
         expected_error,p_only,d_only,expected_delta);
     if(proportional_dut.integral_q!==0 || derivative_dut.integral_q!==0)
       $fatal(1,"FAIL: KI=0 retained an integral");
     @(negedge clk);
   end
 endtask
 task error_step;
   input signed [31:0] e,expected_held,expected_plain,expected_delta;
   begin target=e;actual=0;step(e,expected_held,expected_plain,expected_delta);end
 endtask
 initial begin
   $dumpfile("tb_pid_integral_deadband.vcd");$dumpvars(0,tb_pid_integral_deadband);
   repeat(3) @(negedge clk);rst_n=1;
   error_step(0,0,0,0);
   error_step(Q/2,0,Q/2,Q/2);
   error_step(-Q/2,0,0,-Q);
   error_step(Q,0,Q,3*Q/2);
   error_step(-Q,0,0,-2*Q);
   error_step(Q+1,Q+1,Q+1,2*Q+1);
   // Existing nonzero I must persist at zero, fractions and inclusive boundaries.
   error_step(0,Q+1,Q+1,-Q-1);
   error_step(Q/2,Q+1,3*Q/2+1,Q/2);
   error_step(-Q/2,Q+1,Q+1,-Q);
   error_step(Q,Q+1,2*Q+1,3*Q/2);
   error_step(-Q,Q+1,Q+1,-2*Q);
   error_step(-Q-1,0,0,-1);
   error_step(-Q-1,-Q-1,-Q-1,0);
   error_step(Q,-Q-1,-1,2*Q+1);
   error_step(-Q,-Q-1,-Q-1,-2*Q);
   error_step(Q+1,0,0,2*Q+1);
   // Ordinary accumulation and both existing I limits still work outside the band.
   error_step(3*Q,3*Q,3*Q,2*Q-1);
   error_step(3*Q,4*Q,4*Q,0);
   error_step(0,4*Q,4*Q,-3*Q);
   error_step(-3*Q,Q,Q,-3*Q);
   error_step(-3*Q,-2*Q,-2*Q,0);
   error_step(-3*Q,-4*Q,-4*Q,0);
   // Synchronous clear wins over a new tick and cancels the pending sample.
   @(negedge clk);clear=1;tick=1;target=20*Q;
   @(posedge clk);#1;check_zero;
   @(negedge clk);clear=0;tick=0;
   @(posedge clk);#1;check_zero;
   @(negedge clk);
   // Nonzero absolute inputs: classification is by target-actual, not either input.
   target=9*Q+Q/2;actual=10*Q;step(-Q/2,0,-Q/2,-Q/2);
   // Large signed inputs must not enter the band through abs()/negation overflow.
   error_step(32'sh7fffffff,4*Q,4*Q,32'sh7fffffff);
   error_step(32'sh80000000,-4*Q,-4*Q,32'sh80000000);
   // Asynchronous reset also cancels a captured result.
   @(negedge clk);tick=1;target=2*Q;
   @(posedge clk);#1;rst_n=0;#1;check_zero;
   @(negedge clk);tick=0;rst_n=1;
   @(posedge clk);#1;check_zero;
   $display("TEST PASSED: tb_pid_integral_deadband (inclusive band, retained I, full P/D, disable, limits, reset)");
   $finish;
 end
 initial begin #100000;$fatal(1,"FAIL: integral deadband test timeout");end
endmodule
