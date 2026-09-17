@echo off
REM Modo debug: console visivel (sem instalar pacotes automaticamente).
chcp 65001 >nul
cd /d "%~dp0"
title Robo - L2 Apollo (console)
set PYTHONUNBUFFERED=1

where python >nul 2>&1
if errorlevel 1 (
    echo ERRO: Python nao foi encontrado no PATH.
    pause
    exit /b 1
)

python -c "import cv2, mss, numpy, serial" >nul 2>&1
if errorlevel 1 (
    echo Faltam pacotes Python. Rode UMA vez:
    echo   python -m pip install -r requirements.txt
    pause
    exit /b 1
)

echo F8 liga/desliga. Feche pela interface ou Ctrl+C.
python main.py
echo Saiu com codigo %ERRORLEVEL%.
pause
