#!/bin/sh
# Exécutables autonomes (docs/STANDALONE.md). Lancer DEPUIS LA RACINE DU PROJET.
set -u
ALEX_BIN=${ALEX_BIN:-./alex}
ROOT=$(pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
ok()   { echo "ok    $1"; }
fail() { echo "ÉCHEC $1"; fails=$((fails + 1)); }

"$ALEX_BIN" build tests/app/app.al --standalone -o "$TMP/app" 2>/dev/null || { echo "ÉCHEC construction"; exit 1; }
[ -x "$TMP/app" ] && ok "exécutable créé et exécutable" || fail "bit exécutable"

# Exécution HORS du dépôt, sans stdlib ni sources accessibles.
mkdir "$TMP/ailleurs" && cp "$TMP/app" "$TMP/ailleurs/app"
cd "$TMP/ailleurs"
out=$(ALEX_STDLIB=/nonexistent ./app un "deux trois" 2>&1); rc=$?
expected='Bonjour, monde !
args=["un","deux trois"]
somme=42'
[ "$rc" -eq 0 ] && [ "$out" = "$expected" ] && ok "exécution autonome, arguments transmis" || { fail "exécution autonome (code $rc)"; echo "$out"; }

out=$(./app run build 2>&1)
case "$out" in *'args=["run","build"]'*) ok "la ligne de commande appartient à l'application" ;; *) fail "commandes alex interceptées"; echo "$out" ;; esac

./app --exit 7 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 7 ] && ok "os.exit(7) -> code 7" || fail "code de sortie ($rc)"

out=$(./app --boom 2>&1 >/dev/null); rc=$?
case "$out" in
    *"tests/app/app.al:23, dans boom"*"KeyError"*) [ "$rc" -eq 1 ] && ok "exception : trace (chemin relatif au projet) + code 1" || fail "code $rc" ;;
    *) fail "trace de l'exception"; echo "$out" ;;
esac
if grep -q "$ROOT" ./app; then fail "chemin absolu de la machine de construction embarqué"; else ok "aucun chemin absolu du projet dans l'exécutable"; fi

out=$(./app 2>&1 >/dev/null)
[ -z "$out" ] && ok "pas de ligne « -- terminé » sur stderr" || { fail "stderr non vide"; echo "$out"; }
cd "$ROOT"

# Reconstruction en prenant un exécutable autonome comme runtime : l'ancien bytecode est retiré.
"$ALEX_BIN" build tests/app/app.al --standalone --runtime "$TMP/app" -o "$TMP/app2" 2>/dev/null
s1=$(wc -c < "$TMP/app"); s2=$(wc -c < "$TMP/app2")
[ "$s1" -eq "$s2" ] && "$TMP/app2" >/dev/null 2>&1 && ok "runtime = exécutable autonome : payload remplacé, pas empilé" || fail "reconstruction ($s1 vs $s2)"

# Remorque corrompue : message clair, code 1 (et pas d'exécution de données arbitraires).
cp "$TMP/app" "$TMP/bad" && printf '\377\377\377\377\377\377\377\177ALEXAPP1' >> "$TMP/bad"
out=$("$TMP/bad" 2>&1); rc=$?
case "$out" in *"corrompu"*) [ "$rc" -eq 1 ] && ok "remorque corrompue détectée" || fail "code $rc" ;; *) fail "remorque corrompue"; echo "$out" ;; esac

# Le binaire alex lui-même reste un CLI normal.
out=$("$ALEX_BIN" 2>&1); case "$out" in *"usage: alex"*) ok "alex sans payload : CLI inchangé" ;; *) fail "CLI alex"; echo "$out" ;; esac

# La stdlib est trouvée hors de la racine du dépôt (ALEX_STDLIB, puis à côté du binaire).
printf 'use json\nprint(json.stringify([1]))\n' > "$TMP/s.al"
out=$(cd "$TMP" && ALEX_STDLIB="$ROOT/stdlib" "$ROOT/$ALEX_BIN" run s.al 2>/dev/null)
[ "$out" = "[1]" ] && ok "stdlib via ALEX_STDLIB" || { fail "ALEX_STDLIB"; echo "$out"; }
mkdir -p "$TMP/inst/bin" "$TMP/inst/lib/alex" && cp "$ALEX_BIN" "$TMP/inst/bin/alex" && cp "$(dirname "$(readlink -f "$ALEX_BIN")")/alexvm" "$TMP/inst/bin/alexvm" && cp -r stdlib runtime "$TMP/inst/lib/alex/"
out=$(cd "$TMP" && "$TMP/inst/bin/alex" run s.al 2>/dev/null)
[ "$out" = "[1]" ] && ok "stdlib trouvée dans <bin>/../lib/alex/stdlib" || { fail "stdlib installée"; echo "$out"; }

if [ "$fails" -ne 0 ]; then echo "test-standalone : $fails échec(s)"; exit 1; fi
echo "test-standalone : toutes les vérifications passent"
