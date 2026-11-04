# ALEX STANDARD LIBRARY — io.console
#
# Terminal : écrire sans saut de ligne, couleurs et styles (ANSI), curseur, taille de la fenêtre, et saisie
# au-delà d'input() : touches une à une (flèches, Échap...), mot de passe sans écho, confirmation, menu.
#
# Couleurs : style() n'ajoute les codes ANSI que si la sortie est un terminal qui les accepte (variable
# NO_COLOR absente, TERM différent de « dumb ») ; force=true les ajoute toujours. strip_styles() les retire.
#
# Saisie en mode brut (read_key, read_password) : le terminal retrouve ses réglages ensuite, et aussi si le
# programme s'arrête net (atexit). Hors terminal (entrée redirigée), read_password lit simplement une ligne et
# read_key un caractère.
#
# Exemple
#   use io.console as console
#   console.write_line(console.style("succès", "green", bold=true))
#   nom := console.read_line("Nom : ")
#   if console.confirm("Continuer ?", true):
#       ...
#   k := console.read_key()            # "up", "enter", "a", "ctrl+c"...

from core use len, type, to_int
from collections use append, contains_key
use string as _s
use os as _os
use _native_fd as _f
use _native_cli as _cli

const ESC := str(_s.chr(27))
const _BEL := str(_s.chr(7))
const _DEL := str(_s.chr(127))
const _BS := str(_s.chr(8))

# ---------------------------------------------------------------- écriture
func write(text):
    _cli.write_out(str(text))

func write_line(text=""):
    _cli.write_out(str(text) + "\n")

# Sur la sortie d'erreur (stderr).
func error(text):
    _cli.write_err(str(text))

func error_line(text=""):
    _cli.write_err(str(text) + "\n")

func flush():
    _cli.flush()

# ---------------------------------------------------------------- terminal
# Vrai si le flux ("stdin", "stdout", "stderr") est un terminal.
func is_terminal(stream="stdout"):
    fds := {"stdin": 0, "stdout": 1, "stderr": 2}
    if not contains_key(fds, stream):
        raise("ArgumentError", "console.is_terminal : flux stdin, stdout ou stderr attendu")
    return _f.isatty(fds[stream])

# (colonnes, lignes) du terminal ; (80, 24) si inconnues (sortie redirigée).
func size():
    t := _os.terminal()
    cols := t["columns"]
    rows := t["rows"]
    if cols == null:
        cols = 80
    if rows == null:
        rows = 24
    return (cols, rows)

func colors_enabled():
    return _os.terminal()["color"]

# ---------------------------------------------------------------- styles
_COLORS := {"black": 0, "red": 1, "green": 2, "yellow": 3, "blue": 4, "magenta": 5, "cyan": 6, "white": 7, "gray": 60, "grey": 60, "bright_red": 61, "bright_green": 62, "bright_yellow": 63, "bright_blue": 64, "bright_magenta": 65, "bright_cyan": 66, "bright_white": 67}

func _color_code(name, base, fn):
    if not contains_key(_COLORS, name):
        raise("ArgumentError", "console." + fn + " : couleur inconnue '" + str(name) + "'")
    return str(base + _COLORS[name])

# text avec une couleur (color, background : noms de couleurs) et des attributs. Sans effet si les couleurs ne
# sont pas actives (voir en tête), sauf force=true.
func style(text, color=null, background=null, bold=false, dim=false, italic=false, underline=false, force=false):
    if not force and not colors_enabled():
        return str(text)
    codes := []
    if bold:
        append(codes, "1")
    if dim:
        append(codes, "2")
    if italic:
        append(codes, "3")
    if underline:
        append(codes, "4")
    if color != null:
        append(codes, _color_code(color, 30, "style"))
    if background != null:
        append(codes, _color_code(background, 40, "style"))
    if len(codes) == 0:
        return str(text)
    return ESC + "[" + _s.join(";", codes) + "m" + str(text) + ESC + "[0m"

# Couleur exacte (0..255 par composante), sur les terminaux « 24 bits ».
func rgb(text, r, g, b, force=false):
    for c in [r, g, b]:
        if type(c) != "int" or c < 0 or c > 255:
            raise("ArgumentError", "console.rgb : composantes 0..255 attendues")
    if not force and not colors_enabled():
        return str(text)
    return ESC + "[38;2;" + str(r) + ";" + str(g) + ";" + str(b) + "m" + str(text) + ESC + "[0m"

# Retire les codes ANSI (couleurs, curseur) d'un texte.
func strip_styles(text):
    out := ""
    i := 0
    n := len(text)
    while i < n:
        c := text[i]
        if _s.ord(c) == 27 and i + 1 < n and text[i + 1] == '[':
            i += 2
            while i < n and not ((text[i] >= '@' and text[i] <= '~') and text[i] != '['):
                i += 1
            i += 1
            continue
        out += str(c)
        i += 1
    return out

# Largeur affichée (en colonnes) : longueur sans les codes ANSI.
func visible_length(text):
    return len(strip_styles(text))

# ---------------------------------------------------------------- curseur et écran
func clear():
    write(ESC + "[2J" + ESC + "[H")

func clear_line():
    write("\r" + ESC + "[2K")

# Place le curseur (colonnes et lignes comptées à partir de 1).
func move_to(column, row):
    write(ESC + "[" + str(row) + ";" + str(column) + "H")

func move_up(n=1):
    write(ESC + "[" + str(n) + "A")

func move_down(n=1):
    write(ESC + "[" + str(n) + "B")

func hide_cursor():
    write(ESC + "[?25l")

func show_cursor():
    write(ESC + "[?25h")

func bell():
    write(_BEL)

# Barre de progression « [#####.....]  50 % » (fraction de 0 à 1) ; à afficher avec write("\r" + ...).
func progress_bar(fraction, width=30, fill="#", empty="."):
    f := fraction
    if f < 0:
        f = 0
    if f > 1:
        f = 1
    k := to_int(f * width)
    pct := to_int(f * 100 + 0.5)
    bar := _s.repeat(fill, k) + _s.repeat(empty, width - k)
    p := str(pct)
    while len(p) < 3:
        p = " " + p
    return "[" + bar + "] " + p + " %"

# ---------------------------------------------------------------- saisie
# Une ligne de l'entrée (sans la fin de ligne), avec une invite facultative.
func read_line(prompt=null):
    if prompt != null:
        write(prompt)
        flush()
    return input()

func _read_byte(timeout):
    r := _f.read(0, 1, timeout)
    if r == null:
        return null
    if type(r) == "int":
        raise("IoError", "console : lecture de l'entrée impossible (" + _f.strerror(r) + ")")
    return r

# Mot de passe saisi sans écho (une ligne). Hors terminal : une ligne ordinaire.
func read_password(prompt="Mot de passe : "):
    write(prompt)
    flush()
    if not _f.isatty(0):
        return input()
    _f.set_mode(0, false, false)
    out := ""
    try:
        while true:
            b := _read_byte(null)
            if b == "" or b == "\n" or b == "\r":
                break
            if b == _DEL or b == _BS:
                if out != "":
                    out = _s.slice(out, 0, -1)
                continue
            out = out + b
    finally:
        _f.restore(0)
        write("\n")
        flush()
    return out

_KEYS := {ESC + "[A": "up", ESC + "[B": "down", ESC + "[C": "right", ESC + "[D": "left", ESC + "[H": "home", ESC + "[F": "end", ESC + "OH": "home", ESC + "OF": "end", ESC + "[1~": "home", ESC + "[4~": "end", ESC + "[2~": "insert", ESC + "[3~": "delete", ESC + "[5~": "page_up", ESC + "[6~": "page_down", ESC + "OP": "f1", ESC + "OQ": "f2", ESC + "OR": "f3", ESC + "OS": "f4"}

# Nom d'une séquence de touche lue en mode brut.
func key_name(seq):
    if contains_key(_KEYS, seq):
        return _KEYS[seq]
    if seq == "\r" or seq == "\n":
        return "enter"
    if seq == "\t":
        return "tab"
    if seq == _DEL or seq == _BS:
        return "backspace"
    if seq == ESC:
        return "escape"
    if seq == " ":
        return "space"
    if len(seq) == 1:
        code := _s.ord(seq[0])
        if code >= 1 and code <= 26:
            return "ctrl+" + str(_s.chr(code + 96))
    return seq

# Prochaine touche (sans attendre Entrée) : un caractère, ou un nom (« up », « enter », « escape »,
# « ctrl+c », « f1 »...). null si timeout secondes passent sans touche.
func read_key(timeout=null):
    raw := _f.isatty(0)
    if raw:
        _f.set_mode(0, true, false)
    try:
        b := _read_byte(timeout)
        if b == null:
            return null
        if b == "":
            return "eof"
        seq := b
        if b == ESC:
            # Séquence d'échappement : les octets suivants arrivent aussitôt (sinon c'est la touche Échap).
            nxt := _read_byte(0.03)
            while nxt != null and nxt != "":
                seq = seq + nxt
                last := _s.ord(nxt[0])
                if len(seq) >= 3 and ((last >= 65 and last <= 90) or nxt == "~" or (len(seq) == 3 and _s.starts_with(seq, ESC + "O"))):
                    break
                nxt = _read_byte(0.03)
        else:
            # Caractère UTF-8 sur plusieurs octets : le compléter.
            code := _s.ord(b[0])
            if len(b) == 1 and code >= 192:
                more := 1
                if code >= 240:
                    more = 3
                elif code >= 224:
                    more = 2
                k := 0
                while k < more:
                    nxt2 := _read_byte(0.1)
                    if nxt2 == null or nxt2 == "":
                        break
                    seq = seq + nxt2
                    k += 1
        return key_name(seq)
    finally:
        if raw:
            _f.restore(0)

# Question oui/non ; default (true/false/null) choisi sur une ligne vide. Accepte o/oui/y/yes et n/non/no.
func confirm(question, default=null):
    hint := " [o/n] "
    if default == true:
        hint = " [O/n] "
    elif default == false:
        hint = " [o/N] "
    while true:
        answer := _s.lower(_s.trim(read_line(question + hint)))
        if answer == "" and default != null:
            return default
        if answer == "o" or answer == "oui" or answer == "y" or answer == "yes":
            return true
        if answer == "n" or answer == "non" or answer == "no":
            return false
        write_line("Répondre o (oui) ou n (non).")

# Menu numéroté ; renvoie l'indice (à partir de 0) de l'option choisie.
func choose(question, options):
    if type(options) != "list" or len(options) == 0:
        raise("ArgumentError", "console.choose : list non vide d'options attendue")
    write_line(question)
    i := 0
    while i < len(options):
        write_line("  " + str(i + 1) + ". " + str(options[i]))
        i += 1
    while true:
        answer := _s.trim(read_line("Choix (1-" + str(len(options)) + ") : "))
        ok := answer != ""
        for c in answer:
            if c < '0' or c > '9':
                ok = false
        if ok:
            n := to_int(answer)
            if n >= 1 and n <= len(options):
                return n - 1
        write_line("Choix invalide.")
