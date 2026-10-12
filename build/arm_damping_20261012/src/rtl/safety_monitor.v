`timescale 1ns/1ps
// Latch internal sensor/control faults; re-arm only while stopped.
// Retain the three-clock startup hold after reset.
module safety_monitor (
    input wire clk, rst_n, clear_fault, running,
    input wire [3:0] internal_fault,
    output wire permit,
    output reg latched,
    output reg [3:0] code
);
    reg [2:0] startup;
    assign permit=startup[2] & !latched;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin startup<=0; latched<=0; code<=0; end
        else begin
            startup<={startup[1:0],1'b1};
            if (startup[2]) begin
                if (internal_fault!=0) begin latched<=1; code<=internal_fault; end
                else if (clear_fault && !running) begin latched<=0; code<=0; end
            end
        end
    end
endmodule
