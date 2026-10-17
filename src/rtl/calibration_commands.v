`timescale 1ns/1ps
// Calibration command wire protocol (ASCII, decimal fields):
// !i LF; !c,session,cpr,travel_tenths,encoder_sign,CRC LF;
// !b,session,trial,duty_counts,profile,CRC LF;
// !r,session,trial,kick_counts,hold_counts,CRC LF;
// !h,session,CRC LF; !g,session,trial,CRC LF; !e,session,CRC LF.
// Optional CR precedes LF. CRC-8/ATM: poly 07, init 00, no reflection/xor;
// covers characters after ! and before the last comma. Golden: b,1,1,25,0 -> F6.
// Each byte is parsed sequentially; no unbounded line buffer or combinational scan.
// X is an emergency in every state. Other legacy bytes are routed only outside
// a calibration frame. Invalid frames are discarded to LF or the 100 ms timeout.
module calibration_commands #(
    parameter integer CLK_HZ=50_000_000
) (
    input wire clk, rst_n,
    input wire [7:0] received_byte,
    input wire received_valid,
    output reg [7:0] legacy_byte,
    output reg legacy_valid, emergency_stop, info_request, request_valid,
    output reg [2:0] request_kind,
    output reg [31:0] request_session,
    output reg [15:0] request_trial,
    output reg signed [31:0] request_a, request_b, request_c,
    output reg parse_error
);
    localparam integer TIMEOUT_CLKS=(CLK_HZ/10<1) ? 1 : CLK_HZ/10;
    localparam [3:0] IDLE=0, OPCODE=1, FIRST_COMMA=2, NUMBER=3,
                     CRC_HIGH=4, CRC_LOW=5, EOL=6, AFTER_CR=7,
                     INFO_EOL=8, INFO_CR=9, DISCARD=10;
    reg [3:0] state;
    reg [31:0] timeout_count;
    reg [6:0] length;
    reg [2:0] kind, field_index;
    reg [31:0] session_q, number_q;
    reg [15:0] trial_q;
    reg signed [31:0] a_q, b_q, c_q;
    reg negative, digit_seen, sign_seen;
    reg [7:0] crc_q, received_crc;
    wire [2:0] field_count=(kind==1 || kind==2 || kind==3) ? 3'd4 :
                           (kind==5) ? 3'd2 : 3'd1;
    wire signed_field=(kind==1 && field_index!=0) ||
                      ((kind==2 || kind==3) && field_index>=2);
    wire [35:0] next_number={4'b0,number_q}*36'd10+{32'b0,received_byte[3:0]};
    wire [35:0] number_limit=signed_field ?
        (negative ? 36'h080000000 : 36'h07fffffff) :
        (field_index==1 && kind!=1 ? 36'h00000ffff : 36'h0ffffffff);
    wire signed [31:0] signed_number=negative ? -$signed(number_q) : $signed(number_q);
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
    function [4:0] hex_value;
        input [7:0] value;
        begin
            if(value>="0" && value<="9") hex_value={1'b0,value[3:0]};
            else if(value>="A" && value<="F") hex_value=value-8'h41+5'd10;
            else if(value>="a" && value<="f") hex_value=value-8'h61+5'd10;
            else hex_value=5'h10;
        end
    endfunction
    wire [4:0] digit_hex=hex_value(received_byte);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; timeout_count<=0; length<=0; kind<=0; field_index<=0;
            session_q<=0; trial_q<=0; a_q<=0; b_q<=0; c_q<=0;
            number_q<=0; negative<=0; digit_seen<=0; sign_seen<=0;
            crc_q<=0; received_crc<=0;
            legacy_byte<=0; legacy_valid<=0; emergency_stop<=0; info_request<=0;
            request_valid<=0; request_kind<=0; request_session<=0; request_trial<=0;
            request_a<=0; request_b<=0; request_c<=0; parse_error<=0;
        end else begin
            legacy_valid<=0; emergency_stop<=0; info_request<=0; request_valid<=0; parse_error<=0;
            if(state==IDLE || received_valid) timeout_count<=0;
            else if(timeout_count>=TIMEOUT_CLKS-1) begin
                state<=IDLE; timeout_count<=0; parse_error<=1;
            end else timeout_count<=timeout_count+1'b1;
            if(received_valid) begin
                if(received_byte=="X") begin
                    emergency_stop<=1; state<=IDLE; length<=0;
                end else if(state==IDLE) begin
                    if(received_byte=="!") begin
                        state<=OPCODE; length<=1; crc_q<=0; kind<=0; field_index<=0;
                        session_q<=0; trial_q<=0; a_q<=0; b_q<=0; c_q<=0;
                        number_q<=0; negative<=0; digit_seen<=0; sign_seen<=0;
                    end else begin legacy_byte<=received_byte; legacy_valid<=1; end
                end else if(state==DISCARD) begin
                    if(received_byte==8'h0a) state<=IDLE;
                end else if(length>=80 && received_byte!=8'h0a) begin
                    state<=DISCARD; parse_error<=1;
                end else begin
                    length<=length+1'b1;
                    case(state)
                        OPCODE: begin
                            crc_q<=crc8(0,received_byte);
                            case(received_byte)
                                "i": state<=INFO_EOL;
                                "c": begin kind<=1; state<=FIRST_COMMA; end
                                "b": begin kind<=2; state<=FIRST_COMMA; end
                                "r": begin kind<=3; state<=FIRST_COMMA; end
                                "h": begin kind<=4; state<=FIRST_COMMA; end
                                "g": begin kind<=5; state<=FIRST_COMMA; end
                                "e": begin kind<=6; state<=FIRST_COMMA; end
                                default: begin state<=received_byte==10 ? IDLE : DISCARD; parse_error<=1; end
                            endcase
                        end
                        FIRST_COMMA: if(received_byte==",") begin
                            crc_q<=crc8(crc_q,received_byte); state<=NUMBER;
                        end else begin state<=received_byte==10 ? IDLE : DISCARD; parse_error<=1; end
                        NUMBER: begin
                            if(received_byte>="0" && received_byte<="9") begin
                                if(next_number>number_limit) begin state<=DISCARD; parse_error<=1; end
                                else begin number_q<=next_number[31:0]; digit_seen<=1; crc_q<=crc8(crc_q,received_byte); end
                            end else if((received_byte=="-" || received_byte=="+") && signed_field && !sign_seen && !digit_seen) begin
                                negative<=received_byte=="-"; sign_seen<=1; crc_q<=crc8(crc_q,received_byte);
                            end else if(received_byte=="," && digit_seen) begin
                                if(field_index==0) session_q<=number_q;
                                else if(kind==1) begin
                                    if(field_index==1) a_q<=signed_number;
                                    else if(field_index==2) b_q<=signed_number;
                                    else c_q<=signed_number;
                                end else if(field_index==1) trial_q<=number_q[15:0];
                                else if(field_index==2) a_q<=signed_number;
                                else b_q<=signed_number;
                                number_q<=0; negative<=0; digit_seen<=0; sign_seen<=0;
                                if(field_index==field_count-1) state<=CRC_HIGH;
                                else begin field_index<=field_index+1'b1; crc_q<=crc8(crc_q,received_byte); end
                            end else begin state<=received_byte==10 ? IDLE : DISCARD; parse_error<=1; end
                        end
                        CRC_HIGH: if(!digit_hex[4]) begin received_crc[7:4]<=digit_hex[3:0]; state<=CRC_LOW; end
                                  else begin state<=received_byte==10 ? IDLE : DISCARD; parse_error<=1; end
                        CRC_LOW: if(!digit_hex[4]) begin received_crc[3:0]<=digit_hex[3:0]; state<=EOL; end
                                 else begin state<=received_byte==10 ? IDLE : DISCARD; parse_error<=1; end
                        EOL, AFTER_CR: begin
                            if(received_byte==13 && state==EOL) state<=AFTER_CR;
                            else if(received_byte==10) begin
                                state<=IDLE;
                                if(received_crc==crc_q) begin
                                    request_valid<=1; request_kind<=kind; request_session<=session_q;
                                    request_trial<=trial_q; request_a<=a_q; request_b<=b_q; request_c<=c_q;
                                end else parse_error<=1;
                            end else begin state<=DISCARD; parse_error<=1; end
                        end
                        INFO_EOL, INFO_CR: begin
                            if(received_byte==13 && state==INFO_EOL) state<=INFO_CR;
                            else if(received_byte==10) begin state<=IDLE; info_request<=1; end
                            else begin state<=DISCARD; parse_error<=1; end
                        end
                        default: begin state<=IDLE; parse_error<=1; end
                    endcase
                end
            end
        end
    end
endmodule
