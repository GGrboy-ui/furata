`timescale 1ns/1ps
// Coulomb/friction offset in PWM counts. Direction follows the controller,
// including braking. active is false for an exactly zero unquantized request.
// Three stages keep conversion, addition and saturation on separate paths.
module pwm_friction #(parameter integer PWM_MAX=2500)(
 input wire clk,rst_n,active,negative,
 input wire [15:0] magnitude,t_counts,
 output reg signed [15:0] command
);
 reg [15:0] base_q,offset_q;
 reg negative_q,negative_sum;
 reg [16:0] sum_q;
 wire [15:0] limited=sum_q>PWM_MAX ? PWM_MAX:sum_q[15:0];
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   base_q<=0;offset_q<=0;negative_q<=0;negative_sum<=0;sum_q<=0;command<=0;
  end else begin
   base_q<=magnitude;offset_q<=active ? t_counts:16'd0;negative_q<=negative;
   sum_q<={1'b0,base_q}+{1'b0,offset_q};negative_sum<=negative_q;
   command<=negative_sum ? -$signed(limited):$signed(limited);
  end
 end
endmodule
