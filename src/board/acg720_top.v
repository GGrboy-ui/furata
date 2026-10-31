`timescale 1ns/1ps
// ACG720 + Jiangxie TB6612 board-level integration.
// The analog signal is ACG720 P5-1 (ADC128S102 IN0); the four digital ADC
// balls are M6/M5/P6/N5 and are constrained in constraints/acg720.cst.
module acg720_top #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer BAUD=115200,
    parameter integer ADC_HALF_DIV=2,
    parameter integer PWM_HZ=20000,
    // Duty counts per PWM period: 16 = 12.8 percentage points/ms at 20 kHz.
    parameter [15:0] PWM_SLEW_STEP=16'd16,
    parameter integer ENCODER_INVERT=0,
    parameter integer MOTOR_INVERT=1,
    parameter integer COUNTS_PER_REV=408,
    parameter integer KEY_DEBOUNCE_MS=20,
    parameter integer CW_POSITIVE=1,
    parameter integer POSITION_MS=50,
    parameter integer DEFAULT_OUTER_SPEED=0,
    parameter integer MOVE_DEG_PER_SEC=30,
    parameter integer MOTOR_TEST_PERCENT=20,
    parameter integer MOTOR_TEST_REVERSE=0,
    // Linear duty addition around CENTER; tenths of a degree / percentage points.
    // Zero width or zero maximum disables the addition; rebuild after tuning.
    parameter integer BALANCE_BOOST_RANGE_TENTHS=20,
    parameter integer BALANCE_BOOST_MAX_PERCENT=0,
    // User measured upright (stationary) ADC code on 2026-10-09.
    parameter integer CENTER=3124,
    parameter integer ANGLE_ADC_ZERO=CENTER,
    parameter integer ANGLE_ADC_SPAN=4095,
    parameter integer ANGLE_RANGE_TENTHS=3330,
    parameter integer ANGLE_INVERT=0,
    parameter integer CAPTURE_RANGE=500,
    parameter integer PULSE_MS=100,
    parameter integer CHECK_MS=40,
    parameter integer SWING_TIMEOUT_MS=15000,
    parameter integer RAIL_LIMIT_SAMPLES=500,
    parameter integer OLED_I2C_HZ=100_000,
    parameter [6:0] OLED_ADDRESS=7'h3c,
    parameter integer OLED_COLUMN_OFFSET=0,
    parameter integer OLED_POWER_WAIT_MS=100,
    parameter integer OLED_REFRESH_MS=100
) (
    input wire clk, rst_n, uart_rx, enc_a, enc_b,
    input wire board_adc_dout,
    input wire key1_n, key2_n, key3_n, key4_n,
    output wire uart_tx, pwm_a, ain1, ain2, stby_fpga, dbg_tick,
    output wire board_adc_cs_n, board_adc_din, board_adc_sclk,
    output wire seg7_sclk, seg7_rclk, seg7_dio,
    inout wire oled_scl, oled_sda
);
    localparam integer PWM_MAX=CLK_HZ/PWM_HZ;
    localparam integer WAKE_CYCLES=(CLK_HZ/1000)*2;
    // Round inward to raw ADC codes: default +/-24 codes is about +/-1.95 deg.
    localparam integer BALANCE_BOOST_RANGE_CODES=
        (BALANCE_BOOST_RANGE_TENTHS>0 && ANGLE_ADC_SPAN>0 && ANGLE_RANGE_TENTHS>0) ?
        (BALANCE_BOOST_RANGE_TENTHS*64'sd1*ANGLE_ADC_SPAN)/ANGLE_RANGE_TENTHS : 0;
    wire reset_n;
    clock_reset reset_conditioner(.clk(clk),.arst_n(rst_n),.locked(1'b1),.rst_n(reset_n));

    wire start_cmd, uart_start_cmd, stop_cmd, uart_stop_cmd, clear_cmd;
    wire [7:0] received_byte;
    wire received_valid,legacy_valid;
    wire [7:0] arm_rx_byte,trajectory_rx_byte;
    wire arm_rx_valid,trajectory_rx_valid;
    command_router #(.CLK_HZ(CLK_HZ)) router(
        .clk(clk),.rst_n(reset_n),.data(received_byte),.valid(received_valid),
        .arm_data(arm_rx_byte),.arm_valid(arm_rx_valid),
        .trajectory_data(trajectory_rx_byte),.trajectory_valid(trajectory_rx_valid));
    wire [7:0] arm_byte;
    wire arm_valid,arm_pending,arm_busy,arm_load;
    wire arm_tx_active,trajectory_tx_active,trajectory_tx_valid,trajectory_tx_pending;
    wire [7:0] trajectory_tx_byte;
    wire signed [31:0] arm_goal_q,arm_origin_q;

    wire [7:0] telemetry_byte;
    wire telemetry_valid, telemetry_active, uart_tx_ready;
    reg display_raw;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) display_raw<=0;
        else if (legacy_valid) begin
            if (arm_rx_byte==8'h44) display_raw<=1; // D: raw ADC (decimal)
            else if (arm_rx_byte==8'h41) display_raw<=0; // A: signed angle
        end
    end
    wire [3:0] key_press;
    key_input #(.DEBOUNCE_CYCLES((CLK_HZ/1000)*KEY_DEBOUNCE_MS)) keys (
        .clk(clk),.rst_n(reset_n),.key_n({key4_n,key3_n,key2_n,key1_n}),.press(key_press));
    // K4 resets the control/motor path, while ADC, display and key scanning
    // continue. Conditioning makes reset release synchronous and requires a
    // fresh key event before another run. K4 wins over simultaneous starts.
    wire control_reset_n;
    clock_reset control_reset_conditioner (
        .clk(clk),.arst_n(reset_n && !key_press[3]),.locked(1'b1),.rst_n(control_reset_n));
    assign start_cmd=!key_press[3] && (uart_start_cmd || (key_press==4'b0001));
    wire motor_test_cmd=1'b0; // K2 now exclusively selects the speed outer loop in BALANCE.
    wire balance_cmd=(key_press==4'b0100);
    assign stop_cmd=uart_stop_cmd || key_press[3];
    uart_commands #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.TELEMETRY(1),.FRAMED(1)) uart (
        .clk(clk),.rst_n(reset_n),.rx(uart_rx),.tx(uart_tx),
        .start_cmd(uart_start_cmd),.stop_cmd(uart_stop_cmd),.clear_cmd(clear_cmd),
        .received_byte(received_byte),.received_valid(received_valid),
        .tx_data(trajectory_tx_valid ? trajectory_tx_byte:arm_valid ? arm_byte : telemetry_byte),
        .tx_valid(trajectory_tx_valid || arm_valid || telemetry_valid),
        .tx_frame_active(telemetry_active || arm_pending || trajectory_tx_pending),.tx_ready(uart_tx_ready));

    wire [11:0] sample;
    wire sample_valid, sample_ready;
    wire [3:0] sensor_fault;
    sensor_if #(.CLK_HZ(CLK_HZ),.ADC_HALF_DIV(ADC_HALF_DIV),
                .RAIL_LIMIT_SAMPLES(RAIL_LIMIT_SAMPLES)) sensor (
        .clk(clk),.rst_n(reset_n),.dout(board_adc_dout),
        .cs_n(board_adc_cs_n),.sclk(board_adc_sclk),.din(board_adc_din),
        .sample(sample),.sample_valid(sample_valid),.ready(sample_ready),
        .error_code(sensor_fault));

    wire signed [31:0] raw_position, raw_position_modulo, velocity_unused, delta_unused, raw_control_velocity_q;
    encoder_qei #(.CLK_HZ(CLK_HZ),.COUNTS_PER_REV(COUNTS_PER_REV)) encoder (
        .clk(clk),.rst_n(reset_n),.enc_a(enc_a),.enc_b(enc_b),
        .tick_speed(sample_valid),.position(raw_position),
        .control_velocity_q(raw_control_velocity_q),.vel(velocity_unused),.delta(delta_unused),.position_modulo(raw_position_modulo));
    wire signed [31:0] position=(ENCODER_INVERT!=0) ? -raw_position : raw_position;
    wire signed [31:0] control_velocity_q=(ENCODER_INVERT!=0) ? -raw_control_velocity_q:raw_control_velocity_q;
    wire signed [31:0] inverted_modulo=-raw_position_modulo;
    wire signed [31:0] position_modulo=(ENCODER_INVERT==0) ? raw_position_modulo :
        (inverted_modulo*2>=COUNTS_PER_REV) ? inverted_modulo-COUNTS_PER_REV : inverted_modulo;

    wire running, permit, fault_latched;
    wire [3:0] core_fault, fault_code;
    wire [2:0] state;
    wire signed [31:0] command_q, relative_position;
    // Display runs independently of motor/K4 reset; raw QEI resets only at rst_n.
    wire oled_initialized, oled_error, oled_frame_done;
    oled_encoder_display #(.CLK_HZ(CLK_HZ),.I2C_HZ(OLED_I2C_HZ),
        .ADDRESS(OLED_ADDRESS),.COLUMN_OFFSET(OLED_COLUMN_OFFSET),
        .POWER_WAIT_MS(OLED_POWER_WAIT_MS),.REFRESH_MS(OLED_REFRESH_MS)) oled (
        .clk(clk),.rst_n(reset_n),.raw_count(raw_position),.position_count(position),
        .relative_count(relative_position),.scl(oled_scl),.sda(oled_sda),
        .initialized(oled_initialized),.error(oled_error),.frame_done(oled_frame_done));
    wire angle_update, position_update;
    wire signed [31:0] position_error_q, angle_target_offset_q;
    wire signed [31:0] angle_pid_q;
    wire [287:0] controller_config;
    wire signed [15:0] requested_pwm,actual_pwm;
    wire [3:0] internal_fault=(sensor_fault!=0) ? sensor_fault : core_fault;
    wire [63:0] display_segments;
    wire signed [15:0] displayed_angle;
    wire [11:0] displayed_adc;
    wire display_angle_valid;
    angle_display_data #(.ADC_ZERO(ANGLE_ADC_ZERO),.ADC_SPAN(ANGLE_ADC_SPAN),
        .RANGE_TENTHS(ANGLE_RANGE_TENTHS),.INVERT(ANGLE_INVERT)) angle_display (
        .clk(clk),.rst_n(reset_n),.sample(sample),.sample_valid(sample_valid),
        .sample_ready(sample_ready),.sensor_fault(sensor_fault),.control_state(state),
        .fault_code(fault_latched ? fault_code : internal_fault),.raw_mode(display_raw),
        .segments(display_segments),.angle_tenths(displayed_angle),
        .display_adc(displayed_adc),.angle_valid(display_angle_valid));
    seg595_scan #(.CLK_HZ(CLK_HZ)) segment_driver (
        .clk(clk),.rst_n(reset_n),.segments(display_segments),
        .sclk(seg7_sclk),.rclk(seg7_rclk),.dio(seg7_dio));
    wire signed [31:0] position_goal_q,position_target_q,legacy_goal_q,legacy_target_q;
    wire signed [31:0] trajectory_target_q,trajectory_goal_q,trajectory_velocity_q,legacy_velocity_q;
    reg trajectory_selected;
    reg outer_speed;
    wire speed_update,start_accepted,switch_speed_cmd;
    wire [7:0] handover_remaining;
    wire [15:0] applied_friction_t;
    wire [95:0] position_defaults;
    wire signed [31:0] position_kp_q,position_ki_q,position_kd_q;
    wire [15:0] speed_period_ms,speed_friction_t;
    wire signed [31:0] speed_kp_q,speed_ki_q,speed_kd_q,speed_kpos_q,speed_target_q;
    wire signed [31:0] reference_velocity_q=trajectory_selected ? trajectory_velocity_q:legacy_velocity_q;
    wire trajectory_busy,trajectory_started,trajectory_event,trajectory_submit,period_request,period_pending,period_reply;
    wire [15:0] actual_position_ms,requested_period,trajectory_request_id,trajectory_id,trajectory_event_id;
    wire [7:0] trajectory_event_code,trajectory_status_code;
    wire [7:0] period_code=8'd0; // Legacy reply input is inactive (period_reply=0).
    wire [2:0] trajectory_mode,trajectory_phase,requested_mode;
    wire [3:0] trajectory_point,requested_count;
    wire [7:0] requested_cycles;
    wire [31:0] trajectory_elapsed,trajectory_total,requested_time,requested_dwell;
    wire [255:0] requested_angles;
    assign position_goal_q=trajectory_selected ? trajectory_goal_q:legacy_goal_q;
    assign position_target_q=trajectory_selected ? trajectory_target_q:legacy_target_q;
    assign switch_speed_cmd=(key_press==4'b0010) && state==4 && !outer_speed && permit && !fault_latched && internal_fault==0 &&
        control_reset_n && !stop_cmd && !arm_busy && !trajectory_busy && !trajectory_submit && !period_pending && !period_request && handover_remaining==0;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) outer_speed<=0;
        else if(start_accepted) outer_speed<=0;
        else if(switch_speed_cmd) outer_speed<=1;
    end
    wire signed [31:0] protocol_position;
    wire move_enable=(state==3'd4) && permit && !fault_latched && !stop_cmd && (internal_fault==0);
    position_target #(.REMOTE(1),.COUNTS_PER_REV(COUNTS_PER_REV),.CW_POSITIVE(CW_POSITIVE),
        .MOVE_DEG_PER_SEC(MOVE_DEG_PER_SEC),.POSITION_LIMIT_COUNTS(COUNTS_PER_REV*10)) target (
        .clk(clk),.rst_n(control_reset_n),.enable(move_enable),.tick_ms(sample_valid),
        // K3 now starts manual balance. Hold the captured arm position.
        .move_cmd(3'b000),.load(arm_load),.load_goal_q(arm_goal_q),.load_origin_q(arm_origin_q),
        .velocity_q(legacy_velocity_q),.goal_q(legacy_goal_q),.target_q(legacy_target_q));

    arm_move #(.CLK_HZ(CLK_HZ),.COUNTS_PER_REV(COUNTS_PER_REV),
        .MOVE_DEG_PER_SEC(MOVE_DEG_PER_SEC),.POSITION_LIMIT_COUNTS(COUNTS_PER_REV*10),
        .CW_POSITIVE(CW_POSITIVE)) arm (
        .clk(clk),.rst_n(reset_n),.tick_ms(sample_valid),.enable(move_enable),.stop_cmd(stop_cmd),
        .control_state(state),.position(protocol_position),.target_q(position_target_q),.goal_q(position_goal_q),
        .received_byte(arm_rx_byte),.received_valid(arm_rx_valid),.legacy_valid(legacy_valid),
        .load(arm_load),.load_goal_q(arm_goal_q),.load_origin_q(arm_origin_q),.busy(arm_busy),
        .tx_data(arm_byte),.tx_valid(arm_valid),.tx_pending(arm_pending),
        .tx_ready(uart_tx_ready && !trajectory_tx_active),
        .telemetry_active(telemetry_active || trajectory_tx_active),
        .motion_lock(trajectory_busy || period_pending || period_request || handover_remaining!=0 || switch_speed_cmd),.tx_active(arm_tx_active));

    safety_monitor safety(
        .clk(clk),.rst_n(control_reset_n),
        .clear_fault(clear_cmd),.running(running),.internal_fault(internal_fault),
        .permit(permit),.latched(fault_latched),.code(fault_code));

    control_core #(.PIPELINED_ANGLE_PID(1),.RUNTIME_POSITION_GAINS(1),.ENABLE_VELOCITY(1),.MAX_SPEED(MOVE_DEG_PER_SEC),.RUNTIME_POSITION_PERIOD(1),.POSITION_MS(POSITION_MS),.CENTER(CENTER),.CAPTURE_RANGE(CAPTURE_RANGE),.PULSE_MS(PULSE_MS),
        .CHECK_MS(CHECK_MS),.SWING_TIMEOUT_MS(SWING_TIMEOUT_MS),
        .MOTOR_TEST_PERCENT(MOTOR_TEST_PERCENT),.MOTOR_TEST_REVERSE(MOTOR_TEST_REVERSE),
        .BALANCE_BOOST_RANGE_CODES(BALANCE_BOOST_RANGE_CODES),
        .BALANCE_BOOST_MAX_PERCENT(BALANCE_BOOST_MAX_PERCENT),
        .POSITION_LIMIT_COUNTS(COUNTS_PER_REV*10),.COUNTS_PER_REV(COUNTS_PER_REV)) core (
        .clk(clk),.rst_n(control_reset_n),.sample_valid(sample_valid),.sample_ready(sample_ready),
        .sample(sample),.position(position),.position_target_q(position_target_q),
        .position_period_ms(actual_position_ms),.outer_speed(outer_speed),
        .position_kp_q(position_kp_q),.position_ki_q(position_ki_q),.position_kd_q(position_kd_q),
        .switch_speed_cmd(switch_speed_cmd),.speed_friction_t(speed_friction_t),.start_accepted(start_accepted),
        .position_defaults(position_defaults),.handover_remaining(handover_remaining),.applied_friction_t(applied_friction_t),.speed_period_ms(speed_period_ms),
        .speed_kp_q(speed_kp_q),.speed_ki_q(speed_ki_q),.speed_kd_q(speed_kd_q),.speed_kpos_q(speed_kpos_q),
        .reference_velocity_q(reference_velocity_q),.actual_velocity_q(control_velocity_q),
        .speed_target_q(speed_target_q),.speed_update(speed_update),
        .start_cmd(start_cmd),.motor_test_cmd(motor_test_cmd),.balance_cmd(balance_cmd),.stop_cmd(stop_cmd),
        .permit(permit),.fault_latched(fault_latched),.running(running),
        .command_q(command_q),.state(state),.request_fault(core_fault),
        .relative_position(relative_position),.protocol_position(protocol_position),.angle_update(angle_update),
        .position_update(position_update),.position_error_q(position_error_q),
        .angle_target_offset_q(angle_target_offset_q),.angle_pid_q(angle_pid_q),.controller_config(controller_config));

    // Both parameter banks are committed in the system-reset UART configuration domain.
    assign period_pending=1'b0;
    assign period_reply=1'b0;
    trajectory_engine #(.COUNTS_PER_REV(COUNTS_PER_REV),.POSITION_LIMIT_COUNTS(COUNTS_PER_REV*10),
        .CW_POSITIVE(CW_POSITIVE),.MAX_SPEED(MOVE_DEG_PER_SEC)) trajectory(
        .clk(clk),.rst_n(reset_n),.tick_ms(sample_valid),.enable(move_enable && outer_speed),.stop_cmd(stop_cmd),
        .external_busy(arm_busy || period_pending || period_request || handover_remaining!=0 || switch_speed_cmd),.submit(trajectory_submit),
        .request_id(trajectory_request_id),.request_mode(requested_mode),.request_time_ms(requested_time),
        .request_dwell_ms(requested_dwell),.request_cycles(requested_cycles),.request_count(requested_count),
        .request_angles(requested_angles),.position(protocol_position),.busy(trajectory_busy),
        .started(trajectory_started),.event_valid(trajectory_event),.active_id(trajectory_id),
        .event_id(trajectory_event_id),.event_code(trajectory_event_code),.status_code(trajectory_status_code),
        .mode(trajectory_mode),.phase(trajectory_phase),.point_index(trajectory_point),
        .elapsed_ms(trajectory_elapsed),.total_ms(trajectory_total),.target_q(trajectory_target_q),
        .goal_q(trajectory_goal_q),.velocity_q(trajectory_velocity_q));
    always @(posedge clk or negedge control_reset_n) begin
        if(!control_reset_n) trajectory_selected<=0;
        else if(!move_enable || arm_load) trajectory_selected<=0;
        else if(trajectory_started) trajectory_selected<=1;
    end
    trajectory_uart #(.CLK_HZ(CLK_HZ),.COUNTS_PER_REV(COUNTS_PER_REV),.LIMIT_COUNTS(COUNTS_PER_REV*10),
        .MAX_SPEED(MOVE_DEG_PER_SEC),.MAX_PWM(PWM_MAX),.DEFAULT_PERIOD(POSITION_MS),.DEFAULT_OUTER_SPEED(DEFAULT_OUTER_SPEED)) trajectory_protocol(
        .clk(clk),.rst_n(reset_n),.tick_ms(sample_valid),
        .received_byte(trajectory_rx_byte),.received_valid(trajectory_rx_valid),
        .speed_config_allowed(state==0 && permit && !fault_latched && internal_fault==0 && !arm_busy &&
            !trajectory_busy && !period_pending && !start_cmd && !motor_test_cmd && !balance_cmd && !stop_cmd),
        .outer_speed(outer_speed),.handover_remaining(handover_remaining),.position_defaults(position_defaults),
        .position_kp_q(position_kp_q),.position_ki_q(position_ki_q),.position_kd_q(position_kd_q),
        .speed_period_ms(speed_period_ms),.speed_friction_t(speed_friction_t),.speed_kp_q(speed_kp_q),
        .speed_ki_q(speed_ki_q),.speed_kd_q(speed_kd_q),.speed_kpos_q(speed_kpos_q),.speed_reference_q(reference_velocity_q),
        .speed_target_q(speed_target_q),.speed_actual_q(control_velocity_q),.speed_angle_offset_q(angle_target_offset_q),
        .submit(trajectory_submit),.period_request(period_request),.request_id(trajectory_request_id),
        .requested_period(requested_period),.request_mode(requested_mode),.request_time_ms(requested_time),
        .request_dwell_ms(requested_dwell),.request_cycles(requested_cycles),.request_count(requested_count),
        .request_angles(requested_angles),.event_valid(trajectory_event),.started(trajectory_started),
        .period_reply(period_reply),.event_id(trajectory_event_id),.actual_period(actual_position_ms),
        .active_id(trajectory_id),.event_code(trajectory_event_code),.period_code(period_code),
        .control_state(state),.phase(trajectory_phase),.mode(trajectory_mode),.point_index(trajectory_point),
        .elapsed_ms(trajectory_elapsed),.total_ms(trajectory_total),.position(protocol_position),
        .target_q(trajectory_target_q),.velocity_q(trajectory_velocity_q),.goal_q(trajectory_goal_q),
        .tx_data(trajectory_tx_byte),.tx_valid(trajectory_tx_valid),.tx_pending(trajectory_tx_pending),
        .tx_active(trajectory_tx_active),.tx_ready(uart_tx_ready),
        .tx_blocked(telemetry_active || arm_tx_active || (!trajectory_tx_active && arm_pending)));
    wire signed [31:0] final_command_q=command_q;

    // Assert STBY first, then allow the driver 2 ms to wake before PWM/IN change.
    // Keep the permission path combinational so a fault disables the outputs
    // without waiting for the clock or for the command pipeline below.
    wire run_allowed=control_reset_n && permit && running &&
                     !stop_cmd && (internal_fault==0);
    assign stby_fpga=run_allowed;
    reg [31:0] wake_count;
    wire wake_done=(wake_count>=WAKE_CYCLES);
    always @(posedge clk or negedge control_reset_n) begin
        if (!control_reset_n) wake_count<=0;
        else if (!run_allowed) wake_count<=0;
        else if (wake_count<WAKE_CYCLES) wake_count<=wake_count+1;
    end
    wire motor_ready=run_allowed && wake_done;

    // Convert signed Q16.16 percent to PWM counts in two registered stages.
    // Clamping before multiplication keeps the datapath small and makes even
    // -2^31 saturate safely. The safety gate above is independent of this latency.
    localparam [32:0] HUNDRED_PERCENT_Q=33'd6553600;
    wire signed [32:0] command_ext={final_command_q[31],final_command_q};
    wire [32:0] command_abs=final_command_q[31] ? -command_ext : command_ext;
    wire [22:0] command_abs_limited=(command_abs>HUNDRED_PERCENT_Q) ?
                                     HUNDRED_PERCENT_Q[22:0] : command_abs[22:0];
    reg [22:0] command_mag_q;
    reg command_negative_q;
    always @(posedge clk or negedge control_reset_n) begin
        if (!control_reset_n) begin command_mag_q<=0; command_negative_q<=0; end
        else begin
            command_mag_q<=command_abs_limited;
            command_negative_q<=final_command_q[31] ^ (MOTOR_INVERT!=0);
        end
    end

    wire [15:0] duty_magnitude;
    generate if ((PWM_MAX%100)==0) begin: exact_percent_scale
        // floor(Q16.16 * PWM_MAX / (100*65536)); constant 25 at 50 MHz.
        localparam integer COUNTS_PER_PERCENT=PWM_MAX/100;
        wire [38:0] duty_product=command_mag_q*COUNTS_PER_PERCENT;
        assign duty_magnitude=duty_product[31:16];
    end else begin: general_percent_scale
        wire [38:0] duty_product=command_mag_q*PWM_MAX;
        assign duty_magnitude=duty_product/39'd6553600;
    end endgenerate

    wire signed [15:0] pwm_command;
    pwm_friction #(.PWM_MAX(PWM_MAX)) speed_friction(
        .clk(clk),.rst_n(control_reset_n),
        .active(outer_speed && state==3'd4 && command_mag_q!=0),
        .negative(command_negative_q),.magnitude(duty_magnitude),.t_counts(applied_friction_t),
        .command(pwm_command));
    wire pwm_raw, in1_raw, in2_raw;
    wire signed [15:0] applied_pwm;
    pwm_motor #(.PWM_MAX(PWM_MAX),.SLEW_STEP(PWM_SLEW_STEP)) motor (
        .clk(clk),.rst_n(control_reset_n),.enable(motor_ready),.brake(!motor_ready),
        .cmd(pwm_command),.pwm(pwm_raw),.in1(in1_raw),.in2(in2_raw),
        .applied_cmd(applied_pwm));
    // Undo only the physical wiring inversion: both fields use control sign.
    assign requested_pwm=(MOTOR_INVERT!=0) ? -pwm_command : pwm_command;
    assign actual_pwm=(MOTOR_INVERT!=0) ? -applied_pwm : applied_pwm;
    // Registered metadata conversion. Offset units are 0.1 ADC code; the website
    // converts to degrees using the same calibrated display scale.
    reg signed [31:0] telemetry_offset_q;
    reg signed [63:0] offset_tenths_w;
    always @(posedge clk or negedge control_reset_n) begin
        if(!control_reset_n) begin telemetry_offset_q<=0;offset_tenths_w<=0;end
        else begin telemetry_offset_q<=angle_target_offset_q;offset_tenths_w<=$signed(telemetry_offset_q)*64'sd10;end
    end
    reg signed [15:0] target_offset_adc_tenths, position_target_counts, position_error_counts;
    function signed [15:0] telemetry_count16;
        input signed [63:0] value;
        begin
            if (value>64'sd32767) telemetry_count16=16'sh7fff;
            else if (value< -64'sd32768) telemetry_count16=16'sh8000;
            else telemetry_count16=value[15:0];
        end
    endfunction
    always @(posedge clk or negedge control_reset_n) begin
        if (!control_reset_n) begin
            target_offset_adc_tenths<=0; position_target_counts<=0; position_error_counts<=0;
        end else begin
            target_offset_adc_tenths<=telemetry_count16(offset_tenths_w/64'sd65536);
            position_target_counts<=telemetry_count16($signed(position_target_q)/64'sd65536);
            position_error_counts<=telemetry_count16($signed(position_error_q)/64'sd65536);
        end
    end
    uart_telemetry #(.CLK_HZ(CLK_HZ),.POSITION_FIELDS(1),.ARM_CHANNEL(1)) telemetry (
        .clk(clk),.rst_n(reset_n),.received_byte(arm_rx_byte),.received_valid(legacy_valid),
        .angle_tenths(displayed_angle),.angle_valid(display_angle_valid),
        .requested_pwm(requested_pwm),.actual_pwm(actual_pwm),
        .arm_position(relative_position[15:0]),.position_target(position_target_counts),
        .position_error(position_error_counts),.target_offset_adc_tenths(target_offset_adc_tenths),
        .tx_data(telemetry_byte),.tx_valid(telemetry_valid),.tx_ready(uart_tx_ready),.inhibit(arm_pending || trajectory_tx_pending),
        .frame_active(telemetry_active));
    assign pwm_a=motor_ready && pwm_raw;
    assign ain1=motor_ready && in1_raw;
    assign ain2=motor_ready && in2_raw;
    assign dbg_tick=sample_valid;

endmodule
