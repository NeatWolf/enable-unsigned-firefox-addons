#!/bin/bash -e

if [[ -z $MOZILLA_HOME ]]; then
    echo "Set MOZILLA_HOME first"
    exit 1
fi

OMNI_FILE="$MOZILLA_HOME/omni.ja"
ORIGINAL_OMNI_FILE="$MOZILLA_HOME/omni-orig.ja"

if [[ ! -f $ORIGINAL_OMNI_FILE ]]; then
    echo "Not already patched"
    exit 1
fi

cp -p "$ORIGINAL_OMNI_FILE" "$OMNI_FILE"
rm "$ORIGINAL_OMNI_FILE"
