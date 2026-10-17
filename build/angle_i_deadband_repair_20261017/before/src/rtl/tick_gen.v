// tick_gen.v - one-cycle enable pulses for the control, speed-estimation and log rates.
//
// Rates are derived from the clock by integer division, and the hierarchy is nested on
// purpose: tick_log is a multiple of tick_ctrl, and tick_ctrl is a multiple of tick_speed.
// tick_ctrl and tick_log are asserted on the SAME cycle as a tick_speed pulse, so the
// controller always samples a speed estimate that was updated in the very cycle it runs.
// Deriving the three rates independently would let them drift against each other and the
// controller would sometimes consume a one-cycle-stale velocity.
//
// Defaults for the J280 board: clk_sys = 50 MHz straight from pin M19.
//   1 kHz control loop, 5 kHz speed/sensor update, 10 Hz logging.
// The divider constants require CTRL_HZ to divide SPEED_HZ, and LOG_HZ to divide CTRL_HZ,
// so that the integer divides come out exact. The testbench checks the resulting rates.
//
// The counters and their terminal counts are all 32-bit on purpose. Sizing each counter to
// its own divider would force an explicit narrowing of the terminal constant, and this
// project's rule is that no width change happens silently; three 32-bit counters cost
// roughly a hundred flops out of 41040, which is the cheaper trade.
`timescale 1ns / 1ps

module tick_gen #(
    parameter integer CLK_HZ   = 50_000_000,
    parameter integer CTRL_HZ  = 1000,
    parameter integer SPEED_HZ = 5000,
    parameter integer LOG_HZ   = 10
) (
    input  wire clk,
    input  wire rst_n,
    output reg  tick_speed,   // sensor / velocity update
    output reg  tick_ctrl,    // controller single-shot computation
    output reg  tick_log      // UART / display refresh
);
    localparam integer SPEED_DIV = CLK_HZ / SPEED_HZ;
    localparam integer CTRL_DIV  = SPEED_HZ / CTRL_HZ;
    localparam integer LOG_DIV   = CTRL_HZ / LOG_HZ;

    localparam integer SPEED_TOP = SPEED_DIV - 1;
    localparam integer CTRL_TOP  = CTRL_DIV - 1;
    localparam integer LOG_TOP   = LOG_DIV - 1;

    reg [31:0] speed_cnt;
    reg [31:0] ctrl_cnt;
    reg [31:0] log_cnt;

    wire speed_end = (speed_cnt == SPEED_TOP);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            speed_cnt  <= 32'd0;
            ctrl_cnt   <= 32'd0;
            log_cnt    <= 32'd0;
            tick_speed <= 1'b0;
            tick_ctrl  <= 1'b0;
            tick_log   <= 1'b0;
        end else begin
            speed_cnt  <= speed_end ? 32'd0 : (speed_cnt + 32'd1);
            tick_speed <= speed_end;

            if (speed_end) begin
                if (ctrl_cnt == CTRL_TOP) begin
                    ctrl_cnt  <= 32'd0;
                    tick_ctrl <= 1'b1;
                    if (log_cnt == LOG_TOP) begin
                        log_cnt  <= 32'd0;
                        tick_log <= 1'b1;
                    end else begin
                        log_cnt  <= log_cnt + 32'd1;
                        tick_log <= 1'b0;
                    end
                end else begin
                    ctrl_cnt  <= ctrl_cnt + 32'd1;
                    tick_ctrl <= 1'b0;
                    tick_log  <= 1'b0;
                end
            end else begin
                tick_ctrl <= 1'b0;
                tick_log  <= 1'b0;
            end
        end
    end
endmodule
