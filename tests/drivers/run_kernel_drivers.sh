#!/bin/sh
# Pilotes sous QEMU : chaque tests/drivers/kernel/k_*.al est compilé avec --freestanding, démarré sous QEMU
# (options de k_*_qemu.txt, où $DIR désigne un dossier temporaire préparé par k_*_disk.sh) et sa sortie série
# comparée à k_*_expected.txt. Ignoré si qemu-system-x86_64 est absent. Lancer DEPUIS LA RACINE DU PROJET.
ALEX_BIN=${ALEX_BIN:-./alex}
QEMU=${QEMU:-qemu-system-x86_64}
if ! command -v "$QEMU" > /dev/null 2>&1; then
    echo "test-drivers-kernel : $QEMU absent, ignoré"
    exit 0
fi
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
fails=0
for src in tests/drivers/kernel/k_*.al; do
    name=$(basename "$src" .al)
    base="tests/drivers/kernel/$name"
    if ! "$ALEX_BIN" build --native --freestanding "$src" -o "$DIR/$name.bin" > /dev/null 2> "$DIR/build.err"; then
        echo "ÉCHEC $name : compilation --freestanding"; cat "$DIR/build.err"; fails=$((fails + 1)); continue
    fi
    [ -f "${base}_disk.sh" ] && sh "${base}_disk.sh" "$DIR"
    extra=""
    peer=""
    if [ -f "${base}_peer.txt" ]; then # pair réseau (passerelle simulée) relié par -netdev dgram
        if ! command -v python3 > /dev/null 2>&1; then echo "--    $name : python3 absent, ignoré"; continue; fi
        python3 tests/drivers/kernel/netpeer.py $(cat "${base}_peer.txt") 2> /dev/null &
        peer=$!
        sleep 0.5
    fi
    [ -f "${base}_qemu.txt" ] && extra=$(sed "s#\$DIR#$DIR#g" "${base}_qemu.txt")
    keys=""
    if [ -f "${base}_keys.txt" ]; then # frappes envoyées par le moniteur de QEMU après le démarrage
        if ! command -v python3 > /dev/null 2>&1; then echo "--    $name : python3 absent, ignoré"; continue; fi
        rm -f "$DIR/mon.sock"
        extra="$extra -monitor unix:$DIR/mon.sock,server,nowait"
        python3 tests/drivers/kernel/monkeys.py "$DIR/mon.sock" "${base}_keys.txt" 2 2> /dev/null &
        keys=$!
    else
        extra="$extra -monitor none"
    fi
    timeout 180 "$QEMU" -kernel "$DIR/$name.bin" -display none -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -serial stdio $extra < /dev/null > "$DIR/serial.out" 2> /dev/null
    rc=$?
    [ -n "$peer" ] && kill "$peer" 2> /dev/null
    [ -n "$keys" ] && kill "$keys" 2> /dev/null
    # La révision du micrologiciel NVMe rapportée par QEMU dépend de la version de QEMU (p. ex. « 8.2.2 »
    # ou « 9.2.0 ») : on la neutralise des deux côtés pour que le test reste portable entre versions.
    norm='s/micrologiciel [0-9][0-9A-Za-z.+_-]*/micrologiciel <version>/g'
    sed "$norm" "${base}_expected.txt" > "$DIR/exp.norm"
    sed "$norm" "$DIR/serial.out" > "$DIR/out.norm"
    if ! cmp -s "$DIR/exp.norm" "$DIR/out.norm"; then
        echo "ÉCHEC $name : sortie différente"; diff "$DIR/exp.norm" "$DIR/out.norm" | head -10; fails=$((fails + 1))
    elif [ "$rc" -ne 1 ]; then
        echo "ÉCHEC $name : code de sortie QEMU $rc"; fails=$((fails + 1))
    else
        echo "ok    $name (QEMU)"
    fi
done
[ "$fails" -eq 0 ] || exit 1
