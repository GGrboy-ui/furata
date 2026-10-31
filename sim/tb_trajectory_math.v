`timescale 1ns/1ps
module tb_trajectory_math;
 reg clk=0,rst_n=0,start=0;
 reg [2:0] mode=1;
 reg signed [31:0] s=0,e=0;
 reg signed [1:0] direction=0;
 wire busy,done;wire signed [31:0] q,v;
 trajectory_math dut(.clk(clk),.rst_n(rst_n),.start(start),.mode(mode),.phase_q(s),.envelope_q(e),
  .envelope_direction(direction),.busy(busy),.done(done),.fraction_q(q),.derivative_q(v));
 always #5 clk=~clk;
 real x,r,qr,vr,h,d,z,sum2,sum3,sign_value;
 integer m,k,j;
 function real knot;input integer n;begin case(n) 0:knot=0;1:knot=0.125;2:knot=0.25;3:knot=0.375;
  4:knot=0.625;5:knot=0.75;6:knot=0.875;default:knot=1;endcase end endfunction
 initial begin
  $dumpfile("tb_trajectory_math.vcd");$dumpvars(0,clk,start,mode,s,e,direction,q,v,done);
  repeat(3) @(negedge clk);rst_n=1;
  for(m=1;m<=4;m=m+1) for(k=0;k<=100;k=k+1) begin
   x=k/100.0;mode=m;s=$rtoi(x*16777216.0);r=x<0.5 ? x*2:(1-x)*2;e=$rtoi(r*16777216.0);direction=x<0.5 ? 1:-1;
   h=10*r**3-15*r**4+6*r**5;d=30*r**2-60*r**3+30*r**4;
   if(m==2) begin qr=h*$sin(6.283185307179586*x);vr=h*6.283185307179586*$cos(6.283185307179586*x)+direction*2*d*$sin(6.283185307179586*x);end
   else if(m==4) begin
    sum2=0;sum3=0;
    for(j=0;j<8;j=j+1) begin z=x-knot(j);if(z<0)z=0;sign_value=(j==0||j==3||j==5||j==6)?1:-1;
     sum2=sum2+sign_value*z*z;sum3=sum3+sign_value*z*z*z;end
    qr=sum3*128/15;vr=sum2*128/5;
   end else begin qr=10*x**3-15*x**4+6*x**5;vr=30*x**2-60*x**3+30*x**4;end
   start=1;@(negedge clk);start=0;wait(done);@(negedge clk);
   if($itor(q)/16777216.0-qr>0.000025 || qr-$itor(q)/16777216.0>0.000025 ||
      $itor(v)/16777216.0-vr>0.00006 || vr-$itor(v)/16777216.0>0.00006)
    $fatal(1,"FAIL: normalized math m=%0d x=%f q=%f/%f v=%f/%f",m,x,$itor(q)/16777216,qr,$itor(v)/16777216,vr);
  end
  $display("TEST PASSED: tb_trajectory_math (404 golden samples, endpoints, S knots, sine envelope derivatives)");$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL: math timeout");end
endmodule
