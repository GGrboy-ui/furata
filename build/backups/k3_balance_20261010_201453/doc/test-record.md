# FPGA regression record

The one-command regression is:

```powershell
powershell -ExecutionPolicy Bypass -File sim\run_oss.ps1 -OssCadSuite G:\iverilog -SkipLint
```

It discovers every `sim/tb_*.v`, compiles/runs each test with Icarus, rejects missing tests and writes `build/oss/regression_report.txt`. Each passing test leaves a VCD below `build/oss/<test>/`; `tb_control_core` also writes `control_trace.csv`. `-SkipLint` is needed for the installed Icarus-only tool directory; omit it when Verilator is available.

On 2026-09-30, Icarus Verilog at `G:\iverilog\bin` completed the full regression: 14/14 testbenches passed. The result is recorded in `build/oss/regression_report.txt`. Verilator lint was not run because it is not installed in that directory.

The regression covers the original clock, tick, PWM, divider, encoder and smoke tests plus ADC128S102 framing, PID reference arithmetic, swing-up/balance transitions, safety latching and board-level wake/internal-fault gating. It does not claim mechanical swing-up or balance; those require measured motor, encoder and potentiometer parameters.

## 2026-09-26 timing and wake-sequence update

After registering the command scaling and PID arithmetic and asserting STBY before the 2 ms PWM delay, a full `run_gowin.ps1 -ProcessName all` completed. The 50 MHz timing report shows 69.244 MHz Fmax, 5.558 ns worst setup slack, and zero setup/hold violations. ModelSim 10.1c did not progress past simulator startup, but the subsequent Icarus run passed all 11 testbenches. Hardware and closed-loop behavior remain unverified.

## 2026-09-28 feedback-interface removal

Removed both external feedback inputs from the top, safety monitor, constraints and testbenches. Internal sensor/control faults still gate motor outputs and latch until cleared while stopped. Startup hold, active-fault priority over clear, clear rejection while running, stopped re-arm, UART stop gating, asynchronous reset and the existing STBY/PWM 2 ms wake sequence passed simulation. The full Icarus regression passed 11/11 tests; Verilator lint was not run.

`run_gowin.ps1 -ProcessName all` completed synthesis, place-and-route and bitstream generation. The updated timing report (`impl/pnr/furata_tr_content.html`) shows 62.181 MHz Fmax against the 50 MHz constraint, 3.918 ns worst setup slack, and zero setup/hold violations. The resulting bitstream is `impl/pnr/furata.fs`. The optimized-away unused encoder divider is the synthesis warning; no external-feedback ports remain in the netlist or pin report. Hardware and closed-loop behavior remain unverified.

## 2026-09-30 adapter-board KEY1 through KEY4

This project and the independent workspace copy at `G:/FPGA_furata/FPGA_Pendulum_ACG720` both passed all 14 Icarus testbenches. Their `build/oss/regression_report.txt` files were recorded at 14:35:21 and 14:35:33 respectively. Verilator lint was not run.

- `tb_key_input`: input synchronization, bounced presses/releases, one pulse per held press, independent keys and release-before-press after reset.
- `tb_position_target`: clockwise polarity in both configurations, fractional 10-degree goals, reverse cancellation, unwrapped 360-degree goals, per-tick slew and exact final target, positive/negative limits, simultaneous-command rejection and disable/reset cancellation.
- `tb_acg720_keys`: physical key inputs through the top-level debouncer and control core; KEY1 swing-up/capture, movement accepted only in BALANCE, target reaching the position PID, long-press suppression, stop/restart and internal-fault gating. This test supplies synthetic sensor samples; it is not a mechanical plant simulation.

`run_gowin.ps1 -ProcessName all` completed synthesis, place-and-route and bitstream generation. `impl/pnr/furata_tr_content.html` reports **70.555 MHz Fmax**, **5.827 ns worst setup slack** and zero setup/hold violations against the 50 MHz constraint. `impl/pnr/furata.fs` was generated at 14:34 on 2026-09-30. These timing results apply to this project's `src/` files.

The adapter's new schematic header K1/K2/K3/K4 mapping to P7-33/35/37/39 was checked against the board pin table and schematic; the implemented FPGA balls are D20/E19/F18/F19 with pull-ups. Existing and new pin assignments are unique. The epro2 PCB still contains the older STM32 module footprint, so actual header continuity remains to be checked. No hardware was programmed: clockwise polarity, counts per output-arm revolution, PID tuning and balance during a move require physical validation.

## 2026-10-08 onboard angle display

Final source passed **17/17 Icarus testbenches**, recorded in `build/oss/regression_report.txt`. New tests cover all 4096 ADC values, degree conversion and rounding, zero/span/invert calibration, averaging, rail rejection and raw diagnosis, the 74HC595 wire protocol (bit order, polarity, latch pulse width, inter-digit blanking and whole-frame consistency), and the integrated ADC-to-display path with UART A/D/S/X/C, fault latching and motor gating. The ADC reader test now checks nonzero channel 5 at command bits 13:11. Verilator is not installed, so Verilator lint was not run.

Gowin V1.9.12.03 completed synthesis, placement, routing and fresh bitstream generation at **2026-10-08 23:06:26**. The 50 MHz constraint achieved **68.158 MHz Fmax**, **5.328 ns worst setup slack**, and **zero setup/hold violated endpoints**. There are 22 uniquely constrained ports; the final pin report places seg7_dio at M18, seg7_rclk at C2 and seg7_sclk at F4. SSPI-as-GPIO is enabled in the saved process config and the build script. Logic usage is 3631/59904, registers 1517/60780, DSP 10/118. The only synthesis warning is optimization of the existing unused encoder velocity divider.

The first placement attempt identified M18 as an SSPI dedicated pin. Enabling its GPIO reuse resolved this; no physical pin was guessed or changed. `run_gowin.ps1` now rejects tool-reported ERROR lines even if gw_sh returns zero, and requires a fresh `.fs` for PnR/all runs. This prevents old bitstreams from being reported as new successful builds.

Final `impl/pnr/furata.fs`: **17,311,931 bytes**, SHA-256 **c9babe24e0fc406989af79b34bbcedb37d3956563756400e3425449933e833e0**. Original code and bitstream were backed up at `build/backups/angle_display_20261008_225534` before modification.

The display uses nominal SV01 electrical range 333 degrees, reference zero 2098, 16-sample averaging and one decimal place. Zero, scale and direction require physical calibration; decimal resolution is not a claim of 0.1-degree measurement accuracy. The motor control path keeps the existing raw samples and K1–K4 actions. No hardware was programmed or mechanically tested in this update.

## 2026-10-09 measured upright ADC centre 1014

The user reported ADC=1014 and explicitly confirmed that this was measured with the pendulum held stationary, vertically upward. The board top, control module default and display module default now use **1014**; the display zero follows `CENTER`. The previous reference 2098 differs by 1084 codes and does not contain the measured upright value in its +/-500-code capture window. The new strict window contains integer ADC codes **515..1513**. Display scale and control direction still need physical validation; this single measurement calibrates the zero.

Final sources passed **17/17 Icarus testbenches**. The board-level display test verifies physical serial ADC data 1014 becoming 0.0 degrees, UART D showing decimal 1014, angle refresh, rail fault and re-arm. The KEY1 integration test verifies entry into BALANCE at 1014, fault 5 when the raw angle leaves that window, continued inhibition after restoring a valid reading and pressing KEY1, stopped fault clear, restart, accepted window edges 515/1513 and rejection at 1514. The all-code display test retains an explicit 2098 fixture to preserve its original bipolar-range and alternative-calibration coverage. These tests supply synthetic signals; they do not model the motor and mechanical plant.

Gowin V1.9.12.03 generated the new bitstream at **2026-10-09 15:17:36**. The 50 MHz constraint achieved **62.242 MHz Fmax**, **3.934 ns worst setup slack**, and **zero setup/hold violated endpoints**. The only synthesis warning is optimization of the unused encoder velocity divider. Verilator lint was not run because Verilator is not installed.

Final `impl/pnr/furata.fs`: **17,311,931 bytes**, SHA-256 **1b0c4453b499ec4d758572f3dba7f8e15224f6f1be48b6018028bbcb831e6dc6**. The prior version and documentation were saved in `build/backups/calibration_1014_20261009_151637`. The dated release is `build/releases/furata_center1014_20261009.fs`, with a complete project package `build/releases/furata_center1014_20261009.zip`.

This update resolves the confirmed control/display centre mismatch. It does not prove the origin of the earlier shared fault code 5 or guarantee mechanical swing-up. No hardware was programmed by the agent. After downloading, check 0.0 degrees with the arm upright and the motor stopped; for a swing-up test, let the pendulum hang freely before pressing KEY1. If a fault recurs, record the state/fault sequence.

## 2026-10-10 K2 fixed PWM motor test and K4 control reset

Per the user's confirmed choice, K2 now starts an open-loop, fixed-direction **20% PWM** motor test from STOP. MOTOR_TEST uses state 6 (`60` on the display), bypasses the angle/position PID loops and swing-up timeout, and retains sensor readiness, sensor-fault latching, relative travel limit, PWM slew and the 2 ms STBY wake interval. K1 retains swing-up; K3 retains its -10 degree BALANCE target change. Active swing-up/BALANCE/FAULT ignore K2 until stopped/reset.

K4 has priority over start commands and resets the core, both PID loops, target generator, safety latch, wake counter, command pipeline and PWM module through a conditioned control reset. Healthy sensors return state/fault to `00`, and a new key press is required to restart. ADC acquisition, raw encoder counting, angle display and A/D mode are retained. Persistent sensor faults re-latch and remain inhibited after K4; the display is not forcibly masked to `00`.

**18/18 Icarus testbenches passed**, with no missing tests. The new `tb_acg720_motor_test` measured 400 high clocks in 2000 PWM clocks (20%), and covers fixed direction, sensor-readiness admission, wake interval, no inherited swing timeout, no PID engagement, held-key reset/restart, simultaneous-key reset priority, UART stop, travel fault and sensor fault. Updated `tb_acg720_keys` covers K4 in swing/balance/fault paths, PID/target/PWM clearing, K3 mapping, calibrated capture bounds and persistent-fault re-latching. ADC/display framing and all other existing regressions also passed. These are synthetic electrical/control signals, not a motor/mechanical plant model.

Verilator 5.053 static checking completed with exit code 0; existing width and unused-signal warnings remain. Log: `build/k2_k4_lint.log`. There were no missing-pin, inferred-latch, multiple-driver or combinational-loop diagnostics.

Gowin V1.9.12.03 completed synthesis, place-and-route and fresh bitstream generation at **2026-10-10 19:35:26 Asia/Shanghai**. Against the 50 MHz clock constraint, actual Fmax is **64.677 MHz**, worst setup slack **4.539 ns**, with **zero setup and hold violated endpoints**. The only synthesis warning is optimization of the existing unused encoder velocity divider. Logs: `build/gowin_all.log`, `impl/pnr/furata_tr_content.html`.

Prior source, related documents, process config and bitstream are backed up at `build/backups/k2_motor_test_k4_reset_20261010_192942`. New download artifact: `build/releases/furata_k2_pwm20_k4_reset_20261010.fs`; source and bitstream hashes are recorded in `build/releases/furata_k2_pwm20_k4_reset_20261010_manifest.json`. No FPGA was programmed or motor mechanically tested by this update; no hardware current sensor was added.
