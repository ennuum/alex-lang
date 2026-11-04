#!/bin/sh
# Couverture du compilateur natif : chaque programme du corpus (examples/, tests/ hors tests/native) est
# compilé avec `alexc build --native`, exécuté, et sa sortie (standard + code de sortie) comparée à la VM.
# Usage : sh tools/native_coverage.sh [fichiers.al...]   (depuis la racine du projet)
# Sortie : une ligne par programme (OK / DIFF / KO + première erreur), puis le bilan. NATIVE_COV_LOG=fichier
# garde le détail des erreurs de compilation.
ALEX_BIN=${ALEX_BIN:-./alex}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if [ $# -eq 0 ]; then
    set -- $(ls examples/*.al; find tests -name '*.al' -not -path 'tests/native/*' | sort)
fi
ok=0; diff=0; ko=0; n=0
for src in "$@"; do
    n=$((n + 1))
    # exécutable nommé comme le script (argv[0] : nom de programme par défaut, argparse...)
    mkdir -p "$TMP/$n"
    name="$n/$(basename "$src" .al)"
    if ! "$ALEX_BIN" build --native "$src" -o "$TMP/$name" > /dev/null 2> "$TMP/err"; then
        first=$(grep -v '^$' "$TMP/err" | head -1 | sed 's/^NativeError: //')
        # Programme refusé aussi par la VM (même diagnostic) : comportement identique.
        timeout 20 "$ALEX_BIN" run "$src" < /dev/null > /dev/null 2> "$TMP/vmerr"
        if [ "$(grep -v '^$' "$TMP/vmerr" | head -1)" = "$first" ] && [ -n "$first" ]; then
            ok=$((ok + 1)); echo "OK    $src (refusé comme par la VM)"
            continue
        fi
        ko=$((ko + 1))
        echo "KO    $src : $first"
        [ -n "$NATIVE_COV_LOG" ] && { echo "== $src"; cat "$TMP/err"; } >> "$NATIVE_COV_LOG"
        continue
    fi
    (cd "$(dirname "$src")" 2>/dev/null; true)
    timeout 20 "$ALEX_BIN" run "$src" < /dev/null > "$TMP/vm.out" 2> /dev/null; vm=$?
    timeout 20 "$TMP/$name" < /dev/null > "$TMP/nat.out" 2> /dev/null; nat=$?
    # Durées mesurées (« (0.0123 s) ») : non déterministes, neutralisées avant comparaison.
    for o in vm nat; do
        sed -E 's/[0-9]+(\.[0-9]+)?(e-?[0-9]+)? s\)/N s)/g; s/[0-9]+\.[0-9]{4,}(e-?[0-9]+)? s\b/N s/g' "$TMP/$o.out" > "$TMP/$o.norm"
    done
    if cmp -s "$TMP/vm.norm" "$TMP/nat.norm" && [ "$vm" -eq "$nat" ]; then
        ok=$((ok + 1)); echo "OK    $src"
    else
        diff=$((diff + 1)); echo "DIFF  $src (code VM $vm, natif $nat)"
        [ -n "$NATIVE_COV_LOG" ] && { echo "== $src (DIFF)"; timeout 20 "$TMP/$name" < /dev/null > /dev/null 2> "$TMP/nat.err"; grep -v '^  ' "$TMP/nat.err" | head -3;
                                       diff "$TMP/vm.norm" "$TMP/nat.norm" | head -6; } >> "$NATIVE_COV_LOG"
    fi
done
echo "couverture native : $ok / $n identiques à la VM, $diff différents, $ko refusés à la compilation"
