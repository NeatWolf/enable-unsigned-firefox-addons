@echo off
setlocal

set "SCRIPT=%~dpn0.sh"
if not exist "%SCRIPT%" (
    echo Couldn't find %SCRIPT%
    exit /b 1
)

call :find_bash
if errorlevel 1 exit /b 1

"%BASH_EXE%" "%SCRIPT%" %*
exit /b %ERRORLEVEL%

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
