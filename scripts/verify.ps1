Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RequiredFiles = @(
    'README.md',
    'SUPPORT.md',
    'patch-firefox.cmd',
    'unpatch-firefox.cmd',
    'clear-startup-cache.cmd',
    'patch-firefox.sh',
    'unpatch-firefox.sh',
    'clear-startup-cache.sh',
    'scripts\verify-fixture.sh',
    '.github\workflows\verify.yml',
    '.github\dependabot.yml',
    'AGENTS.md',
    'CONTRIBUTING.md',
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

$PatchRequiredPatterns = @(
    '#!/usr/bin/env bash',
    'set -euo pipefail',
    '--dry-run',
    '--status',
    '--mozilla-home',
    'resolve_mozilla_home',
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
    'repack_omni',
    'verify_new_archive',
    'print_status',
    'app_constants_value',
    'extract_omni',
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

foreach ($Pattern in @('#!/usr/bin/env bash', 'set -euo pipefail', '--dry-run', '--status', '--mozilla-home', 'resolve_mozilla_home', 'Detected MOZILLA_HOME=', 'MOZILLA_HOME', 'omni.ja', 'omni-orig.ja', 'RESTORE_FILE', 'assert_firefox_not_running', 'SKIP_FIREFOX_PROCESS_CHECK', 'is_windows_admin', 'relaunch_elevated', 'ELEVATED_FIREFOX_PATCH', 'Requesting Windows administrator permission', 'print_status', 'app_constants_value', 'extract_omni', 'print_extract_details', 'Extraction details', 'mv "$RESTORE_FILE" "$OMNI_FILE"', 'rm "$ORIGINAL_OMNI_FILE"')) {
    if (-not $UnpatchScript.Contains($Pattern)) {
        throw "unpatch-firefox.sh is missing expected rollback operation: $Pattern"
    }
}

foreach ($Pattern in @('#!/usr/bin/env bash', 'set -euo pipefail', '--dry-run', '--profile', '--profiles-ini', 'profiles.ini', 'read_profiles_ini', 'startup_cache_dirs', 'remove_startup_cache', 'No Firefox profiles found', 'No startupCache directories found', 'Dry run OK')) {
    if (-not $StartupCacheScript.Contains($Pattern)) {
        throw "clear-startup-cache.sh is missing expected cache cleanup behavior: $Pattern"
    }
}

foreach ($Launcher in @(
    @{ Name = 'patch-firefox.cmd'; Text = $PatchLauncher },
    @{ Name = 'unpatch-firefox.cmd'; Text = $UnpatchLauncher },
    @{ Name = 'clear-startup-cache.cmd'; Text = $StartupCacheLauncher }
)) {
    foreach ($Pattern in @('@echo off', '%~dpn0.sh', ':find_bash', 'Git\bin\bash.exe', 'where bash.exe', ':is_wsl_bash', 'System32\bash.exe', 'Microsoft\WindowsApps\bash.exe', "Couldn't find Git Bash", '"%BASH_EXE%" "%SCRIPT%" %*')) {
        if (-not $Launcher.Text.Contains($Pattern)) {
            throw "$($Launcher.Name) is missing expected launcher behavior: $Pattern"
        }
    }
}

$FixtureScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts\verify-fixture.sh') -Raw
foreach ($Pattern in @('modern-sysm', 'legacy-jsm', 'status-mode', 'modern-dry-run-readonly-home', 'unpatch-dry-run-readonly-home', 'mozilla-home-argument', 'already-false', 'missing-appconstants', 'running-firefox-guard', 'startup-cache-profiles-ini', 'POWERSHELL_ZIP_BIN', '--dry-run', '--status')) {
    if (-not $FixtureScript.Contains($Pattern)) {
        throw "scripts\verify-fixture.sh is missing expected test coverage: $Pattern"
    }
}

$WorkflowScript = Get-Content -LiteralPath (Join-Path $RepoRoot '.github\workflows\verify.yml') -Raw
foreach ($Pattern in @('actions/checkout@v4', 'bash -n patch-firefox.sh', 'bash -n clear-startup-cache.sh', 'bash scripts/verify-fixture.sh')) {
    if (-not $WorkflowScript.Contains($Pattern)) {
        throw ".github\workflows\verify.yml is missing expected CI step: $Pattern"
    }
}

$DependabotConfig = Get-Content -LiteralPath (Join-Path $RepoRoot '.github\dependabot.yml') -Raw
foreach ($Pattern in @('package-ecosystem: "github-actions"', 'interval: "monthly"')) {
    if (-not $DependabotConfig.Contains($Pattern)) {
        throw ".github\dependabot.yml is missing expected upkeep setting: $Pattern"
    }
}

$SupportPolicy = Get-Content -LiteralPath (Join-Path $RepoRoot 'SUPPORT.md') -Raw
foreach ($Pattern in @('provided as-is', 'no support commitment', 'patch-firefox.cmd --status', 'patch-firefox.cmd --dry-run', 'patch-firefox.sh --status', 'patch-firefox.sh --dry-run', 'clear-startup-cache.cmd --dry-run', 'clear-startup-cache.sh --dry-run')) {
    if (-not $SupportPolicy.Contains($Pattern)) {
        throw "SUPPORT.md is missing expected policy text: $Pattern"
    }
}

$Readme = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw
foreach ($Pattern in @('patch-firefox.cmd --status', 'patch-firefox.cmd --dry-run', 'clear-startup-cache.cmd --dry-run', 'clear-startup-cache.sh --dry-run', 'C:\Program Files\Mozilla Firefox')) {
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
