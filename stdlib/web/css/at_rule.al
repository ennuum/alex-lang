# ALEX STANDARD LIBRARY — web.css.at_rule
#
# At-rules CSS : @media, @supports, @container, @layer, @scope, @starting-style (blocs de règles), @font-face,
# @page, @property, @counter-style, @font-palette-values (blocs de déclarations), @import, @charset,
# @namespace, @layer a, b (instructions). @keyframes a son propre module (web.css.keyframes).
#
#   use web.css.at_rule as at
#   m := at.media("(max-width: 600px)", [css_rule.StyleRule("nav", {"display": "none"})])
#   m.to_css()                                   # @media (max-width: 600px) { nav { display: none; } }
#   at.font_face("Inter", "url(inter.woff2) format(\"woff2\")", {"font-display": "swap"})
#   at.import_rule("theme.css", "screen", "base")    # @import url("theme.css") layer(base) screen;
#   at.property("--angle", "<angle>", false, "0deg")
#   at.layer_statement(["reset", "base", "components"])   # @layer reset, base, components;
#
# Erreurs : CssError (nom d'at-rule invalide).

from core use len, type
from collections use append
use string as _s
use web.css.css_errors as _err
use web.css.css_rule as _rule
use web.css.declaration as _decl
use web.css.value as _value

const RULE_BLOCKS := ["media", "supports", "container", "layer", "scope", "starting-style", "document", "-moz-document"]
const DECLARATION_BLOCKS := ["font-face", "page", "property", "counter-style", "font-palette-values", "viewport", "font-feature-values", "view-transition", "position-try", "top-left-corner", "top-left", "top-center", "top-right", "top-right-corner", "bottom-left-corner", "bottom-left", "bottom-center", "bottom-right", "bottom-right-corner", "left-top", "left-middle", "left-bottom", "right-top", "right-middle", "right-bottom"]
const STATEMENTS := ["import", "charset", "namespace", "layer"]

class AtRule:
    # body : "rules" (règles enfants), "declarations" ou "statement" (sans bloc).
    func init(name, prelude="", body="rules", line=null):
        n := _s.lower(_s.trim(str(name)))
        if _s.starts_with(n, "@"):
            n = n[1:len(n)]
        if n == "":
            _err.css_error("AtRule", "nom d'at-rule vide")
        self.kind = "at"
        self.name = n
        self.prelude = _s.trim(str(prelude))
        self.body = body
        self.rules = []
        self.declarations = []
        self.line = line
        self.parent = null

    func is_conditional():
        return self.name in ["media", "supports", "container", "scope"]

    func add(rule):
        rule.parent = self
        append(self.rules, rule)
        return rule

    func extend(rules):
        for r in rules:
            self.add(r)
        return self

    func set(name, value, important=false):
        kept := []
        n := _decl.Declaration(name, value, important)
        for d in self.declarations:
            if d.property != n.property:
                append(kept, d)
        append(kept, n)
        self.declarations = kept
        return self

    func get(name):
        d := _decl.find(self.declarations, name)
        return d.value if d != null else null

    func is_empty():
        return self.body != "statement" and len(self.rules) == 0 and len(self.declarations) == 0

    func copy():
        a := AtRule(self.name, self.prelude, self.body, self.line)
        for r in self.rules:
            a.add(r.copy())
        for d in self.declarations:
            append(a.declarations, d.copy())
        return a

    # Copie dont les règles imbriquées sont résolues contre le sélecteur parent (règle dans une règle).
    func flatten_in(parent_selector):
        a := AtRule(self.name, self.prelude, self.body, self.line)
        if len(self.declarations) > 0 and self.body == "rules":
            append(a.rules, _rule.StyleRule(parent_selector, self.declarations))
        for r in self.rules:
            if r.kind == "style":
                for x in r.flatten(parent_selector):
                    a.add(x)
            else:
                a.add(r.flatten_in(parent_selector))
        for d in self.declarations:
            if self.body != "rules":
                append(a.declarations, d.copy())
        return a

    # Règles à plat (imbrication résolue à l'intérieur).
    func flatten():
        a := AtRule(self.name, self.prelude, self.body, self.line)
        for r in self.rules:
            if r.kind == "style":
                for x in r.flatten():
                    a.add(x)
            elif r.kind == "at":
                a.add(r.flatten())
            else:
                a.add(r)
        for d in self.declarations:
            append(a.declarations, d.copy())
        return a

    func to_css(fmt=null, level=0):
        f := fmt if fmt != null else _rule.Format()
        pad := _s.repeat(f.indent, level) if f.pretty else ""
        head := "@" + self.name
        if self.prelude != "":
            head = head + " " + (_compact_prelude(self.prelude) if f.compact else self.prelude)
        if self.body == "statement":
            return pad + head + ";"
        sp := "" if f.compact else " "
        return pad + head + sp + _rule.write_block(self.declarations, self.rules, f, level)

    func __str__():
        return self.to_css()

func _compact_prelude(p):
    out := _value.normalize(p, true)
    out = _s.replace(out, "and (", "and(")
    return out

func body_kind(name):
    n := _s.lower(name)
    if n in DECLARATION_BLOCKS:
        return "declarations"
    if n in RULE_BLOCKS:
        return "rules"
    return "rules"

# ---------------------------------------------------------------- constructeurs

func media(query, rules=null):
    a := AtRule("media", query)
    if rules != null:
        a.extend(rules)
    return a

func supports(condition, rules=null):
    a := AtRule("supports", condition)
    if rules != null:
        a.extend(rules)
    return a

func container(condition, rules=null, name=null):
    a := AtRule("container", (name + " " + condition) if name != null else condition)
    if rules != null:
        a.extend(rules)
    return a

func layer(name, rules=null):
    a := AtRule("layer", name if name != null else "")
    if rules != null:
        a.extend(rules)
    return a

func layer_statement(names):
    return AtRule("layer", _s.join(", ", names), "statement")

func scope(start, end=null, rules=null):
    p := "(" + start + ")"
    if end != null:
        p = p + " to (" + end + ")"
    a := AtRule("scope", p)
    if rules != null:
        a.extend(rules)
    return a

# @font-face ; src : texte (« url(a.woff2) format("woff2") ») ; extra : autres descripteurs (dict).
func font_face(family, src, extra=null):
    a := AtRule("font-face", "", "declarations")
    a.set("font-family", _value.quote(family))
    a.set("src", src)
    if extra != null:
        for k in extra:
            a.set(k, extra[k])
    return a

func page(selector="", descriptors=null):
    a := AtRule("page", selector, "declarations")
    if descriptors != null:
        for k in descriptors:
            a.set(k, descriptors[k])
    return a

# @property : variable typée (syntaxe « <length> », « <color> »...), héritée ou non, valeur initiale.
func property(name, syntax="*", inherits=false, initial=null):
    a := AtRule("property", name, "declarations")
    a.set("syntax", _value.quote(syntax))
    a.set("inherits", "true" if inherits else "false")
    if initial != null:
        a.set("initial-value", initial)
    return a

func import_rule(url, media_query=null, layer_name=null, supports_condition=null):
    p := "url(" + _value.quote(url) + ")"
    if layer_name != null:
        p = p + " layer(" + layer_name + ")"
    if supports_condition != null:
        p = p + " supports(" + supports_condition + ")"
    if media_query != null:
        p = p + " " + media_query
    return AtRule("import", p, "statement")

func charset(name="UTF-8"):
    return AtRule("charset", _value.quote(name), "statement")

func namespace(uri, prefix=null):
    p := "url(" + _value.quote(uri) + ")"
    if prefix != null:
        p = prefix + " " + p
    return AtRule("namespace", p, "statement")

func starting_style(rules):
    a := AtRule("starting-style", "")
    a.extend(rules)
    return a
