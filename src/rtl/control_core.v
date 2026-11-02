`timescale 1ns/1ps
// Jiangxie program 16: pulse swing-up, angle PID at 5 ms, position PID at 50 ms.
// One sample_valid represents 1 ms. Angle is an ADC code, not degrees.
module control_core #(
    parameter integer CENTER=1014, CAPTURE_RANGE=500,
    parameter integer START_PERCENT=55, PULSE_MS=100, CHECK_MS=40,
    parameter integer RUNTIME_POSITION_PERIOD=0,
    parameter integer RUNTIME_POSITION_GAINS=0,
    parameter integer PIPELINED_ANGLE_PID=0,
    parameter integer ENABLE_VELOCITY=0, MAX_SPEED=30,
    parameter integer ANGLE_MS=5, POSITION_MS=50, SWING_TIMEOUT_MS=15000,
    parameter integer POSITION_LIMIT_COUNTS=4080,
    parameter integer MOTOR_TEST_PERCENT=20, MOTOR_TEST_REVERSE=0,
    parameter signed [31:0] ANGLE_KP=32'sd20661, ANGLE_KI=32'sd820, ANGLE_KD=32'sd31214,
    parameter signed [31:0] POSITION_KP=32'sd30214, POSITION_KI=32'sd350, POSITION_KD=32'sd392144,
    // Linear PWM addition about fixed CENTER; zero width/maximum disables it.
    parameter integer BALANCE_BOOST_RANGE_CODES=24,
    parameter integer BALANCE_BOOST_MAX_PERCENT=5,
    parameter integer COUNTS_PER_REV=408,
    // Hold the angle integral within +/-10 ADC codes of its live target.
    // Q16.16 ADC codes; <=0 restores integration for every error sample.
    parameter signed [31:0] ANGLE_I_DEADBAND_Q=32'sd655360,
    // Within +/-2 encoder counts of the live position target, bleed stored
    // position I at each position tick (50 ms by default).
    // No error is integrated inside this band. <=0 disables the bleed.
    parameter signed [31:0] POSITION_I_DECAY_BAND_Q=32'sd131072,
    // Percentage of stored I retained per tick: 30 means retain 30%, remove 70%.
    // Adjustable 0..100 (clamped): 0 clears, 100 holds without adding error.
    parameter integer POSITION_I_DECAY_RETAIN_PERCENT=100
) (
    input wire clk, rst_n, sample_valid, sample_ready,
    input wire [11:0] sample,
    input wire signed [31:0] position,
    input wire signed [31:0] position_target_q,
    input wire [15:0] position_period_ms,
    input wire outer_speed,switch_speed_cmd,
    input wire signed [31:0] position_kp_q,position_ki_q,position_kd_q,
    input wire [15:0] speed_friction_t,
    output reg start_accepted,
    output wire [95:0] position_defaults,
    output wire [7:0] handover_remaining,
    output wire [15:0] applied_friction_t,
    input wire [15:0] speed_period_ms,
    input wire signed [31:0] speed_kp_q,speed_ki_q,speed_kd_q,speed_kpos_q,reference_velocity_q,actual_velocity_q,
    output wire signed [31:0] speed_target_q,
    output wire speed_update,
    input wire start_cmd, motor_test_cmd, balance_cmd, stop_cmd, permit, fault_latched,
    output wire running,
    output wire signed [31:0] command_q,
    output reg [2:0] state,
    output reg [3:0] request_fault,
    output wire signed [31:0] relative_position,
    output reg signed [31:0] protocol_position,
    output wire angle_update, position_update,
    output wire signed [31:0] position_error_q, angle_target_offset_q,
    output wire signed [31:0] angle_pid_q,
    output wire [287:0] controller_config
);
    localparam [2:0] STOP=0, PUSH=1, PULL=2, WAIT_PEAK=3, BALANCE=4, FAULT=5, MOTOR_TEST=6;
    reg [31:0] pulse_count, check_count, swing_count, angle_count, position_count;
    reg positive_first;
    reg [11:0] previous, older;
    reg [1:0] history_count;
    reg signed [31:0] origin;
    // Capture the same wide travel window with origin. A direct comparator
    // preserves immediate shutdown without a subtraction+clamp+compare chain.
    reg signed [32:0] travel_low,travel_high;
    wire signed [32:0] rel_w=$signed({position[31],position})-$signed({origin[31],origin});
    // Continuous accumulated coordinates; never choose a shortest circular path.
    wire signed [31:0] travel_position=rel_w>33'sd16000 ? 32'sd16000 :
                                     rel_w< -33'sd16000 ? -32'sd16000 : rel_w[31:0];
    wire travel_exceeded=(POSITION_LIMIT_COUNTS>=0 && POSITION_LIMIT_COUNTS<16000) ?
        ($signed({position[31],position})>travel_high || $signed({position[31],position})<travel_low) :
        (travel_position>POSITION_LIMIT_COUNTS || travel_position< -POSITION_LIMIT_COUNTS);
    wire signed [49:0] relative_position_q=$signed({rel_w[32],rel_w,16'd0});
    wire signed [49:0] position_error_w=$signed({{18{position_target_q[31]}},position_target_q})-relative_position_q;
    assign position_error_q=position_error_w>50'sd2147483647 ? 32'sh7fffffff :
                            position_error_w< -50'sd2147483648 ? 32'sh80000000 : position_error_w[31:0];
    assign relative_position=rel_w>33'sd2147483647 ? 32'sh7fffffff :
                             rel_w< -33'sd2147483648 ? 32'sh80000000 : rel_w[31:0];
    wire centered=({20'd0,sample}>CENTER-CAPTURE_RANGE) && ({20'd0,sample}<CENTER+CAPTURE_RANGE);
    wire prev_centered=({20'd0,previous}>CENTER-CAPTURE_RANGE) && ({20'd0,previous}<CENTER+CAPTURE_RANGE);
    wire swinging=(state==PUSH || state==PULL || state==WAIT_PEAK);
    assign running=swinging || (state==BALANCE) || (state==MOTOR_TEST);
    wire balance=(state==BALANCE);
    wire speed_selected=(ENABLE_VELOCITY!=0) ? outer_speed:1'b0;
    wire reset_pid=!balance;
    reg previous_speed;
    reg [15:0] speed_count;
    wire outer_clear=!balance || stop_cmd || !permit || fault_latched || previous_speed!=speed_selected;
    wire speed_tick=balance && sample_valid && (speed_count>=speed_period_ms-1);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin previous_speed<=0;speed_count<=0;end
        else begin
            previous_speed<=speed_selected;
            if(outer_clear || !speed_selected) speed_count<=0;
            else if(sample_valid) speed_count<=speed_tick ? 16'd0:speed_count+16'd1;
        end
    end
    wire angle_tick=balance && sample_valid && (angle_count==ANGLE_MS-1);
    wire [31:0] effective_position_ms=(RUNTIME_POSITION_PERIOD!=0) ? {16'd0,position_period_ms}:POSITION_MS;
    wire position_tick=balance && sample_valid && (position_count>=effective_position_ms-1);
    wire signed [31:0] angle_out, position_out;
    wire position_pid_update;
    // The period-config handshake must still advance while position PID is inactive.
    assign position_update=position_pid_update || (speed_selected && position_tick);
    assign angle_pid_q=angle_out;
    // Single source of truth for experiment metadata, including defparam builds.
    assign position_defaults={POSITION_KD,POSITION_KI,POSITION_KP};
    wire signed [31:0] pos_kp=RUNTIME_POSITION_GAINS ? position_kp_q:POSITION_KP;
    wire signed [31:0] pos_ki=RUNTIME_POSITION_GAINS ? position_ki_q:POSITION_KI;
    wire signed [31:0] pos_kd=RUNTIME_POSITION_GAINS ? position_kd_q:POSITION_KD;
    assign controller_config={POSITION_I_DECAY_RETAIN_PERCENT,POSITION_I_DECAY_BAND_Q,
        ANGLE_I_DEADBAND_Q,pos_kd,pos_ki,pos_kp,ANGLE_KD,ANGLE_KI,ANGLE_KP};
    wire signed [31:0] speed_out;
    wire signed [31:0] handover_out;
    wire signed [31:0] outer_out=speed_selected ? (handover_remaining!=0 ? handover_out:speed_out):position_out;
    wire [15:0] transition_t;
    assign applied_friction_t=(handover_remaining!=0) ? transition_t:speed_friction_t;
    outer_handover transfer(.clk(clk),.rst_n(rst_n),.clear(!balance || stop_cmd || !permit || fault_latched),
        .tick_ms(sample_valid),.start(switch_speed_cmd===1'b1),.position_out(position_out),.speed_out(speed_out),
        .friction_t(speed_friction_t),.remaining_ms(handover_remaining),.out_q(handover_out),.applied_t(transition_t));
    reg signed [31:0] measured_angle_q, measured_position_q, target_angle_q, target_position_q;
    generate if(ENABLE_VELOCITY!=0) begin: velocity_loop
        speed_outer #(.COUNTS_PER_REV(COUNTS_PER_REV),.MAX_SPEED(MAX_SPEED)) speed_pi (
            .clk(clk),.rst_n(rst_n),.clear(outer_clear || !speed_selected),.tick(speed_tick),
            .period_ms(speed_period_ms),.kp_q(speed_kp_q),.ki_q(speed_ki_q),.kd_q(speed_kd_q),.kpos_q(speed_kpos_q),
            .position_error_q(target_position_q),.reference_q(reference_velocity_q),.actual_q(actual_velocity_q),
            .target_q(speed_target_q),.out_q(speed_out),.valid(speed_update));
    end else begin: no_velocity_loop
        assign speed_target_q=0;assign speed_out=0;assign speed_update=0;
    end endgenerate
    assign angle_target_offset_q=-outer_out; // ADC-code Q16.16, not PWM percent
    wire signed [31:0] target_angle=(CENTER*65536)-outer_out;
    wire signed [31:0] measured_angle=$signed({4'b0,sample,16'b0});
    // Both PID loops update in milliseconds. One 50 MHz register of latency
    // separates sensor/encoder inputs and the two control arithmetic chains.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            measured_angle_q<=0;
            measured_position_q<=0;
            target_position_q<=0;
            target_angle_q<=CENTER*65536;
        end else begin
            measured_angle_q<=measured_angle;
            measured_position_q<=0;
            target_position_q<=position_error_q;
            target_angle_q<=target_angle;
        end
    end
    pid_fixed #(.PIPELINED_ARITH(PIPELINED_ANGLE_PID),.KP(ANGLE_KP),.KI(ANGLE_KI),.KD(ANGLE_KD),
        .I_DEADBAND_Q(ANGLE_I_DEADBAND_Q)) angle_pid (
        .clk(clk),.rst_n(rst_n),.clear(reset_pid),.tick(angle_tick),
        .runtime_kp_q(ANGLE_KP),.runtime_ki_q(ANGLE_KI),.runtime_kd_q(ANGLE_KD),
        .target_q(target_angle_q),.actual_q(measured_angle_q),.out_q(angle_out),.valid(angle_update));
    pid_fixed #(.RUNTIME_GAINS(RUNTIME_POSITION_GAINS),.KP(POSITION_KP),.KI(POSITION_KI),.KD(POSITION_KD),
        .I_DECAY_BAND_Q(POSITION_I_DECAY_BAND_Q),
        .I_DECAY_RETAIN_PERCENT(POSITION_I_DECAY_RETAIN_PERCENT),
        .DELTA_WRAP_Q(0)) position_pid (
        .clk(clk),.rst_n(rst_n),.clear(outer_clear || speed_selected),.tick(position_tick),
        .runtime_kp_q(position_kp_q),.runtime_ki_q(position_ki_q),.runtime_kd_q(position_kd_q),
        .target_q(target_position_q),.actual_q(measured_position_q),.out_q(position_out),.valid(position_pid_update));
    // Speed position correction also uses target_position_q above, separating
    // the wide coordinate-error arithmetic from the speed PID sample enable.
    // Capture the same registered measurement as angle_pid. The next clock
    // publishes both results together; later sensor changes cannot mix samples.
    // Distance is from fixed CENTER, independently of the outer-loop target.
    localparam integer BOOST_RANGE=(BALANCE_BOOST_RANGE_CODES<0) ? 0 :
                                   (BALANCE_BOOST_RANGE_CODES>4095) ? 4095 : BALANCE_BOOST_RANGE_CODES;
    localparam integer BOOST_MAX=(BALANCE_BOOST_MAX_PERCENT<0) ? 0 :
                                 (BALANCE_BOOST_MAX_PERCENT>100) ? 100 : BALANCE_BOOST_MAX_PERCENT;
    localparam [22:0] BOOST_MAX_Q=BOOST_MAX*23'd65536;
    wire signed [31:0] boost_offset=(measured_angle_q >>> 16)-CENTER;
    wire [31:0] boost_distance=boost_offset[31] ? -boost_offset : boost_offset;
    reg [11:0] boost_distance_q;
    reg [2:0] boost_sample_pending;
    reg [31:0] boost_magnitude_q;
    wire boost_enable=balance && sample_ready && permit && !fault_latched && !stop_cmd;
    // A bounded 12-bit distance times at most 100% Q16.16 fits in 35 bits.
    // Keep the constant divider this wide instead of inferring 64-bit hardware.
    wire [34:0] boost_product=boost_distance_q*BOOST_MAX_Q;
    wire [34:0] boost_scaled;
    generate if (BOOST_RANGE>0 && BOOST_MAX>0) begin: enabled_boost
        // Divide after scaling to retain sub-percentage-point additions.
        assign boost_scaled=boost_product/BOOST_RANGE;
    end else begin: disabled_boost
        assign boost_scaled=35'd0;
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            boost_distance_q<=0; boost_sample_pending<=0; boost_magnitude_q<=0;
        end else if (!boost_enable) begin
            boost_distance_q<=0; boost_sample_pending<=0; boost_magnitude_q<=0;
        end else begin
            boost_sample_pending<={boost_sample_pending[1:0],angle_tick};
            // Outside the compensation interval, capture zero before narrowing.
            if (angle_tick) boost_distance_q<=(boost_distance<=BOOST_RANGE) ? boost_distance[11:0] : 12'd0;
            if (PIPELINED_ANGLE_PID ? boost_sample_pending[2]:boost_sample_pending[0]) boost_magnitude_q<=boost_scaled[31:0];
        end
    end
    // Follow PID direction, including reverse braking; a zero PID stays zero.
    wire signed [32:0] boost_applied_q=(!boost_enable || angle_out==0) ? 33'sd0 :
        angle_out[31] ? -$signed({1'b0,boost_magnitude_q}) : $signed({1'b0,boost_magnitude_q});
    wire signed [32:0] balance_sum=$signed({angle_out[31],angle_out})+boost_applied_q;
    wire signed [31:0] balance_command=(balance_sum>33'sd6553600) ? 32'sd6553600 :
                                     (balance_sum< -33'sd6553600) ? -32'sd6553600 : balance_sum[31:0];
    wire signed [31:0] pulse_q=START_PERCENT*65536;
    localparam integer TEST_PERCENT=(MOTOR_TEST_PERCENT<0) ? 0 :
                                   (MOTOR_TEST_PERCENT>100) ? 100 : MOTOR_TEST_PERCENT;
    wire signed [31:0] test_q=TEST_PERCENT*65536;
    assign command_q=(!permit || fault_latched || stop_cmd) ? 32'sd0 :
                     state==PUSH ? (positive_first ? pulse_q : -pulse_q) :
                     state==PULL ? (positive_first ? -pulse_q : pulse_q) :
                     state==MOTOR_TEST ? ((MOTOR_TEST_REVERSE!=0) ? -test_q : test_q) :
                     balance ? balance_command : 32'sd0;
    always @* begin
        request_fault=0;
        if (state>MOTOR_TEST) request_fault=8;
        else if (running && travel_exceeded) request_fault=7;
        else if (balance && sample_valid && !centered) request_fault=5;
        else if (swinging && swing_count>=SWING_TIMEOUT_MS) request_fault=6;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            travel_low<=-33'sd1*POSITION_LIMIT_COUNTS;travel_high<=POSITION_LIMIT_COUNTS;protocol_position<=0;start_accepted<=0;state<=STOP; pulse_count<=0; check_count<=0; swing_count<=0;
            angle_count<=0; position_count<=0; positive_first<=1;
            previous<=0; older<=0; history_count<=0; origin<=0;
        end else begin
          protocol_position<=relative_position;
          if (fault_latched) begin start_accepted<=0;state<=FAULT;end
        else if (stop_cmd || state==FAULT) begin
            start_accepted<=0;
            state<=STOP; angle_count<=0; position_count<=0;
        end else if (state==STOP) begin
            start_accepted<=0;
            // Manual balance accepts only a fresh command inside the upright
            // window. Rejected requests are not queued; running modes ignore it.
            if ((start_cmd || motor_test_cmd || (balance_cmd && centered)) &&
                permit && sample_ready) begin
                start_accepted<=1;state<=start_cmd ? PUSH : motor_test_cmd ? MOTOR_TEST : BALANCE;
                pulse_count<=0; check_count<=0; swing_count<=0;
                angle_count<=0; position_count<=0; positive_first<=1;
                history_count<=0; previous<=0; older<=0; origin<=position;protocol_position<=0;
                travel_low<=$signed({position[31],position})-POSITION_LIMIT_COUNTS;travel_high<=$signed({position[31],position})+POSITION_LIMIT_COUNTS;
            end
        end else if (sample_valid) begin
            start_accepted<=0;
            if (swinging && swing_count<SWING_TIMEOUT_MS) swing_count<=swing_count+1;
            case(state)
                PUSH: if (pulse_count==PULSE_MS-1) begin pulse_count<=0; state<=PULL; end
                      else pulse_count<=pulse_count+1;
                PULL: if (pulse_count==PULSE_MS-1) begin pulse_count<=0; check_count<=0; state<=WAIT_PEAK; end
                      else pulse_count<=pulse_count+1;
                WAIT_PEAK: begin
                    if (check_count==CHECK_MS-1) begin
                        check_count<=0; older<=previous; previous<=sample;
                        if (history_count<2'd2) history_count<=history_count+2'd1;
                        if (history_count>=1 && centered && prev_centered) begin
                            state<=BALANCE; origin<=position;protocol_position<=0;
                travel_low<=$signed({position[31],position})-POSITION_LIMIT_COUNTS;travel_high<=$signed({position[31],position})+POSITION_LIMIT_COUNTS; angle_count<=0; position_count<=0;
                        end else if (history_count>=2) begin
                            if ({20'd0,sample}>CENTER+CAPTURE_RANGE && {20'd0,previous}>CENTER+CAPTURE_RANGE &&
                                {20'd0,older}>CENTER+CAPTURE_RANGE && previous<sample && previous<older) begin
                                state<=PUSH; positive_first<=1; pulse_count<=0;
                            end else if ({20'd0,sample}<CENTER-CAPTURE_RANGE && {20'd0,previous}<CENTER-CAPTURE_RANGE &&
                                {20'd0,older}<CENTER-CAPTURE_RANGE && previous>sample && previous>older) begin
                                state<=PUSH; positive_first<=0; pulse_count<=0;
                            end
                        end
                    end else check_count<=check_count+1;
                end
                BALANCE: begin
                    angle_count<=angle_tick ? 0 : angle_count+1;
                    position_count<=position_tick ? 0 : position_count+1;
                end
                // Fixed PWM test: no angle/position PID and no swing-up timer.
                // Position limits and top-level sensor faults still inhibit it.
                MOTOR_TEST: begin end
                default: state<=FAULT;
            endcase
        end else start_accepted<=0;
        end
    end
endmodule
