`timescale 1ns/1ps
// Bounded open-loop measurements, independent of the ADC/control sample clock.
// Positions and PWM use logical control signs. Configuration encoder_sign relates
// a positive motor request to direction-corrected encoder motion. No measurement
// changes the controller's gains or writes a compensation value.
module motor_calibration #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer PWM_MAX=2500
) (
    input wire clk, rst_n, abort, core_stopped, permit, sample_ready,
    input wire [3:0] fault,
    input wire signed [31:0] position,
    input wire signed [15:0] actual_pwm,
    input wire request_valid,
    input wire [2:0] request_kind,
    input wire [31:0] request_session,
    input wire [15:0] request_trial,
    input wire signed [31:0] request_a, request_b, request_c,
    output reg session_active, active,
    output wire signed [15:0] cmd_counts,
    output wire signed [15:0] raw_cmd_counts,
    output wire drive_allowed,
    output reg [31:0] session_id,
    output reg [15:0] trial_id,
    output reg [3:0] phase, result,
    output reg [31:0] ms_now,
    output reg event_valid,
    output reg [31:0] t_command, t_pwm, t_edge, t_end,
    output reg signed [31:0] start_position, end_position,
    output reg [15:0] window1, window2, window3
);
    localparam integer MS_CLKS=(CLK_HZ<1000) ? 1 : CLK_HZ/1000;
    localparam integer MAX_DUTY=PWM_MAX/5;
    localparam [31:0] NOT_SEEN=32'hffffffff;
    localparam [3:0] IDLE=0, AWAIT_PWM=1, PRECHECK=2, START=3,
        KICK=4, SETTLE=5, OBSERVE=6, DONE=7;
    localparam [3:0] PENDING=0, START_OK=1, RUN_OK=2, NO_START=3,
        NOT_SUSTAINED=4, TRAVEL=5, FAULT=6, STOPPED=7, LINK_LOSS=8,
        REJECTED=9, PWM_TIMEOUT=10, INVALID=11, NOT_QUIET=12,
        PRECHECK_DONE=13;
    reg [31:0] ms_counter;
    wire tick_ms=(ms_counter==MS_CLKS-1);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ms_counter<=0; ms_now<=0; end
        else if (tick_ms) begin ms_counter<=0; ms_now<=ms_now+1; end
        else ms_counter<=ms_counter+1;
    end

    reg signed [15:0] command, hold_pwm;
    reg signed [31:0] session_origin, quiet_origin, quiet_min, quiet_max;
    reg signed [31:0] window_origin, furthest_forward;
    reg [31:0] travel_limit, heartbeat_ms, phase_ms, demand_ms, progress_ms;
    reg [31:0] flat_clks;
    reg [15:0] last_trial, rest_ms, quiet_ms;
    reg encoder_negative, motion_negative, is_run, short_profile, awaiting_hold;
    reg flat_valid, edge_seen, window_bad;
    reg [1:0] window_index;

    // Deliberate 32-bit modular subtraction: a normal small movement remains
    // small across RAW's signed counter wrap; no circular arm coordinate is used.
    wire signed [31:0] session_delta=position-session_origin;
    wire signed [32:0] session_ext={session_delta[31],session_delta};
    wire [32:0] travel_abs=session_delta[31] ? -session_ext : session_ext;
    wire travel_exceeded=session_active && (travel_abs>{1'b0,travel_limit});
    wire [31:0] heartbeat_age=ms_now-heartbeat_ms;
    wire link_expired=session_active && (heartbeat_age>=32'd200);
    wire unsafe=abort || !core_stopped || !permit || !sample_ready || (fault!=0);
    // Immediate output inhibition does not depend on the next clock or ms tick.
    assign drive_allowed=rst_n && active && session_active && !unsafe &&
                         !travel_exceeded && !link_expired;
    assign cmd_counts=drive_allowed ? command : 16'sd0;
    // The datapath receives this registered demand. Safety uses drive_allowed
    // independently, rather than placing the travel arithmetic before PWM data.
    assign raw_cmd_counts=command;

    wire signed [31:0] quiet_delta=position-quiet_origin;
    wire signed [31:0] q_min=(quiet_delta<quiet_min) ? quiet_delta : quiet_min;
    wire signed [31:0] q_max=(quiet_delta>quiet_max) ? quiet_delta : quiet_max;
    wire signed [32:0] quiet_range=$signed({q_max[31],q_max})-$signed({q_min[31],q_min});
    // Quiet tracking runs while inactive, including outside a session. A single
    // count of jitter is allowed; a larger range starts a fresh quiet interval.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rest_ms<=0; quiet_ms<=0; quiet_origin<=0; quiet_min<=0; quiet_max<=0;
        end else if (active || actual_pwm!=0) begin
            rest_ms<=0; quiet_ms<=0; quiet_origin<=position; quiet_min<=0; quiet_max<=0;
        end else begin
            if (tick_ms && rest_ms<1000) rest_ms<=rest_ms+1;
            if (quiet_range>33'sd1) begin
                quiet_ms<=0; quiet_origin<=position; quiet_min<=0; quiet_max<=0;
            end else begin
                quiet_min<=q_min; quiet_max<=q_max;
                if (tick_ms && quiet_ms<300) quiet_ms<=quiet_ms+1;
            end
        end
    end

    wire signed [31:0] trial_delta=position-start_position;
    wire signed [31:0] forward_delta=motion_negative ? -trial_delta : trial_delta;
    wire signed [31:0] raw_window_delta=position-window_origin;
    wire signed [31:0] forward_window=motion_negative ? -raw_window_delta : raw_window_delta;
    wire [15:0] window_count=(forward_window<=0) ? 16'd0 :
        (forward_window>32'sd65535) ? 16'hffff : forward_window[15:0];
    wire [31:0] trial_age=ms_now-t_command;
    wire [31:0] phase_age=ms_now-phase_ms;
    wire [31:0] demand_age=ms_now-demand_ms;
    wire [31:0] progress_age=ms_now-progress_ms;
    wire [31:0] age_pwm=ms_now-t_pwm;
    wire a_pwm_valid=(request_a!=0 && request_a<=MAX_DUTY && request_a>=-MAX_DUTY);
    wire b_pwm_valid=(request_b<=MAX_DUTY && request_b>=-MAX_DUTY);
    wire [32:0] a_abs=request_a[31] ? -$signed({request_a[31],request_a}) : {1'b0,request_a};
    wire [32:0] b_abs=request_b[31] ? -$signed({request_b[31],request_b}) : {1'b0,request_b};
    // Configuration only: constant division is outside the active data path.
    wire [23:0] config_product=request_a[15:0]*request_b[7:0];
    wire [23:0] config_limit=config_product/24'd3600;

    task finish;
        input [3:0] outcome;
        input close_session;
        begin
            command<=0; active<=0; phase<=DONE; result<=outcome;
            t_end<=ms_now; end_position<=position; event_valid<=1;
            flat_valid<=0; flat_clks<=0;
            if (close_session) session_active<=0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            session_active<=0; active<=0; command<=0; session_id<=0; trial_id<=0;
            phase<=IDLE; result<=PENDING; event_valid<=0;
            session_origin<=0; travel_limit<=0; heartbeat_ms<=0; last_trial<=0;
            encoder_negative<=0; motion_negative<=0;
            is_run<=0; short_profile<=0; awaiting_hold<=0;
            hold_pwm<=0; phase_ms<=0; demand_ms<=0;
            progress_ms<=0; flat_clks<=0; flat_valid<=0; edge_seen<=0;
            furthest_forward<=0; window_origin<=0; window_index<=0; window_bad<=0;
            t_command<=NOT_SEEN; t_pwm<=NOT_SEEN; t_edge<=NOT_SEEN; t_end<=NOT_SEEN;
            start_position<=0; end_position<=0; window1<=0; window2<=0; window3<=0;
        end else begin
            event_valid<=0;
            // Stop, fault and session limits outrank ALL requests, including
            // heartbeats. An already-expired heartbeat cannot resurrect a run.
            if (session_active && abort) finish(STOPPED,1'b1);
            else if (session_active && (!core_stopped || !permit || !sample_ready || fault!=0)) finish(FAULT,1'b1);
            else if (travel_exceeded) finish(TRAVEL,1'b1);
            else if (link_expired) finish(LINK_LOSS,1'b1);
            else begin
                if (request_valid) begin
                    case (request_kind)
                        3'd1: begin
                            if (session_active || active || unsafe || request_session==0 ||
                                request_session==session_id || request_trial!=0 ||
                                request_a<64 || request_a>65535 || request_b<5 || request_b>150 ||
                                (request_c!=1 && request_c!=-1) || config_limit<2) begin
                                result<=REJECTED; event_valid<=1;
                            end else begin
                                session_active<=1; session_id<=request_session; session_origin<=position;
                                travel_limit<={8'd0,config_limit}; encoder_negative<=request_c[31];
                                heartbeat_ms<=ms_now; last_trial<=0; trial_id<=0;
                                phase<=IDLE; result<=PENDING; event_valid<=1;
                                t_command<=NOT_SEEN; t_pwm<=NOT_SEEN; t_edge<=NOT_SEEN; t_end<=NOT_SEEN;
                                start_position<=position; end_position<=position;
                                window1<=0; window2<=0; window3<=0;
                            end
                        end
                        3'd2,3'd3: begin
                            if (!session_active || request_session!=session_id || active || unsafe ||
                                request_trial<=last_trial || !a_pwm_valid || request_c!=0 ||
                                (request_kind==2 && (request_b<0 || request_b>1)) ||
                                (request_kind==3 && (!b_pwm_valid ||
                                    (request_b!=0 && request_a[31]!=request_b[31]) || b_abs>a_abs))) begin
                                result<=REJECTED; event_valid<=1;
                            end else if (rest_ms<1000 || quiet_ms<300 || quiet_range>1 || actual_pwm!=0) begin
                                result<=NOT_QUIET; event_valid<=1;
                            end else begin
                                last_trial<=request_trial; trial_id<=request_trial;
                                active<=1; command<=request_a[15:0]; hold_pwm<=request_b[15:0];
                                is_run<=(request_kind==3); short_profile<=(request_kind==2 && request_b==0);
                                awaiting_hold<=0; motion_negative<=request_a[31]^encoder_negative;
                                phase<=AWAIT_PWM; result<=PENDING; flat_valid<=0; flat_clks<=0; edge_seen<=0;
                                start_position<=position; end_position<=position; furthest_forward<=0;
                                t_command<=ms_now; t_pwm<=NOT_SEEN; t_edge<=NOT_SEEN; t_end<=NOT_SEEN;
                                demand_ms<=ms_now; progress_ms<=ms_now; phase_ms<=ms_now;
                                window1<=0; window2<=0; window3<=0; window_index<=0; window_bad<=0;
                            end
                        end
                        3'd4: begin
                            if (session_active && request_session==session_id) heartbeat_ms<=ms_now;
                            else begin result<=REJECTED; event_valid<=1; end
                        end
                        3'd5: begin
                            // Only a finished matching trial is a cached result.
                            // Queries neither turn PENDING into a result nor erase
                            // a completed outcome when their ID is stale.
                            if (!active && trial_id!=0 && request_session==session_id &&
                                request_trial==trial_id && t_end!=NOT_SEEN) event_valid<=1;
                        end
                        3'd6: begin
                            if (session_active && request_session==session_id) finish(STOPPED,1'b1);
                            else begin result<=REJECTED; event_valid<=1; end
                        end
                        default: begin result<=REJECTED; event_valid<=1; end
                    endcase
                end

                if (active && !(request_valid && request_kind==6 && request_session==session_id)) begin
                    if (forward_delta>furthest_forward) begin
                        furthest_forward<=forward_delta; progress_ms<=ms_now;
                        if (!edge_seen) begin edge_seen<=1; t_edge<=ms_now; end
                    end
                    if (forward_delta< -32'sd1) finish(INVALID,1'b0);
                    else if ((!is_run && short_profile && trial_age>=20) ||
                             (!is_run && !short_profile && trial_age>=120) ||
                             (is_run && trial_age>=600)) begin
                        finish(is_run ? NOT_SUSTAINED : (short_profile ? PWM_TIMEOUT : NO_START),1'b0);
                    end else case (phase)
                        AWAIT_PWM: begin
                            if (short_profile && !is_run) begin
                                if (actual_pwm!=0) begin
                                    t_pwm<=ms_now; phase_ms<=ms_now; phase<=PRECHECK;
                                end else if (demand_age>=10) finish(PWM_TIMEOUT,1'b0);
                            end else if (actual_pwm==command) begin
                                if (!flat_valid) begin
                                    flat_valid<=1; flat_clks<=1;
                                    if (!awaiting_hold) t_pwm<=ms_now;
                                end else if (flat_clks>=MS_CLKS) begin
                                    flat_valid<=0; flat_clks<=0; phase_ms<=ms_now; progress_ms<=ms_now;
                                    phase<=awaiting_hold ? SETTLE : (is_run ? KICK : START);
                                end else flat_clks<=flat_clks+1;
                            end else begin flat_valid<=0; flat_clks<=0; end
                            if (!short_profile && demand_age>=10 &&
                                !(actual_pwm==command && flat_valid && flat_clks>=MS_CLKS)) finish(PWM_TIMEOUT,1'b0);
                        end
                        PRECHECK: if (age_pwm>=8) finish(PRECHECK_DONE,1'b0);
                        START: begin
                            if (forward_delta>=2) finish(START_OK,1'b0);
                            else if (phase_age>=100) finish(NO_START,1'b0);
                        end
                        KICK: begin
                            if (forward_delta>=2) begin
                                command<=hold_pwm; awaiting_hold<=1; phase<=AWAIT_PWM;
                                demand_ms<=ms_now; flat_valid<=0; flat_clks<=0;
                            end else if (trial_age>=120 || progress_age>=100 && !(forward_delta>furthest_forward)) finish(NO_START,1'b0);
                        end
                        SETTLE: begin
                            if (actual_pwm!=command) finish(PWM_TIMEOUT,1'b0);
                            else if (progress_age>=100 && !(forward_delta>furthest_forward)) finish(NOT_SUSTAINED,1'b0);
                            else if (phase_age>=100) begin
                                phase<=OBSERVE; phase_ms<=ms_now; window_origin<=position;
                                window_index<=0; window_bad<=0;
                            end
                        end
                        OBSERVE: begin
                            if (actual_pwm!=command) finish(PWM_TIMEOUT,1'b0);
                            else if (progress_age>=100 && !(forward_delta>furthest_forward)) finish(NOT_SUSTAINED,1'b0);
                            else if (phase_age>=100) begin
                                phase_ms<=ms_now; window_origin<=position;
                                if (window_index==0) begin
                                    window1<=window_count; window_index<=1;
                                    if (window_count==0) window_bad<=1;
                                end else if (window_index==1) begin
                                    window2<=window_count; window_index<=2;
                                    if (window_count==0) window_bad<=1;
                                end else begin
                                    window3<=window_count;
                                    if (!window_bad && window_count>=1 &&
                                        (window1<=1 || window_count>=window1-1)) finish(RUN_OK,1'b0);
                                    else finish(NOT_SUSTAINED,1'b0);
                                end
                            end
                        end
                        default: finish(INVALID,1'b0);
                    endcase
                end

            end
        end
    end
endmodule
