@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"

:menu
cls
echo Enable Unsigned Firefox Add-ons
echo.
echo 1  Check Firefox patch status
echo 2  Test setup with dry run
echo 3  Patch Firefox and choose profile
echo.
echo 4  Show Firefox profiles and add-on setting
echo 5  Test default profile add-on setting
echo 6  Set add-on setting for default profile
echo.
echo 7  Check startup cache
echo 8  Preview startup cache cleanup
echo 9  Clear startup cache
echo.
echo A  Check restore status
echo B  Test restore with dry run
echo C  Restore Firefox from rollback backup
echo P  Pick a profile and set add-on setting
echo.
echo H  Open README
echo Q  Quit
echo.
choice /C 123456789ABCPHQ /N /M "Choose an option: "

if errorlevel 15 goto quit
if errorlevel 14 goto readme
if errorlevel 13 goto pref_pick
if errorlevel 12 goto restore_real
if errorlevel 11 goto restore_dry_run
if errorlevel 10 goto restore_status
if errorlevel 9 goto cache_real
if errorlevel 8 goto cache_dry_run
if errorlevel 7 goto cache_status
if errorlevel 6 goto pref_real
if errorlevel 5 goto pref_dry_run
if errorlevel 4 goto pref_status
if errorlevel 3 goto full_setup
if errorlevel 2 goto full_setup_dry_run
if errorlevel 1 goto patch_status

:patch_status
call "%~dp0patch-firefox.cmd" --status
call :wait
goto menu

:full_setup_dry_run
call :select_profile
if errorlevel 2 goto menu
if errorlevel 1 call :wait & goto menu

echo.
echo Checking Firefox patch dry run...
call "%~dp0patch-firefox.cmd" --dry-run
if errorlevel 1 call :wait & goto menu
echo.
echo Checking the add-on setting for the selected Firefox profile...
call "%~dp0set-unsigned-addon-pref.cmd" --dry-run --profile "%SELECTED_PROFILE%"
if errorlevel 1 call :wait & goto menu
echo.
echo Checking startup cache dry run...
call "%~dp0clear-startup-cache.cmd" --dry-run
call :wait
goto menu

:full_setup
call :confirm_full_setup
if errorlevel 2 goto menu
if errorlevel 1 call :wait & goto menu

call :select_profile
if errorlevel 2 goto menu
if errorlevel 1 call :wait & goto menu

echo.
echo Checking the add-on setting for the selected Firefox profile...
call "%~dp0set-unsigned-addon-pref.cmd" --dry-run --profile "%SELECTED_PROFILE%"
if errorlevel 1 call :wait & goto menu

set "FIREFOX_PATCH_ASSUME_YES=1"
echo.
echo Patching Firefox...
call "%~dp0patch-firefox.cmd"
if errorlevel 1 goto full_setup_done
echo.
echo Setting the add-on setting for the selected Firefox profile...
call "%~dp0set-unsigned-addon-pref.cmd" --profile "%SELECTED_PROFILE%"
if errorlevel 1 goto full_setup_done
echo.
echo Clearing Firefox startup cache...
call "%~dp0clear-startup-cache.cmd"

:full_setup_done
set "FIREFOX_PATCH_ASSUME_YES="
call :wait
goto menu

:pref_status
call "%~dp0set-unsigned-addon-pref.cmd" --status
call :wait
goto menu

:pref_dry_run
call "%~dp0set-unsigned-addon-pref.cmd" --dry-run
call :wait
goto menu

:pref_real
call "%~dp0set-unsigned-addon-pref.cmd"
call :wait
goto menu

:pref_pick
call :select_profile
if errorlevel 1 call :wait & goto menu
call "%~dp0set-unsigned-addon-pref.cmd" --profile "%SELECTED_PROFILE%"
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

:confirm_full_setup
echo.
echo This will patch the Firefox program files, ask which Firefox profile
echo should allow unsigned add-ons, and clear rebuildable startup cache.
echo If Firefox is installed under Program Files, Windows may ask for
echo administrator approval during the patch step.
echo.
echo A Firefox profile is a separate Firefox user-data folder. Choose the
echo profile where you will install the unsigned add-on.
echo.
echo Startup cache cleanup does not delete bookmarks, passwords, history,
echo form data, settings, cookies, or add-ons.
echo Firefox must be closed. Run option 2 first to test without changing files.
echo.
choice /C YN /N /M "Continue? [Y/N] "
if errorlevel 2 (
    echo Cancelled. No files were changed.
    exit /b 2
)
exit /b 0

:select_profile
set "PROFILE_LIST="
set "SELECTED_PROFILE="
for /f "delims=" %%T in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "[System.IO.Path]::GetTempFileName()"') do set "PROFILE_LIST=%%T"
if not defined PROFILE_LIST (
    echo Couldn't create a temporary profile list.
    exit /b 1
)
call "%~dp0set-unsigned-addon-pref.cmd" --list-profiles > "%PROFILE_LIST%"
if errorlevel 1 (
    del "%PROFILE_LIST%" >nul 2>nul
    exit /b 1
)

echo.
echo Available Firefox profiles:
echo A profile is where Firefox stores settings and add-ons for one setup.
for /f "usebackq tokens=1,2,3 delims=|" %%A in ("%PROFILE_LIST%") do (
    if /I "%%C"=="default" (
        echo %%A  %%B  [default]
    ) else (
        echo %%A  %%B
    )
)
echo.
choice /C 123456789Q /N /M "Choose profile number, or Q to cancel: "
set "PROFILE_CHOICE=%ERRORLEVEL%"
if "%PROFILE_CHOICE%"=="10" (
    del "%PROFILE_LIST%" >nul 2>nul
    echo Cancelled. No add-on setting was changed.
    exit /b 2
)

for /f "usebackq tokens=1,2,3 delims=|" %%A in ("%PROFILE_LIST%") do (
    if "%%A"=="!PROFILE_CHOICE!" set "SELECTED_PROFILE=%%B"
)
del "%PROFILE_LIST%" >nul 2>nul

if not defined SELECTED_PROFILE (
    echo Invalid profile selection. No add-on setting was changed.
    exit /b 1
)

exit /b 0

:wait
echo.
pause
exit /b 0

:quit
exit /b 0
