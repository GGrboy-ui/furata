`timescale 1ns/1ps
// ASCII calibration wire, uppercase fixed-width hexadecimal except signed PWM:
// I,DZCAL1,build8,pwmmax4,cpr4,000A,0014,0078,0258,00C8,0096,crc2 CRLF
// M,ms8,session8,trial4,phase1,result1,fault1,pos8,req(+/-dddd),actual(+/-dddd),adc4,flags1,crc2 CRLF
// R,session8,trial4,result1,tcmd8,tpwm8,tedge8,tend8,startpos8,endpos8,w1(4),w2(4),w3(4),crc2 CRLF
// Positions use 32-bit two's complement hex. flags: ready/session/active in bits 0/1/2.
// CRC-8/ATM covers the leading I/M/R through the byte before the final comma.
// M is 100 Hz and independent of ADC validity. !i selects this stream; legacy P/Q
// deselect it after any complete frame. I/R priority applies at frame boundaries.
// A four-entry FIFO preserves pending result snapshots plus the active frame.
// Caller must not emit more than four outstanding result events without TX progress.
// PWM decimal conversion is 16 sequential double-dabble clocks, not a long divide.
module calibration_telemetry #(
    parameter integer CLK_HZ=50_000_000,
    parameter [31:0] BUILD_ID=32'h20261014,
    parameter [15:0] PWM_MAX=16'd2500,
    parameter [15:0] COUNTS_PER_REV=16'd408
) (
    input wire clk, rst_n, info_request, event_valid,
    input wire [7:0] legacy_byte,
    input wire legacy_valid,
    input wire session_active, active,
    input wire [31:0] session_id,
    input wire [15:0] trial_id,
    input wire [3:0] phase, result, fault,
    input wire [31:0] ms_now,
    input wire signed [31:0] position,
    input wire signed [15:0] requested_pwm, actual_pwm,
    input wire [11:0] sample,
    input wire sample_ready,
    input wire [31:0] t_command, t_pwm, t_edge, t_end,
    input wire signed [31:0] start_position, end_position,
    input wire [15:0] window1, window2, window3,
    input wire tx_ready,
    output reg [7:0] tx_data,
    output wire tx_valid, frame_active,
    output reg stream_mode
);
    localparam integer PERIOD=(CLK_HZ/100<1) ? 1 : CLK_HZ/100;
    localparam [1:0] IDLE=0, CONVERT=1, SEND=2, DRAIN=3;
    localparam [1:0] FRAME_I=0, FRAME_M=1, FRAME_R=2;
    localparam [6:0] I_BODY=57, M_BODY=58, R_BODY=86;
    reg [1:0] state, frame_kind;
    reg [6:0] byte_index;
    reg [31:0] timer;
    reg info_pending, sample_pending;
    reg [7:0] crc_q;
    reg [31:0] ms_q, session_q, position_q;
    reg [15:0] trial_q, sample_q;
    reg [3:0] phase_q, result_q, fault_q, flags_q;
    reg [31:0] t_command_q, t_pwm_q, t_edge_q, t_end_q, start_position_q, end_position_q;
    reg [15:0] window1_q, window2_q, window3_q;
    reg request_negative, actual_negative;
    reg [15:0] request_binary, actual_binary, request_bcd, actual_bcd;
    reg [4:0] convert_left;
    reg [291:0] event_fifo [0:3];
    reg [1:0] write_pointer, read_pointer;
    reg [2:0] event_count;
    wire stop_stream=legacy_valid && (legacy_byte=="P" || legacy_byte=="Q");
    wire event_pop=state==IDLE && stream_mode && !stop_stream &&
                   !info_pending && !info_request && event_count!=0;
    wire event_push=event_valid && (event_count<4 || event_pop);
    wire [6:0] body_length=(frame_kind==FRAME_I) ? I_BODY :
                           (frame_kind==FRAME_M) ? M_BODY : R_BODY;
    wire [6:0] last_byte=body_length+7'd4;
    assign tx_valid=state==SEND;
    assign frame_active=state!=IDLE;
    function [7:0] hex_ascii;
        input [3:0] value;
        begin hex_ascii=value<10 ? 8'h30+{4'b0,value} : 8'h41+{4'b0,value}-8'd10; end
    endfunction
    function [7:0] crc8;
        input [7:0] old_crc, value;
        reg [7:0] work;
        integer j;
        begin
            work=old_crc^value;
            for(j=0;j<8;j=j+1) work=work[7] ? (work<<1)^8'h07 : work<<1;
            crc8=work;
        end
    endfunction
    function [15:0] magnitude;
        input signed [15:0] value;
        reg signed [16:0] widened;
        reg [16:0] absolute_value;
        begin
            widened={value[15],value};
            absolute_value=value[15] ? -widened : widened;
            magnitude=absolute_value>9999 ? 16'd9999 : absolute_value[15:0];
        end
    endfunction
    function [15:0] add_three;
        input [15:0] value;
        integer j;
        begin
            add_three=value;
            for(j=0;j<4;j=j+1)
                if(value[j*4+:4]>=5) add_three[j*4+:4]=value[j*4+:4]+4'd3;
        end
    endfunction
    wire [15:0] request_adjusted=add_three(request_bcd);
    wire [15:0] actual_adjusted=add_three(actual_bcd);
    always @* begin
        tx_data=8'h2c;
        case(frame_kind)
            FRAME_I: case(byte_index)
                0: tx_data=8'h49;
                2: tx_data=8'h44;
                3: tx_data=8'h5a;
                4: tx_data=8'h43;
                5: tx_data=8'h41;
                6: tx_data=8'h4c;
                7: tx_data=8'h31;
                9,10,11,12,13,14,15,16: tx_data=hex_ascii(BUILD_ID[(16-byte_index)*4+:4]);
                18,19,20,21: tx_data=hex_ascii(PWM_MAX[(21-byte_index)*4+:4]);
                23,24,25,26: tx_data=hex_ascii(COUNTS_PER_REV[(26-byte_index)*4+:4]);
                28: tx_data=8'h30;
                29: tx_data=8'h30;
                30: tx_data=8'h30;
                31: tx_data=8'h41;
                33: tx_data=8'h30;
                34: tx_data=8'h30;
                35: tx_data=8'h31;
                36: tx_data=8'h34;
                38: tx_data=8'h30;
                39: tx_data=8'h30;
                40: tx_data=8'h37;
                41: tx_data=8'h38;
                43: tx_data=8'h30;
                44: tx_data=8'h32;
                45: tx_data=8'h35;
                46: tx_data=8'h38;
                48: tx_data=8'h30;
                49: tx_data=8'h30;
                50: tx_data=8'h43;
                51: tx_data=8'h38;
                53: tx_data=8'h30;
                54: tx_data=8'h30;
                55: tx_data=8'h39;
                56: tx_data=8'h36;
                58: tx_data=hex_ascii(crc_q[7:4]);
                59: tx_data=hex_ascii(crc_q[3:0]);
                60: tx_data=8'h0d;
                61: tx_data=8'h0a;
                default: ;
            endcase
            FRAME_M: case(byte_index)
                0: tx_data=8'h4d;
                2,3,4,5,6,7,8,9: tx_data=hex_ascii(ms_q[(9-byte_index)*4+:4]);
                11,12,13,14,15,16,17,18: tx_data=hex_ascii(session_q[(18-byte_index)*4+:4]);
                20,21,22,23: tx_data=hex_ascii(trial_q[(23-byte_index)*4+:4]);
                25: tx_data=hex_ascii(phase_q[3:0]);
                27: tx_data=hex_ascii(result_q[3:0]);
                29: tx_data=hex_ascii(fault_q[3:0]);
                31,32,33,34,35,36,37,38: tx_data=hex_ascii(position_q[(38-byte_index)*4+:4]);
                40: tx_data=request_negative ? 8'h2d : 8'h2b;
                41,42,43,44: tx_data=hex_ascii(request_bcd[(44-byte_index)*4+:4]);
                46: tx_data=actual_negative ? 8'h2d : 8'h2b;
                47,48,49,50: tx_data=hex_ascii(actual_bcd[(50-byte_index)*4+:4]);
                52,53,54,55: tx_data=hex_ascii(sample_q[(55-byte_index)*4+:4]);
                57: tx_data=hex_ascii(flags_q[3:0]);
                59: tx_data=hex_ascii(crc_q[7:4]);
                60: tx_data=hex_ascii(crc_q[3:0]);
                61: tx_data=8'h0d;
                62: tx_data=8'h0a;
                default: ;
            endcase
            FRAME_R: case(byte_index)
                0: tx_data=8'h52;
                2,3,4,5,6,7,8,9: tx_data=hex_ascii(session_q[(9-byte_index)*4+:4]);
                11,12,13,14: tx_data=hex_ascii(trial_q[(14-byte_index)*4+:4]);
                16: tx_data=hex_ascii(result_q[3:0]);
                18,19,20,21,22,23,24,25: tx_data=hex_ascii(t_command_q[(25-byte_index)*4+:4]);
                27,28,29,30,31,32,33,34: tx_data=hex_ascii(t_pwm_q[(34-byte_index)*4+:4]);
                36,37,38,39,40,41,42,43: tx_data=hex_ascii(t_edge_q[(43-byte_index)*4+:4]);
                45,46,47,48,49,50,51,52: tx_data=hex_ascii(t_end_q[(52-byte_index)*4+:4]);
                54,55,56,57,58,59,60,61: tx_data=hex_ascii(start_position_q[(61-byte_index)*4+:4]);
                63,64,65,66,67,68,69,70: tx_data=hex_ascii(end_position_q[(70-byte_index)*4+:4]);
                72,73,74,75: tx_data=hex_ascii(window1_q[(75-byte_index)*4+:4]);
                77,78,79,80: tx_data=hex_ascii(window2_q[(80-byte_index)*4+:4]);
                82,83,84,85: tx_data=hex_ascii(window3_q[(85-byte_index)*4+:4]);
                87: tx_data=hex_ascii(crc_q[7:4]);
                88: tx_data=hex_ascii(crc_q[3:0]);
                89: tx_data=8'h0d;
                90: tx_data=8'h0a;
                default: ;
            endcase
            default: ;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            write_pointer<=0; read_pointer<=0; event_count<=0;
        end else begin
            if(event_push) begin
                event_fifo[write_pointer]<={session_id,trial_id,result,t_command,t_pwm,t_edge,t_end,
                    start_position,end_position,window1,window2,window3};
                write_pointer<=write_pointer+1'b1;
            end
            if(event_pop) read_pointer<=read_pointer+1'b1;
            case({event_push,event_pop})
                2'b10: event_count<=event_count+1'b1;
                2'b01: event_count<=event_count-1'b1;
                default: ;
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; frame_kind<=FRAME_I; byte_index<=0; timer<=0;
            info_pending<=0; sample_pending<=0; stream_mode<=0; crc_q<=0;
            ms_q<=0; session_q<=0; position_q<=0; trial_q<=0; sample_q<=0;
            phase_q<=0; result_q<=0; fault_q<=0; flags_q<=0;
            t_command_q<=0; t_pwm_q<=0; t_edge_q<=0; t_end_q<=0;
            start_position_q<=0; end_position_q<=0; window1_q<=0; window2_q<=0; window3_q<=0;
            request_negative<=0; actual_negative<=0;
            request_binary<=0; actual_binary<=0; request_bcd<=0; actual_bcd<=0; convert_left<=0;
        end else begin
            if(info_request) begin stream_mode<=1; info_pending<=1; timer<=0; end
            else if(stop_stream) begin stream_mode<=0; info_pending<=0; sample_pending<=0; timer<=0; end
            else if(!stream_mode) timer<=0;
            else if(timer==PERIOD-1) begin timer<=0; sample_pending<=1; end
            else timer<=timer+1'b1;
            case(state)
                IDLE: if(stream_mode && !stop_stream) begin
                    byte_index<=0; crc_q<=0;
                    if(info_pending) begin
                        frame_kind<=FRAME_I; info_pending<=info_request; state<=SEND;
                    end else if(event_pop) begin
                        {session_q,trial_q,result_q,t_command_q,t_pwm_q,t_edge_q,t_end_q,
                         start_position_q,end_position_q,window1_q,window2_q,window3_q}
                            <=event_fifo[read_pointer];
                        frame_kind<=FRAME_R; state<=SEND;
                    end else if(sample_pending && !info_request) begin
                        ms_q<=ms_now; session_q<=session_id; trial_q<=trial_id;
                        phase_q<=phase; result_q<=result; fault_q<=fault; position_q<=position;
                        sample_q<={4'b0,sample}; flags_q<={1'b0,active,session_active,sample_ready};
                        request_negative<=requested_pwm<0; actual_negative<=actual_pwm<0;
                        request_binary<=magnitude(requested_pwm); actual_binary<=magnitude(actual_pwm);
                        request_bcd<=0; actual_bcd<=0; convert_left<=16;
                        frame_kind<=FRAME_M; sample_pending<=0; state<=CONVERT;
                    end
                end
                CONVERT: begin
                    request_bcd<={request_adjusted[14:0],request_binary[15]};
                    actual_bcd<={actual_adjusted[14:0],actual_binary[15]};
                    request_binary<=request_binary<<1; actual_binary<=actual_binary<<1;
                    convert_left<=convert_left-1'b1;
                    if(convert_left==1) state<=SEND;
                end
                SEND: if(tx_ready) begin
                    if(byte_index<body_length) crc_q<=crc8(crc_q,tx_data);
                    if(byte_index==last_byte) state<=DRAIN;
                    else byte_index<=byte_index+1'b1;
                end
                DRAIN: if(tx_ready) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule

