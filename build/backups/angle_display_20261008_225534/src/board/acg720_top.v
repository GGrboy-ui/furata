`timescale 1ns/1ps
// ACG720 + Jiangxie TB6612 board-level integration.
// The analog signal is ACG720 P5-1 (ADC128S102 IN0); the four digital ADC
// balls are M6/M5/P6/N5 and are constrained in constraints/acg720.cst.
module acg720_top #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer BAUD=115200,
    parameter integer ADC_HALF_DIV=2,
    parameter integer PWM_HZ=20000,
    parameter integer ENCODER_INVERT=1,
    parameter integer MOTOR_INVERT=1,
    parameter integer COUNTS_PER_REV=408,
    parameter integer KEY_DEBOUNCE_MS=20,
    parameter integer CW_POSITIVE=1,
    parameter integer MOVE_DEG_PER_SEC=30,
    parameter integer CENTER=2098,
    parameter integer CAPTURE_RANGE=500,
    parameter integer PULSE_MS=100,
    parameter integer CHECK_MS=40,
    parameter integer SWING_TIMEOUT_MS=15000,
    parameter integer RAIL_LIMIT_SAMPLES=500
) (
    input wire clk, rst_n, uart_rx, enc_a, enc_b,
    input wire board_adc_dout,
    input wire key1_n, key2_n, key3_n, key4_n,
    output wire uart_tx, pwm_a, ain1, ain2, stby_fpga, dbg_tick,
    output wire board_adc_cs_n, board_adc_din, board_adc_sclk
);
    localparam integer PWM_MAX=CLK_HZ/PWM_HZ;
    localparam integer WAKE_CYCLES=(CLK_HZ/1000)*2;
    wire reset_n;
    clock_reset reset_conditioner(.clk(clk),.arst_n(rst_n),.locked(1'b1),.rst_n(reset_n));

    wire start_cmd, uart_start_cmd, stop_cmd, clear_cmd;
    wire [3:0] key_press;
    key_input #(.DEBOUNCE_CYCLES((CLK_HZ/1000)*KEY_DEBOUNCE_MS)) keys (
        .clk(clk),.rst_n(reset_n),.key_n({key4_n,key3_n,key2_n,key1_n}),.press(key_press));
    assign start_cmd=uart_start_cmd || (key_press==4'b0001);
    uart_commands #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) uart (
        .clk(clk),.rst_n(reset_n),.rx(uart_rx),.tx(uart_tx),
        .start_cmd(uart_start_cmd),.stop_cmd(stop_cmd),.clear_cmd(clear_cmd));

    wire [11:0] sample;
    wire sample_valid, sample_ready;
    wire [3:0] sensor_fault;
    sensor_if #(.CLK_HZ(CLK_HZ),.ADC_HALF_DIV(ADC_HALF_DIV),
                .RAIL_LIMIT_SAMPLES(RAIL_LIMIT_SAMPLES)) sensor (
        .clk(clk),.rst_n(reset_n),.dout(board_adc_dout),
        .cs_n(board_adc_cs_n),.sclk(board_adc_sclk),.din(board_adc_din),
        .sample(sample),.sample_valid(sample_valid),.ready(sample_ready),
        .error_code(sensor_fault));

    wire signed [31:0] raw_position, velocity_unused, delta_unused;
    encoder_qei #(.CLK_HZ(CLK_HZ)) encoder (
        .clk(clk),.rst_n(reset_n),.enc_a(enc_a),.enc_b(enc_b),
        .tick_speed(sample_valid),.position(raw_position),
        .vel(velocity_unused),.delta(delta_unused));
    wire signed [31:0] position=(ENCODER_INVERT!=0) ? -raw_position : raw_position;

    wire running, permit, fault_latched;
    wire [3:0] core_fault, fault_code;
    wire [2:0] state;
    wire signed [31:0] command_q, relative_position;
    wire angle_update, position_update;
    wire [3:0] internal_fault=(sensor_fault!=0) ? sensor_fault : core_fault;
    wire signed [31:0] position_goal_q, position_target_q;
    wire move_enable=(state==3'd4) && permit && !fault_latched && !stop_cmd && (internal_fault==0);
    position_target #(.COUNTS_PER_REV(COUNTS_PER_REV),.CW_POSITIVE(CW_POSITIVE),
        .MOVE_DEG_PER_SEC(MOVE_DEG_PER_SEC),.POSITION_LIMIT_COUNTS(COUNTS_PER_REV*10)) target (
        .clk(clk),.rst_n(reset_n),.enable(move_enable),.tick_ms(sample_valid),
        .move_cmd(key_press[0] ? 3'b000 : key_press[3:1]),
        .goal_q(position_goal_q),.target_q(position_target_q));

    safety_monitor safety(
        .clk(clk),.rst_n(reset_n),
        .clear_fault(clear_cmd),.running(running),.internal_fault(internal_fault),
        .permit(permit),.latched(fault_latched),.code(fault_code));

    control_core #(.CENTER(CENTER),.CAPTURE_RANGE(CAPTURE_RANGE),.PULSE_MS(PULSE_MS),
        .CHECK_MS(CHECK_MS),.SWING_TIMEOUT_MS(SWING_TIMEOUT_MS),
        .POSITION_LIMIT_COUNTS(COUNTS_PER_REV*10)) core (
        .clk(clk),.rst_n(reset_n),.sample_valid(sample_valid),.sample_ready(sample_ready),
        .sample(sample),.position(position),.position_target_q(position_target_q),.start_cmd(start_cmd),.stop_cmd(stop_cmd),
        .permit(permit),.fault_latched(fault_latched),.running(running),
        .command_q(command_q),.state(state),.request_fault(core_fault),
        .relative_position(relative_position),.angle_update(angle_update),
        .position_update(position_update));

    // Assert STBY first, then allow the driver 2 ms to wake before PWM/IN change.
    // Keep the permission path combinational so a fault disables the outputs
    // without waiting for the clock or for the command pipeline below.
    wire run_allowed=reset_n && permit && running && 
                     !stop_cmd && (internal_fault==0);
    assign stby_fpga=run_allowed;
    reg [31:0] wake_count;
    wire wake_done=(wake_count>=WAKE_CYCLES);
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) wake_count<=0;
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
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin command_mag_q<=0; command_negative_q<=0; end
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
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) pwm_command<=0;
        else pwm_command<=command_negative_q ? -$signed(duty_magnitude) :
                                                $signed(duty_magnitude);
    end
    wire pwm_raw, in1_raw, in2_raw;
    pwm_motor #(.PWM_MAX(PWM_MAX)) motor (
        .clk(clk),.rst_n(reset_n),.enable(motor_ready),.brake(!motor_ready),
        .cmd(pwm_command),.pwm(pwm_raw),.in1(in1_raw),.in2(in2_raw));
    assign pwm_a=motor_ready && pwm_raw;
    assign ain1=motor_ready && in1_raw;
    assign ain2=motor_ready && in2_raw;
    assign dbg_tick=sample_valid;

endmodule
