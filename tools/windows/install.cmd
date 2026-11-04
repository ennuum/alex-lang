@echo off
rem Installation d'ALEX : double-clic (utilisateur courant) ou  install.cmd -AllUsers
rem Tous les arguments sont transmis a install.ps1 (voir ses options : -InstallDir -NoPath -Associate -Quiet ...).
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
exit /b %ERRORLEVEL%
