#!/bin/bash
EXE=$1; W=$2
rm -rf $W; mkdir -p $W; cd $W
export ALEX_REGISTRY=$W/reg
run() { echo "\$ $*"; "$EXE" "$@" 2>&1; echo "rc=$?"; }
mkdir geo util app
(cd geo && run pkg init geometrie && echo 'x := 1' > geometrie.al && run pkg publish && sed -i 's/0.1.0/0.2.0/' alex.toml && run pkg publish)
(cd util && run pkg init util && echo 'x := 1' > util.al && printf '# commentaire\n' >> alex.toml && run pkg add geometrie "~0.2" && cat alex.toml)
(cd app && run pkg init app && run pkg add util path:../util && run pkg list && cat alex.lock && run pkg add geometrie "0.1" ; run pkg add geometrie ">=0.1" && cat alex.toml && run pkg list && run pkg remove util && run pkg list && cat alex.lock)
(cd app && printf '[package]\nname = "app"\nversion = "x"\n' > alex.toml && run pkg list)
(cd app && printf '[package]\nname = "app"\nversion = "1.0.0"\nalex = ">=99.0"\n' > alex.toml && run pkg install)
