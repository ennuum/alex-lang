#!/bin/sh
# Backend natif (docs/NATIVE.md) : chaque programme est exécuté par la VM puis compilé en natif ;
# sortie standard, code de sortie, message d'erreur et trace de pile doivent être identiques.
# Lancer DEPUIS LA RACINE DU PROJET.
ALEX_BIN=${ALEX_BIN:-./alex}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
for src in tests/native/ok_*.al tests/native/err_*.al; do
    name=$(basename "$src" .al)
    ALEX_NO_TRACE=1 "$ALEX_BIN" run "$src" > "$TMP/vm.out" 2> "$TMP/vm.err"
    vm_rc=$?
    if ! "$ALEX_BIN" build --native "$src" -o "$TMP/$name" 2> "$TMP/build.err"; then
        echo "ÉCHEC $name : compilation native"; cat "$TMP/build.err"; fails=$((fails + 1)); continue
    fi
    "$TMP/$name" > "$TMP/nat.out" 2> "$TMP/nat.err"
    nat_rc=$?
    vm_last=$(grep -v '^-- terminé' "$TMP/vm.err" | tail -n 1)
    nat_last=$(tail -n 1 "$TMP/nat.err")
    # Programme en erreur : la trace de pile complète doit aussi être identique.
    trace_ok=1
    if [ "$vm_rc" -ne 0 ]; then
        "$ALEX_BIN" run "$src" > /dev/null 2> "$TMP/vm.trace"
        "$TMP/$name" > /dev/null 2> "$TMP/nat.trace"
        cmp -s "$TMP/vm.trace" "$TMP/nat.trace" || trace_ok=0
    fi
    if ! cmp -s "$TMP/vm.out" "$TMP/nat.out"; then
        echo "ÉCHEC $name : sortie standard différente"; diff "$TMP/vm.out" "$TMP/nat.out" | head -10; fails=$((fails + 1))
    elif [ "$vm_rc" -ne "$nat_rc" ]; then
        echo "ÉCHEC $name : code de sortie VM $vm_rc, natif $nat_rc"; fails=$((fails + 1))
    elif [ "$vm_last" != "$nat_last" ]; then
        echo "ÉCHEC $name : erreur différente"; echo "  VM    : $vm_last"; echo "  natif : $nat_last"; fails=$((fails + 1))
    elif [ "$trace_ok" -ne 1 ]; then
        echo "ÉCHEC $name : trace de pile différente"; diff "$TMP/vm.trace" "$TMP/nat.trace" | head -6; fails=$((fails + 1))
    else
        echo "ok    $name ($(wc -l < "$TMP/vm.out") lignes, code $nat_rc${nat_last:+, $nat_last})"
        # Même résultat avec une collecte toutes les 4 Kio allouées (détecte un objet libéré à tort).
        if [ "$name" != "ok_gc" ]; then
            ALEX_GC_STRESS=1 "$TMP/$name" > "$TMP/stress.out" 2> /dev/null
            if ! cmp -s "$TMP/vm.out" "$TMP/stress.out"; then
                echo "ÉCHEC $name : résultat différent sous ALEX_GC_STRESS=1"; fails=$((fails + 1))
            fi
        fi
    fi
done

# Modules propres au natif (tasks…) : sortie (standard puis erreur) et code de sortie attendus.
for src in tests/native/only/*.al; do
    name=$(basename "$src" .al)
    expected_rc=0
    [ -f "tests/native/only/${name}_rc.txt" ] && expected_rc=$(cat "tests/native/only/${name}_rc.txt")
    if ! "$ALEX_BIN" build --native "$src" -o "$TMP/$name" 2> "$TMP/build.err"; then
        echo "ÉCHEC $name : compilation native"; cat "$TMP/build.err"; fails=$((fails + 1)); continue
    fi
    "$TMP/$name" > "$TMP/only.out" 2>&1
    rc=$?
    ALEX_GC_STRESS=1 "$TMP/$name" > "$TMP/only_stress.out" 2>&1
    if ! cmp -s "tests/native/only/${name}_expected.txt" "$TMP/only.out" || [ "$rc" -ne "$expected_rc" ]; then
        echo "ÉCHEC $name (code $rc)"; diff "tests/native/only/${name}_expected.txt" "$TMP/only.out" | head -6; fails=$((fails + 1))
    elif ! cmp -s "$TMP/only.out" "$TMP/only_stress.out"; then
        echo "ÉCHEC $name : résultat différent sous ALEX_GC_STRESS=1"; fails=$((fails + 1))
    else
        echo "ok    $name (natif seulement)"
    fi
done

# Constructions refusées : diagnostics attendus, pas d'exécutable produit.
out=$("$ALEX_BIN" build --static tests/native/unsupported_fixture.al -o "$TMP/unsup" 2>&1 | sed "s|$(pwd)/||g")
if [ "$out" = "$(cat tests/native/unsupported_expected.txt)" ] && [ ! -e "$TMP/unsup" ]; then
    echo "ok    diagnostics du sous-ensemble natif"
else
    echo "ÉCHEC diagnostics du sous-ensemble natif"; echo "$out"; fails=$((fails + 1))
fi

if [ "$fails" -ne 0 ]; then echo "test-native : $fails échec(s)"; exit 1; fi
echo "test-native : toutes les vérifications passent"
