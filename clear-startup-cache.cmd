@echo off
setlocal

set "PAUSE_ON_ERROR=1"
if not "%~1"=="" set "PAUSE_ON_ERROR=0"
if defined FIREFOX_PATCH_NO_PAUSE set "PAUSE_ON_ERROR=0"

set "CONFIRM_MODIFY=1"
call :classify_args %*
if defined FIREFOX_PATCH_ASSUME_YES set "CONFIRM_MODIFY=0"

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

if not "%CONFIRM_MODIFY%"=="1" goto run_script
call :confirm_modify
if errorlevel 2 exit /b 0
if errorlevel 1 (
    call :pause_on_error
    exit /b 1
)

:run_script
"%BASH_EXE%" "%SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" call :pause_on_error
exit /b %EXIT_CODE%

:classify_args
if "%~1"=="" exit /b 0
if /I "%~1"=="--dry-run" set "CONFIRM_MODIFY=0"
if /I "%~1"=="--status" set "CONFIRM_MODIFY=0"
if /I "%~1"=="-h" set "CONFIRM_MODIFY=0"
if /I "%~1"=="--help" set "CONFIRM_MODIFY=0"
shift
goto classify_args

:confirm_modify
rem Windows users often arrive here by double-clicking the launcher.
rem Ask before removing startupCache folders from Firefox profiles.
echo.
echo This will delete Firefox profile startupCache folders found by the script.
echo Startup cache is rebuildable Firefox startup data.
echo It is not bookmarks, passwords, history, form data, settings, cookies, or add-ons.
echo Firefox must be closed before clearing startupCache.
echo Run --dry-run first to see exactly what would be removed.
echo.
echo Safer first:
echo   "%~nx0" --dry-run %*
echo.
choice /C YN /N /M "Continue? [Y/N] "
if errorlevel 2 (
    echo Cancelled. No files were changed.
    exit /b 2
)
exit /b 0

:pause_on_error
rem A double-clicked .cmd starts with no arguments and closes on failure.
rem Keep that error visible; normal command-line use stays non-interactive.
if not "%PAUSE_ON_ERROR%"=="1" exit /b 0
echo.
echo The command failed. Press any key to close this window.
pause >nul
exit /b 0

:find_bash
if defined FIREFOX_PATCH_SKIP_BASH_SEARCH goto bash_not_found

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

:bash_not_found
echo Couldn't find Git Bash, the local script runner this tool needs on Windows.
echo Install Git for Windows from https://git-scm.com/download/win
echo Git for Windows includes Git Bash. Reopen this launcher after installing it.
echo This tool does not use Git for downloads, updates, sign-in, or internet access.
echo WSL bash is not used by this launcher.
echo No Firefox files were changed.
exit /b 1

:is_wsl_bash
set "CANDIDATE=%~1"
if /I "%CANDIDATE%"=="%WINDIR%\System32\bash.exe" exit /b 0
if /I "%CANDIDATE%"=="%LocalAppData%\Microsoft\WindowsApps\bash.exe" exit /b 0
exit /b 1
