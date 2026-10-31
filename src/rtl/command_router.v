`timescale 1ns/1ps
// Route @T... exclusively to TRJ1; preserve ARM1 and legacy single bytes.
module command_router #(parameter integer CLK_HZ=50000000)(
    input wire clk,rst_n,input wire [7:0] data,input wire valid,
    output reg [7:0] arm_data,trajectory_data,output reg arm_valid,trajectory_valid
);
    reg [1:0] route;
    reg replay;
    reg expired;
    reg [7:0] second;
    reg [31:0] age;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin route<=0;replay<=0;expired<=0;second<=0;age<=0;arm_data<=0;trajectory_data<=0;arm_valid<=0;trajectory_valid<=0;end
        else begin
            arm_valid<=0;trajectory_valid<=0;
            if(route!=0) begin
                if(age>=CLK_HZ/5) begin expired<=1;replay<=0;end
                else age<=age+1;
            end
            if(replay) begin
                replay<=0;
                if(route==3) begin trajectory_data<=second;trajectory_valid<=1;end
                else begin arm_data<=second;arm_valid<=1;end
            end
            if(valid) begin
                if(data==8'h58) begin
                    route<=0;replay<=0;expired<=0;arm_data<=data;arm_valid<=1;trajectory_data<=data;trajectory_valid<=1;
                end else if(data==8'h40) begin route<=1;age<=0;replay<=0;expired<=0;end
                else if(expired) begin if(data==8'h0a) begin route<=0;expired<=0;end end
                else if(route==1) begin
                    route<=data==8'h54 ? 3:2;second<=data;replay<=1;
                    if(data==8'h54) begin trajectory_data<=8'h40;trajectory_valid<=1;end
                    else begin arm_data<=8'h40;arm_valid<=1;end
                end else if(route==3) begin
                    trajectory_data<=data;trajectory_valid<=1;if(data==8'h0a) route<=0;
                end else begin
                    arm_data<=data;arm_valid<=1;if(data==8'h0a) route<=0;
                end
            end
        end
    end
endmodule
