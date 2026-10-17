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
    parameter signed [31:0] DELTA_WRAP_Q = 0
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
