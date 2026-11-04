#!/bin/sh
# Installeur Windows : assemblage du paquet (avec build/alex.exe et build/alexvm.exe de `make alex-windows`, ou des
# exécutables factices s'ils n'existent pas) et contrôles statiques des scripts d'installation (PATH,
# désinstallation, version). L'exécution réelle exige Windows.
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1"; fail=1; }
chk() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
# Le script écrit dans <racine>/dist ; exécutables factices si la chaîne Windows n'a pas été construite.
created=""
for f in alex.exe alexvm.exe; do
    [ -f build/$f ] || { mkdir -p build; printf MZ > build/$f; created="$created build/$f"; }
done
before=$(ls dist/*.zip 2>/dev/null | sort)
sh tools/package-windows.sh windows-x86_64 >"$D/log" 2>&1
chk "package-windows.sh réussit" "[ \$? -eq 0 ] || grep -q 'archive zip' $D/log"
Z=$(ls -t dist/alex-*-windows-x86_64.zip 2>/dev/null | head -1)
chk "archive zip nommée d'après la version" "[ -n \"$Z\" ]"
if [ -n "$Z" ]; then
    python3 -I - "$Z" <<'PY' && ok "contenu de l'archive" || ko "contenu de l'archive"
import sys, zipfile, re
z = zipfile.ZipFile(sys.argv[1]); n = z.namelist()
root = n[0].split('/')[0]
assert re.match(r'alex-\d+\.\d+\.\d+(-beta\.\d+)?-windows-x86_64$', root), root
for need in ("bin/alex.exe", "bin/alexvm.exe", "lib/alex/stdlib/core/core.al", "lib/alex/runtime/vm/vm.al",
             "lib/alex/runtime/alex/native/dyn_w32.al", "lib/alex/templates", "install.cmd", "install.ps1", "alex.ico", "VERSION.txt"):
    assert any(x.startswith(root + "/" + need) for x in n), need
assert z.read(root + "/VERSION.txt").decode().strip() == root[len("alex-"):-len("-windows-x86_64")]
assert not any(x.endswith((".albc", ".meta", ".cpp", ".hpp", ".h", ".c")) for x in n), "caches ou sources C/C++ dans l'archive"
PY
fi
chk "install.ps1 : PATH ajouté sans doublon" "grep -q 'function Add-ToPath' tools/windows/install.ps1 && grep -q 'Normalize-Dir' tools/windows/install.ps1"
chk "install.ps1 : valeur REG_EXPAND_SZ conservée" "grep -q 'DoNotExpandEnvironmentNames' tools/windows/install.ps1 && grep -q 'ExpandString' tools/windows/install.ps1"
chk "install.ps1 : diffusion WM_SETTINGCHANGE" "grep -q 'SendMessageTimeout' tools/windows/install.ps1"
chk "install.ps1 : désinstallation retire le PATH" "grep -q 'Remove-FromPath' tools/windows/install.ps1"
chk "installeur SDK sans ALEX Studio (projet séparé)" "! grep -q -i 'alex-studio' tools/windows/alex.iss tools/windows/install.ps1"
chk "install.ps1 : BOM UTF-8" "[ \"\$(head -c3 tools/windows/install.ps1 | od -An -tx1 | tr -d ' ')\" = efbbbf ]"
chk "install.cmd : fins de ligne CRLF" "grep -q \"\$(printf '\\r')\" tools/windows/install.cmd"
chk "alex.iss : PATH à l'installation et à la désinstallation" "grep -q 'AddToPath(ExpandConstant' tools/windows/alex.iss && grep -q 'usPostUninstall' tools/windows/alex.iss && grep -q 'ChangesEnvironment=yes' tools/windows/alex.iss"
chk "alex.iss : tâche PATH cochée par défaut" "grep -q 'Name: \"addtopath\"' tools/windows/alex.iss && ! grep 'Name: \"addtopath\"' tools/windows/alex.iss | grep -q unchecked"
chk "disposition compatible avec locate_stdlib()" "grep -q '\"lib/alex\"), \"stdlib\")' src/resolver/resolver.al"
[ -n "$created" ] && rm -f $created
for f in dist/alex-*-windows-x86_64.zip; do case "$before" in *"$f"*) ;; *) rm -f "$f" ;; esac; done
rmdir dist 2>/dev/null
[ $fail -eq 0 ] && echo "installeur Windows : OK" || echo "installeur Windows : ÉCHEC"
exit $fail
