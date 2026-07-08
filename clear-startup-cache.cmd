@echo off
setlocal EnableExtensions

set "LOG_FILE=%~dp0logs\enable-unsigned-firefox-addons.log"

set "PAUSE_ON_ERROR=1"
if not "%~1"=="" set "PAUSE_ON_ERROR=0"
if defined FIREFOX_PATCH_NO_PAUSE set "PAUSE_ON_ERROR=0"

set "CONFIRM_MODIFY=1"
call :classify_args %*
if defined FIREFOX_PATCH_ASSUME_YES set "CONFIRM_MODIFY=0"

set "SCRIPT=%~dpn0.sh"
if not exist "%SCRIPT%" (
    echo Couldn't find %SCRIPT%
    call :log_line "%~nx0 could not find matching shell script"
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
call :run_bash_script %*
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" call :pause_on_error
exit /b %EXIT_CODE%

:run_bash_script
set "RUN_OUTPUT="
for /f "delims=" %%T in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "[System.IO.Path]::GetTempFileName()"') do set "RUN_OUTPUT=%%T"
call :log_line "%~nx0 started"
if not defined RUN_OUTPUT goto run_bash_without_log
"%BASH_EXE%" "%SCRIPT%" %* > "%RUN_OUTPUT%" 2>&1
set "RUN_EXIT=%ERRORLEVEL%"
type "%RUN_OUTPUT%"
call :log_file "%RUN_OUTPUT%"
del "%RUN_OUTPUT%" >nul 2>nul
call :log_line "%~nx0 finished with exit %RUN_EXIT%"
exit /b %RUN_EXIT%

:run_bash_without_log
"%BASH_EXE%" "%SCRIPT%" %*
set "RUN_EXIT=%ERRORLEVEL%"
call :log_line "%~nx0 finished with exit %RUN_EXIT% without captured output"
exit /b %RUN_EXIT%

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
call :read_choice "YN" "Continue? [Y/N] "
if errorlevel 255 (
    echo Cancelled. No files were changed.
    call :log_line "%~nx0 cancelled before changing files"
    exit /b 2
)
if errorlevel 2 (
    echo Cancelled. No files were changed.
    call :log_line "%~nx0 cancelled before changing files"
    exit /b 2
)
if errorlevel 1 exit /b 0
exit /b 1

:log_line
if not exist "%~dp0scripts\append-log.ps1" exit /b 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\append-log.ps1" -LogFile "%LOG_FILE%" -Message "%~1" >nul 2>nul
exit /b 0

:log_file
if not exist "%~dp0scripts\append-log.ps1" exit /b 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\append-log.ps1" -LogFile "%LOG_FILE%" -InputFile "%~1" >nul 2>nul
exit /b 0

:read_choice
if not exist "%~dp0scripts\read-choice.ps1" (
    echo Couldn't find input helper: %~dp0scripts\read-choice.ps1
    exit /b 255
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\read-choice.ps1" -Choices "%~1" -Prompt "%~2"
exit /b %ERRORLEVEL%

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
call :log_line "%~nx0 could not find Git Bash; no Firefox files were changed"
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
