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
  --dry-run              Stage the restore without modifying Firefox.
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

resolve_mozilla_home() {
    local candidate
    local seen="|"
    local matches=()

    if [[ -n $MOZILLA_HOME_ARG ]]; then
        MOZILLA_HOME=$MOZILLA_HOME_ARG
        return
    fi

    if [[ -n ${MOZILLA_HOME:-} ]]; then
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

    # Firefox omni.ja often emits harmless unzip warnings; status validates
    # AppConstants after extraction and prints this log only on real failures.
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

print_status() {
    local app_constants_file
    local require_signing

    echo "MOZILLA_HOME=$MOZILLA_HOME"
    echo "omni.ja: present"
    if [[ -f $ORIGINAL_OMNI_FILE ]]; then
        echo "omni-orig.ja: present"
    else
        echo "omni-orig.ja: absent"
    fi

    if firefox_is_running_for_home "$MOZILLA_HOME"; then
        echo "firefox process: running from MOZILLA_HOME"
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
}

resolve_mozilla_home
require_tools rm tr

if [[ $STATUS_MODE -eq 1 ]]; then
    require_tools cut grep head mktemp sed unzip
else
    require_tools cp mv
    if [[ $DRY_RUN -eq 1 ]]; then
        require_tools mktemp
    fi
fi

if [[ ! -d $MOZILLA_HOME ]]; then
    echo "Couldn't find directory $MOZILLA_HOME"
    exit 1
fi

OMNI_FILE="$MOZILLA_HOME/omni.ja"
ORIGINAL_OMNI_FILE="$MOZILLA_HOME/omni-orig.ja"
RESTORE_FILE=""
TEMPDIR=""
UNZIP_LOG=""

cleanup() {
    if [[ -n ${TEMPDIR:-} ]]; then
        rm -rf "$TEMPDIR"
    fi
    if [[ -n ${RESTORE_FILE:-} ]]; then
        rm -f "$RESTORE_FILE"
    fi
    if [[ -n ${UNZIP_LOG:-} ]]; then
        rm -f "$UNZIP_LOG"
    fi
}
trap cleanup EXIT

if [[ ! -f $OMNI_FILE ]]; then
    echo "Couldn't find $OMNI_FILE"
    exit 1
fi

if [[ $STATUS_MODE -eq 1 ]]; then
    TEMPDIR=$(mktemp -d)
    if [[ ! -d $TEMPDIR ]]; then
        echo "Couldn't create tempdir"
        exit 1
    fi

    UNZIP_LOG=$(mktemp)
    extract_omni "$OMNI_FILE" "$TEMPDIR" "$UNZIP_LOG"
    print_status
    exit 0
fi

if [[ ! -f $ORIGINAL_OMNI_FILE ]]; then
    echo "Not already patched"
    exit 1
fi

if [[ $DRY_RUN -eq 0 ]]; then
    assert_firefox_not_running
    ensure_write_access_or_relaunch "Restoring Firefox"
fi

if [[ $DRY_RUN -eq 1 ]]; then
    TEMPDIR=$(mktemp -d)
    if [[ ! -d $TEMPDIR ]]; then
        echo "Couldn't create tempdir"
        exit 1
    fi
    RESTORE_FILE="$TEMPDIR/omni.ja.restore"
else
    RESTORE_FILE="$MOZILLA_HOME/omni.ja.restore.$$"
fi

if [[ -e $RESTORE_FILE ]]; then
    echo "Temporary restore file already exists: $RESTORE_FILE"
    exit 1
fi

cp -p "$ORIGINAL_OMNI_FILE" "$RESTORE_FILE"

if [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry run OK"
    exit 0
fi

mv "$RESTORE_FILE" "$OMNI_FILE"
RESTORE_FILE=""
rm "$ORIGINAL_OMNI_FILE"

echo Done
