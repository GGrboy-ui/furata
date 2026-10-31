`timescale 1ns/1ps
module tb_trajectory_engine;
 reg clk=0,rst_n=0,tick=0,enable=1,stop=0,lock=0,submit=0;
 reg [15:0] id=0;reg [2:0] mode=1;
 reg [31:0] duration=1000,dwell=0;reg [7:0] cycles_n=1;reg [3:0] count=1;
 reg [255:0] angles=0;reg signed [31:0] position=42;
 wire busy,started,event_valid;wire [15:0] active_id,event_id;wire [7:0] code,status;
 wire [2:0] selected,phase;wire [3:0] point_index;
 wire [31:0] elapsed,total;wire signed [31:0] target,goal,velocity;
 trajectory_engine dut(.clk(clk),.rst_n(rst_n),.tick_ms(tick),.enable(enable),.stop_cmd(stop),.external_busy(lock),
  .submit(submit),.request_id(id),.request_mode(mode),.request_time_ms(duration),.request_dwell_ms(dwell),
  .request_cycles(cycles_n),.request_count(count),.request_angles(angles),.position(position),
  .busy(busy),.started(started),.event_valid(event_valid),.active_id(active_id),.event_id(event_id),.event_code(code),
  .status_code(status),.mode(selected),.phase(phase),.point_index(point_index),.elapsed_ms(elapsed),.total_ms(total),
  .target_q(target),.goal_q(goal),.velocity_q(velocity));
 always #5 clk=~clk;
 task clocks;input integer n;begin repeat(n) @(negedge clk);end endtask
 task ms;begin tick=1;clocks(1);tick=0;clocks(300);end endtask
 task send;begin submit=1;clocks(1);submit=0;clocks(750);end endtask
 integer k,m,expected,old_id,old_target;
 reg signed [31:0] previous;
 initial begin
  $dumpfile("tb_trajectory_engine.vcd");$dumpvars(0,clk,tick,submit,id,phase,elapsed,target,goal,velocity);
  clocks(3);rst_n=1;clocks(2);
  for(m=1;m<=4;m=m+1) begin
   position=42;mode=m;id=id+1;duration=1000;dwell=m==3 ? 100:0;cycles_n=m==2 ? 3:1;
   count=m==3 ? 4:1;angles=0;
   if(m==2) angles[31:0]=10;
   else if(m==3) begin angles[31:0]=50;angles[63:32]=0;angles[95:64]=-50;angles[127:96]=0;end
   else angles[31:0]=m==4 ? -50:50;
   send;if(phase!=2||code!=1||target!=42*65536)$fatal(1,"FAIL: task acceptance m=%0d phase=%0d code=%0d",m,phase,code);
   expected=m==2 ? 3000:m==3 ? 4400:1000;
   if(total!=expected)$fatal(1,"FAIL: total duration");
   previous=target;
   for(k=1;k<=expected;k=k+1) begin
    ms;
    if(elapsed!=k)$fatal(1,"FAIL: dropped trajectory millisecond %0d/%0d",elapsed,k);
    if(target-previous>2250 || previous-target>2250)$fatal(1,"FAIL: position jump");
    if(velocity>34*65536 || velocity< -34*65536)$fatal(1,"FAIL: peak speed");
    if(m==1 && k==500 && (target<42*65536+185600 || target>42*65536+185800))$fatal(1,"FAIL: quintic midpoint");
    if(m==3 && k==1100 && target!=dut.points[0])$fatal(1,"FAIL: intermediate hold");
    if(m==2 && k==500 && (target<42*65536-100 || target>42*65536+100))$fatal(1,"FAIL: sine half period");
    previous=target;
   end
   if(phase!=3 || target!=goal || velocity!=0)$fatal(1,"FAIL: final hold");
   position=goal/65536+10;repeat(220) ms;if(phase!=3)$fatal(1,"FAIL: false arrival without actual feedback");
   position=(goal+32768)/65536;repeat(199) ms;if(phase!=3)$fatal(1,"FAIL: early settle");
   ms;if(phase!=4 || code!=2 || busy)$fatal(1,"FAIL: arrival");
   send;if(code!=20)$fatal(1,"FAIL: duplicate execution");
  end
  mode=1;count=1;dwell=0;cycles_n=1;position=0;id=id+1;angles=0;angles[31:0]=36000;send;
  if(code!=18 || busy)$fatal(1,"FAIL: excessive speed accepted");
  duration=600000;position=4080;id=id+1;angles[31:0]=10;send;if(code!=18)$fatal(1,"FAIL: range accepted");
  position=0;duration=1000;angles[31:0]=50;id=id+1;lock=1;send;if(code!=16)$fatal(1,"FAIL: ARM1/config exclusion");
  lock=0;enable=0;send;if(code!=17)$fatal(1,"FAIL: stopped acceptance");enable=1;
  send;if(!busy)$fatal(1,"FAIL: fresh move");old_id=id;id=id+1;send;if(code!=16||active_id!=old_id)$fatal(1,"FAIL: busy request changed task");
  repeat(10)ms;stop=1;clocks(2);stop=0;clocks(400);if(busy||phase!=5||code!=3)$fatal(1,"FAIL: stop cancellation");
  $display("TEST PASSED: tb_trajectory_engine (four tasks, deadlines, signed motion, sine envelope, waypoint holds, settle, limits, duplicate, exclusion, stop)");$finish;
 end
 initial begin #80000000;$fatal(1,"FAIL: engine timeout");end
endmodule
