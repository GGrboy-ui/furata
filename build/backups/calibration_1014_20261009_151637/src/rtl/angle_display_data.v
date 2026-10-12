`timescale 1ns/1ps
// Display-only path. The controller continues to use the unfiltered ADC sample.
// SV01A103AEA01R00 has a nominal 333-degree electrical range, NOT 360 degrees.
// ADC_ZERO and ADC_SPAN require calibration against the assembled mechanism.
module angle_display_data #(
    parameter integer ADC_ZERO=2098,
    parameter integer ADC_SPAN=4095,
    parameter integer RANGE_TENTHS=3330,
    parameter integer INVERT=0,
    parameter integer AVERAGE_LOG2=4
) (
    input wire clk, rst_n,
    input wire [11:0] sample,
    input wire sample_valid, sample_ready,
    input wire [3:0] sensor_fault,
    input wire [2:0] control_state,
    input wire [3:0] fault_code,
    input wire raw_mode,
    output reg [63:0] segments,
    output reg signed [15:0] angle_tenths,
    output reg [11:0] display_adc,
    output wire angle_valid
);
    // One complete display value is published after averaging and conversion.
    localparam integer COUNT_WIDTH=(AVERAGE_LOG2<1) ? 1 : AVERAGE_LOG2;
    localparam integer ACC_WIDTH=12+AVERAGE_LOG2+1;
    localparam integer AVERAGE_LAST=(1<<AVERAGE_LOG2)-1;
    reg [COUNT_WIDTH-1:0] average_count;
    reg [ACC_WIDTH-1:0] average_sum;
    wire [ACC_WIDTH-1:0] sum_next=average_sum+sample;
    wire [11:0] average_value=sum_next[AVERAGE_LOG2+:12];
    reg [11:0] latest_average;
    reg average_update;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            average_count<=0; average_sum<=0;
            latest_average<=0; average_update<=0;
        end else begin
            average_update<=0;
            if (sample_valid && sample_ready) begin
                if (average_count==AVERAGE_LAST) begin
                    latest_average<=average_value;
                    average_count<=0; average_sum<=0; average_update<=1;
                end else begin
                    average_count<=average_count+1'b1;
                    average_sum<=sum_next;
                end
            end
        end
    end

    localparam [2:0] IDLE=0, PREPARE=1, MULTIPLY=2, DIV_START=3, DIV_WAIT=4, BCD=5;
    reg [2:0] phase;
    reg [11:0] adc_snapshot;
    wire signed [31:0] delta=$signed({1'b0,adc_snapshot})-ADC_ZERO;
    wire [31:0] delta_magnitude=(delta<0) ? -delta : delta;
    reg [12:0] magnitude;
    reg negative;
    reg [23:0] numerator;
    localparam [23:0] RANGE_CONSTANT=RANGE_TENTHS;
    localparam [23:0] ROUND_CONSTANT=ADC_SPAN/2;
    wire [36:0] rounded_product=magnitude*RANGE_CONSTANT+ROUND_CONSTANT;
    localparam [23:0] SPAN_CONSTANT=ADC_SPAN;
    wire divider_done, divider_busy;
    wire [23:0] quotient, remainder_unused;
    divider_seq #(.WIDTH(24)) scale (
        .clk(clk),.rst_n(rst_n),.start(phase==DIV_START),
        .num(numerator),.den(SPAN_CONSTANT),
        .busy(divider_busy),.done(divider_done),.q(quotient),.r(remainder_unused));
    wire [13:0] clipped_angle=(quotient>9999) ? 14'd9999 : quotient[13:0];
    reg [13:0] binary_angle, binary_adc;
    reg [15:0] work_angle, work_adc, bcd_angle, bcd_adc;
    reg [3:0] bcd_count;
    reg displayed_negative, have_value;

    function [15:0] add_three;
        input [15:0] value;
        integer digit;
        begin
            add_three=value;
            for (digit=0;digit<4;digit=digit+1)
                if (value[digit*4+:4]>=5)
                    add_three[digit*4+:4]=value[digit*4+:4]+4'd3;
        end
    endfunction
    wire [15:0] adjusted_angle=add_three(work_angle);
    wire [15:0] adjusted_adc=add_three(work_adc);
    wire [15:0] next_angle={adjusted_angle[14:0],binary_angle[13]};
    wire [15:0] next_adc={adjusted_adc[14:0],binary_adc[13]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase<=IDLE; adc_snapshot<=0; magnitude<=0; negative<=0; numerator<=0;
            binary_angle<=0; binary_adc<=0; work_angle<=0; work_adc<=0;
            bcd_count<=0; bcd_angle<=0; bcd_adc<=0;
            angle_tenths<=0; display_adc<=0; displayed_negative<=0; have_value<=0;
        end else case (phase)
            IDLE: if (average_update) begin adc_snapshot<=latest_average; phase<=PREPARE; end
            PREPARE: begin
                magnitude<=delta_magnitude[12:0];
                negative<=delta[31] ^ (INVERT!=0);
                phase<=MULTIPLY;
            end
            MULTIPLY: begin
                // Round to nearest 0.1 degree, with symmetric positive/negative rounding.
                // ADC_ZERO=0..4095, ADC_SPAN=1..4095, RANGE_TENTHS<=3600:
                // the rounded numerator fits in 24 bits.
                numerator<=rounded_product[23:0];
                phase<=DIV_START;
            end
            DIV_START: phase<=DIV_WAIT;
            DIV_WAIT: if (divider_done) begin
                binary_angle<=clipped_angle; binary_adc<={2'b0,adc_snapshot};
                work_angle<=0; work_adc<=0; bcd_count<=14; phase<=BCD;
            end
            BCD: begin
                work_angle<=next_angle; work_adc<=next_adc;
                binary_angle<=binary_angle<<1; binary_adc<=binary_adc<<1;
                if (bcd_count==1) begin
                    bcd_angle<=next_angle; bcd_adc<=next_adc;
                    display_adc<=adc_snapshot;
                    displayed_negative<=negative && (clipped_angle!=0);
                    angle_tenths<=negative ? -$signed({2'b0,clipped_angle}) :
                                             $signed({2'b0,clipped_angle});
                    have_value<=1; phase<=IDLE;
                end else bcd_count<=bcd_count-1'b1;
            end
            default: phase<=IDLE;
        endcase
    end

    // Rails/blind region must never look like a trustworthy angle. Raw mode
    // still shows the ADC code, including 0000/4095, for wiring diagnosis.
    assign angle_valid=have_value && sample_ready && sensor_fault==0 &&
                       sample!=0 && sample!=4095 && display_adc!=0 && display_adc!=4095;
    function [7:0] glyph;
        input [3:0] number;
        begin case (number)
            0:glyph=8'hc0; 1:glyph=8'hf9; 2:glyph=8'ha4; 3:glyph=8'hb0;
            4:glyph=8'h99; 5:glyph=8'h92; 6:glyph=8'h82; 7:glyph=8'hf8;
            8:glyph=8'h80; 9:glyph=8'h90; 10:glyph=8'h88; 11:glyph=8'h83;
            12:glyph=8'hc6; 13:glyph=8'ha1; 14:glyph=8'h86; 15:glyph=8'h8e;
        endcase end
    endfunction
    // Left to right: state, fault, blank, sign, hundreds, tens, units.dp, tenths.
    // Raw mode:      state, fault, blank, blank, thousands, hundreds, tens, units.
    always @* begin
        segments={8{8'hff}};
        segments[63:56]=glyph({1'b0,control_state});
        segments[55:48]=glyph(fault_code);
        if (raw_mode && sample_ready && have_value) begin
            segments[31:24]=glyph(bcd_adc[15:12]);
            segments[23:16]=glyph(bcd_adc[11:8]);
            segments[15:8]=glyph(bcd_adc[7:4]);
            segments[7:0]=glyph(bcd_adc[3:0]);
        end else if (!raw_mode && angle_valid) begin
            segments[39:32]=displayed_negative ? 8'hbf : 8'hff;
            segments[31:24]=glyph(bcd_angle[15:12]);
            segments[23:16]=glyph(bcd_angle[11:8]);
            segments[15:8]=glyph(bcd_angle[7:4]) & 8'h7f;
            segments[7:0]=glyph(bcd_angle[3:0]);
        end else segments[39:0]={5{8'hbf}};
    end
endmodule
