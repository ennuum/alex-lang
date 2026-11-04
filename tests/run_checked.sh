#!/bin/sh
# Lance des programmes de test Alex qui finissent par « <nom> : N OK, M échecs » : échec si le code de sortie
# n'est pas 0 ou si M n'est pas 0. Usage : tests/run_checked.sh fichier.al [fichier.al...]
ALEX_BIN=${ALEX_BIN:-./alex}
fails=0
for t in "$@"; do
    out=$("$ALEX_BIN" run "$t" 2>&1)
    rc=$?
    summary=$(printf '%s\n' "$out" | grep -E ' [0-9]+ OK, [0-9]+ échecs' | tail -1)
    if [ $rc -ne 0 ] || [ -z "$summary" ] || ! printf '%s' "$summary" | grep -q ' 0 échecs'; then
        printf '%s\n' "$out" | grep -E 'ÉCHEC|Error|erreur' | head -20
        echo "ÉCHEC $t (code $rc) ${summary}"
        fails=$((fails + 1))
    else
        echo "ok    $summary"
    fi
done
[ $fails -eq 0 ]
