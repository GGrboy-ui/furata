// tb_clock_reset.v - self-checking testbench for clock_reset.
//
// Checks the three properties the rest of the design depends on:
//   1. reset is HELD for the full stretch window and only then released,
//   2. release is SYNCHRONOUS - rst_n never changes anywhere except on a clock edge,
//   3. assertion is ASYNCHRONOUS - pulling the raw source low drops rst_n immediately,
//      with no clock edge required (so a reset press works before the clock is running).
`timescale 1ns / 1ps

module tb_clock_reset;
    localparam integer STRETCH = 8;

    reg  clk    = 1'b0;
    reg  arst_n = 1'b0;
    reg  locked = 1'b1;
    wire rst_n;

    clock_reset #(.STRETCH_CYCLES(STRETCH)) dut (
        .clk(clk), .arst_n(arst_n), .locked(locked), .rst_n(rst_n)
    );

    always #5 clk = ~clk;   // 100 MHz model; posedges land at t = 5, 15, 25, ...

    integer errors = 0;

    task fail;
        input [8*48-1:0] msg;
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

    // Edges land at t = 5, 15, 25 ... so a synchronous change satisfies (t-5)%10 == 0.
    // Enabled only while we are testing synchronous release; the deliberate asynchronous
    // assertion test below turns it off first.
    reg edge_check = 1'b0;

    always @(rst_n) begin
        if (edge_check && ((($time - 5) % 10) != 0)) begin
            $display("FAIL: rst_n changed off a clock edge at t=%0t", $time);
            errors = errors + 1;
        end
    end

    integer release_cycles;
    integer i;

    initial begin
        $dumpfile("tb_clock_reset.vcd");
        $dumpvars(0, tb_clock_reset);

        // ---- 1. power-on: raw reset held, then released between clock edges ----------
        #23;
        if (rst_n !== 1'b0) fail("rst_n not low while raw reset asserted");

        arst_n = 1'b1;
        #1;
        if (rst_n !== 1'b0) fail("rst_n released before the synchroniser ran");

        edge_check = 1'b1;
        release_cycles = 0;
        while ((rst_n !== 1'b1) && (release_cycles < 64)) begin
            @(posedge clk);
            #1;
            release_cycles = release_cycles + 1;
        end

        if (rst_n !== 1'b1) begin
            fail("rst_n never released");
        end else begin
            $display("INFO: released after %0d clocks (stretch=%0d)", release_cycles, STRETCH);
            if (release_cycles < (STRETCH + 1)) fail("reset released too early");
            if (release_cycles > (STRETCH + 6)) fail("reset released too late");
        end

        // stays released, and stays synchronous
        wait_cycles(50);
        if (rst_n !== 1'b1) fail("rst_n did not stay released");

        // ---- 2. PLL lock lost: reset must re-assert, then release again --------------
        locked = 1'b0;
        wait_cycles(4);
        #1;
        if (rst_n !== 1'b0) fail("reset did not re-assert after lock lost");

        locked = 1'b1;
        release_cycles = 0;
        while ((rst_n !== 1'b1) && (release_cycles < 64)) begin
            @(posedge clk);
            #1;
            release_cycles = release_cycles + 1;
        end
        if (rst_n !== 1'b1) fail("reset did not release after lock regained");

        // ---- 3. asynchronous assertion: no clock edge may be required ----------------
        edge_check = 1'b0;
        wait_cycles(3);
        arst_n = 1'b0;
        #1;
        if (rst_n !== 1'b0) fail("assertion is not asynchronous");

        #3;
        arst_n = 1'b1;
        wait_cycles(STRETCH + 12);
        #1;
        if (rst_n !== 1'b1) fail("reset did not release after async pulse");

        // a short off-edge pulse must still be caught
        wait_cycles(3);
        arst_n = 1'b0;
        #2;
        arst_n = 1'b1;
        #1;
        if (rst_n !== 1'b0) fail("short async reset pulse was not caught");

        wait_cycles(STRETCH + 12);
        #1;
        if (rst_n !== 1'b1) fail("reset did not release after short pulse");

        if (errors == 0) $display("TEST PASSED: tb_clock_reset");
        else             $display("TEST FAILED: tb_clock_reset (%0d error(s))", errors);

        $finish;
    end
endmodule
