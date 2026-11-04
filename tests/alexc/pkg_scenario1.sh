#!/bin/bash
# usage: pkgtest.sh EXE WORKDIR
EXE=$1; W=$2
rm -rf $W; mkdir -p $W; cd $W
export ALEX_REGISTRY=$W/reg
run() { echo "\$ $*"; "$EXE" "$@" 2>&1; echo "rc=$?"; }
mkdir geo util app
(cd geo && run pkg init geometrie && printf 'func aire(r):\n    return 3 * r * r\n' > geometrie.al && run pkg publish)
(cd geo && sed -i 's/0.1.0/0.2.0/' alex.toml && run pkg publish && run pkg publish)
(cd geo && sed -i 's/0.2.0/1.0.0-rc.1/' alex.toml && run pkg publish)
(cd util && run pkg init util && echo 'x := 1' > util.al && run pkg add geometrie "^0.1")
(cd app && run pkg init app && run pkg add geometrie && run pkg add util path:../util && run pkg list && cat alex.toml && cat alex.lock && run pkg verify && run pkg install --locked && run pkg update && run pkg update nope && run pkg remove util && run pkg list && run pkg remove nope && run pkg add bad-name && run pkg add zzz)
(cd app && echo "modif" >> alex_packages/geometrie/geometrie.al && run pkg verify)
(cd app && run pkg install && run pkg verify)
run pkg
run pkg frob
(cd app && run pkg init app)
