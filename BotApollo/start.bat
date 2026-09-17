@echo off
REM Robo - L2 Apollo — só a interface (sem VBS, sem instalar nada extra).
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
    start "" /B python "%~dp0main.py"
) else (
    start "" /B pythonw "%~dp0main.py"
)

exit /b 0
