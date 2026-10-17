`timescale 1ns/1ps
// Single-byte I2C writer. first/last delimit a multi-byte transaction.
// Both pins are open drain. ACK, clock stretching and bounded bus timeout
// are handled here; a missing display never stalls the control datapath.
module oled_i2c_writer #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer I2C_HZ=100_000,
    parameter integer TIMEOUT_MS=10
) (
    input wire clk, rst_n, start,
    input wire [7:0] data,
    input wire first_byte, last_byte,
    inout wire scl, sda,
    output reg busy, done, error
);
    localparam integer DIV_RAW=(CLK_HZ+4*I2C_HZ-1)/(4*I2C_HZ);
    localparam integer DIV=(DIV_RAW<1)?1:DIV_RAW;
    localparam integer TIMEOUT_RAW=(CLK_HZ/1000)*TIMEOUT_MS;
    localparam integer TIMEOUT=(TIMEOUT_RAW<1)?1:TIMEOUT_RAW;
    localparam [4:0] IDLE=0, START_WAIT=1, START_HOLD=2,
        BIT_SET=3, BIT_RISE=4, BIT_HIGH=5, BIT_FALL=6,
        ACK_SET=7, ACK_RISE=8, ACK_HIGH=9, ACK_FALL=10,
        STOP_SET=11, STOP_RISE=12, STOP_HIGH=13, STOP_RELEASE=14,
        FINISH=15, START_FALL=16, STOP_HOLD=17, START_READY=18,
        START_ASSERT=19, BIT_HOLD=20, ACK_HOLD=21;
    reg [4:0] state;
    reg scl_low, sda_low;
    reg [1:0] scl_sync, sda_sync;
    reg [31:0] divider, age;
    reg [7:0] shift;
    reg [2:0] bit_index;
    reg stop_after;
    assign scl=scl_low ? 1'b0 : 1'bz;
    assign sda=sda_low ? 1'b0 : 1'bz;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin scl_sync<=2'b11; sda_sync<=2'b11; end
        else begin scl_sync<={scl_sync[0],scl}; sda_sync<={sda_sync[0],sda}; end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; scl_low<=0; sda_low<=0; divider<=0; age<=0;
            shift<=0; bit_index<=0; stop_after<=0; busy<=0; done<=0; error<=0;
        end else begin
            done<=0;
            if (state==IDLE) begin
                divider<=0; age<=0;
                if (start) begin
                    shift<=data; bit_index<=7; stop_after<=last_byte;
                    error<=0; busy<=1;
                    if (first_byte) begin scl_low<=0; sda_low<=0; state<=START_WAIT; end
                    else state<=BIT_SET;
                end
            end else if (state==FINISH) begin
                busy<=0; done<=1; state<=IDLE;
            end else if (age>=TIMEOUT-1) begin
                // Also releases a permanently held-low bus without waiting for SCL.
                scl_low<=0; sda_low<=0; error<=1; state<=FINISH;
            end else begin
                age<=age+1;
                if (divider==DIV-1) begin
                    divider<=0;
                    case (state)
                        // Two quarter periods for Standard-mode START/STOP setup
                        // and hold; clock stretching also gets a full high period.
                        START_WAIT: if (scl_sync[1] && sda_sync[1]) state<=START_READY;
                        START_READY: if (scl_sync[1] && sda_sync[1]) state<=START_ASSERT;
                                     else state<=START_WAIT;
                        START_ASSERT: if (scl_sync[1] && sda_sync[1]) begin
                            sda_low<=1; state<=START_HOLD;
                        end else state<=START_WAIT;
                        START_HOLD: state<=START_FALL;
                        START_FALL: begin scl_low<=1; state<=BIT_SET; end
                        BIT_SET: begin sda_low<=!shift[bit_index]; state<=BIT_RISE; end
                        BIT_RISE: begin scl_low<=0; state<=BIT_HIGH; end
                        BIT_HIGH: if (scl_sync[1]) state<=BIT_HOLD;
                        BIT_HOLD: state<=BIT_FALL;
                        BIT_FALL: begin
                            scl_low<=1;
                            if (bit_index==0) state<=ACK_SET;
                            else begin bit_index<=bit_index-3'd1; state<=BIT_SET; end
                        end
                        ACK_SET: begin sda_low<=0; state<=ACK_RISE; end
                        ACK_RISE: begin scl_low<=0; state<=ACK_HIGH; end
                        ACK_HIGH: if (scl_sync[1]) begin
                            error<=sda_sync[1]; state<=ACK_HOLD;
                        end
                        ACK_HOLD: state<=ACK_FALL;
                        ACK_FALL: begin
                            scl_low<=1;
                            if (error || stop_after) state<=STOP_SET;
                            else state<=FINISH;
                        end
                        STOP_SET: begin sda_low<=1; state<=STOP_RISE; end
                        STOP_RISE: begin scl_low<=0; state<=STOP_HIGH; end
                        STOP_HIGH: if (scl_sync[1]) state<=STOP_HOLD;
                        STOP_HOLD: begin sda_low<=0; state<=STOP_RELEASE; end
                        STOP_RELEASE: state<=FINISH;
                        default: state<=FINISH;
                    endcase
                end else divider<=divider+1;
            end
        end
    end
endmodule
