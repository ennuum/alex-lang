# ALEX STANDARD LIBRARY — ui.view.util (interne)
#
# Aides communes aux composants : bornes, listes, tri stable, texte (coupe avec « … », retour à la ligne).
# Les largeurs de texte sont toujours demandées à la surface de rendu (s.text_width), qui compte en
# cellules (terminal) ou en pixels (fenêtre).

from core use len, type, to_int, arity
from collections use append, contains_key
use string as _s

func imin(a, b):
    if a < b:
        return a
    return b

func imax(a, b):
    if a > b:
        return a
    return b

func clamp(v, lo, hi):
    if v < lo:
        return lo
    if v > hi:
        return hi
    return v

func floor(v):
    i := to_int(v)
    if i > v:
        return i - 1
    return i

# Éléments de items entre a (inclus) et b (exclu).
func lslice(items, a, b):
    out := []
    i := imax(a, 0)
    n := imin(b, len(items))
    while i < n:
        append(out, items[i])
        i += 1
    return out

func lcopy(items):
    return [x for x in items]

func lindex(items, value):
    i := 0
    while i < len(items):
        if items[i] == value:
            return i
        i += 1
    return -1

func last(items):
    if len(items) == 0:
        return null
    return items[len(items) - 1]

func pop_last(items):
    out := []
    i := 0
    while i < len(items) - 1:
        append(out, items[i])
        i += 1
    return out

# Ordre de tri commun : null < nombres < booléens < texte (sans casse) ; -1, 0 ou 1.
func compare(a, b):
    ta := _rank(a)
    tb := _rank(b)
    if ta != tb:
        return -1 if ta < tb else 1
    if ta == 0:
        return 0
    if ta == 3:
        a = fold(a)
        b = fold(b)
    elif ta == 4:
        a = str(a)
        b = str(b)
    elif ta == 2:
        a = 1 if a else 0
        b = 1 if b else 0
    if a < b:
        return -1
    if a > b:
        return 1
    return 0

func _rank(v):
    t := type(v)
    if v == null:
        return 0
    if t == "int" or t == "float":
        return 1
    if t == "bool":
        return 2
    if t == "str":
        return 3
    return 4

const _FOLD := {"à": "a", "â": "a", "ä": "a", "á": "a", "ã": "a", "å": "a", "æ": "ae", "ç": "c", "é": "e", "è": "e", "ê": "e", "ë": "e", "í": "i", "ì": "i", "î": "i", "ï": "i", "ñ": "n", "ó": "o", "ò": "o", "ô": "o", "ö": "o", "õ": "o", "ø": "o", "œ": "oe", "ú": "u", "ù": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y", "ß": "ss", "À": "a", "Â": "a", "Ä": "a", "Á": "a", "Ã": "a", "Å": "a", "Æ": "ae", "Ç": "c", "É": "e", "È": "e", "Ê": "e", "Ë": "e", "Í": "i", "Ì": "i", "Î": "i", "Ï": "i", "Ñ": "n", "Ó": "o", "Ò": "o", "Ô": "o", "Ö": "o", "Õ": "o", "Ø": "o", "Œ": "oe", "Ú": "u", "Ù": "u", "Û": "u", "Ü": "u", "Ý": "y", "Ÿ": "y"}

# Clé de comparaison d'un texte : minuscules, sans accents (Élodie se range avec les e).
func fold(text):
    low := _s.lower(text)
    out := ""
    plain := true
    for c in low:
        if _s.ord(c) >= 128:
            plain = false
    if plain:
        return low
    for c in low:
        k := str(c)
        if contains_key(_FOLD, k):
            out += _FOLD[k]
        else:
            out += k
    return out

# Tri fusion stable. key(x) donne la valeur comparée ; renvoie une nouvelle liste.
func sort_by(items, key, descending=false):
    keyed := [[key(items[i]), i] for i in 0..len(items)]
    ordered := _merge_sort(keyed, descending)
    return [items[k[1]] for k in ordered]

# Indices de items dans l'ordre trié (tri stable).
func sorted_indices(items, key, descending=false):
    keyed := [[key(items[i]), i] for i in 0..len(items)]
    return [k[1] for k in _merge_sort(keyed, descending)]

func _merge_sort(a, desc):
    n := len(a)
    if n <= 1:
        return a
    width := 1
    src := a
    while width < n:
        dst := []
        lo := 0
        while lo < n:
            mid := imin(lo + width, n)
            hi := imin(lo + 2 * width, n)
            i := lo
            j := mid
            while i < mid and j < hi:
                c := compare(src[i][0], src[j][0])
                if desc:
                    c = -c
                if c <= 0:
                    append(dst, src[i])
                    i += 1
                else:
                    append(dst, src[j])
                    j += 1
            while i < mid:
                append(dst, src[i])
                i += 1
            while j < hi:
                append(dst, src[j])
                j += 1
            lo = hi
        src = dst
        width = width * 2
    return src

# ---------------------------------------------------------------- texte
func split_lines(text):
    return _s.split(text, "\n")

func slice(text, a, b=null):
    if b == null:
        return _s.slice(text, a)
    return _s.slice(text, a, b)

# Le plus long préfixe de text dont la largeur tient dans w (nombre de caractères).
func fit_count(s, text, w):
    n := len(text)
    if s.text_width(text) <= w:
        return n
    lo := 0
    hi := n
    while lo < hi:
        mid := (lo + hi + 1) // 2
        if s.text_width(_s.slice(text, 0, mid)) <= w:
            lo = mid
        else:
            hi = mid - 1
    return lo

# text coupé pour tenir dans w, terminé par « … » s'il a fallu couper.
func fit(s, text, w):
    if w <= 0:
        return ""
    if s.text_width(text) <= w:
        return text
    ell := "…"
    k := fit_count(s, text, w - s.text_width(ell))
    return _s.slice(text, 0, k) + ell

# Lignes de text pour une largeur w : retour à la ligne aux espaces, mots trop longs coupés.
func wrap(s, text, w):
    out := []
    for para in split_lines(text):
        if para == "" or w <= 0:
            append(out, para)
            continue
        line := ""
        for word in _s.split(para, " "):
            candidate := word if line == "" else line + " " + word
            if s.text_width(candidate) <= w:
                line = candidate
                continue
            if line != "":
                append(out, line)
                line = ""
            # mot plus long que la ligne : le couper
            while s.text_width(word) > w:
                k := imax(1, fit_count(s, word, w))
                append(out, _s.slice(word, 0, k))
                word = _s.slice(word, k)
            line = word
        append(out, line)
    return out

# Largeur de la plus longue ligne.
func block_width(s, lines):
    w := 0
    for l in lines:
        w = imax(w, s.text_width(l))
    return w

# Valeur affichable d'une cellule (tableaux, listes).
func show(v):
    if v == null:
        return ""
    if type(v) == "str":
        return v
    if type(v) == "float":
        if v == to_int(v) and v < 1000000000000000 and v > -1000000000000000:
            return str(to_int(v))
    return str(v)

# Appelle f avec autant d'arguments qu'il en accepte parmi args (les premiers) ; ignore f null.
func call(f, args):
    if f == null:
        return null
    ar := arity(f)
    n := len(args)
    if ar != null and ar[1] < n:
        n = ar[1]
    if n <= 0:
        return f()
    if n == 1:
        return f(args[0])
    if n == 2:
        return f(args[0], args[1])
    if n == 3:
        return f(args[0], args[1], args[2])
    if n == 4:
        return f(args[0], args[1], args[2], args[3])
    return f(args[0], args[1], args[2], args[3], args[4])
