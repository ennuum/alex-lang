# ALEX STANDARD LIBRARY — web.js.js_object
#
# Objets JavaScript : construction de littéraux (avec méthodes, accesseurs, clés calculées, décomposition),
# expressions Object.* courantes, et sémantique des objets JS appliquée aux dicts ALEX (ordre des clés des
# moteurs JS, chemins « a.b[0].c », fusion profonde, pick / omit, description du « type » d'une valeur).
#
#   use web.js.js_object as jo
#   o := jo.literal({"nom": "Ada", "âge": 36})
#   o.method("saluer", jf.function(null, [], [js.ret(je.lit("Bonjour"))]))
#   o.to_js()                                      # {nom: "Ada", âge: 36, saluer() {…}} (sur plusieurs lignes)
#   jo.freeze({"a": 1}).to_js()                    # Object.freeze({a: 1})
#   jo.assign("cible", [{"x": 1}]).to_js()         # Object.assign(cible, {x: 1})
#   jo.key_order({"b": 1, "10": 2, "2": 3})        # ["2", "10", "b"]  (ordre d'énumération JavaScript)
#   jo.get_path({"a": {"b": [{"c": 5}]}}, "a.b[0].c")     # 5
#   jo.set_path({}, "a.b.c", 1)                    # {"a": {"b": {"c": 1}}}
#   jo.deep_merge({"a": {"x": 1}}, {"a": {"y": 2}})       # {"a": {"x": 1, "y": 2}}
#   jo.describe({"nom": "Ada", "tags": ["x"]})     # {nom: string, tags: string[]}
#
# Erreurs : JsValueError (chemin invalide, cible non objet).

from core use len, type, to_int
from collections use append, keys
use string as _s
use web.js.js_errors as _err
use web.js.js_types as _t
use web.js.js_expression as _e

# Littéral objet (ObjectExpr) depuis un dict ; les valeurs peuvent être des Expr.
func literal(props=null):
    return _e.object(props)

func empty():
    return _e.ObjectExpr()

func _call(name, args):
    return _e.Call(_e.path(name), args)

func freeze(obj):
    return _call("Object.freeze", [_e.expr(obj)])

func assign(target, sources):
    args := [_e.path(target) if type(target) == "str" else _e.expr(target)]
    for s in sources:
        append(args, _e.expr(s))
    return _call("Object.assign", args)

func keys_of(obj):
    return _call("Object.keys", [_e.path(obj) if type(obj) == "str" else _e.expr(obj)])

func values_of(obj):
    return _call("Object.values", [_e.path(obj) if type(obj) == "str" else _e.expr(obj)])

func entries_of(obj):
    return _call("Object.entries", [_e.path(obj) if type(obj) == "str" else _e.expr(obj)])

func from_entries(entries):
    return _call("Object.fromEntries", [_e.expr(entries)])

# Object.defineProperty(cible, "nom", {value, writable, enumerable, configurable}).
func define_property(target, name, value, writable=true, enumerable=true, configurable=true):
    desc := {"value": value, "writable": writable, "enumerable": enumerable, "configurable": configurable}
    return _call("Object.defineProperty", [_e.path(target) if type(target) == "str" else _e.expr(target), _e.lit(str(name)), _e.expr(desc)])

# { ...a, ...b, clé: valeur } : sources (noms ou Expr) puis surcharges (dict).
func spread_merge(sources, overrides=null):
    o := _e.ObjectExpr()
    for s in sources:
        o.spread(_e.path(s) if type(s) == "str" else _e.expr(s))
    if overrides != null:
        for k in keys(overrides):
            o.set(k, overrides[k])
    return o

# ---------------------------------------------------------------- sémantique JS sur les dicts

func _is_index(k):
    t := str(k)
    return _t.is_canonical_index(t) and len(t) < 10

# Ordre d'énumération d'un objet JS : clés d'index entier croissantes, puis les autres dans l'ordre d'insertion.
func key_order(d):
    ints := []
    others := []
    for k in keys(d):
        if _is_index(k):
            append(ints, str(k))
        else:
            append(others, str(k))
    i := 1
    while i < len(ints):
        cur := ints[i]
        j := i - 1
        while j >= 0 and to_int(ints[j]) > to_int(cur):
            ints[j + 1] = ints[j]
            j -= 1
        ints[j + 1] = cur
        i += 1
    return ints + others

# Copie du dict dans l'ordre d'énumération JavaScript (clés en texte).
func js_ordered(d):
    out := {}
    for k in key_order(d):
        v := d[k] if k in d else d[to_int(k)]
        out[k] = v
    return out

# Segments d'un chemin « a.b[0]['c d'] ».
func parse_path(path):
    t := str(path)
    out := []
    i := 0
    n := len(t)
    cur := []
    while i < n:
        c := t[i]
        if c == '.':
            if len(cur) > 0:
                append(out, _s.join("", cur))
                cur = []
            i += 1
        elif c == '[':
            if len(cur) > 0:
                append(out, _s.join("", cur))
                cur = []
            j := _s.find(t[i:n], "]")
            if j < 0:
                _err.value_error("js_object.parse_path", "« ] » manquant dans « " + t + " »")
            inner := _s.trim(t[i + 1:i + j])
            if len(inner) >= 2 and (inner[0] == '"' or inner[0] == '\'') and inner[len(inner) - 1] == inner[0]:
                append(out, inner[1:len(inner) - 1])
            else:
                append(out, to_int(inner) if _t.is_canonical_index(inner) else inner)
            i = i + j + 1
        else:
            append(cur, str(c))
            i += 1
    if len(cur) > 0:
        append(out, _s.join("", cur))
    return out

func _step(v, seg):
    t := type(v)
    if t == "dict":
        if seg in v:
            return (true, v[seg])
        if type(seg) == "int" and str(seg) in v:
            return (true, v[str(seg)])
        return (false, null)
    if (t == "list" or t == "tuple") and type(seg) == "int":
        if seg >= 0 and seg < len(v):
            return (true, v[seg])
        return (false, null)
    if (t == "list" or t == "tuple" or t == "str") and seg == "length":
        return (true, len(v))
    return (false, null)

# Valeur au chemin, ou default (comme lodash.get / l'enchaînement optionnel ?.).
func get_path(obj, path, default=null):
    v := obj
    for seg in parse_path(path):
        r := _step(v, seg)
        if not r[0]:
            return default
        v = r[1]
    return v

func has_path(obj, path):
    v := obj
    for seg in parse_path(path):
        r := _step(v, seg)
        if not r[0]:
            return false
        v = r[1]
    return true

# Fixe la valeur au chemin en créant les dicts intermédiaires ; renvoie obj.
func set_path(obj, path, value):
    segs := parse_path(path)
    if len(segs) == 0:
        _err.value_error("js_object.set_path", "chemin vide")
    v := obj
    i := 0
    while i < len(segs) - 1:
        seg := segs[i]
        if type(v) == "dict":
            if not (seg in v) or not (type(v[seg]) == "dict" or type(v[seg]) == "list"):
                v[seg] = [] if type(segs[i + 1]) == "int" else {}
            v = v[seg]
        elif type(v) == "list" and type(seg) == "int":
            while len(v) <= seg:
                append(v, null)
            if v[seg] == null:
                v[seg] = [] if type(segs[i + 1]) == "int" else {}
            v = v[seg]
        else:
            _err.value_error("js_object.set_path", "« " + str(seg) + " » : cible non objet")
        i += 1
    last := segs[len(segs) - 1]
    if type(v) == "list" and type(last) == "int":
        while len(v) <= last:
            append(v, null)
        v[last] = value
    elif type(v) == "dict":
        v[last] = value
    else:
        _err.value_error("js_object.set_path", "cible non objet pour « " + str(last) + " »")
    return obj

# Fusion profonde (les dicts sont fusionnés, le reste remplacé) ; renvoie un nouveau dict.
func deep_merge(a, b):
    out := {}
    for k in keys(a):
        out[k] = a[k]
    for k in keys(b):
        if k in out and type(out[k]) == "dict" and type(b[k]) == "dict":
            out[k] = deep_merge(out[k], b[k])
        else:
            out[k] = b[k]
    return out

func pick(d, names):
    out := {}
    for n in names:
        if n in d:
            out[n] = d[n]
    return out

func omit(d, names):
    out := {}
    for k in keys(d):
        if not (k in names):
            out[k] = d[k]
    return out

# Description de type à la TypeScript d'une valeur ALEX (pour la documentation de données).
func describe(v, depth=0):
    if v == null:
        return "null"
    if _t.is_undefined(v):
        return "undefined"
    t := type(v)
    if t == "bool":
        return "boolean"
    if t == "int" or t == "float":
        return "number"
    if t == "str":
        return "string"
    if t == "list" or t == "tuple":
        if len(v) == 0:
            return "unknown[]"
        kinds := []
        for x in v:
            d := describe(x, depth + 1)
            if not (d in kinds):
                append(kinds, d)
        if len(kinds) == 1:
            k := kinds[0]
            if _s.contains(k, " | ") or _s.starts_with(k, "{"):
                return "Array<" + k + ">"
            return k + "[]"
        return "Array<" + _s.join(" | ", kinds) + ">"
    if t == "dict":
        if depth > 4:
            return "object"
        parts := []
        for k in keys(v):
            append(parts, _t.property_key(k) + ": " + describe(v[k], depth + 1))
        return "{" + _s.join(", ", parts) + "}"
    return "unknown"
