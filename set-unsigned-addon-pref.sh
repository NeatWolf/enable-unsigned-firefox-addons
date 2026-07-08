#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
STATUS_MODE=0
PROFILE_ARG=""
PROFILES_INI_ARG=""
ALL_PROFILES=0
LIST_PROFILES=0

PREF_NAME="xpinstall.signatures.required"
PREF_LINE='user_pref("xpinstall.signatures.required", false);'
BACKUP_SUFFIX=".before-enable-unsigned-addons"

usage() {
    cat <<USAGE
Usage: $0 [--dry-run|--status] [--profile PATH | --profiles-ini PATH]

Options:
  --dry-run            Show what would change without writing.
  --status             Show Firefox profiles and whether each allows unsigned add-ons.
  --profile PATH       Change one Firefox profile folder.
  --profiles-ini PATH  Firefox profiles.ini to read.
  --all-profiles       Change every detected profile. Use only when that is intentional.
  --list-profiles      Print detected profile numbers for the Windows menu picker.
  -h, --help           Show this help.

A Firefox profile is the user-data folder where Firefox stores settings and add-ons.
Without --profile or --all-profiles, the default Firefox profile is used.
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
        --profile)
            if [[ $# -lt 2 || -z $2 ]]; then
                echo "--profile requires a path"
                exit 1
            fi
            PROFILE_ARG=$2
            shift 2
            ;;
        --profile=*)
            PROFILE_ARG=${1#*=}
            if [[ -z $PROFILE_ARG ]]; then
                echo "--profile requires a path"
                exit 1
            fi
            shift
            ;;
        --profiles-ini)
            if [[ $# -lt 2 || -z $2 ]]; then
                echo "--profiles-ini requires a path"
                exit 1
            fi
            PROFILES_INI_ARG=$2
            shift 2
            ;;
        --profiles-ini=*)
            PROFILES_INI_ARG=${1#*=}
            if [[ -z $PROFILES_INI_ARG ]]; then
                echo "--profiles-ini requires a path"
                exit 1
            fi
            shift
            ;;
        --all-profiles)
            ALL_PROFILES=1
            shift
            ;;
        --list-profiles)
            LIST_PROFILES=1
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

if [[ -n $PROFILE_ARG && $ALL_PROFILES -eq 1 ]]; then
    echo "Use either --profile or --all-profiles, not both"
    exit 1
fi

if [[ $DRY_RUN -eq 1 && $STATUS_MODE -eq 1 ]]; then
    echo "Use either --dry-run or --status, not both"
    exit 1
fi

if [[ $LIST_PROFILES -eq 1 ]] && { [[ $DRY_RUN -eq 1 ]] || [[ $STATUS_MODE -eq 1 ]] || [[ -n $PROFILE_ARG ]] || [[ $ALL_PROFILES -eq 1 ]]; }; then
    echo "Use --list-profiles by itself, optionally with --profiles-ini PATH."
    exit 1
fi

require_tools() {
    local tool
    for tool in "$@"; do
        if ! command -v "$tool" > /dev/null 2>&1; then
            echo "Couldn't find required tool: $tool"
            exit 1
        fi
    done
}

path_from_windows_env() {
    local value=$1

    if [[ -z $value ]]; then
        return
    fi

    if command -v cygpath > /dev/null 2>&1; then
        cygpath -u "$value"
    else
        printf '%s\n' "$value"
    fi
}

display_path() {
    local value=$1

    if command -v cygpath > /dev/null 2>&1; then
        cygpath -w "$value"
    else
        printf '%s\n' "$value"
    fi
}

normalize_input_path() {
    local value=$1

    if [[ -z $value ]]; then
        return
    fi

    if command -v cygpath > /dev/null 2>&1 && [[ $value =~ ^[A-Za-z]:[\\/] || $value =~ ^\\\\ ]]; then
        cygpath -u "$value"
    else
        printf '%s\n' "$value"
    fi
}

candidate_profiles_ini_files() {
    local appdata_home

    appdata_home=$(path_from_windows_env "${APPDATA:-}")
    if [[ -n $appdata_home ]]; then
        printf '%s\n' "$appdata_home/Mozilla/Firefox/profiles.ini"
    fi

    printf '%s\n' "$HOME/.mozilla/firefox/profiles.ini"
    printf '%s\n' "$HOME/Library/Application Support/Firefox/profiles.ini"
}

firefox_is_running() {
    local ps_output

    if [[ ${SKIP_FIREFOX_PROCESS_CHECK:-} == "1" ]]; then
        return 1
    fi

    if command -v powershell.exe > /dev/null 2>&1; then
        ps_output=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
$match = Get-Process -Name firefox -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty Id
if ($match) { Write-Output $match }
' 2> /dev/null || true)
        ps_output=${ps_output//$'\r'/}
        [[ -n $ps_output ]]
        return
    fi

    if command -v pgrep > /dev/null 2>&1 && pgrep -x firefox > /dev/null 2>&1; then
        return 0
    fi

    return 1
}

assert_firefox_not_running() {
    if firefox_is_running; then
        echo "Firefox appears to be running. Close Firefox before changing the add-on setting in a profile."
        echo "Set SKIP_FIREFOX_PROCESS_CHECK=1 only if you have verified it is safe to continue."
        exit 1
    fi
}

warn_if_firefox_running_for_dry_run() {
    if firefox_is_running; then
        echo "warning: Firefox appears to be running. Close Firefox before changing the add-on setting for real."
    fi
}

add_profile_dir() {
    local profile_dir=$1

    if [[ -z $profile_dir || ! -d $profile_dir ]]; then
        return
    fi

    if [[ $SEEN_PROFILE_DIRS != *"|$profile_dir|"* ]]; then
        PROFILE_DIRS+=("$profile_dir")
        SEEN_PROFILE_DIRS="${SEEN_PROFILE_DIRS}${profile_dir}|"
    fi
}

profile_path_from_ini() {
    local ini_root=$1
    local profile_path=$2
    local is_relative=$3

    if [[ -z $profile_path ]]; then
        return
    fi

    case "$is_relative" in
        0)
            normalize_input_path "$profile_path"
            ;;
        *)
            printf '%s\n' "$ini_root/$profile_path"
            ;;
    esac
}

emit_profiles_ini_entry() {
    local ini_root=$1
    local profile_path=$2
    local is_relative=$3
    local is_default=$4
    local resolved_profile_path

    if [[ -z $profile_path ]]; then
        return
    fi

    resolved_profile_path=$(profile_path_from_ini "$ini_root" "$profile_path" "$is_relative")
    add_profile_dir "$resolved_profile_path"

    if [[ $is_default == "1" && -z ${DEFAULT_PROFILE_DIR:-} && -d $resolved_profile_path ]]; then
        DEFAULT_PROFILE_DIR=$resolved_profile_path
    fi
}

read_profiles_ini() {
    local ini_file=$1
    local ini_root
    local section=""
    local line
    local profile_path=""
    local is_relative="1"
    local is_default="0"
    local install_default_path=""
    local install_default_profile

    ini_root=${ini_file%/*}

    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        case "$line" in
            \[*\])
                if [[ $section == Profile* ]]; then
                    emit_profiles_ini_entry "$ini_root" "$profile_path" "$is_relative" "$is_default"
                fi
                section=${line#[}
                section=${section%]}
                profile_path=""
                is_relative="1"
                is_default="0"
                ;;
            Path=*)
                if [[ $section == Profile* ]]; then
                    profile_path=${line#Path=}
                fi
                ;;
            IsRelative=*)
                if [[ $section == Profile* ]]; then
                    is_relative=${line#IsRelative=}
                fi
                ;;
            Default=1)
                if [[ $section == Profile* ]]; then
                    is_default="1"
                fi
                ;;
            Default=*)
                if [[ $section == Install* && -z $install_default_path ]]; then
                    install_default_path=${line#Default=}
                fi
                ;;
        esac
    done < "$ini_file"

    if [[ $section == Profile* ]]; then
        emit_profiles_ini_entry "$ini_root" "$profile_path" "$is_relative" "$is_default"
    fi

    if [[ -z ${DEFAULT_PROFILE_DIR:-} && -n $install_default_path ]]; then
        install_default_profile=$(profile_path_from_ini "$ini_root" "$install_default_path" "1")
        if [[ -d $install_default_profile ]]; then
            DEFAULT_PROFILE_DIR=$install_default_profile
        fi
    fi
}

resolve_profile_dirs() {
    local ini_file
    local normalized_profile_arg
    local normalized_profiles_ini_arg

    PROFILE_DIRS=()
    TARGET_PROFILE_DIRS=()
    SEEN_PROFILE_DIRS="|"
    DEFAULT_PROFILE_DIR=""

    if [[ -n $PROFILE_ARG ]]; then
        normalized_profile_arg=$(normalize_input_path "$PROFILE_ARG")
        if [[ ! -d $normalized_profile_arg ]]; then
            echo "Couldn't find Firefox profile directory: $PROFILE_ARG"
            echo "Pass a Firefox profile directory, not the Firefox install directory."
            exit 1
        fi
        add_profile_dir "$normalized_profile_arg"
        TARGET_PROFILE_DIRS=("$normalized_profile_arg")
        return
    fi

    if [[ -n $PROFILES_INI_ARG ]]; then
        normalized_profiles_ini_arg=$(normalize_input_path "$PROFILES_INI_ARG")
        if [[ ! -f $normalized_profiles_ini_arg ]]; then
            echo "Couldn't find Firefox profiles.ini: $PROFILES_INI_ARG"
            echo "Pass a Firefox profiles.ini file or omit --profiles-ini to auto-detect common locations."
            exit 1
        fi
        read_profiles_ini "$normalized_profiles_ini_arg"
    else
        while IFS= read -r ini_file; do
            if [[ -f $ini_file ]]; then
                read_profiles_ini "$ini_file"
            fi
        done < <(candidate_profiles_ini_files)
    fi

    if [[ $ALL_PROFILES -eq 1 ]]; then
        TARGET_PROFILE_DIRS=("${PROFILE_DIRS[@]}")
    elif [[ -n $DEFAULT_PROFILE_DIR ]]; then
        TARGET_PROFILE_DIRS=("$DEFAULT_PROFILE_DIR")
    elif [[ ${#PROFILE_DIRS[@]} -eq 1 ]]; then
        TARGET_PROFILE_DIRS=("${PROFILE_DIRS[0]}")
    fi
}

preference_state() {
    local prefs_file=$1
    local has_true=0
    local has_false=0

    if [[ ! -f $prefs_file ]]; then
        printf 'absent\n'
        return
    fi

    if grep -Eq '^[[:space:]]*user_pref\("xpinstall\.signatures\.required",[[:space:]]*true\);' "$prefs_file"; then
        has_true=1
    fi
    if grep -Eq '^[[:space:]]*user_pref\("xpinstall\.signatures\.required",[[:space:]]*false\);' "$prefs_file"; then
        has_false=1
    fi

    if [[ $has_true -eq 1 && $has_false -eq 1 ]]; then
        printf 'mixed\n'
    elif [[ $has_true -eq 1 ]]; then
        printf 'true\n'
    elif [[ $has_false -eq 1 ]]; then
        printf 'false\n'
    else
        printf 'absent\n'
    fi
}

profile_needs_update() {
    local profile_dir=$1
    local prefs_file="$profile_dir/prefs.js"
    [[ $(preference_state "$prefs_file") != "false" ]]
}

update_profile_pref() {
    local profile_dir=$1
    local prefs_file="$profile_dir/prefs.js"
    local backup_file="$prefs_file$BACKUP_SUFFIX"
    local temp_file

    if ! profile_needs_update "$profile_dir"; then
        echo "Already set $prefs_file"
        return
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        if [[ -f $prefs_file ]]; then
            echo "Would set $PREF_NAME=false in $prefs_file"
        else
            echo "Would create $prefs_file with $PREF_NAME=false"
        fi
        return
    fi

    if [[ -f $prefs_file && ! -f $backup_file ]]; then
        cp "$prefs_file" "$backup_file"
        echo "Backup: $backup_file"
    fi

    temp_file=$(mktemp)
    if [[ -f $prefs_file ]]; then
        grep -Ev '^[[:space:]]*user_pref\("xpinstall\.signatures\.required",[[:space:]]*(true|false)\);[[:space:]]*$' "$prefs_file" > "$temp_file" || true
    else
        : > "$temp_file"
    fi
    printf '%s\n' "$PREF_LINE" >> "$temp_file"
    mv "$temp_file" "$prefs_file"
    echo "Updated $prefs_file"
}

print_status() {
    local profile_dir
    local prefs_file
    local state
    local needs_update=0
    local firefox_running=0

    echo "profiles: ${#PROFILE_DIRS[@]}"
    if [[ -n ${DEFAULT_PROFILE_DIR:-} ]]; then
        echo "default profile: $DEFAULT_PROFILE_DIR"
    elif [[ ${#PROFILE_DIRS[@]} -gt 1 ]]; then
        echo "default profile: not detected"
    fi
    for profile_dir in "${PROFILE_DIRS[@]}"; do
        prefs_file="$profile_dir/prefs.js"
        state=$(preference_state "$prefs_file")
        echo "profile: $profile_dir"
        if [[ -f $prefs_file ]]; then
            echo "prefs.js: present $prefs_file"
        else
            echo "prefs.js: absent $prefs_file"
        fi
        echo "$PREF_NAME: $state"
        if [[ $state != "false" ]]; then
            needs_update=$((needs_update + 1))
        fi
    done

    echo "profiles needing add-on setting change: $needs_update"
    if firefox_is_running; then
        echo "firefox process: running"
        firefox_running=1
    else
        echo "firefox process: not detected"
    fi

    if [[ ${#TARGET_PROFILE_DIRS[@]} -gt 0 ]]; then
        echo "target profiles: ${#TARGET_PROFILE_DIRS[@]}"
        for profile_dir in "${TARGET_PROFILE_DIRS[@]}"; do
            echo "target profile: $profile_dir"
        done
    fi

    if [[ $needs_update -gt 0 && ${#TARGET_PROFILE_DIRS[@]} -eq 0 ]]; then
        echo "next step: choose one profile with --profile PATH, or use --all-profiles intentionally."
    elif [[ $needs_update -gt 0 && $firefox_running -eq 1 ]]; then
        echo "next step: close Firefox before changing the add-on setting."
    elif [[ $needs_update -gt 0 ]]; then
        echo "next step: run this script with --dry-run before changing the add-on setting."
    else
        echo "next step: add-on setting is already ready."
    fi
}

print_profile_list() {
    local profile_dir
    local profile_number=1
    local marker

    for profile_dir in "${PROFILE_DIRS[@]}"; do
        marker=""
        if [[ -n ${DEFAULT_PROFILE_DIR:-} && $profile_dir == "$DEFAULT_PROFILE_DIR" ]]; then
            marker="default"
        fi
        printf '%s|%s|%s\n' "$profile_number" "$(display_path "$profile_dir")" "$marker"
        profile_number=$((profile_number + 1))
    done
}

require_tools grep mktemp mv
if [[ $STATUS_MODE -eq 0 && $DRY_RUN -eq 0 ]]; then
    require_tools cp
fi

resolve_profile_dirs

if [[ ${#PROFILE_DIRS[@]} -eq 0 ]]; then
    echo "No Firefox profiles found."
    if [[ $STATUS_MODE -eq 1 ]]; then
        echo "next step: pass --profile or --profiles-ini if Firefox uses an unusual profile location."
    fi
    exit 0
fi

if [[ $LIST_PROFILES -eq 1 ]]; then
    print_profile_list
    exit 0
fi

if [[ $STATUS_MODE -eq 1 ]]; then
    print_status
    exit 0
fi

if [[ ${#TARGET_PROFILE_DIRS[@]} -eq 0 ]]; then
    echo "Multiple Firefox profiles were found, but no default profile was detected."
    echo "A Firefox profile is the user-data folder for one Firefox setup."
    echo "Run --status to see profile paths, then pass --profile PATH for the profile you use."
    echo "Use --all-profiles only if you intentionally want every detected profile changed."
    exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
    warn_if_firefox_running_for_dry_run
else
    assert_firefox_not_running
fi

UPDATED=0
for profile_dir in "${TARGET_PROFILE_DIRS[@]}"; do
    if profile_needs_update "$profile_dir"; then
        UPDATED=$((UPDATED + 1))
    fi
    update_profile_pref "$profile_dir"
done

if [[ $UPDATED -eq 0 ]]; then
    echo "No add-on setting changes needed."
elif [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry run OK"
    echo "next step: run the same command without --dry-run to change the listed profile setting."
else
    echo Done
    echo "next step: clear Firefox startupCache before starting Firefox."
fi
