# ALEX STANDARD LIBRARY — office.json
# JSON pour les données bureautiques, au-dessus du module standard `json` : tables (lignes / enregistrements /
# colonnes), JSON Lines, aplatissement d'objets imbriqués, chemins d'accès, ordre des clés CONSERVÉ par défaut.
#
#   use office.json as oj
#   rows := oj.load_table("ventes.json")              # [["produit", "qte"], ["A", 3], ...]
#   oj.save_table("sortie.json", rows, "records")     # [{"produit": "A", "qte": 3}, ...]
#   oj.flatten({"a": {"b": 1, "c": [2, 3]}})          # {"a.b": 1, "a.c[0]": 2, "a.c[1]": 3}
#   oj.get_path(doc, "commandes[0].client.nom")
#
# BASE     parse(texte)  stringify(v, indent=null, sort_keys=false)  pretty(v, indent=2)  load(chemin)
#          save(chemin, v, indent=2)  is_valid(texte)
# TABLES   to_rows(données) : accepte une liste d'objets, une liste de listes (1re = en-tête), un objet
#          {"columns": [...], "data": [[...]]} (orientation « split »), un objet de colonnes {"a": [..], "b": [..]}
#          -> [en-tête, lignes...]
#          from_rows(lignes, orient="records") : "records" (liste d'objets) | "rows" (liste de listes)
#          | "columns" (objet de colonnes) | "split" ({"columns", "data"})
#          load_table(chemin) / save_table(chemin, lignes, orient="records", indent=2)
#          records_to_rows(recs, columns=null)   rows_to_records(lignes)
# LIGNES   parse_lines(texte) -> valeurs (JSON Lines / NDJSON)   stringify_lines(valeurs)   load_lines / save_lines
# OBJETS   flatten(v, sep=".")  unflatten(d, sep=".")  get_path(v, chemin, défaut=null)  set_path(v, chemin, valeur)
#          (chemin : « a.b[2].c » ; set_path crée les objets / listes intermédiaires)
# Les dates (dict year/month/day[/hour...]) sont écrites en texte ISO 8601 par to_json_value.
# Erreurs : JSONError (texte invalide), ValueError (forme de table non reconnue, chemin invalide), TypeError.

use json as _std
from core use len, type, to_int
from collections use append, keys, contains_key
use string
use io
use office.utils as u

func parse(text):
    return _std.parse(text)

func is_valid(text):
    return _std.is_valid(text)

# Prépare une valeur pour JSON : dates -> ISO 8601, tuples -> listes, autres valeurs inchangées.
func to_json_value(v):
    t := type(v)
    if t == "dict":
        if u.is_date_dict(v) and len(keys(v)) <= 7:
            if u.get(v, "hour", 0) == 0 and u.get(v, "minute", 0) == 0 and u.get(v, "second", 0) == 0:
                return u.iso_date(v)
            return u.iso_datetime(v, false)
        out := {}
        for k in keys(v):
            out[u.to_text(k)] = to_json_value(v[k])
        return out
    if t == "list" or t == "tuple":
        out := []
        for x in v:
            append(out, to_json_value(x))
        return out
    return v

func stringify(v, indent=null, sort_keys=false):
    return _std.stringify(to_json_value(v), indent, sort_keys)

func pretty(v, indent=2):
    return _std.stringify(to_json_value(v), indent, false)

func load(path):
    return parse(u.decode_text(io.read_bytes(path)))

func save(path, v, indent=2):
    io.write_bytes(path, u.utf8_encode(stringify(v, indent) + "\n"))

# ---------------------------------------------------------------------------------------------- tables

func records_to_rows(records, columns=null):
    cols := columns
    if cols == null:
        cols = []
        seen := {}
        for rec in records:
            for k in keys(rec):
                if not contains_key(seen, k):
                    seen[k] = true
                    append(cols, k)
    rows := [cols]
    for rec in records:
        row := []
        for c in cols:
            if contains_key(rec, c):
                append(row, rec[c])
            else:
                append(row, null)
        append(rows, row)
    return rows

func rows_to_records(rows):
    if len(rows) == 0:
        return []
    header := []
    for h in rows[0]:
        append(header, u.to_text(h))
    out := []
    r := 1
    while r < len(rows):
        rec := {}
        k := 0
        while k < len(header):
            rec[header[k]] = rows[r][k] if k < len(rows[r]) else null
            k = k + 1
        append(out, rec)
        r = r + 1
    return out

func to_rows(data):
    t := type(data)
    if t == "list":
        if len(data) == 0:
            return []
        if type(data[0]) == "dict":
            return records_to_rows(data)
        if type(data[0]) == "list" or type(data[0]) == "tuple":
            out := []
            for r in data:
                row := []
                for v in r:
                    append(row, v)
                append(out, row)
            return out
        # liste de scalaires : une colonne
        out := [["valeur"]]
        for v in data:
            append(out, [v])
        return out
    if t == "dict":
        if contains_key(data, "columns") and contains_key(data, "data"):
            out := [data["columns"]]
            for r in data["data"]:
                append(out, r)
            return out
        cols := keys(data)
        n := 0
        for c in cols:
            if type(data[c]) != "list":
                raise("ValueError", "office.json.to_rows : objet de colonnes attendu (la clé '" + u.to_text(c) + "' n'est pas une liste)")
            if len(data[c]) > n:
                n = len(data[c])
        out := [cols]
        i := 0
        while i < n:
            row := []
            for c in cols:
                col := data[c]
                append(row, col[i] if i < len(col) else null)
            append(out, row)
            i = i + 1
        return out
    raise("ValueError", "office.json.to_rows : forme de table non reconnue (type '" + t + "')")

func from_rows(rows, orient="records"):
    if orient == "records":
        return rows_to_records(rows)
    if orient == "rows":
        return rows
    if len(rows) == 0:
        return {} if orient == "columns" else {"columns": [], "data": []}
    header := rows[0]
    if orient == "split":
        data := []
        r := 1
        while r < len(rows):
            append(data, rows[r])
            r = r + 1
        return {"columns": header, "data": data}
    if orient == "columns":
        out := {}
        k := 0
        for h in header:
            col := []
            r := 1
            while r < len(rows):
                append(col, rows[r][k] if k < len(rows[r]) else null)
                r = r + 1
            out[u.to_text(h)] = col
            k = k + 1
        return out
    raise("ValueError", "office.json.from_rows : orientation inconnue '" + str(orient) + "' (records, rows, columns, split)")

func load_table(path):
    return to_rows(load(path))

func save_table(path, rows, orient="records", indent=2):
    save(path, from_rows(rows, orient), indent)

# ---------------------------------------------------------------------------------------------- JSON Lines

func parse_lines(text):
    out := []
    for line in u.lines(text):
        if string.trim(line) != "":
            append(out, parse(line))
    return out

func stringify_lines(values):
    out := []
    for v in values:
        append(out, stringify(v))
        append(out, "\n")
    return string.join("", out)

func load_lines(path):
    return parse_lines(u.decode_text(io.read_bytes(path)))

func save_lines(path, values):
    io.write_bytes(path, u.utf8_encode(stringify_lines(values)))

# ---------------------------------------------------------------------------------------------- objets

func _flat(v, prefix, sep, out):
    t := type(v)
    if t == "dict" and len(keys(v)) > 0:
        for k in keys(v):
            name := u.to_text(k)
            if prefix != "":
                name = prefix + sep + name
            _flat(v[k], name, sep, out)
    elif (t == "list" or t == "tuple") and len(v) > 0:
        i := 0
        for x in v:
            _flat(x, prefix + "[" + str(i) + "]", sep, out)
            i = i + 1
    else:
        out[prefix] = v

func flatten(v, sep="."):
    out := {}
    _flat(v, "", sep, out)
    return out

# Découpe « a.b[2].c » en ["a", "b", 2, "c"].
func _path_tokens(p, sep="."):
    toks := []
    buf := ""
    i := 0
    cs := u.chars(p)
    n := len(cs)
    while i < n:
        ch := cs[i]
        if ch == sep:
            if buf != "":
                append(toks, buf)
            buf = ""
            i = i + 1
        elif ch == "[":
            if buf != "":
                append(toks, buf)
            buf = ""
            j := i + 1
            num := ""
            while j < n and cs[j] != "]":
                num = num + cs[j]
                j = j + 1
            if j >= n:
                raise("ValueError", "chemin invalide : '" + p + "'")
            v := u.parse_number(num)
            if v == null or type(v) != "int":
                raise("ValueError", "indice invalide dans le chemin : '" + p + "'")
            append(toks, v)
            i = j + 1
        else:
            buf = buf + ch
            i = i + 1
    if buf != "":
        append(toks, buf)
    return toks

func get_path(v, p, fallback=null):
    cur := v
    for t in _path_tokens(p):
        if type(t) == "int":
            if (type(cur) == "list" or type(cur) == "tuple") and t >= 0 and t < len(cur):
                cur = cur[t]
            else:
                return fallback
        else:
            if type(cur) == "dict" and contains_key(cur, t):
                cur = cur[t]
            else:
                return fallback
    return cur

func set_path(v, p, value, sep="."):
    toks := _path_tokens(p, sep)
    if len(toks) == 0:
        raise("ValueError", "chemin vide")
    cur := v
    i := 0
    while i < len(toks):
        t := toks[i]
        last := i == len(toks) - 1
        if type(t) == "int":
            if type(cur) != "list":
                raise("ValueError", "set_path : liste attendue avant [" + str(t) + "]")
            while len(cur) <= t:
                append(cur, null)
            if last:
                cur[t] = value
            else:
                if cur[t] == null:
                    cur[t] = [] if type(toks[i + 1]) == "int" else {}
                cur = cur[t]
        else:
            if type(cur) != "dict":
                raise("ValueError", "set_path : objet attendu avant '" + t + "'")
            if last:
                cur[t] = value
            else:
                if not contains_key(cur, t) or cur[t] == null:
                    cur[t] = [] if type(toks[i + 1]) == "int" else {}
                cur = cur[t]
        i = i + 1
    return v

func unflatten(d, sep="."):
    out := {}
    for k in keys(d):
        set_path(out, k, d[k], sep)
    return out
