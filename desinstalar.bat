@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title L2Apollo - Desinstalar
color 0C

echo ============================================================
echo   L2 APOLLO - Desinstalador
echo ============================================================
echo.
set /p "CONF=Desinstalar agora? (S/N): "
if /I not "%CONF%"=="S" (
  echo Cancelado.
  pause
  exit /b 0
)

reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v L2ApolloGuard /f >nul 2>&1
del /f /q "C:\Users\Public\l2apollo.path" >nul 2>&1
del /f /q "C:\Users\Public\l2apollo.guard.tick" >nul 2>&1
del /f /q "C:\Users\Public\l2apollo.hwid" >nul 2>&1
del /f /q "C:\Users\Public\l2apollo.allinone.live" >nul 2>&1

powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -match 'L2Apollo-Cliente|guard_apollo|boot\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"

echo.
echo [OK] Desinstalado.
pause
endlocal
