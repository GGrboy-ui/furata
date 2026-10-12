// clock_reset.v - reset conditioning: asynchronous assert, synchronous release.
//
// Why: the board reset comes from button SW5 (active low, asynchronous). Feeding that
// straight into logic produces recovery/removal violations and can release reset on
// different cycles in different parts of the design. This module:
//   1. synchronises the raw reset source and the PLL lock input,
//   2. holds reset until BOTH are good, then stretches it for STRETCH_CYCLES,
//   3. releases it synchronously, so every flop leaves reset on the same clock edge.
//
// Assertion is still asynchronous (the async reset term on the flops), so a reset press
// takes effect immediately even if the clock is not running yet.
//
// The Gowin rPLL primitive is deliberately NOT instantiated here. This module takes the
// already-multiplied clock and its `locked` output. Keeping vendor primitives out of rtl/
// is what lets Verilator lint the whole tree; the thin rPLL wrapper belongs in a separate
// file that only the synthesis flow pulls in. At 50 MHz direct from M19 there is no need
// for a PLL at all in this milestone.
`timescale 1ns / 1ps

module clock_reset #(
    parameter [15:0] STRETCH_CYCLES = 16'd16   // reset held this many clocks after inputs are good
) (
    input  wire clk,        // system clock the reset is synchronised to
    input  wire arst_n,     // raw asynchronous reset source, active low (button / external)
    input  wire locked,     // PLL lock, active high; tie 1'b1 when no PLL is used
    output wire rst_n       // conditioned reset, active low, synchronous release
);
    localparam [15:0] STRETCH = STRETCH_CYCLES;

    // Two-flop synchroniser for the raw reset source. Its async clear is the only
    // asynchronous thing in this module, and it is what makes reset assertion immediate.
    reg [1:0] arst_sync;
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) arst_sync <= 2'b00;
        else         arst_sync <= {arst_sync[0], 1'b1};
    end

    // PLL lock is asynchronous to clk too, so it gets its own synchroniser.
    reg [1:0] lock_sync;
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) lock_sync <= 2'b00;
        else         lock_sync <= {lock_sync[0], locked};
    end

    wire inputs_ok = arst_sync[1] & lock_sync[1];

    reg [15:0] stretch_cnt;
    reg        rst_n_q;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            stretch_cnt <= 16'd0;
            rst_n_q     <= 1'b0;
        end else if (!inputs_ok) begin
            // reset source still asserted or PLL unlocked: restart the stretch
            stretch_cnt <= 16'd0;
            rst_n_q     <= 1'b0;
        end else if (stretch_cnt < STRETCH) begin
            stretch_cnt <= stretch_cnt + 16'd1;
            rst_n_q     <= 1'b0;
        end else begin
            rst_n_q     <= 1'b1;
        end
    end

    assign rst_n = rst_n_q;
endmodule
