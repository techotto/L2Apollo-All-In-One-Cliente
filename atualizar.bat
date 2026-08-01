@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title L2Apollo - Atualizar
color 0B

echo ============================================================
echo   L2 APOLLO - Atualizar (git pull)
echo ============================================================
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

echo [..] git pull...
echo.
git pull
if errorlevel 1 (
  echo.
  echo [ERRO] git pull falhou.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo   Pacote atualizado.
echo ============================================================
echo.
pause
endlocal
