#!/bin/sh
# Gestion des versions du compilateur ALEX.
#
# La version de base (MAJEUR.MINEUR.CORRECTIF, SemVer 2.0) est dans le fichier VERSION à la racine ; le CANAL
# (beta | stable) est choisi à la compilation (make CHANNEL=stable). À CHAQUE construction de la chaîne d'outils
# (`make alex`), `make` appelle `tools/version.sh gen` qui :
#   - attribue un numéro de build croissant (compteur local par version et par canal, ou $BUILD_NUMBER en CI) ;
#   - calcule l'empreinte des sources (SHA-256 des sources ALEX du compilateur, du runtime et de la VM, de VERSION
#     et du canal) ;
#   - écrit build/generated/alex_build_info.txt : une ligne
#       version|complète|base|majeur|mineur|correctif|canal|build|date|empreinte|commit|compilé par|plateforme
#     que le compilateur natif inscrit dans `alex` et `alexvm` (variable ALEX_BUILD_INFO, os.alex_build()).
# Version publiée :  stable -> 1.2.0          beta -> 1.2.0-beta.7         (+ métadonnées : +<empreinte>)
#
#   sh tools/version.sh gen <fichier> <canal> [compilateur]   (appelé par make)
#   sh tools/version.sh show                  version de base (VERSION)
#   sh tools/version.sh set 1.4.0             fixe la version de base
#   sh tools/version.sh bump major|minor|patch
#   sh tools/version.sh check <canal>         vérifie VERSION et le canal (code 1 sinon)
#   sh tools/version.sh deb <version>         version Debian (1.2.0-beta.7 -> 1.2.0~beta.7)
#
# Variables : BUILD_NUMBER (numéro imposé, CI), SOURCE_DATE_EPOCH (date reproductible),
#   ALEX_BUILD_STATE (dossier des compteurs, défaut .alex-build à la racine : survit à `make clean`),
#   ALEX_VERSION_FILE (autre fichier VERSION, pour les tests).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION_FILE=${ALEX_VERSION_FILE:-$ROOT/VERSION}
STATE=${ALEX_BUILD_STATE:-$ROOT/.alex-build}

die() { echo "version.sh : $*" >&2; exit 1; }

read_base() {
    [ -f "$VERSION_FILE" ] || die "fichier VERSION introuvable ($VERSION_FILE)"
    b=$(tr -d ' \t\r\n' < "$VERSION_FILE")
    valid_base "$b" || die "VERSION invalide : « $b » (attendu MAJEUR.MINEUR.CORRECTIF, ex. 1.4.0, sans zéro initial)"
    echo "$b"
}

valid_base() {
    echo "$1" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
}

valid_channel() {
    case "$1" in beta|stable) return 0 ;; *) return 1 ;; esac
}

check_channel() {
    valid_channel "$1" || die "canal inconnu : « $1 » (attendu : beta ou stable ; ex. make CHANNEL=stable)"
}

sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -c1-64
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -c1-64
    else cksum | tr ' ' '-'
    fi
}

source_id() { # base canal options
    {
        printf '%s|%s|%s\n' "$1" "$2" "$3"
        (cd "$ROOT" && find src runtime tools/selfhost -type f -name '*.al' | LC_ALL=C sort | while read -r f; do
            printf '%s\n' "$f"
            cat "$f"
        done)
    } | sha | cut -c1-12
}

next_number() { # base canal
    if [ -n "$BUILD_NUMBER" ]; then
        echo "$BUILD_NUMBER" | grep -Eq '^[0-9]+$' || die "BUILD_NUMBER invalide : « $BUILD_NUMBER » (entier attendu)"
        echo "$BUILD_NUMBER"
        return
    fi
    mkdir -p "$STATE"
    f=$STATE/build-$1-$2
    n=0
    [ -f "$f" ] && n=$(tr -dc '0-9' < "$f")
    [ -n "$n" ] || n=0
    n=$((n + 1))
    printf '%s\n' "$n" > "$f.tmp" && mv "$f.tmp" "$f"
    echo "$n"
}

c_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

cmd_gen() {
    out=$1; channel=$2; flags=$3
    [ -n "$out" ] && [ -n "$channel" ] || die "usage : version.sh gen <en-tête> <canal> [options]"
    check_channel "$channel"
    base=$(read_base)
    major=${base%%.*}; rest=${base#*.}; minor=${rest%%.*}; patch=${rest#*.}
    number=$(next_number "$base" "$channel")
    if [ -n "$SOURCE_DATE_EPOCH" ]; then
        date=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$SOURCE_DATE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)
    else
        date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    fi
    sid=$(source_id "$base" "$channel" "$flags")
    commit=""
    if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        commit=$(git -C "$ROOT" rev-parse --short=10 HEAD 2>/dev/null || true)
        if [ -n "$commit" ] && [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
            commit="$commit-modifié"
        fi
    fi
    compiler=${3:-}
    host="$(uname -s 2>/dev/null | tr 'A-Z' 'a-z')-$(uname -m 2>/dev/null)"
    if [ "$channel" = "stable" ]; then semver=$base; else semver="$base-$channel.$number"; fi
    mkdir -p "$(dirname "$out")"
    tmp=$out.tmp.$$
    clean() { printf '%s' "$1" | tr -d '|\n\r'; }
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$semver" "$semver+$sid" "$base" "$major" "$minor" "$patch" \
        "$channel" "$number" "$date" "$sid" "$(clean "$commit")" "$(clean "$compiler")" "$(clean "$host")" > "$tmp"
    mv "$tmp" "$out"
    echo "alex $semver+$sid (canal $channel, build $number)" >&2
}

cmd_set() {
    valid_base "$1" || die "version invalide : « $1 » (attendu MAJEUR.MINEUR.CORRECTIF)"
    printf '%s\n' "$1" > "$VERSION_FILE"
    echo "VERSION = $1"
}

cmd_bump() {
    base=$(read_base)
    major=${base%%.*}; rest=${base#*.}; minor=${rest%%.*}; patch=${rest#*.}
    case "$1" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        *) die "usage : version.sh bump major|minor|patch" ;;
    esac
    cmd_set "$major.$minor.$patch"
}

case "$1" in
    gen) shift; cmd_gen "$@" ;;
    show) read_base ;;
    set) shift; cmd_set "$1" ;;
    bump) shift; cmd_bump "$1" ;;
    check) shift; read_base >/dev/null; check_channel "${1:-beta}"; echo "ok" ;;
    deb) shift; printf '%s\n' "$1" | sed 's/-/~/' ;;
    *) die "usage : version.sh gen|show|set|bump|check|deb ..." ;;
esac
