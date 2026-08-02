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
echo  So clicar aqui. Seus INIs em config\ sao preservados.
echo  A janela NAO fecha sozinha - leia o log ate o final.
echo.

where git >nul 2>&1
if errorlevel 1 (
  echo [ERRO] Git nao encontrado no PATH.
  echo        Instale o Git for Windows e tente de novo.
  goto END_FAIL
)

if not exist "%~dp0.git\" (
  echo [ERRO] Esta pasta nao e um repositorio Git.
  echo        Clone o pacote com:
  echo          git clone https://github.com/techotto/L2Apollo-All-In-One-Cliente.git
  goto END_FAIL
)

set "CFG=%~dp0config"
set "CFGDEF=%~dp0config.default"
set "CFGBAK=%TEMP%\l2apollo-config-bak-%RANDOM%%RANDOM%"
set "LICBAK=%TEMP%\l2apollo-lic-bak-%RANDOM%%RANDOM%"
set "ERR=0"

echo [1/4] Salvando sua config\ e licenca...
mkdir "%CFGBAK%" >nul 2>&1
mkdir "%LICBAK%" >nul 2>&1
if exist "%CFG\" (
  xcopy "%CFG\*" "%CFGBAK\" /E /I /Y /Q
  echo       config\ salva em backup temporario
) else (
  echo       (ainda nao tinha config\)
)
if exist "%~dp0keys.txt" copy /Y "%~dp0keys.txt" "%LICBAK%\keys.txt" >nul
if exist "%~dp0token.txt" copy /Y "%~dp0token.txt" "%LICBAK%\token.txt" >nul
if exist "%~dp0helper.live" copy /Y "%~dp0helper.live" "%LICBAK%\helper.live" >nul
if exist "%~dp0hwid.local" copy /Y "%~dp0hwid.local" "%LICBAK%\hwid.local" >nul
echo.

echo [2/4] Baixando versao nova do GitHub...
git fetch origin
if errorlevel 1 (
  echo [ERRO] Nao consegui baixar do GitHub (rede/git).
  set "ERR=1"
  goto RESTORE
)
echo       fetch OK
echo.

echo [3/4] Aplicando update (.enc / exe / runtime)...
echo       Isso ignora conflito de config\ local (buffer.ini etc).
git reset --hard origin/main
if errorlevel 1 (
  echo [ERRO] Falha ao aplicar update.
  set "ERR=1"
  goto RESTORE
)
git clean -fd
echo       reset OK
git log -1 --oneline
echo.

echo [4/4] Restaurando sua config\ e licenca...
:RESTORE
if not exist "%CFG\" mkdir "%CFG%" >nul 2>&1
if exist "%CFGBAK%\" (
  xcopy "%CFGBAK%\*" "%CFG\" /E /I /Y /Q
  echo       config\ restaurada
) else (
  echo       (sem backup de config)
)
if exist "%LICBAK%\keys.txt" copy /Y "%LICBAK%\keys.txt" "%~dp0keys.txt" >nul
if exist "%LICBAK%\token.txt" copy /Y "%LICBAK%\token.txt" "%~dp0token.txt" >nul
if exist "%LICBAK%\helper.live" copy /Y "%LICBAK%\helper.live" "%~dp0helper.live" >nul
if exist "%LICBAK%\hwid.local" copy /Y "%LICBAK%\hwid.local" "%~dp0hwid.local" >nul

if exist "%CFGDEF\" (
  echo       completando INIs faltantes a partir de config.default\
  for %%F in ("%CFGDEF%\*.ini") do (
    if not exist "%CFG%\%%~nxF" (
      copy /Y "%%F" "%CFG%\%%~nxF" >nul
      echo         + %%~nxF
    )
  )
)

if exist "%CFGBAK%" rmdir /S /Q "%CFGBAK%" >nul 2>&1
if exist "%LICBAK%" rmdir /S /Q "%LICBAK%" >nul 2>&1

if "%ERR%"=="1" goto END_FAIL

echo.
echo ============================================================
echo   OK - Pacote atualizado.
echo   Seus INIs em config\ foram mantidos.
echo.
echo   Agora: pare o script no Adrenaline, abra o .enc de novo (F9).
echo ============================================================
goto END_OK

:END_FAIL
echo.
echo ============================================================
echo   FALHOU - leia as mensagens acima.
echo ============================================================
echo.
echo Pressione qualquer tecla para fechar...
pause >nul
echo.
endlocal
exit /b 1

:END_OK
echo.
echo Pressione qualquer tecla para fechar...
pause >nul
echo.
endlocal
exit /b 0
