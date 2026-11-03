@echo off
title Pocket Help Desk
rem Start as administrator, so Claude can fix things and not only look at them.
rem Windows shows its "allow changes?" box. If that is declined (or the admin
rem password is not available), start normally instead.
powershell -NoProfile -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if %errorlevel%==0 goto run
set "STICK_CMD=%~f0"
powershell -NoProfile -Command "try { Start-Process -FilePath $env:STICK_CMD -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }"
if %errorlevel%==0 exit /b
echo Starting without administrator rights - Claude can look, but not fix everything.
:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0system\launch.ps1"
echo.
pause
