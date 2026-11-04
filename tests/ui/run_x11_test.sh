#!/bin/sh
# Test d'intégration X11 réel : lance tests/ui/x11_widgets.al sous Xvfb et lui envoie de vrais
# événements X (clics, frappes Maj+lettres, Entrée, fermeture WM_DELETE_WINDOW).
# Prérequis : xvfb-run (le pilote, tests/ui/x11_driver.al, parle le protocole X11 directement).
set -eu
cd "$(dirname "$0")/../.."
command -v xvfb-run >/dev/null 2>&1 || { echo "SKIP : xvfb-run absent (apt install xvfb)"; exit 0; }
[ -x ./alexc ] || make alex
DRV="${TMPDIR:-/tmp}/alex_x11_driver.$$"
OUT="${TMPDIR:-/tmp}/alex_x11_out.$$"
./alexc build --native tests/ui/x11_driver.al -o "$DRV" > /dev/null 2>&1 || { echo "ÉCHEC : construction du pilote X11 (tests/ui/x11_driver.al)"; exit 1; }
trap 'rm -f "$DRV" "$OUT"' EXIT

cat > "${TMPDIR:-/tmp}/alex_x11_inner.$$.sh" <<INNER
#!/bin/sh
./alex run tests/ui/x11_widgets.al > "$OUT" 2>&1 &
APP=\$!
"$DRV" "ALEX X11 Test" wait 400 click 60 38 click 30 84 click 100 126 type "Hello" key BackSpace type " Xy" key Return wait 200 close
wait \$APP
INNER
chmod +x "${TMPDIR:-/tmp}/alex_x11_inner.$$.sh"
timeout 60 xvfb-run -a -s "-screen 0 1024x768x24" "${TMPDIR:-/tmp}/alex_x11_inner.$$.sh"
rm -f "${TMPDIR:-/tmp}/alex_x11_inner.$$.sh"

fail=0
for pat in "EVT button" "EVT check" "FINAL text=Hell Xy" "EVT enter"; do
  grep -q "$pat" "$OUT" || { echo "ÉCHEC : '$pat' absent"; fail=1; }
done
if [ $fail -ne 0 ]; then cat "$OUT"; exit 1; fi
echo "UI X11: OK"
