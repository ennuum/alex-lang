# ALEX STANDARD LIBRARY — tui.markup
#
# Balisage de couleurs et de styles dans le texte, à la façon de Rich :
#   "[bold red]Erreur[/] : fichier [italic]notes.txt[/italic] introuvable"
#   "[black on yellow] ATTENTION [/]"   "[#ff8800]orange[/]"   "[u]souligné[/u]"   "\[pas une balise]"
#
# Mots d'une balise : bold (b), dim, italic (i), underline (u), reverse, strike (s), une couleur de texte
# (nom, 0..255, « #rrggbb »), « on <couleur> » pour le fond. [/] ou [/nom] ferme la dernière balise ouverte.
#
#   use tui.markup as mk
#   mk.show("[green]✔[/] terminé")
#   texte := mk.render("[bold]gras[/]")       # séquences ANSI (rien si la sortie n'est pas un terminal)
#   mk.strip("[bold]gras[/]")                  # "gras"
#   mk.draw(buffer, x, y, "[red]rouge[/]")     # dans un tui.screen.Buffer

from core use len, type
from collections use append, pop
use string as _s
use tui.style as _st
use tui.width as _w
use _native_fd as _f
use _native_cli as _cli
use os as _os

func _is_number(t):
    if t == "":
        return false
    for c in t:
        if c < '0' or c > '9':
            return false
    return true

func _to_int(t):
    v := 0
    for c in t:
        v = v * 10 + _s.ord(c) - 48
    return v

func _color(word):
    if _is_number(word):
        return _to_int(word)
    return word

# Style SGR d'une balise (« bold red on blue »).
func tag_style(tag):
    words := [x for x in _s.split(_s.trim(tag), " ") if x != ""]
    fg := null
    bg := null
    flags := {"bold": false, "dim": false, "italic": false, "underline": false, "reverse": false, "strike": false}
    aliases := {"b": "bold", "i": "italic", "u": "underline", "s": "strike", "reverse": "reverse", "bold": "bold", "dim": "dim", "italic": "italic", "underline": "underline", "strike": "strike"}
    i := 0
    while i < len(words):
        wd := _s.lower(words[i])
        if wd == "on" and i + 1 < len(words):
            bg = _color(_s.lower(words[i + 1]))
            i += 2
            continue
        found := false
        for k in ["b", "i", "u", "s", "reverse", "bold", "dim", "italic", "underline", "strike"]:
            if k == wd:
                flags[aliases[k]] = true
                found = true
        if not found:
            fg = _color(wd)
        i += 1
    return _st.style(fg, bg, flags["bold"], flags["dim"], flags["italic"], flags["underline"], flags["reverse"], flags["strike"])

# Découpe le texte balisé en morceaux [[texte, style], ...].
func spans(text, base=""):
    out := []
    stack := [base]
    cur := ""
    i := 0
    t := str(text)
    n := len(t)
    while i < n:
        c := t[i]
        if c == '\\' and i + 1 < n and (t[i + 1] == '[' or t[i + 1] == '\\'):
            cur += str(t[i + 1])
            i += 2
            continue
        if c == '[':
            close := i + 1
            while close < n and t[close] != ']' and t[close] != '[':
                close += 1
            if close < n and t[close] == ']' and close > i + 1:
                tag := _s.slice(t, i + 1, close)
                if cur != "":
                    append(out, [cur, stack[len(stack) - 1]])
                    cur = ""
                if _s.starts_with(tag, "/"):
                    if len(stack) > 1:
                        pop(stack)
                else:
                    append(stack, _st.merge(stack[len(stack) - 1], tag_style(tag)))
                i = close + 1
                continue
        cur += str(c)
        i += 1
    if cur != "":
        append(out, [cur, stack[len(stack) - 1]])
    return out

# Texte sans balises.
func strip(text):
    return _s.join("", [sp[0] for sp in spans(text)])

# Largeur affichée (sans les balises).
func width(text):
    return _w.of(strip(text))

# Retire les séquences ANSI d'un texte déjà rendu.
func strip_ansi(text):
    out := []
    i := 0
    t := str(text)
    n := len(t)
    while i < n:
        if _s.ord(t[i]) == 27 and i + 1 < n and t[i + 1] == '[':
            i += 2
            while i < n and (_s.ord(t[i]) < 64 or _s.ord(t[i]) > 126):
                i += 1
            i += 1
            continue
        append(out, str(t[i]))
        i += 1
    return _s.join("", out)

# Profondeur de couleurs pour la sortie standard : celle du terminal, "none" si redirigée.
func output_depth():
    if not _f.isatty(1):
        return "none"
    if _os.getenv("NO_COLOR") != null:
        return "none"
    ct := _os.getenv("COLORTERM", "")
    if ct == "truecolor" or ct == "24bit":
        return "truecolor"
    if _s.contains(_os.getenv("TERM", ""), "256"):
        return "256"
    return "16"

# Texte avec ses séquences ANSI. depth : "truecolor", "256", "16", "none" (sans couleur ni style) ; null :
# d'après la sortie standard.
func render(text, depth=null):
    if depth == null:
        depth = output_depth()
    out := []
    for sp in spans(text):
        if depth == "none" or sp[1] == "":
            append(out, sp[0])
        else:
            sg := _st.downgrade(sp[1], depth)
            if sg == "":
                append(out, sp[0])
            else:
                append(out, _st.ansi(sg) + sp[0] + _st.RESET)
    return _s.join("", out)

# Affiche le texte balisé (suivi d'une fin de ligne si end="\n").
func show(text, end="\n"):
    _cli.write_out(render(text) + end)
    _cli.flush()

# Dessine le texte balisé dans un tampon (sur une ligne) ; renvoie la largeur écrite.
func draw(buffer, x, y, text, base="", max_width=null):
    col := x
    for sp in spans(text, base):
        room := null
        if max_width != null:
            room = max_width - (col - x)
            if room <= 0:
                break
        col += buffer.text(col, y, sp[0], sp[1], room)
    return col - x
