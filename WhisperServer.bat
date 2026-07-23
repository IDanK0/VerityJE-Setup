@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0WhisperLauncher.ps1" %*
if errorlevel 1 pause
