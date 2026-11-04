# ALEX STANDARD LIBRARY — path
# Manipulation LEXICALE de chemins, en ALEX pur (ne touche jamais au disque ; pour l'accès au système de
# fichiers voir os). Chaque fonction accepte un dernier paramètre optionnel `win` :
#   null (défaut) = style de la plateforme ; true = style Windows ; false = style POSIX.
#
#   use path
#   path.join("a", "b", "c.txt")          # a/b/c.txt
#   path.normalize("a/./b/../c")          # a/c
#   path.stem("x/y.tar.gz")               # y.tar
#   path.relative_to("/a/b/c", "/a")      # b/c
#   path.glob_match("*.al", "main.al")    # true
#
# Style Windows : "/" et "\" sont tous deux des séparateurs en entrée, "\" en sortie ; "C:\x" est absolu,
# "C:x" est relatif au lecteur ; les chemins UNC ne sont pas gérés.
# Erreurs : TypeError (argument non str), ValueError (chemins incompatibles, extension/nom invalide).

from core use len, type
from collections use append
use string as _s
use os as _os

const _WIN := _os.platform() == "windows"

func _is_win(win):
    if win == null:
        return _WIN
    return win

func _need_str(fn, value):
    if type(value) != "str":
        raise("TypeError", "path." + fn + "() : une str est attendue (obtenu '" + type(value) + "')")

func _sep(win):
    if _is_win(win):
        return "\\"
    return "/"

# Caractère d'indice i, en str (s[i] renvoie un char, jamais égal à une str).
func _at(s, i):
    return str(s[i])

func _is_letter(c):
    o := _s.ord(c)
    return (o >= 65 and o <= 90) or (o >= 97 and o <= 122)

# Décompose p en (racine, composants). Les composants vides sont écartés ; "." et ".." sont conservés.
func _split_path(p, win):
    w := _is_win(win)
    rest := p
    root := ""
    if w:
        rest = _s.replace(rest, "/", "\\")
        if len(rest) >= 2 and _is_letter(rest[0]) and _at(rest, 1) == ":":
            root = _s.slice(rest, 0, 2)
            rest = _s.slice(rest, 2)
            if len(rest) > 0 and _at(rest, 0) == "\\":
                root = root + "\\"
        elif len(rest) > 0 and _at(rest, 0) == "\\":
            root = "\\"
    elif len(rest) > 0 and _at(rest, 0) == "/":
        root = "/"
    parts := []
    for seg in _s.split(rest, _sep(win)):
        if seg != "":
            append(parts, seg)
    return (root, parts)

func _root_is_abs(root):
    return len(root) > 0 and (_at(root, len(root) - 1) == "/" or _at(root, len(root) - 1) == "\\")

func _format(root, parts, win):
    out := root + _s.join(_sep(win), parts)
    if out == "":
        return "."
    return out

# Vrai pour un chemin absolu : "/x" (POSIX) ; "C:\x" ou "\x" (Windows).
func is_absolute(p: str, win: bool? = null) -> bool:
    _need_str("is_absolute", p)
    r := _split_path(p, win)
    return _root_is_abs(r[0])

# Liste des composants ; la racine, si elle existe, est le premier élément. parts("/a/b") == ["/", "a", "b"].
func parts(p, win=null):
    _need_str("parts", p)
    r := _split_path(p, win)
    out := []
    if r[0] != "":
        append(out, r[0])
    for x in r[1]:
        append(out, x)
    return out

# Concatène des segments (liste, ou jusqu'à 8 arguments). Un segment vide est ignoré ; un segment absolu
# remplace tout ce qui précède. Aucune normalisation.
func join(first, second=null, third=null, fourth=null, fifth=null, sixth=null, seventh=null, eighth=null, win=null):
    segs := []
    if type(first) == "list" or type(first) == "tuple":
        for x in first:
            append(segs, x)
    else:
        append(segs, first)
    for x in [second, third, fourth, fifth, sixth, seventh, eighth]:
        if x != null:
            append(segs, x)
    sep := _sep(win)
    out := ""
    for seg in segs:
        _need_str("join", seg)
        if seg == "":
            continue
        if out == "" or is_absolute(seg, win):
            out = seg
        else:
            last := _at(out, len(out) - 1)
            if last == "/" or (_is_win(win) and last == "\\") or (_is_win(win) and last == ":"):
                out = out + seg
            else:
                out = out + sep + seg
    return out

# Normalisation lexicale : retire "." et les séparateurs doubles, résout "..". "" ou chemin qui s'annule -> ".".
func normalize(p: str, win: bool? = null) -> str:
    _need_str("normalize", p)
    r := _split_path(p, win)
    out := []
    for seg in r[1]:
        if seg == ".":
            continue
        if seg == "..":
            if len(out) > 0 and out[len(out) - 1] != "..":
                _s_pop(out)
            elif not _root_is_abs(r[0]):
                append(out, "..")
        else:
            append(out, seg)
    return _format(r[0], out, win)

func _s_pop(l):
    __list_remove_at(l, len(l) - 1)

# Dernier composant ; les séparateurs finaux sont ignorés. basename("a/b/") == "b".
func basename(p: str, win: bool? = null) -> str:
    _need_str("basename", p)
    r := _split_path(p, win)
    if len(r[1]) == 0:
        return ""
    return r[1][len(r[1]) - 1]

# Tout sauf le dernier composant ; "" pour un chemin relatif sans séparateur, la racine pour "/x".
func dirname(p: str, win: bool? = null) -> str:
    _need_str("dirname", p)
    r := _split_path(p, win)
    if len(r[1]) <= 1:
        return r[0]
    return r[0] + _s.join(_sep(win), _init(r[1]))

func _init(l):
    out := []
    i := 0
    while i < len(l) - 1:
        append(out, l[i])
        i = i + 1
    return out

# (dirname, basename).
func split(p, win=null):
    return (dirname(p, win), basename(p, win))

# Position du point de l'extension dans `base`, ou -1 (".bashrc" et ".." n'ont pas d'extension).
func _ext_index(base):
    i := len(base) - 1
    while i > 0:
        if _at(base, i) == ".":
            return i
        i = i - 1
    return -1

# Dernière extension avec son point : extension("a/b.tar.gz") == ".gz", "" sinon.
func extension(p: str, win: bool? = null) -> str:
    b := basename(p, win)
    i := _ext_index(b)
    if i < 0:
        return ""
    return _s.slice(b, i)

# Nom sans sa dernière extension : stem("a/b.tar.gz") == "b.tar".
func stem(p: str, win: bool? = null) -> str:
    b := basename(p, win)
    i := _ext_index(b)
    if i < 0:
        return b
    return _s.slice(b, 0, i)

# Remplace (ou ajoute / retire avec "") l'extension : with_extension("a/b.txt", ".md") == "a/b.md".
func with_extension(p: str, ext: str, win: bool? = null) -> str:
    _need_str("with_extension", ext)
    if ext != "" and (_at(ext, 0) != "." or len(ext) == 1):
        raise("ValueError", "path.with_extension() : l'extension doit commencer par '.' et ne pas être vide")
    return with_name(p, stem(p, win) + ext, win)

# Remplace le dernier composant : with_name("a/b.txt", "c.md") == "a/c.md".
func with_name(p: str, name: str, win: bool? = null) -> str:
    _need_str("with_name", name)
    if name == "" or _s.contains(name, "/") or (_is_win(win) and _s.contains(name, "\\")):
        raise("ValueError", "path.with_name() : nom invalide")
    if basename(p, win) == "":
        raise("ValueError", "path.with_name() : le chemin n'a pas de nom")
    d := dirname(p, win)
    if d == "":
        return name
    return join(d, name, win=win)

# Chemin de `p` relatif à `base` (lexical, les deux sont normalisés). Lève ValueError si l'un est absolu et
# pas l'autre, ou si les racines diffèrent.
func relative_to(p, base, win=null):
    _need_str("relative_to", p)
    _need_str("relative_to", base)
    a := _split_path(normalize(p, win), win)
    b := _split_path(normalize(base, win), win)
    if _lower_if_win(a[0], win) != _lower_if_win(b[0], win):
        raise("ValueError", "path.relative_to() : racines différentes ('" + p + "' et '" + base + "')")
    pa := a[1]
    pb := b[1]
    if len(pa) == 1 and pa[0] == ".":
        pa = []
    if len(pb) == 1 and pb[0] == ".":
        pb = []
    i := 0
    while i < len(pa) and i < len(pb) and pa[i] == pb[i]:
        i = i + 1
    out := []
    k := i
    while k < len(pb):
        if pb[k] == "..":
            raise("ValueError", "path.relative_to() : impossible de remonter à travers '..' dans la base")
        append(out, "..")
        k = k + 1
    while i < len(pa):
        append(out, pa[i])
        i = i + 1
    if len(out) == 0:
        return "."
    return _s.join(_sep(win), out)

func _lower_if_win(s, win):
    if _is_win(win):
        return _s.lower(s)
    return s

# Vrai si `p` est `base` ou se trouve sous `base` (lexical).
func is_subpath(p: str, base: str, win: bool? = null) -> bool:
    r := null
    try:
        r = relative_to(p, base, win)
    catch e:
        return false
    return r != ".." and not _s.starts_with(r, ".." + _sep(win))

# Plus long préfixe de composants commun à une liste de chemins ("" s'il n'y en a pas).
func common_prefix(paths, win=null):
    if len(paths) == 0:
        return ""
    first := _split_path(normalize(paths[0], win), win)
    root := first[0]
    common := first[1]
    for p in paths:
        _need_str("common_prefix", p)
        r := _split_path(normalize(p, win), win)
        if r[0] != root:
            return ""
        n := 0
        while n < len(common) and n < len(r[1]) and common[n] == r[1][n]:
            n = n + 1
        common = _s_take(common, n)
    if len(common) == 0:
        return root
    return root + _s.join(_sep(win), common)

func _s_take(l, n):
    out := []
    i := 0
    while i < n:
        append(out, l[i])
        i = i + 1
    return out

# Motif de type shell sur UN nom : * (tout), ? (un caractère), [abc] [a-z] [!a-z]. Sensible à la casse.
func glob_match(pattern: str, name: str) -> bool:
    _need_str("glob_match", pattern)
    _need_str("glob_match", name)
    pc := []
    for c in pattern:
        append(pc, str(c))
    nc := []
    for c in name:
        append(nc, str(c))
    return _glob(pc, 0, nc, 0)

func _glob(p, i, n, j):
    while i < len(p):
        c := p[i]
        if c == "*":
            while i < len(p) and p[i] == "*":
                i = i + 1
            if i == len(p):
                return true
            k := j
            while k <= len(n):
                if _glob(p, i, n, k):
                    return true
                k = k + 1
            return false
        if j >= len(n):
            return false
        if c == "?":
            i = i + 1
            j = j + 1
        elif c == "[":
            close := i + 1
            if close < len(p) and (p[close] == "!" or p[close] == "^"):
                close = close + 1
            if close < len(p) and p[close] == "]":
                close = close + 1
            while close < len(p) and p[close] != "]":
                close = close + 1
            if close >= len(p):
                if n[j] != "[":
                    return false
                i = i + 1
                j = j + 1
            else:
                if not _in_class(p, i + 1, close, n[j]):
                    return false
                i = close + 1
                j = j + 1
        else:
            if c != n[j]:
                return false
            i = i + 1
            j = j + 1
    return j == len(n)

func _in_class(p, a, b, ch):
    neg := false
    if p[a] == "!" or p[a] == "^":
        neg = true
        a = a + 1
    hit := false
    while a < b:
        if a + 2 < b and p[a + 1] == "-":
            if ch >= p[a] and ch <= p[a + 2]:
                hit = true
            a = a + 3
        else:
            if ch == p[a]:
                hit = true
            a = a + 1
    return hit != neg
