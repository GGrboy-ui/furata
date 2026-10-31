# 2026-10-31：综合警告清理与构建复用

已补齐未用增益／旧回复端口的驱动，明确算术截位；控制参数和协议保持不变。使用 `./run_gowin.ps1`，源码、配置、工具和产物一致时直接复用通过时序验证的结果；`-ForceRebuild` 强制重编译。网页调位置／速度 PID、Kpos、t 无需重新编译。当前匹配交付为 `build/warnings_build_cache_20261031/release/`，主下载文件同步更新，未烧录。详见 [警告及构建说明](doc/warnings-and-build.md)。下方为控制功能与历史记录。

# 2026-10-31：K1 位置平衡、K2 速度环与两套独立 PID

K1 起摆并进入位置平衡，K3 手动进入位置平衡；平衡空闲后 K2 单向切入速度环，200 ms 交接，不重设原位置目标。原 K2 开环电机测试入口取消。网页不切换模式，位置 Kp/Ki/Kd 与速度 Kp/Ki/Kd 分区独立停机设置，速度区另有 Kpos 和 t；以各自板端回读为准。

运行本工程 web/start.cmd，以打印网址为准；本机 http://localhost:8767/，标识 POS1 + VEL3。打开 furata.gprj 后确认新增 outer_handover.v 已加载。当前交付目录 build/k1_k2_dual_pid_20261031/release/，主工程 impl/pnr/furata.fs 同步通过验证的版本，不自动烧录。详见 [操作、参数和协议](doc/k1-k2-dual-pid.md)。以下为历史版本记录。

# 2026-10-31：网页 t 输入与单独应用修复

刷新 http://localhost:8767/，t 现在可直接填写待应用值。停机后点击“仅应用 t（停机）”，保留板端当前速度 PI／周期／模式，以板端回读为准。新增“识别／查询 t 配置”以及首次回复丢失后的有限重试；板端回读不会覆盖已编辑的 t。

此次只改网页，固件仍使用已验证的 VEL2 `impl/pnr/furata.fs`。旧 VEL1 固件能填写草稿，但需下载 VEL2 后才能实际应用 t。当前网页与匹配源码包位于 `build/web_t_edit_fix_20261031/release/`。以下为历史记录。

# 2026-10-31：速度模式静摩擦补偿 t

上电默认位置环。速度参数区增加可调 `t`（PWM 计数，默认 0），速度模式按控制器输出方向叠加 ±t 后限幅；位置模式不生效。停机时与速度 PI 参数整组提交并回读，X/K4 保留，上电恢复 0。

当前网页 http://localhost:8767/，标识“VEL2 / 位置启动”；也可运行本工程 `web/start.cmd` 并使用打印的网址。打开 `furata.gprj`；匹配发布为 `build/speed_friction_t_20261031/release/furata.speed-friction-t.fs`，主工程 `impl/pnr/furata.fs` 同步为该版本。源码、网页、说明、回归与时序记录随包交付。见 [t 参数说明](doc/speed-friction-t.md)。未自动烧录，实际 t 与效果需实物验证。

以下为历史记录，其中默认参数和发布文件不代表当前版本。

# 2026-10-31：位置环启动、网页速度环与轨迹跟踪

打开 `furata.gprj`，上电默认选择位置外环。运行本工程 `web/start.cmd`，以窗口打印的网址为准；当前新网页为 <http://localhost:8767/>（8765/8766 被旧目录服务占用）。页面顶部标识“VEL1 / 位置启动”。

停机时在轨迹区顶部填写速度 Kp、Ki、Kpos、速度周期，点击“应用参数并进入速度环”，核对板端回读后按实体 K3，再执行四种轨迹。位置模式下网页及 FPGA 均拒绝轨迹；普通 ARM1 移动支持两种外环。运行中不能改模式／速度参数，X/K4 保留设置，重新上电恢复位置环及默认参数。

当前匹配发布目录为 `build/position_boot_velocity_web_20261031/release/`，下载文件 `furata.position-boot-velocity-web.fs`；根目录 `impl/pnr/furata.fs` 同步为此版本。完整源码、网页、说明及验证记录随包交付。本次不自动烧录，实物增益和轨迹误差仍需采集验证。见 [双外环说明](doc/velocity-outer.md)。

以下为历史版本说明；历史下载文件和默认模式不代表当前版本。

# 2026-10-30：四种轨迹与位置环周期调节 TRJ1

当前工程新增五次多项式、包络正弦往返、多点定位和七段 S 形速度，均在 FPGA 端生成并通过速度外环/角度内环执行；上电默认原位置外环，停机时通过网页切换。网页 <http://localhost:8766/> 新增四模式参数、位置/速度预览和运行时位置环周期（1～1000 ms，默认 50 ms）。停机或平衡空闲可应用，平衡时在原更新边界切换，K4 后保留，上电恢复默认；离散 PID 系数和积分衰减不自动换算。

当前启动补偿测量的代码、协议、网页、专用测试和发布入口已移除；普通 ARM1 移动、原遥测与保护继续保留。完整使用、参数、协议及数据含义见 [四种轨迹说明](doc/trajectory-control.md)。匹配发布路径为 `build/trajectory_20261030/release/`，选用其中 `furata.trajectory.fs`；不使用历史 `impl` 下的旧固件。本次不自动烧录。

以下内容为原工程说明与历史版本记录；当前功能与交付以本节及轨迹说明为准。

# 2026-10-29：网页自定义转臂角度 ARM1

新增可自由填写的转臂相对角度输入，支持 +60°、−40°、12.5° 等；每次以接受指令时的实际位置为起点，在直立平衡中移动，到位前拒绝新命令。须使用本次 ARM1 固件。详见[操作与协议说明](doc/web-arm-move.md)。

# ACG720 Furuta 控制与角度显示

打开 `furata.gprj`，顶层为 `acg720_top`，器件为 GW5AT-LV60PG484AC1/I0。

当前源码（2026-10-17 积分死区修订）：角度环 I 项在 **±1 ADC 码（约 ±0.0813°，含边界）** 内保留已有积分、停止新增积分，P/D 继续使用完整误差。详见 [角度积分死区](doc/angle-integral-deadband.md)。本次保留当前一圈取模的位置反馈及 ±10 圈净位移保护；早前连续位置版本见 [历史说明](doc/continuous-position.md)。

误删修复保留已有调参：顶层 `CENTER=1007`；角度 PID Q16.16 系数 `20661/720/31214`，位置 PID 系数 `26214/0/262144`；`ENCODER_INVERT=0`、`MOTOR_INVERT=1`、`PWM_SLEW_STEP=16`，起摆为 50% / 100 ms。顶层 `BALANCE_BOOST_MAX_PERCENT=0`，当前关闭线性 PWM 补偿。已删除独立 `ARM_DAMPING` 速度阻尼，两个 PID 的 D 项保留。实际参数以 [参数表](doc/parameters.md) 及源码为准。

本次误删修复的独立固件为 `build/angle_i_deadband_repair_20261017/candidate/impl/pnr/furata.fs`。积分死区专项测试 2/2 通过，完整回归 31/33 通过（两项位置相关失败此前已存在，无新增失败）；50 MHz 时序通过。修复前源码和失败复现位于同级 `before/`，详见 [验证记录](doc/test-record.md)。机械平衡与回位效果需实物验证。

以下日期段落保留历史版本的标定、功能与实现记录，其中的参数和下载文件不代表当前源码。

2026-10-08 已加入板载八位数码管角度显示：停止时也持续采样显示，左侧两位显示状态/故障，右侧显示正负角度及一位小数。串口 `D` 显示 ADC 原值，`A` 恢复角度显示，默认直立为零点，实际零点与比例需按装配标定。

2026-10-09 已根据用户确认的“竖直向上、保持不动”测量，将该版本控制中心和显示零点设置为 **ADC=1014**。该版本捕获窗口内整数 ADC 值为 515～1513。显示比例按标称参数计算，需要另行标定；该次更新尚未进行实物起摆验证。

- [下载、显示格式、串口命令和标定方法](doc/angle-display.md)
- [K2 固定 20% PWM 试转与 K4 复位说明](doc/motor-test.md)
- [K3 手动扶直后维持平衡](doc/manual-balance.md)
- [角度环 ±1 ADC 码积分死区](doc/angle-integral-deadband.md)
- [±2° 线性 PWM 补偿与调参](doc/balance-pwm-boost.md)
- [转臂速度阻尼历史记录（当前已删除）](doc/arm-damping.md)
- [连续累计位置独立版本记录](doc/continuous-position.md)
- [一圈位置归零历史记录](doc/circular-position.md)
- [OLED 编码器 RAW / POS / REL 显示与接线](doc/oled-encoder.md)
- [网页角度与要求/实际 PWM 串口回传](doc/uart-telemetry.md)
- [引脚表](doc/pinout.md)
- [控制与显示参数](doc/parameters.md)
- [仿真及高云实现记录](doc/test-record.md)

历史默认构建下载文件为 `impl/pnr/furata.fs`；本次使用上方独立构建输出。在 Gowin Programmer 中选 GW5AT-60B / SRAM Program；断电后需重新下载。首次检查显示时先不按 K1，手动转动摆杆观察读数。

```powershell
& ./sim/run_oss.ps1 -OssCadSuite G:/iverilog -SkipLint
& ./run_gowin.ps1
```

高云命令行脚本会为数码管 M18 启用 SSPI 复用，并检查编译日志与下载文件更新时间。GUI 中同样需要保留 Use SSPI as regular IO 设置，工程包已包含 `impl/furata_process_config.json`。

2026-10-10：K2 从停止状态启动固定方向、20% PWM 的开环电机试转，显示 `60`；K4 停止并复位控制、故障锁存、位置目标和 PWM，故障条件消失后显示 `00`。K1 仍启动起摆。K3 改为从停止状态、摆杆已扶到直立窗口内时直接进入平衡，显示 `40`，持续运行角度 PID 与位置 PID，保持进入时的转臂位置；取消原 -10° 指令。K2/K3 在运行或故障状态不会切换模式；先按 K4。实际转速由负载决定，20% 不是闭环恒定转速。

2026-10-10 K3 版本保留当时用户调参：顶层 `CENTER=1011`、`PULSE_MS=120`，控制核心 `START_PERCENT=45`。其启动与角度保护以顶层 1011 为准，历史 1014 标定版本说明保留在上文。软件检查不代表完成硬件烧录、传感器标定或机械平衡验证。最新验证结果见测试记录。

K3 版本通过 19/19 项 Icarus 仿真及高云综合、布局布线、下载文件生成。50 MHz 约束下 Fmax=64.451 MHz，最差建立余量 4.485 ns，建立/保持违例均为零。

2026-10-10：新增原套件 I²C OLED 编码器显示。SCL=P7-7/F13，SDA=P7-8/F14，显示有符号 RAW、POS、REL 累计计数，停止时也刷新。已通过 22/22 项仿真；最终 50 MHz 实现 Fmax=67.670 MHz，最差建立余量 5.223 ns，建立/保持违例为零。固定下载版本为 `build/releases/furata_oled_encoder_20261010.fs`，详见 [OLED 说明](doc/oled-encoder.md)。

2026-10-10 OLED 构建保留当时 `POSITION_KP=0 / POSITION_KI=0 / POSITION_KD=0`，该版本没有位置保持修正，但 REL 仍显示真实相对计数。上述 K3/OLED 版本的设置与时序记录均属于历史版本，当前文件以上方参数、最新测试记录和发布清单为准。该次仅完成软件与 FPGA 实现验证，未下载到实物 OLED。

2026-10-12：加入与本机 <http://localhost:8765/> 匹配的串口回传。`P` 开始、`Q` 停止回传，每 5 ms 同时采集数码管平均角度、要求 PWM、实际 PWM；实际值包含缓升、换向死区及故障禁止，两种 PWM 同方向符号。P/Q 不改变电机运行状态。已通过 25/25 仿真和网页解析器验证，高云实现 Fmax=68.727 MHz、建立/保持违例为零。固定下载文件 `build/releases/furata_uart_telemetry_20261012.fs`；需下载新固件后网页才能接收，尚未进行实物串口采集。详见 [回传说明](doc/uart-telemetry.md)。


2026-10-31：新增 VEL1 位置／速度双外环、停机网页调参及板端速度反馈，见 [双外环使用与协议说明](doc/velocity-outer.md)。上电默认位置外环，停机后通过网页进入速度外环执行轨迹，参数需实物调节；原 TRJ1／ARM1 保留。
