#!/bin/sh
# Construit {{Nom}} pour Linux : dist/{{nom}} (binaire natif x86-64).
#   sh scripts/construire.sh            (ALEXC=chemin/vers/alexc pour un autre outil)
set -e
cd "$(dirname "$0")/.."
ALEXC=${ALEXC:-$(command -v alexc || command -v alex)}
[ -n "$ALEXC" ] || { echo "alexc introuvable : ajoutez-le au PATH ou définissez ALEXC" >&2; exit 1; }
mkdir -p dist
"$ALEXC" build --native src/main.al -o dist/{{nom}}
echo "dist/{{nom}}"
