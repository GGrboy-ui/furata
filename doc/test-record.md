## 2026-10-31 速度反馈换向不再强制清零

测速算法改动位于 velocity_feedback.v；板级 OLED 输入和速度位置误差采样各增加一个时钟寄存以满足时序。速度 PID 商值符号、累加和限幅增加 4 拍（80 ns）计算分隔，数值算法和毫秒周期不变。即时保护路径不变。算法：按 1 ms 汇总带符号净增量，抵消窗口内返回跳变；第二个非零窗口可在任意方向建立周期，保留滤波历史；未完成旧任务由有效标志取消，移除编码器组合信号对除法器的异步复位。保留原约 40 ms 低通、速度量纲、饱和及 1 秒静止超时。位置、两套 PID、模式按键、t 和保护参数不变。

同样 40 次单计数往返，旧版本 0/40 非零、新版本 39/40 非零（首次建立基准为零）。新增频繁换向、首次反向、连续过零、短时净零跳变、采样边界、多计数窗口、计算期间多次换向以及真实 A/B 到物理 UART 测试。最终 Icarus **57/57**、网页 **12/12**。综合器件网表 A/B 往返 40/40 非零，50 MHz 常数下单计数／双计数周期算术分别得到 20/40 counts/s。

Gowin 50 MHz：Fmax **50.440 MHz**，最差建立／保持 **0.175/0.199 ns**，建立／保持违例 **0/0**。记录和匹配交付位于 build/velocity_reversal_fix_20261031。保留旧源码和实现、全部历史发布；未自动烧录，实物改善仍需低速正反转采集确认。见 [换向修复说明](velocity-reversal-fix.md)。

## 2026-10-31 综合警告清理与构建复用

仅修改四处 RTL 连接／位宽写法，控制数值、K1/K2、两组 PID 与串口格式保持不变。原 EX3791 3 条、EX3073 1 条、EX2565 96 条、EX1998 1 条全部消除；仅保留旧未用测速除法器裁剪的 NL0002。角度运行时端口连接编译角度增益，不连接位置／速度参数。

最终 RTL **54/54**、网页 **11/11**。50 MHz：Fmax **50.225 MHz**，最差建立／保持 **0.090/0.211 ns**，违例 **0/0**。完整构建 **515.9 s**；同输入复用实测 **0.532 s**。源码、配置、网表哈希改变时拒绝复用旧综合的三项检查通过；恢复原文件后再次命中复用。

实际构建、仿真及记录：`build/warnings_build_cache_20261031/candidate`、`validation`、`release`。所有历史发布不变，修改前源码、主实现及日志保留在 `before`。未运行 Verilator（本机工具为 Icarus），未自动烧录。说明见 [警告与构建](warnings-and-build.md)。

## 2026-10-31 K1 位置平衡、K2 速度环与双 PID 独立调参

工程 `G:/furata-git/furata`。K1/K3 强制位置外环；正常位置平衡空闲时 K2 单向切入速度环，保留目标、原点和角度内环历史，200 ms 混合外环输出并渐增 t。网页位置 PID、速度 PID 两组独立草稿、停机原子设置及实际回读；角度 PID 继续使用原编译增益。

- 最终 Icarus 全量 **54/54**，无失败和遗漏；源码快照 `build/k1_k2_dual_pid_20261031/validation8`，完整日志 `final-regression8.log`。新 POS1/VEL3 能力识别、配置查询及设置均经真实 RTL UART 编解码；覆盖两组所有参数双向隔离、非零 Kd 被旧 VEL1/VEL2 设置保留、运行拒绝、四种轨迹、普通移动、到位保持、X/K4 与故障中断。
- 位置运行时与编译流水线各对照原离散算法 **512** 个正负／极端样本；速度 D 检查实际测速负微分、周期换秒、40 ms 滤波、首样本、零 Kd、D 参与抗饱和与溢出。行程保护新增 **4096** 个与原宽位移限幅判定的同周期对比，包括 INT_MIN/MAX 原点及边界；传感器故障标志同周期对照旧计数器表达式。
- 网页 **11/11**；浏览器桌面／移动布局及模拟 Web Serial 通过。实际 RTL 的 POS1/VEL3/@P/@W 及旧格式均通过网页解析。浏览器导出 CSV 验证两组实际 PID、模式及交接字段，停机或断线后新回读不混入旧任务；普通 CSV 维持兼容。
- Gowin V1.9.12.03 独立构建 `candidate5`，检查实际综合文件表包含全部模块（包括 outer_handover、pwm_friction）。50 MHz：Fmax **50.225 MHz**，最差建立 **0.090 ns**、最差保持 **0.211 ns**，建立／保持违例均 **0**。
- 为满足时序，板级 PID 算术流水增加 2 个时钟（40 ns），增益、采样、离散算法和内环历史保持不变；轨迹乘法与遥测换算分拍。行程窗口与原点同时捕获，越界保护保留组合即时关断。旧 K2 电机夹具改为测试内部诊断命令，保留原数值和安全断言；OLED 脉冲对齐采样边沿，ARM 到位在寄存坐标稳定后仍检查连续 200 个样本，轨迹多给一个坐标稳定样本。

固件 SHA256：`2ff71ff17f23c0eeb0ab58e1494d4c77c35b69bd1f85b75ceaa344f41019965d`。发布目录 `build/k1_k2_dual_pid_20261031/release` 包含匹配源码、网页、参数说明、最终回归和时序报告；旧源码、主下载文件及历史发布保留。未运行 Verilator lint（安装目录仅有 Icarus），未自动烧录或进行机械闭环实验；实物过冲和最终增益需新采集数据验证。见 [操作、参数及协议](k1-k2-dual-pid.md)。

## 2026-10-29 网页自定义转臂角度 ARM1

- 基线独立快照：`build/web_arm_move_20261029/before`；RTL 33/36，通过后对比无新增失败。
- 最终独立源码及构建：`build/web_arm_move_20261029/candidate`；RTL **38/38**，无失败或遗漏。
- 网页原有5组测试及新增2组ARM1测试全部通过，包含实际共享Web Serial读写模拟、断开X发送失败时释放锁。
- 新增RTL测试覆盖相对+60°/−40°、实测起点、小数、零、整圈、忙拒绝、200ms到位、越界、非法/超时、取消和物理UART遥测仲裁。
- 连续反馈、OLED累计显示恢复后，原位置及OLED失败消除；原积分衰减测试显式固定30%保留并使用累计目标，生产PID参数不变。
- Gowin all完成；约束50 MHz，Fmax **51.010 MHz**，最差建立裕量 **0.396 ns**、保持裕量 **0.247 ns**，建立/保持违例均为0。
- 校验后的固件：`candidate/impl/pnr/furata.fs`。本次未烧录；实机方向、机械误差和平衡移动仍待验收。
- 操作与通信协议：[web-arm-move.md](web-arm-move.md)。发布文件、哈希及参数详见同构建根目录的validation_manifest.json。

# FPGA regression record

## 2026-10-17 积分死区参数与连接误删修复

与上次验证源码快照比较，23 个源文件中仅 `control_core.v` 不同：除后续 PID 调参外，缺少 `ANGLE_I_DEADBAND_Q` 声明及角度 PID 的 `.I_DEADBAND_Q(ANGLE_I_DEADBAND_Q)` 连接。`pid_fixed.v` 的实际死区逻辑完整。恢复这两处后默认仍为 ±1 ADC 码，保留当前角度 `20661/720/31214`、位置 `26214/0/262144` 和顶层 `CENTER=1007`；其余控制核心内容与已验证版本一致。

修复前 `tb_control_integral_deadband` 复现参数不存在的 elaboration 错误，记录为 `build/angle_i_deadband_repair_20261017/before/before_test.log`。修复后两项积分死区专项测试均通过，完整回归 **31/33 通过**；仅保留此前已存在的 `tb_acg720_oled` 和 `tb_control_position_linear` 两项位置模式不匹配失败，无新增失败。完整记录为同目录 `candidate/regression.log` 与 `candidate/build/oss/regression_report.txt`。

Gowin 独立构建完成：50 MHz 约束下 **Fmax=65.557 MHz**，最差建立余量 **4.746 ns**，最差保持余量 **0.247 ns**；建立/保持 TNS 及违例端点均为零。固件为 `build/angle_i_deadband_repair_20261017/candidate/impl/pnr/furata.fs`，SHA256：`2B3A2E667A2F2802327E54F70CA1E6B25A2A7369D79E6979F6A8D945BDF6BE67`。修复前后源码和验证产物均保留，未覆盖旧构建，未烧录板卡。

## 2026-10-17 角度环 ±1 ADC 码积分死区

新增 `pid_fixed.I_DEADBAND_Q`（默认 0）及 `control_core.ANGLE_I_DEADBAND_Q=65536`，仅角度 PID 在闭区间 ±1 ADC 码内保持已有积分、停止新增积分；P/D 保留真实误差，死区外按完整误差累积。0 或负阈值禁用；KI=0、复位/清除优先级与流水线均保留。未增加积分衰减、I 项输出限幅或抗饱和。详见 [积分死区说明](angle-integral-deadband.md)。

修改前实际参数为角度 `20661/770/31214`、位置 `26214/0/322144`、顶层 `CENTER=1007`，本次全部保留。当前工作区仍采用环形位置反馈；下方连续位置章节及对应固件为早前独立版本。

| 回归 | 结果 | 失败项 |
|---|---|---|
| 修改前基线 | 29/31 通过 | `tb_acg720_oled`、`tb_control_position_linear` |
| 修改后完整回归 | 31/33 通过 | 同上，无新增失败 |
| 新增专项测试 | 2/2 通过 | 无 |

基线失败原因：OLED 跨圈测试要求显示累计计数，但当前接线仍使用一圈坐标；连续位置测试在位移 408 时要求位置为 408，但环形实现返回 0。两项在修改前即失败，修改后失败消息相同；本次没有修改其夹具或位置算法以消除失败。完整日志为 `build/angle_i_deadband_20261017/baseline/baseline_regression.log` 和 `candidate/regression.log`，各自的 `build/oss/regression_report.txt` 保留完整清单与波形路径。

新测试 `tb_pid_integral_deadband` 验证正负边界、边界外最小 Q16.16 单位、小数误差、非零旧积分保持、原积分限幅、P/D 正常响应、默认和负阈值禁用、KI=0、复位/清除及结果延迟。`tb_control_integral_deadband` 验证角度实例的默认配置和关闭对照、位置环实时/小数目标、位置 I 项不受影响及停止/复位。原有 PID、控制、按键、安全、PWM、传感器与 UART 等其余 29 项回归通过。未运行 Verilator lint，使用 Icarus 和 Gowin 完成验证。

Gowin V1.9.12.03 完成独立综合、布局布线和新固件生成：约束 **50 MHz**，**Fmax=65.347 MHz**，最差建立余量 **4.697 ns**，最差保持余量 **0.247 ns**；建立/保持 TNS 为 0，违例端点为 0。

固件：`build/angle_i_deadband_20261017/candidate/impl/pnr/furata.fs`。SHA256：`042A0837136698FED6331EDF7779C6A78E6DA1424B13783DB17D01F359B3FB80`。独立目录保留基线与候选源码、测试、清单、日志和报告，原项目 `impl/` 及既有回归产物未由本次构建覆盖。未烧录板卡；机械不对称、摆动和爬行的改善仍待实物验证。

## 2026-10-17 连续累计位置反馈

项目：`G:/furata-git/furata`。取消控制核心中相对位置与位置误差的一圈取模，位置 PID 采用连续 D 项。OLED POS/REL 与串口/网页同步采用累计计数；行程保护直接比较宽位移 `position-origin`，默认严格超出 ±4080 counts 时请求故障 7。保留修改前已有的 `CENTER=1007` 与 `POSITION_KD=261072`，未修改其他增益和控制周期。行为详见 [连续位置说明](continuous-position.md)。

- Icarus 完整回归 **31/31 通过**，无失败或缺失；记录为 `build/linear_position_20261017/regression_report.txt` 与 `regression.log`。`tb_control_position_linear` 替代旧的环形控制专项测试，覆盖正反一圈/多圈、返回原点、连续 P/D、小数整圈目标、±4080/4081 边界、目标不移动保护原点、数值饱和和重新捕获原点。原环形工具的独立单元测试仍保留，该工具不再接入位置环。
- 板级 OLED 测试以真实 A/B 边沿验证整圈后 RAW/POS/REL 仍累计、反向显示符号及 K3/K4 语义；已有板级平衡与电机测试继续验证保护立即禁止输出、故障锁存和复位。
- 网页 **5 套测试全部通过**，包括累计位置曲线跨整圈连接、串口分块解析、旧/新 CSV、校准页面及共享串口；记录为 `web_tests.log`。物理 UART 模拟字节经实际网页解码器按五种分块宽度验证，+408/-816 counts 和误差字段及十列 CSV 往返通过；记录为 `physical_uart_web_check.log`。
- Gowin V1.9.12.03 完成独立综合、布局布线与新固件生成。约束 50 MHz，**Fmax=62.253 MHz**，最差建立余量 **3.937 ns**，最差保持余量 **0.247 ns**；建立/保持 TNS 均为 0，违例端点均为 0。未运行 Verilator lint（现有 Icarus 工具目录不含 Verilator）。

固件：`build/linear_position_20261017/impl/pnr/furata.fs`。SHA256：`904870D4463D2462B6958CBBE5C3840BDF7F6D5E500248838D50A4900E94BB5E`。构建目录保留 `src/`、工程文件、源码 SHA256 清单及实现报告，已确认全部 23 个源文件与当前源码一致。原项目 `impl/` 保留原状。未进行板卡下载或机械闭环验证。

## Regression command

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

## 2026-10-10 K3 manual upright balance

K3 now admits BALANCE directly from STOP when sensor-ready, permitted, and inside the existing upright window. It captures the current arm position as origin, keeps the zero relative position target, and runs the existing 5 ms angle PID and 50 ms position PID continuously. The previous -10 degree K3 goal is removed. Requests outside the window are ignored, not queued. K3 does not interrupt running modes or clear faults; K4/reset and UART stop retain priority.

Current user tuning retained: top CENTER=1011, PULSE_MS=120; core START_PERCENT=45. PID gains and PWM slew/dead time unchanged. Historical calibration tests explicitly select CENTER=1014 and the control fixture selects START_PERCENT=35.

19/19 Icarus testbenches passed, including new tb_acg720_manual_balance: readiness/range admission, no queued request, no swing pulse, captured origin, sustained angle and position PID, opposite angle demands reaching motor direction, repeat/held keys, stop/reset, angle/travel/sensor faults, and recovery. Samples are synthetic; there is no mechanical plant model. Verilator lint was not run in this invocation.

Gowin all completed and generated fresh impl/pnr/furata.fs at 2026-10-10 20:18:19. 50 MHz constraint: Fmax 64.451 MHz, worst setup slack 4.485 ns; setup and hold violated endpoints both zero. Bitstream length 17,311,931 bytes, SHA256 9B397167438947607989A7E7AF32BFC690E55EFCA01F49794BAA50D0883C926E.

Before-change source, tests, documents and bitstream saved under build/backups/k3_balance_20261010_201453. Dated bitstream build/releases/furata_k3_manual_balance_20261010.fs. No board was programmed; physical feedback polarity and mechanical stability remain bench verification.

## 2026-10-10 EX3990 balance_cmd interface repair

The top-level K3 connection and manual-balance test were present, but control_core lacked the balance_cmd input and the STOP-to-BALANCE admission branch. Restored both. From STOP, manual balance requires permit, sample_ready and an angle strictly inside CENTER +/- CAPTURE_RANGE, then captures the current arm position and clears the existing counters/history. Running and fault states ignore the request; stop/reset priority is retained. The top's current CENTER=1011 and all existing PID/motor tuning are retained.

Revalidated the actual G:/furata/furata project: 19/19 Icarus testbenches passed, including tb_acg720_manual_balance. Verilator lint was not run. Gowin V1.9.12.03 completed synthesis, placement, routing and fresh bitstream generation at 2026-10-10 20:39:05 Asia/Shanghai; no ERROR messages. The existing unused encoder divider optimization warning remains.

At the 50 MHz constraint, actual Fmax=58.329 MHz, worst setup slack=2.856 ns, setup/hold violated endpoints both zero. Fresh impl/pnr/furata.fs is 17,311,931 bytes, SHA256 B79CB119811054018C0C3F2911E00ACD9D0E984B7C5E22B7EE0097FC585C6331. These measurements supersede earlier timing/bitstream values for the current repaired source. The original control_core.v was saved under build/backups/ex3990_balance_fix_20261010_203743. No hardware was programmed or mechanical balance tested.

### 2026-10-10 recurrence after source overwrite

After the successful 20:39:06 build, control_core.v was saved again at 20:39:51 with ANGLE_KI=655 but without balance_cmd or manual-balance admission. The 20:40:21 synthesis log reproduced EX3990 and identified this same file. An older editor buffer being saved is a likely explanation, but the saving process was not established.

Reapplied the two missing changes while retaining ANGLE_KI=655 and other current tuning. Backup: build/backups/ex3990_overwrite_repair_20261010_204202/control_core.v. All 19 Icarus tests passed. Gowin all generated a fresh impl/pnr/furata.fs at 2026-10-10 20:43:24 Asia/Shanghai: Fmax 64.451 MHz, worst setup slack 4.485 ns, zero setup/hold violations and no ERROR messages. SHA256 A2A564CC24340DBE2B08D067535E11A8550C9B0354A05C387A6D375674E940B5.

EDA accessibility confirmed G:/furata/furata/furata.gprj was open. Automatic editor reload/run was unavailable because Computer Use returned coordinate input geometry is unavailable. Reload the latest source before tuning, and rerun GUI synthesis to refresh its old message list. No hardware was programmed.

## 2026-10-10 OLED encoder count display

Added `oled_i2c_writer.v` and `oled_encoder_display.v` to the actual `G:/furata/furata/furata.gprj` project and connected them in `acg720_top.v`. User confirmed the original 128x64 four-pin I2C OLED. Pins: SCL=P7-7/F13, SDA=P7-8/F14, both constrained as LVCMOS33 bidirectional/open-drain signals with pull-ups to 3.3V. Default 7-bit address 0x3C, page addressing, SSD1306 initialization, 5x7 glyphs and signed ten-digit RAW/POS/REL. Counts are captured together before each frame; all 1024 display bytes are written, including blank areas. Default normal SCL is about 80 kHz with extra Standard-mode timing margin. Byte timeout and automatic retry keep display failures independent of motor control.

Final **22/22 Icarus testbenches passed**, no failures or missing tests. New tests:

- `tb_oled_i2c_writer`: physical bus byte order, START/STOP, multi-byte transactions, ACK/NACK, clock stretching, held-low SCL timeout/recovery, and Standard-mode START hold, STOP setup, bus-free and SCL high/low timing at 50 MHz.
- `tb_oled_encoder_display`: initialization/address/control bytes, page addressing and byte counts, blank pixels, both signed 32-bit limits, decimal sign/digits, frozen per-frame values, refresh and unplug/reconnect.
- `tb_acg720_oled`: real A/B quadrature input -> RAW/POS/REL, ENCODER_INVERT, K3 origin capture, K4 count retention, K2/K3 while OLED is absent, and immediate sensor-fault motor inhibition.

During work, the user's control file changed only the position gains to **POSITION_KP=0, POSITION_KI=0, POSITION_KD=0**. Those settings are preserved in the final build; the position loop therefore does not produce a holding correction. The existing `tb_control_core` and `tb_acg720_manual_balance` explicitly use the reference position gains 26214/0/262144 to continue checking an enabled outer loop independently of live tuning. The new OLED board test uses the actual current defaults. No PID/control RTL was changed by the OLED implementation. Angle gains 23661/0/23214, top CENTER=1011 and PULSE_MS=120, and START_PERCENT=45 are retained.

Gowin V1.9.12.03 completed synthesis, place-and-route and bitstream generation at **2026-10-10 21:49:23 Asia/Shanghai**. At the 50 MHz constraint, actual Fmax **67.670 MHz**, worst setup slack **5.223 ns**, with **zero setup and hold violated endpoints**. Final pin report confirms OLED F13/F14 as bidirectional LVCMOS33. No ERROR or new width/latch/multiple-driver diagnostics. Three optimization warnings remove the zero-gain position PID, unused position target and existing unused encoder velocity divider. Verilator lint was not run.

Final bitstream: **17,311,931 bytes**, SHA-256 **50CCC4AAEF67E6085A3D0DEA7BC133C192B8B3F8A04BE8CD5D80E4CDC4E6DE9C**. `impl/pnr/furata.fs` and dated `build/releases/furata_oled_encoder_20261010.fs` hashes match. Source hashes were checked before and after the final build and again before release to rule out an editor save during compilation. Compiled-source hashes and tuning are recorded in `build/releases/furata_oled_encoder_20261010_manifest.json`; logs are `build/gowin_all.log` and `build/oled_regression_20261010.log`. Before-change backup: `build/backups/oled_20261010_213219`.

Source snapshot: `build/releases/furata_oled_encoder_20261010_source`. User instructions: `doc/oled-encoder.md`, also copied to `G:/FPGA_furata/OLED编码器显示说明.md`. No board was programmed or physical OLED/mechanical behavior tested; tests use a behavioral I2C slave and synthetic ADC samples.

## 2026-10-12 website UART angle and PWM telemetry

Updated the requested `G:/furata-git/furata` project to match the live localhost:8765 website's `telemetry-core.js` protocol: `T,SSSSSSSS,±DDD.d,±DDDD,±DDDD` plus physical CR/LF. P enables 5 ms snapshots; Q disables future snapshots and drains an active frame. Neither command changes motor control. Existing S/X/C/D/A reception remains available during TX; echoes are excluded throughout a frame. K4 leaves collection enabled; global reset disables it.

Snapshots use the existing averaged `angle_tenths`, the PWM input request, and a new read-only `pwm_motor.applied_cmd` output. Both PWM fields undo MOTOR_INVERT, retaining the controller's sign. Applied counts include slew/reversal dead time and combinational inhibition. Invalid angles and busy transmitters skip frames while advancing the 32-bit sequence; sequence wraps naturally. Repeated P while enabled does not restart the sequence. No control gains, limits, sampling/display averaging or motor behavior changed.

**25/25 Icarus testbenches passed**. Three additions cover physical UART start/data/stop bits and frame bytes; frozen snapshots; simultaneous S/X/C commands; illegal RX stop bits; P/Q restart/drain/idempotence; sequence wrap and invalid/busy gaps; backpressure; positive/negative boundary fields; the real ADC display average; inverted requested/applied PWM during slew and reversal; immediate fault inhibition; K4, D and S/X independence. Synthetic samples and forced demands are used to isolate these interfaces; there is no mechanical plant model. Verilator lint was not run.

`sim/check_web_telemetry.js` loads the actual website decoder and verifies the physically decoded UART simulation record at five chunk sizes, all nine frames, angle/PWM values, sequence wrap and CSV export/import. Windows simulator logs use binary mode to preserve exactly one CR and one LF. Compatibility check passed with zero rejected frames.

Gowin V1.9.12.03 completed synthesis, placement, routing and fresh bitstream generation at **2026-10-12 19:08:35 Asia/Shanghai**. Under the 50 MHz constraint: **Fmax 68.727 MHz**, worst setup slack **5.450 ns**, zero setup and hold violated endpoints. No ERROR or new synthesis warnings; the three existing unused/zero-gain position and encoder optimization warnings remain.

Bitstream `impl/pnr/furata.fs`: **17,311,931 bytes**, SHA-256 **A207A8701DA9E3A5DB955EA173E6C9C5EA91BBB66E2CF55F35309EA904792AA3**. Fixed release `build/releases/furata_uart_telemetry_20261012.fs`; source snapshot and manifest use the same release prefix. Logs: `build/telemetry_regression_20261012.log`, `build/telemetry_web_compatibility_20261012.log`, `build/gowin_all.log`, and `impl/pnr/furata_tr_content.html`. Before-change source/tests/docs and bitstream: `build/backups/telemetry_20261012_185747`. No hardware was programmed or live board serial capture performed.

### GUI EX3937 after adding telemetry

At 19:12:53 the open Gowin GUI synthesized its old in-memory file list, omitting `uart_telemetry.v`, although the saved `furata.gprj` already enabled the file. Both its generated synthesis project and RTL parser arguments confirmed the omission. Saved failing logs/config under `build/backups/telemetry_missing_module_20261012_191915`.

Closed and reopened the same project in the actual Gowin GUI. The Design tree and hierarchy then included `src/rtl/uart_telemetry.v` and `uart_telemetry(telemetry)`. Ran synthesis from the GUI; it completed at **2026-10-12 19:22:59 Asia/Shanghai**, with no errors and only the three existing optimization warnings. Generated synthesis input now includes the new module. Evidence: `build/telemetry_gui_reload_synthesis_20261012.log`. No RTL changes were needed; the previously built bitstream hash remains unchanged. When external tools add files to an already-open project, reopen the project before compiling in the GUI.

## 2026-10-12 arm velocity damping

Added independent balance-only arm feedback: direction-corrected encoder displacement over each 5 ms angle window, Q16.16 gain (default 65536 = 1 PWM percentage point/count), separate +/-20% clamp, and a signed 33-bit angle-output-minus-damping sum clamped to +/-100%. Entry baselines, modular counter wrap, stop/permit/fault/reset clearing and the original swing/test modes are covered. The sampled delta and multiply/clamp stage publishes with the angle PID output. Position and angle tuning present at edit time were preserved: CENTER=1005, START_PERCENT=63, PULSE_MS=120, ANGLE_KP/KI/KD=29661/0/35214, POSITION_KP/KI/KD=2641/0/6581.

Baseline regression was 23/25: manual-balance and telemetry fixtures assumed centre 1011 but inherited the user's new 1005 default. Both fixtures now explicitly select their historical 1011 calibration. Final **27/27 Icarus tests pass**, including new core and real-QEI board damping tests. Coverage includes signs, update cadence, fractional gain, zero gain, damping/output saturation, mixing with angle PID, stop/restart/fault/reset, counter wrap, both balance entry paths, default encoder/motor inversion, PWM telemetry signal signs and K4. Logs: `build/damping_baseline.log`, `build/damping_regression.log`, `build/oss/regression_report.txt`. Verilator lint was not run; source diff whitespace check passed.

Gowin V1.9.12.03 synthesis, placement, routing and bitstream generation completed in isolated `build/arm_damping_20261012` at 2026-10-12 20:24:42 Asia/Shanghai. The saved compiled RTL matches the working RTL by SHA-256. At 50 MHz: **Fmax 58.763 MHz**, worst setup slack **2.983 ns**, **zero setup/hold violated endpoints**. Synthesis has only the unused encoder velocity divider optimization warning; no errors.

Download file: `build/arm_damping_20261012/impl/pnr/furata.fs`, 17,311,931 bytes, SHA-256 `9911D15F07614B2063380152EB2A114F7859D3086B2389B57E95EC513672C541`. Build log and timing report are under that snapshot's `build/gowin_all.log` and `impl/pnr/furata_tr_content.html`. The original project's `impl` outputs were not replaced by this build. No hardware programming or mechanical validation was performed. See `doc/arm-damping.md` for gain units and tuning.

## 2026-10-12 balance capture window gates arm damping

Strengthened arm damping enable to require BALANCE, the strict CENTER +/- CAPTURE_RANGE window, sample_ready, permit and no stop/fault. Both history accumulation and the applied correction use this gate. Exiting the window suppresses the correction immediately, before the next clock clears history. The previous design already excluded damping from PUSH/PULL/WAIT_PEAK; this change does not establish that damping caused the reported swing-up failure. Capture width remains +/-500 ADC (nominal +/-40.7 degrees), and the existing two WAIT_PEAK checks are unchanged.

Preserved user tuning: top/core ARM_DAMPING_KD=35536, ENCODER_INVERT=0, MOTOR_INVERT=1, CENTER=1005, pulse=63%/120 ms, existing angle/position gains, and E13/E14 encoder inputs with C13 debug output. New tb_arm_damping_capture checks substantial arm motion throughout PUSH/PULL/WAIT_PEAK, crossings into the angle window without early damping, automatic/manual capture, the first balance window, exact angle boundaries and loss of sample readiness. Existing arithmetic and board damping tests now explicitly fix their test gain/direction instead of inheriting user tuning.

All 28 testbenches are validated: full regression passed 27/28; the pre-existing OLED fixture assumed ENCODER_INVERT=1 while the user's board default is now 0. Explicitly fixed that fixture to its intended polarity, then its targeted retest passed. Logs: build/damping_capture_regression.log and build/damping_capture_oled_retest.log. No design changes followed the full regression. Source whitespace checks passed. Verilator lint was not run.

Isolated Gowin V1.9.12.03 build: build/arm_damping_capture_20261012. Synthesis, place/route and bitstream generation passed. Fmax=68.321 MHz at a 50 MHz constraint, worst setup slack=5.363 ns, zero setup/hold violated endpoints. Only the existing unused encoder divider optimization warning remains. Working top, control core and active constraints match the built snapshot by SHA-256.

New bitstream: build/arm_damping_capture_20261012/impl/pnr/furata.fs. SHA-256: BB46716C2EAC26017BBE2A04BF8D7D20ED52180150F49495EA8B4C758A4317F7. Original project impl outputs were not replaced. No hardware programming or mechanical swing-up verification was performed.

## 2026-10-12 circular position feedback and target-offset telemetry

The user requested one-revolution position zeroing and website visibility of the position target offset. Added position_wrap.v with a 50-bit sequential remainder: circular Q16.16 relative position and target-minus-position error in [-COUNTS_PER_REV/2, COUNTS_PER_REV/2), default 408 counts/revolution. The position PID now consumes shortest circular error; DELTA_WRAP_Q wraps its derivative across the half-turn boundary. Encoder QEI retains unwrapped position/speed and separately counts modulo position for OLED POS. OLED REL shows circular captured-origin position. Damping uses total encoder displacement; cumulative travel protection still uses unwrapped relative travel. Restored the previously authorized balance/window damping gate present in the capture version but absent in the starting current checkout. Preserved user tuning from the build snapshot and E13/E14 input mapping.

Board telemetry enables POSITION_FIELDS=1. Frames extend from 31 to 55 bytes with signed arm position, position target, shortest position error (integer counts), and -position_out in 0.1 ADC-code units. This last value is the angle target offset, not PWM or degrees. Snapshot inputs use registered, explicitly saturated 16-bit conversions. The website converts ADC offset by 333/4095 degrees/code. CSV retains ADC units and adds four columns. Legacy 19-/31-byte frames and four-/six-column CSV remain supported, with missing values kept null. New charts show position/target/error and angle/target-angle-offset; circular branch cuts are not joined as large physical position moves.

Live HTTP server serves G:/furata/furata/web, which was updated in place. Added the matching website source to this repository's web/ and retained the tested website in build/circular_position_final_20261012/web. Actual in-app browser import of telemetry_position_serial.log verified the new values and plots. Screenshot: build/circular_position_final_20261012/website_position.jpg, showing simulation data only. No live serial connection was opened.

All 31 testbenches are validated. Full regression initially passed 30/31; tb_acg720_telemetry uses a deliberately lower 100 kbaud, at which new frames occupy 5.5 ms. Its second snapshot occurs later due to documented busy-slot skipping; increased only the fixture's waiting time and added same-snapshot metadata checks, then it passed. Removed metadata width diagnostics with explicit clamping; the final board/core/physical-serial affected retest passed 4/4. Logs: build/circular_position_regression.log, build/circular_position_telemetry_retest.log, build/circular_position_final_retest.log. Web test-core.cjs/test-app.cjs pass; sim/check_web_telemetry.js decoded legacy and new physical UART bytes at 5 chunk widths, including CSV roundtrip. At actual 50 MHz / 115200, the 55-byte test has contiguous sequences at 200 Hz, stable snapshots and Q drain. Verilator lint was not run.

Gowin V1.9.12.03 final synthesis, placement/routing and bitstream completed 2026-10-12 21:46:21 Asia/Shanghai. Fmax=61.413 MHz, worst setup slack=3.717 ns at 50 MHz, zero setup/hold violated endpoints. Only the existing unused encoder divider optimization warning remains. All changed RTL and active constraints match compiled snapshot hashes.

Bitstream: build/circular_position_final_20261012/impl/pnr/furata.fs; SHA-256 3CD9DA7503BE540306DAF97399E4D8244824B2A825D722C5AB2BF8D4F702DAD0. Original impl outputs were not replaced. No board download or mechanical verification was performed. See doc/circular-position.md for wrapping semantics, units, the default 408-count calibration and the new download path.

## 2026-10-13 ±2° 线性 PWM 补偿与独立速度阻尼移除

实际工程为 `G:/furata-git/furata`。顶层新增 `BALANCE_BOOST_RANGE_TENTHS=20` 和 `BALANCE_BOOST_MAX_PERCENT=5`，按标定向下取整为中心两侧各 24 个 ADC 码（约 1.95°）。保留当前 `CENTER=999`、角度 KP/KI/KD=35661/0/35214、位置 KP/KI/KD=4641/0/7581、PWM_SLEW_STEP=16 及现有方向和行程保护。独立 ARM_DAMPING 参数、位移窗口、历史状态、乘法和输出修正已完整删除；PID 的 D 项仍保留。

区间内以固定中心距离 `d` 计算 `5*65536*d/24` 的 Q16.16 PWM 增量，包含边界；区间外增量为零。方向跟随原角度 PID 输出，零输出不增加，最终限幅 ±100%。补偿与 PID 在同一 angle_tick 捕获 measured_angle_q，并在下一时钟同步发布。半宽或最大增量为零时关闭。捕获距离先判断范围再缩至 12 位，乘积/除法采用足够容纳最大合法乘积的 35 位，保留小于一个百分点的精度。

删除三个旧阻尼测试，新增 `tb_balance_boost`、`tb_balance_boost_capture`、`tb_acg720_balance_boost`，并更新环形位置测试。验证包括中心、正负 1/12/24/25 码、分数补偿、实际 D 项反向制动、零 PID、两种关闭参数、双向饱和、固定中心与位置环目标偏移、编码器无独立速度反馈、同次采样发布、等待中取消、运行模式、许可/采样就绪、故障、系统及 K4 复位，以及顶层非默认参数、PWM 换向和回传符号。

最终源码快照的 Icarus 全量回归 **31/31 通过**，完成于 2026-10-13 20:07:25 Asia/Shanghai。命令：`./build/balance_pwm_boost_20261013/sim/run_oss.ps1 -OssCadSuite G:/iverilog -SkipLint`。结果及波形位于快照的 `build/oss/`，完整日志为 `regression_console.log`。未运行 Verilator lint。

Gowin V1.9.12.03 综合、布局布线与下载文件生成完成于 2026-10-13 20:07:23 Asia/Shanghai。50 MHz 约束下 **Fmax=53.833 MHz，最差建立余量=1.424 ns，建立/保持违例均为零**。日志仅包含既有未使用编码器测速除法器的优化警告，无错误。23 份实际 RTL/约束文件与编译快照 SHA-256 一致，清单见 `source_manifest.json`。

新下载文件：`build/balance_pwm_boost_20261013/impl/pnr/furata.fs`，17,311,931 字节，SHA-256：`29EE892EAEBCD99C05847CC93FB36D0A97935EC0996D1BD1ACFDD75BD9CC89CE`。原 `impl/pnr/furata.fs` 保持原有 SHA-256 `C5EA02E9A42E0265D8DB450C6711405C4E3259F40FC558CAD5CDD69ECD9A8598`。未进行上板烧录或机械平衡验证；调参和默认边界跳变说明见 [线性补偿说明](balance-pwm-boost.md)。


## 2026-10-30：FRC1转臂启动补偿测量

主工程保留已有ARM1、连续位置和积分衰减改动。旧网页死区测量区块、DZCAL脚本与专用测试已删除，新增40状态下按位置误差和持续静止触发的单次50ms补偿；默认端口8766。PID参数不改，能力回复直接读取控制核心的实际增益和积分设置。

- 固件标识：`26301001`；原始附加命令窗口50ms，额外补偿0～10个百分点，超时5s，观察200ms，冷却至少1s，无自动重试或自动投入控制。
- 完整Icarus回归：41/41。隔离回归副本仅把全层级VCD改为一级信号，降低文件体积，刺激和断言不变；打包脚本逐个核对副本与主工程。物理UART仿真覆盖FRC1/ARM1/T交错帧、未到位的目标、正负限幅、X及重放抑制。
- 网页：7/7测试通过，全部JavaScript语法通过；覆盖真实RTL串口文本解码、单次请求、故障许可、0%正负方向、人工复核、断连不完整记录、CSV和统计。Chrome无界面截图核对页面；旧入口及依赖移除，未连接测量禁用。
- Gowin综合、布局布线通过：50MHz约束，Fmax=50.502MHz，最差建立余量0.199ns，建立/保持违例均为0。PWM换算采用多周期除法；位置观测和输出合成各增加一个系统时钟寄存级，保持即时安全禁止。
- 8766 HTTP返回200，服务根目录为本工程web；旧标定脚本不再提供。
- 发布：`build/friction_probe_20261030/release/furata.friction.fs`，同目录含源码ZIP、manifest.json及验证记录。以 `python sim/package_friction_release.py` 复核匹配源码、全部测试、时序和SHA-256后生成。
- 硬件尚未测量或烧录：本机仅枚举COM3/COM4蓝牙串口，未识别板卡USB串口。实机方向、波形、重复性和实际阈值仍需按friction-startup-measurement.md验收；软件结果不宣称已测得静摩擦或已验证机械平衡。

## 2026-10-30：TRJ1四种轨迹与位置环周期

新增四种 FPGA 参考轨迹与 1～1000 ms 位置环周期调节，移除当前启动补偿测量功能。默认 50 ms，平衡空闲时在旧周期更新完成后切换，PID 历史保留，K4 保留周期，上电恢复默认；离散参数不自动换算。

全量 RTL 43/43，网页 7/7 与 Chrome/HTTP 检查通过。50 MHz 下 Fmax=50.020 MHz，最差建立余量=0.008 ns，建立/保持违例=0/0，余量较小。主工程、独立编译及回归 RTL 哈希匹配。未烧录或机械验证。发布见 `build/trajectory_20261030/release/`，详细参数/协议见 [轨迹说明](trajectory-control.md)，数值与哈希见发布 `VALIDATION.md`/`manifest.json`。


## 2026-10-31 VEL1 位置／速度双外环

- 新增速度 PI（物理时间积分、抗饱和）、有限位置修正、Q16.16 编码器反馈，接入四种轨迹及普通 ARM1 斜坡；网页停机设置整组参数并回读。
- 上电默认速度外环，20 ms、Kp=6554、Ki=1311、Kpos=32768；原位置模式可在停机时选择，原角度参数／中心标定保持工作目录原值。
- RTL：最终滤波时序优化后全量 47/47 项仿真通过；完整结果为 `build/velocity_outer_20261031/validation/build/oss/regression_report.txt`，原始日志为 `final-regression.log`。独立补偿夹具显式选择原位置模式，原始适配和重跑记录一并保留。
- 修改前基线 40/43，3 项旧夹具采用旧 ADC 中心，与当前生产 CENTER=3124 不一致；只在夹具中显式指定其测试标定。位置保持及补偿夹具显式选择位置模式，新增测试使用默认速度模式。
- 网页：8/8 测试、全部 JavaScript 语法检查、桌面／手机布局及模拟 WebSerial 设置／回读／运行互锁／X／断开均通过；速度图保留三条同轴曲线。
- FPGA 最终实现：Fmax=50.142 MHz，50 MHz 下建立／保持违例为 0/0，最差建立余量 0.057 ns。余量较小，改动 RTL 或实现选项后需重新检查。下载文件哈希以本次 `release/manifest.json` 为准，源码与候选／验证快照一致。
- 未烧录实物，未进行机械闭环跟踪误差验证。使用说明与单位见 `velocity-outer.md`。


## 2026-10-31 修订：上电位置环、网页进入速度环

- 上电／系统复位默认选择位置外环；普通 ARM1 移动支持两种外环。停机时网页通过 @TVC 原子提交模式、速度周期、Kp、Ki、Kpos，新增明确的进入速度环／返回位置环按钮；首次回读同步表单，周期／配置实际值独立显示。
- 四种轨迹必须选择速度外环，网页与 FPGA 双侧检查。位置模式拒绝轨迹；速度模式使用参考速度、有限位置修正及编码器反馈，终点零参考速度保持。模式与速度参数运行中拒绝修改，X/K4 保留，上电回到位置环及默认参数。
- 全量 RTL 47/47 通过，包含上电位置模式的实际位置 PID 输出、位置模式拒绝轨迹、两模式 ARM1、四种轨迹、速度反馈参与输出、参数原子性、运行中拒绝、X/K4、系统复位及全部既有回归。既有位置 PID 周期夹具先完成位置模式断言，再显式停机切入速度模式验证轨迹；串口确认按完整回复检查。
- 网页 8/8、JavaScript 语法、Chrome 桌面／手机布局和模拟 WebSerial 操作通过。浏览器编辑速度周期 25 ms、Kp=0.15、Ki=0.03、Kpos=0.6，核对精确 Q16.16 整数组与板端回读；验证进入速度环、执行轨迹、运行中禁改、X、返回位置环及断开。
- 发现本机 8765／8766 指向旧目录 G:/furata/furata/web；当前工程在 localhost:8767 提供服务，HTTP 7 个资源逐字节匹配。start.ps1 在端口占用时选择下一空闲端口并打印实际路径和网址，已验证选择 8768（8766/8767 均占用）。
- Gowin 重新综合与布局布线通过：50 MHz，Fmax=50.002 MHz，建立／保持违例 0/0，最差建立余量 0.001 ns，余量很小。后续 RTL／约束／实现选项改动后需重新检查；此结果不代替实物轨迹误差和增益验证。
- 发布目录 build/position_boot_velocity_web_20261031/release，含新 .fs、匹配源码／网页 ZIP、说明、参数与协议、时序报告、完整回归摘要及 SHA-256 清单。主工程 impl/pnr/furata.fs 与发布版一致，旧发布包及修改前源码保留。未自动烧录，未进行实物机械闭环验证。


## 2026-10-31 修订：速度模式静摩擦补偿 t（VEL2）

- 新增非负整数 t（PWM 计数），默认 0，最大值为板端 PWM_MAX，当前 2500。速度模式 BALANCE 下按实际控制输出方向叠加 ±t 后饱和；控制器精确零输出不补偿，位置模式／起摆／固定 PWM 测试旁路。保留电机反向、缓升、换向死区与即时禁止门控。
- 与速度 PI 参数一起通过 @TVD 停机原子配置，@TVR 回读 t，@TV2 查询能力。旧 @TVI/@TVQ/@TVC 原样保留，旧 @TVC 不修改已有 t。X/K4 保留，系统复位 t=0 且外环回到位置模式。网页仅对 VEL2 开放 t，任务 CSV 追加 friction_t_pwm_counts，普通 CSV 不变。
- 专项 RTL 3/3；最终完整回归 48/48，通过 tb_pwm_friction 的正反向／零和不足一计数／饱和／17 位加法／1000 随机值及复位。实际顶层串口验证 t=7 时 +5 PWM 变 +12、-5 变 -12、零请求仍零、位置模式仍 5；验证非法 t、运行中设置、整组原子拒绝、旧 VEL1 保留 t、X/K4、复位及四种轨迹。
- 新路径比旧转换多两个寄存时钟（50 MHz 下 40 ns）。首次全量回归的旧 tb_acg720_top 在三时钟内取值，产生 3 个过早采样失败；只将其三处 PWM 转换等待改为五时钟，原有数值、限幅和即时停机断言保留。专项重跑通过后，使用最终夹具重新执行全量 48/48，日志 final-regression-recheck.log，未用首次失败结果替代最终回归。
- 网页 9/9、全部 JavaScript 语法及 Chrome 模拟 WebSerial 通过：t=80 与周期／PI 参数整组提交、实际回读、运行中禁改、X 后返回位置模式保留值、旧固件 t 禁用、任务 CSV、重连；桌面与手机在断开／连接状态均检查无横向溢出。HTTP localhost:8767 资源逐字节匹配当前 web。
- Gowin 最终综合与布局布线：50 MHz，Fmax=50.168 MHz，建立／保持违例 0/0，最差建立余量 0.067 ns。源文件、候选、完整仿真及发布包哈希匹配。
- 发布 build/speed_friction_t_20261031/release，主工程 impl/pnr/furata.fs 同步新版本；旧发布包不覆盖，修改前文件保存在同级 before。未自动烧录或进行实物静摩擦／跟踪误差验证，t 需实物调节。说明见 speed-friction-t.md。

## 2026-10-31：网页 t 无法编辑修复

原输入框要求已连接、VEL2 已识别、两份停机状态均新鲜且无锁，导致未满足条件时直接灰显。改为始终可编辑待应用值；新增“仅应用 t（停机）”，下发时沿用板端实际外环／PI／周期，保留原停止状态、能力及新鲜度检查。新增手动查询及停机空闲最多三次能力识别；首次及后续回读不覆盖已编辑草稿。旧固件未识别 t 时阻止带非零 t 草稿的整组下发，避免悄悄忽略 t。

网页 10/10 与 JavaScript 语法检查通过。新增测试覆盖离线与运行时编辑、禁止实际下发、t 单独提交保留实际 PI、未提交的新输入保护、丢失能力回复重试与手动恢复、旧固件及重连。Chrome 模拟 WebSerial 故意丢弃首次 VEL2 回复，验证自动恢复、输入保留、停止后仅应用 t、板端读回及桌面／手机布局。

本次没有修改 RTL、Gowin 工程或下载文件；逐文件核对与 speed_friction_t_20261031 已验证固件一致，沿用其 RTL 48/48、50 MHz 建立／保持违例 0/0、Fmax 50.168 MHz 的结果，不声称本次重新编译或机械验证。当前 web 在 localhost:8767 提供；旧发布包保留，修复网页随独立发布包交付。

## 2026-11-02：TRJ2 位置环轨迹

四种参考曲线送入位置 PID，位置模式运行，速度模式拒绝，K2 在任务期间不切换；角度内环、现有增益与周期保持。网页新增 60°～360°预设，15 s 默认移动／20 s 正弦周期，大角度按 30°/s 限速延长。

RTL 58/58、网页 13/13 与全部 JS 语法通过。整页模拟 Web Serial、HTTP 资源逐字节一致及 no-store 验证通过。Gowin 50 MHz 约束，Fmax=51.428 MHz，建立／保持违例 0/0，最差建立余量 0.556 ns。新增完整 −360°/20 s S 形逐毫秒仿真与速度边界，四模式实际 UART 位流验证位置 PID 路径、互锁、X/K4。初次旧夹具写死 Ki=400 与当前工程 Ki=600 不符，改为验证编译参数；长轨迹容许低于 1/256 编码器计数的 Q 格式量化波动。

匹配交付见 `build/position_trajectory_20261102/release/`，说明见 [位置环轨迹](position-trajectory.md)。未运行 Verilator lint、未烧录或机械跟踪测量；位置模拟跟随仅用于状态机与到位验证。
