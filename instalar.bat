@echo off
cd /d "%~dp0"
title L2Apollo - Instalador
color 0A

echo ============================================================
echo   L2 APOLLO - Instalador
echo ============================================================
echo.

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "BOOT=%ROOT%\runtime\boot.ps1"

if not exist "%BOOT%" (
  echo [ERRO] Pacote incompleto. Baixe a pasta L2Apollo-Cliente completa.
  pause
  exit /b 1
)

REM config\ local a partir dos defaults (se ainda nao existir)
if exist "%ROOT%\config.default\" (
  if not exist "%ROOT%\config\" mkdir "%ROOT%\config\" >nul 2>&1
  for %%F in ("%ROOT%\config.default\*.ini") do (
    if not exist "%ROOT%\config\%%~nxF" copy /Y "%%F" "%ROOT%\config\%%~nxF" >nul
  )
)

echo.
set "KEY="
set /p "KEY=Informe sua KEY: "
if "%KEY%"=="" (
  echo [ERRO] KEY vazia.
  pause
  exit /b 1
)

set "HWID="
set /p "HWID=Informe o HWID (4 hex, ou Enter para auto-detectar): "

echo.
echo [..] Instalando...
powershell -NoProfile -ExecutionPolicy Bypass -File "%BOOT%" -Action Install -Key "%KEY%" -Hwid "%HWID%"
if errorlevel 1 (
  echo.
  echo [ERRO] Instalacao falhou.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo   Pronto! O Guard esta ativo na bandeja do Windows.
echo ============================================================
echo.
pause
