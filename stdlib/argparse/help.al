# ALEX STANDARD LIBRARY — argparse.help
#
# Génération de l'usage et de l'aide. Fonctions pures qui lisent un ArgumentParser
# (champs : prog description epilog usage_text args groups mutexes sub width
# show_defaults raw_text). Utilisées par parser.al, completion.al et manpage.al.

from core use len, type
from collections use append, contains
use string as _s
use os as _os
use argparse.text as _t

const _PCT := "@@PCT@@"

# --- largeur ---------------------------------------------------------------

# Largeur d'aide : parser.width, sinon colonnes du terminal (80 par défaut) - 2.
func help_width(parser):
    if parser.width != null:
        return parser.width
    cols := 80
    t := _os.terminal()
    if t["columns"] != null and t["columns"] > 20:
        cols = t["columns"]
    return cols - 2

# --- métavars ----------------------------------------------------------------

func choices_text(choices, sep=","):
    return _t.join(sep, _t.stringify(choices))

func sub_names(sp):
    out := []
    for p in sp.commands:
        if not p.hidden:
            append(out, p.name)
    return out

# Nom d'une valeur (un seul "slot") : metavar explicite, {choix}, ou dest.
func metavar_of(arg):
    mv := arg.metavar
    if type(mv) == "str":
        return mv
    if type(mv) == "list" and len(mv) > 0:
        return str(mv[0])
    if arg.action == "parser":
        return "{" + choices_text(sub_names(arg.sub)) + "}"
    if arg.choices != null:
        return "{" + choices_text(arg.choices) + "}"
    if arg.positional:
        return arg.dest
    return _t.upper(arg.dest)

# Les `n` métavars d'un nargs entier (un metavar liste en fournit un par valeur).
func metavar_n(arg, n):
    out := []
    mv := arg.metavar
    i := 0
    while i < n:
        if type(mv) == "list" and i < len(mv):
            append(out, str(mv[i]))
        else:
            append(out, metavar_of(arg))
        i = i + 1
    return out

func takes_value(arg):
    a := arg.action
    if a == "store" or a == "append" or a == "extend":
        return true
    return false

# Jetons d'usage pour les valeurs d'un argument (liste, un jeton = une unité insécable).
func nargs_tokens(arg):
    n := arg.nargs
    m := metavar_of(arg)
    if arg.action == "parser":
        return [m, "..."]
    if n == null:
        return [m]
    if n == "?":
        return ["[" + m + "]"]
    if n == "*":
        return ["[" + m + " ...]"]
    if n == "+":
        return [m, "[" + m + " ...]"]
    if n == "remainder":
        return ["..."]
    return metavar_n(arg, n)

func nargs_text(arg):
    return _t.join(" ", nargs_tokens(arg))

# --- usage ---------------------------------------------------------------------

# Jeton d'usage d'un optionnel ("[-f FOO]", "--req BAR"), ou "" si caché.
func optional_token(arg):
    if arg.hidden:
        return ""
    part := ""
    if arg.action == "boolean_optional":
        part = _t.join(" | ", arg.names)
    else:
        part = arg.names[0]
        if takes_value(arg):
            part = part + " " + nargs_text(arg)
    if arg.required:
        return part
    return "[" + part + "]"

# ([jetons optionnels], [jetons positionnels]) ; les groupes exclusifs forment UN jeton.
func usage_tokens(parser):
    opt := []
    pos := []
    emitted := []
    for arg in parser.args:
        if arg.hidden:
            continue
        if arg.positional:
            for tok in nargs_tokens(arg):
                append(pos, tok)
            continue
        if arg.mutex != null:
            g := arg.mutex
            if contains(emitted, g.id):
                continue
            append(emitted, g.id)
            parts := []
            for m in g.args:
                if m.hidden:
                    continue
                if m.action == "boolean_optional":
                    append(parts, _t.join(" | ", m.names))
                else:
                    p := m.names[0]
                    if takes_value(m):
                        p = p + " " + nargs_text(m)
                    append(parts, p)
            if len(parts) == 0:
                continue
            body := _t.join(" | ", parts)
            if g.required:
                append(opt, "(" + body + ")")
            else:
                append(opt, "[" + body + "]")
            continue
        tok := optional_token(arg)
        if tok != "":
            append(opt, tok)
    return [opt, pos]

# Port de la coupure d'argparse : retourne les lignes (la première sans indentation si prefix).
func _get_lines(parts, indent, text_width, prefix=null):
    lines := []
    cur := []
    line_len := 0
    if prefix != null:
        line_len = len(prefix) - 1
    else:
        line_len = len(indent) - 1
    for part in parts:
        if line_len + 1 + len(part) > text_width and len(cur) > 0:
            append(lines, indent + _t.join(" ", cur))
            cur = []
            line_len = len(indent) - 1
        append(cur, part)
        line_len = line_len + len(part) + 1
    if len(cur) > 0:
        append(lines, indent + _t.join(" ", cur))
    if prefix != null and len(lines) > 0:
        lines[0] = _t.from_index(lines[0], len(indent))
    return lines

func expand_prog(text, parser):
    return _t.replace_all(text, "%(prog)s", parser.prog)

# "usage: prog [-h] ..." (sans saut de ligne final).
func format_usage(parser):
    if parser.usage_text != null:
        return _t.msg("usage") + expand_prog(parser.usage_text, parser)
    prefix := _t.msg("usage")
    parts := usage_tokens(parser)
    opt := parts[0]
    pos := parts[1]
    prog := parser.prog
    all := [prog]
    for t in opt:
        append(all, t)
    for t in pos:
        append(all, t)
    flat := prefix + _t.join(" ", all)
    width := help_width(parser)
    if len(flat) <= width:
        return flat
    text_width := width
    lines := []
    if len(prefix) + len(prog) <= 0.75 * text_width:
        indent := _t.spaces(len(prefix) + len(prog) + 1)
        if len(opt) > 0:
            first := [prog]
            for t in opt:
                append(first, t)
            lines = _get_lines(first, indent, text_width, prefix)
            for l in _get_lines(pos, indent, text_width):
                append(lines, l)
        elif len(pos) > 0:
            first := [prog]
            for t in pos:
                append(first, t)
            lines = _get_lines(first, indent, text_width, prefix)
        else:
            lines = [prog]
    else:
        indent := _t.spaces(len(prefix))
        merged := []
        for t in opt:
            append(merged, t)
        for t in pos:
            append(merged, t)
        lines = _get_lines(merged, indent, text_width)
        if len(lines) > 1:
            lines = []
            for l in _get_lines(opt, indent, text_width):
                append(lines, l)
            for l in _get_lines(pos, indent, text_width):
                append(lines, l)
        with_prog := [prog]
        for l in lines:
            append(with_prog, l)
        lines = with_prog
    return prefix + _t.lines_text(lines)

# --- texte d'aide d'un argument --------------------------------------------------

func default_text(value):
    if type(value) == "list":
        return "[" + _t.join(", ", _t.stringify(value)) + "]"
    return str(value)

func type_name(arg):
    if type(arg.type) == "str":
        return arg.type
    if arg.type == null:
        return "str"
    return "value"

# Remplace %(prog)s %(default)s %(choices)s %(metavar)s %(dest)s %(const)s %(type)s %(nargs)s et %%.
func expand_help(text, arg, parser):
    t := _t.replace_all(text, "%%", _PCT)
    t = _t.replace_all(t, "%(prog)s", parser.prog)
    t = _t.replace_all(t, "%(dest)s", arg.dest)
    t = _t.replace_all(t, "%(metavar)s", metavar_of(arg))
    t = _t.replace_all(t, "%(type)s", type_name(arg))
    if _t.contains_text(t, "%(default)s"):
        d := ""
        if arg.default != null:
            d = default_text(arg.default)
        t = _t.replace_all(t, "%(default)s", d)
    if _t.contains_text(t, "%(const)s"):
        c := ""
        if arg.constant != null:
            c = default_text(arg.constant)
        t = _t.replace_all(t, "%(const)s", c)
    if _t.contains_text(t, "%(choices)s"):
        c2 := ""
        if arg.choices != null:
            c2 = choices_text(arg.choices, ", ")
        t = _t.replace_all(t, "%(choices)s", c2)
    if _t.contains_text(t, "%(nargs)s"):
        n := ""
        if arg.nargs != null:
            n = str(arg.nargs)
        t = _t.replace_all(t, "%(nargs)s", n)
    return _t.replace_all(t, _PCT, "%")

# Aide d'un argument avec défauts automatiques si parser.show_defaults.
func help_of(arg, parser):
    text := arg.help
    if text == null:
        text = ""
    text = expand_help(text, arg, parser)
    if parser.show_defaults and arg.default != null and takes_value(arg):
        raw_help := arg.help
        if raw_help == null:
            raw_help = ""
        if not _t.contains_text(raw_help, "%(default)"):
            suffix := _t.fmt("default_fmt", [default_text(arg.default)])
            if text == "":
                text = suffix
            else:
                text = text + " " + suffix
    return text

# "-f FOO, --foo FOO" / "{a,b}" / "FILE".
func invocation(arg):
    if arg.positional:
        return metavar_of(arg)
    if not takes_value(arg):
        return _t.join(", ", arg.names)
    vals := nargs_text(arg)
    out := []
    for n in arg.names:
        append(out, n + " " + vals)
    return _t.join(", ", out)

# --- sections ----------------------------------------------------------------------

# Éléments d'une section : [[invocation, aide, indent, est_sous_action], ...].
func section_items(parser, group):
    items := []
    for arg in group.args:
        if arg.hidden:
            continue
        append(items, [invocation(arg), help_of(arg, parser), 2])
        if arg.action == "parser":
            for p in arg.sub.commands:
                if p.hidden:
                    continue
                label := p.name
                if len(p.aliases) > 0:
                    label = p.name + " (" + _t.join(", ", p.aliases) + ")"
                h := p.help_text
                if h == null:
                    h = ""
                append(items, [label, h, 4])
    return items

func _render_item(item, help_position, width):
    inv := item[0]
    h := item[1]
    indent := item[2]
    action_width := help_position - indent - 2
    help_width_ := width - help_position
    if help_width_ < 11:
        help_width_ = 11
    lines := []
    hl := _t.wrap(h, help_width_)
    if h == "":
        append(lines, _t.spaces(indent) + inv)
    elif len(inv) <= action_width:
        append(lines, _t.spaces(indent) + _t.pad(inv, action_width) + "  " + hl[0])
        i := 1
        while i < len(hl):
            append(lines, _t.spaces(help_position) + hl[i])
            i = i + 1
    else:
        append(lines, _t.spaces(indent) + inv)
        for l in hl:
            append(lines, _t.spaces(help_position) + l)
    return lines

func _wrap_block(text, width, raw):
    if raw:
        return _t.raw_lines(text)
    return _t.wrap(text, width)

func format_help(parser):
    width := help_width(parser)
    # position de la colonne d'aide (comme HelpFormatter) : globale à toute l'aide
    longest := 0
    for g in parser.groups:
        for item in section_items(parser, g):
            l := len(item[0]) + item[2]
            if l > longest:
                longest = l
    max_help_position := 24
    if width - 20 < max_help_position:
        max_help_position = width - 20
    if max_help_position < 4:
        max_help_position = 4
    help_position := longest + 2
    if help_position > max_help_position:
        help_position = max_help_position
    out := [format_usage(parser)]
    if parser.description != null and parser.description != "":
        append(out, "")
        for l in _wrap_block(expand_prog(parser.description, parser), width, parser.raw_text):
            append(out, l)
    for g in parser.groups:
        items := section_items(parser, g)
        if len(items) == 0:
            continue
        append(out, "")
        append(out, g.title + ":")
        if g.description != null and g.description != "":
            for l in _wrap_block(g.description, width - 2, parser.raw_text):
                append(out, "  " + l)
            append(out, "")
        for item in items:
            for l in _render_item(item, help_position, width):
                append(out, l)
    if parser.epilog != null and parser.epilog != "":
        append(out, "")
        for l in _wrap_block(expand_prog(parser.epilog, parser), width, parser.raw_text):
            append(out, l)
    return _t.lines_text(out) + "\n"
