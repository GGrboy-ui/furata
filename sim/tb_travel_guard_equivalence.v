`timescale 1ns/1ps
// Compare the new captured-bound comparator to the original wide difference
// at the same cycle, including origins at both 32-bit limits and no tick.
module tb_travel_guard_equivalence;
 reg clk=0,rst_n=0,balance_cmd=0,stop_cmd=0;
 reg signed [31:0] position=0;wire [2:0] state;wire [3:0] fault;
 integer i,j;reg signed [31:0] saved_origin;reg signed [63:0] candidate,delta;
 reg expected;always #5 clk=~clk;
 control_core dut(.clk(clk),.rst_n(rst_n),.sample_valid(1'b0),.sample_ready(1'b1),.sample(12'd1014),
  .position(position),.position_target_q(32'sd0),.start_cmd(1'b0),.motor_test_cmd(1'b0),.balance_cmd(balance_cmd),.stop_cmd(stop_cmd),
  .permit(1'b1),.fault_latched(1'b0),.state(state),.request_fault(fault));
 task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
 initial begin
  $dumpfile("tb_travel_guard_equivalence.vcd");$dumpvars(1,tb_travel_guard_equivalence);
  clocks(3);rst_n=1;clocks(3);
  for(i=0;i<8;i=i+1)begin
   stop_cmd=1;clocks(1);stop_cmd=0;
   case(i)0:position=0;1:position=32'sh7fffffff;2:position=32'sh80000000;3:position=-9000;4:position=1000000000;5:position=-1000000000;6:position=2147480000;7:position=-2147480000;endcase
   saved_origin=position;balance_cmd=1;clocks(1);balance_cmd=0;clocks(1);
   if(state!=4||dut.origin!=saved_origin)$fatal(1,"FAIL: guard capture fixture");
   for(j=0;j<512;j=j+1)begin
    case(j%16)
     0:candidate=$signed(saved_origin)+64'sd4080;1:candidate=$signed(saved_origin)+64'sd4081;
     2:candidate=$signed(saved_origin)-64'sd4080;3:candidate=$signed(saved_origin)-64'sd4081;
     4:candidate=2147483647;5:candidate=-2147483648;
     default:candidate=$signed(saved_origin)+$signed(j*7919%40000)-64'sd20000;
    endcase
    position=candidate>2147483647 ? 32'sh7fffffff:candidate< -64'sd2147483648 ? 32'sh80000000:candidate[31:0];
    delta=$signed({{32{position[31]}},position})-$signed({{32{saved_origin[31]}},saved_origin});
    if(delta>16000)delta=16000;else if(delta< -16000)delta=-16000;
    expected=(delta>4080||delta< -4080);
    #1;if((fault==7)!==expected)$fatal(1,"FAIL: travel changed before next clock origin=%0d pos=%0d code=%0d",saved_origin,position,fault);
    clocks(1);
   end
  end
  $display("TEST PASSED: tb_travel_guard_equivalence (4096 samples, original clamp/limit equivalence, inclusive limits, INT_MIN/MAX origins, immediate no-tick protection)");$finish;
 end
 initial begin #100000;$fatal(1,"FAIL: travel equivalence timeout");end
endmodule
