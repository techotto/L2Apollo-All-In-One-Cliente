@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title L2Apollo - Atualizar
color 0B

echo ============================================================
echo   L2 APOLLO - Atualizar
echo ============================================================
echo.
echo  Pasta: %CD%
echo  Vai: achar quem trava .enc/DLL, matar, baixar GitHub,
echo       sobrescrever TUDO menos config\ + licenca.
echo  A janela NAO fecha sozinha.
echo.

where powershell >nul 2>&1
if errorlevel 1 (
  echo [ERRO] PowerShell nao encontrado.
  goto END_FAIL
)
if not exist "%~dp0atualizar-core.ps1" (
  echo [ERRO] Falta atualizar-core.ps1 nesta pasta.
  echo        Rode o update uma vez via suporte / reclone.
  goto END_FAIL
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0atualizar-core.ps1"
set "ERR=%ERRORLEVEL%"

if not "%ERR%"=="0" goto END_FAIL

echo.
echo Pressione qualquer tecla para fechar...
pause >nul
endlocal
exit /b 0

:END_FAIL
echo.
echo ============================================================
echo   FALHOU - leia as mensagens acima.
echo ============================================================
echo.
echo Pressione qualquer tecla para fechar...
pause >nul
endlocal
exit /b 1
