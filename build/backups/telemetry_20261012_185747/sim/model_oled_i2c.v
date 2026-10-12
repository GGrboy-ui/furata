`timescale 1ns/1ps
// Behavioral ACK slave and bus recorder, shared by OLED tests.
module model_oled_i2c (
    inout wire scl, sda,
    input wire ack_enable, stretch,
    output reg active
);
    reg ack_low=0;
    integer bit_count=0, byte_count=0, start_count=0, stop_count=0;
    integer packet_length=0;
    reg [7:0] shift=0;
    reg [7:0] bytes [0:32767];
    integer packet_begin [0:511];
    integer packet_size [0:511];
    initial active=0;
    assign sda=ack_low?1'b0:1'bz;
    assign scl=stretch?1'b0:1'bz;
    always @(negedge sda) if (scl===1'b1) begin
        active=1; bit_count=0; packet_length=0;
        packet_begin[start_count]=byte_count; start_count=start_count+1;
    end
    always @(posedge sda) if (scl===1'b1 && active) begin
        active=0; packet_size[stop_count]=packet_length; stop_count=stop_count+1;
    end
    always @(posedge scl) if (active) begin
        if (bit_count<8) begin
            shift={shift[6:0],sda}; bit_count=bit_count+1;
            if (bit_count==8) begin
                bytes[byte_count]=shift; byte_count=byte_count+1;
                packet_length=packet_length+1;
            end
        end else begin
            if (sda !== (ack_enable ? 1'b0 : 1'b1)) $fatal(1,"FAIL: ACK bus level");
            bit_count=0;
        end
    end
    always @(negedge scl) begin
        if (active && bit_count==8 && ack_enable) ack_low=1;
        else ack_low=0;
    end
endmodule
