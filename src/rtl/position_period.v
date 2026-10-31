`timescale 1ns/1ps
// System-reset configuration: K4/STOP must not reset the selected period.
module position_period #(parameter integer DEFAULT_MS=50)(
 input wire clk,rst_n,request,allowed,position_update,
 input wire [2:0] control_state,
 input wire [15:0] requested_ms,
 output reg [15:0] actual_ms,
 output reg pending,reply,
 output reg [7:0] code
);
 reg [15:0] queued_ms;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin actual_ms<=DEFAULT_MS;queued_ms<=DEFAULT_MS;pending<=0;reply<=0;code<=0;end
  else begin
   reply<=0;
   if(pending) begin
    if(!allowed) begin pending<=0;reply<=1;code<=8'h11;end
    else if(control_state==0 || position_update) begin
     actual_ms<=queued_ms;pending<=0;reply<=1;code<=8'h04;
    end
   end
   if(request) begin
    if(pending) begin reply<=1;code<=8'h10;end
    else if(!allowed) begin reply<=1;code<=8'h11;end
    else if(requested_ms<1 || requested_ms>1000) begin reply<=1;code<=8'h12;end
    else if(control_state==0) begin actual_ms<=requested_ms;reply<=1;code<=8'h04;end
    else begin queued_ms<=requested_ms;pending<=1;end
   end
  end
 end
endmodule
