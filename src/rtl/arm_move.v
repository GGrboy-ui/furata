`timescale 1ns/1ps
// ARM1: line-oriented relative moves. Status integers are fixed-width hexadecimal.
// Queries and movement replies share TX only at complete telemetry boundaries.
module arm_move #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer COUNTS_PER_REV=408,
    parameter integer MOVE_DEG_PER_SEC=30,
    parameter integer POSITION_LIMIT_COUNTS=4080,
    parameter integer CW_POSITIVE=1,
    parameter integer SETTLE_MS=200,
    parameter integer TOLERANCE_COUNTS=2
)(
    input wire clk,rst_n,tick_ms,enable,stop_cmd,
    input wire [2:0] control_state,
    input wire signed [31:0] position,target_q,goal_q,
    input wire [7:0] received_byte,
    input wire received_valid,
    output wire legacy_valid,
    output reg load,
    output reg signed [31:0] load_goal_q,load_origin_q,
    output wire busy,
    output wire [7:0] tx_data,
    output wire tx_valid,tx_pending,
    input wire tx_ready,telemetry_active,
    input wire motion_lock,
    output wire tx_active
);
    localparam [7:0] STATUS=0,ACCEPTED=1,DONE=2,CANCELLED=3,
        BUSY=8'h10,STATE=8'h11,RANGE=8'h12,FORMAT=8'h13,DUPLICATE=8'h14;
    reg [3:0] parse;
    reg [31:0] age;
    reg [5:0] line_length;
    reg [15:0] number_id;
    reg [16:0] angle;
    reg [2:0] id_digits,angle_digits;
    reg negative,cr_seen,query_cap;
    wire is_digit=received_byte>=8'h30 && received_byte<=8'h39;
    wire [3:0] digit=received_byte[3:0];
    assign legacy_valid=received_valid && ((parse==0 && received_byte!=8'h40) || received_byte==8'h58);

    reg moving;
    reg [1:0] calculate;
    reg [15:0] active_id,convert_id;
    reg have_id,convert_negative;
    reg [31:0] settled;
    reg divide_start;
    reg [63:0] numerator;
    wire divide_busy,divide_done;
    wire [63:0] quotient,remainder_unused;
    divider_seq #(.WIDTH(64)) conversion(.clk(clk),.rst_n(rst_n),.start(divide_start),
        .num(numerator),.den(64'd3600),.busy(divide_busy),.done(divide_done),.q(quotient),.r(remainder_unused));
    reg signed [63:0] delta_q;
    wire signed [63:0] actual_q=$signed(position)*64'sd65536;
    wire signed [63:0] candidate=actual_q+delta_q;
    wire signed [63:0] limit_q=POSITION_LIMIT_COUNTS*64'sd65536;
    wire signed [63:0] error_q=$signed(goal_q)-actual_q;
    assign busy=moving || calculate!=0;

    // Reports coalesce if a peer floods queries; @Q always recovers the latest
    // accepted move's result. A movement is never retried automatically.
    reg report_dirty,cap_dirty;
    reg [15:0] report_id,status_id;
    reg [7:0] report_code,status_code;
    task report;
        input [15:0] id;
        input [7:0] code;
        begin report_id<=id;report_code<=code;report_dirty<=1;end
    endtask
    function [7:0] hex_digit;
        input [3:0] n;
        begin hex_digit=n<10 ? 8'h30+{4'b0,n} : 8'h41+{4'b0,n}-8'd10;end
    endfunction
    function [15:0] hex2;
        input [7:0] n;
        begin hex2={hex_digit(n[7:4]),hex_digit(n[3:0])};end
    endfunction
    function [31:0] hex4;
        input [15:0] n;
        begin hex4={hex2(n[15:8]),hex2(n[7:0])};end
    endfunction
    function [63:0] hex8;
        input [31:0] n;
        begin hex8={hex4(n[31:16]),hex4(n[15:0])};end
    endfunction
    reg [271:0] tx_buffer;
    reg [5:0] tx_length,tx_index;
    reg sending,draining;
    assign tx_pending=sending || report_dirty || cap_dirty;
    assign tx_active=sending;
    assign tx_valid=sending && !draining && !telemetry_active;
    assign tx_data=tx_buffer[(tx_length-1-tx_index)*8+:8];

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            parse<=0;age<=0;line_length<=0;number_id<=0;angle<=0;
            id_digits<=0;angle_digits<=0;negative<=0;cr_seen<=0;query_cap<=0;
            moving<=0;calculate<=0;active_id<=0;convert_id<=0;have_id<=0;
            convert_negative<=0;settled<=0;divide_start<=0;numerator<=0;delta_q<=0;
            load<=0;load_goal_q<=0;load_origin_q<=0;
            report_dirty<=0;cap_dirty<=0;report_id<=0;report_code<=0;status_id<=0;status_code<=0;
            tx_buffer<=0;tx_length<=0;tx_index<=0;sending<=0;draining<=0;
        end else begin
            load<=0;divide_start<=0;
            // Build whole immutable replies before offering any byte to UART.
            if(!sending && !load && !telemetry_active) begin
                if(cap_dirty) begin
                    tx_buffer<={"@I,ARM1,",hex4(COUNTS_PER_REV),8'h2c,
                        hex4(MOVE_DEG_PER_SEC),8'h2c,hex4(POSITION_LIMIT_COUNTS),16'h0d0a};
                    tx_length<=24;tx_index<=0;sending<=1;draining<=0;cap_dirty<=0;
                end else if(report_dirty) begin
                    tx_buffer<={"@R,",hex4(report_id),8'h2c,hex2(report_code),8'h2c,
                        hex_digit({1'b0,control_state}),8'h2c,(busy ? 8'h31:8'h30),8'h2c,
                        hex8(position),8'h2c,hex8(goal_q),16'h0d0a};
                    tx_length<=34;tx_index<=0;sending<=1;draining<=0;report_dirty<=0;
                end
            end else if(!telemetry_active && tx_ready) begin
                if(draining) begin sending<=0;draining<=0;end
                else if(tx_index==tx_length-1) draining<=1;
                else tx_index<=tx_index+1'b1;
            end

            if(parse!=0) begin
                if(age>=CLK_HZ/5) begin parse<=0;report(number_id,FORMAT);end
                else age<=age+1'b1;
            end
            if(received_valid) begin
                if(received_byte==8'h40) begin
                    parse<=1;age<=0;line_length<=0;number_id<=0;angle<=0;
                    id_digits<=0;angle_digits<=0;negative<=0;cr_seen<=0;
                end else if(parse!=0) begin
                    line_length<=line_length+1'b1;
                    if(received_byte==8'h0a) begin
                        parse<=0;
                        if(parse==6) begin
                            if(query_cap) cap_dirty<=1;
                            else report(status_id,status_code);
                        end else if(parse==5 && angle_digits!=0) begin
                            if(busy || divide_busy || motion_lock===1'b1) report(number_id,BUSY);
                            else if(!enable) report(number_id,STATE);
                            else if(have_id && active_id==number_id) report(number_id,DUPLICATE);
                            else if(angle==0) begin
                                active_id<=number_id;have_id<=1;status_id<=number_id;status_code<=DONE;
                                report(number_id,DONE);
                            end else begin
                                convert_id<=number_id;convert_negative<=negative ^ (CW_POSITIVE==0);
                                // Half-denominator rounds magnitudes symmetrically to Q16.16.
                                numerator<=angle*64'd65536*COUNTS_PER_REV+64'd1800;
                                divide_start<=1;calculate<=1;
                            end
                        end else report(number_id,FORMAT);
                    end else if(line_length>=31 || (cr_seen && received_byte!=8'h58)) parse<=7;
                    else if(received_byte==8'h0d) begin
                        if(parse==6 || (parse==5 && angle_digits!=0)) cr_seen<=1;
                        else parse<=7;
                    end else case(parse)
                        1: if(received_byte==8'h4d) parse<=2;
                           else if(received_byte==8'h49 || received_byte==8'h51) begin
                               query_cap<=received_byte==8'h49;parse<=6;
                           end else parse<=7;
                        2: if(received_byte==8'h2c) parse<=3;else parse<=7;
                        3: if(is_digit && id_digits<5 && number_id*32'd10+digit<=65535) begin
                               number_id<=number_id*16'd10+digit;id_digits<=id_digits+1'b1;
                           end else if(received_byte==8'h2c && id_digits!=0 && number_id!=0) parse<=4;
                           else parse<=7;
                        4: if(received_byte==8'h2b || received_byte==8'h2d) begin
                               negative<=received_byte==8'h2d;parse<=5;
                           end else parse<=7;
                        5: if(is_digit && angle_digits<5 && angle*32'd10+digit<=36000) begin
                               angle<=angle*17'd10+digit;angle_digits<=angle_digits+1'b1;
                           end else parse<=7;
                        default: parse<=7;
                    endcase
                end
            end

            if(calculate==1 && divide_done) begin
                delta_q<=convert_negative ? -$signed(quotient) : $signed(quotient);
                calculate<=2;
            end else if(calculate==2) begin
                calculate<=0;
                if(!enable) report(convert_id,STATE);
                else if(motion_lock===1'b1) report(convert_id,BUSY);
                else if(candidate>limit_q || candidate< -limit_q) report(convert_id,RANGE);
                else begin
                    load_goal_q<=candidate[31:0];load_origin_q<=actual_q[31:0];load<=1;
                    moving<=1;settled<=0;active_id<=convert_id;have_id<=1;
                    status_id<=convert_id;status_code<=ACCEPTED;report(convert_id,ACCEPTED);
                end
            end
            if(moving && tick_ms && !load) begin
                if(target_q==goal_q && error_q<=TOLERANCE_COUNTS*64'sd65536 &&
                   error_q>=-TOLERANCE_COUNTS*64'sd65536) begin
                    if(settled>=SETTLE_MS-1) begin
                        moving<=0;settled<=0;status_code<=DONE;report(active_id,DONE);
                    end else settled<=settled+1'b1;
                end else settled<=0;
            end
            // Stop/fault wins over all parsing, conversion and arrival events.
            if(!enable || stop_cmd) begin
                if(moving || calculate!=0) begin
                    report(calculate!=0 ? convert_id:active_id,CANCELLED);
                    status_id<=calculate!=0 ? convert_id:active_id;status_code<=CANCELLED;
                end
                moving<=0;calculate<=0;settled<=0;load<=0;
            end
            if(stop_cmd) begin parse<=0;age<=0;end
        end
    end
endmodule
