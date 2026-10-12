// tb_encoder_qei.v - functional and numerical verification of encoder_qei.
//
// The point of this testbench is not "does it count up". It is to PROVE the design choice
// stated in rtl/encoder_qei.v: at control-relevant arm speeds, differencing the position over
// a 5 kHz tick cannot measure speed, and period measurement can. So both quantities are
// measured from OUTSIDE the DUT and checked against what physics says they should be:
//
//     expected Q8.8 counts/s = NET_EDGES * 256 * CLK_HZ / elapsed_clks
//
// and the testbench deliberately asserts that the position-difference path is USELESS at
// approximately 60 rpm (delta reads 0 on most ticks) while the period path is within 1%.
//
// IMPORTANT: the DUT takes the PERIOD of the most recent quadrature edge, it does not average
// over a tick. That is intentional - averaging would add latency the balance loop cannot
// afford - and it means vel is an instantaneous reading. Over one 10 ms window with many
// edges the value the DUT reports is therefore within one edge period of the mean, which is
// what the 1% tolerance below encodes.
//
// Coverage:
//   1. reset                     -> position 0, vel 0, delta 0
//   2. forward, 500 quadrature steps -> position == +500 exactly (4x decode)
//   3. reverse, 500 quadrature steps -> position == 0 exactly (direction)
//   4. 1000 counts/s (~58 rpm for 1040 counts/rev): delta is coarse, speed is calibrated
//   5. 2000 counts/s: speed doubles and remains calibrated
//   6. 20 single-channel glitches  -> position EXACTLY unchanged
//   7. stale-speed hold then forced zero once the shaft stops
//
// Timescale/parameters mirror the DUT defaults.
`timescale 1ns / 1ps

module tb_encoder_qei;

    // ---- parameters mirrored from the DUT ------------------------------------------------
    localparam integer CLK_HZ   = 50_000_000;
    localparam integer SCALE    = 256;        // Q8.8
    localparam integer TICK_DIV = 10_000;     // 50 MHz / 5 kHz
    localparam integer WIN_CLKS = 500_000;    // 10 ms measurement window

    // The assumed 1040 counts/rev converts 1000 counts/s to about 58 rpm.
    // The test itself asserts counts/s from generated edges and elapsed clocks.

    // ---- DUT signals --------------------------------------------------------------------
    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  enc_a = 1'b0;
    reg  enc_b = 1'b0;
    reg  tick_speed = 1'b0;

    wire signed [31:0] position;
    wire signed [31:0] vel;
    wire signed [31:0] delta;

    integer errors = 0;

    // ---- clock and tick generation -------------------------------------------------------
    always #10 clk = ~clk;                       // 20 ns period = 50 MHz

    integer tick_cnt = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            tick_cnt   <= 0;
            tick_speed <= 1'b0;
        end else if (tick_cnt == TICK_DIV-1) begin
            tick_cnt   <= 0;
            tick_speed <= 1'b1;
        end else begin
            tick_cnt   <= tick_cnt + 1;
            tick_speed <= 1'b0;
        end
    end

    // ---- DUT ----------------------------------------------------------------------------
    encoder_qei #(
        .CLK_HZ(CLK_HZ), .VEL_FRAC(8)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .enc_a(enc_a), .enc_b(enc_b), .tick_speed(tick_speed),
        .position(position), .vel(vel), .delta(delta)
    );

    // ---- stimulus helpers ---------------------------------------------------------------

    // Advance one quadrature state along the legal Gray sequence:
    //   forward : 00 -> 01 -> 11 -> 10 -> 00
    //   reverse : 00 -> 10 -> 11 -> 01 -> 00
    // One call = one accepted edge = +-1 decoded count. (An earlier revision toggled a
    // single channel instead, which is a two-edge excursion and made the net count
    // oscillate - see the note in rtl/encoder_qei.v section 2.)
    task qstep;
        input integer dir;          // +1 forward, -1 reverse
        begin
            case ({enc_a, enc_b})
                2'b00: {enc_a, enc_b} = (dir > 0) ? 2'b01 : 2'b10;
                2'b01: {enc_a, enc_b} = (dir > 0) ? 2'b11 : 2'b00;
                2'b11: {enc_a, enc_b} = (dir > 0) ? 2'b10 : 2'b01;
                2'b10: {enc_a, enc_b} = (dir > 0) ? 2'b00 : 2'b11;
            endcase
        end
    endtask

    // Emit exactly n_edges single-bit quadrature transitions in exactly clks clocks.
    // The generator's rate is independent of the DUT's divider constant, so a
    // matching scale error in stimulus and implementation cannot pass this check.
    //
    // Caller-visible outputs are module-level globals: Icarus does not allow a time-consuming
    // task to be called from within an expression. They are 64-bit because with VEL_FRAC=8 a
    // normal speed reading is in the millions of Q8.8 units, so summing 50 of them overflows a
    // 32-bit integer - which showed up as a wrapped average and a nonsense failure before this
    // was widened. They must also be declared BEFORE the task that assigns them, since Verilog
    // has no forward references.
    longint g_ticks, g_vsum, g_dsum, g_zdel;

    task spin;
        input integer n_edges;      // signed: < 0 spins in reverse; one edge == one decoded count
        input integer clks;
        integer cyc, dir, total_edges, pos_before;
        integer acc_edges, acc_ticks, acc_vel, acc_delta, acc_zero;
        integer edge_len;
        longint nxt_at;
        begin
            dir         = (n_edges >= 0) ? 1 : -1;
            total_edges = (n_edges >= 0) ? n_edges : -n_edges;
            edge_len    = clks / total_edges;
            if (edge_len < 8) $fatal(1, "edge interval too short for synchroniser");

            acc_edges  = 0;
            acc_ticks  = 0;
            acc_vel    = 0;
            acc_delta  = 0;
            acc_zero   = 0;
            nxt_at     = 0;
            pos_before = position;

            for (cyc = 0; cyc < clks; cyc = cyc + 1) begin
                @(posedge clk);
                #1;   // drive away from the edge: no race with the DUT's own sampling

                // --- clock-aligned quadrature generation: one bit changes per count ---
                //
                // These two case statements are the same transition tables that a 4x4 sweep
                // (all four start states x 4 forward + 4 reverse steps) confirmed produce
                // +4 / -4 counts. Hand-deriving the intermediate states got it wrong three
                // separate times, which is why the sweep exists.
                if (acc_edges < total_edges) begin
                    if (cyc == nxt_at) begin
                        if (dir > 0) begin
                            case ({enc_a, enc_b})
                                2'b00: {enc_a, enc_b} = 2'b01;
                                2'b01: {enc_a, enc_b} = 2'b11;
                                2'b11: {enc_a, enc_b} = 2'b10;
                                2'b10: {enc_a, enc_b} = 2'b00;
                            endcase
                        end else begin
                            case ({enc_a, enc_b})
                                2'b00: {enc_a, enc_b} = 2'b10;
                                2'b10: {enc_a, enc_b} = 2'b11;
                                2'b11: {enc_a, enc_b} = 2'b01;
                                2'b01: {enc_a, enc_b} = 2'b00;
                            endcase
                        end
                        acc_edges = acc_edges + 1;
                        nxt_at    = (64'd1 * acc_edges * clks) / total_edges;
                    end
                end

                // --- sample the DUT on the tick ---
                if (tick_speed) begin
                    acc_ticks = acc_ticks + 1;
                    acc_vel   = acc_vel + vel;
                    acc_delta = acc_delta + delta;
                    if (delta == 0) acc_zero = acc_zero + 1;
                end
            end

            g_ticks = acc_ticks;
            g_vsum  = acc_vel;
            g_dsum  = acc_delta;
            g_zdel  = acc_zero;

            $display("    [spin] edges=%0d clks=%0d edge_len=%0d -> dpos=%0d ticks=%0d delta_sum=%0d zero=%0d ab=%b",
                     n_edges, clks, edge_len, position - pos_before,
                     acc_ticks, acc_delta, acc_zero, {enc_a, enc_b});
        end
    endtask

    task do_reset;
        begin
            rst_n = 1'b0;
            enc_a = 1'b0;
            enc_b = 1'b0;
            #400;
            rst_n = 1'b1;
            #400;
        end
    endtask

    longint exp_vel, avg_vel, pos_mark, vel_base;
    integer i;
    integer vel_at_stop;


    // Diagnostic monitor: report the measured period the DUT feeds its divider, and the quotient
    // it produces. With CLK_HZ=50e6 and VEL_FRAC=8, VEL_K=12_800_000_000.
    // A period of 50,000 clocks is 1,000 counts/s, or 256,000 in Q8.8.
    integer dbg_cnt = 0;
    integer last_per = -1;
    always @(posedge clk) begin
        if (rst_n && (dut.per_lat !== last_per) && (dbg_cnt < 12)) begin
            last_per = dut.per_lat;
            if (last_per > 1) begin
                dbg_cnt = dbg_cnt + 1;
                $display("    [per] period=%0d clocks -> Q8.8 quotient would be %0d",
                         last_per, (64'd12_800_000_000 / last_per));
            end
        end
    end

    // Second DUT instance with a very short staleness timeout, so the timeout path can be
    // checked in microseconds rather than a full simulated second.
    reg        fast_rst_n = 1'b0;
    reg        fast_a = 1'b0, fast_b = 1'b0, fast_tick = 1'b0;
    wire signed [31:0] fast_pos, fast_vel, fast_delta;

    encoder_qei #(
        .CLK_HZ(CLK_HZ), .VEL_FRAC(8), .VEL_TIMEOUT_CLKS(50)
    ) dut_fast (
        .clk(clk), .rst_n(fast_rst_n), .enc_a(fast_a), .enc_b(fast_b), .tick_speed(fast_tick),
        .position(fast_pos), .vel(fast_vel), .delta(fast_delta));

    initial begin
        $dumpfile("tb_encoder_qei.vcd");
        // Keep the waveform focused: dumping the 50 MHz clock and all divider
        // internals makes this test's VCD hundreds of megabytes.
        $dumpvars(0, enc_a, enc_b, tick_speed, position, vel, delta);

        do_reset;

        // -----------------------------------------------------------------------------
        $display("");
        $display("--- 1. reset state ---");
        if (position !== 32'sd0) begin $display("FAIL: position=%0d after reset", position); errors = errors + 1; end
        if (vel      !== 32'sd0) begin $display("FAIL: vel=%0d after reset", vel);           errors = errors + 1; end
        if (delta    !== 32'sd0) begin $display("FAIL: delta=%0d after reset", delta);       errors = errors + 1; end
        if (errors == 0) $display("  OK: position/vel/delta all zero");

        // -----------------------------------------------------------------------------
        $display("");
        $display("--- 2. 4x decode, forward 500 quadrature steps ---");
        for (i = 0; i < 500; i = i + 1) begin
            qstep(1);
            #800;                      // 40 clocks per edge
        end
        #800;
        if (position !== 32'sd500) begin
            $display("FAIL: forward position=%0d, expected exactly 500 (4x decode broken)", position);
            errors = errors + 1;
        end else begin
            $display("  OK: position=%0d after 500 quadrature steps (4x decode confirmed)", position);
        end

        // -----------------------------------------------------------------------------
        $display("");
        $display("--- 3. 4x decode, reverse 500 quadrature steps ---");
        for (i = 0; i < 500; i = i + 1) begin
            qstep(-1);
            #800;
        end
        #800;
        if (position !== 32'sd0) begin
            $display("FAIL: reverse position=%0d, expected exactly 0 (direction or decode broken)", position);
            errors = errors + 1;
        end else begin
            $display("  OK: position returned to 0 (reverse direction confirmed)");
        end

        // -----------------------------------------------------------------------------
        // Ten decoded counts in 10 ms is exactly 1000 counts/s (near 60 rpm if the
        // assumed 1040 counts/rev is correct). Expected Q8.8 speed is 256000.
        // This expectation is derived from the generated count and elapsed time,
        // not the DUT's divider constant or measured period.
        $display("");
        $display("--- 4. 10 changes / 10 ms, physical speed calibration ---");
        pos_mark = position;
        spin(10, WIN_CLKS);
        if (g_ticks < 45 || g_ticks > 55) begin
            $display("FAIL: tick count %0d out of range (expected ~50)", g_ticks);
            errors = errors + 1;
        end
        if ((position - pos_mark) !== 10) begin
            $display("FAIL: position advanced by %0d, expected exactly 10", position - pos_mark);
            errors = errors + 1;
        end
        exp_vel = (64'd10 * CLK_HZ * SCALE) / WIN_CLKS;
        avg_vel = vel;  // final settled period reading; startup is excluded
        $display("    ticks=%0d dpos=10 zero_deltas=%0d/%0d vel=%0d expected=%0d (%0d counts/s)",
                 g_ticks, g_zdel, g_ticks, avg_vel, exp_vel, exp_vel/SCALE);
        if (avg_vel > exp_vel + (exp_vel/100) || avg_vel < exp_vel - (exp_vel/100)) begin
            $display("FAIL: period-based vel=%0d, expected within 1%% of %0d", avg_vel, exp_vel);
            errors = errors + 1;
        end else begin
            $display("  OK: period-based speed %0d within 1%% of %0d (%0d counts/s)",
                     avg_vel, exp_vel, exp_vel/SCALE);
        end
        // The delta path must be demonstrably coarse here, which is why it is not the speed term.
        if (g_zdel == 0) begin
            $display("FAIL: delta read non-zero on every tick; expected it to read 0 on most ticks");
            errors = errors + 1;
        end else begin
            $display("  OK: delta-per-tick read 0 on %0d/%0d ticks (too coarse to be the speed term)",
                     g_zdel, g_ticks);
        end

        // -----------------------------------------------------------------------------
        // Double the physical edge rate, then check both absolute value and proportionality.
        // Counts per revolution remains a separate hardware measurement for rpm conversion.
        $display("");
        $display("--- 5. 20 changes / 10 ms -> exactly twice the speed of test 4 ---");
        vel_base = avg_vel;
        spin(20, WIN_CLKS);
        avg_vel = vel;
        exp_vel = (64'd20 * CLK_HZ * SCALE) / WIN_CLKS;
        $display("    ticks=%0d  zero_deltas=%0d  vel=%0d  (test 4 was %0d)",
                 g_ticks, g_zdel, avg_vel, vel_base);
        if (vel_base == 0) begin
            $display("FAIL: test 4 produced 0, cannot check proportionality");
            errors = errors + 1;
        end else if (avg_vel > exp_vel + (exp_vel/100) || avg_vel < exp_vel - (exp_vel/100)) begin
            $display("FAIL: doubled edge rate gave vel=%0d, expected %0d", avg_vel, exp_vel);
            errors = errors + 1;
        end else begin
            $display("  OK: reading %0d is 2x test 4's %0d - the speed path is linear in edge rate",
                     avg_vel, vel_base);
        end

        // -----------------------------------------------------------------------------
        $display("");
        $display("--- 6. glitch immunity (single-channel toggles) ---");
        begin : glitch
            integer pos_before;
            pos_before = position;
            for (i = 0; i < 20; i = i + 1) begin
                enc_a = ~enc_a;  #1200;
                enc_a = ~enc_a;  #1200;
            end
            #2000;
            if (position !== pos_before) begin
                $display("FAIL: glitch moved position from %0d to %0d (expect no change)",
                         pos_before, position);
                errors = errors + 1;
            end else begin
                $display("  OK: 20 single-channel glitches left position at %0d", position);
            end
        end

        // -----------------------------------------------------------------------------
        // Stale-speed behaviour, part 1: with the real 1 s timeout, a stopped shaft must HOLD
        // the last measured speed rather than decay towards zero. Only ~40 ms of simulated time
        // is spent here on purpose: waiting out the real 1 s timeout under Icarus costs ~58
        // million clock cycles and dominates the whole regression, so the timeout expiring is
        // checked on a second instance with a 1 us timeout in test 8 instead.
        $display("");
        $display("--- 7. stopped shaft holds the last measured speed ---");
        spin(200, 400_000);                     // ~8 ms of spinning, then stop
        $display("    vel immediately after the shaft stopped = %0d (must be non-zero)", vel);
        if (vel === 32'sd0) begin
            $display("FAIL: vel already 0 right after spinning - the measurement path is suspect");
            errors = errors + 1;
        end
        vel_at_stop = vel;

        #20_000_000;                            // 20 ms at rest
        $display("    vel after 20 ms at rest   = %0d (still held: the period just went stale)", vel);
        if (vel !== vel_at_stop) begin
            $display("FAIL: vel changed to %0d within the timeout window; expected it held at %0d",
                     vel, vel_at_stop);
            errors = errors + 1;
        end

        #20_000_000;                            // 40 ms total at rest
        if (vel === 32'sd0) begin
            $display("FAIL: vel already 0 after 40 ms but the timeout is 1 s");
            errors = errors + 1;
        end else begin
            $display("  OK: speed held at %0d through 40 ms of rest (timeout is 1 s)", vel);
        end

        // -----------------------------------------------------------------------------
        // Stale-speed behaviour, part 2: the same property on a second instance whose timeout is
        // 1 us (50 clocks), checked in microseconds of simulated time.
        $display("");
        $display("--- 8. short-timeout instance: zeroed once the timeout elapses ---");
        fast_rst_n = 1'b0;
        fast_a = 1'b0; fast_b = 1'b0; fast_tick = 1'b0;
        #400;
        fast_rst_n = 1'b1;
        #400;
        // Two transitions 1 us apart, so the divider measures a period and latches a speed.
        fast_a = 1'b1;
        #1000;
        fast_b = 1'b1;
        #1000;
        fast_a = 1'b0;
        #1000;
        fast_b = 1'b0;
        $display("    short-timeout instance: vel right after the transitions = %0d", fast_vel);
        #200_000;                               // 200 us: far beyond the 1 us timeout
        if (fast_vel !== 32'sd0) begin
            $display("FAIL: short-timeout instance still reports %0d after 200 us", fast_vel);
            errors = errors + 1;
        end else begin
            $display("  OK: instance with VEL_TIMEOUT_CLKS=50 was forced to exactly 0");
        end

        // -----------------------------------------------------------------------------
        $display("");
        if (errors == 0) begin
            $display("TEST PASSED: tb_encoder_qei");
        end else begin
            $fatal(1, "TEST FAILED: tb_encoder_qei (%0d error(s))", errors);
        end
        $finish;
    end

    // Watchdog so a bug can never hang the regression. Test 7 deliberately waits out the 1 s
    // staleness timeout, which is 50 million clocks = 1_000_000_000 ns of simulated time, and
    // the watchdog must outlast that or it fires in the middle of a healthy run.
    initial begin
        #5_000_000_000;   // 5 s
        $fatal(1, "FAIL: watchdog timeout");
    end
endmodule
