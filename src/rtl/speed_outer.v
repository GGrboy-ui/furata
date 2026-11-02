`timescale 1ns/1ps
// Runtime PI: gains are per second; all physical values are signed Q16.16.
// Arithmetic is sequenced to keep the 50 MHz control path short.
module speed_outer #(
 parameter integer COUNTS_PER_REV=408,MAX_SPEED=30,
 parameter signed [31:0] ANGLE_LIMIT_Q=1572864
)(
 input wire clk,rst_n,clear,tick,
 input wire [15:0] period_ms,
 input wire signed [31:0] kp_q,ki_q,kd_q,kpos_q,position_error_q,reference_q,actual_q,
 output reg signed [31:0] target_q,out_q,
 output reg valid
);
 localparam signed [63:0] CORRECTION_LIMIT=(64'sd65536*COUNTS_PER_REV*5)/360;
 localparam signed [63:0] SPEED_LIMIT=(64'sd65536*COUNTS_PER_REV*MAX_SPEED)/360;
 reg [4:0] stage;
 reg have_previous;
 reg signed [31:0] kd,previous_actual,derivative_q,d_raw,d_term;
 reg signed [63:0] d_w,d_product,div_signed;
 reg [63:0] denominator;
 reg [15:0] dt;
 reg signed [31:0] kp,ki,kpos,ep,reference,actual,correction,error_q,p_q,integral_q;
 reg signed [63:0] product,p_product,i_product,delta_product,desired,error_w,i_candidate,sum;
 reg div_start,delta_negative;
 reg [63:0] numerator;
 wire div_done,div_busy;wire [63:0] quotient,remainder_unused;
 wire arithmetic_reset=rst_n && !clear;
 divider_seq #(.WIDTH(64)) div_time(.clk(clk),.rst_n(arithmetic_reset),.start(div_start),
  .num(numerator),.den(denominator),.busy(div_busy),.done(div_done),.q(quotient),.r(remainder_unused));
 function signed [31:0] sat32;
  input signed [63:0] x;
  begin sat32=x>64'sd2147483647 ? 32'sh7fffffff:x< -64'sd2147483648 ? 32'sh80000000:x[31:0];end
 endfunction
 function signed [31:0] angle_limit;
  input signed [63:0] x;
  begin angle_limit=x>ANGLE_LIMIT_Q ? ANGLE_LIMIT_Q:x< -ANGLE_LIMIT_Q ? -ANGLE_LIMIT_Q:x[31:0];end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   have_previous<=0;kd<=0;previous_actual<=0;derivative_q<=0;d_raw<=0;d_term<=0;d_w<=0;d_product<=0;div_signed<=0;denominator<=1000;
   stage<=0;dt<=0;kp<=0;ki<=0;kpos<=0;ep<=0;reference<=0;actual<=0;correction<=0;error_q<=0;
   p_q<=0;integral_q<=0;product<=0;p_product<=0;i_product<=0;delta_product<=0;desired<=0;error_w<=0;
   i_candidate<=0;sum<=0;div_start<=0;delta_negative<=0;numerator<=0;target_q<=0;out_q<=0;valid<=0;
  end else if(clear) begin
   have_previous<=0;previous_actual<=0;derivative_q<=0;d_term<=0;
   stage<=0;integral_q<=0;target_q<=0;out_q<=0;valid<=0;div_start<=0;
  end else begin
   valid<=0;div_start<=0;
   case(stage)
    0:if(tick) begin
     kd<=kd_q;kp<=kp_q;ki<=ki_q;kpos<=kpos_q;ep<=position_error_q;reference<=reference_q;actual<=actual_q;
     dt<=period_ms;stage<=1;
    end
    1:begin product<=$signed(kpos)*$signed(ep);stage<=2;end
    2:begin
     correction<=(product>>>16)>CORRECTION_LIMIT ? CORRECTION_LIMIT[31:0]:
      (product>>>16)< -CORRECTION_LIMIT ? -CORRECTION_LIMIT[31:0]:sat32(product>>>16);stage<=3;
    end
    3:begin desired<=$signed(reference)+$signed({{32{correction[31]}},correction});stage<=4;end
    4:begin target_q<=desired>SPEED_LIMIT ? SPEED_LIMIT[31:0]:desired< -SPEED_LIMIT ? -SPEED_LIMIT[31:0]:desired[31:0];stage<=5;end
    5:begin error_w<=$signed({{32{target_q[31]}},target_q})-$signed({{32{actual[31]}},actual});stage<=6;end
    6:begin error_q<=sat32(error_w);stage<=7;end
    7:begin p_product<=$signed(kp)*$signed(error_q);i_product<=$signed(ki)*$signed(error_q);stage<=8;end
    8:begin p_q<=sat32(p_product>>>16);delta_product<=$signed(sat32(i_product>>>16))*$signed({1'b0,dt});stage<=9;end
    9:begin denominator<=1000;delta_negative<=delta_product[63];numerator<=delta_product[63] ? -delta_product:delta_product;div_start<=1;stage<=10;end
    // Register quotient sign separately from accumulation/clamping.
    10:if(div_done) begin div_signed<=delta_negative ? -$signed(quotient):$signed(quotient);stage<=22;end
    22:begin
     i_candidate<=ki==0 ? 64'sd0:$signed({{32{integral_q[31]}},integral_q})+
      div_signed;stage<=11;
    end
    11:begin i_candidate<=angle_limit(i_candidate);stage<=12;end
    12:begin
     d_w<=have_previous ? ($signed({{32{actual[31]}},actual})-$signed({{32{previous_actual[31]}},previous_actual}))*64'sd1000:64'sd0;
     previous_actual<=actual;have_previous<=1;stage<=14;
    end
    14:begin delta_negative<=d_w[63];numerator<=d_w[63] ? -d_w:d_w;denominator<={48'd0,dt};div_start<=1;stage<=15;end
    15:if(div_done) begin div_signed<=delta_negative ? -$signed(quotient):$signed(quotient);stage<=23;end
    23:begin d_raw<=sat32(div_signed);stage<=16;end
    16:begin d_w<=($signed({{32{d_raw[31]}},d_raw})-$signed({{32{derivative_q[31]}},derivative_q}))*$signed({1'b0,dt});stage<=17;end
    17:begin delta_negative<=d_w[63];numerator<=d_w[63] ? -d_w:d_w;denominator<=64'd40+dt;div_start<=1;stage<=18;end
    18:if(div_done) begin div_signed<=delta_negative ? -$signed(quotient):$signed(quotient);stage<=24;end
    24:begin d_w<=$signed({{32{derivative_q[31]}},derivative_q})+div_signed;stage<=25;end
    25:begin derivative_q<=sat32(d_w);stage<=19;end
    19:begin d_product<=$signed(kd)*$signed(derivative_q);stage<=20;end
    20:begin d_term<=sat32(d_product>>>16);stage<=21;end
    21:begin sum<=$signed({{32{p_q[31]}},p_q})+i_candidate-$signed({{32{d_term[31]}},d_term});stage<=13;end
    13:begin
     // Conditional integration: an outward error cannot wind up a saturated PI.
     if(ki==0) integral_q<=0;
     else if(!((sum>ANGLE_LIMIT_Q && error_q>0)||(sum< -ANGLE_LIMIT_Q && error_q<0))) integral_q<=i_candidate[31:0];
     out_q<=angle_limit(sum);valid<=1;stage<=0;
    end
    default:stage<=0;
   endcase
  end
 end
endmodule
