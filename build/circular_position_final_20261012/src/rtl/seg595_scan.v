`timescale 1ns/1ps
// ACG720 U24 selects digits (active high); U25 drives segments (active low).
// Shift MSB first: {segment[7:0], digit_select[7:0]} on each 16-clock transfer.
// All logic uses clk. SCLK/RCLK are registered outputs, not internal clocks.
module seg595_scan #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer SCAN_HZ=1000,
    parameter integer SERIAL_HZ=1_000_000
) (
    input wire clk, rst_n,
    input wire [63:0] segments,
    output reg sclk, rclk, dio
);
    localparam integer SCAN_CYCLES=(CLK_HZ/SCAN_HZ<1) ? 1 : CLK_HZ/SCAN_HZ;
    localparam integer HALF_CYCLES=(CLK_HZ/(2*SERIAL_HZ)<1) ? 1 : CLK_HZ/(2*SERIAL_HZ);
    localparam integer SCAN_WIDTH=(SCAN_CYCLES<2) ? 1 : $clog2(SCAN_CYCLES);
    localparam integer HALF_WIDTH=(HALF_CYCLES<2) ? 1 : $clog2(HALF_CYCLES);
    localparam [1:0] IDLE=0, SHIFT=1, LATCH=2, UNLATCH=3;
    reg [1:0] phase;
    reg [SCAN_WIDTH-1:0] scan_count;
    reg [HALF_WIDTH-1:0] half_count;
    reg [2:0] digit;
    reg [3:0] bit_index;
    reg [63:0] frame;
    reg [15:0] shift_word, on_word;
    reg blank_transfer;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase<=IDLE; scan_count<=0; half_count<=0; digit<=0; bit_index<=15;
            frame<={8{8'hff}}; shift_word<=16'hff00; on_word<=16'hff00;
            blank_transfer<=1; sclk<=0; rclk<=0; dio<=0;
        end else begin
            if (scan_count!=0) scan_count<=scan_count-1'b1;
            case (phase)
                IDLE: if (scan_count==0) begin
                    scan_count<=SCAN_CYCLES-1;
                    // Capture all eight glyphs at the start of a scan frame.
                    // Updating the sensor midway through a scan cannot tear a number.
                    if (digit==0) frame<=segments;
                    on_word<={(digit==0 ? segments[7:0] : frame[digit*8+:8]),(8'b1<<digit)};
                    // Blank all digit selects before changing the next glyph.
                    shift_word<=16'hff00; blank_transfer<=1; bit_index<=15;
                    half_count<=HALF_CYCLES-1; dio<=1; sclk<=0; rclk<=0; phase<=SHIFT;
                end
                SHIFT: if (half_count!=0) half_count<=half_count-1'b1;
                       else begin
                           half_count<=HALF_CYCLES-1;
                           if (!sclk) sclk<=1;
                           else begin
                               sclk<=0;
                               if (bit_index==0) phase<=LATCH;
                               else begin bit_index<=bit_index-1'b1; dio<=shift_word[bit_index-1'b1]; end
                           end
                       end
                LATCH: begin rclk<=1; half_count<=HALF_CYCLES-1; phase<=UNLATCH; end
                UNLATCH: if (half_count!=0) half_count<=half_count-1'b1;
                         else begin
                    rclk<=0;
                    if (blank_transfer) begin
                        shift_word<=on_word; dio<=on_word[15]; bit_index<=15;
                        blank_transfer<=0; half_count<=HALF_CYCLES-1; phase<=SHIFT;
                    end else begin digit<=digit+3'd1; phase<=IDLE; end
                end
                default: phase<=IDLE;
            endcase
        end
    end
endmodule
