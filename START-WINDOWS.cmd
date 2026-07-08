@echo off
setlocal

cd /d "%~dp0"

:menu
cls
echo Enable Unsigned Firefox Add-ons
echo.
echo 1  Check Firefox patch status
echo 2  Test Firefox patch with dry run
echo 3  Patch Firefox
echo.
echo 4  Check startup-cache status
echo 5  Test startup-cache cleanup with dry run
echo 6  Clear startup cache
echo.
echo 7  Check restore status
echo 8  Test restore with dry run
echo 9  Restore Firefox from rollback backup
echo.
echo H  Open README
echo Q  Quit
echo.
choice /C 123456789HQ /N /M "Choose an option: "

if errorlevel 11 goto quit
if errorlevel 10 goto readme
if errorlevel 9 goto restore_real
if errorlevel 8 goto restore_dry_run
if errorlevel 7 goto restore_status
if errorlevel 6 goto cache_real
if errorlevel 5 goto cache_dry_run
if errorlevel 4 goto cache_status
if errorlevel 3 goto patch_real
if errorlevel 2 goto patch_dry_run
if errorlevel 1 goto patch_status

:patch_status
call "%~dp0patch-firefox.cmd" --status
call :wait
goto menu

:patch_dry_run
call "%~dp0patch-firefox.cmd" --dry-run
call :wait
goto menu

:patch_real
call "%~dp0patch-firefox.cmd"
call :wait
goto menu

:cache_status
call "%~dp0clear-startup-cache.cmd" --status
call :wait
goto menu

:cache_dry_run
call "%~dp0clear-startup-cache.cmd" --dry-run
call :wait
goto menu

:cache_real
call "%~dp0clear-startup-cache.cmd"
call :wait
goto menu

:restore_status
call "%~dp0unpatch-firefox.cmd" --status
call :wait
goto menu

:restore_dry_run
call "%~dp0unpatch-firefox.cmd" --dry-run
call :wait
goto menu

:restore_real
call "%~dp0unpatch-firefox.cmd"
call :wait
goto menu

:readme
start "" "%~dp0README.md"
goto menu

:wait
echo.
pause
exit /b 0

:quit
exit /b 0
