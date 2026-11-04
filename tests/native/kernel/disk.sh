#!/bin/sh
# Image de disque FAT16 de test (16 Mio) : HELLO.TXT et les programmes de examples/noyau/programmes compilés
# avec `alexc build --native` (exécutables Linux ordinaires). usage : disk.sh image [alex]
set -e
img=$1
ALEX_BIN=${2:-./alex}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rm -f "$img"
mkfs.fat -F 16 -C "$img" 16384 > /dev/null
printf 'Bonjour depuis le disque !\n' > "$tmp/hello.txt"
mcopy -i "$img" "$tmp/hello.txt" ::/HELLO.TXT
for p in examples/noyau/programmes/*.al; do
    n=$(basename "$p" .al | tr a-z A-Z)
    "$ALEX_BIN" build --native "$p" -o "$tmp/$n.ELF" 2> /dev/null
    mcopy -i "$img" "$tmp/$n.ELF" "::/$n.ELF"
done
