# ALEX STANDARD LIBRARY — web.css.media_query
#
# Requêtes média (Media Queries 4/5) : analyse (listes, not / only, type de média, and / or / not, syntaxe
# d'intervalle « 400px <= width < 800px », préfixes min- / max-), évaluation dans un environnement simulé et
# constructeurs. L'analyseur de conditions est partagé par web.css.container_query et web.css.supports_query.
#
#   use web.css.media_query as mq
#   q := mq.parse("screen and (min-width: 600px), print")
#   env := mq.Environment(800, 600)            # largeur, hauteur (px), écran, 1 dppx, thème clair...
#   q.matches(env)                             # true
#   mq.matches("(400px <= width < 800px)", env)        # false (800 n'est pas < 800)
#   mq.matches("(prefers-color-scheme: dark)", mq.Environment(800, 600, "screen", 1, "dark"))   # true
#   mq.min_width("48em")                       # (min-width: 48em)
#   mq.all_of([mq.screen(), mq.min_width(600), mq.prefers_dark()])   # screen and (min-width: 600px) and (...)
#
# Erreurs : CssParseError (requête mal formée, avec parse ; parse_lenient renvoie « not all » à la place).

from core use len, type, to_float
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.value as _value
use web.css.units as _units

const MEDIA_TYPES := ["all", "screen", "print", "speech"]
const DEPRECATED_TYPES := ["tty", "tv", "projection", "handheld", "braille", "embossed", "aural"]
const RANGE_FEATURES := ["width", "height", "aspect-ratio", "resolution", "color", "color-index", "monochrome", "device-width", "device-height", "device-aspect-ratio", "inline-size", "block-size"]

# ---------------------------------------------------------------- conditions (partagé)
#
# Arbre : ("and", [c...]) ("or", [c...]) ("not", c) ("feature", nom, valeur) ("bool", nom)
#         ("range", nom, [(op, valeur)...]) ("function", nom, texte des arguments) ("unknown", texte)
# Opérateurs d'intervalle exprimés depuis le point de vue de la caractéristique : « width >= 400px ».

func _fail(fn, msg):
    _err.parse_error(fn, msg)

func _non_ws(items):
    out := []
    for it in items:
        if not (isinstance(it, _value.Token) and (it.kind == _value.WHITESPACE or it.kind == _value.COMMENT)):
            append(out, it)
    return out

func _is_kw(it, name):
    return isinstance(it, _value.Token) and it.kind == _value.IDENT and _s.lower(it.value) == name

func parse_condition(text):
    items := _non_ws(_value.components(_value.tokenize(str(text))))
    if len(items) == 0:
        _fail("parse_condition", "condition vide")
    return condition_from(items)

# Condition depuis des composantes (sans espaces).
func condition_from(items):
    if len(items) == 0:
        _fail("parse_condition", "condition vide")
    if _is_kw(items[0], "not"):
        if len(items) != 2:
            _fail("parse_condition", "« not » attend une seule condition entre parenthèses")
        return ("not", in_parens(items[1]))
    first := in_parens(items[0])
    if len(items) == 1:
        return first
    op := null
    parts := [first]
    i := 1
    while i < len(items):
        it := items[i]
        word := _s.lower(it.value) if isinstance(it, _value.Token) and it.kind == _value.IDENT else null
        if word != "and" and word != "or":
            _fail("parse_condition", "« and » ou « or » attendu, trouvé « " + it.to_css() + " »")
        if op != null and op != word:
            _fail("parse_condition", "« and » et « or » mélangés sans parenthèses")
        op = word
        if i + 1 >= len(items):
            _fail("parse_condition", "condition manquante après « " + word + " »")
        append(parts, in_parens(items[i + 1]))
        i += 2
    return (op, parts)

func in_parens(it):
    if isinstance(it, _value.Function):
        return ("function", it.lower_name(), _value.serialize(it.args))
    if not (isinstance(it, _value.Block) and it.open == "("):
        return ("unknown", it.to_css())
    inner := _non_ws(it.items)
    if len(inner) == 0:
        return ("unknown", "()")
    if (isinstance(inner[0], _value.Block) and inner[0].open == "(") or _is_kw(inner[0], "not") or isinstance(inner[0], _value.Function):
        return condition_from(inner)
    colon := -1
    has_cmp := false
    i := 0
    while i < len(inner):
        x := inner[i]
        if isinstance(x, _value.Token) and x.kind == _value.COLON and colon < 0:
            colon = i
        if isinstance(x, _value.Token) and (x.is_delim("<") or x.is_delim(">") or x.is_delim("=")):
            has_cmp = true
        i += 1
    if colon > 0:
        name := _s.lower(inner[0].to_css()) if colon == 1 else _s.lower(_value.serialize(inner[0:colon]))
        return ("feature", name, _s.trim(_value.serialize(_value._strip_ws(it.items[_index_after_colon(it.items):len(it.items)]))))
    if has_cmp:
        return _range(inner, it.to_css())
    if len(inner) == 1 and isinstance(inner[0], _value.Token) and inner[0].kind == _value.IDENT:
        return ("bool", _s.lower(inner[0].value))
    return ("unknown", it.to_css())

func _index_after_colon(items):
    i := 0
    while i < len(items):
        x := items[i]
        if isinstance(x, _value.Token) and x.kind == _value.COLON:
            return i + 1
        i += 1
    return len(items)

func _flip(op):
    if op == "<":
        return ">"
    if op == ">":
        return "<"
    if op == "<=":
        return ">="
    if op == ">=":
        return "<="
    return op

# « width >= 600px », « 600px <= width », « 400px < width <= 800px ».
func _range(inner, raw):
    chunks := []          # alternance valeur / opérateur
    cur := []
    i := 0
    while i < len(inner):
        x := inner[i]
        if isinstance(x, _value.Token) and (x.is_delim("<") or x.is_delim(">") or x.is_delim("=")):
            op := x.value
            if (x.value == "<" or x.value == ">") and i + 1 < len(inner) and isinstance(inner[i + 1], _value.Token) and inner[i + 1].is_delim("="):
                op = op + "="
                i += 1
            append(chunks, ("v", cur))
            append(chunks, ("op", op))
            cur = []
        else:
            append(cur, x)
        i += 1
    append(chunks, ("v", cur))
    vals := []
    ops := []
    for c in chunks:
        if c[0] == "v":
            if len(c[1]) == 0:
                _fail("media_query", "intervalle mal formé « " + raw + " »")
            append(vals, _value.serialize(c[1]))
        else:
            append(ops, c[1])
    if len(vals) == 2:
        a := _s.lower(vals[0])
        if _is_feature_name(a):
            return ("range", a, [(ops[0], vals[1])])
        return ("range", _s.lower(vals[1]), [(_flip(ops[0]), vals[0])])
    if len(vals) == 3:
        if ops[0][0] != ops[1][0] or ops[0] == "=" or ops[1] == "=":
            _fail("media_query", "intervalle incohérent « " + raw + " »")
        return ("range", _s.lower(vals[1]), [(_flip(ops[0]), vals[0]), (ops[1], vals[2])])
    _fail("media_query", "intervalle mal formé « " + raw + " »")

func _is_feature_name(t):
    if len(t) == 0:
        return false
    c := t[0]
    return (c >= 'a' and c <= 'z') or c == '-'

# Texte CSS d'un arbre de condition.
func condition_to_css(c, top=true):
    k := c[0]
    if k == "and" or k == "or":
        parts := []
        for x in c[1]:
            append(parts, _wrapped(x))
        return _s.join(" " + k + " ", parts)
    if k == "not":
        return "not " + _wrapped(c[1])
    if k == "feature":
        return "(" + c[1] + ": " + c[2] + ")"
    if k == "bool":
        return "(" + c[1] + ")"
    if k == "range":
        if len(c[2]) == 1:
            return "(" + c[1] + " " + c[2][0][0] + " " + c[2][0][1] + ")"
        return "(" + c[2][0][1] + " " + _flip(c[2][0][0]) + " " + c[1] + " " + c[2][1][0] + " " + c[2][1][1] + ")"
    if k == "function":
        return c[1] + "(" + c[2] + ")"
    return c[1]

func _wrapped(c):
    k := c[0]
    if k == "and" or k == "or" or k == "not":
        return "(" + condition_to_css(c, false) + ")"
    return condition_to_css(c, false)

# Évalue un arbre ; leaf(c) -> true / false / null (inconnu, traité comme faux).
func evaluate_condition(c, leaf):
    k := c[0]
    if k == "and":
        for x in c[1]:
            if not evaluate_condition(x, leaf):
                return false
        return true
    if k == "or":
        for x in c[1]:
            if evaluate_condition(x, leaf):
                return true
        return false
    if k == "not":
        r := leaf(c[1]) if not (c[1][0] in ["and", "or", "not"]) else evaluate_condition(c[1], leaf)
        if r == null:
            return false
        return not r
    r := leaf(c)
    return r == true

# Compare deux nombres avec un opérateur d'intervalle.
func compare(a, op, b):
    eps := 0.000001
    if op == "=" or op == ":":
        return a - b < eps and b - a < eps
    if op == "<":
        return a < b - eps
    if op == "<=":
        return a <= b + eps
    if op == ">":
        return a > b + eps
    if op == ">=":
        return a >= b - eps
    return false

# Nombre depuis une valeur de caractéristique : longueur -> px, résolution -> dppx, rapport « 16/9 » -> 1.777...,
# nombre. null si non numérique.
func numeric(text, ctx):
    t := _s.trim(str(text))
    if _s.contains(t, "/"):
        parts := _s.split(t, "/")
        if len(parts) == 2:
            try:
                b := to_float(_s.trim(parts[1]))
                if b == 0:
                    return null
                return to_float(_s.trim(parts[0])) / b
            catch e:
                return null
        return null
    d := _units.try_parse(t)
    if d == null:
        return null
    k := d.kind()
    if k == "number":
        return to_float(d.value)
    if k == "length":
        if d.unit == "px" or d.unit == "":
            return to_float(d.value)
        return _units.to_px(d, ctx)
    if k == "resolution":
        return _units.convert(d, "dppx").value
    return null

# ---------------------------------------------------------------- environnement

class Environment:
    # Caractéristiques simulées d'un appareil ; set(nom, valeur) pour les autres (« update », « scripting »...).
    func init(width=1280, height=720, media_type="screen", dpr=1, color_scheme="light", reduced_motion="no-preference", hover="hover", pointer="fine", font_size=16):
        self.media_type = media_type
        self.font_size = to_float(font_size)
        self.features = {
            "width": to_float(width), "height": to_float(height), "resolution": to_float(dpr),
            "prefers-color-scheme": color_scheme, "prefers-reduced-motion": reduced_motion,
            "hover": hover, "any-hover": hover, "pointer": pointer, "any-pointer": pointer,
            "color": 8.0, "color-index": 0.0, "monochrome": 0.0, "grid": 0.0,
            "display-mode": "browser", "prefers-contrast": "no-preference", "forced-colors": "none",
            "scripting": "enabled", "update": "fast" if media_type != "print" else "none",
            "inverted-colors": "none", "prefers-reduced-transparency": "no-preference",
            "prefers-reduced-data": "no-preference", "color-gamut": "srgb", "dynamic-range": "standard",
            "overflow-block": "scroll" if media_type != "print" else "paged", "overflow-inline": "scroll"
        }

    func set(name, value):
        self.features[_s.lower(name)] = to_float(value) if type(value) == "int" else value
        return self

    func resize(width, height):
        self.features["width"] = to_float(width)
        self.features["height"] = to_float(height)
        return self

    func width():
        return self.features["width"]

    func height():
        return self.features["height"]

    func context():
        return _units.Context(self.font_size, self.font_size, self.features["width"], self.features["height"])

    # Valeur d'une caractéristique (nombre ou mot-clé), ou null si inconnue.
    func lookup(name):
        n := _s.lower(name)
        if n == "aspect-ratio" or n == "device-aspect-ratio":
            h := self.features["height"]
            return self.features["width"] / h if h != 0 else 0.0
        if n == "orientation":
            return "portrait" if self.features["height"] >= self.features["width"] else "landscape"
        if n == "device-width":
            return self.features["width"]
        if n == "device-height":
            return self.features["height"]
        if n == "-webkit-device-pixel-ratio":
            return self.features["resolution"]
        if n in self.features:
            return self.features[n]
        return null

    func copy():
        e := Environment(self.features["width"], self.features["height"], self.media_type, self.features["resolution"])
        e.font_size = self.font_size
        for k in keys(self.features):
            e.features[k] = self.features[k]
        return e

func screen_env(width=1280, height=720):
    return Environment(width, height)

func mobile_env(width=390, height=844):
    return Environment(width, height, "screen", 3, "light", "no-preference", "none", "coarse")

func print_env(width=794, height=1123):
    return Environment(width, height, "print")

# Évalue une feuille de condition média contre un environnement.
func feature_matches(leaf, env):
    k := leaf[0]
    if k == "bool":
        v := env.lookup(leaf[1])
        if v == null:
            return null
        if type(v) == "str":
            return v != "none" and v != "no-preference"
        return v != 0
    if k == "feature":
        name := leaf[1]
        op := "="
        if _s.starts_with(name, "min-"):
            name = name[4:len(name)]
            op = ">="
        elif _s.starts_with(name, "max-"):
            name = name[4:len(name)]
            op = "<="
        if _s.starts_with(name, "-webkit-min-"):
            name = "-webkit-" + name[12:len(name)]
            op = ">="
        elif _s.starts_with(name, "-webkit-max-"):
            name = "-webkit-" + name[12:len(name)]
            op = "<="
        return _check(env, name, op, leaf[2])
    if k == "range":
        for pair in leaf[2]:
            r := _check(env, leaf[1], pair[0], pair[1])
            if r != true:
                return r
        return true
    return null

func _check(env, name, op, text):
    actual := env.lookup(name)
    if actual == null:
        return null
    if type(actual) == "str":
        if op != "=":
            return null
        return _s.lower(_s.trim(text)) == actual
    want := numeric(text, env.context())
    if want == null:
        return null
    return compare(actual, op, want)

# ---------------------------------------------------------------- requêtes

class MediaQuery:
    func init(media_type="all", condition=null, negated=false, only=false):
        self.media_type = media_type
        self.condition = condition
        self.negated = negated
        self.only = only

    func matches(env):
        ok := true
        mt := self.media_type
        if mt in DEPRECATED_TYPES or not (mt in MEDIA_TYPES):
            ok = false
        elif mt != "all" and mt != env.media_type:
            ok = false
        if ok and self.condition != null:
            ok = evaluate_condition(self.condition, (leaf) => feature_matches(leaf, env))
        return (not ok) if self.negated else ok

    func to_css():
        parts := []
        if self.negated:
            append(parts, "not")
        if self.only:
            append(parts, "only")
        typed := self.negated or self.only or self.media_type != "all" or self.condition == null
        if typed:
            append(parts, self.media_type)
        if self.condition != null:
            c := condition_to_css(self.condition)
            if typed:
                if self.condition[0] == "or":
                    c = "(" + c + ")"
                append(parts, "and")
            append(parts, c)
        return _s.join(" ", parts)

    func __str__():
        return self.to_css()

    # Caractéristiques citées (noms, préfixes min-/max- retirés).
    func features():
        out := []
        _collect(self.condition, out)
        return out

func _collect(c, out):
    if c == null:
        return
    k := c[0]
    if k == "and" or k == "or":
        for x in c[1]:
            _collect(x, out)
    elif k == "not":
        _collect(c[1], out)
    elif k == "feature" or k == "bool" or k == "range":
        n := c[1]
        if _s.starts_with(n, "min-") or _s.starts_with(n, "max-"):
            n = n[4:len(n)]
        if not (n in out):
            append(out, n)

class MediaQueryList:
    func init(queries):
        self.queries = queries

    # Une liste vide correspond toujours (comme « all »).
    func matches(env):
        if len(self.queries) == 0:
            return true
        for q in self.queries:
            if q.matches(env):
                return true
        return false

    func to_css():
        parts := []
        for q in self.queries:
            append(parts, q.to_css())
        return _s.join(", ", parts)

    func __str__():
        return self.to_css()

    func features():
        out := []
        for q in self.queries:
            for f in q.features():
                if not (f in out):
                    append(out, f)
        return out

# Analyse une requête seule (sans virgule).
func parse_query(items):
    xs := _non_ws(items)
    if len(xs) == 0:
        _fail("media_query.parse", "requête vide")
    first := xs[0]
    if isinstance(first, _value.Block) or isinstance(first, _value.Function) or (_is_kw(first, "not") and len(xs) > 1 and isinstance(xs[1], _value.Block)):
        return MediaQuery("all", condition_from(xs))
    negated := false
    only := false
    i := 0
    if _is_kw(xs[0], "not"):
        negated = true
        i = 1
    elif _is_kw(xs[0], "only"):
        only = true
        i = 1
    if i >= len(xs) or not (isinstance(xs[i], _value.Token) and xs[i].kind == _value.IDENT):
        _fail("media_query.parse", "type de média attendu")
    mt := _s.lower(xs[i].value)
    if mt in ["and", "or", "not", "only", "layer"]:
        _fail("media_query.parse", "type de média invalide « " + mt + " »")
    i += 1
    if i == len(xs):
        return MediaQuery(mt, null, negated, only)
    if not _is_kw(xs[i], "and") or i + 1 >= len(xs):
        _fail("media_query.parse", "« and » attendu après le type de média")
    rest := xs[i + 1:len(xs)]
    cond := condition_from(rest)
    has_or := false
    for x in rest:
        if _is_kw(x, "or"):
            has_or = true
    if has_or:
        _fail("media_query.parse", "« or » non parenthésé après un type de média")
    return MediaQuery(mt, cond, negated, only)

# Analyse une liste de requêtes ; CssParseError si l'une est invalide.
func parse(text):
    if isinstance(text, MediaQueryList):
        return text
    t := _s.trim(str(text))
    if t == "":
        return MediaQueryList([])
    groups := _value.split_on_commas(_value.components(_value.tokenize(t)))
    out := []
    for g in groups:
        append(out, parse_query(g))
    return MediaQueryList(out)

# Comme parse, mais une requête invalide devient « not all » (comportement des navigateurs).
func parse_lenient(text):
    t := _s.trim(str(text))
    if t == "":
        return MediaQueryList([])
    groups := _value.split_on_commas(_value.components(_value.tokenize(t)))
    out := []
    for g in groups:
        try:
            append(out, parse_query(g))
        catch e:
            append(out, MediaQuery("all", null, true))
    return MediaQueryList(out)

func is_valid(text):
    try:
        parse(text)
        return true
    catch e:
        return false

func matches(text, env=null):
    return parse_lenient(text).matches(env if env != null else Environment())

func normalize(text):
    return parse(text).to_css()

# ---------------------------------------------------------------- constructeurs

func _len(v):
    if type(v) == "int" or type(v) == "float":
        return _units.format_number(v) + "px"
    return str(v)

func feature(name, value=null):
    if value == null:
        return "(" + name + ")"
    return "(" + name + ": " + str(value) + ")"

func min_width(v):
    return "(min-width: " + _len(v) + ")"

func max_width(v):
    return "(max-width: " + _len(v) + ")"

func min_height(v):
    return "(min-height: " + _len(v) + ")"

func max_height(v):
    return "(max-height: " + _len(v) + ")"

# Intervalle [a, b[ en syntaxe moderne : (a <= width < b).
func width_between(a, b):
    return "(" + _len(a) + " <= width < " + _len(b) + ")"

func orientation(o):
    return "(orientation: " + o + ")"

func screen():
    return "screen"

func print_media():
    return "print"

func prefers_dark():
    return "(prefers-color-scheme: dark)"

func prefers_light():
    return "(prefers-color-scheme: light)"

func reduced_motion():
    return "(prefers-reduced-motion: reduce)"

func hover_capable():
    return "(hover: hover) and (pointer: fine)"

func touch():
    return "(pointer: coarse)"

func retina(dppx=2):
    return "(min-resolution: " + str(dppx) + "dppx)"

func all_of(parts):
    return _s.join(" and ", parts)

func any_of(parts):
    out := []
    for p in parts:
        append(out, p)
    return _s.join(", ", out)

func negate(query):
    return "not all and " + str(query) if _s.starts_with(_s.trim(str(query)), "(") else "not " + str(query)
