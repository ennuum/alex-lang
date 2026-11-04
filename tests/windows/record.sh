#!/bin/sh
# Références de la suite Windows (tests/windows/suite.al), enregistrées sous Linux par la chaîne ALEX :
#   expected/<nom>.out / .err / .rc   sortie standard, sortie d'erreur (sans la ligne « -- terminé ») et code de
#                                     sortie de la VM (`alex run`), plateforme neutralisée pour ok_io_os ;
#   expected/<nom>.exe.sha256         empreinte de l'exécutable `alexc build --native --windows` produit SOUS LINUX :
#                                     le même compilateur sous Windows doit produire le même fichier, octet pour octet.
#   sh tests/windows/record.sh [./alex]      (depuis la racine du projet)
set -u
cd "$(dirname "$0")/../.."
A=${1:-./alex}
E=tests/windows/expected
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
rm -rf "$E" && mkdir -p "$E"
for src in tests/native/ok_*.al tests/native/err_*.al tests/native/only/ok_tasks.al tests/native/only/err_tasks.al; do
    n=$(basename "$src" .al)
    ALEX_NO_TRACE=1 "$A" run "$src" > "$E/$n.out" 2> "$T/err"
    echo $? > "$E/$n.rc"
    grep -v '^-- terminé' "$T/err" > "$E/$n.err"
    if [ "$n" = ok_io_os ]; then
        sed -e '/^Linux$/{N;s/^Linux\nlinux$/Windows\nwindows/}' "$E/$n.out" > "$T/fix" && cp "$T/fix" "$E/$n.out"
    fi
    if "$A" build --native --windows "$src" -o "$T/$n.exe" > /dev/null 2>&1; then
        sha256sum "$T/$n.exe" | cut -c1-64 > "$E/$n.exe.sha256"
    fi
done
echo "références : $(ls "$E" | wc -l) fichiers dans $E"
