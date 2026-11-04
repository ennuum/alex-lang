# ALEX UI V1.3 — Mesure et géométrie du texte (indices en CARACTÈRES, pas en octets)
#
# Toutes les largeurs viennent de la mesure native (ui.measure_text : atlas DejaVu sous Linux,
# DirectWrite sous Windows) : les curseurs et sélections tombent donc exactement sur les glyphes
# dessinés. Un petit cache évite de re-mesurer les mêmes chaînes à chaque image.
from core use type, len, clamp, to_int
use collections
use string
use _native_ui as _native

const WORD_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
const MAX_CACHE := 600
const _CACHE := {"map": {}}

func _check_size(size, fn):
    if not (type(size) == "int" or type(size) == "float") or size <= 0:
        raise("ArgumentError", "ui.text." + fn + "() : size doit être un nombre > 0")

# {"width","height","ascent"} ; mis en cache par (taille, texte).
func measure(text, size=14.0):
    _check_size(size, "measure")
    key := str(size) + "|" + text
    m := _CACHE["map"]
    if collections.contains_key(m, key):
        return m[key]
    if len(m) >= MAX_CACHE:
        _CACHE["map"] = {}
        m = _CACHE["map"]
    r := _native.text_measure(text, size)
    m[key] = r
    return r

func width(text, size=14.0):
    return measure(text, size)["width"]

func line_height(size=14.0):
    return measure("Mg", size)["height"]

# Caractère d'indice i sous forme de str (l'indexation brute renvoie un type « char » non comparable).
func _c(text, i):
    return str(text[i])

func _sub(text, a, b):
    n := len(text)
    a = clamp(a, 0, n)
    b = clamp(b, 0, n)
    if b <= a:
        return ""
    return string.substring(text, a, b)

# Largeur des i premiers caractères (position x du curseur avant le caractère i).
func prefix_width(text, i, size=14.0):
    return width(_sub(text, 0, i), size)

# Indice de curseur (0..len) le plus proche de x (x relatif au début du texte).
func index_at(text, x, size=14.0):
    n := len(text)
    if n == 0 or x <= 0:
        return 0
    if x >= width(text, size):
        return n
    lo := 0
    hi := n
    while hi - lo > 1:
        mid := to_int((lo + hi) / 2)
        if prefix_width(text, mid, size) <= x:
            lo = mid
        else:
            hi = mid
    a := prefix_width(text, lo, size)
    b := prefix_width(text, hi, size)
    if x - a < b - x:
        return lo
    return hi

func is_word_char(ch):
    return string.find(WORD_CHARS, ch) >= 0 or ch > "~"

# Début du mot contenant / précédant l'indice i (comportement de Ctrl+Gauche).
func word_start(text, i):
    i = clamp(i, 0, len(text))
    while i > 0 and not is_word_char(_c(text, i - 1)) and _c(text, i - 1) != "\n":
        i -= 1
    while i > 0 and is_word_char(_c(text, i - 1)):
        i -= 1
    return i

# Fin du mot contenant / suivant l'indice i (comportement de Ctrl+Droite).
func word_end(text, i):
    n := len(text)
    i = clamp(i, 0, n)
    while i < n and not is_word_char(_c(text, i)) and _c(text, i) != "\n":
        i += 1
    while i < n and is_word_char(_c(text, i)):
        i += 1
    return i

# [début, fin] du « mot » sous l'indice i (double-clic) : suite de caractères de même classe.
func word_bounds(text, i):
    n := len(text)
    if n == 0:
        return [0, 0]
    i = clamp(i, 0, n)
    if i == n:
        i = n - 1
    c := _c(text, i)
    if c == "\n":
        return [i, i]
    cls := is_word_char(c)
    a := i
    while a > 0 and _c(text, a - 1) != "\n" and is_word_char(_c(text, a - 1)) == cls and (_c(text, a - 1) != " " or c == " "):
        a -= 1
    b := i + 1
    while b < n and _c(text, b) != "\n" and is_word_char(_c(text, b)) == cls and (_c(text, b) != " " or c == " "):
        b += 1
    return [a, b]

# ---- lignes (texte multi-ligne, séparateur "\n") ----
func lines(text):
    return string.split(text, "\n")

func line_count(text):
    return len(lines(text))

# Numéro de ligne (0..) de l'indice i.
func line_of(text, i):
    i = clamp(i, 0, len(text))
    n := 0
    k := 0
    while k < i:
        if _c(text, k) == "\n":
            n += 1
        k += 1
    return n

func line_start(text, i):
    i = clamp(i, 0, len(text))
    while i > 0 and _c(text, i - 1) != "\n":
        i -= 1
    return i

func line_end(text, i):
    n := len(text)
    i = clamp(i, 0, n)
    while i < n and _c(text, i) != "\n":
        i += 1
    return i

# Indice du début de la ligne `line` (0..) ; len(text) si la ligne n'existe pas.
func index_of_line(text, line):
    if line <= 0:
        return 0
    n := len(text)
    k := 0
    seen := 0
    while k < n:
        if _c(text, k) == "\n":
            seen += 1
            if seen == line:
                return k + 1
        k += 1
    return n

func sub(text, a, b):
    return _sub(text, a, b)
