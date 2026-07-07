#!/bin/bash -e

if [[ -z $MOZILLA_HOME ]]; then
    echo "Set MOZILLA_HOME first"
    exit 1
fi

OMNI_FILE="$MOZILLA_HOME/omni.ja"
ORIGINAL_OMNI_FILE="$MOZILLA_HOME/omni-orig.ja"

if [[ ! -f $OMNI_FILE ]]; then
    echo "Couldn't find $OMNI_FILE"
    exit 1
fi

if [[ -f $ORIGINAL_OMNI_FILE ]]; then
    echo "Already patched?"
    exit 1
fi

cp -p "$OMNI_FILE" "$ORIGINAL_OMNI_FILE"

TEMPDIR=$(mktemp -d)
if [[ ! -d $TEMPDIR ]]; then
   echo "Couldn't create tempdir"
   exit 1
fi

cleanup() {
    rm -rf "$TEMPDIR"
}
trap cleanup EXIT

unzip -q -d "$TEMPDIR" "$OMNI_FILE" || true

APP_CONSTANTS_FILE=""
for candidate in "$TEMPDIR/modules/AppConstants.sys.mjs" "$TEMPDIR/modules/AppConstants.jsm"; do
    if [[ -f $candidate ]]; then
        APP_CONSTANTS_FILE=$candidate
        break
    fi
done

if [[ -z $APP_CONSTANTS_FILE ]]; then
    echo "Unzip was unsuccessful"
    exit 1
fi

SIGNLINE=$(grep -n "MOZ_REQUIRE_SIGNING:" "$APP_CONSTANTS_FILE" | cut -d: -f 1 | head -n 1)
if [[ -z $SIGNLINE ]]; then
    echo "Didn't find MOZ_REQUIRE_SIGNING in AppConstants"
    exit 1
fi

CURRENT_CONST=$(sed -n "$((SIGNLINE + 2))p" "$APP_CONSTANTS_FILE")

if [[ $CURRENT_CONST != "  true," ]]; then
    echo "Didn't find correct data in existing file"
    exit 1
fi

sed -i -e "$((SIGNLINE + 2))s/true/false/" "$APP_CONSTANTS_FILE"

rm "$OMNI_FILE"
pushd "$TEMPDIR" > /dev/null
zip -qr9XD "$OMNI_FILE" .
popd > /dev/null

echo Done
