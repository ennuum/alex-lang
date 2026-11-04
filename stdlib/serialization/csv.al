# ALEX STANDARD LIBRARY — serialization.csv
#
# Tables d'objets <-> CSV : une ligne par objet (ou dict), une colonne par champ ; à la lecture, les colonnes
# sont CONVERTIES selon un schéma (le module csv ne rend que du texte) et peuvent reconstruire des objets.
#
#   use serialization.csv as sc
#   use serialization.schema as sch
#   texte := sc.dumps([Produit("stylo", 1.2, 10), Produit("cahier", 3.5, 4)])   # en-tête : champs publics
#   s := sch.object({"nom": sch.string(), "prix": sch.number(), "stock": sch.integer()})
#   lignes := sc.loads(texte, s)                    # [{"nom": "stylo", "prix": 1.2, "stock": 10}, ...]
#   objets := sc.loads(texte, s, () => Produit("", 0, 0))      # instances remplies
#   sc.dump_file("produits.csv", objets, ["nom", "stock"])     # colonnes choisies
#
# Sans schéma, loads devine : entiers, flottants, true/false, vide -> null (guess=false : tout reste texte).
# Erreurs : CSVError, ValidationError (schéma), SerializationError (valeur composée dans une cellule).

from core use len, type, to_int, to_float
from collections use append
use string as _s
use csv as _csv
use io as _io
use _native_reflect as _r
use serialization.serializer as _ser
use serialization.serialization_errors as _e

func _row_of(v):
    if type(v) == "dict":
        return v
    if _r.is_instance(v):
        return _ser.plain(v)
    _e.cannot_serialize("", "objet ou dict attendu par ligne (obtenu '" + type(v) + "')")

func _cell(v):
    t := type(v)
    if t == "null":
        return ""
    if t == "bool":
        if v:
            return "true"
        return "false"
    if t == "list" or t == "dict":
        _e.cannot_serialize("", "valeur composée dans une cellule CSV")
    return str(v)

func dumps(items, columns=null, delimiter=","):
    rows := [_row_of(x) for x in items]
    cols := columns
    if cols == null:
        cols = []
        seen := {}
        for r in rows:
            for k in r:
                if not (k in seen):
                    seen[k] = true
                    append(cols, k)
    table := [cols]
    for r in rows:
        line := []
        for c in cols:
            v := null
            if c in r:
                v = r[c]
            append(line, _cell(v))
        append(table, line)
    return _csv.stringify(table, delimiter)

func _digits(s, allow_sign):
    if s == "":
        return false
    i := 0
    if allow_sign and (s[0] == '-' or s[0] == '+'):
        i = 1
    if i >= len(s):
        return false
    while i < len(s):
        if s[i] < '0' or s[i] > '9':
            return false
        i += 1
    return true

# Conversion « au mieux » d'un texte de cellule.
func guess(text):
    t := _s.trim(text)
    if t == "":
        return null
    if t == "true":
        return true
    if t == "false":
        return false
    if _digits(t, true):
        return to_int(t)
    k := _s.find(t, ".")
    if k > 0 and _digits(_s.substring(t, 0, k), true) and _digits(_s.substring(t, k + 1, len(t)), false):
        return to_float(t)
    return text

# schema : serialization.schema (coerce + check) ; factory : fabrique d'objets à remplir.
func loads(text, schema=null, factory=null, delimiter=",", guess_types=true):
    out := []
    for rec in _csv.parse_dict(text, delimiter):
        row := {}
        for k in rec:
            if schema == null and guess_types:
                row[k] = guess(rec[k])
            else:
                row[k] = rec[k]
        if schema != null:
            row = schema.coerce(row)
            schema.check(row)
        if factory != null:
            obj := factory()
            for k in row:
                _r.set_field(obj, k, row[k])
            append(out, obj)
        else:
            append(out, row)
    return out

func dump_file(path, items, columns=null, delimiter=","):
    _io.write_file(path, dumps(items, columns, delimiter))

func load_file(path, schema=null, factory=null, delimiter=","):
    return loads(_io.read_file(path), schema, factory, delimiter)
