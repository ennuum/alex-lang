#!/bin/sh
# Mode --freestanding (docs/NATIVE.md, « Sans OS ») : chaque programme de tests/native est compilé en image
# Multiboot et démarré sous QEMU ; la sortie du port série doit être celle de la VM (sortie standard, puis
# trace et message d'erreur), le code de sortie 2 * code + 1 (périphérique isa-debug-exit). Puis les
# programmes propres au matériel (tests/native/kernel, sorties attendues) et l'exemple de noyau.
# Ignoré si qemu-system-x86_64 est absent. Lancer DEPUIS LA RACINE DU PROJET.
ALEX_BIN=${ALEX_BIN:-./alex}
QEMU=${QEMU:-qemu-system-x86_64}
if ! command -v "$QEMU" > /dev/null 2>&1; then
    echo "test-kernel : $QEMU absent, ignoré"
    exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
boot() {
    image=$1
    shift
    timeout 120 "$QEMU" -kernel "$image" -display none -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -serial stdio -monitor none "$@" 2> /dev/null
}
for src in tests/native/ok_*.al tests/native/err_*.al; do
    name=$(basename "$src" .al)
    [ "$name" = "ok_io_os" ] && continue # appels système : sans objet sans OS
    "$ALEX_BIN" run "$src" > "$TMP/vm.out" 2> "$TMP/vm.err"
    vm_rc=$?
    grep -v '^-- terminé' "$TMP/vm.err" >> "$TMP/vm.out" # erreurs et avertissements : même port série
    if ! "$ALEX_BIN" build --native --freestanding "$src" -o "$TMP/$name.bin" 2> "$TMP/build.err"; then
        echo "ÉCHEC $name : compilation --freestanding"; cat "$TMP/build.err"; fails=$((fails + 1)); continue
    fi
    boot "$TMP/$name.bin" < /dev/null > "$TMP/serial.out"
    rc=$?
    if ! cmp -s "$TMP/vm.out" "$TMP/serial.out"; then
        echo "ÉCHEC $name : sortie série différente de la VM"; diff "$TMP/vm.out" "$TMP/serial.out" | head -6; fails=$((fails + 1))
    elif [ "$rc" -ne $((2 * vm_rc + 1)) ]; then
        echo "ÉCHEC $name : code de sortie QEMU $rc (attendu $((2 * vm_rc + 1)))"; fails=$((fails + 1))
    else
        echo "ok    $name (sans OS)"
    fi
done
for src in tests/native/kernel/*.al examples/noyau/noyau.al examples/noyau/shell.al examples/noyau/demo_processus.al \
    examples/noyau/demo_smp.al examples/noyau/demo_multi.al examples/noyau/demo_virtio.al examples/noyau/demo_fat.al; do
    name=$(basename "$src" .al)
    expected="tests/native/kernel/${name}_expected.txt"
    if ! "$ALEX_BIN" build --native --freestanding "$src" -o "$TMP/$name.bin" 2> "$TMP/build.err"; then
        echo "ÉCHEC $name : compilation --freestanding"; cat "$TMP/build.err"; fails=$((fails + 1)); continue
    fi
    input="tests/native/kernel/${name}_input.txt"
    keys="tests/native/kernel/${name}_keys.txt"
    expected_rc=1
    [ -f "tests/native/kernel/${name}_rc.txt" ] && expected_rc=$(cat "tests/native/kernel/${name}_rc.txt")
    extra="" # options de QEMU propres au test (-smp 4...)
    [ -f "tests/native/kernel/${name}_qemu.txt" ] && extra=$(cat "tests/native/kernel/${name}_qemu.txt")
    disk=""
    if [ -f "tests/native/kernel/${name}_disk" ]; then # disque FAT16 neuf (programmes de examples/noyau/programmes)
        if ! command -v mkfs.fat > /dev/null 2>&1 || ! command -v mcopy > /dev/null 2>&1; then
            echo "--    $name : mkfs.fat / mcopy (dosfstools, mtools) absents, ignoré"; continue
        fi
        disk="$TMP/$name.img"
        if [ -f "tests/native/kernel/${name}_disk.sh" ]; then # disque propre au test
            sh "tests/native/kernel/${name}_disk.sh" "$disk" "$ALEX_BIN"
        else
            sh tests/native/kernel/disk.sh "$disk" "$ALEX_BIN"
        fi
    fi
    drive="-drive file=$disk,format=raw,if=ide,index=0"
    if [ -f "tests/native/kernel/${name}_virtio" ]; then # même disque, branché en virtio-blk
        drive="-drive file=$disk,format=raw,if=none,id=vd0 -device virtio-blk-pci,drive=vd0"
    fi
    if [ -f "$keys" ]; then # frappes au clavier PS/2 par le moniteur de QEMU
        if ! command -v python3 > /dev/null 2>&1; then echo "--    $name : python3 absent, ignoré"; continue; fi
        QEMU="$QEMU" python3 tests/native/kernel/sendkeys.py "$TMP/$name.bin" "$keys" $disk > "$TMP/serial.out" 2> /dev/null
    elif [ -n "$disk" ]; then
        boot "$TMP/$name.bin" -m 256M $drive $extra < /dev/null > "$TMP/serial.out"
    elif [ -f "$input" ]; then # entrée série envoyée après le démarrage (le micrologiciel lit les premiers octets)
        (sleep 2; cat "$input") | boot "$TMP/$name.bin" $extra > "$TMP/serial.out"
    else
        boot "$TMP/$name.bin" $extra < /dev/null > "$TMP/serial.out"
    fi
    rc=$?
    if [ -n "$disk" ] && [ -f "tests/native/kernel/${name}_after.sh" ]; then # le disque vu par l'hôte ensuite
        sh "tests/native/kernel/${name}_after.sh" "$disk" >> "$TMP/serial.out" 2>&1
    fi
    if ! cmp -s "$expected" "$TMP/serial.out" || [ "$rc" -ne "$expected_rc" ]; then
        echo "ÉCHEC $name (code $rc)"; diff "$expected" "$TMP/serial.out" | head -6; fails=$((fails + 1))
    else
        echo "ok    $name (matériel)"
    fi
done
# Le même scénario au clavier, disque branché en virtio-blk (bloc.al choisit le pilote virtio).
if command -v mkfs.fat > /dev/null 2>&1 && command -v mcopy > /dev/null 2>&1 && command -v python3 > /dev/null 2>&1 \
    && [ -f "$TMP/shell.bin" ]; then
    sh tests/native/kernel/disk.sh "$TMP/shell_virtio.img" "$ALEX_BIN"
    ALEX_VIRTIO=1 QEMU="$QEMU" python3 tests/native/kernel/sendkeys.py "$TMP/shell.bin" tests/native/kernel/shell_keys.txt \
        "$TMP/shell_virtio.img" > "$TMP/serial.out" 2> /dev/null
    rc=$?
    if ! cmp -s tests/native/kernel/shell_virtio_expected.txt "$TMP/serial.out" || [ "$rc" -ne 1 ]; then
        echo "ÉCHEC shell sur virtio-blk (code $rc)"; diff tests/native/kernel/shell_virtio_expected.txt "$TMP/serial.out" | head -6
        fails=$((fails + 1))
    else
        echo "ok    shell sur virtio-blk (matériel)"
    fi
fi
# Modules réservés à un mode : messages attendus.
printf 'use hw\nhw.hlt()\n' > "$TMP/hosted_hw.al"
out=$("$ALEX_BIN" build --native "$TMP/hosted_hw.al" -o "$TMP/x" 2>&1)
case "$out" in *"réservé à --freestanding"*) echo "ok    hw refusé hors --freestanding" ;; *) echo "ÉCHEC hw hors --freestanding : $out"; fails=$((fails + 1)) ;; esac
printf 'use os\nprint(os.pid())\n' > "$TMP/fs_os.al"
out=$("$ALEX_BIN" build --native --freestanding "$TMP/fs_os.al" -o "$TMP/x" 2>&1)
case "$out" in *"indisponible avec --freestanding"*) echo "ok    os refusé avec --freestanding" ;; *) echo "ÉCHEC os avec --freestanding : $out"; fails=$((fails + 1)) ;; esac
if [ "$fails" -ne 0 ]; then echo "test-kernel : $fails échec(s)"; exit 1; fi
echo "test-kernel : toutes les vérifications passent"
