@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title L2Apollo - Atualizar
color 0B

echo ============================================================
echo   L2 APOLLO - Atualizar
echo ============================================================
echo.
echo  So clicar aqui. Seus INIs em config\ sao preservados.
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
set "CFGDEF=%~dp0config.default"
set "CFGBAK=%TEMP%\l2apollo-config-bak-%RANDOM%%RANDOM%"
set "LICBAK=%TEMP%\l2apollo-lic-bak-%RANDOM%%RANDOM%"

echo [1/4] Salvando sua config\ e licenca...
mkdir "%CFGBAK%" >nul 2>&1
mkdir "%LICBAK%" >nul 2>&1
if exist "%CFG\" xcopy "%CFG\*" "%CFGBAK\" /E /I /Y /Q >nul
if exist "%~dp0keys.txt" copy /Y "%~dp0keys.txt" "%LICBAK%\keys.txt" >nul
if exist "%~dp0token.txt" copy /Y "%~dp0token.txt" "%LICBAK%\token.txt" >nul
if exist "%~dp0helper.live" copy /Y "%~dp0helper.live" "%LICBAK%\helper.live" >nul
if exist "%~dp0hwid.local" copy /Y "%~dp0hwid.local" "%LICBAK%\hwid.local" >nul

echo [2/4] Baixando versao nova do GitHub...
git fetch origin
if errorlevel 1 (
  echo.
  echo [ERRO] Nao consegui baixar do GitHub (rede/git).
  goto RESTORE_AND_FAIL
)

echo [3/4] Aplicando update (.enc / exe / runtime)...
REM Forca a versao remota (resolve conflito de buffer.ini / arquivos sujos).
git reset --hard origin/main
if errorlevel 1 (
  echo.
  echo [ERRO] Falha ao aplicar update.
  goto RESTORE_AND_FAIL
)
REM Nao usa -x: config\ / keys (gitignore) ficam intactos ate restaurarmos o backup.
git clean -fd >nul 2>&1

echo [4/4] Restaurando sua config\ e licenca...
if not exist "%CFG\" mkdir "%CFG%" >nul 2>&1
if exist "%CFGBAK%\" (
  xcopy "%CFGBAK%\*" "%CFG\" /E /I /Y /Q >nul
)
if exist "%LICBAK%\keys.txt" copy /Y "%LICBAK%\keys.txt" "%~dp0keys.txt" >nul
if exist "%LICBAK%\token.txt" copy /Y "%LICBAK%\token.txt" "%~dp0token.txt" >nul
if exist "%LICBAK%\helper.live" copy /Y "%LICBAK%\helper.live" "%~dp0helper.live" >nul
if exist "%LICBAK%\hwid.local" copy /Y "%LICBAK%\hwid.local" "%~dp0hwid.local" >nul

REM INIs novos do pacote que o cliente ainda nao tem
if exist "%CFGDEF\" (
  for %%F in ("%CFGDEF%\*.ini") do (
    if not exist "%CFG%\%%~nxF" copy /Y "%%F" "%CFG%\%%~nxF" >nul
  )
)

if exist "%CFGBAK%" rmdir /S /Q "%CFGBAK%" >nul 2>&1
if exist "%LICBAK%" rmdir /S /Q "%LICBAK%" >nul 2>&1

echo.
echo ============================================================
echo   OK - Pacote atualizado.
echo   Seus INIs em config\ foram mantidos.
echo.
echo   Agora: pare o script no Adrenaline, abra o .enc de novo (F9).
echo ============================================================
echo.
pause
endlocal
exit /b 0

:RESTORE_AND_FAIL
if exist "%CFGBAK%\" (
  if not exist "%CFG\" mkdir "%CFG%" >nul 2>&1
  xcopy "%CFGBAK%\*" "%CFG\" /E /I /Y /Q >nul
)
if exist "%LICBAK%\keys.txt" copy /Y "%LICBAK%\keys.txt" "%~dp0keys.txt" >nul
if exist "%LICBAK%\token.txt" copy /Y "%LICBAK%\token.txt" "%~dp0token.txt" >nul
if exist "%LICBAK%\helper.live" copy /Y "%LICBAK%\helper.live" "%~dp0helper.live" >nul
if exist "%LICBAK%\hwid.local" copy /Y "%LICBAK%\hwid.local" "%~dp0hwid.local" >nul
if exist "%CFGBAK%" rmdir /S /Q "%CFGBAK%" >nul 2>&1
if exist "%LICBAK%" rmdir /S /Q "%LICBAK%" >nul 2>&1
echo.
pause
endlocal
exit /b 1
