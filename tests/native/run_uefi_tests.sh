#!/bin/sh
# Cible UEFI du backend natif (alexc build --native --uefi, docs/NATIVE.md « UEFI »). Lancer DEPUIS LA RACINE.
#
# Les applications UEFI (PE32+, sous-système 10) sont construites et leur contrat binaire vérifié
# (tests/native/pe_check.al) ; elles sont exécutées si EFIRUN désigne un lanceur (par exemple un script QEMU + OVMF, ou un chargeur
# de test qui fournit une table système UEFI minimale et le port série COM1) :
#
#   1. tests/native/ok_*.al et err_*.al acceptés en UEFI (sans io ni os) : sortie série identique à la sortie
#      standard de la VM suivie de sa trace d'erreur, même code de sortie (statut EFI d'erreur) ;
#   2. tas réduit (EFIRUN_MAX_PAGES=4096 : AllocatePages refuse 64 Mio, le runtime se contente de 16 Mio) ;
#   limites de la cible : ok_async (pile de 256 Kio par tâche sur le tas de 64 Mio) : sortie de la VM ou
#   MemoryError ; err_recursion (100 000 cadres) déborde la pile de 4 Mio du bss et n'est pas exécuté ;
#   3. tests/native/uefi/efi_*.al : services du micrologiciel (hw.efi_call), code de sortie ;
#   4. refus : io / os, mode dynamique impossible.
ALEX_BIN=${ALEX_BIN:-./alex}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
EXEC=1
if [ -z "${EFIRUN:-}" ]; then
    EXEC=0
    echo "--    exécution sautée (EFIRUN non défini) : construction et structure des applications seulement"
fi
"$ALEX_BIN" build --native tests/native/pe_check.al -o "$TMP/pe_check" > /dev/null 2>&1 || { echo "ÉCHEC construction de pe_check"; exit 1; }
n=0
for src in tests/native/ok_*.al tests/native/err_*.al; do
    name=$(basename "$src" .al)
    if ! "$ALEX_BIN" build --native --uefi "$src" -o "$TMP/$name.efi" > /dev/null 2> "$TMP/build.err"; then
        continue # hors du sous-ensemble UEFI (io, os...) : refus vérifié par le banc du compilateur
    fi
    n=$((n + 1))
    if [ $EXEC -eq 0 ]; then
        if ! "$TMP/pe_check" "$TMP/$name.efi" uefi > "$TMP/pe.txt"; then
            echo "ÉCHEC $name : $(cat "$TMP/pe.txt")"; fails=$((fails + 1))
        else
            echo "ok    $name (construit, $(head -1 "$TMP/pe.txt" | cut -c7-))"
        fi
        continue
    fi
    if [ "$name" = "err_recursion" ]; then echo "--    $name : non exécuté (pile UEFI de 4 Mio)"; continue; fi
    if [ "$name" = "ok_async" ]; then
        $EFIRUN "$TMP/$name.efi" > "$TMP/efi.out" 2>&1
        rc=$?
        "$ALEX_BIN" run "$src" > "$TMP/vm.out" 2> "$TMP/vm.err"
        grep -v '^-- terminé' "$TMP/vm.err" >> "$TMP/vm.out"
        if [ "$rc" -eq 0 ] && cmp -s "$TMP/vm.out" "$TMP/efi.out"; then
            echo "ok    $name (tas suffisant)"
        elif [ "$rc" -eq 1 ] && [ "$(tail -n 1 "$TMP/efi.out")" = "MemoryError: mémoire épuisée" ]; then
            echo "ok    $name : MemoryError (tas UEFI de 64 Mio)"
        else
            echo "ÉCHEC $name : ni la sortie de la VM ni MemoryError (code $rc)"; tail -3 "$TMP/efi.out"; fails=$((fails + 1))
        fi
        continue
    fi
    "$ALEX_BIN" run "$src" > "$TMP/vm.out" 2> "$TMP/vm.err"
    vm_rc=$?
    grep -v '^-- terminé' "$TMP/vm.err" >> "$TMP/vm.out"
    $EFIRUN "$TMP/$name.efi" > "$TMP/efi.out" 2> "$TMP/efi.err"
    efi_rc=$?
    if ! cmp -s "$TMP/vm.out" "$TMP/efi.out"; then
        echo "ÉCHEC $name : sortie série différente"; diff "$TMP/vm.out" "$TMP/efi.out" | head -8; cat "$TMP/efi.err"; fails=$((fails + 1))
    elif [ "$vm_rc" -ne "$efi_rc" ]; then
        echo "ÉCHEC $name : code de sortie VM $vm_rc, UEFI $efi_rc"; cat "$TMP/efi.err"; fails=$((fails + 1))
    else
        echo "ok    $name ($(wc -l < "$TMP/efi.out") lignes, code $efi_rc)"
    fi
done
[ "$n" -ge 20 ] || { echo "ÉCHEC : seulement $n programmes acceptés en UEFI"; fails=$((fails + 1)); }

# Tas réduit : 64 Mio refusés par le micrologiciel, 16 Mio acceptés.
if [ -f "$TMP/ok_arith.efi" ] && [ $EXEC -eq 1 ]; then
    "$ALEX_BIN" run tests/native/ok_arith.al > "$TMP/gc.vm" 2> /dev/null
    EFIRUN_MAX_PAGES=4096 $EFIRUN "$TMP/ok_arith.efi" > "$TMP/gc.out" 2>&1
    if cmp -s "$TMP/gc.vm" "$TMP/gc.out"; then echo "ok    tas de 16 Mio (AllocatePages refuse 64 Mio)"; else
        echo "ÉCHEC tas réduit"; diff "$TMP/gc.vm" "$TMP/gc.out" | head -5; fails=$((fails + 1)); fi
fi

for src in tests/native/uefi/efi_*.al; do
    name=$(basename "$src" .al)
    if "$ALEX_BIN" build --native --uefi "$src" -o "$TMP/$name.efi" > /dev/null 2> "$TMP/build.err"; then
        if ! "$TMP/pe_check" "$TMP/$name.efi" uefi > "$TMP/pe.txt"; then
            echo "ÉCHEC $name : $(cat "$TMP/pe.txt")"; fails=$((fails + 1)); continue
        fi
        if [ $EXEC -eq 0 ]; then echo "ok    $name (construit, $(head -1 "$TMP/pe.txt" | cut -c7-))"; continue; fi
        $EFIRUN "$TMP/$name.efi" > "$TMP/$name.out" 2>&1
        rc=$?
        if [ "$rc" -eq 3 ] && cmp -s "tests/native/uefi/${name}_expected.txt" "$TMP/$name.out"; then
            echo "ok    $name (services UEFI, code 3)"
        else
            echo "ÉCHEC $name (code $rc)"; diff "tests/native/uefi/${name}_expected.txt" "$TMP/$name.out"; fails=$((fails + 1))
        fi
    else
        echo "ÉCHEC $name : compilation"; cat "$TMP/build.err"; fails=$((fails + 1))
    fi
done

out=$("$ALEX_BIN" build --native --uefi tests/native/ok_io_os.al -o "$TMP/io.efi" 2>&1)
if echo "$out" | grep -q "indisponible avec --freestanding" && [ ! -e "$TMP/io.efi" ]; then echo "ok    refus de io / os"; else
    echo "ÉCHEC refus de io / os"; echo "$out"; fails=$((fails + 1)); fi

if [ "$fails" -ne 0 ]; then echo "test-native-uefi : $fails échec(s)"; exit 1; fi
echo "test-native-uefi : toutes les vérifications passent"
