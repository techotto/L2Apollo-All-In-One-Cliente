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

echo Iniciando ApolloBot...
echo.
python main.py

echo.
echo ApolloBot encerrado.
pause
