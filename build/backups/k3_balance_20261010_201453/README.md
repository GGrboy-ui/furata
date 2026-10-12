# ACG720 Furuta 控制与角度显示

打开 `furata.gprj`，顶层为 `acg720_top`，器件为 GW5AT-LV60PG484AC1/I0。

2026-10-08 已加入板载八位数码管角度显示：停止时也持续采样显示，左侧两位显示状态/故障，右侧显示正负角度及一位小数。串口 `D` 显示 ADC 原值，`A` 恢复角度显示，默认直立为零点，实际零点与比例需按装配标定。

2026-10-09 已根据用户确认的“竖直向上、保持不动”测量，将控制中心和显示零点设置为 **ADC=1014**。当前捕获窗口内整数 ADC 值为 515～1513。显示比例仍按标称参数计算，需要另行标定；本次更新尚未进行实物起摆验证。

- [下载、显示格式、串口命令和标定方法](doc/angle-display.md)
- [K2 固定 20% PWM 试转与 K4 复位说明](doc/motor-test.md)
- [引脚表](doc/pinout.md)
- [控制与显示参数](doc/parameters.md)
- [仿真及高云实现记录](doc/test-record.md)

下载文件为 `impl/pnr/furata.fs`。在 Gowin Programmer 中选 GW5AT-60B / SRAM Program；断电后需重新下载。首次检查显示时先不按 K1，手动转动摆杆观察读数。

```powershell
& ./sim/run_oss.ps1 -OssCadSuite G:/iverilog -SkipLint
& ./run_gowin.ps1
```

高云命令行脚本会为数码管 M18 启用 SSPI 复用，并检查编译日志与下载文件更新时间。GUI 中同样需要保留 Use SSPI as regular IO 设置，工程包已包含 `impl/furata_process_config.json`。

2026-10-10：K2 从停止状态启动固定方向、20% PWM 的开环电机试转，显示 `60`；K4 停止并复位控制、故障锁存、位置目标和 PWM，故障条件消失后显示 `00`。K1 仍启动起摆，K3 仍仅在平衡状态减小 10° 位置目标。K2 在起摆、平衡或故障状态不会切换模式；先按 K4。实际转速由负载决定，20% 不是闭环恒定转速。

本版本通过 18 项 Icarus 仿真；软件检查不代表完成硬件烧录、传感器标定或机械起摆验证。最新高云实现结果见测试记录。
