`timescale 1ns/1ps
// Unwrapped relative position, signed Q16.16 encoder counts.
// Commands add to the pending goal; a 360-degree request must not wrap to zero.
module position_target #(
    parameter integer COUNTS_PER_REV=408,
    parameter integer CW_POSITIVE=1,
    parameter integer MOVE_DEG_PER_SEC=30,
    parameter integer POSITION_LIMIT_COUNTS=4080
) (
    input wire clk, rst_n, enable, tick_ms,
    // One-hot KEY2 / KEY3 / KEY4 events. Ignore simultaneous commands.
    input wire [2:0] move_cmd,
    output reg signed [31:0] goal_q,
    output reg signed [31:0] target_q
);
    localparam signed [31:0] STEP_10_Q=(64'sd65536*COUNTS_PER_REV+18)/36;
    localparam signed [31:0] REV_Q=64'sd65536*COUNTS_PER_REV;
    localparam signed [63:0] RATE_Q=(64'sd65536*COUNTS_PER_REV*MOVE_DEG_PER_SEC+180000)/360000;
    localparam signed [31:0] SLEW_Q=(RATE_Q<1) ? 1 : RATE_Q;
    // Keep all target arithmetic within the core's Q16.16 measurement range.
    localparam integer LIMIT_COUNTS=(POSITION_LIMIT_COUNTS>16000) ? 16000 : POSITION_LIMIT_COUNTS;
    localparam signed [32:0] LIMIT_Q=64'sd65536*LIMIT_COUNTS;
    reg signed [31:0] delta_q;
    wire signed [32:0] next_goal=$signed({goal_q[31],goal_q})+$signed({delta_q[31],delta_q});
    wire signed [32:0] distance_q=$signed({goal_q[31],goal_q})-$signed({target_q[31],target_q});
    always @* begin
        case(move_cmd)
            3'b001: delta_q=(CW_POSITIVE!=0) ? STEP_10_Q : -STEP_10_Q;
            3'b010: delta_q=(CW_POSITIVE!=0) ? -STEP_10_Q : STEP_10_Q;
            3'b100: delta_q=(CW_POSITIVE!=0) ? REV_Q : -REV_Q;
            default: delta_q=0;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin goal_q<=0; target_q<=0; end
        else if (!enable) begin goal_q<=0; target_q<=0; end
        else begin
            if (next_goal>LIMIT_Q) goal_q<=LIMIT_Q[31:0];
            else if (next_goal< -LIMIT_Q) goal_q<=-LIMIT_Q[31:0];
            else goal_q<=next_goal[31:0];
            if (tick_ms) begin
                if (distance_q>$signed(SLEW_Q)) target_q<=target_q+SLEW_Q;
                else if (distance_q< -$signed(SLEW_Q)) target_q<=target_q-SLEW_Q;
                else target_q<=goal_q;
            end
        end
    end
endmodule
