@echo off
cd /d "%~dp0"
title L2Apollo - Descobrir HWID
color 0B

echo ============================================================
echo   L2 APOLLO - Descobrir HWID
echo ============================================================
echo.
echo  Isto vai preparar licenca temporaria (HWID=AAAA).
echo  Abra o script no Adrenaline (F9) e anote:
echo    HWID=XXXX   ou   HWID MISMATCH (AAAA vs XXXX)
echo  Envie o XXXX ao suporte para receber sua KEY.
echo.
pause

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime\boot.ps1" -Action RevealBinHwid
if errorlevel 1 (
  echo.
  echo [ERRO] Falhou. Verifique se existe .enc na pasta.
  pause
  exit /b 1
)

echo.
pause
