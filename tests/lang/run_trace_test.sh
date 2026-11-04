#!/bin/sh
# Trace de pile d'une exception non capturée, affichée par le CLI (stderr, code de sortie 1).
# Lancer DEPUIS LA RACINE DU PROJET (les chemins affichés sont relatifs au dossier courant).
ALEX_BIN=${ALEX_BIN:-./alex}
out=$("$ALEX_BIN" run tests/lang/trace_fixture.al 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && [ "$out" = "$(cat tests/lang/trace_expected.txt)" ]; then
    echo "test-trace : OK"
else
    echo "test-trace : ÉCHEC (code $rc)"; echo "--- obtenu"; echo "$out"
    echo "--- attendu"; cat tests/lang/trace_expected.txt
    exit 1
fi
out=$(ALEX_NO_TRACE=1 "$ALEX_BIN" run tests/lang/trace_fixture.al 2>&1)
if [ "$out" != "ZeroDivisionError: division entière par zéro (int // 0)" ]; then
    echo "test-trace : ÉCHEC (ALEX_NO_TRACE=1 doit masquer la trace)"; echo "$out"; exit 1
fi
echo "test-trace (ALEX_NO_TRACE) : OK"

# Module importé : son fichier doit apparaître dans la trace, à la compilation comme depuis le cache .albc.
for pass in compilation cache; do
    out=$("$ALEX_BIN" run tests/lang/trace_import_fixture.al 2>&1)
    case "$out" in
        *"tests/lang/trace_lib.al:4, dans fail"*) echo "test-trace (module importé, $pass) : OK" ;;
        *) echo "test-trace : ÉCHEC (module importé, $pass)"; echo "$out"; exit 1 ;;
    esac
done
