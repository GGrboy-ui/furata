// tb_tick_gen.v - self-checking testbench for tick_gen.
//
// Two instances are checked, both driven by the same clock:
//   u_real : CLK_HZ scaled to 1/1000 of the board (50 kHz standing in for 50 MHz).
//            The divider ratios are identical to the real configuration, so counting
//            ticks over 50000 clocks verifies the actual 1 kHz / 5 kHz / 10 Hz design.
//   u_fast : small dividers, used to check pulse shape and the alignment rule that
//            tick_ctrl and tick_log are asserted on a tick_speed cycle.
//
// All counting samples on the falling edge, one half-cycle after the DUT updates, so
// there is no race between the DUT's non-blocking updates and the testbench's counters.
`timescale 1ns / 1ps

module tb_tick_gen;
    // 50 MHz / 1000 = 50 kHz, same ratios as the board
    localparam integer REAL_CLK   = 50_000;
    localparam integer REAL_CTRL  = 1000;
    localparam integer REAL_SPEED = 5000;
    localparam integer REAL_LOG   = 10;
    localparam integer REAL_RUN   = 50_000;   // clocks to observe

    // 1 kHz / 50 / 200 / 5 -> dividers 5, 4, 10
    localparam integer FAST_RUN   = 1000;

    reg clk    = 1'b0;
    reg rst_r  = 1'b0;
    reg rst_f  = 1'b0;

    wire real_tick_speed, real_tick_ctrl, real_tick_log;
    wire fast_tick_speed, fast_tick_ctrl, fast_tick_log;

    tick_gen #(
        .CLK_HZ(REAL_CLK), .CTRL_HZ(REAL_CTRL), .SPEED_HZ(REAL_SPEED), .LOG_HZ(REAL_LOG)
    ) u_real (
        .clk(clk), .rst_n(rst_r),
        .tick_speed(real_tick_speed), .tick_ctrl(real_tick_ctrl), .tick_log(real_tick_log)
    );

    tick_gen #(
        .CLK_HZ(1000), .CTRL_HZ(50), .SPEED_HZ(200), .LOG_HZ(5)
    ) u_fast (
        .clk(clk), .rst_n(rst_f),
        .tick_speed(fast_tick_speed), .tick_ctrl(fast_tick_ctrl), .tick_log(fast_tick_log)
    );

    always #5 clk = ~clk;

    integer errors = 0;

    task fail;
        input [8*48-1:0] msg;
        begin
            $display("FAIL: %0s (t=%0t)", msg, $time);
            errors = errors + 1;
        end
    endtask

    // ---- real-ratio counters -------------------------------------------------------
    reg running_real = 1'b0;
    reg running_fast = 1'b0;

    integer n_speed = 0, n_ctrl = 0, n_log = 0;
    integer n_ctrl_wo_speed = 0, n_log_wo_ctrl = 0;
    reg     prev_speed = 1'b0;
    integer n_speed_back_to_back = 0;

    integer f_speed = 0, f_ctrl = 0, f_log = 0;
    integer f_ctrl_wo_speed = 0, f_log_wo_ctrl = 0;
    reg     f_prev_speed = 1'b0;
    integer f_speed_back_to_back = 0;

    integer i;

    always @(negedge clk) begin
        if (running_real) begin
            if (real_tick_speed) n_speed = n_speed + 1;
            if (real_tick_ctrl)  n_ctrl  = n_ctrl  + 1;
            if (real_tick_log)   n_log   = n_log   + 1;
            if (real_tick_ctrl && !real_tick_speed) n_ctrl_wo_speed = n_ctrl_wo_speed + 1;
            if (real_tick_log  && !real_tick_ctrl)  n_log_wo_ctrl  = n_log_wo_ctrl  + 1;
            if (real_tick_speed && prev_speed) n_speed_back_to_back = n_speed_back_to_back + 1;
            prev_speed = real_tick_speed;
        end

        if (running_fast) begin
            if (fast_tick_speed) f_speed = f_speed + 1;
            if (fast_tick_ctrl)  f_ctrl  = f_ctrl  + 1;
            if (fast_tick_log)   f_log   = f_log   + 1;
            if (fast_tick_ctrl && !fast_tick_speed) f_ctrl_wo_speed = f_ctrl_wo_speed + 1;
            if (fast_tick_log  && !fast_tick_ctrl)  f_log_wo_ctrl  = f_log_wo_ctrl  + 1;
            if (fast_tick_speed && f_prev_speed) f_speed_back_to_back = f_speed_back_to_back + 1;
            f_prev_speed = fast_tick_speed;
        end
    end

    initial begin
        $dumpfile("tb_tick_gen.vcd");
        // Only the fast instance is dumped: same ratios as the board but readable in a
        // waveform viewer. u_real's rates are verified numerically below.
        $dumpvars(0, tb_tick_gen.u_fast);

        // no ticks may escape while reset is asserted
        for (i = 0; i < 20; i = i + 1) @(negedge clk);
        if (real_tick_speed || real_tick_ctrl || real_tick_log)
            fail("tick asserted during reset");

        // ---- 1. real ratios over REAL_RUN clocks ----------------------------------
        rst_r = 1'b1;
        running_real = 1'b1;
        for (i = 0; i < REAL_RUN; i = i + 1) @(negedge clk);
        running_real = 1'b0;

        $display("INFO: real  over %0d clocks: speed=%0d ctrl=%0d log=%0d",
                 REAL_RUN, n_speed, n_ctrl, n_log);

        if (n_speed !== REAL_RUN / (REAL_CLK / REAL_SPEED))
            fail("real tick_speed rate wrong");
        if (n_ctrl !== REAL_RUN / (REAL_CLK / REAL_SPEED) / (REAL_SPEED / REAL_CTRL))
            fail("real tick_ctrl rate wrong");
        if (n_log !== REAL_RUN / (REAL_CLK / REAL_SPEED) / (REAL_SPEED / REAL_CTRL) / (REAL_CTRL / REAL_LOG))
            fail("real tick_log rate wrong");
        if (n_ctrl_wo_speed != 0) fail("real ctrl tick not aligned to a speed tick");
        if (n_log_wo_ctrl != 0)   fail("real log tick not aligned to a ctrl tick");
        if (n_speed_back_to_back != 0) fail("real speed tick wider than one clock");

        // ---- 2. small dividers: same checks, short run ----------------------------
        rst_f = 1'b1;
        running_fast = 1'b1;
        for (i = 0; i < FAST_RUN; i = i + 1) @(negedge clk);
        running_fast = 1'b0;

        $display("INFO: fast  over %0d clocks: speed=%0d ctrl=%0d log=%0d",
                 FAST_RUN, f_speed, f_ctrl, f_log);

        if (f_speed !== 200) fail("fast tick_speed rate wrong");
        if (f_ctrl  !== 50)  fail("fast tick_ctrl rate wrong");
        if (f_log   !== 5)   fail("fast tick_log rate wrong");
        if (f_ctrl_wo_speed != 0) fail("fast ctrl tick not aligned to a speed tick");
        if (f_log_wo_ctrl != 0)   fail("fast log tick not aligned to a ctrl tick");
        if (f_speed_back_to_back != 0) fail("fast speed tick wider than one clock");

        // ---- 3. reset clears the dividers -----------------------------------------
        rst_f = 1'b0;
        for (i = 0; i < 10; i = i + 1) @(negedge clk);
        if (fast_tick_speed || fast_tick_ctrl || fast_tick_log)
            fail("tick asserted after reset re-asserted");

        if (errors == 0) $display("TEST PASSED: tb_tick_gen");
        else             $display("TEST FAILED: tb_tick_gen (%0d error(s))", errors);

        $finish;
    end
endmodule
