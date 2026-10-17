# ACG720 当前参数与验证边界

当前快照：2026-10-13，板级入口为 `src/board/acg720_top.v`。控制核心的通用默认中心可被顶层覆盖；实际板级中心、显示零点及补偿中心均采用顶层 `CENTER=999`。历史文档中的 1014/1011/1005 中心和独立速度阻尼参数不代表当前值。

| Parameter | Value | Source / status |
|---|---:|---|
| ADC centre | `CENTER=999` codes | 顶层当前调参，覆盖控制核心通用默认值 |
| Capture window | `CAPTURE_RANGE=500`; valid integers 500..1498 | 严格位于 `CENTER±500` 内；与补偿区间分开，用于手动平衡准入及角度保护 |
| Angle PID | `ANGLE_KP=35661`, `ANGLE_KI=0`, `ANGLE_KD=35214` | 核心 Q16.16 系数，5 ms 更新；D 项保留 |
| Position PID | `POSITION_KP=4641`, `POSITION_KI=0`, `POSITION_KD=7581` | 核心 Q16.16 系数，50 ms 更新；D 项保留 |
| Balance PWM boost half-width | `BALANCE_BOOST_RANGE_TENTHS=20` | 顶层单位为 0.1°；按 `ANGLE_ADC_SPAN / ANGLE_RANGE_TENTHS` 换算并向下取整，默认 24 ADC codes，约 1.95° |
| Balance PWM boost core range | `BALANCE_BOOST_RANGE_CODES=24` | 核心参数单位为 ADC codes；以固定 `CENTER` 为中心，包含两侧边界，默认 ADC 975..1023 |
| Balance PWM boost maximum | `BALANCE_BOOST_MAX_PERCENT=5` | 区间内增量为 `5×abs(ADC−CENTER)/24` 个 PWM 百分点；跟随角度 PID 输出方向，原输出为零时不添加，最终限幅 ±100% |
| Balance PWM boost disable | Range or maximum = `0` | 关闭补偿；参数修改后重新编译。详见 [补偿说明](balance-pwm-boost.md) |
| Independent arm damping | Removed | 已删除 `ARM_DAMPING` 参数与独立速度反馈代码；[旧记录](arm-damping.md) 仅保留历史追溯 |
| ADC serial input | ADC128S102 IN0 / P5-1 | ACG720 schematic; verify P5 population and signal range |
| ADC interface | CS M6, DIN M5, DOUT P6, SCLK N5 | ACG720 schematic / pin table; 16 clocks/frame, mode-3 edge model |
| Encoder direction | ENCODER_INVERT=0 | Must be checked against hand rotation and motor direction |
| Motor direction | MOTOR_INVERT=1 | Must be checked with low duty open-loop |
| Encoder counts/rev | 408 | Jiangxie material parameter; four-times-decoded counts per output-arm revolution; must be measured on the assembled mechanism |
| Angle sample | 1 kHz | control schedule |
| Angle PID update | 5 ms | control schedule |
| Position PID update | 50 ms | control schedule |
| Swing-up check | 40 ms | Jiangxie reference program |
| Swing pulse | 120 ms at 45% | Current user tuning; unchanged by K3 feature |
| PWM demand slew | `PWM_SLEW_STEP=16` counts/period | 20 kHz PWM、每周期 2500 counts 时约 12.8 个百分点/ms；线性补偿叠加后仍通过既有 PWM 渐变与换向等待 |
| Key debounce | KEY_DEBOUNCE_MS=20 | Active-low adapter K1..K4; release required after reset; one event per press |
| Clockwise target polarity | CW_POSITIVE=1 | CW viewed from above increases position after ENCODER_INVERT; calibrate on hardware |
| Position target slew | MOVE_DEG_PER_SEC=30 | Approximate degrees/s of setpoint, not guaranteed actual speed |
| Motor test duty | MOTOR_TEST_PERCENT=20 | KEY2 starts from STOP; open-loop fixed PWM, not constant rpm; existing slew and wake delay retained |
| Motor test direction | MOTOR_TEST_REVERSE=0 | Logical positive demand by default, then MOTOR_INVERT applies; physical direction requires checking |
| KEY4 | Control/motor reset | Highest priority; clears state, PID, fault latch, position target, wake counter and PWM; ADC/display/key scanning keep running; persistent sensor faults re-latch |
| KEY3 | Manual balance | STOP only, sensor ready, permitted, angle in upright window; captures current arm origin and enters BALANCE directly; no position increment |
| Position target limit | +/-4080 counts | +/-10 revolutions by default, capped at +/-16000 counts for Q16.16 |
| UART | 115200, 8N1; `S`/`X`/`C`, `A` angle / `D` raw display, `P`/`Q` telemetry | 55 字节回传帧每 5 ms 取快照；要求 PWM 包含线性补偿，实际 PWM 包含渐变、换向等待与故障禁止 |
| Display zero | ANGLE_ADC_ZERO=CENTER | Relative upright angle; requires measured zero |
| Display scale | ANGLE_ADC_SPAN=4095, ANGLE_RANGE_TENTHS=3330 | SV01 nominal 333-degree electrical range; requires scale calibration |
| Display polarity | ANGLE_INVERT=0 | Only changes displayed sign; does not change control polarity |
| Display averaging | 16 samples | Display only, approximately 16 ms; control retains raw samples |
| Display scan | 1000 digit slots/s | Onboard 74HC595, 125 complete eight-digit frames/s |
| OLED | SSD1306, 128x64, I2C address 0x3C (7-bit) | P7-7/F13 SCL, P7-8/F14 SDA, open drain / 3.3V pull-ups |
| OLED timing | OLED_I2C_HZ=100000; actual normal bit clock about 80 kHz | Conservative Standard-mode START/STOP and clock-stretch margins |
| OLED refresh | OLED_POWER_WAIT_MS=100, OLED_REFRESH_MS=100; about 7-8 frames/s | Frame snapshot of signed 32-bit RAW/POS/REL; actual frame transfer can exceed the minimum interval |
| OLED reset/error | System reset only; 10 ms byte timeout, 500 ms retry | K4 retains encoder/display; OLED errors do not enter motor fault chain; see doc/oled-encoder.md |

仿真覆盖 ADC 时序、定点运算、状态转换、保护锁存、PWM 方向和板级连接；本次补偿与阻尼移除的实际结果见 [验证记录](test-record.md)。本次独立下载文件路径为 `build/balance_pwm_boost_20261013/impl/pnr/furata.fs`，不执行上板烧录。机械闭环效果仍需实测电机惯量、摩擦、传感器零点与比例、方向、每圈计数及电流限制。
