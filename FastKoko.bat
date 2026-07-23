@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FastKoko.ps1" %*
if errorlevel 1 pause
