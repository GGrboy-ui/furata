`timescale 1ns/1ps
// Signed period speed for the control loop. Position/legacy speed are unchanged.
// First sum valid quadrature steps over 1 ms, cancelling within-window bounce.
// Every subsequent nonzero window establishes a signed period, including a
// reversal. Reversals keep the filter history; only reset/1s inactivity zero it.
module velocity_feedback #(parameter integer CLK_HZ=50000000)(
 input wire clk,rst_n,tick_ms,edge_valid,edge_negative,
 output reg signed [31:0] velocity_q
);
 localparam [63:0] NUMERATOR=64'd65536*CLK_HZ;
 localparam [31:0] TIMEOUT=CLK_HZ;
 // 65535 net steps per ms already exceeds the saturated speed range. Saturate
 // instead of wrapping even if the sampling tick is temporarily absent.
 reg signed [16:0] accumulated_steps,batch_steps;
 reg batch_ready;
 wire signed [17:0] steps_w=$signed({accumulated_steps[16],accumulated_steps})+
  (edge_valid ? (edge_negative ? -18'sd1:18'sd1):18'sd0);
 wire signed [16:0] next_steps=steps_w>18'sd65535 ? 17'sd65535:
  steps_w< -18'sd65535 ? -17'sd65535:steps_w[16:0];
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin accumulated_steps<=0;batch_steps<=0;batch_ready<=0;end
  else begin
   batch_ready<=tick_ms;
   if(tick_ms) begin batch_steps<=next_steps;accumulated_steps<=0;end
   else if(edge_valid) accumulated_steps<=next_steps;
  end
 end
 wire fresh_batch=batch_ready && batch_steps!=0;
 wire batch_negative=batch_steps[16];
 wire [16:0] batch_abs=batch_negative ? -batch_steps:batch_steps;
 reg have_edge,have_period,direction;
 reg [31:0] age,period;
 reg [15:0] period_steps;
 reg start,pending_negative,job_valid;
 reg [31:0] denominator;
 reg [63:0] numerator;
 reg signed [31:0] raw_q;
 wire busy,done;wire [63:0] quotient,remainder_unused;
 wire timed_out=age>=TIMEOUT;
 // A new measurement invalidates the old job, without asynchronous resets from
 // encoder combinational signals. An invalid job cannot become valid again
 // until a new start, even after several reversals during one division.
 divider_seq #(.WIDTH(64)) div(.clk(clk),.rst_n(rst_n),.start(start),
  .num(numerator),.den({32'd0,denominator}),.busy(busy),.done(done),.q(quotient),.r(remainder_unused));
 wire signed [31:0] magnitude=quotient>64'd2048000000 ? 32'sd2048000000:$signed(quotient[31:0]);
 wire signed [32:0] filter_error=$signed({raw_q[31],raw_q})-$signed({velocity_q[31],velocity_q});
 // Same 40ms low-pass and truncate-toward-zero arithmetic as the previous build.
 reg signed [32:0] filter_error_q;
 reg signed [66:0] filter_product_q;
 wire signed [66:0] filter_rounded=filter_product_q+
  (filter_product_q[66] ? 67'sd274877906943:67'sd0);
 wire signed [32:0] filter_delta=filter_rounded>>>38;
 wire signed [32:0] filtered_sum=$signed({velocity_q[31],velocity_q})+filter_delta;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin filter_error_q<=0;filter_product_q<=0;end
  else if(timed_out) begin filter_error_q<=0;filter_product_q<=0;end
  else begin filter_error_q<=filter_error;filter_product_q<=filter_error_q*34'sd6871947674;end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   have_edge<=0;have_period<=0;direction<=0;age<=0;period<=1;period_steps<=1;
   start<=0;pending_negative<=0;job_valid<=0;denominator<=1;numerator<=NUMERATOR;raw_q<=0;velocity_q<=0;
  end else begin
   start<=0;
   if(age<TIMEOUT) age<=age+1'b1;
   if(timed_out) begin have_edge<=0;have_period<=0;raw_q<=0;velocity_q<=0;job_valid<=0;end
   if(fresh_batch) begin
    age<=0;direction<=batch_negative;have_edge<=1;period_steps<=batch_abs[15:0];job_valid<=0;
    if(!have_edge || timed_out) begin have_period<=0;raw_q<=0;end
    else begin period<=age+1'b1;have_period<=1;end
   end
   if(batch_ready && !timed_out && !busy && !start && !done &&
      (have_period || (fresh_batch && have_edge))) begin
    // Start from the just-committed batch too. Otherwise a continuous stream
    // with a nonzero count every ms would cancel every pending old sample.
    denominator<=fresh_batch ? age+1'b1:(age>period ? age:period);
    numerator<=NUMERATOR*(fresh_batch ? {48'd0,batch_abs[15:0]}:{48'd0,period_steps});
    pending_negative<=fresh_batch ? batch_negative:direction;start<=1;job_valid<=1;
   end
   if(done && job_valid && !fresh_batch && !timed_out) begin
    raw_q<=pending_negative ? -magnitude:magnitude;job_valid<=0;
   end
   if(tick_ms && !timed_out) velocity_q<=filtered_sum[31:0];
  end
 end
endmodule
