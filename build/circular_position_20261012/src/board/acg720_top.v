`timescale 1ns/1ps
// ACG720 + Jiangxie TB6612 board-level integration.
// The analog signal is ACG720 P5-1 (ADC128S102 IN0); the four digital ADC
// balls are M6/M5/P6/N5 and are constrained in constraints/acg720.cst.
module acg720_top #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer BAUD=115200,
    parameter integer ADC_HALF_DIV=2,
    parameter integer PWM_HZ=20000,
    parameter integer ENCODER_INVERT=0,
    parameter integer MOTOR_INVERT=1,
    parameter integer COUNTS_PER_REV=408,
    parameter integer KEY_DEBOUNCE_MS=20,
    parameter integer CW_POSITIVE=1,
    parameter integer MOVE_DEG_PER_SEC=30,
    parameter integer MOTOR_TEST_PERCENT=20,
    parameter integer MOTOR_TEST_REVERSE=0,
    // Arm speed damping: Q16.16 PWM percent/count in each 5 ms window.
    parameter signed [31:0] ARM_DAMPING_KD=55536,
    parameter integer ARM_DAMPING_LIMIT_PERCENT=20,
    // User measured upright (stationary) ADC code on 2026-10-09.
    parameter integer CENTER=1005,
    parameter integer ANGLE_ADC_ZERO=CENTER,
    parameter integer ANGLE_ADC_SPAN=4095,
    parameter integer ANGLE_RANGE_TENTHS=3330,
    parameter integer ANGLE_INVERT=0,
    parameter integer CAPTURE_RANGE=500,
    parameter integer PULSE_MS=120,
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
    wire reset_n;
    clock_reset reset_conditioner(.clk(clk),.arst_n(rst_n),.locked(1'b1),.rst_n(reset_n));

    wire start_cmd, uart_start_cmd, stop_cmd, uart_stop_cmd, clear_cmd;
    wire [7:0] received_byte;
    wire received_valid;
    wire [7:0] telemetry_byte;
    wire telemetry_valid, telemetry_active, uart_tx_ready;
    reg display_raw;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) display_raw<=0;
        else if (received_valid) begin
            if (received_byte==8'h44) display_raw<=1; // D: raw ADC (decimal)
            else if (received_byte==8'h41) display_raw<=0; // A: signed angle
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
    wire motor_test_cmd=(key_press==4'b0010);
    wire balance_cmd=(key_press==4'b0100);
    assign stop_cmd=uart_stop_cmd || key_press[3];
    uart_commands #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.TELEMETRY(1)) uart (
        .clk(clk),.rst_n(reset_n),.rx(uart_rx),.tx(uart_tx),
        .start_cmd(uart_start_cmd),.stop_cmd(uart_stop_cmd),.clear_cmd(clear_cmd),
        .received_byte(received_byte),.received_valid(received_valid),
        .tx_data(telemetry_byte),.tx_valid(telemetry_valid),
        .tx_frame_active(telemetry_active),.tx_ready(uart_tx_ready));

    wire [11:0] sample;
    wire sample_valid, sample_ready;
    wire [3:0] sensor_fault;
    sensor_if #(.CLK_HZ(CLK_HZ),.ADC_HALF_DIV(ADC_HALF_DIV),
                .RAIL_LIMIT_SAMPLES(RAIL_LIMIT_SAMPLES)) sensor (
        .clk(clk),.rst_n(reset_n),.dout(board_adc_dout),
        .cs_n(board_adc_cs_n),.sclk(board_adc_sclk),.din(board_adc_din),
        .sample(sample),.sample_valid(sample_valid),.ready(sample_ready),
        .error_code(sensor_fault));

    wire signed [31:0] raw_position, raw_position_modulo, velocity_unused, delta_unused;
    encoder_qei #(.CLK_HZ(CLK_HZ),.COUNTS_PER_REV(COUNTS_PER_REV)) encoder (
        .clk(clk),.rst_n(reset_n),.enc_a(enc_a),.enc_b(enc_b),
        .tick_speed(sample_valid),.position(raw_position),
        .vel(velocity_unused),.delta(delta_unused),.position_modulo(raw_position_modulo));
    wire signed [31:0] position=(ENCODER_INVERT!=0) ? -raw_position : raw_position;
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
        .clk(clk),.rst_n(reset_n),.raw_count(raw_position),.position_count(position_modulo),
        .relative_count(relative_position),.scl(oled_scl),.sda(oled_sda),
        .initialized(oled_initialized),.error(oled_error),.frame_done(oled_frame_done));
    wire angle_update, position_update;
    wire signed [31:0] position_error_q, angle_target_offset_q;
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
    wire signed [31:0] position_goal_q, position_target_q;
    wire move_enable=(state==3'd4) && permit && !fault_latched && !stop_cmd && (internal_fault==0);
    position_target #(.COUNTS_PER_REV(COUNTS_PER_REV),.CW_POSITIVE(CW_POSITIVE),
        .MOVE_DEG_PER_SEC(MOVE_DEG_PER_SEC),.POSITION_LIMIT_COUNTS(COUNTS_PER_REV*10)) target (
        .clk(clk),.rst_n(control_reset_n),.enable(move_enable),.tick_ms(sample_valid),
        // K3 now starts manual balance. Hold the captured arm position.
        .move_cmd(3'b000),
        .goal_q(position_goal_q),.target_q(position_target_q));

    safety_monitor safety(
        .clk(clk),.rst_n(control_reset_n),
        .clear_fault(clear_cmd),.running(running),.internal_fault(internal_fault),
        .permit(permit),.latched(fault_latched),.code(fault_code));

    control_core #(.CENTER(CENTER),.CAPTURE_RANGE(CAPTURE_RANGE),.PULSE_MS(PULSE_MS),
        .CHECK_MS(CHECK_MS),.SWING_TIMEOUT_MS(SWING_TIMEOUT_MS),
        .MOTOR_TEST_PERCENT(MOTOR_TEST_PERCENT),.MOTOR_TEST_REVERSE(MOTOR_TEST_REVERSE),
        .ARM_DAMPING_KD(ARM_DAMPING_KD),.ARM_DAMPING_LIMIT_PERCENT(ARM_DAMPING_LIMIT_PERCENT),
        .POSITION_LIMIT_COUNTS(COUNTS_PER_REV*10),.COUNTS_PER_REV(COUNTS_PER_REV)) core (
        .clk(clk),.rst_n(control_reset_n),.sample_valid(sample_valid),.sample_ready(sample_ready),
        .sample(sample),.position(position),.position_target_q(position_target_q),
        .start_cmd(start_cmd),.motor_test_cmd(motor_test_cmd),.balance_cmd(balance_cmd),.stop_cmd(stop_cmd),
        .permit(permit),.fault_latched(fault_latched),.running(running),
        .command_q(command_q),.state(state),.request_fault(core_fault),
        .relative_position(relative_position),.angle_update(angle_update),
        .position_update(position_update),.position_error_q(position_error_q),
        .angle_target_offset_q(angle_target_offset_q));

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
    wire signed [32:0] command_ext={command_q[31],command_q};
    wire [32:0] command_abs=command_q[31] ? -command_ext : command_ext;
    wire [22:0] command_abs_limited=(command_abs>HUNDRED_PERCENT_Q) ?
                                     HUNDRED_PERCENT_Q[22:0] : command_abs[22:0];
    reg [22:0] command_mag_q;
    reg command_negative_q;
    always @(posedge clk or negedge control_reset_n) begin
        if (!control_reset_n) begin command_mag_q<=0; command_negative_q<=0; end
        else begin
            command_mag_q<=command_abs_limited;
            command_negative_q<=command_q[31] ^ (MOTOR_INVERT!=0);
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

    reg signed [15:0] pwm_command;
    always @(posedge clk or negedge control_reset_n) begin
        if (!control_reset_n) pwm_command<=0;
        else pwm_command<=command_negative_q ? -$signed(duty_magnitude) :
                                                $signed(duty_magnitude);
    end
    wire pwm_raw, in1_raw, in2_raw;
    wire signed [15:0] applied_pwm;
    pwm_motor #(.PWM_MAX(PWM_MAX)) motor (
        .clk(clk),.rst_n(control_reset_n),.enable(motor_ready),.brake(!motor_ready),
        .cmd(pwm_command),.pwm(pwm_raw),.in1(in1_raw),.in2(in2_raw),
        .applied_cmd(applied_pwm));
    // Undo only the physical wiring inversion: both fields use control sign.
    wire signed [15:0] requested_pwm=(MOTOR_INVERT!=0) ? -pwm_command : pwm_command;
    wire signed [15:0] actual_pwm=(MOTOR_INVERT!=0) ? -applied_pwm : applied_pwm;
    // Registered metadata conversion. Offset units are 0.1 ADC code; the website
    // converts to degrees using the same calibrated display scale.
    wire signed [63:0] offset_tenths_w=$signed(angle_target_offset_q)*64'sd10;
    reg signed [15:0] target_offset_adc_tenths, position_target_counts, position_error_counts;
    always @(posedge clk or negedge control_reset_n) begin
        if (!control_reset_n) begin
            target_offset_adc_tenths<=0; position_target_counts<=0; position_error_counts<=0;
        end else begin
            target_offset_adc_tenths<=offset_tenths_w/64'sd65536;
            position_target_counts<=position_target_q/32'sd65536;
            position_error_counts<=position_error_q/32'sd65536;
        end
    end
    uart_telemetry #(.CLK_HZ(CLK_HZ),.POSITION_FIELDS(1)) telemetry (
        .clk(clk),.rst_n(reset_n),.received_byte(received_byte),.received_valid(received_valid),
        .angle_tenths(displayed_angle),.angle_valid(display_angle_valid),
        .requested_pwm(requested_pwm),.actual_pwm(actual_pwm),
        .arm_position(relative_position[15:0]),.position_target(position_target_counts),
        .position_error(position_error_counts),.target_offset_adc_tenths(target_offset_adc_tenths),
        .tx_data(telemetry_byte),.tx_valid(telemetry_valid),.tx_ready(uart_tx_ready),
        .frame_active(telemetry_active));
    assign pwm_a=motor_ready && pwm_raw;
    assign ain1=motor_ready && in1_raw;
    assign ain2=motor_ready && in2_raw;
    assign dbg_tick=sample_valid;

endmodule
