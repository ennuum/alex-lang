# ALEX — commands.new
#
# `alexc new [modèle] <nom> [--dir dossier] [--ci github|gitlab|aucune]`, `alexc new --list [--json]` : projets
# (`alexc new gui` : modèle gui, projet mon_gui ; `alexc new nom` : modèle console)
# créés depuis les modèles de templates/ (à côté de stdlib/), comme alex::tooling (Templates.cpp). « {{nom}} »,
# « {{Nom}} », « {{description}} », « {{modele}} » et « {{entree}} » sont remplacés dans les noms et le contenu.
#
#   use commands.new as cn
#   code := cn.run(["console", "salut"], "templates")
#
# Erreurs : aucune levée (message « erreur: ... » sur stderr, code 1).

from core use len
from collections use append
use string as _s
use os as _os
use io as _io
use commands.common as cc

const _ORDER := ["console", "gui", "cli", "lib", "server", "kernel", "driver"]

func _read(p):
    try:
        return _io.read_file(p)
    catch e:
        return ""

# valeur d'une clé « k = "v" » d'un template.toml
func _toml_value(text, key):
    for line in _s.split(text, "\n"):
        eq := _s.find(line, "=")
        if eq < 0:
            continue
        if _s.replace(_s.substring(line, 0, eq), " ", "") != key:
            continue
        q1 := _s.find(_s.substring(line, eq, len(line)), "\"")
        if q1 < 0:
            continue
        q1 += eq
        q2 := _rfind(line, "\"")
        if q2 > q1:
            return _s.substring(line, q1 + 1, q2)
    return ""

func _rfind(s, ch):
    i := len(s) - 1
    while i >= 0:
        if s[i] == ch[0]:
            return i
        i -= 1
    return -1

func _is_alpha(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')

func _valid_name(n):
    if len(n) == 0 or not (_is_alpha(n[0]) or n[0] == '_'):
        return false
    for c in n:
        if not (_is_alpha(c) or (c >= '0' and c <= '9') or c == '_'):
            return false
    return true

func _rank(id):
    k := 0
    while k < len(_ORDER):
        if _ORDER[k] == id:
            return k
        k += 1
    return len(_ORDER)

# Modèles : [{id, title, description, category, entry}], dans l'ordre console, gui, cli, lib, server, kernel, driver.
func list_templates(root):
    out := []
    names := []
    try:
        names = _os.list_dir(root)
    catch e:
        return out
    for id in names:
        p := _os.join(root, id)
        if not _os.isdir(p) or len(id) == 0 or id[0] == '_':
            continue
        meta := _read(_os.join(p, "template.toml"))
        # point d'entrée : clé « entry » du modèle (ex. src/main.al), sinon le premier fichier usuel à sa racine
        entry := _toml_value(meta, "entry")
        for c in ["main.al", "noyau.al", "demo.al", "exemple.al"]:
            if entry == "" and _os.exists(_os.join(p, c)):
                entry = c
        append(out, {"id": id, "title": _toml_value(meta, "title"), "description": _toml_value(meta, "description"),
                     "category": _toml_value(meta, "category"), "entry": entry, "essai": _toml_value(meta, "essai"),
                     "sources": _toml_value(meta, "sources")})
    return cc.sort_by(out, (a, b) => _rank(a["id"]) < _rank(b["id"]) or (_rank(a["id"]) == _rank(b["id"]) and a["id"] < b["id"]))

func _semver():
    return _os.alex_build()["version"]

func _copy(src, dst, rel, subst):
    for n in _os.list_dir(src):
        r := n if rel == "" else rel + "/" + n
        p := _os.join(src, n)
        if r == "template.toml":
            continue
        out := _os.join(dst, subst(r))
        if _os.isdir(p):
            _os.mkdir_all(out)
            _copy(p, dst, r, subst)
            continue
        _os.mkdir_all(_os.dirname(out))
        _io.write_file(out, subst(_read(p)))

# Vrai si `name` est un module de la bibliothèque standard (dossier stdlib voisin de templates/), avec les mêmes
# chemins que le résolveur : nom.al, nom/nom.al, nom/__init__.al.
func _stdlib_module(root, name):
    std := _os.join(_os.dirname(_os.absolute(root)), "stdlib")
    for rel in [name + ".al", name + "/" + name + ".al", name + "/__init__.al"]:
        if _os.isfile(_os.join(std, rel)):
            return true
    return false

func create_project(root, tpl, name, parent, ci):
    if not _valid_name(name):
        raise("RuntimeError", "nom de projet invalide : « " + name + " » (lettres, chiffres, _)")
    src := _os.join(root, tpl)
    if not _os.isdir(src):
        raise("RuntimeError", "modèle inconnu : " + tpl)
    # le modèle lib fait du nom un module (nom.al, `use nom`) : la stdlib, cherchée d'abord, le masquerait
    if tpl == "lib" and _stdlib_module(root, name):
        raise("RuntimeError", "« " + name + " » est déjà un module de la bibliothèque standard : `use " + name +
              "` le chargerait à la place de la bibliothèque ; choisissez un autre nom")
    dst := (parent if parent != "" else ".") + "/" + name
    if parent != "" and _s.ends_with(parent, "/"):
        dst = parent + name
    if _os.exists(dst) and (not _os.isdir(dst) or len(_os.list_dir(dst)) > 0):
        raise("RuntimeError", "le dossier existe déjà : " + dst)
    info := {"description": "", "entry": "", "sources": ""}
    for t in list_templates(root):
        if t["id"] == tpl:
            info = t
    nom := _s.replace(_s.upper(_s.substring(name, 0, 1)) + _s.substring(name, 1, len(name)), "_", " ")
    subst := (s) => _s.replace(_s.replace(_s.replace(_s.replace(_s.replace(s, "{{nom}}", name), "{{Nom}}", nom), "{{description}}", info["description"]), "{{modele}}", tpl), "{{entree}}", info["entry"])
    _os.mkdir_all(dst)
    _copy(src, dst, "", subst)
    common := _os.join(root, "_commun")
    if not _os.exists(_os.join(dst, "README.md")):
        _io.write_file(_os.join(dst, "README.md"), subst(_read(_os.join(common, "README.md"))))
    _io.write_file(_os.join(dst, ".gitignore"), _read(_os.join(common, "gitignore")))
    m := "[package]\nname = \"" + name + "\"\nversion = \"0.1.0\"\n"
    if info["entry"] != "":
        m += "entry = \"" + info["entry"] + "\"\n"
    # dossiers de sources du modèle (racines de modules : application et tests y trouvent leurs modules)
    if "sources" in info and info["sources"] != "":
        m += "sources = [\"" + _s.join("\", \"", _s.split(info["sources"], ",")) + "\"]\n"
    m += "alex = \">=" + _semver() + "\"\n\n[dependencies]\n"
    _io.write_file(_os.join(dst, "alex.toml"), m)
    if ci == "github":
        _os.mkdir_all(_os.join(dst, ".github/workflows"))
        _io.write_file(_os.join(dst, ".github/workflows/alex.yml"), subst(_read(_os.join(common, "github.yml"))))
    elif ci == "gitlab":
        _io.write_file(_os.join(dst, ".gitlab-ci.yml"), subst(_read(_os.join(common, "gitlab.yml"))))
    return dst

# Segments d'un chemin absolu (« / » et « \ » acceptés).
func _segments(p):
    out := []
    for x in _s.split(_s.replace(_os.absolute(p), "\\", "/"), "/"):
        if x != "":
            append(out, x)
    return out

func _same_seg(a, b):
    if _os.platform() == "windows":
        return _s.lower(a) == _s.lower(b)
    return a == b

# Chemin de `target` vu depuis le dossier `base` (..\alexc.exe), ou chemin absolu sans racine commune.
func _relative(base, target):
    a := _segments(base)
    b := _segments(target)
    if len(a) == 0 or len(b) == 0 or not _same_seg(a[0], b[0]):
        return _os.absolute(target)
    i := 0
    while i < len(a) and i < len(b) and _same_seg(a[i], b[i]):
        i += 1
    parts := []
    k := i
    while k < len(a):
        append(parts, "..")
        k += 1
    while i < len(b):
        append(parts, b[i])
        i += 1
    return _s.join("\\" if _os.platform() == "windows" else "/", parts)

func _on_path(dir):
    win := _os.platform() == "windows"
    path := _os.getenv("PATH")
    if path == null:
        return false
    want := _s.replace(_os.absolute(dir), "\\", "/")
    for d in _s.split(path, ";" if win else ":"):
        if d == "":
            continue
        got := _s.replace(_os.absolute(d), "\\", "/")
        while len(got) > 1 and _s.ends_with(got, "/"):
            got = _s.substring(got, 0, len(got) - 1)
        if _same_seg(got, want):
            return true
    return false

# Commande qui lance cette chaîne d'outils depuis le dossier `project` : « alexc » pour une installation (qui fournit
# alexc, et alex comme alias), le nom de l'exécutable s'il est dans le PATH, sinon son chemin (..\alexc.exe) ; entre
# guillemets s'il contient une espace (PowerShell : & "...").
func tool_command(project):
    me := cc.self_path()
    if me == "" or _os.stem(me) == "alex":
        return "alexc"
    if _on_path(_os.dirname(me)):
        return _os.stem(me)
    r := _relative(project, me)
    if _os.platform() == "windows" and not _s.contains(r, ":") and not _s.starts_with(r, "."):
        r = ".\\" + r
    elif _os.platform() != "windows" and not _s.starts_with(r, "/") and not _s.starts_with(r, "."):
        r = "./" + r
    if _s.contains(r, " "):
        return ("& \"" + r + "\"") if _os.platform() == "windows" else ("\"" + r + "\"")
    return r

func _pad(s, n):
    if len(s) >= n:
        return _s.substring(s, 0, n)
    return s + _s.repeat(" ", n - len(s))

func run(args, root):
    list := false
    json := false
    dir := ""
    ci := "github"
    pos := []
    i := 0
    while i < len(args):
        a := args[i]
        if a == "--list":
            list = true
        elif a == "--json":
            json = true
        elif a == "--dir" and i + 1 < len(args):
            i += 1
            dir = args[i]
        elif a == "--ci" and i + 1 < len(args):
            i += 1
            ci = args[i]
        else:
            append(pos, a)
        i += 1
    templates := list_templates(root)
    if len(templates) == 0:
        cc.err("erreur: aucun modèle de projet : dossier introuvable ou vide : " + root +
               " (templates/ doit se trouver à côté de stdlib/, ou utilisez un alexc portable : alexc bundle)\n")
        return 1
    if list or len(pos) == 0:
        if json:
            arr := []
            for t in templates:
                append(arr, {"id": t["id"], "title": t["title"], "description": t["description"], "category": t["category"], "entry": t["entry"]})
            print(cc.json_dump(arr))
            return 0
        print("usage: alexc new [modèle] <nom> [--dir dossier] [--ci github|gitlab|aucune]\n\nModèles :")
        for t in templates:
            print("  " + _pad(t["id"], 10) + t["title"] + " — " + t["description"])
        return 1 if len(pos) == 0 and not list else 0
    tpl := pos[0] if len(pos) >= 2 else "console"
    name := pos[1] if len(pos) >= 2 else pos[0]
    # `alexc new gui` : un nom de modèle seul désigne le modèle (projet mon_gui), pas un projet console nommé gui
    if len(pos) == 1:
        for t in templates:
            if t["id"] == pos[0]:
                tpl = pos[0]
                name = "mon_" + pos[0]
    try:
        path := create_project(root, tpl, name, dir, ci)
        # commande d'essai du modèle (clé « essai » de template.toml), sinon alexc run
        essai := "alexc run"
        for t in templates:
            if t["id"] == tpl and t["essai"] != "":
                essai = t["essai"]
        tool := tool_command(path)
        if tool != "alexc" and _s.starts_with(essai, "alexc "):
            essai = tool + _s.substring(essai, 5, len(essai))
        print("Projet créé : " + path + " (modèle " + tpl + ")\n  cd " + path + "\n  " + essai + "\n  " + tool + " test")
        return 0
    catch e:
        cc.err("erreur: " + e.message + "\n")
        return 1
