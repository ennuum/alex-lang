# ALEX STANDARD LIBRARY — web.css.css_rule
#
# StyleRule : une règle « sélecteurs { déclarations } », avec règles imbriquées (CSS Nesting : « & »), et Format,
# les options de sérialisation partagées par les règles, les at-rules et web.css.css_writer.
#
#   use web.css.css_rule as cr
#   r := cr.StyleRule("a.bouton", {"color": "white", "background_color": "#36c"})
#   r.set("padding", "4px 8px").set("color", "#fff", true)
#   r.get("color")                     # #fff
#   r.nest("&:hover", {"background-color": "#258"})
#   r.to_css()                         # a.bouton { color: #fff !important; background-color: #36c; ... }
#   r.to_css(cr.Format(true))          # indenté
#   r.flatten()                        # [a.bouton {...}, a.bouton:hover {...}] (imbrication résolue)
#
# Erreurs : CssSelectorError (sélecteur invalide), CssError.

from core use len, type
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.declaration as _decl
use web.css.selector_parser as _sp
use web.css.property as _prop

# Options de sortie : pretty (une déclaration par ligne, indentation), compact (minifié), sort (propriétés
# triées), indent (unité).
class Format:
    func init(pretty=false, indent="  ", compact=false, sort=false):
        self.pretty = pretty
        self.indent = indent
        self.compact = compact
        self.sort = sort

func default_format():
    return Format()

func _decls_from(data):
    if data == null:
        return []
    if type(data) == "dict":
        return _decl.from_dict(data)
    if type(data) == "str":
        return _decl.parse_block(data)
    return data

class StyleRule:
    func init(selector, declarations=null, line=null):
        self.kind = "style"
        self.selector = _s.trim(str(selector))
        self.declarations = _decls_from(declarations)
        self.children = []          # règles imbriquées (StyleRule ou AtRule)
        self.line = line
        self.parent = null

    func selectors():
        return _sp.parse(self.selector, true)

    func selector_list():
        parts := []
        for c in self.selectors().items:
            append(parts, c.to_css())
        return parts

    func validate_selector():
        _sp.parse(self.selector, true)
        return self

    # Fixe une propriété (remplace sa dernière déclaration).
    func set(name, value, important=false):
        n := _prop.canonical(name)
        kept := []
        for d in self.declarations:
            if d.property != n:
                append(kept, d)
        append(kept, _decl.Declaration(n, value, important))
        self.declarations = kept
        return self

    # Ajoute une déclaration (sans retirer les précédentes : repli progressif « display: flex; display: grid »).
    func add(name, value, important=false):
        append(self.declarations, _decl.Declaration(name, value, important))
        return self

    func get(name):
        d := _decl.find(self.declarations, name)
        if d == null:
            return null
        return d.value

    func has(name):
        return _decl.find(self.declarations, name) != null

    func remove(name):
        n := _prop.canonical(name)
        kept := []
        for d in self.declarations:
            if d.property != n:
                append(kept, d)
        self.declarations = kept
        return self

    func update(data):
        for d in _decls_from(data):
            self.set(d.property, d.value, d.important)
        return self

    func properties():
        return _decl.to_dict(self.declarations)

    func is_empty():
        return len(self.declarations) == 0 and len(self.children) == 0

    # Règle imbriquée ; le sélecteur peut utiliser « & » (sinon : descendant).
    func nest(selector, declarations=null):
        r := StyleRule(selector, declarations)
        r.parent = self
        append(self.children, r)
        return r

    func add_child(rule):
        rule.parent = self
        append(self.children, rule)
        return rule

    # Règles à plat : imbrication résolue (« & » remplacé par le sélecteur parent, « :is() » pour une liste).
    # Les at-rules imbriquées (@media dans une règle) sont rendues avec un bloc contenant la règle parente.
    func flatten(parent_selector=null):
        sel := self.selector if parent_selector == null else resolve_nesting(self.selector, parent_selector)
        out := []
        own := StyleRule(sel, [])
        for d in self.declarations:
            append(own.declarations, d.copy())
        own.line = self.line
        if len(own.declarations) > 0:
            append(out, own)
        for c in self.children:
            if c.kind == "style":
                for r in c.flatten(sel):
                    append(out, r)
            else:
                append(out, c.flatten_in(sel))
        return out

    func copy():
        r := StyleRule(self.selector, [])
        for d in self.declarations:
            append(r.declarations, d.copy())
        for c in self.children:
            r.add_child(c.copy())
        r.line = self.line
        return r

    func to_css(fmt=null, level=0):
        return write_rule(self, fmt if fmt != null else Format(), level)

    func __str__():
        return self.to_css()

# Remplace « & » par le parent ; sans « & », le sélecteur imbriqué est un descendant du parent.
func resolve_nesting(selector, parent):
    p := parent
    if _s.contains(parent, ","):
        p = ":is(" + parent + ")"
    parts := []
    for item in _split_top(selector):
        s := _s.trim(item)
        if _s.contains(s, "&"):
            append(parts, _s.replace(s, "&", p))
        elif _s.starts_with(s, ">") or _s.starts_with(s, "+") or _s.starts_with(s, "~"):
            append(parts, p + " " + s)
        else:
            append(parts, p + " " + s)
    return _s.join(", ", parts)

func _split_top(text):
    out := []
    depth := 0
    cur := []
    for c in text:
        if c == '(' or c == '[':
            depth += 1
        elif c == ')' or c == ']':
            depth -= 1
        if c == ',' and depth == 0:
            append(out, _s.join("", cur))
            cur = []
        else:
            append(cur, str(c))
    append(out, _s.join("", cur))
    return out

# ---------------------------------------------------------------- sérialisation

func _sorted_decls(decls):
    out := []
    for d in decls:
        append(out, d)
    i := 1
    while i < len(out):
        cur := out[i]
        j := i - 1
        while j >= 0 and out[j].property > cur.property:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = cur
        i += 1
    return out

# Bloc de déclarations (et de règles enfants) entre accolades, selon le format.
func write_block(decls, children, fmt, level):
    ds := _sorted_decls(decls) if fmt.sort else decls
    if fmt.compact:
        parts := []
        for d in ds:
            append(parts, d.to_css(true))
        inner := _s.join(";", parts)
        if len(parts) > 0 and len(children) > 0:
            inner = inner + ";"
        for c in children:
            inner = inner + c.to_css(fmt, level + 1)
        return "{" + inner + "}"
    if fmt.pretty:
        pad := _s.repeat(fmt.indent, level + 1)
        lines := []
        for d in ds:
            append(lines, pad + d.to_css() + ";")
        for c in children:
            append(lines, c.to_css(fmt, level + 1))
        if len(lines) == 0:
            return "{}"
        return "{\n" + _s.join("\n", lines) + "\n" + _s.repeat(fmt.indent, level) + "}"
    parts := []
    for d in ds:
        append(parts, d.to_css() + ";")
    for c in children:
        append(parts, c.to_css(fmt, level + 1))
    if len(parts) == 0:
        return "{}"
    return "{ " + _s.join(" ", parts) + " }"

func write_rule(rule, fmt, level):
    pad := _s.repeat(fmt.indent, level) if fmt.pretty else ""
    sel := rule.selector
    if fmt.compact:
        sel = _compact_selector(sel)
    elif fmt.pretty and _s.contains(sel, ","):
        sel = _s.join(",\n" + pad, _trimmed(_split_top(sel)))
    return pad + sel + ("" if fmt.compact else " ") + write_block(rule.declarations, rule.children, fmt, level)

func _trimmed(items):
    out := []
    for x in items:
        append(out, _s.trim(x))
    return out

# Sélecteur sans espaces superflus (« a > b , c » -> « a>b,c »).
func _compact_selector(sel):
    out := []
    prev_space := false
    quote := null
    for c in _s.trim(sel):
        if quote != null:
            append(out, str(c))
            if c == quote:
                quote = null
            continue
        if c == '"' or c == '\'':
            quote = c
            append(out, str(c))
            prev_space = false
            continue
        if c == ' ' or c == '\n' or c == '\t':
            prev_space = true
            continue
        if c == '>' or c == '+' or c == '~' or c == ',':
            prev_space = false
            while len(out) > 0 and out[len(out) - 1] == " ":
                out = out[0:len(out) - 1]
            append(out, str(c))
            continue
        if prev_space and len(out) > 0 and not (out[len(out) - 1] in [">", "+", "~", ",", "("]):
            append(out, " ")
        prev_space = false
        append(out, str(c))
    return _s.join("", out)

func rule(selector, declarations=null):
    return StyleRule(selector, declarations)
