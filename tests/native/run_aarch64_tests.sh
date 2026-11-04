#!/bin/sh
# Backend natif AArch64 (docs/NATIVE.md, « ARM64 ») : les mêmes programmes que run_native_tests.sh, compilés
# avec --target linux-aarch64 et exécutés par l'émulateur AArch64 écrit en ALEX (tests/native/aarch64/a64run.al,
# compilé en x86-64 natif) ou par A64RUN (par exemple qemu-aarch64, ou "" sur une vraie machine ARM64) ; sortie,
# code de sortie, erreur et trace de pile doivent être ceux de la VM. Vérifie aussi l'assembleur AArch64
# (tests/native/aarch64/test_asm.al, encodages de référence). Lancer DEPUIS LA RACINE DU PROJET.
ALEX_BIN=${ALEX_BIN:-./alex}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
if [ -z "${A64RUN+x}" ]; then
    "$ALEX_BIN" build --native --static --image-base 0x10000000 tests/native/aarch64/a64run.al -o "$TMP/a64run" > /dev/null || exit 1
    A64RUN="$TMP/a64run"
fi

# Assembleur : chaque instruction comparée à son encodage de référence.
if "$ALEX_BIN" run tests/native/aarch64/test_asm.al > "$TMP/asm.txt" 2>&1; then grep '^ok' "$TMP/asm.txt"
else echo "ÉCHEC assembleur AArch64"; grep -v '^-- terminé' "$TMP/asm.txt" | head; fails=$((fails + 1)); fi

run() { if [ -n "$A64RUN" ]; then "$A64RUN" "$@"; else "$@"; fi; }

for src in tests/native/ok_*.al tests/native/err_*.al; do
    name=$(basename "$src" .al)
    ALEX_NO_TRACE=1 "$ALEX_BIN" run "$src" > "$TMP/vm.out" 2> "$TMP/vm.err"
    vm_rc=$?
    if ! "$ALEX_BIN" build --native --target linux-aarch64 "$src" -o "$TMP/$name" > /dev/null 2> "$TMP/build.err"; then
        echo "ÉCHEC $name : compilation AArch64"; cat "$TMP/build.err"; fails=$((fails + 1)); continue
    fi
    # os.arch() vaut "aarch64" pour cette cible : la sortie attendue est celle de la VM, architecture remplacée.
    [ "$name" = ok_io_os ] && sed -i "s/^$(uname -m)\$/aarch64/" "$TMP/vm.out"
    run "$TMP/$name" > "$TMP/nat.out" 2> "$TMP/nat.err"
    nat_rc=$?
    vm_last=$(grep -v '^-- terminé' "$TMP/vm.err" | tail -n 1)
    nat_last=$(tail -n 1 "$TMP/nat.err")
    trace_ok=1
    if [ "$vm_rc" -ne 0 ]; then
        "$ALEX_BIN" run "$src" > /dev/null 2> "$TMP/vm.trace"
        run "$TMP/$name" > /dev/null 2> "$TMP/nat.trace"
        cmp -s "$TMP/vm.trace" "$TMP/nat.trace" || trace_ok=0
    fi
    if ! cmp -s "$TMP/vm.out" "$TMP/nat.out"; then
        echo "ÉCHEC $name : sortie standard différente"; diff "$TMP/vm.out" "$TMP/nat.out" | head -10; fails=$((fails + 1))
    elif [ "$vm_rc" -ne "$nat_rc" ]; then
        echo "ÉCHEC $name : code de sortie VM $vm_rc, AArch64 $nat_rc"; tail -3 "$TMP/nat.err"; fails=$((fails + 1))
    elif [ "$vm_last" != "$nat_last" ]; then
        echo "ÉCHEC $name : erreur différente"; echo "  VM      : $vm_last"; echo "  AArch64 : $nat_last"; fails=$((fails + 1))
    elif [ "$trace_ok" -ne 1 ]; then
        echo "ÉCHEC $name : trace de pile différente"; diff "$TMP/vm.trace" "$TMP/nat.trace" | head -6; fails=$((fails + 1))
    else
        echo "ok    $name ($(wc -l < "$TMP/vm.out") lignes, code $nat_rc${nat_last:+, $nat_last})"
        # err_recursion : 100 000 cadres parcourus à chaque collecte, plus d'une heure sous émulation (vérifié par test-native).
        if [ "$name" != "ok_gc" ] && [ "$name" != "err_recursion" ]; then
            ALEX_GC_STRESS=1 run "$TMP/$name" > "$TMP/stress.out" 2> /dev/null
            if ! cmp -s "$TMP/vm.out" "$TMP/stress.out"; then
                echo "ÉCHEC $name : résultat différent sous ALEX_GC_STRESS=1"; fails=$((fails + 1))
            fi
        fi
    fi
done

for src in tests/native/only/*.al; do
    name=$(basename "$src" .al)
    expected_rc=0
    [ -f "tests/native/only/${name}_rc.txt" ] && expected_rc=$(cat "tests/native/only/${name}_rc.txt")
    if ! "$ALEX_BIN" build --native --target linux-aarch64 "$src" -o "$TMP/$name" > /dev/null 2> "$TMP/build.err"; then
        echo "ÉCHEC $name : compilation AArch64"; cat "$TMP/build.err"; fails=$((fails + 1)); continue
    fi
    run "$TMP/$name" > "$TMP/only.out" 2>&1
    rc=$?
    ALEX_GC_STRESS=1 run "$TMP/$name" > "$TMP/only_stress.out" 2>&1
    if ! cmp -s "tests/native/only/${name}_expected.txt" "$TMP/only.out" || [ "$rc" -ne "$expected_rc" ]; then
        echo "ÉCHEC $name (code $rc)"; diff "tests/native/only/${name}_expected.txt" "$TMP/only.out" | head -6; fails=$((fails + 1))
    elif ! cmp -s "$TMP/only.out" "$TMP/only_stress.out"; then
        echo "ÉCHEC $name : résultat différent sous ALEX_GC_STRESS=1"; fails=$((fails + 1))
    else
        echo "ok    $name (natif seulement)"
    fi
done

if [ "$fails" -ne 0 ]; then echo "test-native-aarch64 : $fails échec(s)"; exit 1; fi
echo "test-native-aarch64 : toutes les vérifications passent"
