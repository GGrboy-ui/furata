`timescale 1ns/1ps
module tb_arm_move;
 reg clk=0,rst_n=0,tick_ms=0,enable=1,stop_cmd=0;
 reg [2:0] control_state=4;
 reg signed [31:0] position=0;
 reg [7:0] received_byte=0;reg received_valid=0;
 reg telemetry_active=0;
 wire legacy_valid,load,busy,tx_valid,tx_pending;
 wire [7:0] tx_data;
 wire signed [31:0] load_goal,load_origin,goal_q,target_q;
 integer loads=0,last_code=-1,reports=0,capabilities=0,length=0;
 reg [7:0] line[0:80];
 arm_move #(.CLK_HZ(1000000)) dut(
   .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.enable(enable),.stop_cmd(stop_cmd),.control_state(control_state),
   .position(position),.target_q(target_q),.goal_q(goal_q),.received_byte(received_byte),.received_valid(received_valid),
   .legacy_valid(legacy_valid),.load(load),.load_goal_q(load_goal),.load_origin_q(load_origin),.busy(busy),
   .tx_data(tx_data),.tx_valid(tx_valid),.tx_pending(tx_pending),.tx_ready(1'b1),.telemetry_active(telemetry_active));
 position_target #(.REMOTE(1)) trajectory(.clk(clk),.rst_n(rst_n),.enable(enable),.tick_ms(tick_ms),
   .move_cmd(3'b0),.load(load),.load_goal_q(load_goal),.load_origin_q(load_origin),.goal_q(goal_q),.target_q(target_q));
 always #5 clk=~clk;
 function integer hex;input [7:0] c;begin hex=c<="9"?c-"0":c-"A"+10;end endfunction
 always @(posedge clk) begin
   if(load) loads=loads+1;
   if(tx_valid && !telemetry_active) begin
     line[length]=tx_data;
     if(tx_data==10) begin
       if(line[0]!="@" || line[length-1]!=13) $fatal(1,"FAIL: malformed response");
       if(line[1]=="I") begin
         if(length!=23) $fatal(1,"FAIL: capability length %0d",length);
         capabilities=capabilities+1;
       end else begin
         if(length!=33) $fatal(1,"FAIL: report length %0d",length);
         last_code=hex(line[8])*16+hex(line[9]);reports=reports+1;
         if(last_code==1 && {line[24],line[25],line[26],line[27],line[28],line[29],line[30],line[31]}!==dut.hex8(goal_q))
           $fatal(1,"FAIL: acceptance response did not snapshot new goal");
       end
       length=0;
     end else length=length+1;
   end
 end
 task cycles;input integer n;begin repeat(n) @(negedge clk);end endtask
 task send;input [7:0] c;begin received_byte=c;received_valid=1;cycles(1);received_valid=0;cycles(1);end endtask
 task command;input [255:0] text;input integer n;integer j;begin for(j=n-1;j>=0;j=j-1) send(text[j*8+:8]);cycles(120);end endtask
 task tick;begin tick_ms=1;cycles(1);tick_ms=0;cycles(1);end endtask
 task expect_code;input integer c;begin cycles(150);if(last_code!=c) $fatal(1,"FAIL: code=%h expected=%h",last_code,c);end endtask
 task arrived;input integer ticks;begin repeat(ticks) tick;cycles(120);if(busy) $fatal(1,"FAIL: did not settle");expect_code(2);end endtask
 integer n;
 initial begin
   $dumpfile("tb_arm_move.vcd");$dumpvars(0,tb_arm_move);
   cycles(4);rst_n=1;cycles(4);
   command("@I\n",3);if(capabilities!=1) $fatal(1,"FAIL: capability query");
   command("@M,1,+600\n",10);expect_code(1);
   if(goal_q!==68*65536 || target_q!==0 || !busy) $fatal(1,"FAIL: +60 goal %0d",goal_q);
   command("@M,2,-400\n",10);expect_code(16);if(loads!=1) $fatal(1,"FAIL: busy moved");
   repeat(2100) tick;position=68;
   repeat(199) tick;if(!busy) $fatal(1,"FAIL: premature arrival");
   arrived(1);
   // Second request is relative to measured 68 counts, not the old goal.
   command("@M,2,-400\n",10);expect_code(1);
   if(goal_q!==1485483 || target_q!==68*65536) $fatal(1,"FAIL: -40 Q16 goal %0d",goal_q);
   repeat(1400) tick;position=23;arrived(200);
   command("@M,2,-400\n",10);expect_code(20);if(loads!=2) $fatal(1,"FAIL: duplicate executed");
   n=loads;command("@M,3,+0\n",8);expect_code(2);if(loads!=n || busy) $fatal(1,"FAIL: zero moved");
   position=100;command("@M,4,+125\n",10);expect_code(1);
   if(goal_q!==7482027 || target_q!==100*65536) $fatal(1,"FAIL: fractional move actual base %0d",goal_q);
   stop_cmd=1;cycles(1);stop_cmd=0;enable=0;cycles(120);expect_code(3);
   if(busy) $fatal(1,"FAIL: stop did not cancel");
   command("@M,5,+600\n",10);expect_code(17);
   enable=1;position=4000;command("@M,5,+600\n",10);expect_code(1);
   enable=0;cycles(120);enable=1;cycles(10);
   command("@M,6,+36000\n",12);expect_code(18);if(busy) $fatal(1,"FAIL: out-of-range became busy");
   command("@M,7,+36001\n",12);expect_code(19);
   command("@M,999999,+1\n",13);expect_code(19);
   command("@M,8,+9999999999999999999999\n",29);expect_code(19);
   n=loads;command("@M,8,+60S\n",10);expect_code(19);if(loads!=n) $fatal(1,"FAIL: invalid packet moved");
   command("@M,8,+",6);cycles(200010);expect_code(19);
   position=-4000;command("@M,8,-600\n",10);expect_code(1);enable=0;cycles(120);enable=1;cycles(10);
   command("@M,9,-36000\n",12);expect_code(18);
   position=0;command("@M,10,+3600\n",12);expect_code(1);
   if(goal_q!==408*65536) $fatal(1,"FAIL: full turn wrapped");
   repeat(12100) tick;position=408;arrived(200);
   command("@M,11,-3600\n",12);expect_code(1);
   if(goal_q!==0 || target_q!==408*65536) $fatal(1,"FAIL: negative turn wrong");
   // Loss of balance cancels; no later re-entry may resurrect this motion.
   enable=0;cycles(120);expect_code(3);enable=1;cycles(120);if(busy) $fatal(1,"FAIL: resurrected move");
   // Telemetry owns the wire until its last stop bit; replies wait intact.
   telemetry_active=1;command("@I\n",3);if(tx_valid) $fatal(1,"FAIL: reply interrupted telemetry");
   telemetry_active=0;cycles(100);if(capabilities!=2) $fatal(1,"FAIL: pending reply lost");
   $display("TEST PASSED: tb_arm_move (relative motion, fractions, busy, settle, limits, parser, cancellation, TX arbitration)");$finish;
 end
 initial begin #8000000;$fatal(1,"FAIL: timeout");end
endmodule
