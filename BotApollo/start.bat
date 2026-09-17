@echo off
REM Robo - L2 Apollo — interface sem console.
REM Se o processo cair (exit != 0), reinicia sozinho apos 3s.
REM Console/debug: start-console.bat

cd /d "%~dp0"

where pythonw >nul 2>&1
if errorlevel 1 (
    where python >nul 2>&1
    if errorlevel 1 (
        echo Python nao encontrado no PATH.
        echo Instale o Python e marque "Add Python to PATH".
        pause
        exit /b 1
    )
)

start "" /MIN powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0restart-watch.ps1"
exit /b 0
