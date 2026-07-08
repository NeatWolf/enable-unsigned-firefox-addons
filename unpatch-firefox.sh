#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
MOZILLA_HOME_ARG=""

usage() {
    cat <<USAGE
Usage: $0 [--dry-run] [--mozilla-home PATH]

Options:
  --dry-run              Stage the restore without modifying Firefox.
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

resolve_mozilla_home

for tool in cp mv rm tr; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        echo "Couldn't find required tool: $tool"
        exit 1
    fi
done

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

assert_firefox_not_running() {
    if firefox_is_running_for_home "$MOZILLA_HOME"; then
        echo "Firefox appears to be running from $MOZILLA_HOME. Close Firefox before modifying omni.ja."
        echo "Set SKIP_FIREFOX_PROCESS_CHECK=1 only if you have verified it is safe to continue."
        exit 1
    fi
}

if [[ ! -d $MOZILLA_HOME ]]; then
    echo "Couldn't find directory $MOZILLA_HOME"
    exit 1
fi

OMNI_FILE="$MOZILLA_HOME/omni.ja"
ORIGINAL_OMNI_FILE="$MOZILLA_HOME/omni-orig.ja"
RESTORE_FILE="$MOZILLA_HOME/omni.ja.restore.$$"

cleanup() {
    if [[ -n ${RESTORE_FILE:-} ]]; then
        rm -f "$RESTORE_FILE"
    fi
}
trap cleanup EXIT

if [[ ! -f $ORIGINAL_OMNI_FILE ]]; then
    echo "Not already patched"
    exit 1
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

assert_firefox_not_running

mv "$RESTORE_FILE" "$OMNI_FILE"
RESTORE_FILE=""
rm "$ORIGINAL_OMNI_FILE"

echo Done
