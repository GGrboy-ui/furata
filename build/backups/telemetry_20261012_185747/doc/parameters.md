# ACG720 control parameters and verification boundary

| Parameter | Value | Source / status |
|---|---:|---|
| ADC centre | 1011 codes | Current user-tuned board top; supersedes the historical 1014 setting |
| Capture window | +/-500 codes; valid integers 512..1510 | Around current centre 1011; shared by manual admission and angle fault protection |
| Angle PID | Kp 0.365, Ki 0.01, Kd 0.4 | Jiangxie reference; Ki/Kd represented for 5 ms updates |
| Position PID | Kp 0.4, Ki 0, Kd 4 | Jiangxie reference; represented for 50 ms updates |
| ADC serial input | ADC128S102 IN0 / P5-1 | ACG720 schematic; verify P5 population and signal range |
| ADC interface | CS M6, DIN M5, DOUT P6, SCLK N5 | ACG720 schematic / pin table; 16 clocks/frame, mode-3 edge model |
| Encoder direction | ENCODER_INVERT=1 | Must be checked against hand rotation and motor direction |
| Motor direction | MOTOR_INVERT=1 | Must be checked with low duty open-loop |
| Encoder counts/rev | 408 | Jiangxie material parameter; four-times-decoded counts per output-arm revolution; must be measured on the assembled mechanism |
| Angle sample | 1 kHz | control schedule |
| Angle PID update | 5 ms | control schedule |
| Position PID update | 50 ms | control schedule |
| Swing-up check | 40 ms | Jiangxie reference program |
| Swing pulse | 120 ms at 45% | Current user tuning; unchanged by K3 feature |
| Key debounce | KEY_DEBOUNCE_MS=20 | Active-low adapter K1..K4; release required after reset; one event per press |
| Clockwise target polarity | CW_POSITIVE=1 | CW viewed from above increases position after ENCODER_INVERT; calibrate on hardware |
| Position target slew | MOVE_DEG_PER_SEC=30 | Approximate degrees/s of setpoint, not guaranteed actual speed |
| Motor test duty | MOTOR_TEST_PERCENT=20 | KEY2 starts from STOP; open-loop fixed PWM, not constant rpm; existing slew and wake delay retained |
| Motor test direction | MOTOR_TEST_REVERSE=0 | Logical positive demand by default, then MOTOR_INVERT applies; physical direction requires checking |
| KEY4 | Control/motor reset | Highest priority; clears state, PID, fault latch, position target, wake counter and PWM; ADC/display/key scanning keep running; persistent sensor faults re-latch |
| KEY3 | Manual balance | STOP only, sensor ready, permitted, angle in upright window; captures current arm origin and enters BALANCE directly; no position increment |
| Position target limit | +/-4080 counts | +/-10 revolutions by default, capped at +/-16000 counts for Q16.16 |
| UART | 115200, 8N1; `S`/`X`/`C`, `A` angle / `D` raw display | board interface |
| Display zero | ANGLE_ADC_ZERO=CENTER | Relative upright angle; requires measured zero |
| Display scale | ANGLE_ADC_SPAN=4095, ANGLE_RANGE_TENTHS=3330 | SV01 nominal 333-degree electrical range; requires scale calibration |
| Display polarity | ANGLE_INVERT=0 | Only changes displayed sign; does not change control polarity |
| Display averaging | 16 samples | Display only, approximately 16 ms; control retains raw samples |
| Display scan | 1000 digit slots/s | Onboard 74HC595, 125 complete eight-digit frames/s |
| OLED | SSD1306, 128x64, I2C address 0x3C (7-bit) | P7-7/F13 SCL, P7-8/F14 SDA, open drain / 3.3V pull-ups |
| OLED timing | OLED_I2C_HZ=100000; actual normal bit clock about 80 kHz | Conservative Standard-mode START/STOP and clock-stretch margins |
| OLED refresh | OLED_POWER_WAIT_MS=100, OLED_REFRESH_MS=100; about 7-8 frames/s | Frame snapshot of signed 32-bit RAW/POS/REL; actual frame transfer can exceed the minimum interval |
| OLED reset/error | System reset only; 10 ms byte timeout, 500 ms retry | K4 retains encoder/display; OLED errors do not enter motor fault chain; see doc/oled-encoder.md |

The FPGA regression checks ADC timing, fixed-point arithmetic, swing-up mode transitions,
protection latching, PWM direction and the board-level wiring contract. It does not claim that
the mechanism will swing up or balance: motor inertia, friction, sensor zero, polarity,
counts/rev and current limits remain bench measurements. A mechanical closed-loop acceptance
run is the next step after those values are recorded.
