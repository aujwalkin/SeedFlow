@echo off
powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\SonarrImport.ps1"
exit /b %ERRORLEVEL%
