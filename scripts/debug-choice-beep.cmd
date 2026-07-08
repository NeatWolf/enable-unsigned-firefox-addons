@echo off
setlocal EnableExtensions

if /I "%~1"=="-h" goto help
if /I "%~1"=="--help" goto help

echo Debug-only Windows choice prompt test.
echo This script does not read or change Firefox files.
echo.
echo It intentionally runs several choice prompts. To test whether Windows
echo beeps on this system, press Enter or a key that is not listed.

call :run_choice "1 of 4: yes/no prompt" YN "Continue? [Y/N] "
call :run_choice "2 of 4: main-menu-style prompt" 123Q "Choose 1, 2, 3, or Q: "
call :run_choice "3 of 4: profile-picker-style prompt" 123456789Q "Choose profile number, or Q to cancel: "
call :run_choice "4 of 4: letter-menu-style prompt" ABCDQ "Choose A, B, C, D, or Q: "

echo.
echo Choice prompt test finished.
exit /b 0

:run_choice
echo.
echo Choice test %~1
choice /C %~2 /N /M "%~3"
echo choice exit code: %ERRORLEVEL%
exit /b 0

:help
echo Usage: scripts\debug-choice-beep.cmd
echo.
echo Debug-only helper for checking whether Windows choice prompts trigger
echo the system bell on invalid keys. This script does not touch Firefox.
exit /b 0
