#!/bin/sh
# Distribution d'ALEX : archive .tar.gz et paquet Debian (.deb) installables.
#   sh tools/package.sh [version]          (ou : make package)
#
# Arborescence installée (préfixe /usr/local par défaut, ou celui de install.sh) :
#   bin/alexc (et bin/alex, alias)           chaîne d'outils écrite en ALEX : compilateur, VM, outils (lsp, debug,
#                                            test, doc, fmt, new, pkg)
#   bin/alexvm                               machine virtuelle seule (exécutables autonomes, alexc build --standalone)
#   lib/alex/stdlib/                         bibliothèque standard
#   lib/alex/templates/                      modèles de projets (alex new)
#   lib/alex/runtime/alex, runtime/vm        runtime natif, préludes et VM (sources ALEX, lus par alexc build --native)
#   share/doc/alex/                          guides (Markdown) et référence HTML de la stdlib
#   share/alex/editors/vscode/               extension VS Code (grammaire, LSP, débogueur)
# ALEX Studio (l'IDE) est un projet séparé, avec ses propres paquets (alex-studio, qui dépend de alex-lang).
set -e
ROOT0=$(cd "$(dirname "$0")/.." && pwd)
# Version : celle du compilateur construit (1.2.0 ou 1.2.0-beta.7), sinon le fichier VERSION.
if [ -n "$1" ]; then VERSION=$1
elif [ -x "$ROOT0/alex" ]; then VERSION=$("$ROOT0/alex" version --short)
else VERSION=$(tr -d ' \t\r\n' < "$ROOT0/VERSION"); fi
# Debian : « ~ » classe une pré-version AVANT la version finale (1.2.0~beta.7 < 1.2.0).
DEB_VERSION=$(printf '%s' "$VERSION" | sed 's/-/~/')
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ARCH=$(uname -m)
OS=$(uname -s | tr 'A-Z' 'a-z')
NAME=alex-$VERSION-$OS-$ARCH
OUT=$ROOT/dist
STAGE=$(mktemp -d)/$NAME
mkdir -p "$STAGE/bin" "$STAGE/lib/alex" "$STAGE/share/doc/alex" "$STAGE/share/alex/editors" "$OUT"

echo "== construction"
(cd "$ROOT" && make -s alex)
cp "$ROOT/alex" "$STAGE/bin/alexc"
strip "$STAGE/bin/alexc" 2>/dev/null || true
cp "$STAGE/bin/alexc" "$STAGE/bin/alex"   # ancien nom, conservé pour les scripts existants
cp "$ROOT/build/alexvm" "$STAGE/bin/alexvm"
strip "$STAGE/bin/alexvm" 2>/dev/null || true

echo "== bibliothèque standard, modèles"
copy_tree() { # source destination : sans caches de compilation
    (cd "$1" && find . -type f ! -name '*.albc' ! -name '*.meta' ! -path '*/__pycache__/*' -print) | while read -r f; do
        mkdir -p "$2/$(dirname "$f")"
        cp "$1/$f" "$2/$f"
    done
}
copy_tree "$ROOT/stdlib" "$STAGE/lib/alex/stdlib"
# Runtime de la chaîne ALEX pure (préludes, runtime natif, stdlib native, VM) : uniquement des fichiers .al
copy_tree "$ROOT/runtime/alex" "$STAGE/lib/alex/runtime/alex"
copy_tree "$ROOT/runtime/vm" "$STAGE/lib/alex/runtime/vm"
copy_tree "$ROOT/templates" "$STAGE/lib/alex/templates"
copy_tree "$ROOT/editors/vscode" "$STAGE/share/alex/editors/vscode"

echo "== documentation"
cp "$ROOT"/docs/*.md "$STAGE/share/doc/alex/" 2>/dev/null || true
cp "$ROOT/README.md" "$STAGE/share/doc/alex/" 2>/dev/null || true
ALEX_STDLIB="$STAGE/lib/alex/stdlib" "$STAGE/bin/alexc" doc --html "$STAGE/share/doc/alex/reference" >/dev/null 2>&1 || echo "(référence HTML non générée)"

cat > "$STAGE/install.sh" <<'EOF'
#!/bin/sh
# Installation d'ALEX : sh install.sh [préfixe]   (défaut : /usr/local ; ~/.local sans droits d'administration)
set -e
PREFIX=${1:-/usr/local}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$PREFIX/bin" "$PREFIX/lib" "$PREFIX/share"
cp "$HERE"/bin/* "$PREFIX/bin/"
rm -rf "$PREFIX/lib/alex"
cp -R "$HERE/lib/alex" "$PREFIX/lib/alex"
cp -R "$HERE/share/." "$PREFIX/share/"
echo "ALEX installé dans $PREFIX — essayez : alexc new console bonjour && cd bonjour && alexc run"
EOF
chmod +x "$STAGE/install.sh"
cat > "$STAGE/LISEZMOI.txt" <<EOF
ALEX $VERSION ($OS $ARCH)

Installation :   sh install.sh            (dans /usr/local)
                 sh install.sh ~/.local   (sans droits d'administration)
Sans installer : ./bin/alexc run fichier.al  (la bibliothèque est trouvée dans lib/alex)

Premiers pas :   alexc new gui mon_app && cd mon_app && alexc run
Documentation :  share/doc/alex/ (guides) et share/doc/alex/reference/index.html (bibliothèque)
EOF

echo "== archive"
(cd "$(dirname "$STAGE")" && tar -czf "$OUT/$NAME.tar.gz" "$NAME")
echo "   $OUT/$NAME.tar.gz"

if command -v dpkg-deb >/dev/null 2>&1; then
    echo "== paquet Debian"
    DEB=$(dirname "$STAGE")/deb
    mkdir -p "$DEB/DEBIAN" "$DEB/usr"
    cp -R "$STAGE/bin" "$STAGE/lib" "$STAGE/share" "$DEB/usr/"
    SIZE=$(du -sk "$DEB/usr" | cut -f1)
    cat > "$DEB/DEBIAN/control" <<EOF
Package: alex-lang
Version: $DEB_VERSION
Section: devel
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Maintainer: ALEX <alex@localhost>
Depends: libc6
Description: Langage ALEX et sa bibliothèque standard
 Compilateur et machine virtuelle ALEX, compilation native et noyaux sans OS,
 bibliothèque standard, serveur de langage (alex lsp), débogueur, exécuteur de
 tests, générateur de documentation, gestionnaire de paquets ; chaîne
 d'outils entièrement écrite en ALEX (alexc, alexvm), interface graphique X11
 parlant directement le protocole (sans Xlib).
EOF
    dpkg-deb --root-owner-group --build "$DEB" "$OUT/alex-lang_${DEB_VERSION}_amd64.deb" >/dev/null
    echo "   $OUT/alex-lang_${DEB_VERSION}_amd64.deb"
fi
rm -rf "$(dirname "$STAGE")"
