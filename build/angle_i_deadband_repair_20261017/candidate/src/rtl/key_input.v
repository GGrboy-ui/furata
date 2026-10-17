`timescale 1ns/1ps
// Four active-low adapter keys. Each stable press emits one clock pulse.
// A stable release is required after reset and between presses.
module key_input #(
    parameter integer DEBOUNCE_CYCLES=1_000_000
) (
    input wire clk, rst_n,
    input wire [3:0] key_n,
    output reg [3:0] press
);
    localparam integer N=(DEBOUNCE_CYCLES<1) ? 1 : DEBOUNCE_CYCLES;
    localparam integer W=(N<2) ? 1 : $clog2(N+1);
    reg [3:0] sync_meta, sync_keys;
    reg [1:0] sync_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sync_meta<=4'hf; sync_keys<=4'hf; sync_valid<=0; end
        else begin sync_meta<=key_n; sync_keys<=sync_meta; sync_valid<={sync_valid[0],1'b1}; end
    end
    genvar k;
    generate for(k=0;k<4;k=k+1) begin: filter
        reg candidate, armed;
        reg [W-1:0] count;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin candidate<=1; armed<=0; count<=0; press[k]<=0; end
            else begin
                press[k]<=0;
                if (!sync_valid[1]) count<=0;
                else if (sync_keys[k]!=candidate) begin candidate<=sync_keys[k]; count<=0; end
                else if (count<N) begin
                    if (count==N-1) begin
                        if (candidate) armed<=1;
                        else begin press[k]<=armed; armed<=0; end
                    end
                    count<=count+1'b1;
                end
            end
        end
    end endgenerate
endmodule
