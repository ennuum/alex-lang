#!/bin/sh
# Test X11 réel du paquet window : position, états (émulés sans gestionnaire de fenêtres), focus, événements
# clavier (appui ET relâchement) envoyés par tests/ui/x11_driver.al. Ignoré sans xvfb-run.
set -eu
cd "$(dirname "$0")/../.."
command -v xvfb-run >/dev/null 2>&1 || { echo "SKIP : xvfb-run absent (apt install xvfb)"; exit 0; }
[ -x ./alexc ] || make alex
DRV="${TMPDIR:-/tmp}/alex_x11_wdriver.$$"
OUT="${TMPDIR:-/tmp}/alex_x11_wout.$$"
INNER="${TMPDIR:-/tmp}/alex_x11_winner.$$.sh"
./alexc build --native tests/ui/x11_driver.al -o "$DRV" > /dev/null 2>&1 || { echo "ÉCHEC : construction du pilote X11 (tests/ui/x11_driver.al)"; exit 1; }
trap 'rm -f "$DRV" "$OUT" "$INNER"' EXIT
cat > "$INNER" <<INNERSH
#!/bin/sh
ALEX_UI_BACKEND=x11 ./alex run tests/window/x11_window_app.al > "$OUT" 2>&1 &
APP=\$!
"$DRV" "ALEX Window Test" wait 1500 type "ab" wait 300 close
wait \$APP
INNERSH
chmod +x "$INNER"
timeout 60 xvfb-run -a -s "-screen 0 1024x768x24" "$INNER"
fail=0
for pat in "POS (150, 100)" "MAX maximized (1024, 768)" "RESTORE normal (320, 200)" "FOCUSED true" "a:press" "a:release" "b:press" "b:release" "PRESSED \[\]"; do
  grep -q "$pat" "$OUT" || { echo "ÉCHEC : '$pat' absent"; fail=1; }
done
if [ $fail -ne 0 ]; then cat "$OUT"; exit 1; fi
echo "window X11 : OK"
