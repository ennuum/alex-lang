# ALEX STANDARD LIBRARY — modules.module
#
# Description STATIQUE d'un module ALEX à partir de son source (sans l'exécuter) : imports (`use`,
# `from … use …`), noms exportés (func, class, struct, interface, enum, const et variables de premier
# niveau), en-tête de documentation, et nom de module <-> chemin de fichier.
#
#   use modules.module as mod
#   m := mod.from_file("stdlib/collections/hash_map.al", "collections.hash_map")
#   print(m.name, m.doc_title())                 # collections.hash_map  « ALEX STANDARD LIBRARY — ... »
#   print(m.imports)                             # ["core", "collections", "collections.list", ...]
#   print(m.exports["class"])                    # ["HashMap"]
#   print(m.has_export("of"), m.is_private("_x"))
#   print(mod.relative_candidates("collections.hash_map"))
#   # ["collections/hash_map.al", "collections/hash_map/hash_map.al", "collections/hash_map/__init__.al"]
#
# Erreurs : ModuleError (nom de module invalide), IoError.

from core use len, type
from collections use append
use string as _s
use io as _io

const ERROR := "ModuleError"

func is_valid_name(name):
    if type(name) != "str" or name == "":
        return false
    for part in _s.split(name, "."):
        if part == "":
            return false
        c0 := part[0]
        if not ((c0 >= 'a' and c0 <= 'z') or (c0 >= 'A' and c0 <= 'Z') or c0 == '_'):
            return false
        for c in part:
            if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_'):
                return false
    return true

func need_name(fn, name):
    if not is_valid_name(name):
        raise(ERROR, fn + " : nom de module invalide '" + str(name) + "'")

# Chemins relatifs essayés pour un module, dans l'ordre du résolveur (src/ModuleResolver.cpp).
func relative_candidates(name):
    need_name("relative_candidates", name)
    parts := _s.split(name, ".")
    base := _s.join("/", parts)
    last := parts[len(parts) - 1]
    return [base + ".al", base + "/" + last + ".al", base + "/__init__.al"]

# Nom de module d'un fichier relatif à une racine : "collections/hash_map.al" -> "collections.hash_map".
func name_from_path(rel):
    p := _s.replace(rel, "\\", "/")
    if _s.ends_with(p, ".al"):
        p = _s.substring(p, 0, len(p) - 3)
    parts := _s.split(p, "/")
    n := len(parts)
    if n >= 2 and (parts[n - 1] == parts[n - 2] or parts[n - 1] == "__init__"):
        parts = parts[:n - 1]
    return _s.join(".", parts)

class ModuleInfo:
    func init(name, path=null):
        self.name = name
        self.path = path
        self.imports = []            # modules importés (noms), ordre d'apparition, sans doublon
        self.import_aliases = {}     # alias -> module (use x as y)
        self.imported_names = {}     # nom -> module (from x use nom)
        self.exports = {"func": [], "class": [], "struct": [], "interface": [], "enum": [], "const": [], "var": []}
        self.doc = []                # lignes du commentaire d'en-tête (sans « # »)
        self.line_count = 0

    func all_exports():
        out := []
        for k in self.exports:
            for n in self.exports[k]:
                append(out, n)
        return out

    func public_exports():
        return [n for n in self.all_exports() if not _s.starts_with(n, "_")]

    func has_export(n):
        for x in self.all_exports():
            if x == n:
                return true
        return false

    func is_private(n):
        return _s.starts_with(n, "_")

    func doc_title():
        if len(self.doc) == 0:
            return ""
        return self.doc[0]

    func depends_on(other):
        for x in self.imports:
            if x == other:
                return true
        return false

    func imports_native():
        return [x for x in self.imports if _s.starts_with(x, "_native_")]

    func __str__():
        return "<module " + self.name + ">"

func _add_unique(xs, v):
    for x in xs:
        if x == v:
            return
    append(xs, v)

func _first_word(line):
    out := ""
    for c in line:
        if c == ' ' or c == '(' or c == ':' or c == '\t':
            break
        out += str(c)
    return out

# Analyse un source ALEX.
func parse(source, name="<module>", path=null):
    m := ModuleInfo(name, path)
    lines := _s.split(_s.replace(source, "\r", ""), "\n")
    m.line_count = len(lines)
    in_header := true
    for raw in lines:
        if in_header:
            t := _s.trim(raw)
            if _s.starts_with(t, "#"):
                append(m.doc, _s.trim(_s.substring(t, 1, len(t))))
                continue
            if t != "" or len(m.doc) > 0:
                in_header = false
        if len(raw) == 0 or raw[0] == ' ' or raw[0] == '\t' or raw[0] == '#':
            continue
        line := _s.trim(raw)
        if _s.starts_with(line, "use "):
            rest := _s.trim(_s.substring(line, 4, len(line)))
            alias := null
            k := _s.find(rest, " as ")
            if k >= 0:
                alias = _s.trim(_s.substring(rest, k + 4, len(rest)))
                rest = _s.trim(_s.substring(rest, 0, k))
            _add_unique(m.imports, rest)
            if alias != null:
                m.import_aliases[alias] = rest
            else:
                parts := _s.split(rest, ".")
                m.import_aliases[parts[len(parts) - 1]] = rest
        elif _s.starts_with(line, "from "):
            k := _s.find(line, " use ")
            if k > 0:
                mod_name := _s.trim(_s.substring(line, 5, k))
                _add_unique(m.imports, mod_name)
                for n in _s.split(_s.substring(line, k + 5, len(line)), ","):
                    nn := _s.trim(n)
                    if nn != "":
                        m.imported_names[nn] = mod_name
        elif _s.starts_with(line, "func ") or _s.starts_with(line, "async func "):
            body := line
            if _s.starts_with(line, "async "):
                body = _s.substring(line, 6, len(line))
            append(m.exports["func"], _first_word(_s.substring(body, 5, len(body))))
        elif _s.starts_with(line, "class "):
            append(m.exports["class"], _first_word(_s.substring(line, 6, len(line))))
        elif _s.starts_with(line, "struct "):
            append(m.exports["struct"], _first_word(_s.substring(line, 7, len(line))))
        elif _s.starts_with(line, "interface "):
            append(m.exports["interface"], _first_word(_s.substring(line, 10, len(line))))
        elif _s.starts_with(line, "enum "):
            append(m.exports["enum"], _first_word(_s.substring(line, 5, len(line))))
        elif _s.starts_with(line, "const "):
            n := _first_word(_s.substring(line, 6, len(line)))
            append(m.exports["const"], n)
        elif _s.contains(line, ":=") and not _s.starts_with(line, "@"):
            n := _first_word(line)
            if is_valid_name(n) and not _s.contains(n, "."):
                _add_unique(m.exports["var"], n)
    return m

func from_file(path, name=null):
    n := name
    if n == null:
        n = name_from_path(path)
    return parse(_io.read_file(path), n, path)
