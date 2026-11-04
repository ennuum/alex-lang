#!/bin/sh
# Distribution Windows d'ALEX : archive .zip (install.cmd / install.ps1) et installeur .exe (Inno Setup).
#   sh tools/package-windows.sh [windows-x86_64]     (ou : make installer-windows)
#
# Prérequis : build/alex.exe et build/alexvm.exe, produits sous Linux par la chaîne ALEX (make alex-windows ;
# aucun compilateur C/C++ ni MinGW).
# Disposition de l'archive et du dossier installé (bibliothèque cherchée dans <bin>\..\lib\alex\stdlib) :
#   bin\alexc.exe bin\alex.exe (alias) bin\alexvm.exe   lib\alex\{stdlib,runtime,templates}   share\doc\alex   share\alex\editors\vscode
#   alex.ico  LISEZMOI.txt  VERSION.txt  install.cmd  install.ps1
# Installeur .exe : produit si Inno Setup est disponible (iscc, ou « wine iscc.exe », ou $ISCC) ; sinon seule
# l'archive est créée et le script alex.iss reste utilisable sous Windows (iscc tools\windows\alex.iss).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PLATFORM=${1:-windows-x86_64}
case "$PLATFORM" in
    windows-x86_64) ARCH_TAG=x86_64 ;;
    *) echo "plateforme Windows attendue : windows-x86_64 (reçu : $PLATFORM)" >&2; exit 2 ;;
esac
EXE="$ROOT/build/alex.exe"
INFO="$ROOT/build/generated/alex_build_info.txt"

if [ ! -f "$EXE" ] || [ ! -f "$ROOT/build/alexvm.exe" ]; then
    echo "== chaîne Windows (make alex-windows)"
    (cd "$ROOT" && make alex-windows)
fi
[ -f "$EXE" ] || { echo "alex.exe introuvable : $EXE" >&2; exit 1; }

# Version inscrite dans alex.exe : première colonne de la ligne d'identité de la construction.
VERSION=${ALEX_PACKAGE_VERSION:-$(cut -d'|' -f1 "$INFO" 2>/dev/null)}
[ -n "$VERSION" ] || VERSION=$(tr -d ' \t\r\n' < "$ROOT/VERSION")
# Version numérique à quatre champs pour les ressources Windows : 1.2.0-beta.7 -> 1.2.0.7 ; 1.2.0 -> 1.2.0.0
BASE=${VERSION%%-*}
BUILDN=$(printf '%s' "$VERSION" | sed -n 's/.*-beta\.\([0-9][0-9]*\).*/\1/p')
NUMERIC="$BASE.${BUILDN:-0}"

NAME=alex-$VERSION-windows-$ARCH_TAG
OUT="$ROOT/dist"
WORK=$(mktemp -d)
STAGE="$WORK/$NAME"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$STAGE/bin" "$STAGE/lib/alex" "$STAGE/share/doc/alex" "$STAGE/share/alex/editors" "$OUT"

echo "== assemblage de $NAME"
cp "$EXE" "$STAGE/bin/alexc.exe"
cp "$EXE" "$STAGE/bin/alex.exe"   # ancien nom, conservé pour les scripts existants
cp "$ROOT/build/alexvm.exe" "$STAGE/bin/alexvm.exe"
copy_tree() { # source destination : sans caches de compilation
    (cd "$1" && find . -type f ! -name '*.albc' ! -name '*.meta' ! -path '*/__pycache__/*' -print) | while read -r f; do
        mkdir -p "$2/$(dirname "$f")"
        cp "$1/$f" "$2/$f"
    done
}
copy_tree "$ROOT/stdlib" "$STAGE/lib/alex/stdlib"
copy_tree "$ROOT/templates" "$STAGE/lib/alex/templates"
# Runtime de la chaîne ALEX pure (préludes, runtime natif, stdlib native, VM) : uniquement des fichiers .al,
# à côté de stdlib (runtime_dir = <parent de stdlib>/runtime) ; sans eux alex.exe ne peut pas compiler en natif.
copy_tree "$ROOT/runtime/alex" "$STAGE/lib/alex/runtime/alex"
copy_tree "$ROOT/runtime/vm" "$STAGE/lib/alex/runtime/vm"
copy_tree "$ROOT/editors/vscode" "$STAGE/share/alex/editors/vscode"
cp "$ROOT"/docs/*.md "$ROOT/README.md" "$STAGE/share/doc/alex/" 2>/dev/null || true
# Référence HTML de la stdlib : générée par le alex natif s'il existe (le alex.exe ne s'exécute pas ici).
if [ -x "$ROOT/alex" ]; then
    ALEX_STDLIB="$STAGE/lib/alex/stdlib" "$ROOT/alex" doc --html "$STAGE/share/doc/alex/reference" >/dev/null 2>&1 || echo "(référence HTML non générée)"
fi

# Icône multi-résolutions (.ico) d'après le logo d'ALEX.
python3 - "$ROOT/tools/branding/alex_logo_256.png" "$STAGE/alex.ico" <<'PY' || echo "(icône non générée : Pillow absent ?)"
import sys
from PIL import Image
img = Image.open(sys.argv[1]).convert("RGBA")
img.save(sys.argv[2], format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
PY
[ -f "$STAGE/alex.ico" ] || cp "$ROOT/tools/windows/fallback.ico" "$STAGE/alex.ico" 2>/dev/null || : > "$STAGE/alex.ico"

printf '%s\n' "$VERSION" > "$STAGE/VERSION.txt"
cp "$ROOT/tools/windows/install.ps1" "$ROOT/tools/windows/install.cmd" "$STAGE/"
cat > "$STAGE/LISEZMOI.txt" <<'TXT'
ALEX @VERSION@ (Windows @ARCH@)

Installation :  double-cliquez sur install.cmd           (utilisateur courant, sans droits d'administrateur)
                install.cmd -AllUsers                     (tous les utilisateurs, demande l'élévation)
                install.cmd -Associate                    (associe aussi les fichiers .al)
                install.cmd -NoPath -NoShortcuts          (copie seule)
                install.cmd -Uninstall                    (désinstallation ; aussi via « Applications installées »)

L'installation ajoute le dossier bin au PATH : ouvrez ensuite un NOUVEAU terminal et tapez  alexc --version
Sans installer : bin\alexc.exe run fichier.al  (la bibliothèque est trouvée dans lib\alex)

ALEX Studio, l'IDE, est distribué à part (installeur alex-studio) ; il utilise ce SDK.

Premiers pas :  alexc new gui mon_app && cd mon_app && alexc run
Documentation : share\doc\alex\
TXT
sed -i "s/@VERSION@/$VERSION/; s/@ARCH@/$ARCH_TAG/" "$STAGE/LISEZMOI.txt"

echo "== archive zip"
ZIP="$OUT/$NAME.zip"
rm -f "$ZIP"
if command -v zip >/dev/null 2>&1; then
    (cd "$WORK" && zip -qr -9 "$ZIP" "$NAME")
else
    python3 -I - "$WORK" "$NAME" "$ZIP" <<'PY'
import sys, zipfile, os
work, name, out = sys.argv[1:4]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for d, _, fs in os.walk(os.path.join(work, name)):
        for f in fs:
            p = os.path.join(d, f)
            z.write(p, os.path.relpath(p, work))
PY
fi
echo "   $ZIP"

echo "== installeur"
ISCC_CMD=""
USE_WINE=0
if [ -n "${ISCC:-}" ]; then
    ISCC_CMD="$ISCC"
elif command -v iscc >/dev/null 2>&1; then
    ISCC_CMD=iscc
elif command -v wine >/dev/null 2>&1; then
    for c in "$HOME"/.wine/drive_c/Program\ Files*/Inno\ Setup\ */ISCC.exe; do
        if [ -f "$c" ]; then ISCC_CMD="$c"; USE_WINE=1; fi
    done
fi
if [ -z "$ISCC_CMD" ]; then
    echo "   Inno Setup absent : installeur .exe non produit (archive zip prête)."
    echo "   Sous Windows :  iscc /DAppVersion=$VERSION /DNumericVersion=$NUMERIC /DArchTag=$ARCH_TAG /DStageDir=<dossier $NAME décompressé> tools/windows/alex.iss"
    exit 0
fi
# Sous wine, iscc attend des chemins Windows.
conv() {
    if [ "$USE_WINE" = 1 ] && command -v winepath >/dev/null 2>&1; then winepath -w "$1"; else printf '%s' "$1"; fi
}
if [ "$USE_WINE" = 1 ]; then RUN="wine $ISCC_CMD"; else RUN="$ISCC_CMD"; fi
$RUN "/DAppVersion=$VERSION" "/DNumericVersion=$NUMERIC" "/DArchTag=$ARCH_TAG" \
    "/DStageDir=$(conv "$STAGE")" "/DOutDir=$(conv "$OUT")" "$(conv "$ROOT/tools/windows/alex.iss")"
echo "   $OUT/$NAME-setup.exe"
