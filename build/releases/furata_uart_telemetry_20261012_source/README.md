# ACG720 Furuta 控制与角度显示

打开 `furata.gprj`，顶层为 `acg720_top`，器件为 GW5AT-LV60PG484AC1/I0。

2026-10-08 已加入板载八位数码管角度显示：停止时也持续采样显示，左侧两位显示状态/故障，右侧显示正负角度及一位小数。串口 `D` 显示 ADC 原值，`A` 恢复角度显示，默认直立为零点，实际零点与比例需按装配标定。

2026-10-09 已根据用户确认的“竖直向上、保持不动”测量，将控制中心和显示零点设置为 **ADC=1014**。当前捕获窗口内整数 ADC 值为 515～1513。显示比例仍按标称参数计算，需要另行标定；本次更新尚未进行实物起摆验证。

- [下载、显示格式、串口命令和标定方法](doc/angle-display.md)
- [K2 固定 20% PWM 试转与 K4 复位说明](doc/motor-test.md)
- [K3 手动扶直后维持平衡](doc/manual-balance.md)
- [OLED 编码器 RAW / POS / REL 显示与接线](doc/oled-encoder.md)
- [网页角度与要求/实际 PWM 串口回传](doc/uart-telemetry.md)
- [引脚表](doc/pinout.md)
- [控制与显示参数](doc/parameters.md)
- [仿真及高云实现记录](doc/test-record.md)

下载文件为 `impl/pnr/furata.fs`。在 Gowin Programmer 中选 GW5AT-60B / SRAM Program；断电后需重新下载。首次检查显示时先不按 K1，手动转动摆杆观察读数。

```powershell
& ./sim/run_oss.ps1 -OssCadSuite G:/iverilog -SkipLint
& ./run_gowin.ps1
```

高云命令行脚本会为数码管 M18 启用 SSPI 复用，并检查编译日志与下载文件更新时间。GUI 中同样需要保留 Use SSPI as regular IO 设置，工程包已包含 `impl/furata_process_config.json`。

2026-10-10：K2 从停止状态启动固定方向、20% PWM 的开环电机试转，显示 `60`；K4 停止并复位控制、故障锁存、位置目标和 PWM，故障条件消失后显示 `00`。K1 仍启动起摆。K3 改为从停止状态、摆杆已扶到直立窗口内时直接进入平衡，显示 `40`，持续运行角度 PID 与位置 PID，保持进入时的转臂位置；取消原 -10° 指令。K2/K3 在运行或故障状态不会切换模式；先按 K4。实际转速由负载决定，20% 不是闭环恒定转速。

最新源码保留用户当前调参：顶层 `CENTER=1011`、`PULSE_MS=120`，控制核心 `START_PERCENT=45`。历史 1014 标定版本说明保留在上文；当前启动与角度保护以顶层 1011 为准。软件检查不代表完成硬件烧录、传感器标定或机械平衡验证。最新验证结果见测试记录。

K3 版本通过 19/19 项 Icarus 仿真及高云综合、布局布线、下载文件生成。50 MHz 约束下 Fmax=64.451 MHz，最差建立余量 4.485 ns，建立/保持违例均为零。

2026-10-10：新增原套件 I²C OLED 编码器显示。SCL=P7-7/F13，SDA=P7-8/F14，显示有符号 RAW、POS、REL 累计计数，停止时也刷新。已通过 22/22 项仿真；最终 50 MHz 实现 Fmax=67.670 MHz，最差建立余量 5.223 ns，建立/保持违例为零。固定下载版本为 `build/releases/furata_oled_encoder_20261010.fs`，详见 [OLED 说明](doc/oled-encoder.md)。

OLED 构建保留用户当前 `POSITION_KP=0 / POSITION_KI=0 / POSITION_KD=0`，此时没有位置保持修正，但 REL 仍显示真实相对计数。上述旧 K3 版本的非零位置环设置与时序记录属于历史版本，当前文件以最新测试记录和发布清单为准。本次仅完成软件与 FPGA 实现验证，未下载到实物 OLED。

2026-10-12：加入与本机 <http://localhost:8765/> 匹配的串口回传。`P` 开始、`Q` 停止回传，每 5 ms 同时采集数码管平均角度、要求 PWM、实际 PWM；实际值包含缓升、换向死区及故障禁止，两种 PWM 同方向符号。P/Q 不改变电机运行状态。已通过 25/25 仿真和网页解析器验证，高云实现 Fmax=68.727 MHz、建立/保持违例为零。固定下载文件 `build/releases/furata_uart_telemetry_20261012.fs`；需下载新固件后网页才能接收，尚未进行实物串口采集。详见 [回传说明](doc/uart-telemetry.md)。
