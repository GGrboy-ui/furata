`timescale 1ns/1ps
// Independent control-speed estimate; legacy encoder_qei.vel is unchanged.
// Only adjacent valid quadrature edges count. First/reversed edge establishes
// an epoch, a second same-direction edge establishes a period. Late results
// are invalidated across reversals/timeouts. tick_ms must represent 1 ms.
module velocity_feedback #(parameter integer CLK_HZ=50000000)(
 input wire clk,rst_n,tick_ms,edge_valid,edge_negative,
 output reg signed [31:0] velocity_q
);
 localparam [63:0] NUMERATOR=64'd65536*CLK_HZ;
 localparam [31:0] TIMEOUT=CLK_HZ;
 reg have_edge,have_period,direction;
 reg [31:0] age,period;
 reg start,pending_negative;
 reg [31:0] denominator;
 reg signed [31:0] raw_q;
 wire busy,done;wire [63:0] quotient,remainder_unused;
 wire reversal=edge_valid && have_edge && edge_negative!=direction;
 wire invalidate=reversal || age>=TIMEOUT;
 // Resetting the divider cancels old-direction work rather than accepting it later.
 wire divide_reset=rst_n && !invalidate;
 divider_seq #(.WIDTH(64)) div(.clk(clk),.rst_n(divide_reset),.start(start),
  .num(NUMERATOR),.den({32'd0,denominator}),.busy(busy),.done(done),.q(quotient),.r(remainder_unused));
 wire signed [31:0] magnitude=quotient>64'd2048000000 ? 32'sd2048000000:$signed(quotient[31:0]);
 wire signed [32:0] filter_error=$signed({raw_q[31],raw_q})-$signed({velocity_q[31],velocity_q});
 // Exact signed truncate-toward-zero /40 for every 33-bit input, using DSPs.
 // K=ceil(2^38/40), 40*K-2^38=16; 16*2^32<2^38 bounds reciprocal error.
 // Register both arithmetic stages; their 2-clock latency is far below 1 ms.
 reg signed [32:0] filter_error_q;
 reg signed [66:0] filter_product_q;
 wire signed [66:0] filter_rounded=filter_product_q+
  (filter_product_q[66] ? 67'sd274877906943:67'sd0);
 wire signed [32:0] filter_delta=filter_rounded>>>38;
 wire signed [32:0] filtered_sum=$signed({velocity_q[31],velocity_q})+filter_delta;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin filter_error_q<=0;filter_product_q<=0;end
  else if(invalidate || (edge_valid && !have_edge)) begin filter_error_q<=0;filter_product_q<=0;end
  else begin filter_error_q<=filter_error;filter_product_q<=filter_error_q*34'sd6871947674;end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   have_edge<=0;have_period<=0;direction<=0;age<=0;period<=1;start<=0;pending_negative<=0;
   denominator<=1;raw_q<=0;velocity_q<=0;
  end else begin
   start<=0;
   if(age<TIMEOUT) age<=age+1'b1;
   if(age>=TIMEOUT) begin have_edge<=0;have_period<=0;raw_q<=0;velocity_q<=0;end
   if(edge_valid) begin
    age<=0;direction<=edge_negative;have_edge<=1;
    if(!have_edge || reversal || age>=TIMEOUT) begin have_period<=0;raw_q<=0;velocity_q<=0;end
    else begin period<=age+1'b1;have_period<=1;end
   end
   if(tick_ms && have_period && !invalidate && !busy && !start) begin
    denominator<=age>period ? age:period;pending_negative<=direction;start<=1;
   end
   if(done && !invalidate) raw_q<=pending_negative ? -magnitude:magnitude;
   if(tick_ms && !invalidate && !(edge_valid && !have_edge)) velocity_q<=filtered_sum[31:0]; // Explicit narrowing; same low 32 bits as before.
  end
 end
endmodule
