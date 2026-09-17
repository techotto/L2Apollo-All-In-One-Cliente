@echo off
REM Robo - L2 Apollo — sobe a interface (mata instancia anterior).
REM Console/debug: start-console.bat | Log: logs\start.log

cd /d "%~dp0"

if not exist "%~dp0start-bot.ps1" (
    echo ERRO: falta start-bot.ps1
    pause
    exit /b 1
)

REM PATH Maquina+Usuario (igual ao cmd) — Explorer as vezes nao herda tudo
for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "MACH_PATH=%%B"
for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USER_PATH=%%B"
if defined MACH_PATH set "PATH=%MACH_PATH%;%PATH%"
if defined USER_PATH set "PATH=%USER_PATH%;%PATH%"

powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0start-bot.ps1"
exit /b %ERRORLEVEL%
