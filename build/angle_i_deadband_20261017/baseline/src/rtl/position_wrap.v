`timescale 1ns/1ps
// Signed circular Q16.16 coordinate in [-one_turn/2, one_turn/2).
// Sequential remainder keeps the 50 MHz control path free of a large divider.
module position_wrap #(
    parameter integer COUNTS_PER_REV=408
) (
    input wire clk, rst_n,
    input wire signed [49:0] value_q,
    output reg signed [31:0] wrapped_q,
    output reg valid
);
    localparam integer REV_COUNTS=(COUNTS_PER_REV<1) ? 1 : COUNTS_PER_REV;
    localparam signed [49:0] PERIOD_Q=REV_COUNTS*50'sd65536;
    localparam signed [49:0] HALF_Q=PERIOD_Q/2;
    reg pending, negative;
    reg signed [49:0] submitted_q;
    wire busy, done;
    wire [49:0] quotient_unused, remainder_q;
    wire launch=!pending && !busy && (!valid || value_q!=submitted_q);
    wire [49:0] magnitude=value_q[49] ? -value_q : value_q;
    wire signed [49:0] signed_remainder=negative ? -$signed(remainder_q) : $signed(remainder_q);
    wire signed [49:0] shortest=(signed_remainder>=HALF_Q) ? signed_remainder-PERIOD_Q :
                               (signed_remainder< -HALF_Q) ? signed_remainder+PERIOD_Q : signed_remainder;
    divider_seq #(.WIDTH(50)) divide (
        .clk(clk),.rst_n(rst_n),.start(launch),.num(magnitude),.den(PERIOD_Q),
        .busy(busy),.done(done),.q(quotient_unused),.r(remainder_q));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wrapped_q<=0; valid<=0; pending<=0; negative<=0; submitted_q<=0;
        end else begin
            if (launch) begin pending<=1; negative<=value_q[49]; submitted_q<=value_q; end
            if (done) begin wrapped_q<=shortest[31:0]; valid<=1; pending<=0; end
        end
    end
endmodule
