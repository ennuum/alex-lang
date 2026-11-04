# ALEX STANDARD LIBRARY — web.css.css_writer
#
# Écriture de CSS : feuilles, règles et listes de règles vers du texte (lisible, indenté ou compact), avec
# options (tri des propriétés, résolution de l'imbrication pour les anciens navigateurs, en-tête, fusion des
# @media identiques), et construction rapide depuis des dicts ALEX.
#
#   use web.css.css_writer as cw
#   cw.write(sheet)                                 # une règle par ligne
#   cw.write(sheet, cw.Writer(true))                # indenté (2 espaces)
#   cw.Writer(true, "    ", false, true).write(sheet)       # 4 espaces, propriétés triées
#   w := cw.Writer(true); w.flatten = true; w.header = "Thème clair"
#   w.write(sheet)                                  # imbrication résolue, /* Thème clair */ en tête
#   cw.from_dict({"body": {"margin": 0}, "@media (max-width: 600px)": {"nav": {"display": "none"}}})
#   cw.inline_style({"color": "red", "font_size": "12px"})   # color: red; font-size: 12px
#   cw.save("site.css", sheet, cw.Writer(true))
#
# Erreurs : CssError (structure de dict invalide), IOError (save).

from core use len, type
from collections use append, keys
use string as _s
use io as _io
use web.css.css_errors as _err
use web.css.css_rule as _rule
use web.css.at_rule as _at
use web.css.declaration as _decl
use web.css.stylesheet as _sheet
use web.css.keyframes as _kf

class Writer:
    func init(pretty=false, indent="  ", compact=false, sort=false):
        self.pretty = pretty
        self.indent = indent
        self.compact = compact
        self.sort = sort
        self.flatten = false          # imbrication résolue (sélecteurs complets)
        self.header = null            # commentaire d'en-tête
        self.merge_media = false      # @media de même requête fusionnées (ordre de la première)
        self.final_newline = true
        self.blank_lines = true       # ligne vide entre règles (mode pretty)

    func format():
        return _rule.Format(self.pretty, self.indent, self.compact, self.sort)

    func _rules_of(target):
        if isinstance(target, _sheet.Stylesheet):
            return target.rules
        if type(target) == "list":
            return target
        return [target]

    func prepare(rules):
        out := []
        if self.flatten:
            for r in rules:
                if r.kind == "style":
                    for x in r.flatten():
                        append(out, x)
                elif r.kind == "at":
                    append(out, r.flatten())
                else:
                    append(out, r)
        else:
            out = rules
        if self.merge_media:
            out = merge_media(out)
        return out

    func write(target):
        f := self.format()
        parts := []
        for r in self.prepare(self._rules_of(target)):
            append(parts, r.to_css(f, 0))
        sep := ""
        if not self.compact:
            sep = "\n\n" if self.pretty and self.blank_lines else "\n"
        text := _s.join(sep, parts)
        if self.header != null:
            h := "/* " + _s.replace(str(self.header), "*/", "* /") + " */"
            text = h + ("" if self.compact else "\n") + text
        if self.final_newline and not self.compact and text != "":
            text = text + "\n"
        return text

# Fusionne les @media de même requête (premier niveau), le contenu rejoignant la première occurrence.
func merge_media(rules):
    out := []
    seen := {}
    for r in rules:
        if r.kind == "at" and r.name == "media":
            key := r.prelude
            if key in seen:
                target := out[seen[key]]
                for c in r.rules:
                    target.add(c.copy())
                continue
            c := r.copy()
            seen[key] = len(out)
            append(out, c)
        else:
            append(out, r)
    return out

# Texte CSS d'une feuille, d'une règle ou d'une liste de règles.
func write(target, writer=null):
    w := writer if writer != null else Writer()
    return w.write(target)

func pretty(target):
    return Writer(true).write(target)

func compact(target):
    return Writer(false, "", true).write(target)

func save(path, target, writer=null):
    _io.write_file(path, write(target, writer))
    return path

# Règles depuis un dict : clé sélecteur -> dict de propriétés (les clés commençant par « & » ou contenant
# « & » sont imbriquées) ; clé « @media … » / « @supports … » / « @layer … » / « @container … » -> dict de
# règles ; « @font-face » -> dict de descripteurs (ou liste de dicts) ; « @keyframes nom » -> dict d'images clés.
func rules_from_dict(spec):
    if type(spec) != "dict":
        _err.css_error("css_writer.from_dict", "dict attendu")
    out := []
    for k in keys(spec):
        v := spec[k]
        key := _s.trim(str(k))
        if _s.starts_with(key, "@"):
            sp := _s.find(key, " ")
            name := key[1:len(key)] if sp < 0 else key[1:sp]
            prelude := "" if sp < 0 else _s.trim(key[sp + 1:len(key)])
            lname := _s.lower(name)
            if _s.ends_with(lname, "keyframes"):
                from_k := _kf.Keyframes(prelude, v)
                append(out, from_k)
                continue
            if _at.body_kind(lname) == "declarations":
                items := v if type(v) == "list" else [v]
                for d in items:
                    a := _at.AtRule(lname, prelude, "declarations")
                    for dk in keys(d):
                        a.set(dk, d[dk])
                    append(out, a)
                continue
            if lname in ["import", "charset", "namespace"] or (lname == "layer" and v == null):
                append(out, _at.AtRule(lname, prelude, "statement"))
                continue
            a := _at.AtRule(lname, prelude, "rules")
            a.extend(rules_from_dict(v))
            append(out, a)
            continue
        append(out, _style_from(key, v))
    return out

func _style_from(selector, props):
    if type(props) != "dict":
        _err.css_error("css_writer.from_dict", "dict de propriétés attendu pour « " + selector + " »")
    flat := {}
    nested := []
    for k in keys(props):
        v := props[k]
        if type(v) == "dict":
            append(nested, (str(k), v))
        else:
            flat[k] = v
    r := _rule.StyleRule(selector, flat)
    for n in nested:
        if _s.starts_with(n[0], "@"):
            sub := rules_from_dict({n[0]: {"&": n[1]}})
            for x in sub:
                r.add_child(x)
        else:
            r.add_child(_style_from(n[0], n[1]))
    return r

func from_dict(spec, writer=null):
    return write(rules_from_dict(spec), writer)

func sheet_from_dict(spec):
    return _sheet.Stylesheet(rules_from_dict(spec))

# Valeur d'un attribut style depuis un dict (noms ALEX acceptés).
func inline_style(props, compact_output=false):
    return _decl.to_css(_decl.from_dict(props), compact_output)

# Commentaire CSS sûr.
func comment(text):
    return "/* " + _s.replace(str(text), "*/", "* /") + " */"
