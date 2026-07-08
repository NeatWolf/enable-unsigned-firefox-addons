#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
STATUS_MODE=0
MOZILLA_HOME_ARG=""
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"
ORIGINAL_ARGS=("$@")

usage() {
    cat <<USAGE
Usage: $0 [--dry-run|--status] [--mozilla-home PATH]

Options:
  --dry-run              Build and verify a patched archive without modifying Firefox.
  --status               Inspect the Firefox install without modifying it.
  --mozilla-home PATH    Firefox install directory containing omni.ja.
  -h, --help             Show this help.

If --mozilla-home is omitted, MOZILLA_HOME is used. If neither is set, the
script tries to auto-detect a Firefox install directory that contains omni.ja.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --status)
            STATUS_MODE=1
            shift
            ;;
        --mozilla-home)
            if [[ $# -lt 2 || -z $2 ]]; then
                echo "--mozilla-home requires a path"
                exit 1
            fi
            MOZILLA_HOME_ARG=$2
            shift 2
            ;;
        --mozilla-home=*)
            MOZILLA_HOME_ARG=${1#*=}
            if [[ -z $MOZILLA_HOME_ARG ]]; then
                echo "--mozilla-home requires a path"
                exit 1
            fi
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

if [[ $DRY_RUN -eq 1 && $STATUS_MODE -eq 1 ]]; then
    echo "Use either --dry-run or --status, not both"
    exit 1
fi

candidate_mozilla_homes() {
    local firefox_bin
    local firefox_dir
    local candidate

    if command -v firefox > /dev/null 2>&1; then
        firefox_bin=$(command -v firefox)
        firefox_dir=$(cd -- "${firefox_bin%/*}" 2> /dev/null && pwd -P || true)
        if [[ -n $firefox_dir ]]; then
            printf '%s\n' "$firefox_dir"
        fi
    fi

    for candidate in \
        "/c/Program Files/Mozilla Firefox" \
        "/c/Program Files (x86)/Mozilla Firefox" \
        "/mnt/c/Program Files/Mozilla Firefox" \
        "/Applications/Firefox.app/Contents/Resources"; do
        printf '%s\n' "$candidate"
    done
}

normalize_mozilla_home_path() {
    local value=$1

    if [[ -z $value ]]; then
        return
    fi

    if [[ -d $value ]]; then
        printf '%s\n' "$value"
        return
    fi

    if command -v cygpath > /dev/null 2>&1 && [[ $value =~ ^[A-Za-z]:[\\/] || $value =~ ^\\\\ ]]; then
        cygpath -u "$value"
    else
        printf '%s\n' "$value"
    fi
}

resolve_mozilla_home() {
    local candidate
    local seen="|"
    local matches=()

    if [[ -n $MOZILLA_HOME_ARG ]]; then
        MOZILLA_HOME=$(normalize_mozilla_home_path "$MOZILLA_HOME_ARG")
        return
    fi

    if [[ -n ${MOZILLA_HOME:-} ]]; then
        MOZILLA_HOME=$(normalize_mozilla_home_path "$MOZILLA_HOME")
        return
    fi

    while IFS= read -r candidate; do
        if [[ -f "$candidate/omni.ja" && $seen != *"|$candidate|"* ]]; then
            matches+=("$candidate")
            seen="${seen}${candidate}|"
        fi
    done < <(candidate_mozilla_homes)

    case ${#matches[@]} in
        1)
            MOZILLA_HOME=${matches[0]}
            echo "Detected MOZILLA_HOME=$MOZILLA_HOME"
            ;;
        0)
            echo "Set MOZILLA_HOME or pass --mozilla-home /path/to/firefox"
            exit 1
            ;;
        *)
            echo "Found multiple Firefox installs. Pass --mozilla-home explicitly:"
            for candidate in "${matches[@]}"; do
                echo "  $candidate"
            done
            exit 1
            ;;
    esac
}

require_tools() {
    local tool
    for tool in "$@"; do
        if ! command -v "$tool" > /dev/null 2>&1; then
            echo "Couldn't find required tool: $tool"
            exit 1
        fi
    done
}

is_windows_admin() {
    local result

    if ! command -v powershell.exe > /dev/null 2>&1; then
        return 1
    fi

    result=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { "1" } else { "0" }
' 2> /dev/null | tr -d '\r' || true)

    [[ $result == "1" ]]
}

bash_quote() {
    printf '%q' "$1"
}

relaunch_elevated() {
    local action=$1
    local bash_win
    local elevated_command
    local arg

    if [[ ${ELEVATED_FIREFOX_PATCH:-} == "1" ]]; then
        return 1
    fi

    if ! command -v powershell.exe > /dev/null 2>&1 || ! command -v cygpath > /dev/null 2>&1; then
        return 1
    fi

    if is_windows_admin; then
        return 1
    fi

    bash_win=$(cygpath -w "$BASH")
    elevated_command="cd $(bash_quote "$PWD") && MOZILLA_HOME=$(bash_quote "$MOZILLA_HOME") ELEVATED_FIREFOX_PATCH=1 $(bash_quote "$SCRIPT_PATH")"
    for arg in "${ORIGINAL_ARGS[@]}"; do
        elevated_command+=" $(bash_quote "$arg")"
    done

    echo "$action requires write access to $MOZILLA_HOME."
    echo "Requesting Windows administrator permission..."
    ELEVATED_BASH_WIN="$bash_win" ELEVATED_COMMAND="$elevated_command" powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
try {
    $process = Start-Process -FilePath $env:ELEVATED_BASH_WIN -ArgumentList @("-lc", $env:ELEVATED_COMMAND) -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
} catch {
    Write-Error $_
    exit 1
}
'
    exit $?
}

ensure_write_access_or_relaunch() {
    local action=$1

    if [[ -w $MOZILLA_HOME && -w $OMNI_FILE ]]; then
        return
    fi

    if is_windows_admin; then
        return
    fi

    relaunch_elevated "$action"

    echo "$action requires write access to $MOZILLA_HOME."
    echo "Approve the Windows UAC prompt, run Git Bash as Administrator, or use a Firefox install directory you can write to."
    exit 1
}

write_access_status() {
    if [[ -w $MOZILLA_HOME && -w $OMNI_FILE ]]; then
        printf 'available\n'
    elif is_windows_admin; then
        printf 'available as administrator\n'
    else
        printf 'requires administrator permission\n'
    fi
}

repacker_status() {
    # Status mode is a safe place to show what a future patch run would use
    # to rebuild omni.ja. Keep these labels simple because users may paste
    # this output somewhere or read it before trying --dry-run.
    if command -v zip > /dev/null 2>&1; then
        printf 'Info-ZIP zip\n'
    elif command -v powershell.exe > /dev/null 2>&1; then
        printf 'PowerShell/.NET ZipArchive\n'
    elif command -v python3 > /dev/null 2>&1; then
        printf 'Python zipfile fallback (python3)\n'
    elif command -v python > /dev/null 2>&1; then
        printf 'Python zipfile fallback (python)\n'
    else
        printf 'missing\n'
    fi
}

print_patch_next_step() {
    local require_signing=$1
    local firefox_running=$2
    local repacker=$3

    if [[ $require_signing == "false" && -f $ORIGINAL_OMNI_FILE ]]; then
        echo "next step: no patch needed; use unpatch-firefox before updating Firefox."
    elif [[ $require_signing == "false" ]]; then
        echo "next step: no patch needed; no rollback backup was found."
    elif [[ -f $ORIGINAL_OMNI_FILE ]]; then
        echo "next step: restore or remove the leftover rollback backup before patching again."
    elif [[ $firefox_running -eq 1 ]]; then
        echo "next step: close Firefox before patching."
    elif [[ $repacker == "missing" ]]; then
        echo "next step: install Info-ZIP zip or use Windows PowerShell before patching."
    elif [[ $require_signing == "true" ]]; then
        echo "next step: run this script with --dry-run before patching."
    fi
}

firefox_is_running_for_home() {
    local mozilla_home=$1
    local mozilla_home_physical
    local mozilla_home_win
    local ps_output
    local pid
    local exe_path
    local exe_dir

    if [[ ${SKIP_FIREFOX_PROCESS_CHECK:-} == "1" ]]; then
        return 1
    fi

    if command -v powershell.exe > /dev/null 2>&1; then
        mozilla_home_win=$mozilla_home
        if command -v cygpath > /dev/null 2>&1; then
            mozilla_home_win=$(cygpath -w "$mozilla_home")
        fi

        ps_output=$(MOZILLA_HOME_WIN="$mozilla_home_win" powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
$target = [System.IO.Path]::GetFullPath($env:MOZILLA_HOME_WIN).TrimEnd("\", "/")
$matches = Get-Process -Name firefox -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Path -and
        [System.IO.Path]::GetDirectoryName($_.Path).TrimEnd("\", "/").Equals($target, [System.StringComparison]::OrdinalIgnoreCase)
    } |
    Select-Object -First 1 -ExpandProperty Id
if ($matches) { Write-Output $matches }
' 2> /dev/null | tr -d '\r' || true)

        if [[ -n $ps_output ]]; then
            return 0
        fi

        return 1
    fi

    if [[ -d /proc ]] && command -v pgrep > /dev/null 2>&1 && command -v readlink > /dev/null 2>&1; then
        mozilla_home_physical=$(cd -- "$mozilla_home" 2> /dev/null && pwd -P || printf '%s\n' "$mozilla_home")
        while IFS= read -r pid; do
            exe_path=$(readlink "/proc/$pid/exe" 2> /dev/null || true)
            if [[ -z $exe_path ]]; then
                continue
            fi
            exe_dir=$(cd -- "$(dirname -- "$exe_path")" 2> /dev/null && pwd -P || true)
            if [[ $exe_dir == "$mozilla_home_physical" ]]; then
                return 0
            fi
        done < <(pgrep -x firefox || true)
    fi

    return 1
}

find_app_constants() {
    local root=$1
    local candidate

    for candidate in "$root/modules/AppConstants.sys.mjs" "$root/modules/AppConstants.jsm"; do
        if [[ -f $candidate ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

app_constants_value() {
    local app_constants_file=$1
    local signline
    local current_const

    if grep -Eq "^[[:space:]]*MOZ_REQUIRE_SIGNING:[[:space:]]*false," "$app_constants_file"; then
        printf 'false\n'
        return 0
    fi

    if grep -Eq "^[[:space:]]*MOZ_REQUIRE_SIGNING:[[:space:]]*true," "$app_constants_file"; then
        printf 'true\n'
        return 0
    fi

    signline=$(grep -n "MOZ_REQUIRE_SIGNING:" "$app_constants_file" | cut -d: -f 1 | head -n 1 || true)
    if [[ -z $signline ]]; then
        printf 'unknown\n'
        return 1
    fi

    current_const=$(sed -n "$((signline + 2))p" "$app_constants_file")
    case "$current_const" in
        "  false,")
            printf 'false\n'
            ;;
        "  true,")
            printf 'true\n'
            ;;
        *)
            printf 'unknown\n'
            return 1
            ;;
    esac
}

app_constants_is_false() {
    local app_constants_file=$1
    [[ $(app_constants_value "$app_constants_file") == "false" ]]
}

application_ini_value() {
    local ini_file=$1
    local key=$2
    local line

    line=$(grep -m 1 "^$key=" "$ini_file" || true)
    if [[ -n $line ]]; then
        printf '%s\n' "${line#*=}"
    fi
}

assert_firefox_not_running() {
    if firefox_is_running_for_home "$MOZILLA_HOME"; then
        echo "Firefox appears to be running from $MOZILLA_HOME. Close Firefox before modifying omni.ja."
        echo "Set SKIP_FIREFOX_PROCESS_CHECK=1 only if you have verified it is safe to continue."
        exit 1
    fi
}

extract_omni() {
    local archive=$1
    local target_dir=$2
    local log_file=$3

    # Firefox omni.ja often emits harmless unzip warnings; callers validate
    # AppConstants after extraction and print this log only on real failures.
    : > "$log_file"
    unzip -q -d "$target_dir" "$archive" > /dev/null 2> "$log_file" || true
}

print_extract_details() {
    local log_file=$1

    if [[ -s $log_file ]]; then
        echo "Extraction details:"
        sed -e 's/^/  /' "$log_file"
    fi
}

patch_require_signing() {
    local app_constants_file=$1
    local signline
    local current_const

    if app_constants_is_false "$app_constants_file"; then
        echo "MOZ_REQUIRE_SIGNING is already false in AppConstants."
        echo "Nothing was changed. Run --status to check whether a rollback backup exists."
        exit 1
    fi

    if grep -Eq "^[[:space:]]*MOZ_REQUIRE_SIGNING:[[:space:]]*true," "$app_constants_file"; then
        sed -i -e "s/^\([[:space:]]*MOZ_REQUIRE_SIGNING:[[:space:]]*\)true,/\1false,/" "$app_constants_file"
        return
    fi

    signline=$(grep -n "MOZ_REQUIRE_SIGNING:" "$app_constants_file" | cut -d: -f 1 | head -n 1 || true)
    if [[ -z $signline ]]; then
        echo "Didn't find MOZ_REQUIRE_SIGNING in AppConstants"
        exit 1
    fi

    current_const=$(sed -n "$((signline + 2))p" "$app_constants_file")
    if [[ $current_const != "  true," ]]; then
        echo "Didn't find correct data in existing file"
        exit 1
    fi

    sed -i -e "$((signline + 2))s/true/false/" "$app_constants_file"
}

repack_omni() {
    local target=$1
    local powershell_root
    local powershell_target
    local python_target=$target

    if [[ -n $ZIP_BIN ]]; then
        zip -0DXqr "$target" .
        return
    fi

    if [[ -n $POWERSHELL_ZIP_BIN ]]; then
        powershell_root=$PWD
        powershell_target=$target
        if command -v cygpath > /dev/null 2>&1; then
            powershell_root=$(cygpath -w "$powershell_root")
            powershell_target=$(cygpath -w "$powershell_target")
        fi

        OMNI_ROOT="$powershell_root" OMNI_TARGET="$powershell_target" "$POWERSHELL_ZIP_BIN" -NoProfile -ExecutionPolicy Bypass -Command '
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
$root = [System.IO.Path]::GetFullPath($env:OMNI_ROOT).TrimEnd("\", "/")
$target = [System.IO.Path]::GetFullPath($env:OMNI_TARGET)
if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Force
}
$stream = [System.IO.File]::Open($target, [System.IO.FileMode]::CreateNew)
try {
    $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        Get-ChildItem -LiteralPath $root -Recurse -File |
            Sort-Object FullName |
            ForEach-Object {
                if ([System.String]::Equals($_.FullName, $target, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return
                }
                $relative = $_.FullName.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
                $entry = $archive.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::NoCompression)
                $entry.LastWriteTime = $_.LastWriteTime
                $entryStream = $entry.Open()
                $fileStream = [System.IO.File]::OpenRead($_.FullName)
                try {
                    $fileStream.CopyTo($entryStream)
                } finally {
                    $fileStream.Dispose()
                    $entryStream.Dispose()
                }
            }
    } finally {
        $archive.Dispose()
    }
} finally {
    $stream.Dispose()
}
'
        return
    fi

    if command -v cygpath > /dev/null 2>&1; then
        python_target=$(cygpath -w "$target")
    fi

    OMNI_TARGET="$python_target" "$PYTHON_BIN" - <<'PY'
import os
import zipfile
from pathlib import Path

target = Path(os.environ["OMNI_TARGET"])
if target.exists():
    target.unlink()

root = Path.cwd()
target = target.resolve()
with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_STORED) as archive:
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.resolve() != target:
            archive.write(path, path.relative_to(root).as_posix())
PY
}

verify_new_archive() {
    local app_constants_file

    VERIFY_TEMPDIR=$(mktemp -d)
    VERIFY_UNZIP_LOG=$(mktemp)
    extract_omni "$NEW_OMNI_FILE" "$VERIFY_TEMPDIR" "$VERIFY_UNZIP_LOG"

    app_constants_file=$(find_app_constants "$VERIFY_TEMPDIR" || true)
    if [[ -z $app_constants_file ]]; then
        echo "Replacement archive is missing AppConstants"
        print_extract_details "$VERIFY_UNZIP_LOG"
        exit 1
    fi

    if ! app_constants_is_false "$app_constants_file"; then
        echo "Replacement archive did not set MOZ_REQUIRE_SIGNING to false"
        print_extract_details "$VERIFY_UNZIP_LOG"
        exit 1
    fi

    rm -rf "$VERIFY_TEMPDIR"
    VERIFY_TEMPDIR=""
    rm -f "$VERIFY_UNZIP_LOG"
    VERIFY_UNZIP_LOG=""
}

print_status() {
    local app_constants_file
    local require_signing
    local application_ini="$MOZILLA_HOME/application.ini"
    local app_name
    local app_version
    local build_id
    local firefox_running=0
    local repacker

    echo "MOZILLA_HOME=$MOZILLA_HOME"
    echo "omni.ja: present"
    if [[ -f $application_ini ]]; then
        app_name=$(application_ini_value "$application_ini" "Name")
        app_version=$(application_ini_value "$application_ini" "Version")
        build_id=$(application_ini_value "$application_ini" "BuildID")
        echo "application: ${app_name:-unknown} ${app_version:-unknown}"
        echo "build id: ${build_id:-unknown}"
    else
        echo "application: unknown (application.ini not found)"
        echo "build id: unknown"
    fi

    if [[ -f $ORIGINAL_OMNI_FILE ]]; then
        echo "omni-orig.ja: present"
    else
        echo "omni-orig.ja: absent"
    fi
    echo "write access: $(write_access_status)"
    repacker=$(repacker_status)
    echo "repacker: $repacker"

    if firefox_is_running_for_home "$MOZILLA_HOME"; then
        echo "firefox process: running from MOZILLA_HOME"
        firefox_running=1
    else
        echo "firefox process: not detected for MOZILLA_HOME"
    fi

    app_constants_file=$(find_app_constants "$TEMPDIR" || true)
    if [[ -z $app_constants_file ]]; then
        echo "MOZ_REQUIRE_SIGNING: unknown (AppConstants not found)"
        print_extract_details "$UNZIP_LOG"
        exit 1
    fi

    require_signing=$(app_constants_value "$app_constants_file" || true)
    echo "MOZ_REQUIRE_SIGNING: $require_signing"

    if [[ $require_signing == "false" && -f $ORIGINAL_OMNI_FILE ]]; then
        echo "state: patched with rollback backup"
    elif [[ $require_signing == "false" ]]; then
        echo "state: patched without rollback backup"
    elif [[ $require_signing == "true" && -f $ORIGINAL_OMNI_FILE ]]; then
        echo "state: unpatched archive with leftover rollback backup"
    elif [[ $require_signing == "true" ]]; then
        echo "state: unpatched"
    else
        echo "state: unknown"
        exit 1
    fi

    print_patch_next_step "$require_signing" "$firefox_running" "$repacker"
}

resolve_mozilla_home
require_tools cut grep head mktemp rm sed tr unzip

if [[ $STATUS_MODE -eq 0 ]]; then
    require_tools cp mv
    ZIP_BIN=$(command -v zip || true)
    POWERSHELL_ZIP_BIN=$(command -v powershell.exe || true)
    PYTHON_BIN=""
    if command -v python3 > /dev/null 2>&1; then
        PYTHON_BIN=$(command -v python3)
    elif command -v python > /dev/null 2>&1; then
        PYTHON_BIN=$(command -v python)
    fi

    if [[ -z $ZIP_BIN && -z $POWERSHELL_ZIP_BIN && -z $PYTHON_BIN ]]; then
        echo "Couldn't find a repacker. Install Info-ZIP zip, use Windows PowerShell, or install python3/python for the fallback repacker."
        exit 1
    fi
fi

if [[ ! -d $MOZILLA_HOME ]]; then
    echo "Couldn't find directory $MOZILLA_HOME"
    exit 1
fi

OMNI_FILE="$MOZILLA_HOME/omni.ja"
ORIGINAL_OMNI_FILE="$MOZILLA_HOME/omni-orig.ja"
NEW_OMNI_FILE=""
TEMPDIR=""
VERIFY_TEMPDIR=""
UNZIP_LOG=""
VERIFY_UNZIP_LOG=""

cleanup() {
    if [[ -n ${TEMPDIR:-} ]]; then
        rm -rf "$TEMPDIR"
    fi
    if [[ -n ${VERIFY_TEMPDIR:-} ]]; then
        rm -rf "$VERIFY_TEMPDIR"
    fi
    if [[ -n ${NEW_OMNI_FILE:-} ]]; then
        rm -f "$NEW_OMNI_FILE"
    fi
    if [[ -n ${UNZIP_LOG:-} ]]; then
        rm -f "$UNZIP_LOG"
    fi
    if [[ -n ${VERIFY_UNZIP_LOG:-} ]]; then
        rm -f "$VERIFY_UNZIP_LOG"
    fi
}
trap cleanup EXIT

if [[ ! -f $OMNI_FILE ]]; then
    echo "Couldn't find $OMNI_FILE"
    exit 1
fi

if [[ $STATUS_MODE -eq 0 && -f $ORIGINAL_OMNI_FILE ]]; then
    echo "Patch refused because rollback backup already exists: $ORIGINAL_OMNI_FILE"
    echo "Firefox may already be patched. Run --status to inspect this install."
    echo "To restore the backup before patching again, run unpatch-firefox.sh."
    exit 1
fi

if [[ $STATUS_MODE -eq 0 && $DRY_RUN -eq 0 ]]; then
    assert_firefox_not_running
    ensure_write_access_or_relaunch "Patching Firefox"
fi

TEMPDIR=$(mktemp -d)
if [[ ! -d $TEMPDIR ]]; then
    echo "Couldn't create tempdir"
    exit 1
fi

UNZIP_LOG=$(mktemp)
extract_omni "$OMNI_FILE" "$TEMPDIR" "$UNZIP_LOG"

if [[ $STATUS_MODE -eq 1 ]]; then
    print_status
    exit 0
fi

if [[ $DRY_RUN -eq 1 ]]; then
    NEW_OMNI_FILE="${TEMPDIR}.omni.ja.new.$$"
else
    NEW_OMNI_FILE="$MOZILLA_HOME/omni.ja.new.$$"
    if [[ -e $NEW_OMNI_FILE ]]; then
        echo "Temporary output already exists: $NEW_OMNI_FILE"
        exit 1
    fi
fi

APP_CONSTANTS_FILE=$(find_app_constants "$TEMPDIR" || true)
if [[ -z $APP_CONSTANTS_FILE ]]; then
    echo "Couldn't extract AppConstants from $OMNI_FILE"
    echo "Firefox's archive layout may have changed. No files were changed."
    print_extract_details "$UNZIP_LOG"
    exit 1
fi

patch_require_signing "$APP_CONSTANTS_FILE"

pushd "$TEMPDIR" > /dev/null
repack_omni "$NEW_OMNI_FILE"
popd > /dev/null

verify_new_archive

if [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry run OK"
    echo "next step: run the same command without --dry-run to patch Firefox."
    exit 0
fi

cp -p "$OMNI_FILE" "$ORIGINAL_OMNI_FILE"
if ! mv "$NEW_OMNI_FILE" "$OMNI_FILE"; then
    rm -f "$ORIGINAL_OMNI_FILE"
    echo "Couldn't replace $OMNI_FILE"
    exit 1
fi
NEW_OMNI_FILE=""

echo Done
