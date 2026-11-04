# ALEX STANDARD LIBRARY — ui.view.edit (interne)
#
# Édition de texte commune aux champs (input, spinbox) et aux zones multilignes (textarea) : le texte est une
# str, le curseur un indice de caractère. apply() renvoie [texte, curseur] après une touche, ou null si la
# touche n'édite pas.

from core use len, type
use string as _s
use ui.view.util as _u

func _sl(t, a, b=null):
    if b == null:
        return _s.slice(t, a)
    return _s.slice(t, a, b)

func insert(text, cur, what):
    return [_sl(text, 0, cur) + what + _sl(text, cur), cur + len(what)]

func _is_space(c):
    return c == " " or c == "\n" or c == "\t"

func word_left(text, cur):
    k := cur
    while k > 0 and _is_space(str(text[k - 1])):
        k -= 1
    while k > 0 and not _is_space(str(text[k - 1])):
        k -= 1
    return k

func word_right(text, cur):
    k := cur
    n := len(text)
    while k < n and _is_space(str(text[k])):
        k += 1
    while k < n and not _is_space(str(text[k])):
        k += 1
    return k

# Début et fin de la ligne qui contient cur.
func line_start(text, cur):
    k := cur
    while k > 0 and text[k - 1] != '\n':
        k -= 1
    return k

func line_end(text, cur):
    k := cur
    n := len(text)
    while k < n and text[k] != '\n':
        k += 1
    return k

# [ligne, colonne] du curseur.
func line_col(text, cur):
    line := 0
    col := 0
    i := 0
    n := len(text)
    while i < cur and i < n:
        if text[i] == '\n':
            line += 1
            col = 0
        else:
            col += 1
        i += 1
    return [line, col]

func index_of(text, line, col):
    l := 0
    i := 0
    n := len(text)
    while i < n and l < line:
        if text[i] == '\n':
            l += 1
        i += 1
    c := 0
    while i < n and text[i] != '\n' and c < col:
        i += 1
        c += 1
    return i

func clean(text, multiline):
    out := ""
    for c in text:
        if c == '\r':
            continue
        if c == '\n' and not multiline:
            out += " "
            continue
        if c == '\t':
            out += "    "
            continue
        out += str(c)
    return out

# Applique une touche (ou un collage) à text ; [texte, curseur] ou null.
func apply(text, cur, ev, multiline, clipboard=null):
    if ev["type"] == "paste":
        return insert(text, cur, clean(ev["text"], multiline))
    key := ev["key"]
    n := len(text)
    if key == "backspace":
        if cur == 0:
            return [text, cur]
        return [_sl(text, 0, cur - 1) + _sl(text, cur), cur - 1]
    if key == "delete" or key == "ctrl+d":
        if cur >= n:
            return [text, cur]
        return [_sl(text, 0, cur) + _sl(text, cur + 1), cur]
    if key == "left":
        return [text, _u.imax(0, cur - 1)]
    if key == "right":
        return [text, _u.imin(n, cur + 1)]
    if key == "ctrl+left" or key == "alt+b":
        return [text, word_left(text, cur)]
    if key == "ctrl+right" or key == "alt+f":
        return [text, word_right(text, cur)]
    if key == "ctrl+w" or key == "ctrl+backspace" or key == "alt+backspace":
        k := word_left(text, cur)
        return [_sl(text, 0, k) + _sl(text, cur), k]
    if key == "home" or key == "ctrl+a":
        return [text, line_start(text, cur)]
    if key == "end" or key == "ctrl+e":
        return [text, line_end(text, cur)]
    if key == "ctrl+u":
        k := line_start(text, cur)
        return [_sl(text, 0, k) + _sl(text, cur), k]
    if key == "ctrl+k":
        e := line_end(text, cur)
        if e == cur and multiline and cur < n:
            e = cur + 1
        return [_sl(text, 0, cur) + _sl(text, e), cur]
    if key == "ctrl+v" and clipboard != null:
        return insert(text, cur, clean(clipboard, multiline))
    if multiline and key == "enter":
        return insert(text, cur, "\n")
    if key == "space":
        return insert(text, cur, " ")
    t := ev["text"]
    if t != null and t != "" and _s.ord(t[0]) >= 32:
        return insert(text, cur, t)
    return null
