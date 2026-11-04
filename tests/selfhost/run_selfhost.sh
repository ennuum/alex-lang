#!/bin/sh
# Compilateur ALEX écrit en ALEX (docs/SELFHOST.md) :
#   1. point fixe de l'auto-compilation : le compilateur compilé par lui-même (bytecode) se reproduit à l'identique ;
#   2. le bytecode ainsi produit, exécuté par la VM, compile un programme comme la chaîne d'outils ;
#   3. table de référence (tests/selfhost/golden.tsv), sous-ensemble rapide : bytecode et exécutables de chaque
#      cible identiques octet pour octet à ceux du compilateur de référence, mêmes diagnostics de refus
#      (programmes de tests/selfhost/bad compris) — table complète : make test-golden.
# Lancer DEPUIS LA RACINE DU PROJET.
set -u
cd "$(dirname "$0")/../.."
A=${ALEX_BIN:-./alex}
VM=$(dirname "$(readlink -f "$A")")/alexvm
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0
ok() { echo "OK   $1"; }
ko() { echo "ÉCHEC $1"; fail=1; }

"$A" build src/alexc.al -o "$W/alexc1.albc" > /dev/null 2>&1
"$VM" "$W/alexc1.albc" build src/alexc.al -o "$W/alexc2.albc" > /dev/null 2>&1
[ -s "$W/alexc1.albc" ] && cmp -s "$W/alexc1.albc" "$W/alexc2.albc" && ok "point fixe : alex(alex) == alex (bytecode)" || ko "point fixe"
"$A" build tests/selfhost/progs/sh_oop.al -o "$W/p1.albc" > /dev/null 2>&1
"$VM" "$W/alexc2.albc" build tests/selfhost/progs/sh_oop.al -o "$W/p2.albc" > /dev/null 2>&1
cmp -s "$W/p1.albc" "$W/p2.albc" && ok "compilateur en bytecode == chaîne d'outils" || ko "compilateur en bytecode"
"$A" run tests/selfhost/progs/sh_oop.al > "$W/o1" 2>&1
"$VM" "$W/p2.albc" > "$W/o2" 2>&1
cmp -s "$W/o1" "$W/o2" && ok "exécution du programme compilé" || ko "exécution"

if bash tests/selfhost/golden.sh --quick "$A" > "$W/golden.txt" 2>&1; then ok "$(tail -1 "$W/golden.txt")"
else cat "$W/golden.txt"; ko "table de référence"; fi

[ $fail -eq 0 ] && echo "selfhost : tout est identique" || echo "selfhost : ÉCHECS"
exit $fail
