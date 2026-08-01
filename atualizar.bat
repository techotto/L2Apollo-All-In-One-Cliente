@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title L2Apollo - Atualizar
color 0B

echo ============================================================
echo   L2 APOLLO - Atualizar (git pull)
echo ============================================================
echo.
echo  Sua pasta config\ sera PRESERVADA (INIs locais nao sobrescritos).
echo.

where git >nul 2>&1
if errorlevel 1 (
  echo [ERRO] Git nao encontrado no PATH.
  echo        Instale o Git for Windows e tente de novo.
  pause
  exit /b 1
)

if not exist "%~dp0.git\" (
  echo [ERRO] Esta pasta nao e um repositorio Git.
  echo        Clone o pacote com:
  echo          git clone https://github.com/techotto/L2Apollo-All-In-One-Cliente.git
  pause
  exit /b 1
)

set "CFG=%~dp0config"
set "CFGBAK=%TEMP%\l2apollo-config-bak-%RANDOM%%RANDOM%"

if exist "%CFG\" (
  echo [..] Salvando config\ local...
  mkdir "%CFGBAK%" >nul 2>&1
  xcopy "%CFG\*" "%CFGBAK\" /E /I /Y /Q >nul
  if errorlevel 1 (
    echo [ERRO] Falha ao copiar config\ para backup.
    pause
    exit /b 1
  )
)

echo [..] git pull...
echo.
git pull
if errorlevel 1 (
  echo.
  echo [ERRO] git pull falhou.
  if exist "%CFGBAK\" (
    echo [..] Restaurando config\ do backup...
    if not exist "%CFG\" mkdir "%CFG%" >nul 2>&1
    xcopy "%CFGBAK\*" "%CFG\" /E /I /Y /Q >nul
    rmdir /S /Q "%CFGBAK%" >nul 2>&1
  )
  pause
  exit /b 1
)

if exist "%CFGBAK\" (
  echo [..] Restaurando sua config\ local...
  if not exist "%CFG\" mkdir "%CFG%" >nul 2>&1
  xcopy "%CFGBAK\*" "%CFG\" /E /I /Y /Q >nul
  rmdir /S /Q "%CFGBAK%" >nul 2>&1
  echo [OK] config\ preservada.
)

echo.
echo ============================================================
echo   Pacote atualizado (.enc / exe / runtime).
echo   Seus INIs em config\ foram mantidos.
echo ============================================================
echo.
pause
endlocal
