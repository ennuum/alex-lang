#!/usr/bin/env bash
# Amorçage de la chaîne ALEX pure (étapes B et D, docs/SELFHOST.md), SANS compilateur C++ :
#   0. graine versionnée : bootstrap/alexvm (VM écrite en ALEX, exécutable) et bootstrap/alexc.albc (compilateur
#      écrit en ALEX, bytecode) ;
#   1. la graine compile le compilateur en natif                        -> build/alexc-stage1
#   2. build/alexc-stage1 se recompile                                   -> build/alexc
#   3. build/alexc construit la VM                                       -> build/alexvm
#   4. contrôle : build/alexc se recompile à l'identique (point fixe), la VM reconstruite est identique ;
#      stage1 == stage2 si la graine est à jour.
#
#   tools/selfhost/bootstrap.sh            (make pure ; aussi le premier make alex)
#   tools/selfhost/bootstrap.sh --seed     régénère la graine depuis build/ (après une évolution du compilateur)
# La chaîne finale (build/alex, avec son numéro de version) est ensuite construite par build/alexc : make alex.
set -eu
cd "$(dirname "$0")/../.."
REPO=$(pwd)
mkdir -p build
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
if [ "${1:-}" = "--seed" ]; then
    C=build/alex
    [ -x "$C" ] || C=build/alexc
    [ -x build/alexvm ] && [ -x "$C" ] || { echo "build/alexvm et build/alex requis (make alex)"; exit 1; }
    mkdir -p bootstrap
    cp build/alexvm bootstrap/alexvm
    ALEX_VM="$REPO/build/alexvm" "$C" build src/alexc.al -o bootstrap/alexc.albc > /dev/null 2>&1
    ls -l bootstrap/alexvm bootstrap/alexc.albc | awk '{print "     " $9 " : " $5 " octets"}'
    exit 0
fi
[ -x bootstrap/alexvm ] && [ -f bootstrap/alexc.albc ] || { echo "graine absente : bootstrap/alexvm, bootstrap/alexc.albc"; exit 1; }
t0=$(date +%s)
# chemin de la chaîne d'outils embarqué dans les exécutables dynamiques (ALEX_EXE) : alexc, à tous les étages
export ALEX_EXE="$REPO/build/alexc"
echo "1/4 graine (VM ALEX + compilateur en bytecode) -> build/alexc-stage1"
ALEX_QUIET_RUN=1 bootstrap/alexvm bootstrap/alexc.albc native --dynamic src/alexc.al -o build/alexc-stage1 > /dev/null
echo "2/4 build/alexc-stage1 -> build/alexc"
# ALEX_EXE (embarqué dans les exécutables) doit désigner un fichier existant à chaque étage
[ -x build/alexc ] || cp build/alexc-stage1 build/alexc
build/alexc-stage1 native --dynamic src/alexc.al -o build/alexc > /dev/null
echo "3/4 build/alexc -> build/alexvm"
build/alexc vm -o build/alexvm > /dev/null
echo "4/4 point fixe"
build/alexc native --dynamic src/alexc.al -o "$W/alexc-stage3" > /dev/null
build/alexc vm -o "$W/alexvm2" > /dev/null
ok=0
cmp -s build/alexc "$W/alexc-stage3" && echo "OK   point fixe du compilateur : stage2 == stage3" || { echo "ÉCHEC point fixe du compilateur"; ok=1; }
cmp -s build/alexc-stage1 build/alexc && echo "OK   graine à jour : stage1 == stage2" || echo "     graine plus ancienne que les sources (stage1 != stage2) : tools/selfhost/bootstrap.sh --seed"
cmp -s build/alexvm "$W/alexvm2" && echo "OK   VM reconstruite identique" || { echo "ÉCHEC VM non reproductible"; ok=1; }
ls -l build/alexc build/alexvm | awk '{print "     " $9 " : " $5 " octets"}'
echo "     $(( $(date +%s) - t0 )) s, aucun compilateur C++ utilisé"
exit $ok
