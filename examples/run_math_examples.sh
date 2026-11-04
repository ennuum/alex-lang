#!/bin/sh
# Lance tous les exemples/tests du module math et affiche un bilan.
# Usage : sh examples/run_math_examples.sh   (depuis n'importe où)
#
# Le dossier stdlib/ est résolu relativement au dossier courant : ce script
# se place donc à la racine du projet avant de lancer ./alex.
cd "$(dirname "$0")/.." || exit 1

errfile=$(mktemp)
status=0
total=0
failed=0

for f in examples/math_*.al; do
    total=$((total + 1))
    if ./alex run "$f" > /dev/null 2> "$errfile"; then
        echo "[OK]     $f"
    else
        echo "[ECHEC]  $f"
        sed 's/^/           /' "$errfile" | head -3
        failed=$((failed + 1))
        status=1
    fi
done

rm -f "$errfile"
echo ""
echo "$((total - failed))/$total fichiers réussis"
exit $status
