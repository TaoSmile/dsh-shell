@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0launcher\start-shell-edge.ps1"
if errorlevel 1 pause
