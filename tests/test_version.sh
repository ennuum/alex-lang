#!/bin/sh
# Tests de la gestion des versions du compilateur (docs/VERSIONS.md). Lancer depuis la racine : make test-version
set -e
ROOT=$(pwd)
A=$ROOT/alex
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "  [OK]     $1"; }
ko() { echo "  [ÉCHEC]  $1"; fails=$((fails + 1)); }
expect() { # description commande...
    d=$1; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else ko "$d"; fi
}
expect_not() {
    d=$1; shift
    if "$@" >/dev/null 2>&1; then ko "$d"; else ok "$d"; fi
}

echo "== tools/version.sh"
printf '3.4.5\n' > "$T/VERSION"
export ALEX_VERSION_FILE="$T/VERSION" ALEX_BUILD_STATE="$T/state"
sh tools/version.sh gen "$T/g1/info.txt" beta 2>/dev/null
sh tools/version.sh gen "$T/g2/info.txt" beta 2>/dev/null
expect "numéro de build croissant (bêta 1 puis 2)" grep -q '^3.4.5-beta.2|' "$T/g2/info.txt"
sh tools/version.sh gen "$T/gs/info.txt" stable 2>/dev/null
expect "stable sans suffixe" grep -q '^3.4.5|3.4.5+' "$T/gs/info.txt"
BUILD_NUMBER=42 sh tools/version.sh gen "$T/gn/info.txt" beta 2>/dev/null
expect "BUILD_NUMBER imposé (CI)" grep -q '^3.4.5-beta.42|' "$T/gn/info.txt"
SOURCE_DATE_EPOCH=0 sh tools/version.sh gen "$T/gd/info.txt" beta 2>/dev/null
expect "SOURCE_DATE_EPOCH (date reproductible)" grep -q '|1970-01-01T00:00:00Z|' "$T/gd/info.txt"
expect_not "canal inconnu refusé" sh tools/version.sh check rc
printf '1.02.3\n' > "$T/BAD"
expect_not "VERSION invalide refusée" env ALEX_VERSION_FILE="$T/BAD" sh tools/version.sh show
sh tools/version.sh bump minor >/dev/null
expect "bump minor -> 3.5.0" grep -qx '3.5.0' "$T/VERSION"
sh tools/version.sh bump major >/dev/null
expect "bump major -> 4.0.0" grep -qx '4.0.0' "$T/VERSION"
expect "version Debian 1.2.0~beta.7" test "$(sh tools/version.sh deb 1.2.0-beta.7)" = "1.2.0~beta.7"
unset ALEX_VERSION_FILE ALEX_BUILD_STATE

echo "== identité inscrite dans un exécutable (bêta et stable)"
# ALEX_BUILD_INFO : le compilateur natif inscrit la version donnée par tools/version.sh gen (comme pour alex et
# alexvm) ; os.alex_build() et os.alex_satisfies() la lisent à l'exécution.
cat > "$T/ver.al" <<'EOF2'
use os
b := os.alex_build()
print(b["version"] + " " + b["channel"] + " " + b["base"] + " " + str(b["major"]) + str(b["minor"]) + str(b["patch"]))
print(b["full"] == b["version"] + "+" + b["source_id"])
print(os.alex_satisfies(">=3.4.5"), os.alex_satisfies(">=3.4.0"), os.alex_satisfies(">=3.4.5-beta.1"), os.alex_satisfies("^3.0"), os.alex_satisfies(">=3.5"))
try:
    os.alex_satisfies("n'importe quoi")
    print("accepté")
catch e:
    print("refusé")
EOF2
for ch in beta stable; do
    printf '3.4.5\n' > "$T/VERSION"
    ALEX_VERSION_FILE="$T/VERSION" ALEX_BUILD_STATE="$T/st2" sh tools/version.sh gen "$T/u-$ch.txt" $ch 2>/dev/null
    if ALEX_BUILD_INFO="$T/u-$ch.txt" $A build --native --dynamic "$T/ver.al" -o "$T/ver-$ch" > /dev/null 2>&1; then
        out=$("$T/ver-$ch" 2>&1)
        if [ $ch = stable ]; then want="3.4.5 stable 3.4.5 345
true
true true true true false
refusé"; else want="3.4.5-beta.1 beta 3.4.5 345
true
false true true false false
refusé"; fi
        if [ "$out" = "$want" ]; then ok "identité $ch"; else ko "identité $ch"; echo "$out"; fi
    else
        ko "construction ($ch)"
    fi
done

echo "== alex --version / alex version"
V=$($A version --short)
CH=$($A version --channel)
case "$CH" in
    beta) echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$' && ok "forme bêta ($V)" || ko "forme bêta ($V)" ;;
    stable) echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' && ok "forme stable ($V)" || ko "forme stable ($V)" ;;
    *) ko "canal inconnu $CH" ;;
esac
expect "base = fichier VERSION" sh -c "$A version --short | grep -q \"^\$(cat VERSION)\""
expect "--version mentionne la version" sh -c "$A --version | head -1 | grep -q \"alex $V\""
expect "--json" sh -c "$A version --json | grep -q '\"channel\": \"$CH\"'"
expect "--check satisfaite" $A version --check ">=0.1.0"
expect_not "--check non satisfaite" $A version --check ">=999.0.0"

echo "== bytecode (section PRODUCER)"
printf 'use os\nprint(os.alex_version())\nprint(os.alex_satisfies(">=0.1"))\n' > "$T/p.al"
(cd "$T" && $A build p.al -o p.albc >/dev/null 2>&1)
FULL=$($A version --full)
expect "producteur inscrit dans le .albc" sh -c "$A version '$T/p.albc' | grep -q 'compilé par alex $FULL'"
OUT=$(cd "$T" && $A run p.albc 2>&1)
expect "os.alex_version() = alex version --short" sh -c "printf '%s' \"$OUT\" | head -1 | grep -qx '$V'"
expect "os.alex_satisfies" sh -c "printf '%s' \"$OUT\" | sed -n 2p | grep -qx true"
python3 -c "import sys; b=bytearray(open(sys.argv[1],'rb').read()); b[6]=99; open(sys.argv[2],'wb').write(b)" "$T/p.albc" "$T/futur.albc"
expect_not "format plus récent refusé" sh -c "cd '$T' && $A run futur.albc"
expect "message explicite" sh -c "cd '$T' && $A run futur.albc 2>&1 | grep -q 'plus récent'"

echo "== caches de modules"
expect "cache .meta lié au compilateur" grep -qx "compiler=$FULL" stdlib/os/os.al.meta
cp stdlib/os/os.al.meta "$T/meta.bak"
sed -i 's/^compiler=.*/compiler=0.0.0-ancien/' stdlib/os/os.al.meta
(cd "$T" && $A run p.al >/dev/null 2>&1)
expect "cache d'un autre compilateur recompilé" grep -qx "compiler=$FULL" stdlib/os/os.al.meta
(cd "$T" && $A run p.al >/dev/null 2>&1)
$A run "$T/p.al" >/dev/null 2>&1
expect "cache réécrit selon le dossier courant (chemin relatif)" grep -qx "source=stdlib/os/os.al" stdlib/os/os.al.meta

echo "== exigence alex = \"...\" (alex.toml)"
mkdir -p "$T/proj" && cd "$T/proj"
$A pkg init demo >/dev/null
printf 'print("ok")\n' > main.al
expect "pkg init : exigence satisfaite par ce compilateur" $A run
sed -i 's/^alex = .*/alex = ">=999.0.0"/' alex.toml
expect_not "exigence non satisfaite refusée" $A run
expect "message explicite" sh -c "$A run 2>&1 | grep -q 'exige le compilateur ALEX >=999.0.0'"
sed -i 's/^alex = .*/alex = "pas une version"/' alex.toml
expect_not "exigence mal formée refusée" $A run
cd "$ROOT"

if [ $fails -gt 0 ]; then echo "VERSIONS : $fails échec(s)"; exit 1; fi
echo "VERSIONS: OK"
