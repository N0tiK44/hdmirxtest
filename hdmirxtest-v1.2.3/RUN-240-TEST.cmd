@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\host-cycle.ps1" -Mode 240 %*
pause
