`timescale 1ns/1ps
// Jiangxie program 16: pulse swing-up, angle PID at 5 ms, position PID at 50 ms.
// One sample_valid represents 1 ms. Angle is an ADC code, not degrees.
module control_core #(
    parameter integer CENTER=1014, CAPTURE_RANGE=500,
    parameter integer START_PERCENT=45, PULSE_MS=100, CHECK_MS=40,
    parameter integer ANGLE_MS=5, POSITION_MS=50, SWING_TIMEOUT_MS=15000,
    parameter integer POSITION_LIMIT_COUNTS=4080,
    parameter integer MOTOR_TEST_PERCENT=20, MOTOR_TEST_REVERSE=0,
    parameter signed [31:0] ANGLE_KP=29661, ANGLE_KI=0, ANGLE_KD=35214,
    parameter signed [31:0] POSITION_KP=4641, POSITION_KI=0, POSITION_KD=7581,
    // Q16.16 percent per encoder count over ANGLE_MS; zero disables damping.
    parameter signed [31:0] ARM_DAMPING_KD=35536,
    parameter integer ARM_DAMPING_LIMIT_PERCENT=20,
    parameter integer COUNTS_PER_REV=408
) (
    input wire clk, rst_n, sample_valid, sample_ready,
    input wire [11:0] sample,
    input wire signed [31:0] position,
    input wire signed [31:0] position_target_q,
    input wire start_cmd, motor_test_cmd, balance_cmd, stop_cmd, permit, fault_latched,
    output wire running,
    output wire signed [31:0] command_q,
    output reg [2:0] state,
    output reg [3:0] request_fault,
    output wire signed [31:0] relative_position,
    output wire angle_update, position_update,
    output wire signed [31:0] position_error_q, angle_target_offset_q
);
    localparam [2:0] STOP=0, PUSH=1, PULL=2, WAIT_PEAK=3, BALANCE=4, FAULT=5, MOTOR_TEST=6;
    reg [31:0] pulse_count, check_count, swing_count, angle_count, position_count;
    reg positive_first;
    reg [11:0] previous, older;
    reg [1:0] history_count;
    reg signed [31:0] origin;
    wire signed [32:0] rel_w=$signed({position[31],position})-$signed({origin[31],origin});
    // Travel protection continues to use total displacement, independently of
    // the circular feedback coordinate. A full revolution is zero position error.
    wire signed [31:0] travel_position=rel_w>33'sd16000 ? 32'sd16000 :
                                     rel_w< -33'sd16000 ? -32'sd16000 : rel_w[31:0];
    wire signed [49:0] relative_position_q=$signed({rel_w[32],rel_w,16'd0});
    wire signed [49:0] position_error_w=$signed({{18{position_target_q[31]}},position_target_q})-relative_position_q;
    wire signed [31:0] wrapped_position_q;
    wire position_valid, position_error_valid;
    position_wrap #(.COUNTS_PER_REV(COUNTS_PER_REV)) wrap_position (
        .clk(clk),.rst_n(rst_n),.value_q(relative_position_q),.wrapped_q(wrapped_position_q),.valid(position_valid));
    position_wrap #(.COUNTS_PER_REV(COUNTS_PER_REV)) wrap_error (
        .clk(clk),.rst_n(rst_n),.value_q(position_error_w),.wrapped_q(position_error_q),.valid(position_error_valid));
    assign relative_position=wrapped_position_q/32'sd65536;
    wire centered=({20'd0,sample}>CENTER-CAPTURE_RANGE) && ({20'd0,sample}<CENTER+CAPTURE_RANGE);
    wire prev_centered=({20'd0,previous}>CENTER-CAPTURE_RANGE) && ({20'd0,previous}<CENTER+CAPTURE_RANGE);
    wire swinging=(state==PUSH || state==PULL || state==WAIT_PEAK);
    assign running=swinging || (state==BALANCE) || (state==MOTOR_TEST);
    wire balance=(state==BALANCE);
    wire reset_pid=!balance;
    wire angle_tick=balance && sample_valid && (angle_count==ANGLE_MS-1);
    wire position_tick=balance && sample_valid && (position_count==POSITION_MS-1);
    wire signed [31:0] angle_out, position_out;
    assign angle_target_offset_q=-position_out; // ADC-code Q16.16, not PWM percent
    wire signed [31:0] target_angle=(CENTER*65536)-position_out;
    wire signed [31:0] measured_angle=$signed({4'b0,sample,16'b0});
    // Both PID loops update in milliseconds. One 50 MHz register of latency
    // separates sensor/encoder inputs and the two control arithmetic chains.
    reg signed [31:0] measured_angle_q, measured_position_q, target_angle_q, target_position_q;
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
    pid_fixed #(.KP(ANGLE_KP),.KI(ANGLE_KI),.KD(ANGLE_KD)) angle_pid (
        .clk(clk),.rst_n(rst_n),.clear(reset_pid),.tick(angle_tick),
        .target_q(target_angle_q),.actual_q(measured_angle_q),.out_q(angle_out),.valid(angle_update));
    pid_fixed #(.KP(POSITION_KP),.KI(POSITION_KI),.KD(POSITION_KD),
        .DELTA_WRAP_Q(COUNTS_PER_REV*65536)) position_pid (
        .clk(clk),.rst_n(rst_n),.clear(reset_pid),.tick(position_tick && position_error_valid),
        .target_q(target_position_q),.actual_q(measured_position_q),.out_q(position_out),.valid(position_update));
    // Independent arm velocity feedback at the angle-loop cadence. Use the
    // direction-corrected absolute encoder, not origin-relative/clamped position:
    // capturing an origin must not create a velocity impulse. Modular subtraction
    // also preserves small movements across the signed encoder counter wrap.
    localparam integer DAMPING_LIMIT=(ARM_DAMPING_LIMIT_PERCENT<0) ? 0 :
                                    (ARM_DAMPING_LIMIT_PERCENT>100) ? 100 : ARM_DAMPING_LIMIT_PERCENT;
    localparam signed [63:0] DAMPING_LIMIT_Q=DAMPING_LIMIT*64'sd65536;
    localparam signed [31:0] DAMPING_GAIN=(ARM_DAMPING_KD<0) ? 32'sd0 : ARM_DAMPING_KD;
    reg signed [31:0] arm_previous_position, arm_delta;
    reg arm_sample_pending;
    reg signed [31:0] arm_damping_q;
    wire arm_damping_enable=balance && centered && sample_ready &&
                            permit && !fault_latched && !stop_cmd;
    wire signed [31:0] arm_damping_applied_q=arm_damping_enable ? arm_damping_q : 32'sd0;
    wire signed [63:0] arm_damping_product=$signed(arm_delta)*$signed(DAMPING_GAIN);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arm_previous_position<=0; arm_delta<=0;
            arm_sample_pending<=0; arm_damping_q<=0;
        end else if (!arm_damping_enable) begin
            arm_previous_position<=position; arm_delta<=0;
            arm_sample_pending<=0; arm_damping_q<=0;
        end else begin
            arm_sample_pending<=angle_tick;
            if (angle_tick) begin
                arm_delta<=position-arm_previous_position;
                arm_previous_position<=position;
            end
            // Same one-clock arithmetic stage as angle_pid: both terms are
            // published together, and no combinational multiplier reaches PWM.
            if (arm_sample_pending) begin
                if (arm_damping_product>DAMPING_LIMIT_Q) arm_damping_q<=DAMPING_LIMIT_Q[31:0];
                else if (arm_damping_product< -DAMPING_LIMIT_Q) arm_damping_q<=-DAMPING_LIMIT_Q[31:0];
                else arm_damping_q<=arm_damping_product[31:0];
            end
        end
    end
    wire signed [32:0] balance_sum=$signed({angle_out[31],angle_out})-
                                  $signed({arm_damping_applied_q[31],arm_damping_applied_q});
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
        else if (running && (travel_position>POSITION_LIMIT_COUNTS || travel_position< -POSITION_LIMIT_COUNTS)) request_fault=7;
        else if (balance && sample_valid && !centered) request_fault=5;
        else if (swinging && swing_count>=SWING_TIMEOUT_MS) request_fault=6;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=STOP; pulse_count<=0; check_count<=0; swing_count<=0;
            angle_count<=0; position_count<=0; positive_first<=1;
            previous<=0; older<=0; history_count<=0; origin<=0;
        end else if (fault_latched) state<=FAULT;
        else if (stop_cmd || state==FAULT) begin
            state<=STOP; angle_count<=0; position_count<=0;
        end else if (state==STOP) begin
            // Manual balance accepts only a fresh command inside the upright
            // window. Rejected requests are not queued; running modes ignore it.
            if ((start_cmd || motor_test_cmd || (balance_cmd && centered)) &&
                permit && sample_ready) begin
                state<=start_cmd ? PUSH : motor_test_cmd ? MOTOR_TEST : BALANCE;
                pulse_count<=0; check_count<=0; swing_count<=0;
                angle_count<=0; position_count<=0; positive_first<=1;
                history_count<=0; previous<=0; older<=0; origin<=position;
            end
        end else if (sample_valid) begin
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
                            state<=BALANCE; origin<=position; angle_count<=0; position_count<=0;
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
        end
    end
endmodule
