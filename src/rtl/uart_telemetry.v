`timescale 1ns/1ps
// Legacy 31 bytes; POSITION_FIELDS adds four signed fields (55 bytes total).
// Extra fields: relative arm counts, target counts, shortest error counts,
// position-loop target-angle offset in 0.1 ADC-code units.
// Sequence advances every 5 ms while enabled, even for invalid/busy slots.
// Each frame snapshots all fields together. Q completes a frame already begun.
module uart_telemetry #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer POSITION_FIELDS=0
) (
    input wire clk, rst_n,
    input wire [7:0] received_byte,
    input wire received_valid,
    input wire signed [15:0] angle_tenths,
    input wire angle_valid,
    input wire signed [15:0] requested_pwm, actual_pwm,
    input wire signed [15:0] arm_position, position_target, position_error, target_offset_adc_tenths,
    output reg [7:0] tx_data,
    output wire tx_valid,
    input wire tx_ready,
    output wire frame_active
);
    localparam integer PERIOD=CLK_HZ/200;
    localparam [1:0] IDLE=0, CONVERT=1, SEND=2, DRAIN=3;
    reg enabled;
    reg [31:0] timer, sequence_q, frame_sequence;
    reg [1:0] phase;
    localparam integer LAST_BYTE=(POSITION_FIELDS!=0) ? 54 : 30;
    reg [5:0] byte_index;
    reg [4:0] convert_left;
    reg angle_negative, request_negative, actual_negative;
    reg [15:0] angle_binary, request_binary, actual_binary;
    reg [15:0] angle_bcd, request_bcd, actual_bcd;
    reg arm_negative, target_negative, error_negative, offset_negative;
    reg [15:0] arm_binary, target_binary, error_binary, offset_binary;
    reg [15:0] arm_bcd, target_bcd, error_bcd, offset_bcd;
    wire start_request=received_valid && received_byte==8'h50; // P
    wire stop_request=received_valid && received_byte==8'h51;  // Q

    function [15:0] magnitude;
        input signed [15:0] value;
        reg signed [16:0] extended;
        reg [16:0] absolute_value;
        begin
            extended={value[15],value};
            absolute_value=value[15] ? -extended : extended;
            magnitude=(absolute_value>9999) ? 16'd9999 : absolute_value[15:0];
        end
    endfunction
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
    function [7:0] hex_ascii;
        input [3:0] value;
        begin hex_ascii=(value<10) ? (8'h30+{4'b0,value}) : (8'h41+{4'b0,value}-8'd10); end
    endfunction
    wire [15:0] angle_adjusted=add_three(angle_bcd);
    wire [15:0] request_adjusted=add_three(request_bcd);
    wire [15:0] actual_adjusted=add_three(actual_bcd);
    wire [15:0] arm_adjusted=add_three(arm_bcd);
    wire [15:0] target_adjusted=add_three(target_bcd);
    wire [15:0] error_adjusted=add_three(error_bcd);
    wire [15:0] offset_adjusted=add_three(offset_bcd);
    assign tx_valid=(phase==SEND);
    assign frame_active=(phase!=IDLE);

    always @* begin
        tx_data=8'h2c;
        case (byte_index)
            0: tx_data=8'h54;
            2,3,4,5,6,7,8,9: tx_data=hex_ascii(frame_sequence[(9-byte_index)*4+:4]);
            11: tx_data=angle_negative ? 8'h2d : 8'h2b;
            12: tx_data=hex_ascii(angle_bcd[15:12]);
            13: tx_data=hex_ascii(angle_bcd[11:8]);
            14: tx_data=hex_ascii(angle_bcd[7:4]);
            15: tx_data=8'h2e;
            16: tx_data=hex_ascii(angle_bcd[3:0]);
            18: tx_data=request_negative ? 8'h2d : 8'h2b;
            19: tx_data=hex_ascii(request_bcd[15:12]);
            20: tx_data=hex_ascii(request_bcd[11:8]);
            21: tx_data=hex_ascii(request_bcd[7:4]);
            22: tx_data=hex_ascii(request_bcd[3:0]);
            24: tx_data=actual_negative ? 8'h2d : 8'h2b;
            25: tx_data=hex_ascii(actual_bcd[15:12]);
            26: tx_data=hex_ascii(actual_bcd[11:8]);
            27: tx_data=hex_ascii(actual_bcd[7:4]);
            28: tx_data=hex_ascii(actual_bcd[3:0]);
            29: tx_data=(POSITION_FIELDS!=0) ? 8'h2c : 8'h0d;
            30: tx_data=(POSITION_FIELDS!=0) ? (arm_negative ? 8'h2d : 8'h2b) : 8'h0a;
            31: tx_data=hex_ascii(arm_bcd[15:12]);
            32: tx_data=hex_ascii(arm_bcd[11:8]);
            33: tx_data=hex_ascii(arm_bcd[7:4]);
            34: tx_data=hex_ascii(arm_bcd[3:0]);
            36: tx_data=target_negative ? 8'h2d : 8'h2b;
            37: tx_data=hex_ascii(target_bcd[15:12]);
            38: tx_data=hex_ascii(target_bcd[11:8]);
            39: tx_data=hex_ascii(target_bcd[7:4]);
            40: tx_data=hex_ascii(target_bcd[3:0]);
            42: tx_data=error_negative ? 8'h2d : 8'h2b;
            43: tx_data=hex_ascii(error_bcd[15:12]);
            44: tx_data=hex_ascii(error_bcd[11:8]);
            45: tx_data=hex_ascii(error_bcd[7:4]);
            46: tx_data=hex_ascii(error_bcd[3:0]);
            48: tx_data=offset_negative ? 8'h2d : 8'h2b;
            49: tx_data=hex_ascii(offset_bcd[15:12]);
            50: tx_data=hex_ascii(offset_bcd[11:8]);
            51: tx_data=hex_ascii(offset_bcd[7:4]);
            52: tx_data=hex_ascii(offset_bcd[3:0]);
            53: tx_data=8'h0d;
            54: tx_data=8'h0a;
            default: tx_data=8'h2c;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enabled<=0; timer<=0; sequence_q<=0; frame_sequence<=0;
            phase<=IDLE; byte_index<=0; convert_left<=0;
            angle_negative<=0; request_negative<=0; actual_negative<=0;
            angle_binary<=0; request_binary<=0; actual_binary<=0;
            angle_bcd<=0; request_bcd<=0; actual_bcd<=0;
            arm_negative<=0; target_negative<=0; error_negative<=0; offset_negative<=0;
            arm_binary<=0; target_binary<=0; error_binary<=0; offset_binary<=0;
            arm_bcd<=0; target_bcd<=0; error_bcd<=0; offset_bcd<=0;
        end else begin
            if (stop_request) begin enabled<=0; timer<=0; end
            else if (start_request && !enabled) begin
                enabled<=1; timer<=0; sequence_q<=0;
            end else if (enabled) begin
                if (timer==PERIOD-1) begin
                    timer<=0; sequence_q<=sequence_q+1'b1;
                    if (angle_valid && phase==IDLE) begin
                        frame_sequence<=sequence_q;
                        angle_binary<=magnitude(angle_tenths);
                        request_binary<=magnitude(requested_pwm);
                        actual_binary<=magnitude(actual_pwm);
                        angle_negative<=angle_tenths<0;
                        request_negative<=requested_pwm<0;
                        actual_negative<=actual_pwm<0;
                        arm_binary<=magnitude(arm_position); target_binary<=magnitude(position_target);
                        error_binary<=magnitude(position_error); offset_binary<=magnitude(target_offset_adc_tenths);
                        arm_negative<=arm_position<0; target_negative<=position_target<0;
                        error_negative<=position_error<0; offset_negative<=target_offset_adc_tenths<0;
                        arm_bcd<=0; target_bcd<=0; error_bcd<=0; offset_bcd<=0;
                        angle_bcd<=0; request_bcd<=0; actual_bcd<=0;
                        convert_left<=16; byte_index<=0; phase<=CONVERT;
                    end
                end else timer<=timer+1'b1;
            end
            case (phase)
                CONVERT: begin
                    angle_bcd<={angle_adjusted[14:0],angle_binary[15]};
                    request_bcd<={request_adjusted[14:0],request_binary[15]};
                    actual_bcd<={actual_adjusted[14:0],actual_binary[15]};
                    angle_binary<=angle_binary<<1;
                    request_binary<=request_binary<<1;
                    actual_binary<=actual_binary<<1;
                    arm_bcd<={arm_adjusted[14:0],arm_binary[15]}; arm_binary<=arm_binary<<1;
                    target_bcd<={target_adjusted[14:0],target_binary[15]}; target_binary<=target_binary<<1;
                    error_bcd<={error_adjusted[14:0],error_binary[15]}; error_binary<=error_binary<<1;
                    offset_bcd<={offset_adjusted[14:0],offset_binary[15]}; offset_binary<=offset_binary<<1;
                    convert_left<=convert_left-1'b1;
                    if (convert_left==1) phase<=SEND;
                end
                SEND: if (tx_ready) begin
                    if (byte_index==LAST_BYTE) phase<=DRAIN;
                    else byte_index<=byte_index+1'b1;
                end
                // Keep echo excluded until the final LF stop bit has left TX.
                DRAIN: if (tx_ready) phase<=IDLE;
                default: ;
            endcase
        end
    end
endmodule
