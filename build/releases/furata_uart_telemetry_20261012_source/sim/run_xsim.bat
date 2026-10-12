@echo off
setlocal enabledelayedexpansion
rem ============================================================
rem  run_xsim.bat - run RTL functional simulation with Vivado xsim
rem
rem  Usage (from anywhere):
rem      sim\run_xsim.bat tb_pwm_motor          :: batch regression
rem      sim\run_xsim.bat tb_pwm_motor gui      :: open waveform GUI
rem
rem  Layout expected:
rem      rtl\*.v  rtl\*.sv        design sources
rem      sim\tb_*.v  sim\tb_*.sv  testbenches (tb_ prefix required)
rem
rem  Build artifacts go to build\sim\ , sources are never touched.
rem ============================================================

set "VIVADO_BIN=G:\2026.1\Vivado\bin"
set "GOWIN_PRIM=E:\Gowin\Gowin_V1.9.12.03_x64\IDE\simlib\gw2a\prim_sim.v"

set "PROJ=%~dp0.."
set "TOP=%~1"
if "%TOP%"=="" set "TOP=tb_top"
set "MODE=%~2"

if not exist "%VIVADO_BIN%\xvlog.bat" (
    echo [ERROR] xvlog.bat not found in "%VIVADO_BIN%" - fix VIVADO_BIN in this script.
    exit /b 1
)

set "SRC="
for %%f in ("%PROJ%\rtl\*.v")   do set "SRC=!SRC! "%%f""
for %%f in ("%PROJ%\rtl\*.sv")  do set "SRC=!SRC! "%%f""
for %%f in ("%PROJ%\sim\tb_*.v")  do set "SRC=!SRC! "%%f""
for %%f in ("%PROJ%\sim\tb_*.sv") do set "SRC=!SRC! "%%f""

if "!SRC!"=="" (
    echo [ERROR] no sources found. Expected rtl\*.v and sim\tb_*.v
    exit /b 1
)

set "BUILD=%PROJ%\build\sim"
if not exist "%BUILD%" mkdir "%BUILD%"
pushd "%BUILD%"

echo === [1/3] xvlog: compile design + testbench ===
call "%VIVADO_BIN%\xvlog.bat" -sv !SRC!
if errorlevel 1 goto :fail

if exist "%GOWIN_PRIM%" (
    echo ===      compile Gowin GW2A primitive simulation library ===
    call "%VIVADO_BIN%\xvlog.bat" "%GOWIN_PRIM%"
    if errorlevel 1 goto :fail
) else (
    echo [WARN] Gowin prim_sim.v not found at "%GOWIN_PRIM%"
    echo [WARN] designs instantiating rPLL / other primitives will fail to elaborate.
)

echo === [2/3] xelab: elaborate top "%TOP%" ===
call "%VIVADO_BIN%\xelab.bat" %TOP% -s sim_snapshot --debug typical
if errorlevel 1 goto :fail

echo === [3/3] xsim: run ===
if /i "%MODE%"=="gui" (
    call "%VIVADO_BIN%\xsim.bat" sim_snapshot --gui
) else (
    call "%VIVADO_BIN%\xsim.bat" sim_snapshot -R
)

popd
echo === done ===
exit /b 0

:fail
echo.
echo [FAILED] see messages above; simulation did not start.
popd
exit /b 1
