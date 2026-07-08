Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RequiredFiles = @(
    'README.md',
    'CHANGELOG.md',
    'MAINTENANCE.md',
    'SUPPORT.md',
    'START-WINDOWS.cmd',
    'LICENSE',
    'patch-firefox.cmd',
    'unpatch-firefox.cmd',
    'clear-startup-cache.cmd',
    'patch-firefox.sh',
    'unpatch-firefox.sh',
    'clear-startup-cache.sh',
    'scripts\verify-fixture.sh',
    '.github\workflows-disabled\verify.yml',
    '.github\dependabot-disabled.yml',
    '.github\ISSUE_TEMPLATE\config.yml',
    'AGENTS.md',
    'SECURITY.md',
    '.editorconfig',
    '.gitattributes'
)

foreach ($RelativePath in $RequiredFiles) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required file: $RelativePath"
    }
}

$PatchScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'patch-firefox.sh') -Raw
$UnpatchScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'unpatch-firefox.sh') -Raw
$StartupCacheScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'clear-startup-cache.sh') -Raw
$PatchLauncher = Get-Content -LiteralPath (Join-Path $RepoRoot 'patch-firefox.cmd') -Raw
$UnpatchLauncher = Get-Content -LiteralPath (Join-Path $RepoRoot 'unpatch-firefox.cmd') -Raw
$StartupCacheLauncher = Get-Content -LiteralPath (Join-Path $RepoRoot 'clear-startup-cache.cmd') -Raw
$StartWindowsLauncher = Get-Content -LiteralPath (Join-Path $RepoRoot 'START-WINDOWS.cmd') -Raw

$License = Get-Content -LiteralPath (Join-Path $RepoRoot 'LICENSE') -Raw
foreach ($Pattern in @('Source-Available Showcase License', 'Copyright (c) 2026 NeatWolf', 'personal local testing only', 'artificial-intelligence training', 'provided as-is')) {
    if (-not $License.Contains($Pattern)) {
        throw "LICENSE is missing expected source-available/no-AI-training text: $Pattern"
    }
}

$PatchRequiredPatterns = @(
    '#!/usr/bin/env bash',
    'set -euo pipefail',
    '--dry-run',
    '--status',
    '--mozilla-home',
    'resolve_mozilla_home',
    'normalize_mozilla_home_path',
    'cygpath -u "$value"',
    'Detected MOZILLA_HOME=',
    'MOZILLA_HOME',
    'omni.ja',
    'omni-orig.ja',
    'mktemp -d',
    'trap cleanup EXIT',
    'AppConstants.sys.mjs',
    'AppConstants.jsm',
    'MOZ_REQUIRE_SIGNING',
    'patch_require_signing',
    'MOZ_REQUIRE_SIGNING:[[:space:]]*true,',
    'NEW_OMNI_FILE',
    'omni.ja.new.$$',
    'assert_firefox_not_running',
    'SKIP_FIREFOX_PROCESS_CHECK',
    'is_windows_admin',
    'relaunch_elevated',
    'ELEVATED_FIREFOX_PATCH',
    'Requesting Windows administrator permission',
    'write_access_status',
    'write access:',
    'Expected a directory containing omni.ja',
    'Pass the folder that contains omni.ja',
    'repacker_status',
    'repacker:',
    'print_patch_next_step',
    'next step:',
    'without --dry-run to patch Firefox',
    'clear Firefox startupCache before starting Firefox',
    'repack_omni',
    'verify_new_archive',
    'print_status',
    'Patch refused because rollback backup already exists',
    'MOZ_REQUIRE_SIGNING is already false in AppConstants.',
    "Firefox's archive layout may have changed",
    'application_ini_value',
    'application.ini',
    'application:',
    'build id:',
    'app_constants_value',
    'extract_omni',
    'unzip_status',
    'extra bytes at beginning or within zipfile',
    'find_app_constants "$target_dir"',
    "Couldn't extract",
    'unzip reported warnings that are not safe to ignore',
    'unzip failed with exit code',
    'print_extract_details',
    'Extraction details',
    'POWERSHELL_ZIP_BIN',
    'ZipArchive',
    'ZIP_STORED'
)

foreach ($Pattern in $PatchRequiredPatterns) {
    if (-not $PatchScript.Contains($Pattern)) {
        throw "patch-firefox.sh is missing expected safeguard or operation: $Pattern"
    }
}

foreach ($Pattern in @('#!/usr/bin/env bash', 'set -euo pipefail', '--dry-run', '--status', '--mozilla-home', 'resolve_mozilla_home', 'normalize_mozilla_home_path', 'cygpath -u "$value"', 'Detected MOZILLA_HOME=', 'MOZILLA_HOME', 'omni.ja', 'omni-orig.ja', 'RESTORE_FILE', 'No rollback backup found', 'Nothing was restored', 'assert_firefox_not_running', 'SKIP_FIREFOX_PROCESS_CHECK', 'is_windows_admin', 'relaunch_elevated', 'ELEVATED_FIREFOX_PATCH', 'Requesting Windows administrator permission', 'write_access_status', 'write access:', 'Expected a directory containing omni.ja', 'Pass the folder that contains omni.ja', 'print_restore_next_step', 'next step:', 'without --dry-run to restore Firefox', 'update Firefox, then patch again if unsigned addons are still needed', 'print_status', 'application_ini_value', 'application.ini', 'application:', 'build id:', 'app_constants_value', 'extract_omni', 'unzip_status', 'extra bytes at beginning or within zipfile', 'find_app_constants "$target_dir"', "Couldn't extract", 'unzip reported warnings that are not safe to ignore', 'unzip failed with exit code', 'print_extract_details', 'Extraction details', 'mv "$RESTORE_FILE" "$OMNI_FILE"', 'rm "$ORIGINAL_OMNI_FILE"')) {
    if (-not $UnpatchScript.Contains($Pattern)) {
        throw "unpatch-firefox.sh is missing expected rollback operation: $Pattern"
    }
}

foreach ($Pattern in @('#!/usr/bin/env bash', 'set -euo pipefail', '--dry-run', '--status', 'STATUS_MODE', '--profile', '--profiles-ini', 'profiles.ini', 'normalize_input_path', 'read_profiles_ini', 'startup_cache_dirs', 'remove_startup_cache', 'firefox_is_running', 'assert_firefox_not_running', 'warn_if_firefox_running_for_dry_run', 'warning: Firefox appears to be running', 'cleanup for real', 'SKIP_FIREFOX_PROCESS_CHECK', 'print_status', 'startupCache: present', 'startupCache: absent', 'startupCache directories:', 'firefox process:', 'close Firefox before clearing startupCache', 'preview startupCache cleanup', 'no startupCache cleanup needed', 'if Firefox uses an unusual profile location', 'Pass a Firefox profile directory', 'Pass a Firefox profiles.ini file', 'No Firefox profiles found', 'No startupCache directories found', 'Dry run OK', 'without --dry-run to clear the listed startupCache directories', 'start Firefox and verify MOZ_REQUIRE_SIGNING')) {
    if (-not $StartupCacheScript.Contains($Pattern)) {
        throw "clear-startup-cache.sh is missing expected cache cleanup behavior: $Pattern"
    }
}

foreach ($Launcher in @(
    @{ Name = 'patch-firefox.cmd'; Text = $PatchLauncher },
    @{ Name = 'unpatch-firefox.cmd'; Text = $UnpatchLauncher },
    @{ Name = 'clear-startup-cache.cmd'; Text = $StartupCacheLauncher }
)) {
    foreach ($Pattern in @('@echo off', 'PAUSE_ON_ERROR', 'FIREFOX_PATCH_NO_PAUSE', 'FIREFOX_PATCH_SKIP_BASH_SEARCH', 'CONFIRM_MODIFY', ':classify_args', '--status', ':confirm_modify', 'Safer first:', '"%~nx0" --dry-run %*', 'choice /C YN /N', 'Cancelled. No files were changed.', ':pause_on_error', 'double-clicked .cmd', 'pause >nul', '%~dpn0.sh', ':find_bash', ':bash_not_found', 'Git\bin\bash.exe', 'where bash.exe', ':is_wsl_bash', 'System32\bash.exe', 'Microsoft\WindowsApps\bash.exe', "Couldn't find Git Bash", 'Install Git for Windows', 'Git for Windows includes Git Bash', 'WSL bash is not used', '"%BASH_EXE%" "%SCRIPT%" %*')) {
        if (-not $Launcher.Text.Contains($Pattern)) {
            throw "$($Launcher.Name) is missing expected launcher behavior: $Pattern"
        }
    }
}

foreach ($Pattern in @('After a successful restore, omni-orig.ja is removed.')) {
    if (-not $UnpatchLauncher.Contains($Pattern)) {
        throw "unpatch-firefox.cmd is missing expected restore confirmation text: $Pattern"
    }
}

foreach ($Pattern in @('Firefox must be closed before clearing startupCache.')) {
    if (-not $StartupCacheLauncher.Contains($Pattern)) {
        throw "clear-startup-cache.cmd is missing expected cache confirmation text: $Pattern"
    }
}

foreach ($Pattern in @('@echo off', 'Enable Unsigned Firefox Add-ons', 'choice /C 123456789HQ /N', 'Check Firefox patch status', 'Test Firefox patch with dry run', 'Patch Firefox', 'Check startup-cache status', 'Test startup-cache cleanup with dry run', 'Clear startup cache', 'Check restore status', 'Test restore with dry run', 'Restore Firefox from rollback backup', 'Open README', 'patch-firefox.cmd" --status', 'patch-firefox.cmd" --dry-run', 'clear-startup-cache.cmd" --status', 'clear-startup-cache.cmd" --dry-run', 'unpatch-firefox.cmd" --status', 'unpatch-firefox.cmd" --dry-run', 'start "" "%~dp0README.md"', 'pause')) {
    if (-not $StartWindowsLauncher.Contains($Pattern)) {
        throw "START-WINDOWS.cmd is missing expected menu behavior: $Pattern"
    }
}

$PatchLauncherPath = Join-Path $RepoRoot 'patch-firefox.cmd'
$SavedNoPause = $env:FIREFOX_PATCH_NO_PAUSE
$SavedSkipBashSearch = $env:FIREFOX_PATCH_SKIP_BASH_SEARCH
try {
    $env:FIREFOX_PATCH_NO_PAUSE = '1'
    $env:FIREFOX_PATCH_SKIP_BASH_SEARCH = '1'

    $MissingBashOutput = & cmd.exe /d /c "`"$PatchLauncherPath`" --help" 2>&1
    $MissingBashExitCode = $LASTEXITCODE
    $MissingBashText = $MissingBashOutput -join "`n"

    if ($MissingBashExitCode -eq 0) {
        throw 'Windows launcher missing-Git-Bash check unexpectedly succeeded.'
    }

    foreach ($Pattern in @("Couldn't find Git Bash", 'Install Git for Windows', 'Reopen this launcher after installing it', 'WSL bash is not used by this launcher')) {
        if (-not $MissingBashText.Contains($Pattern)) {
            throw "Windows launcher missing-Git-Bash output is missing: $Pattern"
        }
    }
} finally {
    if ($null -eq $SavedNoPause) {
        Remove-Item Env:FIREFOX_PATCH_NO_PAUSE -ErrorAction SilentlyContinue
    } else {
        $env:FIREFOX_PATCH_NO_PAUSE = $SavedNoPause
    }
    if ($null -eq $SavedSkipBashSearch) {
        Remove-Item Env:FIREFOX_PATCH_SKIP_BASH_SEARCH -ErrorAction SilentlyContinue
    } else {
        $env:FIREFOX_PATCH_SKIP_BASH_SEARCH = $SavedSkipBashSearch
    }
}

$FixtureScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts\verify-fixture.sh') -Raw
foreach ($Pattern in @('modern-sysm', 'legacy-jsm', 'status-mode', 'application: Firefox 99.0', 'build id: 20260101000000', 'write access: available', 'repacker:', 'next step:', 'clear Firefox startupCache before starting Firefox', 'Removed rollback backup:', 'update Firefox, then patch again if unsigned addons are still needed', 'start Firefox and verify MOZ_REQUIRE_SIGNING', 'close Firefox before patching', 'close Firefox before restoring', 'close Firefox before clearing startupCache', 'without --dry-run to patch Firefox', 'without --dry-run to restore Firefox', 'without --dry-run to clear the listed startupCache directories', 'preview startupCache cleanup', 'no startupCache cleanup needed', 'if Firefox uses an unusual profile location', 'path-errors', 'Pass the folder that contains omni.ja', 'Pass a Firefox profile directory', 'Pass a Firefox profiles.ini file', 'Patch refused because rollback backup already exists', 'No rollback backup found', 'MOZ_REQUIRE_SIGNING is already false in AppConstants.', 'modern-dry-run-readonly-home', 'prefixed-omni-warning', 'corrupt-omni-crc', 'CORRUPTME_PAYLOAD', 'corrupt archive still reported Dry run OK', 'unpatch-dry-run-readonly-home', 'mozilla-home-argument', 'windows_home', 'already-false', 'missing-appconstants', 'running-firefox-guard', 'running-firefox-unpatch-guard', 'startup-cache-profiles-ini', 'startupCache: present', 'firefox process: running', 'running-dry-run', 'warning: Firefox appears to be running. Close Firefox before running cleanup for real.', 'running dry-run removed startupCache', 'windows-absolute', 'Windows --profile', 'POWERSHELL_ZIP_BIN', '--dry-run', '--status')) {
    if (-not $FixtureScript.Contains($Pattern)) {
        throw "scripts\verify-fixture.sh is missing expected test coverage: $Pattern"
    }
}

$WorkflowScript = Get-Content -LiteralPath (Join-Path $RepoRoot '.github\workflows-disabled\verify.yml') -Raw
foreach ($Pattern in @('actions/checkout@v4', 'bash -n patch-firefox.sh', 'bash -n clear-startup-cache.sh', 'bash scripts/verify-fixture.sh', 'windows-latest', 'powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1')) {
    if (-not $WorkflowScript.Contains($Pattern)) {
        throw ".github\workflows-disabled\verify.yml is missing expected parked CI step: $Pattern"
    }
}

$DependabotConfig = Get-Content -LiteralPath (Join-Path $RepoRoot '.github\dependabot-disabled.yml') -Raw
foreach ($Pattern in @('package-ecosystem: "github-actions"', 'interval: "monthly"')) {
    if (-not $DependabotConfig.Contains($Pattern)) {
        throw ".github\dependabot-disabled.yml is missing expected parked upkeep setting: $Pattern"
    }
}

$IssueTemplateConfig = Get-Content -LiteralPath (Join-Path $RepoRoot '.github\ISSUE_TEMPLATE\config.yml') -Raw
foreach ($Pattern in @('blank_issues_enabled: false', 'No support policy', 'SUPPORT.md')) {
    if (-not $IssueTemplateConfig.Contains($Pattern)) {
        throw ".github\ISSUE_TEMPLATE\config.yml is missing expected support boundary setting: $Pattern"
    }
}

$SupportPolicy = Get-Content -LiteralPath (Join-Path $RepoRoot 'SUPPORT.md') -Raw
foreach ($Pattern in @('provided as-is', 'no support commitment', 'no help desk', 'no compatibility guarantee', 'restore from your own backup', 'reinstall Firefox', 'patch-firefox.cmd --status', 'patch-firefox.cmd --dry-run', 'patch-firefox.sh --status', 'patch-firefox.sh --dry-run', 'Python is optional', 'Administrator permission is not required')) {
    if (-not $SupportPolicy.Contains($Pattern)) {
        throw "SUPPORT.md is missing expected policy text: $Pattern"
    }
}

$Changelog = Get-Content -LiteralPath (Join-Path $RepoRoot 'CHANGELOG.md') -Raw
foreach ($Pattern in @('Changelog', 'Unreleased', 'double-click Windows start menu', 'release ZIPs', 'download, folder placement', 'source-available showcase license', 'Parked GitHub Actions', 'as-is/no-support', 'corrupt archives', 'Windows CI', 'safer Windows launchers', 'write access', 'path error', 'restore removes', 'running Firefox guard', 'repacker', 'success next-step', 'next-step', 'startupCache', 'dry-run', 'matching dry-run command', 'startupCache dry-run warning', 'PowerShell/.NET archive rebuilding', 'repository verification')) {
    if (-not $Changelog.Contains($Pattern)) {
        throw "CHANGELOG.md is missing expected summary text: $Pattern"
    }
}

$MaintenanceNotes = Get-Content -LiteralPath (Join-Path $RepoRoot 'MAINTENANCE.md') -Raw
foreach ($Pattern in @('maintained as-is', 'source-available showcase software', 'no-AI-training', 'verify.ps1', 'Python optional', 'PowerShell/.NET fallback', 'CHANGELOG.md', 'disable Issues and Discussions', 'GitHub repository settings', 'GitHub Actions is currently parked', 'Dependabot for GitHub Actions is currently parked')) {
    if (-not $MaintenanceNotes.Contains($Pattern)) {
        throw "MAINTENANCE.md is missing expected maintenance note: $Pattern"
    }
}

$SecurityPolicy = Get-Content -LiteralPath (Join-Path $RepoRoot 'SECURITY.md') -Raw
foreach ($Pattern in @('No supported versions', 'provided as-is', 'Report Firefox vulnerabilities to Mozilla')) {
    if (-not $SecurityPolicy.Contains($Pattern)) {
        throw "SECURITY.md is missing expected policy text: $Pattern"
    }
}

$Readme = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw
foreach ($Pattern in @('This modifies a local Firefox install', 'no compatibility guarantee', 'Keep your own backup or be ready to reinstall Firefox', 'source-available showcase software', 'AI training', 'LICENSE', 'SUPPORT.md', 'latest release ZIP', 'Do not download files one by one', 'enable-unsigned-firefox-addons.zip', 'double-click `START-WINDOWS.cmd`', 'Do not put the scripts inside the Firefox install folder', 'Choose `1` to check Firefox patch status', 'Choose `2` to test the patch with a dry run', 'Advanced command-line use', 'patch-firefox.cmd --status', 'Firefox application version and build ID', 'archive repacker', 'next step', 'Successful commands print the next practical step', 'same command without `--dry-run`', 'patch-firefox.cmd --dry-run', 'matching `--dry-run` command', 'restore removes `omni-orig.ja`', 'ask for confirmation', 'modifying files', 'clear-startup-cache.cmd --status', 'startupCache folders are present', 'Firefox is still running', 'dry run warns', 'clear-startup-cache.cmd --dry-run', 'clear-startup-cache.sh --status', 'clear-startup-cache.sh --dry-run', 'folder that contains `omni.ja`', 'Firefox profile directory', 'Git for Windows includes Git Bash', 'START-WINDOWS.cmd', 'workflows-disabled', 'dependabot-disabled', 'CHANGELOG.md', 'MAINTENANCE.md', 'SECURITY.md', 'C:\Program Files\Mozilla Firefox', 'Windows paths such as', 'stop before rebuilding or restoring files')) {
    if (-not $Readme.Contains($Pattern)) {
        throw "README.md is missing expected Windows launcher guidance: $Pattern"
    }
}

$GitAttributes = Get-Content -LiteralPath (Join-Path $RepoRoot '.gitattributes') -Raw
if (-not $GitAttributes.Contains('*.cmd text eol=crlf')) {
    throw '.gitattributes must keep Windows launchers as CRLF.'
}

$WslBashPaths = @(
    (Join-Path $env:WINDIR 'System32\bash.exe'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\bash.exe')
)
$GitBashCandidates = @(
    'C:\Program Files\Git\bin\bash.exe',
    'C:\Program Files\Git\usr\bin\bash.exe'
)

$BashCandidates = @()
$PathBash = Get-Command bash -ErrorAction SilentlyContinue
if ($null -ne $PathBash) {
    $BashCandidates += $PathBash.Source
}
$BashCandidates += $GitBashCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

$UsableBash = $BashCandidates |
    Select-Object -Unique |
    Where-Object {
        $Candidate = $_
        -not ($WslBashPaths | Where-Object { [string]::Equals($_, $Candidate, [System.StringComparison]::OrdinalIgnoreCase) })
    } |
    Select-Object -First 1

if ($null -eq $UsableBash) {
    Write-Warning 'No non-WSL Bash was found; skipped bash -n syntax checks. Use Git Bash or run bash -n manually inside a working Unix-like environment.'
} else {
    $Scripts = @('patch-firefox.sh', 'unpatch-firefox.sh', 'clear-startup-cache.sh')
    foreach ($Script in $Scripts) {
        $ScriptPath = Join-Path $RepoRoot $Script
        & $UsableBash -n $ScriptPath
        if ($LASTEXITCODE -ne 0) {
            throw "Bash syntax check failed for $Script."
        }
    }

    $FixtureScriptPath = Join-Path $RepoRoot 'scripts\verify-fixture.sh'
    & $UsableBash -n $FixtureScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Bash syntax check failed for scripts\verify-fixture.sh.'
    }

    $Launchers = @('patch-firefox.cmd', 'unpatch-firefox.cmd', 'clear-startup-cache.cmd')
    foreach ($Launcher in $Launchers) {
        $LauncherPath = Join-Path $RepoRoot $Launcher
        & cmd.exe /d /c "`"$LauncherPath`" --help"
        if ($LASTEXITCODE -ne 0) {
            throw "Windows launcher help check failed for $Launcher."
        }

        $CancelOutput = & cmd.exe /d /c "echo N| `"$LauncherPath`"" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Windows launcher confirmation cancel check failed for $Launcher."
        }
        $CancelText = $CancelOutput -join "`n"
        foreach ($Pattern in @('Safer first:', "`"$Launcher`" --dry-run", 'Cancelled. No files were changed.')) {
            if (-not $CancelText.Contains($Pattern)) {
                throw "Windows launcher confirmation output for $Launcher is missing: $Pattern"
            }
        }
    }

    $MissingTools = @(& $UsableBash -lc 'for tool in unzip mktemp sed grep; do command -v "$tool" >/dev/null 2>&1 || echo "$tool"; done; command -v zip >/dev/null 2>&1 || command -v powershell.exe >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || echo "zip, powershell.exe, or python3/python"')
    if ($MissingTools.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace(($MissingTools -join ''))) {
        Write-Warning "Skipped fixture verification because Bash is missing: $($MissingTools -join ', ')"
    } else {
        & $UsableBash $FixtureScriptPath
        if ($LASTEXITCODE -ne 0) {
            throw 'Fixture verification failed.'
        }
    }
}

Write-Host 'Verification completed.'
