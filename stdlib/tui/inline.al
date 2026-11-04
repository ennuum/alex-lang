# ALEX STANDARD LIBRARY — tui.inline
#
# Composants de terminal « en ligne » : ils s'affichent sous le curseur, au fil d'un script, sans prendre tout
# l'écran (à la différence de ui.view en mode terminal).
#
# Saisie (clavier, avec repli ligne à ligne si l'entrée n'est pas un terminal)
#   select(question, options, default)          -> indice choisi (flèches, j/k, lettres pour filtrer, Entrée)
#   multi_select(question, options, selected)   -> liste d'indices (Espace coche, « a » tout, Entrée valide)
#   prompt(question, default, validate, password, choices)  -> texte (édition, Tab complète parmi choices)
#   confirm(question, default)                  -> bool (o/n, y/n, Entrée = défaut)
#   number(question, default, minimum, maximum, integer)    -> nombre
# Affichage
#   table(lignes, entêtes, alignements, cadre, largeur) -> texte ; print_table(...)
#   tree(nœud) -> texte (nœud : str, [libellé, [enfants]] ou {"label", "children"})
#   panel(texte, titre, cadre, largeur, marge), rule(titre), columns(éléments)
#   ProgressBar(total, libellé) : update(n), set(valeur), finish() ; Spinner(texte) : tick(), stop(texte)
#   spin(texte, fonction, arguments) : animation pendant que la fonction s'exécute (fil séparé)
# Le texte accepte le balisage de tui.markup (« [bold red]...[/] »).
#
# Échap annule select / multi_select / prompt (résultat null) ; Ctrl+C lève InterruptError.
# Tests : use_virtual(touches, largeur) remplace clavier et écran ; output() rend ce qui a été écrit.

from core use len, type, to_int, to_float
from collections use append, pop, contains_key
use string as _s
use os as _os
use _native_fd as _f
use _native_net as _b
use _native_cli as _cli
use tui.input as _in
use tui.width as _w
use tui.markup as _mk
use tui.screen as _screen
use concurrency.thread as _thread

# ---------------------------------------------------------------- entrée / sortie
_IO := {"virtual": false, "keys": [], "out": [], "width": 80, "tty_in": null, "tty_out": null}

# Remplace clavier et écran : keys = noms de touches (« down », « enter », « a ») ou texte entre « text: » ;
# la sortie est accumulée (output()). width : largeur supposée du terminal.
func use_virtual(keys=null, width=80):
    _IO["virtual"] = true
    _IO["keys"] = []
    if keys != null:
        for k in keys:
            if _s.starts_with(k, "text:"):
                for c in _s.slice(k, 5):
                    if c == ' ':
                        append(_IO["keys"], "space")
                    else:
                        append(_IO["keys"], str(c))
            else:
                append(_IO["keys"], k)
    _IO["out"] = []
    _IO["width"] = width

func use_terminal():
    _IO["virtual"] = false
    _IO["keys"] = []
    _IO["out"] = []

# Tout ce qui a été écrit depuis use_virtual, sans les séquences ANSI de déplacement.
func output(raw=false):
    t := _s.join("", _IO["out"])
    if raw:
        return t
    return _mk.strip_ansi(t)

# Écran virtuel final : rejoue la sortie sur un émulateur et renvoie ses lignes non vides.
func screen_lines(height=40):
    use_emu := _emulate(_s.join("", _IO["out"]), _IO["width"], height)
    return [l for l in use_emu if l != ""]

use tui.emulator as _emu_mod
func _emulate(text, width, height):
    e := _emu_mod.Emulator(width, height)
    e.feed(text)
    return e.lines()

func _write(text):
    if _IO["virtual"]:
        append(_IO["out"], text)
    else:
        _cli.write_out(text)
        _cli.flush()

func _interactive():
    if _IO["virtual"]:
        return true
    return _f.isatty(0) and _f.isatty(1)

func _out_tty():
    if _IO["virtual"]:
        return true
    return _f.isatty(1)

func term_width():
    if _IO["virtual"]:
        return _IO["width"]
    w := _os.terminal()["columns"]
    if w == null:
        return 80
    return w

func _depth():
    if _IO["virtual"]:
        return "none"
    return _mk.output_depth()

func _m(text):
    return _mk.render(text, _depth())

class _Keys:
    func init():
        self.dec = _in.Decoder()
        self.queue = []
        self.tail = ""

    func start():
        if not _IO["virtual"]:
            _f.set_mode(0, true, false)

    func stop():
        if not _IO["virtual"]:
            _f.restore(0)

    func read():
        if _IO["virtual"]:
            if len(_IO["keys"]) == 0:
                raise("IoError", "tui.inline : plus de touches simulées")
            k := _IO["keys"][0]
            _IO["keys"] = [_IO["keys"][i] for i in 1..len(_IO["keys"])]
            ev := {"type": "key", "key": k, "text": null}
            if len(k) == 1:
                ev["text"] = k
            if k == "space":
                ev["text"] = " "
            return ev
        while true:
            if len(self.queue) > 0:
                ev := self.queue[0]
                self.queue = [self.queue[i] for i in 1..len(self.queue)]
                if ev["type"] == "key" or ev["type"] == "paste":
                    return ev
                continue
            slice := null
            if self.dec.waiting():
                slice = 0.03
            data := _f.read(0, 1024, slice)
            if data == null:
                for e in self.dec.flush():
                    append(self.queue, e)
                continue
            if type(data) == "int" or data == "":
                raise("IoError", "tui.inline : fin de l'entrée")
            raw := self.tail + data
            whole := _b.utf8_prefix(raw)
            self.tail = _b.bslice(raw, whole, _b.blen(raw))
            for e in self.dec.feed(_b.bslice(raw, 0, whole)):
                append(self.queue, e)

# Zone redessinée sur place (plusieurs lignes sous le curseur).
class _Live:
    func init():
        self.count = 0

    func draw(lines, cursor_col=null):
        out := []
        if self.count > 0:
            append(out, "\r")
            if self.count > 1:
                append(out, "\e[" + str(self.count - 1) + "A")
        width := term_width() - 1
        i := 0
        for line in lines:
            if i > 0:
                append(out, "\r\n")
            append(out, "\e[2K" + _fit(line, width))
            i += 1
        extra := self.count - len(lines)
        if extra > 0:
            k := 0
            while k < extra:
                append(out, "\r\n\e[2K")
                k += 1
            append(out, "\e[" + str(extra) + "A")
        if cursor_col != null:
            append(out, "\r")
            if cursor_col > 0:
                append(out, "\e[" + str(cursor_col) + "C")
        self.count = len(lines)
        _write(_s.join("", out))

    # Remplace la zone par ces lignes définitives et passe à la ligne.
    func finish(lines):
        self.draw(lines)
        _write("\r\n")
        self.count = 0

func _fit(line, width):
    if _mk.width(line) <= width:
        return _m(line)
    return _w.truncate(_mk.strip(line), width)

func _cancel_check(ev):
    if ev["key"] == "ctrl+c":
        raise("InterruptError", "saisie interrompue (Ctrl+C)")

# ---------------------------------------------------------------- select
func _matches(option, filter):
    if filter == "":
        return true
    return _s.contains(_s.lower(_mk.strip(option)), _s.lower(filter))

# Choix d'une option dans une liste ; renvoie son indice (dans options), ou null (Échap).
# page : nombre de lignes visibles ; filter : la frappe de lettres filtre la liste.
func select(question, options, default=0, page=10, filter=true):
    if type(options) != "list" or len(options) == 0:
        raise("ArgumentError", "tui.select : liste d'options non vide attendue")
    if not _interactive():
        return _select_lines(question, options, default)
    keys := _Keys()
    live := _Live()
    cur := default
    if cur == null or cur < 0 or cur >= len(options):
        cur = 0
    text := ""
    top := 0
    _write("\e[?25l")
    keys.start()
    try:
        while true:
            visible := [i for i in 0..len(options) if _matches(options[i], text)]
            pos := 0
            k := 0
            while k < len(visible):
                if visible[k] == cur:
                    pos = k
                k += 1
            if len(visible) > 0 and not _contains(visible, cur):
                cur = visible[0]
                pos = 0
            if pos < top:
                top = pos
            if pos >= top + page:
                top = pos - page + 1
            lines := ["[bold cyan]?[/] [bold]" + question + "[/]" + _filter_hint(text, filter)]
            j := top
            while j < len(visible) and j < top + page:
                idx := visible[j]
                if idx == cur:
                    append(lines, "[cyan]❯ " + str(options[idx]) + "[/]")
                else:
                    append(lines, "  " + str(options[idx]))
                j += 1
            if len(visible) == 0:
                append(lines, "  [dim](aucune option)[/]")
            elif len(visible) > page:
                append(lines, "  [dim](" + str(pos + 1) + "/" + str(len(visible)) + ")[/]")
            live.draw(lines)
            ev := keys.read()
            _cancel_check(ev)
            key := ev["key"]
            if key == "enter":
                if len(visible) > 0:
                    live.finish(["[green]✔[/] [bold]" + question + "[/] [cyan]" + _mk.strip(str(options[cur])) + "[/]"])
                    return cur
            elif key == "escape":
                live.finish(["[red]✘[/] [bold]" + question + "[/] [dim]annulé[/]"])
                return null
            elif key == "up" or (key == "k" and not filter):
                if pos > 0:
                    cur = visible[pos - 1]
                elif len(visible) > 0:
                    cur = visible[len(visible) - 1]
            elif key == "down" or key == "tab" or (key == "j" and not filter):
                if pos + 1 < len(visible):
                    cur = visible[pos + 1]
                elif len(visible) > 0:
                    cur = visible[0]
            elif key == "home" and len(visible) > 0:
                cur = visible[0]
            elif key == "end" and len(visible) > 0:
                cur = visible[len(visible) - 1]
            elif key == "page_down" and len(visible) > 0:
                cur = visible[_min(len(visible) - 1, pos + page)]
            elif key == "page_up" and len(visible) > 0:
                cur = visible[_max(0, pos - page)]
            elif key == "backspace" and filter:
                if text != "":
                    text = _s.slice(text, 0, len(text) - 1)
            elif filter and ev["text"] != null:
                text += ev["text"]
    finally:
        keys.stop()
        _write("\e[?25h")

func _filter_hint(text, filter):
    if not filter or text == "":
        return ""
    return " [dim]filtre :[/] [yellow]" + text + "[/]"

func _contains(items, x):
    for i in items:
        if i == x:
            return true
    return false

func _select_lines(question, options, default):
    _write(_mk.strip(question) + "\n")
    i := 0
    while i < len(options):
        _write("  " + str(i + 1) + ". " + _mk.strip(str(options[i])) + "\n")
        i += 1
    while true:
        _write("Choix (1-" + str(len(options)) + ") : ")
        line := input()
        if line == null:
            return default
        t := _s.trim(line)
        if t == "" and default != null:
            return default
        n := _parse_int(t)
        if n != null and n >= 1 and n <= len(options):
            return n - 1

# ---------------------------------------------------------------- multi_select
# Cases à cocher ; renvoie la liste des indices cochés (dans l'ordre des options), ou null (Échap).
# minimum : nombre de choix exigé pour valider.
func multi_select(question, options, selected=null, page=10, minimum=0):
    if type(options) != "list" or len(options) == 0:
        raise("ArgumentError", "tui.multi_select : liste d'options non vide attendue")
    checked := [false for i in 0..len(options)]
    if selected != null:
        for i in selected:
            checked[i] = true
    if not _interactive():
        return _multi_lines(question, options, checked)
    keys := _Keys()
    live := _Live()
    cur := 0
    top := 0
    note := ""
    _write("\e[?25l")
    keys.start()
    try:
        while true:
            if cur < top:
                top = cur
            if cur >= top + page:
                top = cur - page + 1
            lines := ["[bold cyan]?[/] [bold]" + question + "[/] [dim](Espace : cocher, a : tout, Entrée : valider)[/]"]
            j := top
            while j < len(options) and j < top + page:
                box := "◯"
                if checked[j]:
                    box = "[green]◉[/]"
                if j == cur:
                    append(lines, "[cyan]❯[/] " + box + " [cyan]" + str(options[j]) + "[/]")
                else:
                    append(lines, "  " + box + " " + str(options[j]))
                j += 1
            if note != "":
                append(lines, "[red]" + note + "[/]")
            live.draw(lines)
            ev := keys.read()
            _cancel_check(ev)
            key := ev["key"]
            note = ""
            if key == "enter":
                result := [i for i in 0..len(options) if checked[i]]
                if len(result) < minimum:
                    note = "Choisir au moins " + str(minimum) + " option(s)."
                    continue
                names := [_mk.strip(str(options[i])) for i in result]
                live.finish(["[green]✔[/] [bold]" + question + "[/] [cyan]" + _s.join(", ", names) + "[/]"])
                return result
            elif key == "escape":
                live.finish(["[red]✘[/] [bold]" + question + "[/] [dim]annulé[/]"])
                return null
            elif key == "space" or key == "x":
                checked[cur] = not checked[cur]
            elif key == "a":
                all_on := true
                for c in checked:
                    if not c:
                        all_on = false
                checked = [not all_on for i in 0..len(options)]
            elif key == "up" or key == "k":
                cur = (cur - 1 + len(options)) % len(options)
            elif key == "down" or key == "j" or key == "tab":
                cur = (cur + 1) % len(options)
            elif key == "home":
                cur = 0
            elif key == "end":
                cur = len(options) - 1
    finally:
        keys.stop()
        _write("\e[?25h")

func _multi_lines(question, options, checked):
    _write(_mk.strip(question) + "\n")
    i := 0
    while i < len(options):
        _write("  " + str(i + 1) + ". " + _mk.strip(str(options[i])) + "\n")
        i += 1
    _write("Numéros séparés par des virgules : ")
    line := input()
    if line == null or _s.trim(line) == "":
        return [i for i in 0..len(options) if checked[i]]
    out := []
    for part in _s.split(line, ","):
        n := _parse_int(_s.trim(part))
        if n != null and n >= 1 and n <= len(options) and not _contains(out, n - 1):
            append(out, n - 1)
    return out

# ---------------------------------------------------------------- prompt
# Saisie d'une ligne. validate(texte) -> null si correct, sinon le message d'erreur à afficher ;
# password : affiche des « • » ; choices : liste de complétions (Tab). Renvoie le texte, ou null (Échap).
func prompt(question, default=null, validate=null, password=false, choices=null, placeholder=null):
    if not _interactive():
        _write(_mk.strip(question) + " ")
        line := input()
        if (line == null or line == "") and default != null:
            return str(default)
        return line
    keys := _Keys()
    live := _Live()
    value := []
    cur := 0
    error := null
    keys.start()
    try:
        while true:
            shown := _s.join("", value)
            if password:
                shown = _s.repeat("•", len(value))
            head := "[bold cyan]?[/] [bold]" + question + "[/] "
            hint := ""
            if len(value) == 0 and default != null:
                hint = "[dim](" + str(default) + ")[/]"
            elif len(value) == 0 and placeholder != null:
                hint = "[dim]" + placeholder + "[/]"
            completion := ""
            if choices != null and len(value) > 0 and not password:
                c := _complete(shown, choices)
                if c != null and len(c) > len(shown):
                    completion = "[dim]" + _escape(_s.slice(c, len(shown))) + "[/]"
            line := head + _escape(shown) + completion + hint
            lines := [line]
            if error != null:
                append(lines, "[red]  ✘ " + _escape(error) + "[/]")
            col := _mk.width(head) + _w.of(_s.join("", [value[i] for i in 0..cur]))
            if password:
                col = _mk.width(head) + cur
            live.draw(lines)
            if len(lines) > 1:
                _write("\e[" + str(len(lines) - 1) + "A")
            _write("\r" + _move_right(col))
            ev := keys.read()
            if len(lines) > 1:
                _write("\e[" + str(len(lines) - 1) + "B")
            if ev["type"] == "paste":
                for ch in ev["text"]:
                    if _s.ord(ch) >= 32:
                        value = _insert(value, cur, str(ch))
                        cur += 1
                continue
            _cancel_check(ev)
            key := ev["key"]
            if key == "enter":
                result := _s.join("", value)
                if result == "" and default != null:
                    result = str(default)
                if validate != null:
                    msg := validate(result)
                    if msg != null and msg != true:
                        error = str(msg)
                        if msg == false:
                            error = "valeur invalide"
                        continue
                shown_final := result
                if password:
                    shown_final = _s.repeat("•", len(result))
                live.finish(["[green]✔[/] [bold]" + question + "[/] [cyan]" + _escape(shown_final) + "[/]"])
                return result
            elif key == "escape":
                live.finish(["[red]✘[/] [bold]" + question + "[/] [dim]annulé[/]"])
                return null
            elif key == "left":
                if cur > 0:
                    cur -= 1
            elif key == "right":
                if cur < len(value):
                    cur += 1
                elif choices != null:
                    c := _complete(_s.join("", value), choices)
                    if c != null:
                        value = [str(x) for x in c]
                        cur = len(value)
            elif key == "home" or key == "ctrl+a":
                cur = 0
            elif key == "end" or key == "ctrl+e":
                cur = len(value)
            elif key == "backspace":
                if cur > 0:
                    value = _remove(value, cur - 1)
                    cur -= 1
            elif key == "delete" or key == "ctrl+d":
                if cur < len(value):
                    value = _remove(value, cur)
            elif key == "ctrl+u":
                value = [value[i] for i in cur..len(value)]
                cur = 0
            elif key == "ctrl+k":
                value = [value[i] for i in 0..cur]
            elif key == "ctrl+w":
                k := cur
                while k > 0 and value[k - 1] == " ":
                    k -= 1
                while k > 0 and value[k - 1] != " ":
                    k -= 1
                value = _concat([value[i] for i in 0..k], [value[i] for i in cur..len(value)])
                cur = k
            elif key == "tab" and choices != null:
                c := _complete(_s.join("", value), choices)
                if c != null:
                    value = [str(x) for x in c]
                    cur = len(value)
            elif ev["text"] != null:
                value = _insert(value, cur, ev["text"])
                cur += 1
                error = null
    finally:
        keys.stop()

func _move_right(n):
    if n <= 0:
        return ""
    return "\e[" + str(n) + "C"

func _escape(text):
    return _s.replace(_s.replace(str(text), "\\", "\\\\"), "[", "\\[")

func _insert(items, at, x):
    out := [items[i] for i in 0..at]
    append(out, x)
    for i in at..len(items):
        append(out, items[i])
    return out

func _remove(items, at):
    return [items[i] for i in 0..len(items) if i != at]

func _concat(a, b):
    out := [x for x in a]
    for x in b:
        append(out, x)
    return out

# Plus long préfixe commun des choix qui commencent par text (ou le seul choix), null si aucun.
func _complete(text, choices):
    found := [c for c in choices if _s.starts_with(_s.lower(c), _s.lower(text))]
    if len(found) == 0:
        return null
    common := found[0]
    for c in found:
        k := 0
        while k < len(common) and k < len(c) and _s.lower(str(common[k])) == _s.lower(str(c[k])):
            k += 1
        common = _s.slice(common, 0, k)
    if len(common) < len(text):
        return null
    return common

func _parse_int(t):
    if t == "":
        return null
    neg := false
    if _s.starts_with(t, "-"):
        neg = true
        t = _s.slice(t, 1)
    if t == "":
        return null
    v := 0
    for c in t:
        if c < '0' or c > '9':
            return null
        v = v * 10 + _s.ord(c) - 48
    if neg:
        return -v
    return v

func _parse_number(t, integer):
    t = _s.replace(_s.trim(t), ",", ".")
    n := _parse_int(t)
    if n != null:
        return n
    if integer:
        return null
    try:
        return to_float(t)
    catch e:
        return null

# ---------------------------------------------------------------- confirm, number
# Question oui/non : o/y = oui, n = non, Entrée = défaut (si défini).
func confirm(question, default=null):
    hint := "[dim](o/n)[/]"
    if default == true:
        hint = "[dim](O/n)[/]"
    elif default == false:
        hint = "[dim](o/N)[/]"
    if not _interactive():
        _write(_mk.strip(question) + " (o/n) ")
        line := input()
        a := _s.lower(_s.trim(line))
        if a == "" and default != null:
            return default
        return a == "o" or a == "oui" or a == "y" or a == "yes"
    keys := _Keys()
    live := _Live()
    head := "[bold cyan]?[/] [bold]" + question + "[/] " + hint
    keys.start()
    try:
        while true:
            live.draw([head])
            ev := keys.read()
            _cancel_check(ev)
            k := _s.lower(ev["key"])
            answer := null
            if k == "o" or k == "y":
                answer = true
            elif k == "n":
                answer = false
            elif k == "enter" and default != null:
                answer = default
            elif k == "escape":
                answer = false
            if answer != null:
                word := "non"
                if answer:
                    word = "oui"
                live.finish(["[green]✔[/] [bold]" + question + "[/] [cyan]" + word + "[/]"])
                return answer
    finally:
        keys.stop()

# Nombre (entier si integer=true) borné par minimum / maximum.
func number(question, default=null, minimum=null, maximum=null, integer=false):
    func check(text):
        v := _parse_number(text, integer)
        if v == null:
            if integer:
                return "entier attendu"
            return "nombre attendu"
        if minimum != null and v < minimum:
            return "au moins " + str(minimum)
        if maximum != null and v > maximum:
            return "au plus " + str(maximum)
        return null
    r := prompt(question, default, check)
    if r == null:
        return null
    return _parse_number(r, integer)

# ---------------------------------------------------------------- tableaux et blocs
func _min(a, b):
    if a < b:
        return a
    return b

func _max(a, b):
    if a > b:
        return a
    return b

func _cell(text, width, align):
    plain := str(text)
    if _mk.width(plain) > width:
        plain = _w.truncate(_mk.strip(plain), width)
        return _w.pad(plain, width, align)
    gap := width - _mk.width(plain)
    if align == "right":
        return _s.repeat(" ", gap) + plain
    if align == "center":
        return _s.repeat(" ", gap // 2) + plain + _s.repeat(" ", gap - gap // 2)
    return plain + _s.repeat(" ", gap)

# Tableau en texte. rows : liste de listes ; headers : entêtes ; align : liste de "left" / "right" / "center"
# (par défaut, les colonnes de nombres sont alignées à droite) ; border : "round", "single", "double",
# "heavy", "ascii", "none" ; max_width : largeur maximale (celle du terminal par défaut).
func table(rows, headers=null, align=null, border="round", max_width=null, header_style="bold"):
    ncol := 0
    if headers != null:
        ncol = len(headers)
    for r in rows:
        if len(r) > ncol:
            ncol = len(r)
    if ncol == 0:
        return ""
    cells := []
    for r in rows:
        append(cells, [_fmt(r[i]) if i < len(r) else "" for i in 0..ncol])
    widths := [0 for i in 0..ncol]
    if headers != null:
        for i in 0..len(headers):
            widths[i] = _mk.width(str(headers[i]))
    numeric := [true for i in 0..ncol]
    for r in rows:
        for i in 0..len(r):
            if type(r[i]) != "int" and type(r[i]) != "float" and r[i] != null:
                numeric[i] = false
    for r in cells:
        for i in 0..ncol:
            widths[i] = _max(widths[i], _mk.width(r[i]))
    aligns := []
    for i in 0..ncol:
        if align != null and i < len(align) and align[i] != null:
            append(aligns, align[i])
        elif numeric[i] and len(rows) > 0:
            append(aligns, "right")
        else:
            append(aligns, "left")
    if max_width == null:
        max_width = term_width()
    sep := 3
    edges := 4
    if border == "none":
        sep = 2
        edges = 0
    total := edges + sep * (ncol - 1)
    for wd in widths:
        total += wd
    while total > max_width:
        big := 0
        for i in 0..ncol:
            if widths[i] > widths[big]:
                big = i
        if widths[big] <= 3:
            break
        widths[big] -= 1
        total -= 1
    lines := []
    if border == "none":
        if headers != null:
            append(lines, _s.join("  ", ["[" + header_style + "]" + _cell(headers[i] if i < len(headers) else "", widths[i], aligns[i]) + "[/]" for i in 0..ncol]))
        for r in cells:
            append(lines, _s.join("  ", [_cell(r[i], widths[i], aligns[i]) for i in 0..ncol]))
        return _join_lines(lines)
    b := _screen.box_chars(border)
    tees := _tees(border)
    append(lines, b[0] + _s.join(tees[0], [_s.repeat(b[4], widths[i] + 2) for i in 0..ncol]) + b[1])
    if headers != null:
        append(lines, b[5] + _s.join(b[5], [" [" + header_style + "]" + _cell(headers[i] if i < len(headers) else "", widths[i], aligns[i]) + "[/] " for i in 0..ncol]) + b[5])
        append(lines, tees[2] + _s.join(tees[4], [_s.repeat(b[4], widths[i] + 2) for i in 0..ncol]) + tees[3])
    for r in cells:
        append(lines, b[5] + _s.join(b[5], [" " + _cell(r[i], widths[i], aligns[i]) + " " for i in 0..ncol]) + b[5])
    append(lines, b[2] + _s.join(tees[1], [_s.repeat(b[4], widths[i] + 2) for i in 0..ncol]) + b[3])
    return _join_lines(lines)

func _fmt(v):
    if v == null:
        return ""
    if type(v) == "float":
        r := to_int(v * 100 + (0.5 if v >= 0 else -0.5)) / 100.0
        return str(r)
    return str(v)

# [haut, bas, gauche, droite, croix] des jonctions d'un cadre.
func _tees(border):
    if border == "double":
        return ["╦", "╩", "╠", "╣", "╬"]
    if border == "heavy":
        return ["┳", "┻", "┣", "┫", "╋"]
    if border == "ascii":
        return ["+", "+", "+", "+", "+"]
    return ["┬", "┴", "├", "┤", "┼"]

func _join_lines(lines):
    return _s.join("\n", lines)

func print_table(rows, headers=null, align=null, border="round", max_width=null):
    _write(_m(table(rows, headers, align, border, max_width)) + "\n")

# Arbre en texte. node : str (feuille), [libellé, [enfants]] ou {"label": ..., "children": [...]}.
func tree(node, guide="dim"):
    lines := []
    label := _tree_label(node)
    append(lines, label)
    _tree_children(_tree_kids(node), "", lines, guide)
    return _join_lines(lines)

func _tree_label(node):
    if type(node) == "dict":
        return str(node["label"])
    if type(node) == "list":
        return str(node[0])
    return str(node)

func _tree_kids(node):
    if type(node) == "dict":
        if contains_key(node, "children"):
            return node["children"]
        return []
    if type(node) == "list" and len(node) > 1:
        return node[1]
    return []

func _tree_children(kids, prefix, lines, guide):
    i := 0
    while i < len(kids):
        last := i == len(kids) - 1
        branch := "├── "
        more := "│   "
        if last:
            branch = "└── "
            more = "    "
        append(lines, "[" + guide + "]" + prefix + branch + "[/]" + _tree_label(kids[i]))
        _tree_children(_tree_kids(kids[i]), prefix + more, lines, guide)
        i += 1

func print_tree(node):
    _write(_m(tree(node)) + "\n")

# Panneau encadré autour d'un texte (plusieurs lignes possibles, balisage accepté).
func panel(text, title=null, border="round", width=null, padding=1, style="", title_style="bold"):
    content := []
    for line in _s.split(str(text), "\n"):
        append(content, line)
    inner := 0
    for line in content:
        inner = _max(inner, _mk.width(line))
    if title != null:
        inner = _max(inner, _mk.width(title) + 2)
    if width != null:
        inner = width - 2 - 2 * padding
    else:
        inner = _min(inner, term_width() - 2 - 2 * padding)
    b := _screen.box_chars(border)
    pad := _s.repeat(" ", padding)
    open_s := ""
    close_s := ""
    if style != "":
        open_s = "[" + style + "]"
        close_s = "[/]"
    lines := []
    top := b[4]
    if title != null:
        t := " [" + title_style + "]" + title + "[/] "
        rest := inner + 2 * padding - _mk.width(t) - 1
        top = b[4] + t + _s.repeat(b[4], _max(0, rest))
    else:
        top = _s.repeat(b[4], inner + 2 * padding)
    append(lines, open_s + b[0] + close_s + _wrap_style(top, style) + open_s + b[1] + close_s)
    for line in content:
        for part in _wrap_markup(line, inner):
            append(lines, open_s + b[5] + close_s + pad + _cell(part, inner, "left") + pad + open_s + b[5] + close_s)
    append(lines, open_s + b[2] + _s.repeat(b[4], inner + 2 * padding) + b[3] + close_s)
    return _join_lines(lines)

func _wrap_style(text, style):
    if style == "":
        return text
    return "[" + style + "]" + text + "[/]"

func _wrap_markup(line, width):
    if _mk.width(line) <= width:
        return [line]
    return [_escape(x) for x in _w.wrap(_mk.strip(line), width)]

func print_panel(text, title=null, border="round", width=null):
    _write(_m(panel(text, title, border, width)) + "\n")

# Ligne horizontale, avec un titre centré facultatif.
func rule(title=null, width=null, char="─", style="dim"):
    if width == null:
        width = term_width()
    if title == null or title == "":
        return "[" + style + "]" + _s.repeat(char, width) + "[/]"
    t := " " + title + " "
    side := _max(0, (width - _mk.width(t)) // 2)
    other := _max(0, width - _mk.width(t) - side)
    return "[" + style + "]" + _s.repeat(char, side) + "[/]" + t + "[" + style + "]" + _s.repeat(char, other) + "[/]"

func print_rule(title=null):
    _write(_m(rule(title)) + "\n")

# Éléments répartis en colonnes de même largeur (comme ls).
func columns(items, width=null, gap=2):
    if width == null:
        width = term_width()
    if len(items) == 0:
        return ""
    cw := 0
    for it in items:
        cw = _max(cw, _mk.width(str(it)))
    ncol := _max(1, (width + gap) // (cw + gap))
    nrow := (len(items) + ncol - 1) // ncol
    lines := []
    r := 0
    while r < nrow:
        parts := []
        c := 0
        while c < ncol:
            k := c * nrow + r
            if k < len(items):
                append(parts, _cell(str(items[k]), cw, "left"))
            c += 1
        append(lines, _rtrim(_s.join(_s.repeat(" ", gap), parts)))
        r += 1
    return _join_lines(lines)

func _rtrim(t):
    n := len(t)
    while n > 0 and t[n - 1] == ' ':
        n -= 1
    return _s.slice(t, 0, n)

# ---------------------------------------------------------------- progression
const _BLOCKS := ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]

func _bar(fraction, width):
    f := _max(0.0, _min(1.0, fraction))
    total := to_int(f * width * 8)
    full := total // 8
    part := total % 8
    out := _s.repeat("█", full)
    if full < width:
        out += _BLOCKS[part]
        out += _s.repeat(" ", width - full - (1 if part > 0 else 0))
    return out

func _duration(seconds):
    s := to_int(seconds + 0.5)
    if s >= 3600:
        return str(s // 3600) + ":" + _two((s // 60) % 60) + ":" + _two(s % 60)
    return str(s // 60) + ":" + _two(s % 60)

func _two(n):
    if n < 10:
        return "0" + str(n)
    return str(n)

class ProgressBar:
    # total : nombre d'étapes (null : progression indéterminée) ; width : largeur de la barre.
    func init(total=null, label="", width=30, unit="", interval=0.05):
        self.total = total
        self.label = label
        self.width = width
        self.unit = unit
        self.value = 0
        self.interval = interval
        self.started = _os.monotonic_time()
        self._last = -1.0
        self._tick = 0
        self.done = false

    func update(n=1):
        self.set(self.value + n)

    func set(value):
        self.value = value
        now := _os.monotonic_time()
        if now - self._last >= self.interval:
            self._last = now
            self._draw(false)

    # Ligne affichée (balisage) pour l'état courant.
    func line():
        elapsed := _os.monotonic_time() - self.started
        head := ""
        if self.label != "":
            head = "[bold]" + self.label + "[/] "
        if self.total == null or self.total <= 0:
            self._tick += 1
            pos := self._tick % (2 * self.width - 2)
            if pos >= self.width:
                pos = 2 * self.width - 2 - pos
            bar := _s.repeat(" ", pos) + "███" + _s.repeat(" ", _max(0, self.width - pos - 3))
            bar = _s.slice(bar, 0, self.width)
            return head + "[cyan]" + bar + "[/] " + str(self.value) + self.unit + " [dim]" + _duration(elapsed) + "[/]"
        frac := self.value / self.total
        pct := to_int(_min(1.0, frac) * 100)
        rate := ""
        eta := ""
        if elapsed > 0 and self.value > 0:
            r := self.value / elapsed
            rate = " [dim]" + _fmt(r) + self.unit + "/s[/]"
            if self.value < self.total:
                eta = " [dim]reste " + _duration((self.total - self.value) / r) + "[/]"
        p := str(pct)
        while len(p) < 3:
            p = " " + p
        return head + "[cyan]" + _bar(frac, self.width) + "[/] " + p + " % " + str(self.value) + "/" + str(self.total) + self.unit + rate + eta

    func _draw(final):
        if not _out_tty():
            if final:
                _write(_mk.strip(self.line()) + "\n")
            return
        text := _fit(self.line(), term_width() - 1)
        _write("\r\e[2K" + text)
        if final:
            _write("\n")

    func finish(label=null):
        if self.done:
            return
        if label != null:
            self.label = label
        if self.total != null and self.value < self.total:
            self.value = self.total
        self.done = true
        self._draw(true)

_SPINNERS := {"dots": ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"], "line": ["-", "\\", "|", "/"], "arc": ["◜", "◠", "◝", "◞", "◡", "◟"], "dots2": ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]}

func spinner_frames(kind="dots"):
    if not contains_key(_SPINNERS, kind):
        raise("ArgumentError", "tui : spinner inconnu '" + str(kind) + "' (dots, line, arc, dots2)")
    return _SPINNERS[kind]

class Spinner:
    func init(text="", kind="dots", interval=0.08):
        self.text = text
        self.frames = spinner_frames(kind)
        self.interval = interval
        self.index = 0
        self._last = -1.0
        self.started = _os.monotonic_time()

    # À appeler régulièrement : avance l'animation quand il le faut.
    func tick(text=null):
        if text != null:
            self.text = text
        now := _os.monotonic_time()
        if now - self._last < self.interval:
            return
        self._last = now
        self.index = (self.index + 1) % len(self.frames)
        if _out_tty():
            _write("\r\e[2K" + _m("[cyan]" + self.frames[self.index] + "[/] " + self.text))

    # Termine : remplace la ligne par final (« ✔ texte » par défaut, ok=false : « ✘ »).
    func stop(final=null, ok=true):
        mark := "[green]✔[/]"
        if not ok:
            mark = "[red]✘[/]"
        if final == null:
            final = self.text
        line := mark + " " + final
        if _out_tty():
            _write("\r\e[2K" + _m(line) + "\n")
        else:
            _write(_mk.strip(line) + "\n")

# Corps du fil d'animation de spin().
func _spin_worker(text, kind, interval, depth):
    frames := spinner_frames(kind)
    i := 0
    while true:
        line := "[cyan]" + frames[i % len(frames)] + "[/] " + text
        _cli.write_out("\r\e[2K" + _mk.render(line, depth))
        _cli.flush()
        try:
            msg := _thread.receive(interval)
            return null
        catch e:
            i += 1

# Exécute fn(args...) en affichant un spinner animé (dans un fil séparé) ; renvoie le résultat de fn.
# L'affichage se termine par « ✔ texte » (ou « ✘ texte » si fn lève une exception, relancée ensuite).
func spin(text, fn, args=null, kind="dots", done=null):
    if args == null:
        args = []
    if not _out_tty() or _IO["virtual"] or not _thread.supported():
        return _call(fn, args)
    t := _thread.spawn(_spin_worker, [text, kind, 0.08, _depth()])
    ok := false
    try:
        result := _call(fn, args)
        ok = true
        return result
    finally:
        t.send("stop")
        t.join()
        mark := "[green]✔[/] "
        if not ok:
            mark = "[red]✘[/] "
        final := text
        if done != null and ok:
            final = done
        _write("\r\e[2K" + _m(mark + final) + "\n")

func _call(fn, args):
    n := len(args)
    if n == 0:
        return fn()
    if n == 1:
        return fn(args[0])
    if n == 2:
        return fn(args[0], args[1])
    if n == 3:
        return fn(args[0], args[1], args[2])
    if n == 4:
        return fn(args[0], args[1], args[2], args[3])
    raise("ArgumentError", "tui.spin : au plus 4 arguments")
