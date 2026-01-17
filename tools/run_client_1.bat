@echo off
REM Tamaroyn - launch one client (Instance 1)

set GODOT_EXE=C:\Path\To\Godot_v4.5.1-stable_win64.exe

REM Project root is one folder above this script.
set PROJECT_DIR=%~dp0..

"%GODOT_EXE%" --path "%PROJECT_DIR%" -- --connect 127.0.0.1 --port 2456
PAUSE
