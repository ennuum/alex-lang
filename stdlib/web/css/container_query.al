# ALEX STANDARD LIBRARY — web.css.container_query
#
# Requêtes de conteneur (@container) : analyse « [nom] <condition> », évaluation contre un conteneur simulé
# (taille, type de confinement, propriétés personnalisées pour style()), choix du conteneur le plus proche
# parmi des ancêtres, et constructeurs (container-type / container-name).
#
#   use web.css.container_query as cq
#   q := cq.parse("carte (min-width: 400px)")
#   q.name                                         # carte
#   c := cq.Container(480, 300, "inline-size", ["carte"])
#   q.matches(c)                                   # true
#   cq.matches("(width > 30em) and style(--theme: sombre)", cq.Container(600, 0, "inline-size", [], {"--theme": "sombre"}))
#   cq.find([interne, externe], q)                 # premier ancêtre (du plus proche au plus lointain) adapté
#   cq.declarations("carte", "inline-size")        # {"container-name": "carte", "container-type": "inline-size"}
#
# Erreurs : CssParseError (requête mal formée).

from core use len, type, to_float
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.value as _value
use web.css.units as _units
use web.css.media_query as _mq

const SIZE_FEATURES := ["width", "height", "inline-size", "block-size", "aspect-ratio", "orientation"]
const TYPES := ["normal", "size", "inline-size", "scroll-state"]

# Conteneur simulé : taille du contenu (px), type (« size », « inline-size », « normal »), noms, propriétés
# personnalisées calculées (pour style()), taille de police, mode d'écriture vertical.
class Container:
    func init(width=0, height=0, container_type="inline-size", names=null, styles=null, font_size=16, vertical=false):
        self.width = to_float(width)
        self.height = to_float(height)
        self.container_type = container_type
        self.names = names if names != null else []
        if type(self.names) == "str":
            self.names = _s.split(_s.trim(self.names), " ")
        self.styles = styles if styles != null else {}
        self.font_size = to_float(font_size)
        self.vertical = vertical

    func has_name(n):
        return n in self.names

    func supports_feature(name):
        n := name
        if _s.starts_with(n, "min-") or _s.starts_with(n, "max-"):
            n = n[4:len(n)]
        if self.container_type == "size":
            return true
        if self.container_type == "inline-size":
            return n == ("height" if self.vertical else "width") or n == "inline-size"
        return false

    func lookup(name):
        n := _s.lower(name)
        if n == "width":
            return self.width
        if n == "height":
            return self.height
        if n == "inline-size":
            return self.height if self.vertical else self.width
        if n == "block-size":
            return self.width if self.vertical else self.height
        if n == "aspect-ratio":
            return self.width / self.height if self.height != 0 else 0.0
        if n == "orientation":
            return "portrait" if self.height >= self.width else "landscape"
        return null

    func context():
        return _units.Context(self.font_size, self.font_size, self.width, self.height, null, self.width, self.height)

class ContainerQuery:
    func init(name, condition):
        self.name = name
        self.condition = condition

    func features():
        out := []
        _collect(self.condition, out)
        return out

    # Le conteneur convient-il (nom, type) pour cette requête ?
    func accepts(container):
        if self.name != null and not container.has_name(self.name):
            return false
        for f in self.features():
            if f in SIZE_FEATURES and not container.supports_feature(f):
                return false
        return true

    func matches(container):
        if container == null:
            return false
        if self.condition == null:
            return true
        return _mq.evaluate_condition(self.condition, (leaf) => _leaf(leaf, container))

    func to_css():
        if self.condition == null:
            return self.name
        c := _mq.condition_to_css(self.condition)
        if self.name != null:
            return self.name + " " + c
        return c

    func __str__():
        return self.to_css()

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

func _check(container, name, op, text):
    actual := container.lookup(name)
    if actual == null:
        return null
    if type(actual) == "str":
        return op == "=" and _s.lower(_s.trim(text)) == actual
    want := _mq.numeric(text, container.context())
    if want == null:
        d := _units.try_parse(text)
        if d == null:
            return null
        want = _units.to_px(d, container.context())
    return _mq.compare(actual, op, want)

func _leaf(leaf, container):
    k := leaf[0]
    if k == "function":
        if leaf[1] == "style":
            return _style_matches(leaf[2], container)
        return null
    if k == "bool":
        v := container.lookup(leaf[1])
        if v == null:
            return null
        return v != 0 if type(v) != "str" else true
    if k == "feature":
        name := leaf[1]
        op := "="
        if _s.starts_with(name, "min-"):
            name = name[4:len(name)]
            op = ">="
        elif _s.starts_with(name, "max-"):
            name = name[4:len(name)]
            op = "<="
        return _check(container, name, op, leaf[2])
    if k == "range":
        for pair in leaf[2]:
            r := _check(container, leaf[1], pair[0], pair[1])
            if r != true:
                return r
        return true
    return null

# style(--prop: valeur) ou style(--prop) ; les conditions combinées dans style() sont prises en charge.
func _style_matches(text, container):
    t := _s.trim(text)
    if _s.starts_with(t, "(") or _s.starts_with(_s.lower(t), "not "):
        c := _mq.parse_condition(t)
        return _mq.evaluate_condition(c, (leaf) => _style_leaf(leaf, container))
    return _style_leaf(_mq.in_parens(_value.components(_value.tokenize("(" + t + ")"))[0]), container)

func _style_leaf(leaf, container):
    if leaf[0] == "feature":
        if not (leaf[1] in container.styles):
            return false
        return _value.normalize(container.styles[leaf[1]]) == _value.normalize(leaf[2])
    if leaf[0] == "bool":
        return leaf[1] in container.styles
    return null

# « [nom] condition » ; le nom est un identifiant initial qui n'est ni « not » ni une condition.
func parse(text):
    if isinstance(text, ContainerQuery):
        return text
    items := _mq._non_ws(_value.components(_value.tokenize(_s.trim(str(text)))))
    if len(items) == 0:
        _err.parse_error("container_query.parse", "requête de conteneur vide")
    name := null
    first := items[0]
    if isinstance(first, _value.Token) and first.kind == _value.IDENT and not _mq._is_kw(first, "not"):
        n := _s.lower(first.value)
        if n in ["none", "and", "or", "not", "initial", "inherit", "unset", "default"]:
            _err.parse_error("container_query.parse", "nom de conteneur invalide « " + first.value + " »")
        name = first.value
        items = items[1:len(items)]
        if len(items) == 0:
            return ContainerQuery(name, null)
    return ContainerQuery(name, _mq.condition_from(items))

func is_valid(text):
    try:
        parse(text)
        return true
    catch e:
        return false

func matches(text, container):
    q := parse(text)
    return q.accepts(container) and q.matches(container)

# Conteneur de requête : premier ancêtre (liste du plus proche au plus lointain) adapté à la requête.
func find(ancestors, query):
    q := parse(query)
    for c in ancestors:
        if q.accepts(c):
            return c
    return null

# Évalue la requête contre le conteneur le plus proche adapté (false s'il n'y en a pas).
func evaluate(ancestors, query):
    q := parse(query)
    c := find(ancestors, q)
    if c == null:
        return false
    return q.matches(c)

# ---------------------------------------------------------------- constructeurs

func declarations(name=null, container_type="inline-size"):
    out := {}
    if name != null:
        out["container-name"] = name if type(name) == "str" else _s.join(" ", name)
    out["container-type"] = container_type
    return out

func shorthand(name, container_type="inline-size"):
    return str(name) + " / " + container_type

func min_width(v):
    return "(min-width: " + _mq._len(v) + ")"

func max_width(v):
    return "(max-width: " + _mq._len(v) + ")"

func style(prop, value=null):
    if value == null:
        return "style(" + prop + ")"
    return "style(" + prop + ": " + str(value) + ")"

func query(condition, name=null):
    if name == null:
        return condition
    return name + " " + condition
