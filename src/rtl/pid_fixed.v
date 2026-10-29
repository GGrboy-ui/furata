`timescale 1ns/1ps
// Discrete positional PID. Inputs, gains and output are signed Q16.16.
// Ki and Kd are selected for the actual update interval (5 ms angle, 50 ms position);
// they are never silently rescaled when the tick rate changes.
module pid_fixed #(
    parameter signed [31:0] KP = 32'sd23921,       // 0.365 * 2^16
    parameter signed [31:0] KI = 32'sd655,         // 0.010 * 2^16
    parameter signed [31:0] KD = 32'sd26214,       // 0.400 * 2^16
    parameter signed [31:0] OUT_LIMIT = 32'sd6553600,
    parameter signed [31:0] I_LIMIT = 32'sd1073741824,
    // Enable only for circular position error. Error is already normalized.
    parameter signed [31:0] DELTA_WRAP_Q = 0,
    // Inclusive error band that holds the accumulated integral; <=0 disables it.
    // P and D always use the complete error. Units match the Q16.16 inputs.
    parameter signed [31:0] I_DEADBAND_Q = 32'sd0,
    // Optional near-target bleed: retain a percentage of stored I per tick, without
    // adding error. Signed division rounds toward zero for symmetric decay.
    // Takes priority over hold deadband; <=0 preserves the existing behavior.
    parameter signed [31:0] I_DECAY_BAND_Q = 32'sd0,
    parameter integer I_DECAY_RETAIN_PERCENT = 75
) (
    input wire clk, rst_n, clear, tick,
    input wire signed [31:0] target_q, actual_q,
    output reg signed [31:0] out_q,
    output reg valid
);
    reg signed [31:0] previous_q, integral_q;
    reg signed [31:0] error_stage_q, integral_stage_q, delta_stage_q;
    reg sample_pending;
    reg signed [31:0] error_q, inext_q, delta_q;
    reg signed [63:0] error_w, isum_w, delta_w;
    reg signed [63:0] kp_term, ki_term, kd_term, sum_w, scaled_w;
    localparam integer I_RETAIN_PERCENT = (I_DECAY_RETAIN_PERCENT<0) ? 0 :
        (I_DECAY_RETAIN_PERCENT>100) ? 100 : I_DECAY_RETAIN_PERCENT;
    // Exact truncate-toward-zero division of the 32-bit I by 100, expressed as a
    // single constant multiply so synthesis infers DSPs instead of a combinational
    // divider (a LUT divider added ~57 logic levels and missed 50 MHz by 23 ns).
    //   K = ceil(I_RETAIN_PERCENT * 2^38 / 100)
    // The reciprocal rounding error e = 100*K - I_RETAIN_PERCENT*2^38 is in
    // [0,99] and e*2^31 < 2^38, so floor(|I|*K/2^38) == floor(|I|*RETAIN/100).
    // Keeping the product signed and adding 2^38-1 for negative values only turns
    // the arithmetic shift into Verilog's truncate-toward-zero `/`, so no
    // absolute-value or sign-restore logic sits on the critical path.
    localparam [38:0] I_RETAIN_RECIP =
        (I_RETAIN_PERCENT * 64'sd274877906944 + 64'sd99) / 64'sd100;
    wire signed [70:0] i_decay_product =
        $signed({{39{integral_q[31]}},integral_q}) * $signed({1'b0,I_RETAIN_RECIP});
    wire signed [70:0] i_decay_adjusted = i_decay_product
        + (i_decay_product[70] ? 71'sh0000003FFFFFFFFF : 71'sd0);
    wire signed [31:0] i_decay_next = i_decay_adjusted[69:38];

    function [31:0] clamp32;
        input signed [63:0] x;
        begin
            if (x > 64'sd2147483647) clamp32=32'sh7fffffff;
            else if (x < -64'sd2147483648) clamp32=32'sh80000000;
            else clamp32=x[31:0];
        end
    endfunction

    always @* begin
        error_w={{32{target_q[31]}},target_q}-{{32{actual_q[31]}},actual_q};
        error_q=clamp32(error_w);
        isum_w={{32{integral_q[31]}},integral_q}+{{32{error_q[31]}},error_q};
        if (KI==0) inext_q=0;
        else if (I_DECAY_BAND_Q>0 && error_q>=-I_DECAY_BAND_Q && error_q<=I_DECAY_BAND_Q)
            inext_q=i_decay_next;
        else if (I_DEADBAND_Q>0 && error_q>=-I_DEADBAND_Q && error_q<=I_DEADBAND_Q)
            inext_q=integral_q;
        else if (isum_w > $signed(I_LIMIT)) inext_q=I_LIMIT;
        else if (isum_w < -$signed(I_LIMIT)) inext_q=-I_LIMIT;
        else inext_q=isum_w[31:0];
        delta_w={{32{error_q[31]}},error_q}-{{32{previous_q[31]}},previous_q};
        if (DELTA_WRAP_Q>0) begin
            if (delta_w >= $signed(DELTA_WRAP_Q)/2) delta_w=delta_w-$signed(DELTA_WRAP_Q);
            else if (delta_w < -$signed(DELTA_WRAP_Q)/2) delta_w=delta_w+$signed(DELTA_WRAP_Q);
        end
        delta_q=clamp32(delta_w);

        // Sign-extend both factors before multiplication.  Without this explicit
        // widening Verilog may evaluate a 32x32 product in only 32 bits.
        kp_term=$signed({{32{KP[31]}},KP}) * $signed({{32{error_stage_q[31]}},error_stage_q});
        ki_term=$signed({{32{KI[31]}},KI}) * $signed({{32{integral_stage_q[31]}},integral_stage_q});
        kd_term=$signed({{32{KD[31]}},KD}) * $signed({{32{delta_stage_q[31]}},delta_stage_q});
        sum_w=kp_term+ki_term+kd_term;
        scaled_w=sum_w/64'sd65536; // signed division truncates toward zero
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_q<=0; previous_q<=0; integral_q<=0; valid<=0;
            error_stage_q<=0; integral_stage_q<=0; delta_stage_q<=0;
            sample_pending<=0;
        end else begin
            valid<=0;
            if (clear) begin
                out_q<=0; previous_q<=0; integral_q<=0;
                error_stage_q<=0; integral_stage_q<=0; delta_stage_q<=0;
                sample_pending<=0;
            end else begin
                // The next clock computes the result of this captured sample.
                // Tick spacing is 5 ms / 50 ms in the board design.
                sample_pending<=tick;
                if (tick) begin
                    previous_q<=error_q;
                    integral_q<=inext_q;
                    error_stage_q<=error_q;
                    integral_stage_q<=inext_q;
                    delta_stage_q<=delta_q;
                end
                if (sample_pending) begin
                    valid<=1;
                    if (scaled_w>$signed(OUT_LIMIT)) out_q<=OUT_LIMIT;
                    else if (scaled_w<-$signed(OUT_LIMIT)) out_q<=-$signed(OUT_LIMIT);
                    else out_q<=scaled_w[31:0];
                end
            end
        end
    end
endmodule
