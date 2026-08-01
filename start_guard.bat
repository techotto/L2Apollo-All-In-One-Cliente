@echo off
cd /d "%~dp0"
title L2Apollo Guard
if exist "%~dp0L2Apollo.exe" (
  start "" "%~dp0L2Apollo.exe" --guard
) else (
  start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0runtime\boot.ps1" -Action Guard
)
