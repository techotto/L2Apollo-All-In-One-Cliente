@echo off
chcp 65001 >nul
cd /d "%~dp0"
title ApolloBot - Clique por imagem
set PYTHONUNBUFFERED=1

where python >nul 2>&1
if errorlevel 1 (
    echo ERRO: Python nao foi encontrado no PATH.
    echo Instale o Python e marque a opcao "Add Python to PATH".
    pause
    exit /b 1
)

python -c "import cv2, mss, numpy, serial" >nul 2>&1
if errorlevel 1 (
    echo Instalando dependencias...
    python -m pip install -r requirements.txt
    if errorlevel 1 (
        echo ERRO: nao foi possivel instalar as dependencias.
        pause
        exit /b 1
    )
)

:loop
echo.
echo [%date% %time%] Iniciando ApolloBot...
echo.
python main.py
set EXITCODE=%ERRORLEVEL%

echo.
echo [%date% %time%] ApolloBot caiu (codigo %EXITCODE%). Reiniciando em 3s...
echo Pressione Ctrl+C agora se quiser parar de verdade.
timeout /t 3 /nobreak >nul
goto loop
