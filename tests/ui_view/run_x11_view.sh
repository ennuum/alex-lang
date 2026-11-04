#!/bin/sh
# ui.view dans une vraie fenêtre X11 (Xvfb) : clics, frappes, Tab, molette, menu (F10), envoyés par
# tests/ui/x11_driver.al. Positions prises sur la même mise en page calculée hors écran (probe).
set -eu
cd "$(dirname "$0")/../.."
command -v xvfb-run >/dev/null 2>&1 || { echo "SKIP : xvfb-run absent (apt install xvfb)"; exit 0; }
[ -x ./alexc ] || make alex
T="${TMPDIR:-/tmp}"
DRV="$T/alex_view_x11_driver.$$"
OUT="$T/alex_view_x11_out.$$"
INNER="$T/alex_view_x11_inner.$$.sh"
./alexc build --native tests/ui/x11_driver.al -o "$DRV" > /dev/null 2>&1 || { echo "ÉCHEC : construction du pilote X11 (tests/ui/x11_driver.al)"; exit 1; }
trap 'rm -f "$DRV" "$OUT" "$INNER"' EXIT
POS=$(ALEX_UI_BACKEND=headless ./alex run tests/ui_view/x11_view_app.al probe | grep '^POS')
pos() { echo "$POS" | awk -v k="$1" '$2 == k { print $3, $4 }'; }
NOM=$(pos nom); CHK=$(pos Cocher); BTN=$(pos Ajouter); TROIS=$(pos trois)
cat > "$INNER" <<INNER_EOF
#!/bin/sh
./alex run tests/ui_view/x11_view_app.al > "$OUT" 2>&1 &
APP=\$!
# attendre que la fenêtre existe (compilation des modules au premier lancement)
i=0; while [ \$i -lt 100 ] && ! "$DRV" "ALEX VIEW X11" wait 1 >/dev/null 2>&1; do sleep 0.1; i=\$((i+1)); done
sleep 0.5
"$DRV" "ALEX VIEW X11" wait 300 click $NOM type "Hello" key BackSpace type "p" key Tab key space click $BTN click $BTN key ctrl+a click $TROIS wheel $TROIS -2 key Down wait 200 key F10 key Down key Return 2>/dev/null
wait \$APP
INNER_EOF
chmod +x "$INNER"
timeout 90 xvfb-run -a -s "-screen 0 1024x768x24" "$INNER" || true
fail=0
for pat in "FINAL nom=Hellp ok=true n=3 item=quatre"; do
  grep -q "$pat" "$OUT" || { echo "ÉCHEC : '$pat' absent"; fail=1; }
done
if [ $fail -ne 0 ]; then cat "$OUT"; exit 1; fi
echo "ui.view (X11 réel) : OK"
