# ALEX STANDARD LIBRARY — web.css.supports_query
#
# Conditions @supports : « (propriété: valeur) », « selector(…) », « font-tech(…) », « font-format(…) »,
# combinées par not / and / or. L'évaluation simule un moteur : propriété connue (web.css.property) et valeur
# conforme à sa nature (web.css.declaration.is_valid_value), sélecteur analysable ; un Engine permet de
# simuler un navigateur qui ne gère pas certaines propriétés ou pseudo-classes.
#
#   use web.css.supports_query as sq
#   sq.supports("(display: grid) and (not (display: inline-grid))")   # false
#   sq.supports("(color: rgb(0 0 0 / 50%))")                           # true
#   sq.supports("selector(:has(> img))")                                # true
#   old := sq.Engine(["gap", "aspect-ratio"], [":has"])
#   sq.supports("(aspect-ratio: 16 / 9)", old)                          # false
#   sq.parse("(a: b) or (c: d)").to_css()                               # (a: b) or (c: d)
#   sq.declaration("display", "grid")                                   # (display: grid)
#
# Erreurs : CssParseError (condition mal formée, avec parse ; supports() renvoie false).

from core use len, type
from collections use append
use string as _s
use web.css.css_errors as _err
use web.css.property as _prop
use web.css.declaration as _decl
use web.css.selector_parser as _sp
use web.css.media_query as _mq

const FONT_FORMATS := ["collection", "embedded-opentype", "opentype", "svg", "truetype", "woff", "woff2"]
const FONT_TECHS := ["features-opentype", "features-aat", "features-graphite", "color-colrv0", "color-colrv1", "color-svg", "color-sbix", "color-cbdt", "variations", "palettes", "incremental"]

# Moteur simulé : propriétés et motifs de sélecteurs (« :has », « ::backdrop »...) non pris en charge.
class Engine:
    func init(unsupported_properties=null, unsupported_selectors=null, unsupported_values=null):
        self.unsupported_properties = []
        for p in (unsupported_properties if unsupported_properties != null else []):
            append(self.unsupported_properties, _prop.canonical(p))
        self.unsupported_selectors = unsupported_selectors if unsupported_selectors != null else []
        # valeurs non prises en charge : liste de (propriété, valeur) ou de valeurs seules (« subgrid »)
        self.unsupported_values = unsupported_values if unsupported_values != null else []

    func supports_declaration(name, value):
        n := _prop.canonical(name)
        if _prop.unprefixed(n) in self.unsupported_properties or n in self.unsupported_properties:
            return false
        if not _prop.is_known(n):
            return false
        v := _s.lower(_s.trim(value))
        for u in self.unsupported_values:
            if type(u) == "str":
                if _s.contains(v, _s.lower(u)):
                    return false
            elif _prop.canonical(u[0]) == n and _s.contains(v, _s.lower(u[1])):
                return false
        return _decl.is_valid_value(n, value)

    func supports_selector(text):
        for u in self.unsupported_selectors:
            if _s.contains(text, u):
                return false
        return _sp.is_valid(text)

func default_engine():
    return Engine()

class SupportsCondition:
    func init(tree):
        self.tree = tree

    func evaluate(engine=null):
        e := engine if engine != null else Engine()
        return _mq.evaluate_condition(self.tree, (leaf) => _leaf(leaf, e))

    func to_css():
        return _mq.condition_to_css(self.tree)

    func __str__():
        return self.to_css()

    # Propriétés testées par la condition.
    func properties():
        out := []
        _props(self.tree, out)
        return out

func _props(c, out):
    k := c[0]
    if k == "and" or k == "or":
        for x in c[1]:
            _props(x, out)
    elif k == "not":
        _props(c[1], out)
    elif k == "feature" and not (c[1] in out):
        append(out, c[1])

func _leaf(leaf, engine):
    k := leaf[0]
    if k == "feature":
        return engine.supports_declaration(leaf[1], leaf[2])
    if k == "function":
        name := leaf[1]
        arg := _s.trim(leaf[2])
        if name == "selector":
            return engine.supports_selector(arg)
        if name == "font-format":
            return _s.lower(arg) in FONT_FORMATS
        if name == "font-tech":
            return _s.lower(arg) in FONT_TECHS
        return false
    return false

# Analyse ; une simple « propriété: valeur » sans parenthèses est acceptée (forme CSS.supports(texte)).
func parse(text):
    if isinstance(text, SupportsCondition):
        return text
    t := _s.trim(str(text))
    if t == "":
        _err.parse_error("supports_query.parse", "condition vide")
    if not _s.starts_with(t, "(") and not _s.starts_with(_s.lower(t), "not") and not _s.contains(t, "(") and _s.contains(t, ":"):
        t = "(" + t + ")"
    return SupportsCondition(_mq.parse_condition(t))

func is_valid(text):
    try:
        parse(text)
        return true
    catch e:
        return false

# Vrai si la condition est satisfaite (false si elle est mal formée).
func supports(text, engine=null):
    c := null
    try:
        c = parse(text)
    catch e:
        return false
    return c.evaluate(engine)

# Équivalent de CSS.supports(propriété, valeur).
func supports_declaration(name, value, engine=null):
    e := engine if engine != null else Engine()
    return e.supports_declaration(name, value)

# ---------------------------------------------------------------- constructeurs

func declaration(name, value):
    return "(" + _prop.canonical(name) + ": " + str(value) + ")"

func selector(text):
    return "selector(" + text + ")"

func font_format(name):
    return "font-format(" + name + ")"

func font_tech(name):
    return "font-tech(" + name + ")"

func _wrap(c):
    t := _s.trim(str(c))
    if _s.starts_with(t, "(") and _balanced_outer(t):
        return t
    if _s.starts_with(t, "selector(") or _s.starts_with(t, "font-"):
        return t
    return "(" + t + ")"

func _balanced_outer(t):
    depth := 0
    i := 0
    while i < len(t):
        if t[i] == '(':
            depth += 1
        elif t[i] == ')':
            depth -= 1
            if depth == 0 and i < len(t) - 1:
                return false
        i += 1
    return true

func negate(c):
    return "not " + _wrap(c)

func all_of(conds):
    parts := []
    for c in conds:
        append(parts, _wrap(c))
    return _s.join(" and ", parts)

func any_of(conds):
    parts := []
    for c in conds:
        append(parts, _wrap(c))
    return _s.join(" or ", parts)
