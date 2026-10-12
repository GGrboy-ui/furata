# ACG720 Furuta 控制与角度显示

打开 `furata.gprj`，顶层为 `acg720_top`，器件为 GW5AT-LV60PG484AC1/I0。

2026-10-08 已加入板载八位数码管角度显示：停止时也持续采样显示，左侧两位显示状态/故障，右侧显示正负角度及一位小数。串口 `D` 显示 ADC 原值，`A` 恢复角度显示，默认直立为零点，实际零点与比例需按装配标定。

- [下载、显示格式、串口命令和标定方法](doc/angle-display.md)
- [引脚表](doc/pinout.md)
- [控制与显示参数](doc/parameters.md)
- [仿真及高云实现记录](doc/test-record.md)

下载文件为 `impl/pnr/furata.fs`。在 Gowin Programmer 中选 GW5AT-60B / SRAM Program；断电后需重新下载。首次检查显示时先不按 K1，手动转动摆杆观察读数。

```powershell
& ./sim/run_oss.ps1 -OssCadSuite G:/iverilog -SkipLint
& ./run_gowin.ps1
```

高云命令行脚本会为数码管 M18 启用 SSPI 复用，并检查编译日志与下载文件更新时间。GUI 中同样需要保留 Use SSPI as regular IO 设置，工程包已包含 `impl/furata_process_config.json`。

本版本通过 17 项 Icarus 仿真，50 MHz 实现时序通过；软件检查不代表完成硬件烧录、传感器标定或机械起摆验证。
