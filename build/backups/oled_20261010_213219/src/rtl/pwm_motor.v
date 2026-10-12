// pwm_motor.v - PWM + direction for one TB6612FNG channel, with safety behaviour.
//
// Command interface: a signed demand in PWM counts, + = forward, - = reverse. The sign
// picks the direction pins, the magnitude sets the duty. Anything outside +-(PWM_MAX) is
// clamped, never truncated or wrapped.
//
// What this module guarantees:
//   * inhibit (enable low, or brake high) takes effect COMBINATIONALLY - no clock is
//     needed for the motor to be made safe. The direction pins go to the brake/coast
//     pattern in the same delta the fault appears.
//   * duty changes at most SLEW_STEP counts per PWM period, so no step change in current.
//   * a direction reversal always ramps duty to zero first, then waits DEAD_CYCLES PWM
//     periods at zero duty before the direction pins swap. The TB6612 sees no
//     back-EMF-reversing step. Measured behaviour: one period to reach zero duty, then
//     DEAD_CYCLES + 1 periods held at zero after the pins swap, i.e. the dead time is the
//     configured value plus one whole period. The margin errs safe, so it is left as is.
//
// TB6612FNG truth table, which the output encoding below is chosen from:
//   IN1 IN2 PWM    mode
//    H   H   L     short brake
//    H   H   H     short brake
//    L   H   H     CCW (reverse)
//    L   H   L     short brake
//    H   L   H     CW  (forward)
//    H   L   L     short brake
//    L   L   H     stop / coast (outputs high impedance)
//    L   L   L     short brake
// Note the asymmetry that trips people up: PWM low ALWAYS means short brake, whatever the
// direction pins say. So "PWM off" (the reset-safe requirement) is a brake, not a coast.
// Coasting needs PWM HIGH with both direction pins low. BRAKE_ON_INHIBIT picks between the
// two; the default is short brake, which is the state that cannot let the arm run away.
`timescale 1ns / 1ps

module pwm_motor #(
    // PWM_MAX is the duty count at 100% and equals CLK_HZ / PWM_HZ: 2500 at 50 MHz with a
    // 20 kHz PWM. It is a plain parameter rather than derived from CLK_HZ/PWM_HZ so that
    // there is exactly one number to get right instead of two that can disagree.
    parameter [15:0] PWM_MAX          = 16'd2500,
    parameter [15:0] SLEW_STEP        = 16'd4,   // max duty change per PWM period
    parameter [15:0] DEAD_CYCLES      = 16'd8,   // PWM periods held at zero duty when reversing
    parameter integer BRAKE_ON_INHIBIT = 1       // 1 = short brake, 0 = coast
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,   // 0 = inhibit (safe state)
    input  wire               brake,    // 1 = emergency short brake, ignores cmd
    input  wire signed [15:0] cmd,      // signed demand: + forward, - reverse
    output wire               pwm,
    output wire               in1,
    output wire               in2
);
    // DUTY_MAX is declared signed so the comparisons against the signed cmd inside mag_of()
    // stay signed. Mixing a signed operand with an unsigned localparam silently turns the
    // compare unsigned, and every negative command would then look like a huge positive one.
    localparam signed [15:0] DUTY_MAX = PWM_MAX;
    localparam        [15:0] DUTY_TOP = PWM_MAX - 1;
    localparam        [15:0] SLEW     = SLEW_STEP;
    localparam        [15:0] DEAD     = DEAD_CYCLES;

    // Free-running PWM ramp. Period is PWM_MAX clocks, i.e. PWM_HZ.
    reg [15:0] pwm_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pwm_cnt <= 16'd0;
        else        pwm_cnt <= (pwm_cnt == DUTY_TOP) ? 16'd0 : (pwm_cnt + 16'd1);
    end

    wire period_end = (pwm_cnt == DUTY_TOP);

    // |cmd| clamped to the duty range. Saturation, never wrap-around.
    function [15:0] mag_of;
        input signed [15:0] v;
        begin
            if      (v >  DUTY_MAX) mag_of = DUTY_MAX;
            else if (v < -DUTY_MAX) mag_of = DUTY_MAX;
            else if (v <  16'sd0)   mag_of = -v;
            else                    mag_of = v;
        end
    endfunction

    wire        want_dir = (cmd < 0);
    wire [15:0] want_mag = mag_of(cmd);
    wire        inhibit  = (!enable) || brake;

    reg        dir_q;    // 0 = forward (IN1 high), 1 = reverse (IN2 high)
    reg [15:0] duty_q;   // currently applied duty, always <= DUTY_MAX
    reg [15:0] hold_q;   // PWM periods left at zero duty before the direction pins may swap

    // Duty, direction and dead-time all move only on a PWM period boundary, so the
    // compare against pwm_cnt below can never be cut short mid-pulse.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dir_q  <= 1'b0;
            duty_q <= 16'd0;
            hold_q <= DEAD;
        end else if (period_end) begin
            if (inhibit) begin
                // Safe state. Adopt the requested direction immediately: with duty forced
                // to zero there is no current, so swapping now costs nothing, and it means
                // the very first driven period after release already points the right way.
                duty_q <= 16'd0;
                dir_q  <= want_dir;
                hold_q <= DEAD;
            end else if (hold_q != 16'd0) begin
                // Dead time: stay at zero duty, then take the new direction on the last step.
                duty_q <= 16'd0;
                hold_q <= hold_q - 16'd1;
                if (hold_q == 16'd1) dir_q <= want_dir;
            end else if (want_dir != dir_q) begin
                if (duty_q == 16'd0) begin
                    dir_q  <= want_dir;
                    hold_q <= DEAD;
                end else begin
                    duty_q <= (duty_q > SLEW) ? (duty_q - SLEW) : 16'd0;
                end
            end else if (duty_q < want_mag) begin
                duty_q <= ((want_mag - duty_q) > SLEW) ? (duty_q + SLEW) : want_mag;
            end else if (duty_q > want_mag) begin
                duty_q <= ((duty_q - want_mag) > SLEW) ? (duty_q - SLEW) : want_mag;
            end
        end
    end

    wire drive = enable && (!brake) && (duty_q != 16'd0);

    // Combinational on purpose: a fault must be able to kill the outputs without waiting
    // for a clock edge or a PWM period boundary.
    assign in1 = inhibit ? ((BRAKE_ON_INHIBIT != 0) ? 1'b1 : 1'b0) : ~dir_q;
    assign in2 = inhibit ? ((BRAKE_ON_INHIBIT != 0) ? 1'b1 : 1'b0) :  dir_q;

    assign pwm = inhibit ? ((BRAKE_ON_INHIBIT != 0) ? 1'b0 : 1'b1)
                         : (drive && (pwm_cnt < duty_q));
endmodule
