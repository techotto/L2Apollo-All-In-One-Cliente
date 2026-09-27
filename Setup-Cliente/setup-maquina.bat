@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title L2Apollo - Setup da maquina
color 0B

echo ============================================================
echo   L2 APOLLO - Setup da maquina
echo ============================================================
echo.
echo   Pasta: %~dp0
echo.

REM Se nao for Admin, pede UAC e reabre ESTE bat (janela fica aberta com /k)
net session >nul 2>&1
if not errorlevel 1 goto :RUN

echo [!] Precisa de Administrador.
echo     Aceite o UAC na proxima tela.
echo.
pause

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -LiteralPath '%~f0' -Verb RunAs -WorkingDirectory '%~dp0'"
if errorlevel 1 (
  echo.
  echo [ERRO] Nao conseguiu elevar ^(UAC cancelado?^).
  echo        Ou: botao direito neste .bat -^> Executar como administrador.
  echo.
  pause
  exit /b 1
)

echo.
echo Abriu a janela elevada. Pode fechar esta.
pause
exit /b 0

:RUN
echo [OK] Administrador OK.
echo.
echo   Vai instalar ^(se faltar^): Git, Python 3, clone do GitHub, pip.
echo   Destino: Documentos\L2Apollo-All-In-One-Cliente
echo.
pause

if not exist "%~dp0setup-maquina.ps1" (
  echo [ERRO] Falta setup-maquina.ps1 na mesma pasta do .bat
  echo.
  pause
  exit /b 1
)

echo.
echo [..] PowerShell iniciando...
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-maquina.ps1"
set ERR=%ERRORLEVEL%

echo.
echo ============================================================
if not "%ERR%"=="0" (
  echo   FALHOU - codigo %ERR%
) else (
  echo   SETUP CONCLUIDO
)
echo ============================================================
echo.
echo Pressione qualquer tecla para fechar...
pause >nul
exit /b %ERR%
