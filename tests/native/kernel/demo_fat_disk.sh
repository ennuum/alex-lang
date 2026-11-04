#!/bin/sh
# Disque de demo_fat : celui des autres tests (disk.sh), plus une arborescence créée par mtools avec des noms
# longs (espaces, apostrophe, accents en UTF-8) et un répertoire de 40 fichiers (deux grappes d'entrées).
# usage : demo_fat_disk.sh image [alex]
set -e
img=$1
sh tests/native/kernel/disk.sh "$img" "${2:-./alex}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C.UTF-8
printf 'Lisez-moi : ce disque a été préparé par mtools.\n' > "$tmp/a.txt"
printf 'Chiffre d affaires 2026 : en hausse.\n' > "$tmp/b.txt"
mmd -i "$img" "::/Documents" "::/Documents/Rapports annuels" "::/Documents/Archive"
mcopy -i "$img" "$tmp/a.txt" "::/Documents/Lisez-moi d'abord.txt"
mcopy -i "$img" "$tmp/b.txt" "::/Documents/Rapports annuels/Résumé 2026.txt"
i=1
while [ $i -le 40 ]; do
    n=$(printf '%02d' $i)
    printf 'fichier %s\n' "$n" > "$tmp/f.txt"
    mcopy -i "$img" "$tmp/f.txt" "::/Documents/Archive/fichier numéro $n.txt"
    i=$((i + 1))
done
