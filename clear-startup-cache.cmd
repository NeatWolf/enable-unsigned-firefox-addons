@echo off
setlocal

set "PAUSE_ON_ERROR=1"
if not "%~1"=="" set "PAUSE_ON_ERROR=0"
if defined FIREFOX_PATCH_NO_PAUSE set "PAUSE_ON_ERROR=0"

set "SCRIPT=%~dpn0.sh"
if not exist "%SCRIPT%" (
    echo Couldn't find %SCRIPT%
    call :pause_on_error
    exit /b 1
)

call :find_bash
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" (
    call :pause_on_error
    exit /b %EXIT_CODE%
)

"%BASH_EXE%" "%SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" call :pause_on_error
exit /b %EXIT_CODE%

:pause_on_error
rem A double-clicked .cmd starts with no arguments and closes on failure.
rem Keep that error visible; normal command-line use stays non-interactive.
if not "%PAUSE_ON_ERROR%"=="1" exit /b 0
echo.
echo The command failed. Press any key to close this window.
pause >nul
exit /b 0

:find_bash
for %%P in (
    "%ProgramFiles%\Git\bin\bash.exe"
    "%ProgramFiles%\Git\usr\bin\bash.exe"
    "%ProgramFiles(x86)%\Git\bin\bash.exe"
    "%ProgramFiles(x86)%\Git\usr\bin\bash.exe"
    "%LocalAppData%\Programs\Git\bin\bash.exe"
    "%LocalAppData%\Programs\Git\usr\bin\bash.exe"
) do (
    if exist "%%~P" (
        set "BASH_EXE=%%~P"
        exit /b 0
    )
)

for /f "delims=" %%P in ('where bash.exe 2^>nul') do (
    call :is_wsl_bash "%%~fP"
    if errorlevel 1 (
        set "BASH_EXE=%%~fP"
        exit /b 0
    )
)

echo Couldn't find Git Bash. Install Git for Windows from https://git-scm.com/download/win
exit /b 1

:is_wsl_bash
set "CANDIDATE=%~1"
if /I "%CANDIDATE%"=="%WINDIR%\System32\bash.exe" exit /b 0
if /I "%CANDIDATE%"=="%LocalAppData%\Microsoft\WindowsApps\bash.exe" exit /b 0
exit /b 1
