@echo off
REM Robo - L2 Apollo — sobe a interface (mata instancia anterior).
REM Console/debug: start-console.bat | Log: logs\start.log

cd /d "%~dp0"

if not exist "%~dp0start-bot.ps1" (
    echo ERRO: falta start-bot.ps1
    pause
    exit /b 1
)

REM -File com aspas: path com espaco OK. Sem "start \"\"" (quebrava o path).
powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0start-bot.ps1"
exit /b %ERRORLEVEL%
