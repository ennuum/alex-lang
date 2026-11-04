# ALEX STANDARD LIBRARY — argparse.manpage
#
# Génère des pages de manuel (roff, macros man(7)) depuis un ArgumentParser :
#
#   parser.format_man(1, "2026-10-07")      page du parseur (NOM, SYNOPSIS, DESCRIPTION,
#                                             OPTIONS, ARGUMENTS, COMMANDES, VOIR AUSSI, AUTEUR)
#   parser.man_pages(1, "2026-10-07")       {"prog.1": ..., "prog-sous.1": ...} : une page par
#                                             commande et sous-commande (style git-commit(1))
#
# Écrire une page :  file.write("tool.1", parser.format_man())   puis   man ./tool.1
#
# Échappements roff : \ -> \e, - -> \- dans les options/commandes, ligne commençant par
# . ou ' protégée par \&. Les titres de section suivent la langue d'argparse
# (argparse.text.set_language : "fr" NOM/COMMANDES..., "en" NAME/COMMANDS...).

from core use len, type
from collections use append, keys
use argparse.text as _t
use argparse.help as _h
use argparse.completion as _c

# --- échappements ----------------------------------------------------------------

func esc(text):
    t := _t.replace_all(text, "\\", "\\e")
    return t

# Texte courant : \ échappé ; une ligne qui commencerait par . ou ' est protégée.
func prose(text):
    out := []
    for line in _t.raw_lines(esc(text)):
        if _t.starts_with(line, ".") or _t.starts_with(line, "'"):
            append(out, "\\&" + line)
        else:
            append(out, line)
    return _t.lines_text(out)

# Option / commande : tirets insécables à l'impression (\-).
func dashes(text):
    return _t.replace_all(esc(text), "-", "\\-")

func bold(text):
    return "\\fB" + dashes(text) + "\\fR"

func italic(text):
    return "\\fI" + dashes(text) + "\\fR"

# Décore un jeton d'usage : mots commençant par - en gras, métavars en italique.
func decorate(token):
    out := []
    for w in _t.words(token):
        lead := ""
        trail := ""
        core := w
        while len(core) > 0 and (_t.char_at(core, 0) == "[" or _t.char_at(core, 0) == "("):
            lead = lead + _t.char_at(core, 0)
            core = _t.from_index(core, 1)
        while len(core) > 0 and (_t.char_at(core, len(core) - 1) == "]" or _t.char_at(core, len(core) - 1) == ")"):
            trail = _t.char_at(core, len(core) - 1) + trail
            core = _t.head(core, len(core) - 1)
        piece := ""
        if core == "" or core == "|" or core == "...":
            piece = esc(core)
        elif _t.starts_with(core, "-"):
            piece = bold(core)
        else:
            piece = italic(core)
        append(out, esc(lead) + piece + esc(trail))
    return _t.join(" ", out)

# --- structure --------------------------------------------------------------------

func _first_line(text):
    if text == null:
        return ""
    ws := _t.words(text)
    if len(ws) == 0:
        return ""
    return _t.join(" ", ws)

func _paragraphs(text):
    out := []
    cur := []
    for line in _t.raw_lines(text):
        if _t.words(line) == []:
            if len(cur) > 0:
                append(out, _t.join("\n", cur))
                cur = []
        else:
            append(cur, line)
    if len(cur) > 0:
        append(out, _t.join("\n", cur))
    return out

func _root(parser):
    w := _t.words(parser.prog)
    if len(w) == 0:
        return "prog"
    return w[0]

# Nom de page : « tool-add » pour le parseur « tool add ».
func page_name(parser):
    return _t.replace_all(_t.join(" ", _t.words(parser.prog)), " ", "-")

func _option_entry(arg, parser):
    heads := []
    for n in arg.names:
        h := bold(n)
        if _h.takes_value(arg):
            h = h + " " + decorate(_h.nargs_text(arg))
        append(heads, h)
    return ".TP\n" + _t.join(", ", heads) + "\n" + prose(_h.help_of(arg, parser))

func _synopsis(parser):
    toks := _h.usage_tokens(parser)
    all := []
    for t in toks[0]:
        append(all, t)
    for t in toks[1]:
        append(all, t)
    pieces := []
    for t in all:
        append(pieces, decorate(t))
    return ".B " + dashes(parser.prog) + "\n" + _t.join(" ", pieces)

func format_man(parser, section, date, source, manual, author):
    name := page_name(parser)
    root := _root(parser)
    sec := str(section)
    d := ""
    if date != null:
        d = str(date)
    src := source
    if src == null:
        src = parser.prog
        if parser.version != null:
            v := _t.replace_all(str(parser.version), "%(prog)s", parser.prog)
            if _t.contains_text(v, parser.prog):
                src = v
            else:
                src = parser.prog + " " + v
    man := manual
    if man == null:
        man = _t.fmt("man_manual", [root])
    L := []
    append(L, ".\\\" Page de manuel générée par argparse")
    append(L, ".TH \"" + _t.upper(dashes(name)) + "\" \"" + sec + "\" \"" + esc(d) + "\" \"" + esc(src) + "\" \"" + esc(man) + "\"")
    append(L, ".SH " + _t.msg("man_name"))
    summary := _first_line(parser.help_text)
    if summary == "":
        summary = _first_line(parser.description)
    if summary == "":
        append(L, dashes(name))
    else:
        append(L, dashes(name) + " \\- " + esc(summary))
    append(L, ".SH " + _t.msg("man_synopsis"))
    append(L, _synopsis(parser))
    if parser.description != null and parser.description != "":
        append(L, ".SH " + _t.msg("man_description"))
        first := true
        for para in _paragraphs(_t.replace_all(parser.description, "%(prog)s", parser.prog)):
            if not first:
                append(L, ".PP")
            first = false
            append(L, prose(para))
    opts := _c.options_of(parser)
    if len(opts) > 0:
        append(L, ".SH " + _t.msg("man_options"))
        for a in opts:
            append(L, _option_entry(a, parser))
    pos := _c.positionals_of(parser)
    if len(pos) > 0:
        append(L, ".SH " + _t.msg("man_arguments"))
        for a in pos:
            append(L, ".TP\n" + italic(_h.metavar_of(a)) + "\n" + prose(_h.help_of(a, parser)))
    visible := []
    if parser.sub != null:
        for c in parser.sub.commands:
            if not c.hidden:
                append(visible, c)
    if len(visible) > 0:
        append(L, ".SH " + _t.msg("man_commands"))
        for c in visible:
            label := bold(page_name(c)) + "(" + sec + ")"
            if len(c.aliases) > 0:
                label = label + " (" + dashes(_t.join(", ", c.aliases)) + ")"
            h := c.help_text
            if h == null:
                h = c.description
            if h == null:
                h = ""
            append(L, ".TP\n" + label + "\n" + prose(_first_line(h)))
    refs := []
    if parser.parent != null:
        append(refs, bold(page_name(parser.parent)) + "(" + sec + ")")
    for c in visible:
        append(refs, bold(page_name(c)) + "(" + sec + ")")
    if len(refs) > 0:
        append(L, ".SH " + _t.msg("man_see_also"))
        append(L, _t.join(",\n", refs))
    if author != null:
        append(L, ".SH " + _t.msg("man_author"))
        append(L, prose(str(author)))
    if parser.epilog != null and parser.epilog != "":
        append(L, ".PP")
        append(L, prose(_t.replace_all(parser.epilog, "%(prog)s", parser.prog)))
    return _t.lines_text(L) + "\n"

# {"prog.1": roff, "prog-sous.1": roff, ...} pour tout l'arbre (hors sous-commandes cachées).
func man_pages(parser, section, date, source, manual, author):
    out := {}
    ns := _c.nodes(parser, _root(parser))
    for n in ns:
        p := n["parser"]
        out[page_name(p) + "." + str(section)] = format_man(p, section, date, source, manual, author)
    return out
