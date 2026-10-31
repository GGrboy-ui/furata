`timescale 1ns/1ps
module tb_control_position_period;
 reg clk=0,rst_n=0,sample=0,balance=0,request=0;
 reg [15:0] requested=1;wire [15:0] actual;
 wire [2:0] state;wire position_update,pending,reply;wire [7:0] code;
 integer updates=0;
 always #5 clk=~clk;
 control_core #(.RUNTIME_POSITION_PERIOD(1),.CENTER(1007),.BALANCE_BOOST_MAX_PERCENT(0)) core(
  .clk(clk),.rst_n(rst_n),.sample_valid(sample),.sample_ready(1'b1),.sample(12'd1007),
  .position(32'sd0),.position_target_q(32'sd0),.position_period_ms(actual),
  .start_cmd(1'b0),.motor_test_cmd(1'b0),.balance_cmd(balance),.stop_cmd(1'b0),.permit(1'b1),.fault_latched(1'b0),
  .state(state),.position_update(position_update));
 position_period period_config(.clk(clk),.rst_n(rst_n),.request(request),.allowed(1'b1),.position_update(position_update),
  .control_state(state),.requested_ms(requested),.actual_ms(actual),.pending(pending),.reply(reply),.code(code));
 always @(posedge clk)if(position_update)updates<=updates+1;
 task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
 task ms;begin sample=1;clocks(1);sample=0;clocks(8);end endtask
 task set_period;input integer n;begin requested=n;request=1;clocks(1);request=0;clocks(1);end endtask
 integer old;
 initial begin
  $dumpfile("tb_control_position_period.vcd");$dumpvars(0,clk,sample,actual,pending,position_update,updates);
  clocks(3);rst_n=1;clocks(3);set_period(1);balance=1;clocks(1);balance=0;
  repeat(1000)ms;if(updates!=1000)$fatal(1,"FAIL: 1ms update cadence %0d",updates);
  set_period(1000);ms;if(actual!=1000||updates!=1001)$fatal(1,"FAIL: old 1ms boundary");
  repeat(999)ms;if(updates!=1001)$fatal(1,"FAIL: extra 1000ms update");
  ms;if(updates!=1002)$fatal(1,"FAIL: missing 1000ms update");
  set_period(50);repeat(999)ms;if(actual!=1000||updates!=1002)$fatal(1,"FAIL: shorter period applied before old boundary");
  ms;if(actual!=50||updates!=1003)$fatal(1,"FAIL: old 1000ms boundary");
  repeat(49)ms;if(updates!=1003)$fatal(1,"FAIL: early 50ms update");
  ms;if(updates!=1004)$fatal(1,"FAIL: missing 50ms update");
  $display("TEST PASSED: tb_control_position_period (1/1000/50 ms, exact PID tick counts, old-boundary switching)");$finish;
 end
endmodule
