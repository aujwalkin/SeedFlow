@echo off
powershell.exe -ExecutionPolicy Bypass -File "B:\Plex\Scripts\SonarrImport\SonarrImport.ps1"
exit /b %ERRORLEVEL%
