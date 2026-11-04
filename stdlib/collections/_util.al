# ALEX STANDARD LIBRARY — collections._util (interne)
#
# Outils partagés par les collections : hachage de toute valeur (instances comprises), comparaison
# paramétrable, affichage et conversion d'itérables en listes.
#
# Hachage : les valeurs natives hachables (int, float, str, char, bool, null, tuples de hachables) utilisent
# hash() ; une instance doit fournir hash_code() (et __eq__ si l'égalité n'est pas l'identité) — sinon son
# identité est utilisée via un numéro attribué à la première rencontre.

from core use type, hash, len
from collections use append

_ids := [0]

func _instance_hash(v):
    try:
        return v.hash_code()
    catch e:
        if e.type != "AttributeError":
            raise(e)
    # Identité : numéro unique mémorisé dans l'objet lui-même.
    try:
        return v.__collections_id
    catch e2:
        _ids[0] += 1
        v.__collections_id = _ids[0]
        return _ids[0]

func hash_of(v):
    t := type(v)
    if t == "instance":
        return _instance_hash(v)
    if t == "list":
        h := 7
        for x in v:
            h = (h * 31 + hash_of(x)) & 0x3fffffffffffffff
        return h
    if t == "dict":
        raise("TypeError", "collections : un dict ne peut pas servir de clé (non hachable)")
    return hash(v)

# Comparaison à trois issues : -1, 0, 1. cmp(a, b) personnalisée, sinon < et ==.
func compare(a, b, cmp=null):
    if cmp != null:
        r := cmp(a, b)
        if r < 0:
            return -1
        if r > 0:
            return 1
        return 0
    if a == b:
        return 0
    if a < b:
        return -1
    return 1

# Liste à partir d'une liste, d'un tuple, d'un dict (clés), d'une str (caractères) ou d'un objet
# fournissant to_list().
func to_list(items, fn="collections"):
    t := type(items)
    if t == "null":
        return []
    if t == "list":
        return items[:]
    if t == "tuple" or t == "str":
        out := []
        for x in items:
            append(out, x)
        return out
    if t == "dict":
        out := []
        for k in items:
            append(out, k)
        return out
    if t == "instance":
        try:
            return items.to_list()
        catch e:
            if e.type != "AttributeError":
                raise(e)
        out := []
        for x in items:
            append(out, x)
        return out
    raise("TypeError", fn + " : itérable attendu (obtenu '" + t + "')")

func show(v):
    if type(v) == "str":
        return "\"" + v + "\""
    return str(v)

func join_items(items, sep=", "):
    out := ""
    first := true
    for x in items:
        if not first:
            out += sep
        out += show(x)
        first = false
    return out

# Nouveau numéro unique (identité d'objet, ALEX n'ayant pas d'opérateur `is`).
func new_id():
    _ids[0] += 1
    return _ids[0]

# Identité d'une instance : numéro attribué à la première demande (indépendant de __eq__).
func identity(v):
    try:
        return v.__collections_id
    catch e:
        _ids[0] += 1
        v.__collections_id = _ids[0]
        return _ids[0]

# Même objet (et non simplement égal) ; pour les valeurs non instances, égalité ordinaire.
func same(a, b):
    if type(a) == "instance" and type(b) == "instance":
        return identity(a) == identity(b)
    if type(a) == "instance" or type(b) == "instance":
        return false
    return a == b
