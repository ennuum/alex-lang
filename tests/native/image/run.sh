#!/bin/sh
# image.encode : compilé en natif puis exécuté (les modules image.* n'existent qu'en natif). Depuis la racine.
ALEX_BIN=${ALEX_BIN:-./alexc}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$ALEX_BIN" build --native tests/native/image/test_encode.al -o "$TMP/test_encode" || exit 1
"$TMP/test_encode"
