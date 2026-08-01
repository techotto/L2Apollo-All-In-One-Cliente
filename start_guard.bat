@echo off
cd /d "%~dp0"
title L2Apollo Guard
if exist "%~dp0config.default\" (
  if not exist "%~dp0config\" mkdir "%~dp0config\" >nul 2>&1
  for %%F in ("%~dp0config.default\*.ini") do (
    if not exist "%~dp0config\%%~nxF" copy /Y "%%F" "%~dp0config\%%~nxF" >nul
  )
)
if exist "%~dp0L2Apollo.exe" (
  start "" "%~dp0L2Apollo.exe" --guard
) else (
  start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0runtime\boot.ps1" -Action Guard
)
