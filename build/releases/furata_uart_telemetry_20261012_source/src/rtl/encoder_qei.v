// encoder_qei.v - quadrature (A/B) decoder plus period-based speed measurement.
//
// WHY THIS MODULE EXISTS
//   rtl/ previously had no encoder path at all. The migration plan assumed the existing
//   building blocks covered the interface side, but nothing was there: this is new, and it
//   is the one module in the migration that does NOT depend on any of the unresolved
//   hardware unknowns (angle-sensor type, drive-board part number, ACG720 pinout, pin
//   voltage). So it can be written and fully verified now.
//
// WHY PERIOD MEASUREMENT AND NOT "POSITION DIFFERENCE OVER A TICK"
//   The active mechanics use a parameterized count/rev value (default 408 until
//   hand-turned calibration). At low speed, position difference over one control
//   tick is quantized and produces long runs of zero with occasional one-count
//   steps. Period between quadrature edges is therefore the primary velocity path;
//   delta is retained only as a coarse cross-check.
// OUTPUT SCALING
//   vel is Q(VEL_FRAC) counts per second. Default VEL_FRAC=8 gives Q8.8, engineering range
//   +-32768 counts/s - far above the ~9130 counts/s this motor can produce - with
//   1/256 counts/s resolution. The constant is computed at elaboration in 64 bits:
//       VEL_K = CLK_HZ << VEL_FRAC                     [counts/s, Q_VEL_FRAC]
//   Every accepted quadrature edge increments position by one count, so its measured
//   inter-edge period must not be divided by the 4x decode factor a second time.
//
// SAFETY / ROBUSTNESS PROPERTIES (all covered by tb_encoder_qei.v)
//   * Two-flop synchronisers on A and B: the encoder is asynchronous to clk_sys.
//   * 4x decode uses a transition table with a modular comparison (next == prev+1 counts up,
//     prev == next+1 counts down, anything else counts nothing). A one-step glitch that
//     returns to the previous state therefore leaves the position EXACTLY unchanged, however
//     often it repeats - the original J280-era plan had no answer for this at all.
//   * The period counter saturates, so a stopped shaft yields a huge period, a huge period
//     yields speed ~ 0, and after VEL_TIMEOUT_CLKS with no edge the speed is forced to
//     exactly 0. The output cannot hold a stale non-zero value.
//   * The divider is a multi-cycle sequential shift/subtract, so no 64-bit combinational
//     divide is inferred. It completes well inside one 200 us tick at 50 MHz.
//
// PORTABILITY: no vendor primitives, pure behavioural RTL - Verilator lints it and Icarus
// simulates it next to the rest of rtl\.
`timescale 1ns / 1ps

module encoder_qei #(
    parameter integer CLK_HZ           = 50_000_000,      // system clock; must match tick_gen
    parameter integer VEL_FRAC         = 8,               // fractional bits in vel (Q8.8)
    parameter integer VEL_TIMEOUT_CLKS = 50_000_000       // 1 s without an edge -> vel = 0
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enc_a,        // raw A phase, asynchronous
    input  wire               enc_b,        // raw B phase, asynchronous
    input  wire               tick_speed,   // one-cycle pulse from tick_gen (5 kHz default)
    output wire signed [31:0] position,     // signed 4x-decoded count; wraps on purpose
    output reg  signed [31:0] vel,          // Q(VEL_FRAC) counts/s, + = forward
    output reg  signed [31:0] delta         // position change over the last tick_speed window
);
    // ---------------------------------------------------------------------------
    // 1. Input synchronisation (encoder edges are asynchronous to clk_sys).
    // ---------------------------------------------------------------------------
    reg [1:0] a_sync, b_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_sync <= 2'b00;
            b_sync <= 2'b00;
        end else begin
            a_sync <= {a_sync[0], enc_a};
            b_sync <= {b_sync[0], enc_b};
        end
    end

    wire [1:0] ab_now = {a_sync[1], b_sync[1]};   // {a, b}

    // ---------------------------------------------------------------------------
    // 2. 4x quadrature decode.
    //    The two legal Gray sequences for {a,b} are:
    //        forward : 00 -> 01 -> 11 -> 10 -> 00
    //        reverse : 00 -> 10 -> 11 -> 01 -> 00
    //    Index the table by {prev_a,prev_b,cur_a,cur_b} and return +1/-1/0.
    //    The modular comparison is what makes glitches self-cancelling: 00 -> 01 -> 00
    //    nets exactly +1 -1 = 0, so a single-channel glitch can never accumulate a phantom
    //    count no matter how often it repeats.
    //
    //    NOTE: an earlier revision of this table had these two rows swapped. The bug is
    //    invisible in isolation - the decoder still counts 4 edges per revolution - but the
    //    net count over any full quadrature cycle becomes +1-1+1-1 = 0, so position never
    //    moves and velocity reads garbage. tb_encoder_qei.v catches it because it measures
    //    NET counts over a known number of edges instead of trusting an edge count.
    // ---------------------------------------------------------------------------
    reg  [1:0] ab_prev;
    reg        ab_valid;

    function [1:0] step_of;
        input [3:0] idx;                     // {prev_a,prev_b,cur_a,cur_b}
        begin
            case (idx)
                // forward: 00->01, 01->11, 11->10, 10->00
                4'b0001, 4'b0111, 4'b1110, 4'b1000: step_of = 2'd1;
                // reverse: 00->10, 10->11, 11->01, 01->00
                4'b0010, 4'b1011, 4'b1101, 4'b0100: step_of = 2'd3;   // 2'd3 encodes -1
                default:                            step_of = 2'd0;   // no change / illegal
            endcase
        end
    endfunction

    wire [1:0] step = step_of({ab_prev, ab_now});

    wire       new_sample = (ab_now != ab_prev);
    wire       any_edge   = ab_valid && new_sample;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ab_prev  <= 2'b00;
            ab_valid <= 1'b0;
        end else if (!ab_valid) begin
            // First sample after reset is adopted as the reference and counts nothing.
            ab_prev  <= ab_now;
            ab_valid <= 1'b1;
        end else if (new_sample) begin
            ab_prev <= ab_now;
        end
    end

    wire signed [31:0] d_pos = (step == 2'd1) ? 32'sd1 : ((step == 2'd3) ? -32'sd1 : 32'sd0);

    // ---------------------------------------------------------------------------
    // 3. Position and per-tick delta.
    // ---------------------------------------------------------------------------
    reg signed [31:0] pos_q;
    reg signed [31:0] pos_at_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pos_q       <= 32'sd0;
            pos_at_tick <= 32'sd0;
            delta       <= 32'sd0;
        end else begin
            if (any_edge) pos_q <= pos_q + d_pos;
            if (tick_speed) begin
                delta       <= pos_q - pos_at_tick;
                pos_at_tick <= pos_q;
            end
        end
    end

    assign position = pos_q;

    // ---------------------------------------------------------------------------
    // 4. Period measurement between accepted edges, saturating.
    //    Declared BEFORE the divider because the divider reads per_cnt. Verilog has no
    //    forward references: an earlier revision put this block after the divider and
    //    Icarus refused to elaborate it ("Unable to bind wire/reg/memory per_cnt").
    // ---------------------------------------------------------------------------
    localparam [31:0] CNT_MAX = 32'hFFFF_FFFF;

    reg [31:0] per_cnt;      // clocks since the last edge, this edge included
    reg [31:0] per_lat;      // the completed period, latched ON the edge

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            per_cnt <= 32'd0;
            per_lat <= 32'd1;
        end else if (any_edge) begin
            // THE ORDER HERE IS LOAD-BEARING. divider_seq starts one cycle after the edge, so by
            // then per_cnt has already been reloaded with 1. Reading per_cnt for the divisor
            // therefore measured a period of 65 clocks at every speed, which pinned the
            // reported speed to the ceiling - the exact bug this latch exists to prevent.
            // Latch the elapsed count here, on the edge, and give the divider per_lat.
            per_lat <= (per_cnt == 32'd0) ? 32'd1 : per_cnt;
            per_cnt <= 32'd1;
        end else if (per_cnt != CNT_MAX) begin
            per_cnt <= per_cnt + 32'd1;
        end
    end

    // ---------------------------------------------------------------------------
    // 5. Speed = VEL_K / period, using the separately verified sequential divider.
    //    See rtl/divider_seq.v and tb_divider_seq.v: an inlined version of this division
    //    produced a bit-reversed quotient here, which is why it is now a module with its own
    //    exact-arithmetic testbench.
    //
    //    The numerator is widened to WIDTH bits explicitly so divider_seq's port connection
    //    is unambiguous (VEL_K is already in Q(VEL_FRAC) counts/s).
    //
    //    An edge arriving while the divider is busy is ignored. The period is thousands of
    //    clocks at any speed this rig can reach, so the 64-cycle division always finishes
    //    long before the next edge; if edges ever did outrun it, the speed reading would go
    //    briefly stale rather than wrong.
    // ---------------------------------------------------------------------------
    // At 50 MHz and Q8.8, VEL_K is 12_800_000_000 and requires a 64-bit numerator.
    // The 64-cycle divider still completes well before the next valid motor edge.
    localparam integer DIV_W  = 64;
    localparam [63:0] VEL_K   = ({32'd0, CLK_HZ[31:0]} << VEL_FRAC);
    localparam [31:0] TIMEOUT  = VEL_TIMEOUT_CLKS;

    wire             div_busy;
    wire             div_done;
    wire [DIV_W-1:0] div_quo;
    wire [DIV_W-1:0] div_rem_unused;   // connected so the port is not left open

    reg              dir_captured;   // direction that produced the period being measured

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dir_captured <= 1'b0;
        else if (any_edge) dir_captured <= (step == 2'd3);
    end

    // Start the division ONE CYCLE AFTER the edge. This is required, not cosmetic: per_lat is
    // written by the edge itself, so a start gated directly on any_edge would sample the
    // previous period. That was the bug that made the divisor read 23 clocks instead of 1000
    // and pinned the reported speed to the ceiling.
    reg div_go;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) div_go <= 1'b0;
        else        div_go <= any_edge;
    end

    wire div_start = div_go && !div_busy;

    divider_seq #(.WIDTH(DIV_W)) u_div (
        .clk   (clk),
        .rst_n (rst_n),
        .start (div_start),
        .num   (VEL_K),
        .den   ({32'd0, per_lat}),
        .busy  (div_busy),
        .done  (div_done),
        .q     (div_quo),
        .r     (div_rem_unused)
    );

    // The remainder is genuinely not needed on the speed path. It is read once into a harmless
    // sink so that both the port connection and the signal are used, keeping the lint clean
    // without either leaving a port open or pretending the value matters.
    wire _unused_div_rem = ^div_rem_unused;

    // ---------------------------------------------------------------------------
    // 6. Output: sign, saturation and a staleness timeout.
    //
    //    SCALING NOTE, because getting this wrong cost a long debugging session: VEL_K is
    //    already scaled by 2^VEL_FRAC, so the quotient is a Q(VEL_FRAC) counts/s value and for
    //    this rig it lives in the MILLIONS: 1000 counts/s in Q8.8 is 256000, and the motor's
    //    full speed of ~9130 counts/s is 2337280. A 16-bit ceiling (65535) is therefore not a
    //    conservative clamp, it is BELOW the normal operating range - clamping to it does not
    //    limit the reading, it destroys it. The clamp below is 24-bit for that reason, and the
    //    comparison is a plain magnitude test on a 24-bit value.
    //
    //    A ceiling is a convenience, not a safety property: the safety property is the staleness
    //    timeout at the bottom, which involves no arithmetic at all.
    // ---------------------------------------------------------------------------
    localparam [23:0] VEL_CEIL = 24'd8_000_000;    // Q(VEL_FRAC) counts/s; = 31250 counts/s

    reg [31:0] since_edge;

    // Compare before narrowing: short periods can produce a quotient above 32 bits.
    wire [23:0] mag24 = (div_quo > {40'd0, VEL_CEIL}) ? VEL_CEIL : div_quo[23:0];

    // Latch on the cycle AFTER done. divider_seq presents done/q/r together, and a registered
    // copy of done removes any dependence on that timing detail.
    reg div_done_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) div_done_q <= 1'b0;
        else        div_done_q <= div_done;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vel        <= 32'sd0;
            since_edge <= 32'd0;
        end else begin
            if (any_edge)                   since_edge <= 32'd0;
            else if (since_edge != CNT_MAX) since_edge <= since_edge + 32'd1;

            if (div_done_q) begin
                vel <= dir_captured ? -$signed({8'd0, mag24}) : $signed({8'd0, mag24});
            end

            if (since_edge >= TIMEOUT) vel <= 32'sd0;
        end
    end
endmodule
