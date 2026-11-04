#!/bin/sh
# Cible Windows du backend natif (alexc build --native --windows, docs/NATIVE.md « Windows »).
# Lancer DEPUIS LA RACINE DU PROJET.
#
# Les exécutables PE32+ produits sont exécutés :
#   - sous Windows (MSYS2, Git Bash) : directement, la VM de référence étant alexvm.exe (alex.exe run) ;
#   - sous Linux : par WINRUN (par exemple WINRUN=wine), sinon seuls leur construction et leur contrat binaire
#     sont vérifiés (tests/native/pe_check.al : en-têtes, relocations, imports, protections des sections) ;
#   - WINRUN_SIM=1 : lanceur simulé qui comprend WINRUN_CONSOLE (poignées de console) et WINRUN_CLICKS (clics
#     simulés de l'interface graphique) — vérifications sautées sans lui.
#
#   1. tests/native/ok_*.al et err_*.al : sortie standard, code de sortie, erreur et trace de pile identiques
#      à la VM, aussi avec ALEX_GC_STRESS=1 ;
#   2. tests/native/only : tâches (piles VirtualAlloc, page de garde VirtualProtect) ;
#   3. tests/native/windows/win_*.al : ligne de commande, input() CRLF, os / io sous Windows ;
#   4. structure du PE et refus de `posix`.
#
# WIN_ARCH=arm64 : mêmes vérifications pour Windows ARM64 (--windows --arm64).
ALEX_BIN=${ALEX_BIN:-./alex}
WIN_ARCH=${WIN_ARCH:-x86_64}
ARCH_FLAG=""
[ "$WIN_ARCH" = arm64 ] && ARCH_FLAG="--arm64"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
EXEC=1
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ON_WINDOWS=1 ;;
    *) ON_WINDOWS=0 ;;
esac
if [ -z "${WINRUN+x}" ]; then
    if [ $ON_WINDOWS -eq 1 ] && [ "$WIN_ARCH" != arm64 ]; then
        WINRUN=""
    elif command -v wine > /dev/null 2>&1 && [ "$WIN_ARCH" != arm64 ]; then
        WINRUN=wine
    else
        EXEC=0
        echo "--    exécution sautée (ni Windows, ni WINRUN, ni wine) : construction et structure des PE seulement"
    fi
fi
SIM=${WINRUN_SIM:-0}
# os.arch() : "aarch64" pour Windows ARM64, la VM (hôte x86-64) affiche "x86_64".
# contrat binaire de chaque PE produit (vérificateur écrit en ALEX, compilé une fois)
PEK=x64
[ "$WIN_ARCH" = arm64 ] && PEK=arm64
"$ALEX_BIN" build --native tests/native/pe_check.al -o "$TMP/pe_check" > /dev/null 2>&1 || { echo "ÉCHEC construction de pe_check"; exit 1; }
pe_ok() { # fichier.exe nom [gui]
    if ! "$TMP/pe_check" "$1" $PEK ${3:-console} > "$TMP/pe.txt"; then
        echo "ÉCHEC $2 : $(cat "$TMP/pe.txt")"; fails=$((fails + 1)); return 1
    fi
}
fix_arch() { if [ "$WIN_ARCH" = arm64 ]; then sed -e 's/^x86_64$/aarch64/' "$1"; else cat "$1"; fi; }

build() { # build source sortie.exe
    if ! "$ALEX_BIN" build --native --windows $ARCH_FLAG "$1" -o "$2" > /dev/null 2> "$TMP/build.err"; then
        echo "ÉCHEC $(basename "$1" .al) : compilation native Windows"; cat "$TMP/build.err"; fails=$((fails + 1)); return 1
    fi
}

for src in tests/native/ok_*.al tests/native/err_*.al; do
    name=$(basename "$src" .al)
    ALEX_NO_TRACE=1 "$ALEX_BIN" run "$src" > "$TMP/vm.out" 2> "$TMP/vm.err"
    vm_rc=$?
    if [ "$name" = "ok_io_os" ]; then # seule différence attendue : os.name() et os.platform()
        sed -e '/^Linux$/{N;s/^Linux\nlinux$/Windows\nwindows/}' "$TMP/vm.out" > "$TMP/vm.fix"
        fix_arch "$TMP/vm.fix" > "$TMP/vm.out"
    fi
    build "$src" "$TMP/$name.exe" || continue
    pe_ok "$TMP/$name.exe" "$name" || continue
    if [ $EXEC -eq 0 ]; then echo "ok    $name (construit, $(head -1 "$TMP/pe.txt" | cut -c7-))"; continue; fi
    $WINRUN "$TMP/$name.exe" > "$TMP/win.out" 2> "$TMP/win.err"
    win_rc=$?
    vm_last=$(grep -v '^-- terminé' "$TMP/vm.err" | tail -n 1)
    win_last=$(tail -n 1 "$TMP/win.err")
    trace_ok=1
    if [ "$vm_rc" -ne 0 ]; then
        "$ALEX_BIN" run "$src" > /dev/null 2> "$TMP/vm.trace"
        $WINRUN "$TMP/$name.exe" > /dev/null 2> "$TMP/win.trace"
        cmp -s "$TMP/vm.trace" "$TMP/win.trace" || trace_ok=0
    fi
    if ! cmp -s "$TMP/vm.out" "$TMP/win.out"; then
        echo "ÉCHEC $name : sortie standard différente"; diff "$TMP/vm.out" "$TMP/win.out" | head -10; tail -n 3 "$TMP/win.err"; fails=$((fails + 1))
    elif [ "$vm_rc" -ne "$win_rc" ]; then
        echo "ÉCHEC $name : code de sortie VM $vm_rc, Windows $win_rc"; tail -n 3 "$TMP/win.err"; fails=$((fails + 1))
    elif [ "$vm_last" != "$win_last" ]; then
        echo "ÉCHEC $name : erreur différente"; echo "  VM      : $vm_last"; echo "  Windows : $win_last"; fails=$((fails + 1))
    elif [ "$trace_ok" -ne 1 ]; then
        echo "ÉCHEC $name : trace de pile différente"; diff "$TMP/vm.trace" "$TMP/win.trace" | head -6; fails=$((fails + 1))
    else
        extra=""
        # err_recursion : 100 000 cadres parcourus à chaque collecte, trop long sous émulation ARM64.
        if [ "$name" != "ok_gc" ] && { [ "$WIN_ARCH" != arm64 ] || [ "$name" != "err_recursion" ]; }; then
            ALEX_GC_STRESS=1 $WINRUN "$TMP/$name.exe" > "$TMP/stress.out" 2> /dev/null
            if cmp -s "$TMP/vm.out" "$TMP/stress.out"; then extra=", GC stress"; else
                echo "ÉCHEC $name : résultat différent sous ALEX_GC_STRESS=1"; fails=$((fails + 1)); continue
            fi
        fi
        if [ "$SIM" = 1 ]; then
            WINRUN_CONSOLE=1 $WINRUN "$TMP/$name.exe" > "$TMP/con.out" 2> "$TMP/con.err"
            if ! cmp -s "$TMP/vm.out" "$TMP/con.out" || [ "$(tail -n 1 "$TMP/con.err")" != "$win_last" ]; then
                echo "ÉCHEC $name : sortie différente vers une console (WriteConsoleW)"; diff "$TMP/vm.out" "$TMP/con.out" | head -6; fails=$((fails + 1)); continue
            fi
            extra="$extra, console"
        fi
        echo "ok    $name ($(wc -l < "$TMP/vm.out") lignes, code $win_rc${win_last:+, $win_last}$extra)"
    fi
done

for src in tests/native/only/*.al; do
    name=$(basename "$src" .al)
    case "$name" in ok_posix|ok_pixmap) continue ;; esac # POSIX : sans objet sous Windows
    expected_rc=0
    [ -f "tests/native/only/${name}_rc.txt" ] && expected_rc=$(cat "tests/native/only/${name}_rc.txt")
    build "$src" "$TMP/$name.exe" || continue
    pe_ok "$TMP/$name.exe" "$name" || continue
    if [ $EXEC -eq 0 ]; then echo "ok    $name (construit, $(head -1 "$TMP/pe.txt" | cut -c7-))"; continue; fi
    $WINRUN "$TMP/$name.exe" > "$TMP/only.out" 2>&1
    rc=$?
    ALEX_GC_STRESS=1 $WINRUN "$TMP/$name.exe" > "$TMP/only_stress.out" 2>&1
    if ! cmp -s "tests/native/only/${name}_expected.txt" "$TMP/only.out" || [ "$rc" -ne "$expected_rc" ]; then
        echo "ÉCHEC $name (code $rc)"; diff "tests/native/only/${name}_expected.txt" "$TMP/only.out" | head -6; fails=$((fails + 1))
    elif ! cmp -s "$TMP/only.out" "$TMP/only_stress.out"; then
        echo "ÉCHEC $name : résultat différent sous ALEX_GC_STRESS=1"; fails=$((fails + 1))
    else
        echo "ok    $name (natif seulement)"
    fi
done

# Ligne de commande : guillemets, barres obliques inverses, vide, tabulation, UTF-8 hors du plan de base.
W=tests/native/windows
if build $W/win_args.al "$TMP/win_args.exe" && [ $EXEC -eq 1 ]; then
    $WINRUN "$TMP/win_args.exe" simple "deux mots" "" 'guillemet " dedans' 'barres \\ et fin\' '\"début' \
        "accents été ☀ 😀" 'a\\\"b' "$(printf '\ttab')" > "$TMP/args.out" 2>&1
    if cmp -s "$W/win_args_expected.txt" "$TMP/args.out"; then echo "ok    win_args (ligne de commande)"; else
        echo "ÉCHEC win_args"; diff "$W/win_args_expected.txt" "$TMP/args.out"; fails=$((fails + 1)); fi
fi
if build $W/win_input.al "$TMP/win_input.exe" && [ $EXEC -eq 1 ]; then
    printf 'abc\r\nété\r\n\r\nx y\nfin\r\n' | $WINRUN "$TMP/win_input.exe" > "$TMP/in.out" 2>&1
    if [ "$SIM" = 1 ]; then
        printf 'abc\nété\n\nx y\nfin\n' | WINRUN_CONSOLE=1 $WINRUN "$TMP/win_input.exe" > "$TMP/in_con.out" 2>&1
    else
        cp "$TMP/in.out" "$TMP/in_con.out"
    fi
    if cmp -s "$W/win_input_expected.txt" "$TMP/in.out" && cmp -s "$W/win_input_expected.txt" "$TMP/in_con.out"; then
        echo "ok    win_input (tube et console, CRLF)"
    else
        echo "ÉCHEC win_input"; diff "$W/win_input_expected.txt" "$TMP/in.out"; diff "$W/win_input_expected.txt" "$TMP/in_con.out"; fails=$((fails + 1))
    fi
fi
if build $W/win_os.al "$TMP/win_os.exe" && [ $EXEC -eq 1 ]; then
    mkdir -p "$TMP/dossier é"
    dir=$(cd "$TMP/dossier é" && pwd -P)
    ALEX_WIN_VAR=oui ALEX_WIN_DIR="$dir" $WINRUN "$TMP/win_os.exe" > "$TMP/os.out" 2>&1
    fix_arch "$W/win_os_expected.txt" > "$TMP/os.expected"
    if cmp -s "$TMP/os.expected" "$TMP/os.out"; then echo "ok    win_os (os et io sous Windows)"; else
        echo "ÉCHEC win_os"; diff "$TMP/os.expected" "$TMP/os.out"; fails=$((fails + 1)); fi
fi

# Application graphique (--gui, module wingui) : la calculatrice d'exemple pilotée par des clics simulés
# (WM_COMMAND via la procédure de fenêtre : thunk Microsoft x64, registres non volatils vérifiés à chaque
# rappel), aussi avec ALEX_GC_STRESS=1 ; une exception non rattrapée dans un rappel est montrée par MessageBoxW.
CLICS="7 × 8 = + 2 , 5 = ÷ 0 = C 1 0 ← 9 ± ="
if "$ALEX_BIN" build --native --windows --gui $ARCH_FLAG examples/windows/calculatrice.al -o "$TMP/calc.exe" > "$TMP/build.err" 2>&1 || { cat "$TMP/build.err"; false; }; then
    if [ "$SIM" = 1 ]; then
        WINRUN_CLICKS="$CLICS" $WINRUN "$TMP/calc.exe" > "$TMP/calc.out" 2>&1
        rc=$?
        ALEX_GC_STRESS=1 WINRUN_CLICKS="$CLICS" $WINRUN "$TMP/calc.exe" > "$TMP/calc_stress.out" 2>&1
        if [ "$rc" -eq 0 ] && cmp -s $W/calculatrice_expected.txt "$TMP/calc.out" && cmp -s "$TMP/calc.out" "$TMP/calc_stress.out"; then
            echo "ok    calculatrice (interface graphique, $(wc -l < "$TMP/calc.out") clics, GC stress)"
        else
            echo "ÉCHEC calculatrice (code $rc)"; diff $W/calculatrice_expected.txt "$TMP/calc.out" | head; fails=$((fails + 1))
        fi
    else
        echo "--    calculatrice : clics simulés sautés (WINRUN_SIM=1 requis)"
    fi
    "$TMP/pe_check" "$TMP/calc.exe" $PEK gui > "$TMP/pe.txt"
    gui_ok() { head -1 "$TMP/pe.txt" | grep -q '^ok' && grep -q 'dll=.*user32.dll' "$TMP/pe.txt" && grep -q 'ressources=oui' "$TMP/pe.txt"; }
    if gui_ok; then
        echo "ok    PE graphique (sous-système 2, user32, manifeste)"
    else
        echo "ÉCHEC PE graphique"; fails=$((fails + 1))
    fi
fi
if "$ALEX_BIN" build --native --windows --gui $ARCH_FLAG $W/win_gui_err.al -o "$TMP/gui_err.exe" > /dev/null 2>&1 && [ "$SIM" != 1 ]; then
    echo "--    erreur dans un rappel : clic simulé sauté (WINRUN_SIM=1 requis)"
elif [ -f "$TMP/gui_err.exe" ]; then
    WINRUN_CLICKS="Boum" $WINRUN "$TMP/gui_err.exe" > "$TMP/gui_err.out" 2>&1
    rc=$?
    if [ "$rc" -eq 1 ] && cmp -s $W/win_gui_err_expected.txt "$TMP/gui_err.out"; then echo "ok    erreur dans un rappel (MessageBoxW, code 1)"; else
        echo "ÉCHEC erreur dans un rappel (code $rc)"; diff $W/win_gui_err_expected.txt "$TMP/gui_err.out"; fails=$((fails + 1)); fi
else
    echo "ÉCHEC win_gui_err : compilation"; fails=$((fails + 1))
fi

# Structure du PE : sous-système console, imports de kernel32 seulement par nom, pas de section RWX,
# DYNAMIC_BASE + NX_COMPAT, relocations bien formées (tests/native/pe_check.al).
if [ -f "$TMP/win_os.exe" ]; then
    if "$TMP/pe_check" "$TMP/win_os.exe" $PEK console > "$TMP/pe.txt" && grep -q 'dll=kernel32.dll' "$TMP/pe.txt" \
        && grep -q 'fonctions=.*ExitProcess' "$TMP/pe.txt"; then
        echo "ok    structure PE32+ $WIN_ARCH ($(head -1 "$TMP/pe.txt" | cut -c7-))"
    else
        echo "ÉCHEC structure PE32+ $WIN_ARCH"; cat "$TMP/pe.txt"; fails=$((fails + 1))
    fi
fi

out=$("$ALEX_BIN" build --native --windows $ARCH_FLAG $W/win_posix.al -o "$TMP/win_posix.exe" 2>&1)
if echo "$out" | grep -q "module 'posix' : appels système POSIX : indisponible avec --windows" && [ ! -e "$TMP/win_posix.exe" ]; then
    echo "ok    refus de posix"
else
    echo "ÉCHEC refus de posix"; echo "$out"; fails=$((fails + 1))
fi

SUITE=test-native-windows
[ "$WIN_ARCH" = arm64 ] && SUITE="test-native-windows (ARM64)"
if [ "$fails" -ne 0 ]; then echo "$SUITE : $fails échec(s)"; exit 1; fi
echo "$SUITE : toutes les vérifications passent"
