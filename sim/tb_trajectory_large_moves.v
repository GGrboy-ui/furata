`timescale 1ns/1ps
// Long-duration, full-turn references; this is not a mechanical plant model.
module tb_trajectory_large_moves;
 reg clk=0,rst_n=0,tick=0,enable=1,stop=0,submit=0;always #5 clk=~clk;
 reg [15:0] id=0;reg [2:0] mode=1;
 reg [31:0] duration=15000;reg [3:0] count=1;
 reg [255:0] angles=0;reg signed [31:0] position=0;
 wire busy,started,event_valid;wire [15:0] active_id,event_id;wire [7:0] code,status;
 wire [2:0] selected,phase;wire [3:0] point_index;
 wire [31:0] elapsed,total;wire signed [31:0] target,goal,velocity;
 trajectory_engine dut(.clk(clk),.rst_n(rst_n),.tick_ms(tick),.enable(enable),.stop_cmd(stop),.external_busy(1'b0),
  .submit(submit),.request_id(id),.request_mode(mode),.request_time_ms(duration),.request_dwell_ms(32'd0),
  .request_cycles(8'd1),.request_count(count),.request_angles(angles),.position(position),
  .busy(busy),.started(started),.event_valid(event_valid),.active_id(active_id),.event_id(event_id),.event_code(code),
  .status_code(status),.mode(selected),.phase(phase),.point_index(point_index),.elapsed_ms(elapsed),.total_ms(total),
  .target_q(target),.goal_q(goal),.velocity_q(velocity));
 task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
 task ms;begin tick=1;clocks(1);tick=0;clocks(300);end endtask
 task request;begin id=id+1;submit=1;clocks(1);submit=0;clocks(750);end endtask
 task cancel;begin stop=1;clocks(2);stop=0;clocks(300);end endtask
 integer k,a;reg signed [31:0] previous;
 initial begin
  $dumpfile("tb_trajectory_large_moves.vcd");$dumpvars(1,tb_trajectory_large_moves);
  clocks(4);rst_n=1;clocks(2);
  for(a=60;a<=360;a=a+30)begin
   mode=1;duration=(a*1875+29)/30;if(duration<15000)duration=15000;
   angles=0;angles[31:0]=a*10;request;
   if(code!=1||phase!=2||total!=duration)$fatal(1,"FAIL: large quintic preset %0d",a);
   cancel;
  end
  mode=1;angles[31:0]=3600;duration=22499;request;
  if(code!=18||busy)$fatal(1,"FAIL: 360deg quintic exceeded 30deg/s without rejection");
  duration=22500;request;if(code!=1||phase!=2)$fatal(1,"FAIL: 22.5s full-turn quintic rejected");cancel;
  mode=2;angles[31:0]=600;duration=20000;request;
  if(code!=1||total!=20000)$fatal(1,"FAIL: 60deg/20s sine rejected");repeat(100)ms;cancel;
  angles[31:0]=3600;duration=20000;request;
  if(code!=18||busy)$fatal(1,"FAIL: fast full-turn sine accepted");
  duration=75408;request;if(code!=1)$fatal(1,"FAIL: slow full-turn sine rejected");cancel;
  // The direct +360 to -360 waypoint segment needs 45s at the unchanged limit.
  mode=3;count=2;angles[31:0]=3600;angles[63:32]=-3600;duration=22500;request;
  if(code!=18||busy)$fatal(1,"FAIL: waypoint speed used magnitude instead of displacement");
  duration=45000;request;if(code!=1)$fatal(1,"FAIL: slow waypoint jump rejected");cancel;
  // Execute every millisecond of a -360deg / 20s S curve without wrapping a turn.
  mode=4;count=1;angles=0;angles[31:0]=-3600;duration=20000;position=0;request;
  if(code!=1||phase!=2||goal!=-408*65536)$fatal(1,"FAIL: negative full-turn S curve acceptance/goal");
  previous=target;
  for(k=1;k<=20000;k=k+1)begin
   ms;
   if(elapsed!=k)$fatal(1,"FAIL: lost long-profile tick");
   // Q8.24 cancellation near zero speed can move a few Q16.16 LSBs backwards.
   // Bound that ripple to 1/256 encoder count (0.00345deg), far below one count.
   if(target-previous>256||previous-target>2400)$fatal(1,"FAIL: long-profile position discontinuity");
   if(velocity>128||velocity< -34*65536)$fatal(1,"FAIL: long-profile velocity sign/limit");
   if(k==10000&&(target< -204*65536-100||target> -204*65536+100))$fatal(1,"FAIL: S curve midpoint");
   previous=target;
  end
  if(phase!=3||target!=goal||velocity!=0||elapsed!=20000)$fatal(1,"FAIL: long-profile final hold");
  repeat(210)ms;if(phase!=3)$fatal(1,"FAIL: reference end incorrectly claimed physical arrival");
  position=-408;repeat(200)ms;if(phase!=4||code!=2)$fatal(1,"FAIL: long-profile actual arrival");
  $display("TEST PASSED: tb_trajectory_large_moves (60..360deg, 15..20s, speed limits, 720deg segment, full negative turn, deadline, actual settle)");$finish;
 end
 initial begin #100000000;$fatal(1,"FAIL: long trajectory timeout");end
endmodule
