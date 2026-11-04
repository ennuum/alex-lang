#!/bin/sh
# Modules de pilotes ajoutés (sous-ensemble natif) : chaque tests/stdlib2/native/k*.al est
#   1. compilé avec --native --freestanding (image multiboot du noyau Alex : vérifie que tout le code
#      des modules utilisés appartient au sous-ensemble natif) ;
#   2. compilé avec --native pour l'hôte, exécuté, et sa sortie comparée à celle de la VM (alex run),
#      sauf kpci (accès PCI réels par ports : VM seulement).
# Lancer DEPUIS LA RACINE DU PROJET.
ALEX_BIN=${ALEX_BIN:-./alex}
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
fails=0
for src in tests/stdlib2/native/k*.al; do
    name=$(basename "$src" .al)
    if ! "$ALEX_BIN" build --native --freestanding "$src" -o "$DIR/$name.bin" > /dev/null 2> "$DIR/err"; then
        echo "ÉCHEC $name : compilation --freestanding"; cat "$DIR/err"; fails=$((fails + 1)); continue
    fi
    if [ "$name" = "kpci" ]; then
        echo "ok    $name (freestanding)"; continue
    fi
    if ! "$ALEX_BIN" build --native "$src" -o "$DIR/$name.exe" > /dev/null 2> "$DIR/err"; then
        echo "ÉCHEC $name : compilation --native"; cat "$DIR/err"; fails=$((fails + 1)); continue
    fi
    "$DIR/$name.exe" 2>&1 | grep -v -- '-- terminé' > "$DIR/$name.native.txt"
    "$ALEX_BIN" run "$src" 2>&1 | grep -v -- '-- terminé' > "$DIR/$name.vm.txt"
    if cmp -s "$DIR/$name.native.txt" "$DIR/$name.vm.txt"; then
        echo "ok    $name (freestanding, natif = VM, $(wc -l < "$DIR/$name.vm.txt") lignes)"
    else
        echo "ÉCHEC $name : sortie native différente de la VM"; diff "$DIR/$name.native.txt" "$DIR/$name.vm.txt" | head -10
        fails=$((fails + 1))
    fi
done
[ $fails -eq 0 ]
