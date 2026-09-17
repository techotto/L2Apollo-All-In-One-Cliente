@echo off
REM Robo - L2 Apollo — interface (sem console).
REM Se cair (exit != 0), reinicia sozinho apos 3s.
REM Console/debug: start-console.bat
REM Log: logs\start.log

cd /d "%~dp0"

if not exist "%~dp0restart-watch.ps1" (
    echo ERRO: falta restart-watch.ps1
    pause
    exit /b 1
)

REM Evita stub WindowsApps: o PowerShell resolve o python real.
start "" /MIN powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart-watch.ps1"
exit /b 0
