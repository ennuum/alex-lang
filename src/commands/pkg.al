# ALEX — commands.pkg
#
# `alexc pkg init <nom> | add <nom> [contrainte|path:dossier] | remove <nom> | install [--locked] |
# update [nom...] | list | publish | verify [--registry <dossier>] [--dir <projet>]` : gestionnaire de paquets,
# comme alex::pkg (PackageManager.cpp, Manifest.cpp, Semver.cpp) — manifeste alex.toml, dépendances installées à
# plat dans alex_packages/, verrou alex.lock (versions, sources, empreintes SHA-256), registre LOCAL
# <registre>/<nom>/<version>/ alimenté par `publish`, résolution transitive (plus haute version compatible).
#
#   use commands.pkg as cp
#   v := cp.parse_version("1.2.3-rc.1")          # [1, 2, 3, "rc.1", ""] ou null
#   cp.satisfies(v, cp.parse_constraint("^1.2"))
#   code := cp.run(["install"])
#
# Erreurs : PackageError (manifeste invalide, résolution impossible, registre altéré...).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use io as _io
use crypto as _crypto
use commands.common as cc

func _fail(msg):
    raise("PackageError", msg)

# ------------------------------------------------------------------------------------------------ versions

func _is_digit(c):
    return c >= '0' and c <= '9'

func _is_alnum(c):
    return _is_digit(c) or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')

func _is_numeric(s):
    if len(s) == 0:
        return false
    for c in s:
        if not _is_digit(c):
            return false
    return true

func _valid_ids(s, is_pre):
    if len(s) == 0:
        return false
    for id in _s.split(s, "."):
        if len(id) == 0:
            return false
        for c in id:
            if not (_is_alnum(c) or c == '-'):
                return false
        if is_pre and _is_numeric(id) and len(id) > 1 and id[0] == '0':
            return false
    return true

func _parse_parts(s, min_parts, allow_suffix):
    parts := [0, 0, 0]
    pos := 0
    n := 0
    while n < 3:
        start := pos
        while pos < len(s) and _is_digit(s[pos]):
            pos += 1
        if pos == start or pos - start > 9:
            return null
        parts[n] = to_int(_s.substring(s, start, pos))
        n += 1
        if pos < len(s) and s[pos] == '.':
            pos += 1
            continue
        break
    if n < min_parts:
        return null
    v := [parts[0], parts[1], parts[2], "", ""]
    if pos < len(s):
        if not allow_suffix or n != 3:
            return null
        rest := _s.substring(s, pos, len(s))
        plus := _s.find(rest, "+")
        has_build := plus >= 0
        head := _s.substring(rest, 0, plus) if has_build else rest
        build := _s.substring(rest, plus + 1, len(rest)) if has_build else ""
        pre := ""
        if len(head) > 0:
            if head[0] != '-':
                return null
            pre = _s.substring(head, 1, len(head))
            if not _valid_ids(pre, true):
                return null
        if has_build and not _valid_ids(build, false):
            return null
        v[3] = pre
        v[4] = build
    return v

func parse_version(s):
    return _parse_parts(s, 3, true)

func version_str(v):
    s := str(v[0]) + "." + str(v[1]) + "." + str(v[2])
    if v[3] != "":
        s += "-" + v[3]
    if v[4] != "":
        s += "+" + v[4]
    return s

func _cmp_str(a, b):
    return -1 if a < b else (1 if a > b else 0)

func _compare_pre(a, b):
    if a == "" and b == "":
        return 0
    if a == "":
        return 1
    if b == "":
        return -1
    pa := _s.split(a, ".")
    pb := _s.split(b, ".")
    i := 0
    while i < len(pa) and i < len(pb):
        na := _is_numeric(pa[i])
        nb := _is_numeric(pb[i])
        if na and nb:
            if len(pa[i]) != len(pb[i]):
                return -1 if len(pa[i]) < len(pb[i]) else 1
            c := _cmp_str(pa[i], pb[i])
            if c != 0:
                return c
        elif na != nb:
            return -1 if na else 1
        else:
            c := _cmp_str(pa[i], pb[i])
            if c != 0:
                return c
        i += 1
    if len(pa) != len(pb):
        return -1 if len(pa) < len(pb) else 1
    return 0

func compare_versions(a, b):
    k := 0
    while k < 3:
        if a[k] != b[k]:
            return -1 if a[k] < b[k] else 1
        k += 1
    return _compare_pre(a[3], b[3])

# Contrainte : [genre, version] ; genre « any », « exact », « caret », « tilde », « ge ».
func parse_constraint(raw):
    s := ""
    for c in raw:
        if c != ' ' and c != '\t' and c != '\n' and c != '\r':
            s += str(c)
    if s == "*":
        return ["any", [0, 0, 0, "", ""]]
    kind := "caret"
    rest := s
    if _s.starts_with(s, ">="):
        kind = "ge"
        rest = _s.substring(s, 2, len(s))
    elif _s.starts_with(s, "^"):
        rest = _s.substring(s, 1, len(s))
    elif _s.starts_with(s, "~"):
        kind = "tilde"
        rest = _s.substring(s, 1, len(s))
    elif _s.starts_with(s, "="):
        kind = "exact"
        rest = _s.substring(s, 1, len(s))
    v := _parse_parts(rest, 1, true)
    if v == null:
        return null
    return [kind, v]

func _caret_upper(v):
    if v[0] > 0:
        return [v[0] + 1, 0, 0, "", ""]
    if v[1] > 0:
        return [0, v[1] + 1, 0, "", ""]
    return [0, 0, v[2] + 1, "", ""]

func _ordered(v, c):
    k := c[0]
    cv := c[1]
    if k == "any":
        return true
    if k == "exact":
        return compare_versions(v, cv) == 0
    if k == "ge":
        return compare_versions(v, cv) >= 0
    if k == "caret":
        return compare_versions(v, cv) >= 0 and compare_versions(v, _caret_upper(cv)) < 0
    return compare_versions(v, cv) >= 0 and compare_versions(v, [cv[0], cv[1] + 1, 0, "", ""]) < 0

func satisfies(v, c):
    if c[0] == "any":
        return v[3] == ""
    if v[3] != "":
        cv := c[1]
        if cv[3] == "" or cv[0] != v[0] or cv[1] != v[1] or cv[2] != v[2]:
            return false
    return _ordered(v, c)

# ------------------------------------------------------------------------------------------------ manifeste

func _trim(s):
    return _s.trim(s)

func _strip_comment(line):
    q := false
    i := 0
    for c in line:
        if c == '"':
            q = not q
        elif c == '#' and not q:
            return _s.substring(line, 0, i)
        i += 1
    return line

func _comment_start(line):
    q := false
    i := 0
    for c in line:
        if c == '"':
            q = not q
        elif c == '#' and not q:
            return i
        i += 1
    return -1

func _mfail(origin, line, msg):
    _fail(origin + ":" + str(line) + ": " + msg)

func _parse_quoted(v, origin, line):
    if len(v) < 2 or v[0] != '"' or v[len(v) - 1] != '"' or _s.find(_s.substring(v, 1, len(v)), "\"") != len(v) - 2:
        _mfail(origin, line, "chaîne entre guillemets attendue, obtenu `" + v + "`")
    return _s.substring(v, 1, len(v) - 1)

func _parse_inline_table(v, origin, line):
    if len(v) < 2 or v[len(v) - 1] != '}':
        _mfail(origin, line, "table en ligne mal fermée")
    inner := _s.substring(v, 1, len(v) - 1)
    out := {}
    items := []
    item := ""
    q := false
    for c in inner:
        if c == '"':
            q = not q
        if c == ',' and not q:
            append(items, item)
            item = ""
        else:
            item += str(c)
    append(items, item)
    for raw in items:
        it := _trim(raw)
        if it == "":
            continue
        eq := _s.find(it, "=")
        if eq < 0:
            _mfail(origin, line, "`clé = \"valeur\"` attendu dans la table en ligne")
        out[_trim(_s.substring(it, 0, eq))] = _parse_quoted(_trim(_s.substring(it, eq + 1, len(it))), origin, line)
    return out

func is_valid_name(n):
    if len(n) == 0:
        return false
    c0 := n[0]
    if not ((c0 >= 'a' and c0 <= 'z') or (c0 >= 'A' and c0 <= 'Z') or c0 == '_'):
        return false
    for c in n:
        if not (_is_alnum(c) or c == '_'):
            return false
    return true

func _getlines(text):
    ls := _s.split(text, "\n")
    if len(ls) > 0 and ls[len(ls) - 1] == "":
        ls = ls[0:len(ls) - 1]
    return ls

# Manifeste : {name, version, description, entry, sources : [dossiers], alex, deps : [{name, is_path, path,
# constraint}]}. sources : dossiers de sources du projet (racines de modules : `use vues.principale` trouve
# src/vues/principale.al), ex. `sources = ["src"]`.
func parse_manifest(text, origin):
    m := {"name": "", "version": "", "description": "", "entry": "", "sources": [], "alex": "", "deps": []}
    section := ""
    no := 0
    for raw in _getlines(text):
        no += 1
        line := _trim(_strip_comment(raw))
        if line == "":
            continue
        if line[0] == '[':
            if line[len(line) - 1] != ']':
                _mfail(origin, no, "en-tête de section mal fermé")
            section = _trim(_s.substring(line, 1, len(line) - 1))
            if section != "package" and section != "dependencies":
                _mfail(origin, no, "section inconnue [" + section + "] (attendu : package, dependencies)")
            continue
        eq := _s.find(line, "=")
        if eq < 0:
            _mfail(origin, no, "`clé = valeur` attendu")
        key := _trim(_s.substring(line, 0, eq))
        value := _trim(_s.substring(line, eq + 1, len(line)))
        if section == "package":
            if key == "sources":
                m["sources"] = _parse_string_list(value, origin, no)
                continue
            s := _parse_quoted(value, origin, no)
            if key == "description":
                m["description"] = s
            elif key == "name":
                m["name"] = s
            elif key == "version":
                m["version"] = s
            elif key == "entry":
                m["entry"] = s
            elif key == "alex":
                if parse_constraint(s) == null:
                    _mfail(origin, no, "exigence de version du compilateur invalide `" + s + "` (ex. \">=1.2.0\", \"^1.0\", \"~1.4.2\")")
                m["alex"] = s
            else:
                _mfail(origin, no, "clé inconnue `" + key + "` dans [package]")
        elif section == "dependencies":
            if not is_valid_name(key):
                _mfail(origin, no, "nom de dépendance invalide `" + key + "` (identifiant ALEX attendu)")
            for d in m["deps"]:
                if d["name"] == key:
                    _mfail(origin, no, "dépendance `" + key + "` déclarée deux fois")
            d := {"name": key, "is_path": false, "path": "", "constraint": ""}
            if len(value) > 0 and value[0] == '{':
                t := _parse_inline_table(value, origin, no)
                for k in cc.sort_strings([x for x in t]):
                    if k != "path" and k != "version":
                        _mfail(origin, no, "clé inconnue `" + k + "` (attendu : path, version)")
                if "path" in t:
                    d["is_path"] = true
                    d["path"] = t["path"]
                if "version" in t:
                    d["constraint"] = t["version"]
                if not d["is_path"] and d["constraint"] == "":
                    _mfail(origin, no, "`" + key + "` : `path` ou `version` requis")
            else:
                d["constraint"] = _parse_quoted(value, origin, no)
            if d["constraint"] != "" and parse_constraint(d["constraint"]) == null:
                _mfail(origin, no, "contrainte de version invalide `" + d["constraint"] + "`")
            append(m["deps"], d)
        else:
            _mfail(origin, no, "entrée hors de toute section")
    if m["name"] == "":
        _fail(origin + ": [package] name requis")
    if not is_valid_name(m["name"]):
        _fail(origin + ": nom de package invalide `" + m["name"] + "` (identifiant ALEX attendu : lettres, chiffres, _)")
    if m["version"] == "":
        _fail(origin + ": [package] version requise")
    if parse_version(m["version"]) == null:
        _fail(origin + ": version invalide `" + m["version"] + "` (attendu MAJOR.MINOR.PATCH)")
    return m

func dependency_toml(d):
    o := d["name"] + " = "
    if d["is_path"]:
        o += "{ path = \"" + d["path"] + "\""
        if d["constraint"] != "":
            o += ", version = \"" + d["constraint"] + "\""
        o += " }"
    else:
        o += "\"" + ("*" if d["constraint"] == "" else d["constraint"]) + "\""
    return o

# Liste de chaînes TOML (`["src", "lib"]`) ou chaîne seule (`"src"`).
func _parse_string_list(value, origin, no):
    v := _trim(value)
    if len(v) == 0 or v[0] != '[':
        return [_parse_quoted(v, origin, no)]
    if v[len(v) - 1] != ']':
        _mfail(origin, no, "liste mal fermée (attendu : [\"src\", ...])")
    out := []
    for part in _s.split(_s.substring(v, 1, len(v) - 1), ","):
        p := _trim(part)
        if p != "":
            append(out, _parse_quoted(p, origin, no))
    return out

func serialize_manifest(m):
    o := "[package]\nname = \"" + m["name"] + "\"\nversion = \"" + m["version"] + "\"\n"
    if "description" in m and m["description"] != "":
        o += "description = \"" + m["description"] + "\"\n"
    if m["entry"] != "":
        o += "entry = \"" + m["entry"] + "\"\n"
    if "sources" in m and len(m["sources"]) > 0:
        o += "sources = [" + _s.join(", ", ["\"" + x + "\"" for x in m["sources"]]) + "]\n"
    if m["alex"] != "":
        o += "alex = \"" + m["alex"] + "\"\n"
    o += "\n[dependencies]\n"
    for d in m["deps"]:
        o += dependency_toml(d) + "\n"
    return o

# Lignes [corps, fin de ligne] (« », « \n » ou « \r\n »).
func _split_eol(text):
    out := []
    pos := 0
    n := _s.byte_len(text)
    while pos < n:
        rest := _s.byte_slice(text, pos, n)
        nl := _s.byte_find(rest, "\n")
        if nl < 0:
            append(out, [rest, ""])
            pos = n
        else:
            body := _s.byte_slice(rest, 0, nl)
            eol := "\n"
            if _s.ends_with(body, "\r"):
                body = _s.substring(body, 0, len(body) - 1)
                eol = "\r\n"
            append(out, [body, eol])
            pos += nl + 1
    return out

func _join_eol(lines):
    return _s.join("", [l[0] + l[1] for l in lines])

func _key_of(body):
    code := _trim(_strip_comment(body))
    if code == "" or code[0] == '[':
        return null
    eq := _s.find(code, "=")
    if eq < 0:
        return null
    return _trim(_s.substring(code, 0, eq))

func _deps_range(lines):
    begin := -1
    end := len(lines)
    i := 0
    while i < len(lines):
        code := _trim(_strip_comment(lines[i][0]))
        if code != "" and code[0] == '[':
            if begin < 0:
                inner := _s.substring(code, 1, len(code) - 1) if len(code) >= 2 else ""
                if _trim(inner) == "dependencies":
                    begin = i + 1
            else:
                end = i
                break
        i += 1
    if begin < 0:
        return [-1, -1]
    return [begin, end]

func _default_eol(lines):
    for l in lines:
        if l[1] != "":
            return l[1]
    return "\n"

func _indent_of(body):
    i := 0
    while i < len(body) and (body[i] == ' ' or body[i] == '\t'):
        i += 1
    return _s.substring(body, 0, i)

func set_dependency_in_text(text, d, origin):
    lines := _split_eol(text)
    eol := _default_eol(lines)
    rg := _deps_range(lines)
    begin := rg[0]
    end := rg[1]
    nb := dependency_toml(d)
    if begin < 0:
        if len(lines) > 0 and lines[len(lines) - 1][1] == "":
            lines[len(lines) - 1][1] = eol
        if len(lines) > 0 and _trim(lines[len(lines) - 1][0]) != "":
            append(lines, ["", eol])
        append(lines, ["[dependencies]", eol])
        append(lines, [nb, eol])
    else:
        last := begin - 1
        found := -1
        i := begin
        while i < end:
            key := _key_of(lines[i][0])
            if key != null:
                last = i
                if key == d["name"]:
                    found = i
                    break
            i += 1
        if found >= 0:
            body := lines[found][0]
            cs := _comment_start(body)
            if cs >= 0:
                ws := cs
                while ws > 0 and (body[ws - 1] == ' ' or body[ws - 1] == '\t'):
                    ws -= 1
                lines[found][0] = _indent_of(body) + nb + _s.substring(body, ws, len(body))
            else:
                lines[found][0] = _indent_of(body) + nb
        else:
            at := last + 1
            if last >= begin and lines[last][1] == "":
                lines[last][1] = eol
            if at >= len(lines):
                if len(lines) > 0 and lines[len(lines) - 1][1] == "":
                    lines[len(lines) - 1][1] = eol
                append(lines, [nb, eol])
            else:
                lines = lines[0:at] + [[nb, eol]] + lines[at:len(lines)]
    result := _join_eol(lines)
    parse_manifest(result, origin)
    return result

func remove_dependency_from_text(text, name, origin):
    lines := _split_eol(text)
    rg := _deps_range(lines)
    if rg[0] < 0:
        return null
    i := rg[0]
    while i < rg[1]:
        key := _key_of(lines[i][0])
        if key != null and key == name:
            result := _join_eol(lines[0:i] + lines[i + 1:len(lines)])
            parse_manifest(result, origin)
            return result
        i += 1
    return null

# ------------------------------------------------------------------------------------------------ gestionnaire

func _semver():
    return _os.alex_build()["version"]

func _is_beta():
    return _os.alex_build()["channel"] == "beta"

func compiler_compatible(m):
    if m["alex"] == "":
        return true
    try:
        return _os.alex_satisfies(m["alex"])
    catch e:
        return false

func check_compiler_requirement(m, origin):
    if compiler_compatible(m):
        return
    _fail(origin + " : le package `" + m["name"] + "` exige le compilateur ALEX " + m["alex"] + ", or ce compilateur est en version " +
          _semver() + (" (bêta)" if _is_beta() else "") + " — mettez alex à jour (alex --version)")

func _pj(a, b):
    if a == "":
        return b
    if _s.ends_with(a, "/"):
        return a + b
    return a + "/" + b

func _read(p):
    if not _os.isfile(p):
        _fail("impossible de lire '" + p + "'")
    return _io.read_file(p)

func _write(p, text):
    try:
        _io.write_file(p, text)
    catch e:
        _fail("impossible d'écrire '" + p + "'")

func _excluded(rel):
    parts := _s.split(rel, "/")
    for p in parts:
        if p == "alex_packages" or p == ".git":
            return true
    name := parts[len(parts) - 1]
    if name == "alex.lock":
        return true
    return _s.ends_with(name, ".albc") or _s.ends_with(name, ".al.meta")

func _list_files(dir):
    out := []
    if not _os.isdir(dir):
        return out
    _walk(dir, "", out)
    return cc.sort_strings(out)

func _walk(dir, rel, out):
    names := []
    try:
        names = _os.list_dir(_pj(dir, rel) if rel != "" else dir)
    catch e:
        return
    for n in names:
        r := n if rel == "" else rel + "/" + n
        p := _pj(dir, r)
        if _os.isdir(p):
            _walk(dir, r, out)
        elif _os.isfile(p) and not _excluded(r):
            append(out, r)

func _copy_tree(src, dst):
    for rel in _list_files(src):
        target := _pj(dst, rel)
        _os.mkdir_all(_os.dirname(target))
        _io.write_bytes(target, _io.read_bytes(_pj(src, rel)))
    _os.mkdir_all(dst)

func _rmtree(p):
    try:
        if _os.isdir(p) and not _os.islink(p):
            for n in _os.list_dir(p):
                _rmtree(_pj(p, n))
            _os.rmdir(p)
        elif _os.exists(p) or _os.islink(p):
            _os.remove(p)
    catch e:
        pass

func _utf8(s):
    return _s.byte_unpack(s)

func hash_directory(dir):
    data := []
    for rel in _list_files(dir):
        for b in _utf8(rel):
            append(data, b)
        append(data, 0)
        for b in _io.read_bytes(_pj(dir, rel)):
            append(data, b)
        append(data, 0)
    return "sha256:" + _crypto.sha256(data)

func hash_directory_fnv1a(dir):
    # FNV-1a 64 bits (multiplication modulo 2^64 par morceaux de 32 bits)
    lo := 2216829733
    hi := 3421674724
    feed := []
    for rel in _list_files(dir):
        for b in _utf8(rel):
            append(feed, b)
        append(feed, 0)
        for b in _io.read_bytes(_pj(dir, rel)):
            append(feed, b)
        append(feed, 0)
    for b in feed:
        lo = lo ^ b
        # h * 1099511628211 = h * (2^40 + 435)
        nlo := lo * 435
        nhi := hi * 435 + (nlo >> 32) + ((lo << 8) & 4294967295)
        lo = nlo & 4294967295
        hi = nhi & 4294967295
    return "fnv1a64:" + _hex8(hi) + _hex8(lo)

func _hex8(x):
    digits := "0123456789abcdef"
    s := ""
    k := 0
    while k < 8:
        s = str(digits[x & 15]) + s
        x = x >> 4
        k += 1
    return s

func _hash_like(dir, ref):
    return hash_directory_fnv1a(dir) if _s.starts_with(ref, "fnv1a64:") else hash_directory(dir)

func _abs_norm(p):
    return _os.normalize(_os.absolute(p))

func _weakly_canonical(p):
    try:
        if _os.exists(p):
            return _os.realpath(p)
    catch e:
        pass
    return _abs_norm(p)

func _relative(path, base):
    a := [x for x in _s.split(path, "/") if x != ""]
    b := [x for x in _s.split(base, "/") if x != ""]
    i := 0
    while i < len(a) and i < len(b) and a[i] == b[i]:
        i += 1
    parts := []
    k := i
    while k < len(b):
        append(parts, "..")
        k += 1
    while i < len(a):
        append(parts, a[i])
        i += 1
    return "." if len(parts) == 0 else _s.join("/", parts)

class PackageManager:
    func init(project_dir, registry_dir):
        self.project = project_dir
        self.registry_dir = registry_dir

    func manifest_path():
        return _pj(self.project, "alex.toml")

    func lock_path():
        return _pj(self.project, "alex.lock")

    func packages_dir():
        return _pj(self.project, "alex_packages")

    func registry():
        if self.registry_dir != "":
            return self.registry_dir
        r := _os.getenv("ALEX_REGISTRY")
        if r != null and r != "":
            return r
        h := _os.getenv("HOME")
        if h != null and h != "":
            return _pj(_pj(h, ".alex"), "registry")
        return ".alex_registry"

    func load_root():
        if not _os.isfile(self.manifest_path()):
            _fail("aucun alex.toml dans '" + self.project + "' (créez-le avec `alexc pkg init <nom>`)")
        return parse_manifest(_read(self.manifest_path()), self.manifest_path())

    func read_lock():
        out := []
        if not _os.isfile(self.lock_path()):
            return out
        for line in _getlines(_read(self.lock_path())):
            if line == "[[package]]":
                append(out, {"name": "", "version": "", "source": "", "checksum": ""})
                continue
            eq := _s.find(line, " = \"")
            if eq < 0 or len(out) == 0 or len(line) == 0 or line[len(line) - 1] != '"':
                continue
            key := _s.substring(line, 0, eq)
            val := _s.substring(line, eq + 4, len(line) - 1)
            if key in out[len(out) - 1]:
                out[len(out) - 1][key] = val
        return out

    func registry_versions(name):
        out := []
        dir := _pj(self.registry(), name)
        if not _os.isdir(dir):
            return out
        for n in _os.list_dir(dir):
            p := _pj(dir, n)
            if not _os.isdir(p):
                continue
            v := parse_version(n)
            if v != null and _os.isfile(_pj(p, "alex.toml")):
                append(out, v)
        return out

    func pick(name, ds, pins):
        describe := _s.join(", ", [("*" if d["dep"]["constraint"] == "" else d["dep"]["constraint"]) + " (demandé par " + d["from"] + ")" for d in ds])
        have_path := false
        path_dir := ""
        for d in ds:
            if not d["dep"]["is_path"]:
                continue
            dir := _weakly_canonical(_pj(d["base"], d["dep"]["path"]))
            if not have_path:
                have_path = true
                path_dir = dir
            elif dir != path_dir:
                _fail("`" + name + "` est demandé depuis deux dossiers différents : " + path_dir + " et " + dir + " (demandé par " + d["from"] + ")")
        if have_path:
            mp := _pj(path_dir, "alex.toml")
            if not _os.isfile(mp):
                _fail("`" + name + "` : " + mp + " introuvable")
            m := parse_manifest(_read(mp), mp)
            if m["name"] != name:
                _fail("le dossier " + path_dir + " contient le package `" + m["name"] + "`, pas `" + name + "`")
            check_compiler_requirement(m, mp)
            v := parse_version(m["version"])
            if not self.check_all(v, ds):
                _fail("`" + name + "` (dossier local) est en version " + m["version"] + ", qui ne satisfait pas : " + describe)
            return {"version": v, "src": path_dir, "manifest": m, "is_path": true,
                    "source": "path:" + _relative(path_dir, _weakly_canonical(self.project))}
        versions := self.registry_versions(name)
        if len(versions) == 0:
            _fail("package `" + name + "` introuvable dans le registre '" + self.registry() + "' (demandé par " + ds[0]["from"] + ")")
        versions = cc.sort_by(versions, (a, b) => compare_versions(a, b) > 0)
        too_new := []
        pin := pins[name] if name in pins else null
        if pin != null:
            for v in versions:
                if compare_versions(v, pin) == 0 and self.check_all(v, ds) and self.compatible(name, v, too_new):
                    return self.take(name, v)
        for v in versions:
            if not self.check_all(v, ds):
                continue
            if not self.compatible(name, v, too_new):
                continue
            return self.take(name, v)
        avail := _s.join(", ", [version_str(v) for v in versions])
        if len(too_new) > 0:
            _fail("aucune version de `" + name + "` compatible avec ce compilateur (alex " + _semver() + ") ne satisfait : " + describe +
                  ". Versions trop récentes : " + _s.join(", ", too_new))
        _fail("aucune version de `" + name + "` ne satisfait : " + describe + ". Versions disponibles : " + avail)

    func check_all(v, ds):
        for d in ds:
            if d["dep"]["constraint"] == "":
                continue
            c := parse_constraint(d["dep"]["constraint"])
            if c != null and not satisfies(v, c):
                return false
        return true

    func compatible(name, v, too_new):
        mp := _pj(_pj(_pj(self.registry(), name), version_str(v)), "alex.toml")
        if not _os.isfile(mp):
            return true
        m := parse_manifest(_read(mp), mp)
        if compiler_compatible(m):
            return true
        append(too_new, version_str(v) + " (exige alex " + m["alex"] + ")")
        return false

    func take(name, v):
        dir := _pj(_pj(self.registry(), name), version_str(v))
        mp := _pj(dir, "alex.toml")
        return {"version": v, "src": _weakly_canonical(dir), "manifest": parse_manifest(_read(mp), mp), "is_path": false, "source": "registry"}

    func resolve(root, pins):
        chosen := {}
        project_abs := _weakly_canonical(self.project)
        it := 0
        while it < 100:
            demands := {}
            work := [{"dep": d, "from": root["name"], "base": project_abs} for d in root["deps"]]
            expanded := {}
            while len(work) > 0:
                d := work[len(work) - 1]
                work = work[0:len(work) - 1]
                nm := d["dep"]["name"]
                if nm == root["name"]:
                    _fail("le package `" + root["name"] + "` ne peut pas dépendre de lui-même (demandé par " + d["from"] + ")")
                if not (nm in demands):
                    demands[nm] = []
                append(demands[nm], d)
                if (nm in chosen) and not (nm in expanded):
                    expanded[nm] = true
                    for dd in chosen[nm]["manifest"]["deps"]:
                        append(work, {"dep": dd, "from": nm, "base": chosen[nm]["src"]})
            changed := false
            for name in cc.sort_strings([k for k in demands]):
                c := self.pick(name, demands[name], pins)
                if not (name in chosen) or compare_versions(chosen[name]["version"], c["version"]) != 0 or chosen[name]["src"] != c["src"]:
                    chosen[name] = c
                    changed = true
            nc := {}
            for name in chosen:
                if name in demands:
                    nc[name] = chosen[name]
                else:
                    changed = true
            chosen = nc
            if not changed:
                return chosen
            it += 1
        _fail("la résolution des dépendances ne converge pas (contraintes cycliques contradictoires ?)")

    func init_project(name):
        if not is_valid_name(name):
            _fail("nom de package invalide `" + name + "` (identifiant ALEX : lettres, chiffres, _)")
        if _os.exists(self.manifest_path()):
            _fail("alex.toml existe déjà dans '" + self.project + "'")
        m := {"name": name, "version": "0.1.0", "entry": "", "alex": ">=" + _semver(), "deps": []}
        _os.mkdir_all(self.project)
        _write(self.manifest_path(), serialize_manifest(m))
        print("Créé " + self.manifest_path())

    func run(mode, names):
        root := self.load_root()
        check_compiler_requirement(root, self.manifest_path())
        old := self.read_lock()
        if mode == "locked" and len(old) == 0:
            _fail("alex.lock absent : `install --locked` exige un verrou existant (lancez `alexc pkg install`)")
        pins := {}
        unpinned := {}
        for n in names:
            unpinned[n] = true
        if mode == "update":
            for n in names:
                known := false
                for e in old:
                    if e["name"] == n:
                        known = true
                if not known:
                    _fail("`" + n + "` n'est pas installé (absent de alex.lock) : rien à mettre à jour")
        if mode != "update" or len(names) > 0:
            for e in old:
                if e["source"] != "registry" or (e["name"] in unpinned):
                    continue
                v := parse_version(e["version"])
                if v != null:
                    pins[e["name"]] = v
        chosen := self.resolve(root, pins)
        names_sorted := cc.sort_strings([k for k in chosen])
        src_hash := {}
        for name in names_sorted:
            src_hash[name] = hash_directory(chosen[name]["src"])
        if mode != "update":
            for e in old:
                if not (e["name"] in chosen):
                    continue
                c := chosen[e["name"]]
                if e["source"] != "registry" or c["source"] != "registry":
                    continue
                if version_str(c["version"]) != e["version"]:
                    continue
                if _hash_like(c["src"], e["checksum"]) != e["checksum"]:
                    _fail("`" + e["name"] + " " + e["version"] + "` : le contenu du registre ne correspond plus à l'empreinte de alex.lock (" +
                          e["checksum"] + "). Le registre a été modifié depuis le verrouillage ; `alexc pkg update " + e["name"] +
                          "` pour accepter la nouvelle version du contenu")
        if mode == "locked":
            diffs := []
            by := {}
            for e in old:
                by[e["name"]] = e
            for name in names_sorted:
                c := chosen[name]
                vs := version_str(c["version"])
                if not (name in by):
                    append(diffs, name + " " + vs + " : absent de alex.lock")
                elif by[name]["version"] != vs:
                    append(diffs, name + " : alex.lock=" + by[name]["version"] + ", résolu=" + vs)
                elif by[name]["source"] != c["source"]:
                    append(diffs, name + " : source " + by[name]["source"] + " -> " + c["source"])
                elif _hash_like(c["src"], by[name]["checksum"]) != by[name]["checksum"]:
                    append(diffs, name + " : contenu différent de l'empreinte de alex.lock")
            for e in old:
                if not (e["name"] in chosen):
                    append(diffs, e["name"] + " " + e["version"] + " : dans alex.lock mais plus demandé")
            if len(diffs) > 0:
                _fail("alex.lock n'est plus à jour (lancez `alexc pkg install` pour le régénérer) :" + _s.join("", ["\n  - " + d for d in diffs]))
        pkg := self.packages_dir()
        _os.mkdir_all(pkg)
        old_by := {}
        for e in old:
            old_by[e["name"]] = e
        new_lock := []
        for name in names_sorted:
            c := chosen[name]
            dest := _pj(pkg, name)
            h := src_hash[name]
            vs := version_str(c["version"])
            note := ""
            if (name in old_by) and old_by[name]["version"] != vs:
                note = " [avant : " + old_by[name]["version"] + "]"
            if not _os.exists(dest) or hash_directory(dest) != h:
                _rmtree(dest)
                _copy_tree(c["src"], dest)
                print("  + " + name + " " + vs + " (" + c["source"] + ")" + note)
            else:
                print("  = " + name + " " + vs + " (déjà à jour)" + note)
            append(new_lock, {"name": name, "version": vs, "source": c["source"], "checksum": h})
        for e in old:
            if e["name"] in chosen:
                continue
            _rmtree(_pj(pkg, e["name"]))
            print("  - " + e["name"] + " " + e["version"] + " (retiré)")
        if mode == "locked":
            print(str(len(new_lock)) + " package(s) installé(s) depuis alex.lock (verrou inchangé)")
            return
        migrated := false
        for e in old:
            if _s.starts_with(e["checksum"], "fnv1a64:"):
                migrated = true
        lock := "# Généré par `alexc pkg install` — ne pas modifier à la main.\n"
        for e in new_lock:
            lock += "\n[[package]]\nname = \"" + e["name"] + "\"\nversion = \"" + e["version"] + "\"\nsource = \"" + e["source"] + "\"\nchecksum = \"" + e["checksum"] + "\"\n"
        _write(self.lock_path(), lock)
        if migrated:
            print("alex.lock migré des empreintes FNV-1a vers SHA-256")
        print(str(len(new_lock)) + " package(s) installé(s) dans " + pkg)

    func add(name, spec):
        if not is_valid_name(name):
            _fail("nom de package invalide `" + name + "`")
        self.load_root()
        original := _read(self.manifest_path())
        d := {"name": name, "is_path": false, "path": "", "constraint": ""}
        if _s.starts_with(spec, "path:"):
            d["is_path"] = true
            d["path"] = _s.substring(spec, 5, len(spec))
            if d["path"] == "":
                _fail("`path:` sans dossier")
        elif spec == "":
            versions := self.registry_versions(name)
            if len(versions) == 0:
                _fail("package `" + name + "` introuvable dans le registre '" + self.registry() + "'")
            usable := []
            for v in versions:
                mp := _pj(_pj(_pj(self.registry(), name), version_str(v)), "alex.toml")
                if not _os.isfile(mp) or compiler_compatible(parse_manifest(_read(mp), mp)):
                    append(usable, v)
            if len(usable) > 0:
                versions = usable
            stable := [v for v in versions if v[3] == ""]
            pool := stable if len(stable) > 0 else versions
            best := pool[0]
            for v in pool:
                if compare_versions(best, v) < 0:
                    best = v
            best = [best[0], best[1], best[2], best[3], ""]
            d["constraint"] = "^" + version_str(best)
        else:
            if parse_constraint(spec) == null:
                _fail("contrainte de version invalide `" + spec + "`")
            d["constraint"] = spec
        edited := set_dependency_in_text(original, d, self.manifest_path())
        _write(self.manifest_path(), edited)
        try:
            self.run("normal", [])
        catch e:
            _write(self.manifest_path(), original)
            raise(e.type, e.message)

    func remove(name):
        self.load_root()
        original := _read(self.manifest_path())
        edited := remove_dependency_from_text(original, name, self.manifest_path())
        if edited == null:
            _fail("`" + name + "` n'est pas une dépendance de ce projet")
        _write(self.manifest_path(), edited)
        try:
            self.run("normal", [])
        catch e:
            _write(self.manifest_path(), original)
            raise(e.type, e.message)

    func list():
        root := self.load_root()
        print(root["name"] + " " + root["version"])
        lock := self.read_lock()
        if len(lock) == 0:
            print("  (aucun package installé)")
            return
        direct := {}
        for d in root["deps"]:
            direct[d["name"]] = true
        for e in lock:
            print("  " + e["name"] + " " + e["version"] + " (" + e["source"] + ")" + ("" if e["name"] in direct else " [transitif]"))

    func publish():
        m := self.load_root()
        for d in m["deps"]:
            if d["is_path"]:
                _fail("un package publié ne peut pas avoir de dépendance `path` (`" + d["name"] + "`)")
        dest := _pj(_pj(self.registry(), m["name"]), m["version"])
        mine := parse_version(m["version"])
        for v in self.registry_versions(m["name"]):
            if compare_versions(v, mine) == 0:
                _fail(m["name"] + " " + m["version"] + " est déjà publié" + ("" if version_str(v) == m["version"] else " (comme " + version_str(v) + ")") +
                      " (les versions publiées sont immuables : incrémentez `version`)")
        if _os.exists(dest):
            _fail(m["name"] + " " + m["version"] + " est déjà publié (les versions publiées sont immuables : incrémentez `version`)")
        _copy_tree(self.project, dest)
        print("Publié " + m["name"] + " " + m["version"] + " -> " + dest)

    func verify():
        lock := self.read_lock()
        if len(lock) == 0:
            _fail("alex.lock absent ou vide (lancez `alexc pkg install`)")
        problems := []
        legacy := false
        for e in lock:
            dir := _pj(self.packages_dir(), e["name"])
            fnv := _s.starts_with(e["checksum"], "fnv1a64:")
            if not fnv and not _s.starts_with(e["checksum"], "sha256:"):
                append(problems, e["name"] + " : algorithme d'empreinte inconnu (`" + e["checksum"] + "`)")
            elif not _os.isdir(dir):
                append(problems, e["name"] + " : manquant dans alex_packages")
            elif _hash_like(dir, e["checksum"]) != e["checksum"]:
                append(problems, e["name"] + " : contenu modifié depuis l'installation")
            legacy = legacy or fnv
        if len(problems) > 0:
            _fail("vérification échouée :" + _s.join("", ["\n  - " + p for p in problems]))
        print(str(len(lock)) + " package(s) conformes à alex.lock")
        if legacy:
            print("note : alex.lock utilise encore des empreintes FNV-1a (non cryptographiques) ; `alexc pkg install` les migre vers SHA-256")

const _USAGE := "usage: alexc pkg init <nom> | add <nom> [contrainte|path:dossier] | remove <nom> |\n                install [--locked] | update [nom...] | list | publish | verify\n                [--registry <dossier>] [--dir <projet>]\n"

# Exigence `alex = "..."` du manifeste du dossier courant (vérifiée avant toute compilation).
func check_project_requirement():
    if not _os.isfile("alex.toml"):
        return
    m := parse_manifest(_io.read_file("alex.toml"), "alex.toml")
    check_compiler_requirement(m, "alex.toml")

func run(argv):
    project := "."
    registry := ""
    locked := false
    args := []
    i := 0
    while i < len(argv):
        a := argv[i]
        if a == "--locked":
            locked = true
        elif a == "--registry" and i + 1 < len(argv):
            i += 1
            registry = argv[i]
        elif a == "--dir" and i + 1 < len(argv):
            i += 1
            project = argv[i]
        else:
            append(args, a)
        i += 1
    if len(args) == 0:
        cc.err(_USAGE)
        return 1
    pm := PackageManager(project, registry)
    sub := args[0]
    if sub == "init" and len(args) == 2:
        pm.init_project(args[1])
    elif sub == "add" and (len(args) == 2 or len(args) == 3):
        pm.add(args[1], args[2] if len(args) == 3 else "")
    elif sub == "remove" and len(args) == 2:
        pm.remove(args[1])
    elif sub == "install" and len(args) == 1:
        pm.run("locked" if locked else "normal", [])
    elif sub == "update" and not locked:
        pm.run("update", args[1:len(args)])
    elif sub == "list" and len(args) == 1:
        pm.list()
    elif sub == "publish" and len(args) == 1:
        pm.publish()
    elif sub == "verify" and len(args) == 1:
        pm.verify()
    else:
        cc.err(_USAGE)
        return 1
    return 0
