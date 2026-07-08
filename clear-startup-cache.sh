#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
PROFILE_ARG=""
PROFILES_INI_ARG=""

usage() {
    cat <<USAGE
Usage: $0 [--dry-run] [--profile PATH | --profiles-ini PATH]

Options:
  --dry-run            Print startupCache directories that would be removed.
  --profile PATH       Firefox profile directory containing startupCache.
  --profiles-ini PATH  Firefox profiles.ini to read.
  -h, --help           Show this help.

Without --profile or --profiles-ini, common Firefox profiles.ini locations are used.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
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

if [[ -n $PROFILE_ARG && -n $PROFILES_INI_ARG ]]; then
    echo "Use either --profile or --profiles-ini, not both"
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

candidate_profiles_ini_files() {
    local appdata_home

    appdata_home=$(path_from_windows_env "${APPDATA:-}")
    if [[ -n $appdata_home ]]; then
        printf '%s\n' "$appdata_home/Mozilla/Firefox/profiles.ini"
    fi

    printf '%s\n' "$HOME/.mozilla/firefox/profiles.ini"
    printf '%s\n' "$HOME/Library/Application Support/Firefox/profiles.ini"
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

emit_profiles_ini_entry() {
    local ini_root=$1
    local profile_path=$2
    local is_relative=$3

    if [[ -z $profile_path ]]; then
        return
    fi

    case "$is_relative" in
        0)
            add_profile_dir "$profile_path"
            ;;
        *)
            add_profile_dir "$ini_root/$profile_path"
            ;;
    esac
}

read_profiles_ini() {
    local ini_file=$1
    local ini_root
    local line
    local profile_path=""
    local is_relative="1"

    ini_root=${ini_file%/*}

    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        case "$line" in
            \[*\])
                emit_profiles_ini_entry "$ini_root" "$profile_path" "$is_relative"
                profile_path=""
                is_relative="1"
                ;;
            Path=*)
                profile_path=${line#Path=}
                ;;
            IsRelative=*)
                is_relative=${line#IsRelative=}
                ;;
        esac
    done < "$ini_file"

    emit_profiles_ini_entry "$ini_root" "$profile_path" "$is_relative"
}

# Use Firefox's own profile registry as the source of truth. This avoids
# scanning arbitrary directories for folders named startupCache.
resolve_profile_dirs() {
    local ini_file

    PROFILE_DIRS=()
    SEEN_PROFILE_DIRS="|"

    if [[ -n $PROFILE_ARG ]]; then
        if [[ ! -d $PROFILE_ARG ]]; then
            echo "Couldn't find profile directory $PROFILE_ARG"
            exit 1
        fi
        add_profile_dir "$PROFILE_ARG"
        return
    fi

    if [[ -n $PROFILES_INI_ARG ]]; then
        if [[ ! -f $PROFILES_INI_ARG ]]; then
            echo "Couldn't find profiles.ini $PROFILES_INI_ARG"
            exit 1
        fi
        read_profiles_ini "$PROFILES_INI_ARG"
        return
    fi

    while IFS= read -r ini_file; do
        if [[ -f $ini_file ]]; then
            read_profiles_ini "$ini_file"
        fi
    done < <(candidate_profiles_ini_files)
}

startup_cache_dirs() {
    local profile_dir
    local cache_dir

    # Only the direct startupCache child of a known Firefox profile is eligible.
    for profile_dir in "${PROFILE_DIRS[@]}"; do
        cache_dir="$profile_dir/startupCache"
        if [[ -d $cache_dir ]]; then
            printf '%s\n' "$cache_dir"
        fi
    done
}

remove_startup_cache() {
    local cache_dir=$1

    if [[ ${cache_dir##*/} != "startupCache" || ! -d $cache_dir ]]; then
        echo "Refusing unexpected cache path: $cache_dir"
        exit 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "Would remove $cache_dir"
        return
    fi

    rm -rf "$cache_dir"
    echo "Removed $cache_dir"
}

require_tools rm
resolve_profile_dirs

if [[ ${#PROFILE_DIRS[@]} -eq 0 ]]; then
    echo "No Firefox profiles found."
    exit 0
fi

CACHE_DIRS=()
while IFS= read -r cache_dir; do
    CACHE_DIRS+=("$cache_dir")
done < <(startup_cache_dirs)

if [[ ${#CACHE_DIRS[@]} -eq 0 ]]; then
    echo "No startupCache directories found."
    exit 0
fi

for cache_dir in "${CACHE_DIRS[@]}"; do
    remove_startup_cache "$cache_dir"
done

if [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry run OK"
else
    echo Done
fi
