#!/bin/bash -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

TEMPDIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEMPDIR"
}
trap cleanup EXIT

FIXTURE_HOME="$TEMPDIR/firefox"
OMNI_SOURCE="$TEMPDIR/omni-source"
mkdir -p "$FIXTURE_HOME" "$OMNI_SOURCE/modules"

cat > "$OMNI_SOURCE/modules/AppConstants.sys.mjs" <<'APP_CONSTANTS'
export var AppConstants = {
  MOZ_REQUIRE_SIGNING:
#ifdef MOZ_REQUIRE_SIGNING
  true,
#endif
};
APP_CONSTANTS

pushd "$OMNI_SOURCE" > /dev/null
zip -qr9XD "$FIXTURE_HOME/omni.ja" .
popd > /dev/null

MOZILLA_HOME="$FIXTURE_HOME" "$REPO_ROOT/patch-firefox.sh" > /dev/null

if [[ ! -f "$FIXTURE_HOME/omni-orig.ja" ]]; then
    echo "patch did not create omni-orig.ja"
    exit 1
fi

mkdir "$TEMPDIR/patched"
unzip -q -d "$TEMPDIR/patched" "$FIXTURE_HOME/omni.ja"
if ! grep -q "  false," "$TEMPDIR/patched/modules/AppConstants.sys.mjs"; then
    echo "patch did not set MOZ_REQUIRE_SIGNING to false"
    exit 1
fi

MOZILLA_HOME="$FIXTURE_HOME" "$REPO_ROOT/unpatch-firefox.sh"

if [[ -f "$FIXTURE_HOME/omni-orig.ja" ]]; then
    echo "unpatch did not remove omni-orig.ja"
    exit 1
fi

mkdir "$TEMPDIR/restored"
unzip -q -d "$TEMPDIR/restored" "$FIXTURE_HOME/omni.ja"
if ! grep -q "  true," "$TEMPDIR/restored/modules/AppConstants.sys.mjs"; then
    echo "unpatch did not restore MOZ_REQUIRE_SIGNING to true"
    exit 1
fi

echo "Fixture verification completed."

