#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

TEMPDIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEMPDIR"
}
trap cleanup EXIT

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

make_omni() {
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

write_app_constants() {
    local format=$1
    local target=$2

    case "$format" in
        modern)
            cat > "$target" <<'APP_CONSTANTS'
export var AppConstants = Object.freeze({
  MOZ_REQUIRE_SIGNING: true,
});
APP_CONSTANTS
            ;;
        modern-false)
            cat > "$target" <<'APP_CONSTANTS'
export var AppConstants = Object.freeze({
  MOZ_REQUIRE_SIGNING: false,
});
APP_CONSTANTS
            ;;
        legacy)
            cat > "$target" <<'APP_CONSTANTS'
export var AppConstants = {
  MOZ_REQUIRE_SIGNING:
#ifdef MOZ_REQUIRE_SIGNING
  true,
#endif
};
APP_CONSTANTS
            ;;
        *)
            echo "Unknown fixture format: $format"
            exit 1
            ;;
    esac
}

create_fixture() {
    local name=$1
    local format=$2
    local app_constants_relpath=$3
    local fixture_home="$TEMPDIR/$name/firefox"
    local omni_source="$TEMPDIR/$name/omni-source"

    mkdir -p "$fixture_home"
    cat > "$fixture_home/application.ini" <<'APPLICATION_INI'
[App]
Name=Firefox
Version=99.0
BuildID=20260101000000
APPLICATION_INI

    if [[ $format == "missing" ]]; then
        mkdir -p "$omni_source/modules"
        echo "export const NothingUseful = true;" > "$omni_source/modules/Other.sys.mjs"
    else
        mkdir -p "$(dirname "$omni_source/$app_constants_relpath")"
        write_app_constants "$format" "$omni_source/$app_constants_relpath"
    fi

    pushd "$omni_source" > /dev/null
    make_omni "$fixture_home/omni.ja"
    popd > /dev/null
}

assert_app_constants_value() {
    local name=$1
    local archive=$2
    local app_constants_relpath=$3
    local expected=$4
    local extract_dir="$TEMPDIR/$name/extract-$expected-$$"
    local app_constants_file="$extract_dir/$app_constants_relpath"

    mkdir -p "$extract_dir"
    unzip -q -d "$extract_dir" "$archive"

    if [[ ! -f $app_constants_file ]]; then
        echo "$name: missing $app_constants_relpath in archive"
        exit 1
    fi

    if [[ $expected == "true" ]]; then
        if ! grep -Eq "MOZ_REQUIRE_SIGNING:[[:space:]]*true,|^[[:space:]]*true," "$app_constants_file"; then
            echo "$name: expected MOZ_REQUIRE_SIGNING true"
            exit 1
        fi
    else
        if grep -Eq "MOZ_REQUIRE_SIGNING:[[:space:]]*true,|^[[:space:]]*true," "$app_constants_file"; then
            echo "$name: left MOZ_REQUIRE_SIGNING true"
            exit 1
        fi
        if ! grep -Eq "MOZ_REQUIRE_SIGNING:[[:space:]]*false,|^[[:space:]]*false," "$app_constants_file"; then
            echo "$name: expected MOZ_REQUIRE_SIGNING false"
            exit 1
        fi
    fi
}

assert_no_patch_side_effects() {
    local name=$1
    local fixture_home=$2

    if [[ -f "$fixture_home/omni-orig.ja" ]]; then
        echo "$name: unexpected omni-orig.ja"
        exit 1
    fi

    if compgen -G "$fixture_home/omni.ja.new.*" > /dev/null; then
        echo "$name: left temporary replacement archive"
        exit 1
    fi

    if compgen -G "$TEMPDIR/*.omni.ja.new.*" > /dev/null; then
        echo "$name: left dry-run replacement archive"
        exit 1
    fi
}

assert_output_contains() {
    local name=$1
    local output=$2
    local expected=$3

    case "$output" in
        *"$expected"*)
            ;;
        *)
            echo "$name: expected output to contain: $expected"
            printf '%s\n' "$output"
            exit 1
            ;;
    esac
}

assert_command_fails_with() {
    local name=$1
    local expected=$2
    shift 2
    local output

    if output=$("$@" 2>&1); then
        echo "$name: command unexpectedly succeeded"
        printf '%s\n' "$output"
        exit 1
    fi

    assert_output_contains "$name" "$output" "$expected"
}

run_roundtrip_fixture() {
    local name=$1
    local format=$2
    local app_constants_relpath=$3
    local fixture_home="$TEMPDIR/$name/firefox"
    local patch_output
    local unpatch_output

    create_fixture "$name" "$format" "$app_constants_relpath"

    patch_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh")
    assert_output_contains "$name-patch-output" "$patch_output" "Done"
    assert_output_contains "$name-patch-output" "$patch_output" "next step: clear Firefox startupCache before starting Firefox."
    if [[ ! -f "$fixture_home/omni-orig.ja" ]]; then
        echo "$name: patch did not create omni-orig.ja"
        exit 1
    fi
    assert_app_constants_value "$name-patched" "$fixture_home/omni.ja" "$app_constants_relpath" "false"

    assert_command_fails_with "$name-already-backed-up" "Patch refused because rollback backup already exists" \
        env SKIP_FIREFOX_PROCESS_CHECK=1 MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh"

    MOZILLA_HOME="$fixture_home" "$REPO_ROOT/unpatch-firefox.sh" --dry-run > /dev/null
    if [[ ! -f "$fixture_home/omni-orig.ja" ]]; then
        echo "$name: unpatch dry-run removed omni-orig.ja"
        exit 1
    fi
    assert_app_constants_value "$name-unpatch-dry-run" "$fixture_home/omni.ja" "$app_constants_relpath" "false"

    unpatch_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 MOZILLA_HOME="$fixture_home" "$REPO_ROOT/unpatch-firefox.sh")
    assert_output_contains "$name-unpatch-output" "$unpatch_output" "Done"
    assert_output_contains "$name-unpatch-output" "$unpatch_output" "Removed rollback backup: $fixture_home/omni-orig.ja"
    assert_output_contains "$name-unpatch-output" "$unpatch_output" "next step: update Firefox, then patch again if unsigned addons are still needed."
    if [[ -f "$fixture_home/omni-orig.ja" ]]; then
        echo "$name: unpatch did not remove omni-orig.ja"
        exit 1
    fi
    assert_app_constants_value "$name-restored" "$fixture_home/omni.ja" "$app_constants_relpath" "true"

    assert_command_fails_with "$name-no-backup" "No rollback backup found" \
        env SKIP_FIREFOX_PROCESS_CHECK=1 MOZILLA_HOME="$fixture_home" "$REPO_ROOT/unpatch-firefox.sh"
}

run_status_fixture() {
    local name="status-mode"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local status_output

    create_fixture "$name" "modern" "$app_constants_relpath"

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/patch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-patch-unpatched" "$status_output" "application: Firefox 99.0"
    assert_output_contains "$name-patch-unpatched" "$status_output" "build id: 20260101000000"
    assert_output_contains "$name-patch-unpatched" "$status_output" "MOZ_REQUIRE_SIGNING: true"
    assert_output_contains "$name-patch-unpatched" "$status_output" "omni-orig.ja: absent"
    assert_output_contains "$name-patch-unpatched" "$status_output" "write access: available"
    assert_output_contains "$name-patch-unpatched" "$status_output" "repacker:"
    assert_output_contains "$name-patch-unpatched" "$status_output" "state: unpatched"
    assert_output_contains "$name-patch-unpatched" "$status_output" "next step: run this script with --dry-run before patching."

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/unpatch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-unpatch-unpatched" "$status_output" "application: Firefox 99.0"
    assert_output_contains "$name-unpatch-unpatched" "$status_output" "build id: 20260101000000"
    assert_output_contains "$name-unpatch-unpatched" "$status_output" "MOZ_REQUIRE_SIGNING: true"
    assert_output_contains "$name-unpatch-unpatched" "$status_output" "write access: available"
    assert_output_contains "$name-unpatch-unpatched" "$status_output" "state: unpatched"
    assert_output_contains "$name-unpatch-unpatched" "$status_output" "next step: no restore needed."

    SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/patch-firefox.sh" --mozilla-home "$fixture_home" > /dev/null

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/patch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-patch-patched" "$status_output" "MOZ_REQUIRE_SIGNING: false"
    assert_output_contains "$name-patch-patched" "$status_output" "omni-orig.ja: present"
    assert_output_contains "$name-patch-patched" "$status_output" "state: patched with rollback backup"
    assert_output_contains "$name-patch-patched" "$status_output" "next step: no patch needed; use unpatch-firefox before updating Firefox."

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/unpatch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-unpatch-patched" "$status_output" "MOZ_REQUIRE_SIGNING: false"
    assert_output_contains "$name-unpatch-patched" "$status_output" "state: patched with rollback backup"
    assert_output_contains "$name-unpatch-patched" "$status_output" "next step: run this script with --dry-run before restoring."

    SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/unpatch-firefox.sh" --mozilla-home "$fixture_home" > /dev/null

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/patch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-patch-restored" "$status_output" "MOZ_REQUIRE_SIGNING: true"
    assert_output_contains "$name-patch-restored" "$status_output" "omni-orig.ja: absent"
    assert_output_contains "$name-patch-restored" "$status_output" "state: unpatched"
    assert_output_contains "$name-patch-restored" "$status_output" "next step: run this script with --dry-run before patching."
}

run_patch_dry_run_fixture() {
    local name="modern-dry-run"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local dry_run_output

    create_fixture "$name" "modern" "$app_constants_relpath"

    dry_run_output=$(MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" --dry-run)
    assert_output_contains "$name" "$dry_run_output" "Dry run OK"
    assert_output_contains "$name" "$dry_run_output" "next step: run the same command without --dry-run to patch Firefox."
    assert_no_patch_side_effects "$name" "$fixture_home"
    assert_app_constants_value "$name" "$fixture_home/omni.ja" "$app_constants_relpath" "true"
}

run_prefixed_archive_fixture() {
    local name="prefixed-omni-warning"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local clean_archive="$TEMPDIR/$name/clean.omni.ja"
    local dry_run_output

    create_fixture "$name" "modern" "$app_constants_relpath"
    mv "$fixture_home/omni.ja" "$clean_archive"
    printf 'firefox omni prefix\n' > "$fixture_home/omni.ja"
    cat "$clean_archive" >> "$fixture_home/omni.ja"

    dry_run_output=$(MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" --dry-run)
    assert_output_contains "$name" "$dry_run_output" "Dry run OK"
    assert_output_contains "$name" "$dry_run_output" "next step: run the same command without --dry-run to patch Firefox."
    assert_no_patch_side_effects "$name" "$fixture_home"
}

run_prefixed_archive_exit_2_fixture() {
    local name="prefixed-omni-exit-2"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local fake_bin="$TEMPDIR/$name/fake-bin"
    local real_unzip
    local patch_status_output
    local unpatch_status_output

    create_fixture "$name" "modern" "$app_constants_relpath"
    real_unzip=$(command -v unzip)
    mkdir -p "$fake_bin"
    cat > "$fake_bin/unzip" <<'UNZIP_SHIM'
#!/usr/bin/env bash
set +e
"$REAL_UNZIP" "$@"
real_status=$?
archive="${!#}"

if [[ $(basename "$archive") == "omni.ja" ]]; then
    cat >&2 <<EOF
warning [$archive]:  44369976 extra bytes at beginning or within zipfile
  (attempting to process anyway)
error [$archive]:  reported length of central directory is
  -44369976 bytes too long (Atari STZip zipfile?  J.H.Holm ZIPSPLIT 1.1
  zipfile?).  Compensating...
EOF
    exit 2
fi

exit "$real_status"
UNZIP_SHIM
    chmod +x "$fake_bin/unzip"

    patch_status_output=$(PATH="$fake_bin:$PATH" REAL_UNZIP="$real_unzip" MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" --status)
    assert_output_contains "$name-patch-status" "$patch_status_output" "MOZ_REQUIRE_SIGNING: true"
    assert_output_contains "$name-patch-status" "$patch_status_output" "next step: run this script with --dry-run before patching."

    unpatch_status_output=$(PATH="$fake_bin:$PATH" REAL_UNZIP="$real_unzip" "$REPO_ROOT/unpatch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-unpatch-status" "$unpatch_status_output" "MOZ_REQUIRE_SIGNING: true"
    assert_output_contains "$name-unpatch-status" "$unpatch_status_output" "next step: no restore needed."
}

run_corrupt_archive_fixture() {
    local name="corrupt-omni-crc"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local omni_source="$TEMPDIR/$name/omni-source"
    local payload_offset
    local patch_output

    mkdir -p "$fixture_home" "$omni_source/modules"
    cat > "$fixture_home/application.ini" <<'APPLICATION_INI'
[App]
Name=Firefox
Version=99.0
BuildID=20260101000000
APPLICATION_INI
    write_app_constants "modern" "$omni_source/$app_constants_relpath"
    printf 'CORRUPTME_PAYLOAD\n' > "$omni_source/modules/Damaged.txt"

    pushd "$omni_source" > /dev/null
    make_omni "$fixture_home/omni.ja"
    popd > /dev/null

    payload_offset=$(grep -abo "CORRUPTME_PAYLOAD" "$fixture_home/omni.ja" | head -n 1 | cut -d: -f 1 || true)
    if [[ -z $payload_offset ]]; then
        echo "$name: couldn't find stored payload to damage"
        exit 1
    fi
    printf X | dd of="$fixture_home/omni.ja" bs=1 seek="$payload_offset" count=1 conv=notrunc > /dev/null 2>&1

    if patch_output=$(MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" --dry-run 2>&1); then
        echo "$name: patch dry-run unexpectedly succeeded for corrupt archive"
        printf '%s\n' "$patch_output"
        exit 1
    fi
    assert_output_contains "$name" "$patch_output" "Couldn't extract $fixture_home/omni.ja cleanly."
    if [[ $patch_output == *"Dry run OK"* ]]; then
        echo "$name: corrupt archive still reported Dry run OK"
        exit 1
    fi
    assert_no_patch_side_effects "$name" "$fixture_home"
}

run_unpatch_dry_run_readonly_home_fixture() {
    local name="unpatch-dry-run-readonly-home"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local dry_run_output

    create_fixture "$name" "modern" "$app_constants_relpath"
    SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/patch-firefox.sh" --mozilla-home "$fixture_home" > /dev/null

    chmod a-w "$fixture_home" || true
    if ! dry_run_output=$("$REPO_ROOT/unpatch-firefox.sh" --dry-run --mozilla-home "$fixture_home"); then
        chmod u+w "$fixture_home" || true
        echo "$name: unpatch dry-run should not require write access to MOZILLA_HOME"
        exit 1
    fi
    assert_output_contains "$name" "$dry_run_output" "Dry run OK"
    assert_output_contains "$name" "$dry_run_output" "next step: run the same command without --dry-run to restore Firefox."

    chmod u+w "$fixture_home" || true
    if [[ ! -f "$fixture_home/omni-orig.ja" ]]; then
        echo "$name: unpatch dry-run removed omni-orig.ja"
        exit 1
    fi
    assert_app_constants_value "$name" "$fixture_home/omni.ja" "$app_constants_relpath" "false"

    SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/unpatch-firefox.sh" --mozilla-home "$fixture_home" > /dev/null
}

run_patch_dry_run_readonly_home_fixture() {
    local name="modern-dry-run-readonly-home"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local dry_run_output

    create_fixture "$name" "modern" "$app_constants_relpath"
    chmod a-w "$fixture_home" || true

    if ! dry_run_output=$(MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" --dry-run); then
        chmod u+w "$fixture_home" || true
        echo "$name: patch dry-run should not require write access to MOZILLA_HOME"
        exit 1
    fi
    assert_output_contains "$name" "$dry_run_output" "next step: run the same command without --dry-run to patch Firefox."

    chmod u+w "$fixture_home" || true
    assert_no_patch_side_effects "$name" "$fixture_home"
    assert_app_constants_value "$name" "$fixture_home/omni.ja" "$app_constants_relpath" "true"
}

run_mozilla_home_argument_fixture() {
    local name="mozilla-home-argument"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local windows_home
    local status_output

    create_fixture "$name" "modern" "$app_constants_relpath"

    env -u MOZILLA_HOME "$REPO_ROOT/patch-firefox.sh" --dry-run --mozilla-home "$fixture_home" > /dev/null
    assert_no_patch_side_effects "$name" "$fixture_home"
    assert_app_constants_value "$name" "$fixture_home/omni.ja" "$app_constants_relpath" "true"

    if command -v cygpath > /dev/null 2>&1; then
        windows_home=$(cygpath -w "$fixture_home")

        status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 env -u MOZILLA_HOME "$REPO_ROOT/patch-firefox.sh" --status --mozilla-home "$windows_home")
        assert_output_contains "$name-windows-status-home" "$status_output" "MOZILLA_HOME=$fixture_home"
        assert_output_contains "$name-windows-status" "$status_output" "MOZ_REQUIRE_SIGNING: true"

        env -u MOZILLA_HOME "$REPO_ROOT/patch-firefox.sh" --dry-run --mozilla-home "$windows_home" > /dev/null
        assert_no_patch_side_effects "$name-windows-dry-run" "$fixture_home"

        status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 MOZILLA_HOME="$windows_home" "$REPO_ROOT/unpatch-firefox.sh" --status)
        assert_output_contains "$name-windows-env-status-home" "$status_output" "MOZILLA_HOME=$fixture_home"
        assert_output_contains "$name-windows-env-status" "$status_output" "MOZ_REQUIRE_SIGNING: true"
    fi
}

run_path_error_fixture() {
    local name="path-errors"
    local missing_home="$TEMPDIR/$name/missing-firefox"
    local empty_home="$TEMPDIR/$name/empty-firefox"
    local missing_profile="$TEMPDIR/$name/missing-profile"
    local missing_profiles_ini="$TEMPDIR/$name/missing-profiles.ini"

    mkdir -p "$empty_home"

    assert_command_fails_with "$name-patch-missing-home" "Couldn't find Firefox install directory:" \
        env -u MOZILLA_HOME "$REPO_ROOT/patch-firefox.sh" --status --mozilla-home "$missing_home"
    assert_command_fails_with "$name-patch-empty-home" "Pass the folder that contains omni.ja" \
        env -u MOZILLA_HOME "$REPO_ROOT/patch-firefox.sh" --status --mozilla-home "$empty_home"

    assert_command_fails_with "$name-unpatch-missing-home" "Expected a directory containing omni.ja" \
        env -u MOZILLA_HOME "$REPO_ROOT/unpatch-firefox.sh" --status --mozilla-home "$missing_home"
    assert_command_fails_with "$name-unpatch-empty-home" "Couldn't find omni.ja in Firefox install directory:" \
        env -u MOZILLA_HOME "$REPO_ROOT/unpatch-firefox.sh" --status --mozilla-home "$empty_home"

    assert_command_fails_with "$name-missing-profile" "Pass a Firefox profile directory, not the Firefox install directory." \
        "$REPO_ROOT/clear-startup-cache.sh" --status --profile "$missing_profile"
    assert_command_fails_with "$name-missing-profiles-ini" "Pass a Firefox profiles.ini file or omit --profiles-ini" \
        "$REPO_ROOT/clear-startup-cache.sh" --status --profiles-ini "$missing_profiles_ini"
}

run_patch_failure_fixture() {
    local name=$1
    local format=$2
    local app_constants_relpath=$3
    local fixture_home="$TEMPDIR/$name/firefox"

    create_fixture "$name" "$format" "$app_constants_relpath"

    if SKIP_FIREFOX_PROCESS_CHECK=1 MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" > /dev/null 2> /dev/null; then
        echo "$name: patch unexpectedly succeeded"
        exit 1
    fi

    if [[ $format == "modern-false" ]]; then
        assert_command_fails_with "$name-message" "MOZ_REQUIRE_SIGNING is already false in AppConstants." \
            env SKIP_FIREFOX_PROCESS_CHECK=1 MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh"
    fi

    assert_no_patch_side_effects "$name" "$fixture_home"
}

run_process_guard_fixture() {
    local name="running-firefox-guard"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local fake_bin="$TEMPDIR/$name/fake-bin"
    local status_output

    create_fixture "$name" "modern" "$app_constants_relpath"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/powershell.exe" <<'POWERSHELL'
#!/usr/bin/env bash
echo 12345
POWERSHELL
    chmod +x "$fake_bin/powershell.exe"

    status_output=$(PATH="$fake_bin:$PATH" MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" --status)
    assert_output_contains "$name-status" "$status_output" "firefox process: running from MOZILLA_HOME"
    assert_output_contains "$name-status" "$status_output" "next step: close Firefox before patching."

    if PATH="$fake_bin:$PATH" MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" > /dev/null 2> /dev/null; then
        echo "$name: patch unexpectedly succeeded while Firefox was reported running"
        exit 1
    fi

    assert_no_patch_side_effects "$name" "$fixture_home"
    assert_app_constants_value "$name" "$fixture_home/omni.ja" "$app_constants_relpath" "true"
}

run_unpatch_process_guard_fixture() {
    local name="running-firefox-unpatch-guard"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local fake_bin="$TEMPDIR/$name/fake-bin"
    local status_output

    create_fixture "$name" "modern" "$app_constants_relpath"
    SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/patch-firefox.sh" --mozilla-home "$fixture_home" > /dev/null

    mkdir -p "$fake_bin"
    cat > "$fake_bin/powershell.exe" <<'POWERSHELL'
#!/usr/bin/env bash
echo 12345
POWERSHELL
    chmod +x "$fake_bin/powershell.exe"

    status_output=$(PATH="$fake_bin:$PATH" "$REPO_ROOT/unpatch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-status" "$status_output" "firefox process: running from MOZILLA_HOME"
    assert_output_contains "$name-status" "$status_output" "next step: close Firefox before restoring."

    if PATH="$fake_bin:$PATH" "$REPO_ROOT/unpatch-firefox.sh" --mozilla-home "$fixture_home" > /dev/null 2> /dev/null; then
        echo "$name: unpatch unexpectedly succeeded while Firefox was reported running"
        exit 1
    fi

    if [[ ! -f "$fixture_home/omni-orig.ja" ]]; then
        echo "$name: unpatch process guard removed omni-orig.ja"
        exit 1
    fi

    if compgen -G "$fixture_home/omni.ja.restore.*" > /dev/null; then
        echo "$name: unpatch process guard left restore temp file"
        exit 1
    fi

    assert_app_constants_value "$name" "$fixture_home/omni.ja" "$app_constants_relpath" "false"
}

run_startup_cache_fixture() {
    local name="startup-cache-profiles-ini"
    local firefox_data="$TEMPDIR/$name/firefox-data"
    local relative_profile="$firefox_data/Profiles/abc.default"
    local absolute_profile="$TEMPDIR/$name/absolute.default"
    local stray_profile="$firefox_data/Profiles/not-listed.default"
    local direct_profile="$TEMPDIR/$name/direct.default"
    local dry_run_output
    local status_output
    local clean_output
    local remove_output
    local direct_remove_output
    local empty_profiles_ini="$TEMPDIR/$name/empty-profiles.ini"
    local guard_profile="$TEMPDIR/$name/running-firefox.default"
    local fake_bin="$TEMPDIR/$name/fake-bin"
    local guard_status_output
    local windows_ini
    local windows_profile
    local windows_direct_profile
    local windows_ini_arg
    local windows_profile_arg
    local windows_direct_profile_arg

    mkdir -p \
        "$relative_profile/startupCache" \
        "$absolute_profile/startupCache" \
        "$stray_profile/startupCache" \
        "$direct_profile/startupCache" \
        "$guard_profile/startupCache" \
        "$fake_bin"

    echo "cache" > "$relative_profile/startupCache/startupCache.8.little"
    echo "cache" > "$absolute_profile/startupCache/startupCache.8.little"
    echo "cache" > "$stray_profile/startupCache/startupCache.8.little"
    echo "cache" > "$direct_profile/startupCache/startupCache.8.little"
    echo "cache" > "$guard_profile/startupCache/startupCache.8.little"
    cat > "$fake_bin/powershell.exe" <<'POWERSHELL'
#!/usr/bin/env bash
echo 12345
POWERSHELL
    chmod +x "$fake_bin/powershell.exe"

    cat > "$firefox_data/profiles.ini" <<PROFILES_INI
[Profile0]
Name=default
IsRelative=1
Path=Profiles/abc.default

[Profile1]
Name=absolute
IsRelative=0
Path=$absolute_profile
PROFILES_INI

    : > "$empty_profiles_ini"
    status_output=$("$REPO_ROOT/clear-startup-cache.sh" --status --profiles-ini "$empty_profiles_ini")
    assert_output_contains "$name-empty-status" "$status_output" "No Firefox profiles found."
    assert_output_contains "$name-empty-status" "$status_output" "next step: pass --profile or --profiles-ini if Firefox uses an unusual profile location."

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/clear-startup-cache.sh" --status --profiles-ini "$firefox_data/profiles.ini")
    assert_output_contains "$name-status" "$status_output" "profiles: 2"
    assert_output_contains "$name-status" "$status_output" "startupCache: present $relative_profile/startupCache"
    assert_output_contains "$name-status" "$status_output" "startupCache: present $absolute_profile/startupCache"
    assert_output_contains "$name-status" "$status_output" "startupCache directories: 2"
    assert_output_contains "$name-status" "$status_output" "firefox process: not detected"
    assert_output_contains "$name-status" "$status_output" "next step: run this script with --dry-run to preview startupCache cleanup."

    guard_status_output=$(PATH="$fake_bin:$PATH" "$REPO_ROOT/clear-startup-cache.sh" --status --profile "$guard_profile")
    assert_output_contains "$name-running-status" "$guard_status_output" "firefox process: running"
    assert_output_contains "$name-running-status" "$guard_status_output" "next step: close Firefox before clearing startupCache."

    if PATH="$fake_bin:$PATH" "$REPO_ROOT/clear-startup-cache.sh" --profile "$guard_profile" > /dev/null 2> /dev/null; then
        echo "$name: startupCache cleanup unexpectedly succeeded while Firefox was reported running"
        exit 1
    fi
    if [[ ! -d "$guard_profile/startupCache" ]]; then
        echo "$name: process guard removed startupCache"
        exit 1
    fi

    dry_run_output=$(PATH="$fake_bin:$PATH" "$REPO_ROOT/clear-startup-cache.sh" --dry-run --profile "$guard_profile")
    assert_output_contains "$name-running-dry-run" "$dry_run_output" "warning: Firefox appears to be running. Close Firefox before running cleanup for real."
    assert_output_contains "$name-running-dry-run" "$dry_run_output" "Would remove $guard_profile/startupCache"
    assert_output_contains "$name-running-dry-run" "$dry_run_output" "Dry run OK"
    if [[ ! -d "$guard_profile/startupCache" ]]; then
        echo "$name: running dry-run removed startupCache"
        exit 1
    fi

    dry_run_output=$("$REPO_ROOT/clear-startup-cache.sh" --dry-run --profiles-ini "$firefox_data/profiles.ini")
    assert_output_contains "$name-dry-run" "$dry_run_output" "Would remove $relative_profile/startupCache"
    assert_output_contains "$name-dry-run" "$dry_run_output" "Would remove $absolute_profile/startupCache"
    assert_output_contains "$name-dry-run" "$dry_run_output" "Dry run OK"
    assert_output_contains "$name-dry-run" "$dry_run_output" "next step: run the same command without --dry-run to clear the listed startupCache directories."

    if [[ ! -d "$relative_profile/startupCache" || ! -d "$absolute_profile/startupCache" ]]; then
        echo "$name: dry-run removed startupCache"
        exit 1
    fi

    remove_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/clear-startup-cache.sh" --profiles-ini "$firefox_data/profiles.ini")
    assert_output_contains "$name-remove" "$remove_output" "Removed $relative_profile/startupCache"
    assert_output_contains "$name-remove" "$remove_output" "Removed $absolute_profile/startupCache"
    assert_output_contains "$name-remove" "$remove_output" "Done"
    assert_output_contains "$name-remove" "$remove_output" "next step: start Firefox and verify MOZ_REQUIRE_SIGNING if you just patched Firefox."
    if [[ -d "$relative_profile/startupCache" || -d "$absolute_profile/startupCache" ]]; then
        echo "$name: listed startupCache directory was not removed"
        exit 1
    fi

    if [[ ! -d "$stray_profile/startupCache" ]]; then
        echo "$name: unlisted profile startupCache was removed"
        exit 1
    fi

    clean_output=$("$REPO_ROOT/clear-startup-cache.sh" --profiles-ini "$firefox_data/profiles.ini")
    assert_output_contains "$name-clean" "$clean_output" "No startupCache directories found."

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/clear-startup-cache.sh" --status --profiles-ini "$firefox_data/profiles.ini")
    assert_output_contains "$name-clean-status" "$status_output" "startupCache directories: 0"
    assert_output_contains "$name-clean-status" "$status_output" "next step: no startupCache cleanup needed."

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/clear-startup-cache.sh" --status --profile "$direct_profile")
    assert_output_contains "$name-direct-status" "$status_output" "profiles: 1"
    assert_output_contains "$name-direct-status" "$status_output" "startupCache: present $direct_profile/startupCache"
    assert_output_contains "$name-direct-status" "$status_output" "startupCache directories: 1"

    direct_remove_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/clear-startup-cache.sh" --profile "$direct_profile")
    assert_output_contains "$name-direct-remove" "$direct_remove_output" "next step: start Firefox and verify MOZ_REQUIRE_SIGNING if you just patched Firefox."
    if [[ -d "$direct_profile/startupCache" ]]; then
        echo "$name: explicit profile startupCache was not removed"
        exit 1
    fi

    if command -v cygpath > /dev/null 2>&1; then
        windows_ini="$TEMPDIR/$name/windows-profiles.ini"
        windows_profile="$TEMPDIR/$name/windows-absolute.default"
        windows_direct_profile="$TEMPDIR/$name/windows-direct.default"
        mkdir -p "$windows_profile/startupCache" "$windows_direct_profile/startupCache"
        echo "cache" > "$windows_profile/startupCache/startupCache.8.little"
        echo "cache" > "$windows_direct_profile/startupCache/startupCache.8.little"

        windows_ini_arg=$(cygpath -w "$windows_ini")
        windows_profile_arg=$(cygpath -w "$windows_profile")
        windows_direct_profile_arg=$(cygpath -w "$windows_direct_profile")

        cat > "$windows_ini" <<PROFILES_INI
[Profile0]
Name=windows-absolute
IsRelative=0
Path=$windows_profile_arg
PROFILES_INI

        dry_run_output=$("$REPO_ROOT/clear-startup-cache.sh" --dry-run --profiles-ini "$windows_ini_arg")
        assert_output_contains "$name-windows-dry-run" "$dry_run_output" "Would remove $windows_profile/startupCache"

        SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/clear-startup-cache.sh" --profiles-ini "$windows_ini_arg" > /dev/null
        if [[ -d "$windows_profile/startupCache" ]]; then
            echo "$name: Windows profiles.ini path startupCache was not removed"
            exit 1
        fi

        SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/clear-startup-cache.sh" --profile "$windows_direct_profile_arg" > /dev/null
        if [[ -d "$windows_direct_profile/startupCache" ]]; then
            echo "$name: Windows --profile startupCache was not removed"
            exit 1
        fi
    fi
}

run_unsigned_addon_pref_fixture() {
    local name="unsigned-addon-pref-profiles"
    local firefox_data="$TEMPDIR/$name/firefox-data"
    local default_profile="$firefox_data/Profiles/default-release"
    local other_profile="$firefox_data/Profiles/other"
    local third_profile="$firefox_data/Profiles/third"
    local no_default_data="$TEMPDIR/$name/no-default-data"
    local no_default_a="$no_default_data/Profiles/a"
    local no_default_b="$no_default_data/Profiles/b"
    local guard_profile="$TEMPDIR/$name/running.default"
    local fake_bin="$TEMPDIR/$name/fake-bin"
    local status_output
    local dry_run_output
    local list_output
    local update_output
    local all_output

    mkdir -p "$default_profile" "$other_profile" "$third_profile" "$no_default_a" "$no_default_b" "$guard_profile" "$fake_bin"
    cat > "$default_profile/prefs.js" <<'PREFS'
user_pref("browser.startup.homepage", "about:blank");
user_pref("xpinstall.signatures.required", true);
PREFS
    cat > "$other_profile/prefs.js" <<'PREFS'
user_pref("xpinstall.signatures.required", true);
PREFS
    cat > "$no_default_a/prefs.js" <<'PREFS'
user_pref("xpinstall.signatures.required", true);
PREFS
    cat > "$no_default_b/prefs.js" <<'PREFS'
user_pref("xpinstall.signatures.required", true);
PREFS
    cat > "$guard_profile/prefs.js" <<'PREFS'
user_pref("xpinstall.signatures.required", true);
PREFS

    cat > "$firefox_data/profiles.ini" <<PROFILES_INI
[Profile0]
Name=default
IsRelative=1
Path=Profiles/default-release
Default=1

[Profile1]
Name=other
IsRelative=1
Path=Profiles/other

[Profile2]
Name=third
IsRelative=1
Path=Profiles/third
PROFILES_INI

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/set-unsigned-addon-pref.sh" --status --profiles-ini "$firefox_data/profiles.ini")
    assert_output_contains "$name-status" "$status_output" "profiles: 3"
    assert_output_contains "$name-status" "$status_output" "default profile: $default_profile"
    assert_output_contains "$name-status" "$status_output" "target profile: $default_profile"
    assert_output_contains "$name-status" "$status_output" "xpinstall.signatures.required: true"

    list_output=$("$REPO_ROOT/set-unsigned-addon-pref.sh" --list-profiles --profiles-ini "$firefox_data/profiles.ini")
    assert_output_contains "$name-list" "$list_output" "1|"
    assert_output_contains "$name-list" "$list_output" "|default"
    assert_output_contains "$name-list" "$list_output" "2|"

    dry_run_output=$("$REPO_ROOT/set-unsigned-addon-pref.sh" --dry-run --profiles-ini "$firefox_data/profiles.ini")
    assert_output_contains "$name-dry-run" "$dry_run_output" "Would set xpinstall.signatures.required=false in $default_profile/prefs.js"
    assert_output_contains "$name-dry-run" "$dry_run_output" "Dry run OK"
    if grep -Fq 'user_pref("xpinstall.signatures.required", false);' "$default_profile/prefs.js"; then
        echo "$name: dry-run changed default profile prefs.js"
        exit 1
    fi

    update_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/set-unsigned-addon-pref.sh" --profiles-ini "$firefox_data/profiles.ini")
    assert_output_contains "$name-update-default" "$update_output" "Backup: $default_profile/prefs.js.before-enable-unsigned-addons"
    assert_output_contains "$name-update-default" "$update_output" "Updated $default_profile/prefs.js"
    assert_output_contains "$name-update-default" "$update_output" "Done"
    if ! grep -Fq 'user_pref("xpinstall.signatures.required", false);' "$default_profile/prefs.js"; then
        echo "$name: default profile pref was not set false"
        exit 1
    fi
    if grep -Fq 'user_pref("xpinstall.signatures.required", false);' "$other_profile/prefs.js"; then
        echo "$name: default update changed other profile"
        exit 1
    fi

    update_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/set-unsigned-addon-pref.sh" --profile "$other_profile")
    assert_output_contains "$name-update-one-profile" "$update_output" "Updated $other_profile/prefs.js"
    if ! grep -Fq 'user_pref("xpinstall.signatures.required", false);' "$other_profile/prefs.js"; then
        echo "$name: explicit profile pref was not set false"
        exit 1
    fi

    all_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/set-unsigned-addon-pref.sh" --all-profiles --profiles-ini "$firefox_data/profiles.ini")
    assert_output_contains "$name-all-profiles" "$all_output" "Updated $third_profile/prefs.js"
    if ! grep -Fq 'user_pref("xpinstall.signatures.required", false);' "$third_profile/prefs.js"; then
        echo "$name: all-profiles did not create third profile pref"
        exit 1
    fi

    cat > "$no_default_data/profiles.ini" <<PROFILES_INI
[Profile0]
Name=a
IsRelative=1
Path=Profiles/a

[Profile1]
Name=b
IsRelative=1
Path=Profiles/b
PROFILES_INI
    assert_command_fails_with "$name-no-default" "Multiple Firefox profiles were found, but no default profile was detected." \
        "$REPO_ROOT/set-unsigned-addon-pref.sh" --dry-run --profiles-ini "$no_default_data/profiles.ini"

    cat > "$fake_bin/powershell.exe" <<'POWERSHELL'
#!/usr/bin/env bash
echo 12345
POWERSHELL
    chmod +x "$fake_bin/powershell.exe"
    if PATH="$fake_bin:$PATH" "$REPO_ROOT/set-unsigned-addon-pref.sh" --profile "$guard_profile" > /dev/null 2> /dev/null; then
        echo "$name: profile preference update unexpectedly succeeded while Firefox was reported running"
        exit 1
    fi
    if grep -Fq 'user_pref("xpinstall.signatures.required", false);' "$guard_profile/prefs.js"; then
        echo "$name: process guard changed prefs.js"
        exit 1
    fi
}

run_roundtrip_fixture "modern-sysm" "modern" "modules/AppConstants.sys.mjs"
run_roundtrip_fixture "legacy-jsm" "legacy" "modules/AppConstants.jsm"
run_status_fixture
run_patch_dry_run_fixture
run_prefixed_archive_fixture
run_prefixed_archive_exit_2_fixture
run_corrupt_archive_fixture
run_patch_dry_run_readonly_home_fixture
run_unpatch_dry_run_readonly_home_fixture
run_mozilla_home_argument_fixture
run_path_error_fixture
run_patch_failure_fixture "already-false" "modern-false" "modules/AppConstants.sys.mjs"
run_patch_failure_fixture "missing-appconstants" "missing" "modules/AppConstants.sys.mjs"
run_process_guard_fixture
run_unpatch_process_guard_fixture
run_startup_cache_fixture
run_unsigned_addon_pref_fixture

echo "Fixture verification completed."
