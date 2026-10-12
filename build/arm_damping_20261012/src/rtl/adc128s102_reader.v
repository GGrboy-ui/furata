`timescale 1ns/1ps
// ADC128S102 serial interface, 16 clocks/frame.  The converter returns the
// result of the previous frame, therefore every request sends a command frame
// followed by a second (identical) frame and only the second result is reported.
// DIN is changed while SCLK is low and DOUT is sampled on the rising edge
// (the mode-3 timing used by the ACG720 schematic example).
module adc128s102_reader #(
    parameter integer HALF_DIV=2
) (
    input wire clk, rst_n, start,
    input wire [2:0] channel,
    input wire dout,
    output reg cs_n, sclk, din,
    output wire busy,
    output reg [11:0] data,
    output reg valid
);
    reg [2:0] state;
    reg [31:0] divider;
    reg [4:0] bit_index;
    reg [15:0] tx, rx;
    reg second_frame;
    assign busy=(state!=0);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=0; divider<=0; bit_index<=0; tx<=0; rx<=0;
            second_frame<=0; cs_n<=1; sclk<=1; din<=0; data<=0; valid<=0;
        end else begin
            valid<=0;
            if (state==0) begin
                cs_n<=1; sclk<=1; din<=0;
                if (start) begin
                    // The first byte is {DC,DC,ADD2,ADD1,ADD0,DC,DC,DC}.
                    // Address occupies bits 13:11 of the 16-clock frame.
                    tx<={2'b00,channel,11'b0};
                    rx<=0; bit_index<=15;
                    second_frame<=0; divider<=HALF_DIV-1; cs_n<=0; state<=1;
                end
            end else if (divider!=0) divider<=divider-1;
            else begin
                divider<=HALF_DIV-1;
                case (state)
                    1: begin
                        if (sclk) begin sclk<=0; din<=tx[bit_index]; end
                        else begin
                            sclk<=1; rx<={rx[14:0],dout};
                            if (bit_index==0) state<=2;
                            else bit_index<=bit_index-5'd1;
                        end
                    end
                    2: begin
                        cs_n<=1; din<=0;
                        if (second_frame) begin
                            // The first four received bits are pipeline/null
                            // bits; the final twelve are the ADC result.
                            data<=rx[11:0]; valid<=1; state<=0;
                        end
                        else begin second_frame<=1; state<=3; end
                    end
                    3: begin cs_n<=0; rx<=0; bit_index<=15; state<=1; end
                    default: begin state<=0; cs_n<=1; sclk<=1; end
                endcase
            end
        end
    end
endmodule
