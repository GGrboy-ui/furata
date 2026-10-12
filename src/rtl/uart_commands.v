`timescale 1ns/1ps
// Full-duplex command channel, 115200 8N1. Bad stop bits are rejected.
// Optional telemetry bytes share TX; echoes are suppressed during whole frames.
module uart_commands #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer BAUD=115200,
    parameter integer TELEMETRY=0
) (
    input wire clk, rst_n, rx,
    output wire tx,
    output reg start_cmd, stop_cmd, clear_cmd,
    output reg [7:0] received_byte,
    output reg received_valid,
    input wire [7:0] tx_data,
    input wire tx_valid, tx_frame_active,
    output wire tx_ready
);
    localparam integer DIV=CLK_HZ/BAUD;
    reg [1:0] sync;
    reg [1:0] state;
    reg [31:0] count, tx_count;
    reg [2:0] bit_no;
    reg [7:0] byte_q;
    reg [9:0] tx_shift;
    reg [3:0] tx_left;
    assign tx=(tx_left==0) ? 1'b1 : tx_shift[0];
    assign tx_ready=(tx_left==0);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync<=2'b11; state<=0; count<=0; bit_no<=3'd0; byte_q<=0;
            start_cmd<=0; stop_cmd<=0; clear_cmd<=0;
            received_byte<=0; received_valid<=0;
            tx_count<=0; tx_shift<=10'h3ff; tx_left<=0;
        end else begin
            sync<={sync[0],rx}; start_cmd<=0; stop_cmd<=0; clear_cmd<=0;
            received_valid<=0;
            if (tx_left!=0) begin
                if (tx_count!=0) tx_count<=tx_count-1;
                else begin tx_count<=DIV-1; tx_shift<={1'b1,tx_shift[9:1]}; tx_left<=tx_left-4'd1; end
            end
            if (TELEMETRY!=0 && tx_valid && tx_ready) begin
                tx_shift<={1'b1,tx_data,1'b0}; tx_left<=4'd10; tx_count<=DIV-1;
            end
            case(state)
                0: if (!sync[1]) begin count<=DIV/2-1; state<=1; end
                1: if (count!=0) count<=count-1;
                   else if (sync[1]) state<=0;
                   else begin count<=DIV-1; bit_no<=0; state<=2; end
                2: if (count!=0) count<=count-1;
                   else begin
                       byte_q[bit_no]<=sync[1]; count<=DIV-1;
                       if (bit_no==3'd7) state<=3; else bit_no<=bit_no+3'd1;
                   end
                3: if (count!=0) count<=count-1;
                   else begin
                       state<=0;
                       if (sync[1]) begin
                           received_byte<=byte_q; received_valid<=1;
                           start_cmd<=(byte_q==8'h53);
                           stop_cmd<=(byte_q==8'h58);
                           clear_cmd<=(byte_q==8'h43);
                           if (tx_left==0 && (TELEMETRY==0 || (!tx_frame_active && !tx_valid))) begin
                               tx_shift<={1'b1,byte_q,1'b0}; tx_left<=4'd10; tx_count<=DIV-1;
                           end
                       end
                   end
                default: state<=0;
            endcase
        end
    end
endmodule
