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

run_roundtrip_fixture() {
    local name=$1
    local format=$2
    local app_constants_relpath=$3
    local fixture_home="$TEMPDIR/$name/firefox"

    create_fixture "$name" "$format" "$app_constants_relpath"

    SKIP_FIREFOX_PROCESS_CHECK=1 MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" > /dev/null
    if [[ ! -f "$fixture_home/omni-orig.ja" ]]; then
        echo "$name: patch did not create omni-orig.ja"
        exit 1
    fi
    assert_app_constants_value "$name-patched" "$fixture_home/omni.ja" "$app_constants_relpath" "false"

    MOZILLA_HOME="$fixture_home" "$REPO_ROOT/unpatch-firefox.sh" --dry-run > /dev/null
    if [[ ! -f "$fixture_home/omni-orig.ja" ]]; then
        echo "$name: unpatch dry-run removed omni-orig.ja"
        exit 1
    fi
    assert_app_constants_value "$name-unpatch-dry-run" "$fixture_home/omni.ja" "$app_constants_relpath" "false"

    SKIP_FIREFOX_PROCESS_CHECK=1 MOZILLA_HOME="$fixture_home" "$REPO_ROOT/unpatch-firefox.sh" > /dev/null
    if [[ -f "$fixture_home/omni-orig.ja" ]]; then
        echo "$name: unpatch did not remove omni-orig.ja"
        exit 1
    fi
    assert_app_constants_value "$name-restored" "$fixture_home/omni.ja" "$app_constants_relpath" "true"
}

run_status_fixture() {
    local name="status-mode"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local status_output

    create_fixture "$name" "modern" "$app_constants_relpath"

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/patch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-patch-unpatched" "$status_output" "MOZ_REQUIRE_SIGNING: true"
    assert_output_contains "$name-patch-unpatched" "$status_output" "omni-orig.ja: absent"
    assert_output_contains "$name-patch-unpatched" "$status_output" "state: unpatched"

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/unpatch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-unpatch-unpatched" "$status_output" "MOZ_REQUIRE_SIGNING: true"
    assert_output_contains "$name-unpatch-unpatched" "$status_output" "state: unpatched"

    SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/patch-firefox.sh" --mozilla-home "$fixture_home" > /dev/null

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/patch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-patch-patched" "$status_output" "MOZ_REQUIRE_SIGNING: false"
    assert_output_contains "$name-patch-patched" "$status_output" "omni-orig.ja: present"
    assert_output_contains "$name-patch-patched" "$status_output" "state: patched with rollback backup"

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/unpatch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-unpatch-patched" "$status_output" "MOZ_REQUIRE_SIGNING: false"
    assert_output_contains "$name-unpatch-patched" "$status_output" "state: patched with rollback backup"

    SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/unpatch-firefox.sh" --mozilla-home "$fixture_home" > /dev/null

    status_output=$(SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/patch-firefox.sh" --status --mozilla-home "$fixture_home")
    assert_output_contains "$name-patch-restored" "$status_output" "MOZ_REQUIRE_SIGNING: true"
    assert_output_contains "$name-patch-restored" "$status_output" "omni-orig.ja: absent"
    assert_output_contains "$name-patch-restored" "$status_output" "state: unpatched"
}

run_patch_dry_run_fixture() {
    local name="modern-dry-run"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"

    create_fixture "$name" "modern" "$app_constants_relpath"

    MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" --dry-run > /dev/null
    assert_no_patch_side_effects "$name" "$fixture_home"
    assert_app_constants_value "$name" "$fixture_home/omni.ja" "$app_constants_relpath" "true"
}

run_unpatch_dry_run_readonly_home_fixture() {
    local name="unpatch-dry-run-readonly-home"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"

    create_fixture "$name" "modern" "$app_constants_relpath"
    SKIP_FIREFOX_PROCESS_CHECK=1 "$REPO_ROOT/patch-firefox.sh" --mozilla-home "$fixture_home" > /dev/null

    chmod a-w "$fixture_home" || true
    if ! "$REPO_ROOT/unpatch-firefox.sh" --dry-run --mozilla-home "$fixture_home" > /dev/null; then
        chmod u+w "$fixture_home" || true
        echo "$name: unpatch dry-run should not require write access to MOZILLA_HOME"
        exit 1
    fi

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

    create_fixture "$name" "modern" "$app_constants_relpath"
    chmod a-w "$fixture_home" || true

    if ! MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" --dry-run > /dev/null; then
        chmod u+w "$fixture_home" || true
        echo "$name: patch dry-run should not require write access to MOZILLA_HOME"
        exit 1
    fi

    chmod u+w "$fixture_home" || true
    assert_no_patch_side_effects "$name" "$fixture_home"
    assert_app_constants_value "$name" "$fixture_home/omni.ja" "$app_constants_relpath" "true"
}

run_mozilla_home_argument_fixture() {
    local name="mozilla-home-argument"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"

    create_fixture "$name" "modern" "$app_constants_relpath"

    env -u MOZILLA_HOME "$REPO_ROOT/patch-firefox.sh" --dry-run --mozilla-home "$fixture_home" > /dev/null
    assert_no_patch_side_effects "$name" "$fixture_home"
    assert_app_constants_value "$name" "$fixture_home/omni.ja" "$app_constants_relpath" "true"
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

    assert_no_patch_side_effects "$name" "$fixture_home"
}

run_process_guard_fixture() {
    local name="running-firefox-guard"
    local app_constants_relpath="modules/AppConstants.sys.mjs"
    local fixture_home="$TEMPDIR/$name/firefox"
    local fake_bin="$TEMPDIR/$name/fake-bin"

    create_fixture "$name" "modern" "$app_constants_relpath"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/powershell.exe" <<'POWERSHELL'
#!/usr/bin/env bash
echo 12345
POWERSHELL
    chmod +x "$fake_bin/powershell.exe"

    if PATH="$fake_bin:$PATH" MOZILLA_HOME="$fixture_home" "$REPO_ROOT/patch-firefox.sh" > /dev/null 2> /dev/null; then
        echo "$name: patch unexpectedly succeeded while Firefox was reported running"
        exit 1
    fi

    assert_no_patch_side_effects "$name" "$fixture_home"
    assert_app_constants_value "$name" "$fixture_home/omni.ja" "$app_constants_relpath" "true"
}

run_roundtrip_fixture "modern-sysm" "modern" "modules/AppConstants.sys.mjs"
run_roundtrip_fixture "legacy-jsm" "legacy" "modules/AppConstants.jsm"
run_status_fixture
run_patch_dry_run_fixture
run_patch_dry_run_readonly_home_fixture
run_unpatch_dry_run_readonly_home_fixture
run_mozilla_home_argument_fixture
run_patch_failure_fixture "already-false" "modern-false" "modules/AppConstants.sys.mjs"
run_patch_failure_fixture "missing-appconstants" "missing" "modules/AppConstants.sys.mjs"
run_process_guard_fixture

echo "Fixture verification completed."
