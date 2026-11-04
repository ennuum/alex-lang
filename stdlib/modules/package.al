# ALEX STANDARD LIBRARY — modules.package
#
# Le manifeste d'un paquet ALEX (alex.toml) et son verrou (alex.lock), lus et écrits en ALEX — même format
# que `alexc pkg` (src/Manifest.cpp) : sous-ensemble de TOML (sections, chaînes, tables en ligne, commentaires).
#
#   [package]
#   name = "monapp"
#   version = "0.1.0"
#   entry = "main.al"
#   alex = ">=1.2.0"
#   [dependencies]
#   geometrie = "^1.0"
#   utils = { path = "../utils" }
#
#   use modules.package as pkg
#   p := pkg.load("alex.toml")
#   print(p.name, p.version, [str(d) for d in p.dependencies])
#   p.add_dependency("json5", "^2.1")
#   pkg.save(p, "alex.toml")
#   print(pkg.validate(p))                 # [] si valide, sinon la liste des problèmes
#   lock := pkg.load_lock("alex.lock")     # [{"name", "version", "source", "checksum"}]
#
# Erreurs : PackageError (manifeste mal formé), IoError, TypeError.

from core use len, type
from collections use append
use string as _s
use io as _io
use os as _os
use modules.version as _v
from modules.dependency use Dependency

const ERROR := "PackageError"

func is_valid_name(name):
    if type(name) != "str" or name == "":
        return false
    c0 := name[0]
    if not ((c0 >= 'a' and c0 <= 'z') or (c0 >= 'A' and c0 <= 'Z') or c0 == '_'):
        return false
    for c in name:
        if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_'):
            return false
    return true

class Package:
    func init(name, version="0.1.0", entry="", alex=""):
        self.name = name
        self.version = version
        self.entry = entry
        self.alex = alex
        self.dependencies = []
        self.directory = null

    func dependency(name):
        for d in self.dependencies:
            if d.name == name:
                return d
        return null

    # Ajoute ou remplace ; spec : contrainte ("^1.0") ou "path:../x".
    func add_dependency(name, spec="*"):
        d := Dependency(name, spec)
        if type(spec) == "str" and _s.starts_with(spec, "path:"):
            d = Dependency(name, "*", spec)
        out := []
        replaced := false
        for x in self.dependencies:
            if x.name == name:
                append(out, d)
                replaced = true
            else:
                append(out, x)
        if not replaced:
            append(out, d)
        self.dependencies = out
        return d

    func remove_dependency(name):
        n := len(self.dependencies)
        self.dependencies = [d for d in self.dependencies if d.name != name]
        return len(self.dependencies) != n

    func requires_alex(alex_version):
        if self.alex == "":
            return true
        return _v.satisfies(alex_version, self.alex)

    func to_toml():
        return serialize(self)

    func __str__():
        return self.name + " " + self.version

# ---------------------------------------------------------------- TOML (sous-ensemble)

func _strip_comment(line):
    in_str := false
    i := 0
    while i < len(line):
        c := line[i]
        if c == '"':
            in_str = not in_str
        elif c == '#' and not in_str:
            return _s.substring(line, 0, i)
        i += 1
    return line

func _unquote(v, where):
    t := _s.trim(v)
    if len(t) < 2 or t[0] != '"' or t[len(t) - 1] != '"':
        raise(ERROR, where + " : chaîne entre guillemets attendue (obtenu " + t + ")")
    return _s.substring(t, 1, len(t) - 1)

func _inline_table(v, where):
    t := _s.trim(v)
    inner := _s.trim(_s.substring(t, 1, len(t) - 1))
    out := {}
    if inner == "":
        return out
    for part in _s.split(inner, ","):
        eq := _s.find(part, "=")
        if eq < 0:
            raise(ERROR, where + " : « clé = valeur » attendu dans la table en ligne")
        out[_s.trim(_s.substring(part, 0, eq))] = _unquote(_s.substring(part, eq + 1, len(part)), where)
    return out

func parse(text, origin="alex.toml"):
    section := ""
    pkg := Package("")
    seen_pkg := false
    n := 0
    for raw in _s.split(_s.replace(text, "\r", ""), "\n"):
        n += 1
        line := _s.trim(_strip_comment(raw))
        if line == "":
            continue
        where := origin + ":" + str(n)
        if _s.starts_with(line, "["):
            if not _s.ends_with(line, "]"):
                raise(ERROR, where + " : section mal fermée")
            section = _s.trim(_s.substring(line, 1, len(line) - 1))
            if section == "package":
                seen_pkg = true
            continue
        eq := _s.find(line, "=")
        if eq < 0:
            raise(ERROR, where + " : « clé = valeur » attendu")
        key := _s.trim(_s.substring(line, 0, eq))
        val := _s.trim(_s.substring(line, eq + 1, len(line)))
        if section == "package":
            v := _unquote(val, where)
            if key == "name":
                pkg.name = v
            elif key == "version":
                pkg.version = v
            elif key == "entry":
                pkg.entry = v
            elif key == "alex":
                pkg.alex = v
        elif section == "dependencies":
            if _s.starts_with(val, "{"):
                tbl := _inline_table(val, where)
                if "path" in tbl:
                    c := "*"
                    if "version" in tbl:
                        c = tbl["version"]
                    append(pkg.dependencies, Dependency(key, c, "path:" + tbl["path"]))
                elif "version" in tbl:
                    append(pkg.dependencies, Dependency(key, tbl["version"]))
                else:
                    raise(ERROR, where + " : table de dépendance sans « path » ni « version »")
            else:
                append(pkg.dependencies, Dependency(key, _unquote(val, where)))
    if not seen_pkg:
        raise(ERROR, origin + " : section [package] absente")
    if not is_valid_name(pkg.name):
        raise(ERROR, origin + " : nom de paquet invalide '" + pkg.name + "' (identifiant ALEX attendu)")
    if not _v.is_valid(pkg.version):
        raise(ERROR, origin + " : version invalide '" + pkg.version + "'")
    return pkg

func serialize(p):
    lines := ["[package]", "name = \"" + p.name + "\"", "version = \"" + p.version + "\""]
    if p.entry != "":
        append(lines, "entry = \"" + p.entry + "\"")
    if p.alex != "":
        append(lines, "alex = \"" + p.alex + "\"")
    append(lines, "")
    append(lines, "[dependencies]")
    for d in p.dependencies:
        if d.is_path():
            if d.constraint == "*" or d.constraint == "":
                append(lines, d.name + " = { path = \"" + d.path() + "\" }")
            else:
                append(lines, d.name + " = { path = \"" + d.path() + "\", version = \"" + str(d.constraint) + "\" }")
        else:
            append(lines, d.name + " = \"" + str(d.constraint) + "\"")
    return _s.join("\n", lines) + "\n"

func load(path="alex.toml"):
    p := parse(_io.read_file(path), path)
    p.directory = _os.dirname(_os.absolute(path))
    return p

func save(p, path="alex.toml"):
    _io.write_file(path, serialize(p))

# Problèmes (liste de messages) ; [] si le paquet est valide.
func validate(p):
    out := []
    if not is_valid_name(p.name):
        append(out, "nom invalide '" + p.name + "'")
    if not _v.is_valid(p.version):
        append(out, "version invalide '" + p.version + "'")
    if p.alex != "":
        try:
            _v.constraint(p.alex)
        catch e:
            append(out, "exigence alex invalide '" + p.alex + "'")
    seen := {}
    for d in p.dependencies:
        if d.name in seen:
            append(out, "dépendance en double '" + d.name + "'")
        seen[d.name] = true
        if not is_valid_name(d.name):
            append(out, "nom de dépendance invalide '" + d.name + "'")
        if d.name == p.name:
            append(out, "le paquet dépend de lui-même")
        try:
            _v.constraint(d.constraint)
        catch e2:
            append(out, "contrainte invalide pour '" + d.name + "' : " + str(d.constraint))
    return out

func new(name, version="0.1.0", entry="main.al"):
    if not is_valid_name(name):
        raise(ERROR, "package.new : nom invalide '" + name + "'")
    return Package(name, version, entry)

# ---------------------------------------------------------------- alex.lock

func parse_lock(text):
    out := []
    cur := null
    for raw in _s.split(_s.replace(text, "\r", ""), "\n"):
        line := _s.trim(_strip_comment(raw))
        if line == "":
            continue
        if line == "[[package]]":
            if cur != null:
                append(out, cur)
            cur = {"name": "", "version": "", "source": "", "checksum": ""}
            continue
        eq := _s.find(line, "=")
        if eq > 0 and cur != null:
            cur[_s.trim(_s.substring(line, 0, eq))] = _unquote(_s.substring(line, eq + 1, len(line)), "alex.lock")
    if cur != null:
        append(out, cur)
    return out

func load_lock(path="alex.lock"):
    if not _os.exists(path):
        return []
    return parse_lock(_io.read_file(path))
