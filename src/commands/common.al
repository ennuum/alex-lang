# ALEX — commands.common
#
# Outils partagés par les commandes de `alexc`, la chaîne d'outils ALEX écrite en ALEX (src/alexc.al) :
# chemins de l'exécutable, de la machine virtuelle et de la bibliothèque standard, écriture sur stderr, JSON
# compact dans l'ordre d'insertion (comme alex::tooling::Json du C++), parcours de dossiers.
#
#   use commands.common as cc
#   cc.err("message\n")
#   cc.json_dump({"event": "file", "line": 3})
#
# Erreurs : celles d'io et d'os.

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use io as _io
use json as _json
use _native_cli as _cli
use commands.bundle as _sdk

func err(text):
    _cli.write_err(text)

func out(text):
    _cli.write_out(text)

func flush():
    _cli.flush()

func ends_with(s, suffix):
    return len(s) >= len(suffix) and _s.substring(s, len(s) - len(suffix), len(s)) == suffix

func starts_with(s, prefix):
    return _s.starts_with(s, prefix)

# Chemin de l'exécutable courant (alexc), "" s'il est inconnu (sous Windows, le runtime répond pour
# « /proc/self/exe » par GetModuleFileNameW).
func self_path():
    try:
        return _os.realpath("/proc/self/exe")
    catch e:
        return ""

func _vm_name():
    return "alexvm.exe" if _os.platform() == "windows" else "alexvm"

# Machine virtuelle : $ALEX_VM, sinon alexvm (alexvm.exe sous Windows) à côté d'alexc.
func vm_path():
    v := _os.getenv("ALEX_VM")
    if v != null and v != "":
        return v
    return _os.join(_os.dirname(self_path()), _vm_name())

# Bibliothèque standard (comme l'alex de référence : $ALEX_STDLIB, ./stdlib, à côté de l'exécutable,
# ../lib/alex/stdlib), plus ../stdlib (alexc construit dans build/ d'un dépôt), enfin le SDK embarqué dans
# l'exécutable (commands.bundle, extrait une fois dans un cache), qui fournit aussi la VM si aucune n'est à
# côté d'alexc. Fixe ALEX_STDLIB (et ALEX_VM) pour le compilateur et les processus fils.
func stdlib_root():
    env := _os.getenv("ALEX_STDLIB")
    if env != null and env != "":
        return env
    dir := _os.dirname(self_path())
    for c in ["./stdlib", _os.join(dir, "stdlib"), _os.join(dir, "../lib/alex/stdlib"), _os.join(dir, "../stdlib")]:
        if _os.isfile(_os.join(c, "core/core.al")):
            if c != "./stdlib":
                _os.setenv("ALEX_STDLIB", _os.normalize(c))
                return _os.normalize(c)
            return "stdlib"
    sdk := _sdk.extract(self_path())
    if sdk != "":
        root := _os.join(sdk, "stdlib")
        _os.setenv("ALEX_STDLIB", root)
        vm := _os.join(sdk, _vm_name())
        if not _os.isfile(vm_path()) and _os.isfile(vm):
            _os.setenv("ALEX_VM", vm)
        return root
    return "stdlib"

# Chemin d'un tube nommé entre alexc et la VM (repl, debug) : fichier FIFO `dir/nom` sous POSIX, tube nommé
# Windows \\.\pipe\alexc-<pid>-<nom> sous Windows (ni fichier ni dossier à créer ; voir _native_fd).
func fifo_path(dir, name):
    if _os.platform() == "windows":
        return "\\\\.\\pipe\\alexc-" + str(_os.pid()) + "-" + name
    return dir + "/" + name

func trim(s):
    return _s.trim(s)

# Lignes d'un texte (« \r » final de chaque ligne retiré), comme splitLines du service de langage C++ : la
# dernière ligne (éventuellement vide) est toujours présente.
func split_lines(text):
    out := []
    for l in _s.split(text, "\n"):
        if _s.ends_with(l, "\r"):
            l = _s.substring(l, 0, len(l) - 1)
        append(out, l)
    return out

# JSON compact, clés dans l'ordre d'insertion (alex::tooling::Json::dump).
func json_dump(v):
    if type(v) == "float" and v == to_int(v) and v < 9000000000000000.0 and v > -9000000000000000.0:
        return str(to_int(v))
    t := type(v)
    if t == "list" or t == "tuple":
        return "[" + _s.join(",", [json_dump(x) for x in v]) + "]"
    if t == "dict":
        parts := []
        for k in v:
            append(parts, json_string(str(k)) + ":" + json_dump(v[k]))
        return "{" + _s.join(",", parts) + "}"
    if t == "str":
        return json_string(v)
    return _json.stringify(v, null, false)

# Chaîne JSON (alex::tooling::jsonEscape) : UTF-8 valide garanti, octet invalide -> U+FFFD.
func json_string(s):
    b := _s.byte_unpack(s)
    n := len(b)
    out := [34]
    hx := "0123456789abcdef"
    i := 0
    while i < n:
        c := b[i]
        if c >= 128:
            ln := 2 if (c & 224) == 192 else (3 if (c & 240) == 224 else (4 if (c & 248) == 240 else 0))
            ok := ln != 0 and i + ln <= n and c >= 194
            k := 1
            while ok and k < ln:
                if (b[i + k] & 192) != 128:
                    ok = false
                k += 1
            if ok:
                k = 0
                while k < ln:
                    append(out, b[i + k])
                    k += 1
                i += ln
            else:
                append(out, 239)
                append(out, 191)
                append(out, 189)
                i += 1
            continue
        if c == 34:
            append(out, 92)
            append(out, 34)
        elif c == 92:
            append(out, 92)
            append(out, 92)
        elif c == 10:
            append(out, 92)
            append(out, 110)
        elif c == 13:
            append(out, 92)
            append(out, 114)
        elif c == 9:
            append(out, 92)
            append(out, 116)
        elif c == 8:
            append(out, 92)
            append(out, 98)
        elif c == 12:
            append(out, 92)
            append(out, 102)
        elif c < 32:
            for x in [92, 117, 48, 48]:
                append(out, x)
            append(out, _s.byte_at(hx, c >> 4))
            append(out, _s.byte_at(hx, c & 15))
        else:
            append(out, c)
        i += 1
    append(out, 34)
    return _s.byte_pack(out)

func json_parse(text):
    return _json.parse(text)

# Fichiers .al (ou ceux qui satisfont `keep(nom)`) sous `root`, récursivement, en ignorant alex_packages, build,
# dist, node_modules et les dossiers cachés. Ordre du parcours : celui de list_dir.
func walk_files(root, keep, skip_node_modules=false):
    out := []
    _walk(root, keep, skip_node_modules, out)
    return out

func _walk(dir, keep, skip_nm, out):
    names := []
    try:
        names = _os.list_dir(dir)
    catch e:
        return
    for n in names:
        p := _os.join(dir, n)
        if _os.isdir(p) and not _os.islink(p):
            if n == "alex_packages" or n == "build" or n == "dist" or (skip_nm and n == "node_modules") or (len(n) > 0 and n[0] == '.'):
                continue
            _walk(p, keep, skip_nm, out)
        elif keep(n):
            append(out, p)

# Tri de chaînes (ordre des octets, comme std::sort sur std::string) ; tri fusion stable.
func sort_strings(xs):
    return sort_by(xs, (a, b) => a < b)

func sort_by(xs, less):
    if len(xs) <= 1:
        return [x for x in xs]
    mid := len(xs) // 2
    l := sort_by(xs[0:mid], less)
    r := sort_by(xs[mid:len(xs)], less)
    out := []
    i := 0
    j := 0
    while i < len(l) and j < len(r):
        if less(r[j], l[i]):
            append(out, r[j])
            j += 1
        else:
            append(out, l[i])
            i += 1
    while i < len(l):
        append(out, l[i])
        i += 1
    while j < len(r):
        append(out, r[j])
        j += 1
    return out

func read_file(path):
    return _io.read_file(path)

func write_file(path, text):
    _io.write_file(path, text)
