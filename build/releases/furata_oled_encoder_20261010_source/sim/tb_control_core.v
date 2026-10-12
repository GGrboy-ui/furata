`timescale 1ns/1ps
module tb_control_core;
 reg clk=0,rst_n=0,sample_valid=0,sample_ready=0,start_cmd=0,stop_cmd=0,permit=1,fault_latched=0;
 reg [11:0] sample=12'd1014; reg signed [31:0] position=0;
 wire running; wire signed [31:0] command_q,relative_position; wire [2:0] state;
 wire [3:0] request_fault; wire angle_update,position_update; integer errors=0;
 // Outer-loop behavior fixture: keep nonzero reference gains independent of bench tuning.
 control_core #(.START_PERCENT(35),.PULSE_MS(2),.CHECK_MS(2),.ANGLE_MS(2),.POSITION_MS(4),.SWING_TIMEOUT_MS(20),.POSITION_LIMIT_COUNTS(100),
   .POSITION_KP(26214),.POSITION_KI(0),.POSITION_KD(262144)) dut(
   .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_ready(sample_ready),.sample(sample),.position(position),
   .position_target_q(32'sd0),.start_cmd(start_cmd),.motor_test_cmd(1'b0),.balance_cmd(1'b0),.stop_cmd(stop_cmd),.permit(permit),.fault_latched(fault_latched),.running(running),.command_q(command_q),
   .state(state),.request_fault(request_fault),.relative_position(relative_position),.angle_update(angle_update),.position_update(position_update));
 always #5 clk=~clk;
 task samp; input [11:0] v; begin sample=v; sample_valid=1; @(posedge clk); #1; sample_valid=0; end endtask
 integer trace;
 always @(posedge clk) if (rst_n && sample_valid) $fwrite(trace,"%0t,%0d,%0d,%0d\n",$time,state,sample,command_q);
 initial begin
   $dumpfile("tb_control_core.vcd"); $dumpvars(0,tb_control_core);
   trace=$fopen("control_trace.csv","w"); $fwrite(trace,"time,state,sample,command_q\n");
   #12 rst_n=1; sample_ready=1; start_cmd=1; samp(1014); start_cmd=0;
   if(state!==3'd1 || !running) begin $display("FAIL: start did not enter PUSH"); errors=errors+1; end
   if(command_q!==32'sd2293760) begin $display("FAIL: positive swing command=%0d",command_q); errors=errors+1; end
   samp(1014); samp(1014); samp(1014); samp(1014);
   if(state!==3'd3) begin $display("FAIL: pulse sequence state=%0d",state); errors=errors+1; end
   samp(1014); samp(1014); samp(1014); samp(1014);
   if(state!==3'd4) begin $display("FAIL: centered samples did not capture balance state=%0d",state); errors=errors+1; end
   if(command_q!==0) begin $display("FAIL: centered command=%0d",command_q); errors=errors+1; end
   position=32'sd10;
   samp(1014); samp(1014); samp(1014); samp(1014); samp(1014); samp(1014); samp(1014); samp(1014);
   // The position and angle PID stages each add one clock of latency.
   samp(1014); samp(1014);
   if(command_q===0) begin $display("FAIL: position outer loop produced no angle demand"); errors=errors+1; end
   position=0;
   sample=12'd3000; sample_valid=1; #1;
   if(request_fault!==4'd5) begin $display("FAIL: angle fault code=%0d",request_fault); errors=errors+1; end
   @(posedge clk); #1; sample_valid=0;
   stop_cmd=1; @(posedge clk); #1; stop_cmd=0;
   if(state!==3'd0 || running) begin $display("FAIL: stop did not return STOP"); errors=errors+1; end
   if(errors==0) $display("TEST PASSED: tb_control_core"); else $display("TEST FAILED: tb_control_core (%0d error(s))",errors);
   $fclose(trace); $finish;
 end
endmodule
