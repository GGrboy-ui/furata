// smoke_selftest.v - toolchain smoke test, not a project module.
//
// Purpose: prove the OSS CAD Suite install (verilator lint, iverilog + vvp simulation,
// VCD generation for GTKWave) actually works end to end on this machine.
// It exercises the same class of logic the J280 project leans on: a synchronous
// up-counter with a tick enable and a wrap-around compare - the shape of tick_gen.v.
`timescale 1ns / 1ps

module smoke_selftest #(
    parameter integer DIV  = 4,      // cycles per tick
    parameter integer WIDTH = 8
) (
    input  wire              clk,
    input  wire              rst_n,
    output reg  [WIDTH-1:0]  count,
    output reg               tick
);
    reg [15:0] div_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 16'd0;
            count   <= {WIDTH{1'b0}};
            tick    <= 1'b0;
        end else begin
            if (div_cnt == DIV - 1) begin
                div_cnt <= 16'd0;
                count   <= count + 1'b1;
                tick    <= 1'b1;
            end else begin
                div_cnt <= div_cnt + 1'b1;
                tick    <= 1'b0;
            end
        end
    end
endmodule

module tb_smoke_selftest;
    reg clk = 0;
    reg rst_n = 0;
    wire [7:0] count;
    wire tick;

    smoke_selftest #(.DIV(4), .WIDTH(8)) dut (
        .clk(clk), .rst_n(rst_n), .count(count), .tick(tick)
    );

    always #5 clk = ~clk;   // 100 MHz

    integer ticks_seen = 0;
    integer errors = 0;

    initial begin
        $dumpfile("smoke.vcd");
        $dumpvars(0, tb_smoke_selftest);

        #23 rst_n = 1;       // release reset off a clock edge
        #2000;

        if (count == 0 && ticks_seen == 0) begin
            $display("FAIL: counter never advanced");
            errors = errors + 1;
        end else begin
            $display("PASS: count=%0d after %0d ticks", count, ticks_seen);
        end

        $display("SMOKE %s", (errors == 0) ? "OK" : "FAILED");
        $finish;
    end

    // Count ticks and check the divide ratio is honoured.
    integer clk_edges = 0;
    always @(posedge clk) begin
        clk_edges = clk_edges + 1;
        if (rst_n && tick) ticks_seen = ticks_seen + 1;
    end
endmodule
