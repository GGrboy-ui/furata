# ACG720 control parameters and verification boundary

| Parameter | Value | Source / status |
|---|---:|---|
| ADC centre | 1014 codes | User measured upright, stationary on 2026-10-09; replaces old reference 2098 |
| Capture window | +/-500 codes; valid integers 515..1513 | Around measured centre 1014; physical capture behaviour requires bench verification |
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
| Swing pulse | 100 ms at 35% | Jiangxie reference program |
| Key debounce | KEY_DEBOUNCE_MS=20 | Active-low adapter K1..K4; release required after reset; one event per press |
| Clockwise target polarity | CW_POSITIVE=1 | CW viewed from above increases position after ENCODER_INVERT; calibrate on hardware |
| Position target slew | MOVE_DEG_PER_SEC=30 | Approximate degrees/s of setpoint, not guaranteed actual speed |
| Key position increments | +10 / -10 / +360 degrees | KEY2 / KEY3 / KEY4, BALANCE only; accumulate unwrapped Q16.16 counts |
| Position target limit | +/-4080 counts | +/-10 revolutions by default, capped at +/-16000 counts for Q16.16 |
| UART | 115200, 8N1; `S`/`X`/`C`, `A` angle / `D` raw display | board interface |
| Display zero | ANGLE_ADC_ZERO=CENTER | Relative upright angle; requires measured zero |
| Display scale | ANGLE_ADC_SPAN=4095, ANGLE_RANGE_TENTHS=3330 | SV01 nominal 333-degree electrical range; requires scale calibration |
| Display polarity | ANGLE_INVERT=0 | Only changes displayed sign; does not change control polarity |
| Display averaging | 16 samples | Display only, approximately 16 ms; control retains raw samples |
| Display scan | 1000 digit slots/s | Onboard 74HC595, 125 complete eight-digit frames/s |

The FPGA regression checks ADC timing, fixed-point arithmetic, swing-up mode transitions,
protection latching, PWM direction and the board-level wiring contract. It does not claim that
the mechanism will swing up or balance: motor inertia, friction, sensor zero, polarity,
counts/rev and current limits remain bench measurements. A mechanical closed-loop acceptance
run is the next step after those values are recorded.
