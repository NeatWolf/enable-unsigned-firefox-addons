#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
MOZILLA_HOME_ARG=""

usage() {
    cat <<USAGE
Usage: $0 [--dry-run] [--mozilla-home PATH]

Options:
  --dry-run              Build and verify a patched archive without modifying Firefox.
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

for tool in cp grep mktemp mv rm sed tr unzip; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        echo "Couldn't find required tool: $tool"
        exit 1
    fi
done

ZIP_BIN=$(command -v zip || true)
PYTHON_BIN=""
if command -v python3 > /dev/null 2>&1; then
    PYTHON_BIN=$(command -v python3)
elif command -v python > /dev/null 2>&1; then
    PYTHON_BIN=$(command -v python)
fi

if [[ -z $ZIP_BIN && -z $PYTHON_BIN ]]; then
    echo "Couldn't find a repacker. Install Info-ZIP zip, or install python3/python for the fallback repacker."
    exit 1
fi

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
NEW_OMNI_FILE=""
TEMPDIR=""
VERIFY_TEMPDIR=""

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
}
trap cleanup EXIT

if [[ ! -f $OMNI_FILE ]]; then
    echo "Couldn't find $OMNI_FILE"
    exit 1
fi

if [[ -f $ORIGINAL_OMNI_FILE ]]; then
    echo "Already patched?"
    exit 1
fi

TEMPDIR=$(mktemp -d)
if [[ ! -d $TEMPDIR ]]; then
    echo "Couldn't create tempdir"
    exit 1
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

unzip -q -d "$TEMPDIR" "$OMNI_FILE" || true

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

app_constants_is_false() {
    local app_constants_file=$1
    local signline
    local current_const

    if grep -Eq "^[[:space:]]*MOZ_REQUIRE_SIGNING:[[:space:]]*false," "$app_constants_file"; then
        return 0
    fi

    signline=$(grep -n "MOZ_REQUIRE_SIGNING:" "$app_constants_file" | cut -d: -f 1 | head -n 1 || true)
    if [[ -z $signline ]]; then
        return 1
    fi

    current_const=$(sed -n "$((signline + 2))p" "$app_constants_file")
    [[ $current_const == "  false," ]]
}

patch_require_signing() {
    local app_constants_file=$1
    local signline
    local current_const

    if app_constants_is_false "$app_constants_file"; then
        echo "MOZ_REQUIRE_SIGNING is already false"
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
    local python_target=$target

    if [[ -n $ZIP_BIN ]]; then
        zip -0DXqr "$target" .
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
    unzip -q -d "$VERIFY_TEMPDIR" "$NEW_OMNI_FILE" || true

    app_constants_file=$(find_app_constants "$VERIFY_TEMPDIR" || true)
    if [[ -z $app_constants_file ]]; then
        echo "Replacement archive is missing AppConstants"
        exit 1
    fi

    if ! app_constants_is_false "$app_constants_file"; then
        echo "Replacement archive did not set MOZ_REQUIRE_SIGNING to false"
        exit 1
    fi

    rm -rf "$VERIFY_TEMPDIR"
    VERIFY_TEMPDIR=""
}

APP_CONSTANTS_FILE=$(find_app_constants "$TEMPDIR" || true)
if [[ -z $APP_CONSTANTS_FILE ]]; then
    echo "Unzip was unsuccessful"
    exit 1
fi

patch_require_signing "$APP_CONSTANTS_FILE"

pushd "$TEMPDIR" > /dev/null
repack_omni "$NEW_OMNI_FILE"
popd > /dev/null

verify_new_archive

if [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry run OK"
    exit 0
fi

assert_firefox_not_running

cp -p "$OMNI_FILE" "$ORIGINAL_OMNI_FILE"
if ! mv "$NEW_OMNI_FILE" "$OMNI_FILE"; then
    rm -f "$ORIGINAL_OMNI_FILE"
    echo "Couldn't replace $OMNI_FILE"
    exit 1
fi
NEW_OMNI_FILE=""

echo Done
