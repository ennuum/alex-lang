#!/bin/sh
# Types graduels : erreurs de compilation attendues + programme typé + vérifications runtime.
# Lancer DEPUIS LA RACINE DU PROJET.
ALEX_BIN=${ALEX_BIN:-./alex}
out=$("$ALEX_BIN" run tests/lang/types_errors_fixture.al 2>&1 | sed "s|$(pwd)/||g")
if [ "$out" != "$(cat tests/lang/types_errors_expected.txt)" ]; then
    echo "test-types : ÉCHEC (diagnostics statiques)"
    echo "--- obtenu"; echo "$out"; echo "--- attendu"; cat tests/lang/types_errors_expected.txt
    exit 1
fi
echo "test-types (diagnostics statiques) : OK"
out=$("$ALEX_BIN" check tests/lang/types_errors_fixture.al 2>&1); rc=$?
[ "$rc" -ne 0 ] || { echo "test-types : ÉCHEC (alex check doit échouer)"; exit 1; }
"$ALEX_BIN" check tests/lang/test_types.al >/dev/null 2>&1 || { echo "test-types : ÉCHEC (alex check)"; exit 1; }
echo "test-types (alex check) : OK"
"$ALEX_BIN" run tests/lang/test_types.al || exit 1
