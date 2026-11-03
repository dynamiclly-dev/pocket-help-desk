@echo off
rem Pocket Help Desk: open a sign-in page in a PRIVATE window, so the computer keeps
rem no cookies or saved sign-in after the window is closed.
rem Claude Code calls this through the BROWSER variable with the URL as %1.
rem No private-capable browser = refuse (never a normal window) and show the link
rem straight on the screen (CON), so it can be opened in a private window by hand.
setlocal
set "AP=SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths"
reg query "HKLM\%AP%\msedge.exe" >nul 2>&1 && (start "" msedge --inprivate "%~1" & exit /b 0)
reg query "HKLM\%AP%\chrome.exe" >nul 2>&1 && (start "" chrome --incognito "%~1" & exit /b 0)
reg query "HKCU\%AP%\chrome.exe" >nul 2>&1 && (start "" chrome --incognito "%~1" & exit /b 0)
reg query "HKLM\%AP%\firefox.exe" >nul 2>&1 && (start "" firefox -private-window "%~1" & exit /b 0)
set "URL=%~1"
setlocal EnableDelayedExpansion
>CON echo(
>CON echo [Pocket Help Desk] No browser with a private mode found. Open this link in a PRIVATE window yourself:
>CON echo(!URL!
>CON echo(
exit /b 1
