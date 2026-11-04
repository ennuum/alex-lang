# ALEX STANDARD LIBRARY — event.event_filter
#
# Filtres d'événements composables : un filtre est un prédicat sur un événement (event.Event, ou toute valeur
# pour les filtres génériques), que l'on combine (both / either / negate) et que l'on applique à un écouteur
# (guard). Filtres de type (avec jokers « clavier.* »), de champ (égalité, comparaison, appartenance), de
# source, de fenêtre temporelle, et filtres à ÉTAT : dédoublonnage, limitation de débit, échantillonnage,
# saut des n premiers, arrêt après n.
#
#   use event.event_filter as ef
#   f := ef.both(ef.type_is("commande.*"), ef.field_gt("montant", 100))
#   bus.on("commande.creee", ef.guard(f, traiter))          # traiter n'est appelé que si f(e)
#   print(f(event.Event("commande.creee", {"montant": 250})))   # true
#   anti_rebond := ef.rate_limit(5, 1.0)                     # 5 événements par seconde au plus
#   uniques := ef.distinct((e) => e.get("id"))               # une seule fois chaque id
#   echantillon := ef.sample(10)                             # un événement sur 10
#   fp := ef.parse("type=souris.* and x>100 and bouton in [1,3]")   # petit langage de filtres
#
# Erreurs : ArgumentError (filtre mal formé, paramètre), TypeError (prédicat non fonction).

from core use len, type, to_int, to_float
from collections use append
use string as _s
use os as _os

func _type_of(e):
    if type(e) == "str":
        return e
    if type(e) == "dict":
        if "type" in e:
            return e["type"]
        return null
    try:
        return e.type
    catch x:
        return null

func _field(e, key):
    d := null
    if type(e) == "dict":
        if "data" in e and type(e["data"]) == "dict":
            d = e["data"]
        else:
            d = e
    else:
        try:
            d = e.data
        catch x:
            d = null
    if type(d) == "dict" and key in d:
        return d[key]
    return null

func glob_match(pattern, text):
    if pattern == "*" or pattern == text:
        return true
    if _s.ends_with(pattern, ".*"):
        base := _s.substring(pattern, 0, len(pattern) - 2)
        return text == base or _s.starts_with(text, base + ".")
    if _s.ends_with(pattern, "*"):
        return _s.starts_with(text, _s.substring(pattern, 0, len(pattern) - 1))
    if _s.starts_with(pattern, "*"):
        return _s.ends_with(text, _s.substring(pattern, 1, len(pattern)))
    return false

func type_is(*patterns):
    return (e) => _any_glob(patterns, _type_of(e))

func _any_glob(patterns, t):
    if t == null:
        return false
    for p in patterns:
        if glob_match(p, t):
            return true
    return false

func field_eq(key, value):
    return (e) => _field(e, key) == value

func field_ne(key, value):
    return (e) => not (_field(e, key) == value)

func field_gt(key, value):
    return (e) => _cmp_ok(_field(e, key), value, ">")

func field_ge(key, value):
    return (e) => _cmp_ok(_field(e, key), value, ">=")

func field_lt(key, value):
    return (e) => _cmp_ok(_field(e, key), value, "<")

func field_le(key, value):
    return (e) => _cmp_ok(_field(e, key), value, "<=")

func field_in(key, values):
    return (e) => _field(e, key) in values

func has_field(key):
    return (e) => _field(e, key) != null

func _cmp_ok(v, w, op):
    if v == null or w == null:
        return false
    tv := type(v)
    tw := type(w)
    numeric := (tv == "int" or tv == "float") and (tw == "int" or tw == "float")
    if not numeric and tv != tw:
        return false
    if op == ">":
        return v > w
    if op == ">=":
        return v >= w
    if op == "<":
        return v < w
    return v <= w

func source_is(src):
    return (e) => _source(e) == src

func _source(e):
    try:
        return e.source
    catch x:
        return null

# Événements dont l'horodatage est dans [start, stop] (secondes epoch).
func between_times(start, stop):
    return (e) => _ts_between(e, start, stop)

func _ts_between(e, a, b):
    t := null
    try:
        t = e.timestamp
    catch x:
        t = null
    if t == null:
        return false
    return t >= a and t <= b

func predicate(fn):
    if type(fn) != "function":
        raise("TypeError", "predicate : fonction attendue")
    return fn

func always():
    return (e) => true

func never():
    return (e) => false

func both(*filters):
    return (e) => _all(filters, e)

func either(*filters):
    return (e) => _some(filters, e)

func negate(f):
    return (e) => not f(e)

func _all(fs, e):
    for f in fs:
        if not f(e):
            return false
    return true

func _some(fs, e):
    for f in fs:
        if f(e):
            return true
    return false

# Écouteur filtré : handler(*args) appelé seulement si f(premier argument).
func guard(f, handler):
    return (*args) => _guarded(f, handler, args)

func _guarded(f, handler, args):
    first := null
    if len(args) > 0:
        first = args[0]
    if f(first):
        return handler(*args)
    return null

# ---- filtres à état ----
class _State:
    func init():
        self.n = 0
        self.seen = {}
        self.times = []

func distinct(key_fn=null):
    st := _State()
    return (e) => _distinct(st, key_fn, e)

func _distinct(st, key_fn, e):
    k := null
    if key_fn == null:
        k = str(_type_of(e)) + "|" + str(_field(e, "id"))
        try:
            k = str(e.type) + "|" + str(e.data)
        catch x:
            k = str(e)
    else:
        k = str(key_fn(e))
    if k in st.seen:
        return false
    st.seen[k] = true
    return true

# Au plus n événements par fenêtre glissante de per secondes.
func rate_limit(n, per=1.0, clock=null):
    if n < 1 or per <= 0:
        raise("ArgumentError", "rate_limit : n >= 1 et per > 0 attendus")
    st := _State()
    return (e) => _rate(st, n, per, clock)

func _rate(st, n, per, clock):
    now := 0.0
    if clock == null:
        now = _os.monotonic_time()
    else:
        now = clock()
    st.times = [t for t in st.times if now - t < per]
    if len(st.times) >= n:
        return false
    append(st.times, now)
    return true

# Un événement sur every (le premier passe).
func sample(every):
    if every < 1:
        raise("ArgumentError", "sample : every >= 1 attendu")
    st := _State()
    return (e) => _sample(st, every)

func _sample(st, every):
    ok := st.n % every == 0
    st.n += 1
    return ok

func skip(count):
    st := _State()
    return (e) => _skip(st, count)

func _skip(st, count):
    st.n += 1
    return st.n > count

func take(count):
    st := _State()
    return (e) => _take(st, count)

func _take(st, count):
    st.n += 1
    return st.n <= count

# ---- petit langage : « type=a.* and x>3 and nom!=bob and k in [1,2] » (and / or, sans parenthèses) ----
func parse(text):
    t := _s.trim(text)
    if t == "":
        return always()
    ors := _split_kw(t, " or ")
    if len(ors) > 1:
        return either(*[parse(x) for x in ors])
    ands := _split_kw(t, " and ")
    if len(ands) > 1:
        return both(*[parse(x) for x in ands])
    return _atom(t)

func _split_kw(t, kw):
    out := []
    rest := t
    depth := 0
    i := 0
    start := 0
    while i < len(t):
        c := t[i]
        if c == '[':
            depth += 1
        elif c == ']':
            depth -= 1
        if depth == 0 and i + len(kw) <= len(t) and _s.substring(t, i, i + len(kw)) == kw:
            append(out, _s.substring(t, start, i))
            i += len(kw)
            start = i
            continue
        i += 1
    append(out, _s.substring(t, start, len(t)))
    return out

func _value(v):
    s := _s.trim(v)
    if s == "true":
        return true
    if s == "false":
        return false
    if s == "null":
        return null
    if len(s) >= 2 and (s[0] == '"' or s[0] == '\'') and s[len(s) - 1] == s[0]:
        return _s.substring(s, 1, len(s) - 1)
    num := len(s) > 0
    dot := false
    i := 0
    while i < len(s):
        c := s[i]
        if c == '.':
            dot = true
        elif not ((c >= '0' and c <= '9') or (c == '-' and i == 0)):
            num = false
        i += 1
    if num:
        if dot:
            return to_float(s)
        return to_int(s)
    return s

func _atom(t):
    k := _s.find(t, " not in [")
    if k > 0:
        key := _s.trim(_s.substring(t, 0, k))
        items := _list_values(_s.substring(t, k + 8, len(t)))
        return negate(field_in(key, items))
    k = _s.find(t, " in [")
    if k > 0:
        key := _s.trim(_s.substring(t, 0, k))
        return field_in(key, _list_values(_s.substring(t, k + 4, len(t))))
    for op in [">=", "<=", "!=", "=", ">", "<"]:
        k = _s.find(t, op)
        if k > 0:
            key := _s.trim(_s.substring(t, 0, k))
            v := _value(_s.substring(t, k + len(op), len(t)))
            if key == "type":
                if op == "=":
                    return type_is(str(v))
                if op == "!=":
                    return negate(type_is(str(v)))
            if op == "=":
                return field_eq(key, v)
            if op == "!=":
                return field_ne(key, v)
            if op == ">":
                return field_gt(key, v)
            if op == ">=":
                return field_ge(key, v)
            if op == "<":
                return field_lt(key, v)
            return field_le(key, v)
    if _s.starts_with(t, "has "):
        return has_field(_s.trim(_s.substring(t, 4, len(t))))
    raise("ArgumentError", "event_filter.parse : condition illisible « " + t + " »")

func _list_values(t):
    s := _s.trim(t)
    if not _s.starts_with(s, "[") or not _s.ends_with(s, "]"):
        raise("ArgumentError", "event_filter.parse : liste [..] attendue")
    inner := _s.substring(s, 1, len(s) - 1)
    if _s.trim(inner) == "":
        return []
    return [_value(x) for x in _s.split(inner, ",")]
