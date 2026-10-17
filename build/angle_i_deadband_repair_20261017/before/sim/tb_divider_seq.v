// tb_divider_seq.v - exact-arithmetic verification of divider_seq.
//
// This testbench exists because an inlined version of this divider produced a bit-reversed
// quotient inside encoder_qei - a bug that looked like a plausible number. Here every result
// is compared against Verilog's own 64-bit integer division, so correctness is not a matter
// of judgement. The cases include the exact numbers the encoder path uses:
//   12_800_000_000 / period where period is the measured inter-edge clock count.
`timescale 1ns / 1ps

module tb_divider_seq;
    localparam integer W = 64;

    reg              clk = 1'b0;
    reg              rst_n = 1'b0;
    reg              start = 1'b0;
    reg  [W-1:0]     num = 0;
    reg  [W-1:0]     den = 0;
    wire             busy, done;
    wire [W-1:0]     q, r;

    integer errors = 0;
    integer k;

    always #10 clk = ~clk;

    divider_seq #(.WIDTH(W)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .num(num), .den(den),
        .busy(busy), .done(done), .q(q), .r(r));

    // Run one division and check both quotient and remainder exactly.
    task check;
        input [W-1:0] n;
        input [W-1:0] d;
        input [255:0] tag;
        reg   [W-1:0] e_q;
        reg   [W-1:0] e_r;
        integer to;
        begin
            e_q = n / d;
            e_r = n % d;

            @(negedge clk);
            num = n; den = d; start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            to = 0;
            while (!done && to < 200) begin
                @(negedge clk);
                to = to + 1;
            end

            if (!done) begin
                $display("FAIL [%0s]: no done pulse within 200 cycles", tag);
                errors = errors + 1;
            end else if (q !== e_q) begin
                $display("FAIL [%0s]: %0d / %0d = %0d, expected %0d", tag, n, d, q, e_q);
                errors = errors + 1;
            end else if (r !== e_r) begin
                $display("FAIL [%0s]: %0d %% %0d = %0d, expected %0d", tag, n, d, r, e_r);
                errors = errors + 1;
            end else begin
                $display("  OK [%0s]: %0d / %0d = %0d r %0d  (%0d cycles)", tag, n, d, q, e_r, to);
            end
            @(negedge clk);
        end
    endtask

    initial begin
        $dumpfile("tb_divider_seq.vcd");
        $dumpvars(0, tb_divider_seq);

        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        $display("");
        $display("--- small values ---");
        check(64'd100,     64'd7,  "100/7");
        check(64'd1,       64'd1,  "1/1");
        check(64'd0,       64'd5,  "0/5");
        check(64'd5,       64'd1,  "5/1");
        check(64'd12,      64'd12, "12/12");
        check(64'd11,      64'd12, "11/12");

        $display("");
        $display("--- exact encoder constant, the cases the speed path uses ---");
        // VEL_K = 50 MHz << 8 = 12_800_000_000 (each decoded edge is one count).
        check(64'd12_800_000_000, 64'd960,   "VEL_K/960");
        check(64'd12_800_000_000, 64'd480,   "VEL_K/480");
        check(64'd12_800_000_000, 64'd9600,  "VEL_K/9600");
        check(64'd12_800_000_000, 64'd48000, "VEL_K/48000 (about 60 rpm)");
        check(64'd12_800_000_000, 64'd1,     "VEL_K/1 (saturation case)");

        $display("");
        $display("--- large and awkward divisors ---");
        check(64'd12_800_000_000, 64'd50_000_000, "VEL_K/50e6");
        check(64'd12_800_000_000, 64'd2_500_000_000, "VEL_K / wide divisor");
        check(64'd18_446_744_073_709_551_615, 64'd18_446_744_073_709_551_615, "max/max");
        check(64'd18_446_744_073_709_551_615, 64'd1, "max/1");

        $display("");
        if (errors == 0) $display("TEST PASSED: tb_divider_seq");
        else             $fatal(1, "TEST FAILED: tb_divider_seq (%0d error(s))", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $fatal(1, "FAIL: watchdog timeout");
    end
endmodule
