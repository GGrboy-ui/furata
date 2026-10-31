`timescale 1ns/1ps
module tb_pid_runtime;
 reg clk=0,rst_n=0,clear=0,tick=0;always #5 clk=~clk;
 reg signed [31:0] target_q=65536,actual_q=0,runtime_kp_q=65536,runtime_ki_q=0,runtime_kd_q=0;
 wire signed [31:0] out_q;wire valid;
 pid_fixed #(.RUNTIME_GAINS(1),.I_DECAY_BAND_Q(0)) dut(.*);
 reg eq_tick=0,eq_clear=0;reg signed [31:0] eq_target=0;wire signed [31:0] eq_old_out,eq_new_out;wire eq_old_valid,eq_new_valid;wire signed [31:0] eq_pipe_out;wire eq_pipe_valid;integer i;
 pid_fixed #(.KP(39214),.KI(400),.KD(362144),.I_DECAY_BAND_Q(131072),.I_DECAY_RETAIN_PERCENT(100)) legacy(.clk(clk),.rst_n(rst_n),.clear(eq_clear),.tick(eq_tick),.target_q(eq_target),.actual_q(32'sd0),.out_q(eq_old_out),.valid(eq_old_valid));
 pid_fixed #(.RUNTIME_GAINS(1),.I_DECAY_BAND_Q(131072),.I_DECAY_RETAIN_PERCENT(100)) runtime_default(.clk(clk),.rst_n(rst_n),.clear(eq_clear),.tick(eq_tick),.target_q(eq_target),.actual_q(32'sd0),.runtime_kp_q(32'sd39214),.runtime_ki_q(32'sd400),.runtime_kd_q(32'sd362144),.out_q(eq_new_out),.valid(eq_new_valid));
 pid_fixed #(.PIPELINED_ARITH(1),.KP(39214),.KI(400),.KD(362144),.I_DECAY_BAND_Q(131072),.I_DECAY_RETAIN_PERCENT(100)) compiled_pipeline(.clk(clk),.rst_n(rst_n),.clear(eq_clear),.tick(eq_tick),.target_q(eq_target),.actual_q(32'sd0),.out_q(eq_pipe_out),.valid(eq_pipe_valid));
 task step;begin @(negedge clk);tick=1;@(negedge clk);tick=0;wait(valid);@(negedge clk);end endtask
 initial begin
  $dumpfile("tb_pid_runtime.vcd");$dumpvars(1,tb_pid_runtime);
  repeat(3)@(negedge clk);rst_n=1;step;if(out_q!=65536)$fatal(1,"FAIL: runtime P");
  clear=1;@(negedge clk);clear=0;runtime_kp_q=0;runtime_ki_q=32768;step;step;if(out_q!=65536)$fatal(1,"FAIL: runtime I");
  clear=1;@(negedge clk);clear=0;runtime_ki_q=0;runtime_kd_q=131072;step;if(out_q!=131072)$fatal(1,"FAIL: runtime D");step;if(out_q!=0)$fatal(1,"FAIL: D static error");
  clear=1;@(negedge clk);clear=0;runtime_kd_q=0;runtime_kp_q=65536;
  @(negedge clk);tick=1;@(negedge clk);tick=0;runtime_kp_q=131072;wait(valid);@(negedge clk);
  if(out_q!=65536)$fatal(1,"FAIL: coefficient sample mixing");step;if(out_q!=131072)$fatal(1,"FAIL: next gain missing");
  // Compare runtime defaults against the unchanged compiled-gain path over
  // positive/negative errors, I hold band, output limits and reset history.
  for(i=0;i<512;i=i+1) begin
   if(i%64==0)begin eq_clear=1;@(negedge clk);eq_clear=0;end
   case(i%16)
    0:eq_target=32'sh7fffffff;1:eq_target=32'sh80000000;
    2:eq_target=131072;3:eq_target=-131072;4:eq_target=0;
    default:eq_target=$signed((i*7919)%4000000)-2000000;
   endcase
   eq_tick=1;@(negedge clk);eq_tick=0;wait(eq_new_valid);@(negedge clk);
   if(eq_new_out!==eq_old_out || eq_pipe_out!==eq_old_out || runtime_default.integral_q!==legacy.integral_q || compiled_pipeline.integral_q!==legacy.integral_q || runtime_default.previous_q!==legacy.previous_q)
    $fatal(1,"FAIL: runtime default differs from legacy sample %0d",i);
  end
  $display("TEST PASSED: tb_pid_runtime (separate runtime P/I/D, captured gains, 512-sample runtime and compiled-pipeline/legacy equivalence with I band and limits)");$finish;
 end
 initial begin #100000;$fatal(1,"FAIL: runtime PID timeout");end
endmodule
