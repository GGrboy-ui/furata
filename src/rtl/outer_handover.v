`timescale 1ns/1ps
// Snapshot the old outer output; mix over 200 actual millisecond samples.
// The angle loop is not reset. Both divisions commit atomically before next tick.
module outer_handover(
 input wire clk,rst_n,clear,tick_ms,start,
 input wire signed [31:0] position_out,speed_out,
 input wire [15:0] friction_t,
 output reg [7:0] remaining_ms,
 output reg signed [31:0] out_q,
 output reg [15:0] applied_t
);
 reg [3:0] stage;reg [7:0] next_remaining;
 reg signed [31:0] origin,speed_sample,next_out;
 reg [15:0] t_sample;
 reg signed [63:0] mix;
 reg negative,div_start;
 reg [63:0] numerator;
 wire busy,done;wire [63:0] quotient,unused;
 wire arithmetic_reset=rst_n && !clear;
 divider_seq #(.WIDTH(64)) divide(.clk(clk),.rst_n(arithmetic_reset),.start(div_start),.num(numerator),.den(64'd200),.busy(busy),.done(done),.q(quotient),.r(unused));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin remaining_ms<=0;out_q<=0;applied_t<=0;stage<=0;next_remaining<=0;origin<=0;speed_sample<=0;next_out<=0;t_sample<=0;mix<=0;negative<=0;div_start<=0;numerator<=0;end
  else if(clear) begin remaining_ms<=0;out_q<=0;applied_t<=0;stage<=0;div_start<=0;end
  else if(start) begin origin<=position_out;out_q<=position_out;applied_t<=0;remaining_ms<=200;stage<=0;div_start<=0;end
  else begin
   div_start<=0;
   case(stage)
    0:if(tick_ms && remaining_ms!=0) begin next_remaining<=remaining_ms-1'b1;speed_sample<=speed_out;t_sample<=friction_t;stage<=1;end
    1:begin mix<=$signed(origin)*$signed({1'b0,next_remaining})+$signed(speed_sample)*$signed(10'd200-{2'b0,next_remaining});stage<=2;end
    2:begin negative<=mix[63];numerator<=mix[63] ? -mix:mix;div_start<=1;stage<=3;end
    3:if(done) begin next_out<=negative ? -$signed(quotient[31:0]):$signed(quotient[31:0]);numerator<=t_sample*(64'd200-next_remaining);stage<=4;end
    4:begin div_start<=1;stage<=5;end
    5:if(done) begin out_q<=next_out;applied_t<=quotient[15:0];remaining_ms<=next_remaining;stage<=0;end
    default:stage<=0;
   endcase
  end
 end
endmodule
