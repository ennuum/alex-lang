#!/usr/bin/env bash
# Sorties du compilateur comparées à une table de référence (tests/selfhost/golden.tsv) : empreinte SHA-256 de
# chaque bytecode et de chaque exécutable produit, ou première ligne du diagnostic quand le programme est refusé.
# La table a été enregistrée avec le compilateur de référence (C++) avant son retrait ; le compilateur ALEX doit
# la reproduire octet pour octet. Le producteur inscrit dans un .albc (version du compilateur) est neutralisé.
#
#   tests/selfhost/golden.sh [--quick] [./alex]          vérifie (make test-golden ; --quick : make test-selfhost)
#   tests/selfhost/golden.sh --record BINAIRE [modes]    réenregistre (évolution voulue du compilateur)
#   (COMPILE1=outil : bc1 / bcq produits par un outil « outil fichier.al sortie.albc [--qualifier Q --source S] »,
#    comme l'alex-compile1 du compilateur de référence qui a servi à enregistrer la table)
#
# Modes : bc (programme complet), bc1 (fichier seul), bcq (module qualifié), x64 (Linux, statique), win (Windows
# x64), gui (Windows graphique), uefi, fs (sans OS, multiboot), a64 (Linux ARM64), wa64 (Windows ARM64).
set -u
cd "$(dirname "$0")/../.."
REPO=$(pwd)
TABLE="$REPO/tests/selfhost/golden.tsv"
RECORD=0; QUICK=0
while [ $# -gt 0 ]; do
    case "$1" in
        --record) RECORD=1; shift ;;
        --quick) QUICK=1; shift ;;
        *) break ;;
    esac
done
E=${1:-./alex}
[ $# -gt 0 ] && shift
case "$E" in /*) ;; *) E="$REPO/$E" ;; esac
MODES=${*:-bc bc1 bcq x64 win gui uefi fs a64 wa64}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

files() {
    if [ $QUICK -eq 1 ]; then
        ls tests/selfhost/progs/*.al examples/comprehensions.al examples/functional_demo.al stdlib/json/json.al \
           tests/native/ok_enums.al tests/native/ok_closures.al tests/native/ok_exceptions.al tests/native/ok_dict.al \
           tests/native/ok_generic.al tests/native/ok_async.al tests/native/ok_inherit.al tests/native/err_index.al \
           tests/native/windows/win_os.al tests/native/windows/win_posix.al examples/windows/calculatrice.al \
           tests/native/uefi/efi_conout.al tests/native/ok_io_os.al examples/noyau/noyau.al tests/native/kernel/k_irq.al \
           tests/selfhost/bad/*.al
    else
        ls examples/*.al examples/windows/*.al examples/noyau/*.al tests/*.al tests/*/*.al tests/*/*/*.al 2>/dev/null
    fi
}

# empreinte d'un .albc, producteur neutralisé (section PRODUCER : « alex <version> »)
hash_albc() {
    python3 -c '
import hashlib, re, sys
b = open(sys.argv[1], "rb").read()
b = re.sub(rb"[\x00-\xff]{4}alex [0-9]+\.[0-9]+\.[0-9]+[-+.0-9A-Za-z\xc3\xa9]*", b"LLLLalex X", b)
print(hashlib.sha256(b).hexdigest())' "$1"
}

one() { # mode fichier -> ligne « mode fichier résultat »
    m=$1; f=$2; o="$W/out"
    rm -f "$o" "$o".*
    case $m in
        bc) "$E" build "$f" -o "$o" > /dev/null 2> "$W/err" ;;
        bc1) if [ -n "${COMPILE1:-}" ]; then "$COMPILE1" "$f" "$o" > /dev/null 2> "$W/err"; else "$E" compile "$f" -o "$o" > /dev/null 2> "$W/err"; fi ;;
        bcq) if [ -n "${COMPILE1:-}" ]; then "$COMPILE1" "$f" "$o" --qualifier '$mod00112233445566ff' --source "$f" > /dev/null 2> "$W/err"
             else "$E" compile "$f" -o "$o" --qualifier '$mod00112233445566ff' --source "$f" > /dev/null 2> "$W/err"; fi ;;
        x64) "$E" build --native --static "$f" -o "$o" > /dev/null 2> "$W/err" ;;
        win) "$E" build --native --static --windows "$f" -o "$o" > /dev/null 2> "$W/err" ;;
        gui) "$E" build --native --static --gui "$f" -o "$o" > /dev/null 2> "$W/err" ;;
        uefi) "$E" build --native --uefi "$f" -o "$o" > /dev/null 2> "$W/err" ;;
        fs) "$E" build --native --freestanding "$f" -o "$o" > /dev/null 2> "$W/err" ;;
        a64) "$E" build --native --static --target linux-aarch64 "$f" -o "$o" > /dev/null 2> "$W/err" ;;
        wa64) "$E" build --native --static --windows --arm64 "$f" -o "$o" > /dev/null 2> "$W/err" ;;
    esac
    rc=$?
    if [ $rc -eq 0 ] && [ -f "$o" ]; then
        case $m in bc*) h=$(hash_albc "$o") ;; *) h=$(sha256sum "$o" | cut -c1-64) ;; esac
        printf '%s\t%s\t%s\n' "$m" "$f" "$h"
    else
        printf '%s\t%s\tREFUS %s\n' "$m" "$f" "$(grep -v '^-- terminé' "$W/err" | head -1 | sed "s#$REPO/##g")"
    fi
}

if [ $RECORD -eq 1 ]; then
    : > "$W/table"
    for m in $MODES; do
        for f in $(files); do one "$m" "$f" >> "$W/table"; done
        echo "$m : $(grep -c "^$m	" "$W/table") programmes" >&2
    done
    if [ -f "$TABLE" ]; then
        # modes non réenregistrés : lignes conservées
        for m in bc bc1 bcq x64 win gui uefi fs a64 wa64; do
            case " $MODES " in *" $m "*) ;; *) grep "^$m	" "$TABLE" >> "$W/table" ;; esac
        done
    fi
    LC_ALL=C sort -t "	" -k1,1 -k2,2 "$W/table" > "$TABLE"
    echo "table : $(wc -l < "$TABLE") lignes dans tests/selfhost/golden.tsv"
    exit 0
fi

pass=0; fail=0; refus=0
for m in $MODES; do
    for f in $(files); do
        want=$(awk -F '\t' -v m="$m" -v f="$f" '$1 == m && $2 == f { print $3 }' "$TABLE")
        [ -z "$want" ] && continue
        got=$(one "$m" "$f" | cut -f3)
        if [ "$got" = "$want" ]; then
            pass=$((pass + 1))
            case "$want" in REFUS*) refus=$((refus + 1)) ;; esac
        else
            fail=$((fail + 1)); echo "ÉCHEC $m $f"; echo "  attendu : $want"; echo "  obtenu  : $got"
        fi
    done
done
echo "golden : $pass identiques (dont $refus refus au même diagnostic), $fail différences"
[ $fail -eq 0 ]
