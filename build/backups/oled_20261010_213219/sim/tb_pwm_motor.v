// tb_pwm_motor.v - self-checking testbench for pwm_motor.
//
// Small parameters keep the run short and the numbers readable: PWM_MAX = 20, so one PWM
// period is 20 clocks and 1 duty count is 5%. SLEW_STEP = 2, DEAD_CYCLES = 2.
//
// The checks are the safety properties the rest of the project leans on:
//   * reset / brake / enable-low produce the safe pin pattern in the SAME time step,
//   * duty never steps by more than SLEW_STEP per PWM period,
//   * a direction reversal always passes through zero duty and waits DEAD_CYCLES before
//     the direction pins swap (so the TB6612 never sees a back-EMF-reversing step),
//   * out-of-range commands saturate instead of wrapping.
//
// Duty is measured by counting how many clocks pwm is high inside one PWM period. Period
// alignment uses the DUT's own pwm_cnt through a hierarchical reference; that is why the
// lint step in sim\run_oss.ps1 covers rtl\ only.
`timescale 1ns / 1ps

module tb_pwm_motor;
    localparam integer PMAX = 20;
    localparam integer SLEW = 2;
    localparam integer DEAD = 2;

    reg  clk    = 1'b0;
    reg  rst_n  = 1'b0;
    reg  enable = 1'b0;
    reg  brake  = 1'b0;
    reg  signed [15:0] cmd = 16'sd0;

    wire pwm, in1, in2;

    pwm_motor #(
        .PWM_MAX(PMAX), .SLEW_STEP(SLEW), .DEAD_CYCLES(DEAD), .BRAKE_ON_INHIBIT(1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .enable(enable), .brake(brake), .cmd(cmd),
        .pwm(pwm), .in1(in1), .in2(in2)
    );

    always #5 clk = ~clk;

    integer errors = 0;

    task fail;
        input [8*64-1:0] msg;   // wide enough that no message silently loses its first char
        begin
            $display("FAIL: %0s (t=%0t)", msg, $time);
            errors = errors + 1;
        end
    endtask

    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    task wait_periods;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk); #1;
                while (dut.pwm_cnt != 16'd0) begin @(posedge clk); #1; end
            end
        end
    endtask

    // Measure the duty and direction of exactly one PWM period, starting at a period start.
    // No leading edge advance: when the previous call finished we are already 1ns into a
    // period boundary, and stepping first would skip a whole period (that made the duty
    // sequence read 8,4,0 instead of 8,6,4,2,0 and looked like a slew violation).
    task measure_period;
        output integer d;
        output dir;
        integer k;
        begin
            while (dut.pwm_cnt != 16'd0) begin @(posedge clk); #1; end
            d   = 0;
            dir = dut.dir_q;
            for (k = 0; k < PMAX; k = k + 1) begin
                if (pwm) d = d + 1;
                @(posedge clk); #1;
            end
        end
    endtask

    integer duty;
    reg     dir;
    integer dseq [0:23];
    reg     dirseq [0:23];
    integer p, k, fp, zeros_after, delta, last_duty, last_dir;

    initial begin
        $dumpfile("tb_pwm_motor.vcd");
        $dumpvars(0, tb_pwm_motor);

        // ---- A. reset: safe pattern, no drive ------------------------------------
        wait_cycles(8);
        #1;
        if (pwm !== 1'b0) fail("pwm not low during reset");
        if (in1 !== 1'b1 || in2 !== 1'b1) fail("reset is not short brake");

        // ---- B. enable with zero demand: forward pins, zero duty ------------------
        rst_n  = 1'b1;
        enable = 1'b1;
        cmd    = 16'sd0;
        wait_periods(4);
        #1;
        if (in1 !== 1'b1 || in2 !== 1'b0) fail("zero command did not select forward");
        if (pwm !== 1'b0) fail("zero command produced drive");

        // ---- C. 50% forward -------------------------------------------------------
        cmd = 16'sd10;
        wait_periods(12);
        measure_period(duty, dir);
        if (duty !== 10) fail("50% command did not settle at duty 10");
        if (dir !== 1'b0) fail("positive command selected reverse");

        // ---- D. 100% forward ------------------------------------------------------
        cmd = 16'sd20;
        wait_periods(12);
        measure_period(duty, dir);
        if (duty !== PMAX) fail("full command did not reach 100% duty");

        // ---- E. slope back to 50% -------------------------------------------------
        cmd = 16'sd10;
        wait_periods(12);
        measure_period(duty, dir);
        if (duty !== 10) fail("duty did not come back to 10");

        // ---- F. reversal: zero first, dead time, then swap ------------------------
        cmd = -16'sd10;
        for (p = 0; p < 24; p = p + 1) begin
            measure_period(dseq[p], dirseq[p]);
        end

        $write("INFO: reversal duty:");
        for (p = 0; p < 24; p = p + 1) $write(" %0d", dseq[p]);
        $write("\nINFO: reversal dir :");
        for (p = 0; p < 24; p = p + 1) $write(" %0d", dirseq[p]);
        $write("\n");

        fp = -1;
        for (p = 0; p < 24; p = p + 1) begin
            if (dirseq[p] === 1'b1 && fp < 0) fp = p;
        end
        if (fp < 0) begin
            fail("reverse command never swapped the direction pins");
        end else begin
            if (fp == 0) fail("reversal test started already reversed");
            if (dseq[fp] != 0) fail("direction pins swapped while duty was nonzero");
            zeros_after = 0;
            for (k = fp; k < 24; k = k + 1) begin
                if (dseq[k] == 0) zeros_after = zeros_after + 1;
                else k = 24;   // stop at the first driven period
            end
            if (zeros_after < DEAD) fail("dead time shorter than DEAD_CYCLES");
        end

        // never step the duty by more than SLEW_STEP, in either direction
        for (p = 1; p < 24; p = p + 1) begin
            delta = dseq[p] - dseq[p-1];
            if (delta < 0) delta = -delta;
            if (delta > SLEW) fail("duty changed by more than SLEW_STEP in one period");
        end

        last_duty = dseq[23];
        last_dir  = dirseq[23];
        if (last_duty !== 10) fail("reverse command did not settle at duty 10");
        if (last_dir !== 1'b1) fail("reverse command did not settle reversed");
        if (in1 !== 1'b0 || in2 !== 1'b1) fail("reverse pins are not IN1=0 IN2=1");

        // ---- G/H. out of range must saturate, not wrap ----------------------------
        cmd = 16'sd30000;
        wait_periods(30);   // reversal + settle: 5 down, 3 dead, 10 up, with margin
        measure_period(duty, dir);
        if (duty !== PMAX) fail("large positive command did not saturate at 100%");
        if (dir !== 1'b0)  fail("large positive command selected reverse");

        cmd = -16'sd30000;
        wait_periods(40);
        measure_period(duty, dir);
        if (duty !== PMAX) fail("large negative command did not saturate at 100%");
        if (dir !== 1'b1)  fail("large negative command selected forward");

        // ---- I. brake takes effect in the same time step --------------------------
        brake = 1'b1;
        #1;
        if (pwm !== 1'b0) fail("brake did not clear pwm immediately");
        if (in1 !== 1'b1 || in2 !== 1'b1) fail("brake is not short brake");
        wait_periods(3);
        #1;
        if (pwm !== 1'b0) fail("pwm came back while braked");

        // ---- J. enable low behaves the same way -----------------------------------
        brake  = 1'b0;
        enable = 1'b0;
        #1;
        if (pwm !== 1'b0) fail("enable low did not clear pwm immediately");
        if (in1 !== 1'b1 || in2 !== 1'b1) fail("enable low is not short brake");
        wait_periods(3);
        #1;
        if (pwm !== 1'b0) fail("pwm came back while disabled");

        if (errors == 0) $display("TEST PASSED: tb_pwm_motor");
        else             $display("TEST FAILED: tb_pwm_motor (%0d error(s))", errors);

        $finish;
    end
endmodule
