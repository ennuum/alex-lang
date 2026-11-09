#!/usr/bin/env bash
# Commandes de la chaîne d'outils (repl, fmt, new, doc, test, pkg, debug, lsp) comparées à des sorties de
# référence (tests/alexc/golden/), enregistrées avec l'alex de référence avant le retrait du C++ : mêmes sorties,
# mêmes codes de sortie, aux durées mesurées et aux dossiers temporaires près.
#
#   tests/alexc/golden.sh [./alex]                    vérifie (make test-alexc)
#   tests/alexc/golden.sh --record BINAIRE            réenregistre les références (évolution voulue d'une sortie)
set -u
cd "$(dirname "$0")/../.."
REPO=$(pwd)
G="$REPO/tests/alexc/golden"
RECORD=0
if [ "${1:-}" = "--record" ]; then RECORD=1; shift; fi
E=${1:-./alex}
case "$E" in /*) ;; *) E="$REPO/$E" ;; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
O="$W/out"
mkdir -p "$O"
# normalisation : dossier temporaire, durées, version de la chaîne d'outils (et ce qui en dépend : longueur des
# messages LSP, empreintes des paquets dont le manifeste porte l'exigence alex = ">=VERSION")
V=$("$E" version --short)
# Les valeurs substituées sont des chaînes littérales, pas des expressions : on échappe les métacaractères
# (le « . » de « 1.4.0 » accepterait n'importe quel caractère et prendrait des durées comme « 1.4000 ms »).
lit() { printf '%s' "$1" | sed -E 's/[][\.*^$+?(){}|#]/\\&/g'; }
VR=$(lit "$V"); WR=$(lit "$W"); RR=$(lit "$REPO")
# Ordre : durées d'abord (avant qu'un motif de version puisse en manger une partie), puis dossiers et version.
# Canal : le suffixe « (bêta) » que la chaîne bêta ajoute après sa version est retiré, pour que les mêmes
# références valent dans les deux canaux. Empreintes de modules ($mod…) : hachage du chemin absolu du module.
norm() { sed -E 's/[0-9]+\.[0-9]+ (ms|s)\b/D/g; s/"duration":[0-9.e+-]+/"duration":D/g' "$1" \
    | sed -E "s#$WR#W#g; s#$RR#REPO#g; s#$VR( \(bêta\))?#VERSION#g" \
    | sed -E 's/^Content-Length: [0-9]+/Content-Length: N/; s/\}Content-Length: [0-9]+/}Content-Length: N/g; s/sha256:[0-9a-f]{64}/sha256:H/g; s/\$mod[0-9a-f]{16}/$modH/g'; }
put() { norm "$2" > "$O/$1.txt"; }
# repl
"$E" repl < tests/alexc/repl.in > "$W/x" 2>&1; echo "rc=$?" >> "$W/x"
put repl "$W/x"
# fmt
mkdir -p "$W/fm/sub" "$W/fm/build"
printf 'x := 1   \n\tif x:\n\t\tprint(x)\t\n\n\n\n\ny := 2\n\n\n' > "$W/fm/a.al"; printf 'ok := 1\n' > "$W/fm/sub/b.al"; printf 'z  \n' > "$W/fm/build/c.al"
(cd "$W/fm" && "$E" fmt --check; echo "rc=$?"; "$E" fmt; echo "rc=$?"; cat a.al) > "$W/x" 2>&1
put fmt "$W/x"
# new
mkdir -p "$W/n"
{ "$E" new --list; echo "rc=$?"; "$E" new --list --json; for t in console gui cli lib server kernel driver; do "$E" new $t p_$t --dir "$W/n" | sed "s#$W/n#DIR#g"; done
  "$E" new cli p_x --dir "$W/n" --ci gitlab > /dev/null; "$E" new bad-name; echo "rc=$?"; } > "$W/x" 2>&1
put new "$W/x"
# fichiers binaires des modèles (icônes, images) : taille et empreinte plutôt que le contenu
(cd "$W/n" && find . -type f | LC_ALL=C sort | while read -r f; do echo "== $f"; case "$f" in
    *.ico|*.png) echo "<binaire : $(wc -c < "$f" | tr -d ' ') octets, sha256 $(sha256sum "$f" | cut -c1-16)>" ;;
    *) cat "$f" ;; esac; done) > "$W/x"
put new_files "$W/x"
# doc
{ "$E" doc --list; for m in json os string compiler.parser ui.widgets; do "$E" doc $m; "$E" doc --json $m; done; "$E" doc nexistepas; echo "rc=$?"
  (mkdir -p "$W/h" && cd "$W/h" && ALEX_STDLIB="$REPO/stdlib" "$E" doc --html site json os > /dev/null; echo "rc=$?"); } > "$W/x" 2>&1
put doc "$W/x"
(cd "$W/h" && find . -type f | LC_ALL=C sort | while read -r f; do echo "== $f"; cat "$f"; echo; done) > "$W/x"
put doc_html "$W/x"
# test
mkdir -p "$W/tt/tests/sub"
cat > "$W/tt/tests/test_a.al" <<'AL'
use testing
func test_ok():
    testing.assert_eq(1 + 1, 2)

func test_ko():
    testing.assert_eq(1, 2, "un n'est pas deux")

func test_err():
    raise("ValueError", "boum")
print("sortie libre")
AL
printf 'use testing\ntesting.test("enregistré", () => testing.assert_true(true))\ntesting.skip("sauté", () => 0, "plus tard")\ntesting.run()\n' > "$W/tt/tests/sub/b_test.al"
printf 'print("2 échecs")\n' > "$W/tt/tests/test_script.al"
printf 'x := [1][5]\n' > "$W/tt/tests/test_crash.al"
printf 'func test_x(:\n' > "$W/tt/tests/test_syntax.al"
printf '[package]\nname = "tt"\nversion = "0.1.0"\n' > "$W/tt/alex.toml"
(cd "$W/tt" && for a in "" "--list" "--json" "--list --json" "-k ok" "tests/test_a.al" "-j1"; do echo "== $a"; ALEX_STDLIB="$REPO/stdlib" "$E" test $a; echo "rc=$?"; done) > "$W/x" 2>&1
put test "$W/x"
# pkg
for s in 1 2; do
    bash tests/alexc/pkg_scenario$s.sh "$E" "$W/pk" 2>&1 | sed "s#$W/pk#PK#g" > "$W/x"
    put pkg$s "$W/x"
done
# debug
for m in 2 1; do
    python3 tests/alexc/debug_drive.py "$E" $m > "$W/x" 2>&1
    put debug$m "$W/x"
done
# lsp : la session de tests/tooling/lsp_test.py, messages du serveur octet pour octet
# (copie exécutable : le bit x de lsp_tee.sh ne survit pas à toutes les extractions / checkouts)
cp tests/alexc/lsp_tee.sh "$W/lsp_tee.sh" && chmod +x "$W/lsp_tee.sh"
REAL="$E" LOG="$W/lsp" python3 tests/tooling/lsp_test.py "$W/lsp_tee.sh" > /dev/null 2>&1
put lsp "$W/lsp"

if [ $RECORD -eq 1 ]; then
    rm -rf "$G" && mkdir -p "$G" && cp "$O"/*.txt "$G"/
    echo "références enregistrées : $(ls "$G" | wc -l) fichiers dans tests/alexc/golden"
    exit 0
fi
pass=0; fail=0
for f in "$G"/*.txt; do
    n=$(basename "$f" .txt)
    if cmp -s "$f" "$O/$n.txt"; then pass=$((pass+1)); echo "  ok   $n"
    else fail=$((fail+1)); echo "  ÉCHEC $n"; diff "$f" "$O/$n.txt" | head -20; fi
done
echo "$pass OK, $fail échecs"
[ $fail -eq 0 ]
