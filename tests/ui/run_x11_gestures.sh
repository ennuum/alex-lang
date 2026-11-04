#!/bin/sh
# Test X11 réel (V1.3) : clic, double-clic, clic droit, glisser, molette, Ctrl+touche, fermeture confirmée.
set -eu
cd "$(dirname "$0")/../.."
command -v xvfb-run >/dev/null 2>&1 || { echo "SKIP : xvfb-run absent"; exit 0; }
[ -x ./alexc ] || make alex
DRV="${TMPDIR:-/tmp}/alex_x11_driver.$$"
OUT="${TMPDIR:-/tmp}/alex_x11_gest.$$"
./alexc build --native tests/ui/x11_driver.al -o "$DRV" > /dev/null 2>&1 || { echo "ÉCHEC : construction du pilote X11 (tests/ui/x11_driver.al)"; exit 1; }
trap 'rm -f "$DRV" "$OUT" "$OUT.sh"' EXIT
cat > "$OUT.sh" <<INNER
#!/bin/sh
./alex run tests/ui/x11_gestures.al > "$OUT" 2>&1 &
APP=\$!
T="ALEX X11 Gestes"
"$DRV" "\$T" wait 300 click 50 40 wait 450 dclick 60 40 wait 450 rclick 70 40 wait 450 drag 200 100 260 140 wait 100 wheel 100 100 -2 wheel 100 100 1 wait 100 key ctrl+Left key ctrl+shift+a wait 100 type "(.)" wait 100 close wait 300 close wait 800
wait \$APP
INNER
chmod +x "$OUT.sh"
timeout 60 xvfb-run -a -s "-screen 0 1024x768x24" "$OUT.sh"
fail=0
for pat in "EVT click 50 40" "EVT double_click" "EVT context 70 40" "EVT drag_end 260 140" "EVT wheel -1.0" "EVT wheel 1.0" "EVT key 37 2" "EVT key 65 6" "EVT close_request 1" "EVT close_request 2" "FIN cursor=pointer"; do
  grep -q "$pat" "$OUT" || { echo "ÉCHEC : '$pat' absent"; fail=1; }
done
# ponctuation : jamais confondue avec flèches / Suppr (codes VK_OEM, texte transmis séparément)
grep -Eq "EVT key [0-9]+ [0-9]+ \(" "$OUT" || { echo "ÉCHEC : '(' attendu comme TEXTE saisi"; fail=1; }
grep -Eq "EVT key (40|37|46) [0-9]+ [(.)]" "$OUT" && { echo "ÉCHEC : ponctuation confondue avec une touche de navigation"; fail=1; }
grep -q "EVT key 190 0 \." "$OUT" || { echo "ÉCHEC : '.' (VK_OEM_PERIOD=190) attendu"; fail=1; }
if [ $fail -ne 0 ]; then cat "$OUT"; exit 1; fi
echo "UI X11 GESTES: OK"
