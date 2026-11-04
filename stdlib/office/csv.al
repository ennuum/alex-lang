# ALEX STANDARD LIBRARY — office.csv
# CSV pour la bureautique, au-dessus du module standard `csv` (RFC 4180) : détection du séparateur, encodages
# (BOM UTF-8 / UTF-16, Windows-1252), conversion des types, décimale française, compatibilité Excel.
#
#   use office.csv as csv
#   rows := csv.load("ventes.csv", null, true)          # séparateur détecté, types convertis
#   recs := csv.load_records("ventes.csv")               # [{"produit": "A", "qte": 3}, ...]
#   csv.save("sortie.csv", rows, ";", "excel")           # dialecte Excel français : « ; », décimale « , », BOM
#   csv.sniff("a;b;c\n1;2;3\n")                          # ";"
#
# LECTURE
#   parse(texte, delimiter=null, infer=false, decimal=".", skip_blank=true, comment=null, quote="\"")
#       -> lignes (listes). delimiter null : détection (sniff). comment : préfixe des lignes ignorées ("#").
#   parse_records(texte, delimiter=null, infer=true, decimal=".", columns=null)  -> liste de dicts (la 1re ligne est
#       l'en-tête, sauf si `columns` est fourni ; en-têtes vides -> "colonne_N", doublons suffixés « _2 »)
#   load(chemin, ...) / load_records(chemin, ...)   (encodage détecté : voir utils.decode_text)
# ÉCRITURE
#   stringify(lignes, delimiter=",", dialect="rfc", decimal=null, quote_all=false, newline=null)
#       dialect "rfc" : CRLF, décimale « . » ; "unix" : LF ; "excel" : CRLF, « ; » et décimale « , » si delimiter
#       est ";" (sinon « . ») ; les dates (dict year/month/day) s'écrivent en ISO 8601.
#   stringify_records(recs, columns=null, delimiter=",", dialect="rfc", decimal=null)
#   save(chemin, lignes, delimiter=",", dialect="rfc", bom=null)   save_records(chemin, recs, columns=null, ...)
#       bom null : BOM UTF-8 seulement pour le dialecte "excel" (Excel reconnaît alors l'UTF-8).
# TYPES
#   infer_value(texte, decimal=".") : "" -> null ; entiers ; décimaux (« 1 234,5 » si decimal=",") ; true/false,
#       vrai/faux ; pourcentages « 12% » -> 0.12 ; le reste reste du texte (zéros initiaux conservés : « 007 »).
#   infer_rows(lignes, decimal=".")   columns_types(lignes) -> ["int" | "float" | "bool" | "str" | "null", ...]
#   sniff(texte) -> séparateur probable parmi , ; TAB | :
# Erreurs : CSVError (texte mal formé, avec position), TypeError.

use csv as _std
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use io
use office.utils as u
use office.errors as errors

const _CANDIDATES := [",", ";", "\t", "|", ":"]

# Séparateur le plus régulier sur les premières lignes (hors guillemets).
func sniff(text):
    sample := text
    if len(sample) > 20000:
        sample = u.str_slice(sample, 0, 20000)
    lines := u.lines(sample)
    best := ","
    best_score := -1
    for d in _CANDIDATES:
        counts := []
        k := 0
        for line in lines:
            if k >= 20:
                break
            if string.trim(line) == "":
                continue
            n := 0
            inq := false
            for c in line:
                ch := str(c)
                if ch == "\"":
                    inq = not inq
                elif ch == d and not inq:
                    n = n + 1
            append(counts, n)
            k = k + 1
        if len(counts) == 0:
            continue
        first := counts[0]
        if first == 0:
            continue
        same := 0
        for c in counts:
            if c == first:
                same = same + 1
        score := same * 100 + first
        if d == ":":
            score = score - 50
        if score > best_score:
            best_score = score
            best = d
    return best

func _strip_bom(text):
    if len(text) > 0 and string.ord(text[0]) == 65279:
        return u.str_slice(text, 1, null)
    return text

# Convertit un texte de cellule en valeur typée.
func infer_value(s, decimal="."):
    if type(s) != "str":
        return s
    t := string.trim(s)
    if t == "":
        return null
    low := string.lower(t)
    if low == "true" or low == "vrai":
        return true
    if low == "false" or low == "faux":
        return false
    # zéros initiaux significatifs (codes postaux, identifiants) : on garde le texte
    if len(t) > 1 and str(t[0]) == "0" and str(t[1]) != "." and str(t[1]) != ",":
        return s
    if len(t) > 2 and (string.starts_with(t, "-0") and str(t[2]) != "." and str(t[2]) != ","):
        return s
    num := t
    pct := false
    if string.ends_with(num, "%"):
        pct = true
        num = string.trim(u.str_slice(num, 0, len(num) - 1))
    if decimal == ",":
        num = string.replace(string.replace(string.replace(num, " ", ""), " ", ""), " ", "")
        if string.contains(num, "."):
            # « 1.234,5 » : le point sert de séparateur de milliers
            if string.contains(num, ","):
                num = string.replace(num, ".", "")
            else:
                return s
        num = string.replace(num, ",", ".")
    v := u.parse_number(num)
    if v == null:
        return s
    if pct:
        return to_float(v) / 100.0
    return v

func infer_rows(rows, decimal="."):
    out := []
    for r in rows:
        row := []
        for c in r:
            append(row, infer_value(c, decimal))
        append(out, row)
    return out

func _kind(v):
    t := type(v)
    if v == null:
        return "null"
    return t

# Type dominant de chaque colonne (en ignorant les cellules vides) : "int", "float", "bool", "str" ou "null".
func columns_types(rows):
    width := 0
    for r in rows:
        if len(r) > width:
            width = len(r)
    out := []
    c := 0
    while c < width:
        kind := "null"
        for r in rows:
            if c >= len(r):
                continue
            k := _kind(r[c])
            if k == "null":
                continue
            if kind == "null":
                kind = k
            elif kind != k:
                if (kind == "int" and k == "float") or (kind == "float" and k == "int"):
                    kind = "float"
                else:
                    kind = "str"
        append(out, kind)
        c = c + 1
    return out

func parse(text, delimiter=null, infer=false, decimal=".", skip_blank=true, comment=null, quote="\""):
    if type(text) != "str":
        raise("TypeError", "office.csv.parse : texte attendu (obtenu '" + type(text) + "')")
    t := _strip_bom(text)
    d := delimiter
    if d == null:
        d = sniff(t)
    rows := _std.parse(t, d, quote)
    out := []
    for r in rows:
        if skip_blank and len(r) == 1 and string.trim(r[0]) == "":
            continue
        if comment != null and len(r) > 0 and string.starts_with(r[0], comment):
            continue
        if infer:
            row := []
            for c in r:
                append(row, infer_value(c, decimal))
            append(out, row)
        else:
            append(out, r)
    return out

func _header(names):
    out := []
    seen := {}
    i := 1
    for h in names:
        name := string.trim(u.to_text(h))
        if name == "":
            name = "colonne_" + str(i)
        base := name
        k := 2
        while contains_key(seen, name):
            name = base + "_" + str(k)
            k = k + 1
        seen[name] = true
        append(out, name)
        i = i + 1
    return out

func parse_records(text, delimiter=null, infer=true, decimal=".", columns=null):
    rows := parse(text, delimiter, false, decimal)
    if len(rows) == 0:
        return []
    header := null
    start := 0
    if columns != null:
        header = _header(columns)
    else:
        header = _header(rows[0])
        start = 1
    out := []
    r := start
    while r < len(rows):
        row := rows[r]
        rec := {}
        k := 0
        while k < len(header):
            v := null
            if k < len(row):
                v = row[k]
                if infer:
                    v = infer_value(v, decimal)
            rec[header[k]] = v
            k = k + 1
        append(out, rec)
        r = r + 1
    return out

func load(path, delimiter=null, infer=false, decimal=".", skip_blank=true, comment=null):
    return parse(u.decode_text(io.read_bytes(path)), delimiter, infer, decimal, skip_blank, comment)

func load_records(path, delimiter=null, infer=true, decimal=".", columns=null):
    return parse_records(u.decode_text(io.read_bytes(path)), delimiter, infer, decimal, columns)

func _field(v, decimal):
    t := type(v)
    if v == null:
        return ""
    if t == "str":
        return v
    if t == "int":
        return str(v)
    if t == "float":
        s := u.format_number(v)
        if decimal == ",":
            s = string.replace(s, ".", ",")
        return s
    if t == "bool":
        return "true" if v else "false"
    if u.is_date_dict(v):
        if u.get(v, "hour", 0) == 0 and u.get(v, "minute", 0) == 0 and u.get(v, "second", 0) == 0:
            return u.iso_date(v)
        return u.iso_datetime(v, false)
    return u.to_text(v)

func _quote_field(s, delimiter, quote_all):
    need := quote_all
    if not need:
        for c in s:
            ch := str(c)
            if ch == delimiter or ch == "\"" or ch == "\n" or ch == "\r":
                need = true
                break
        if not need and len(s) > 0 and (str(s[0]) == " " or str(s[len(s) - 1]) == " "):
            need = true
    if not need:
        return s
    return "\"" + string.replace(s, "\"", "\"\"") + "\""

func _dialect(dialect, delimiter, decimal, newline):
    nl := newline
    dec := decimal
    if dialect == "unix":
        if nl == null:
            nl = "\n"
    elif dialect == "excel":
        if nl == null:
            nl = "\r\n"
        if dec == null:
            dec = "," if delimiter == ";" else "."
    elif dialect == "rfc":
        if nl == null:
            nl = "\r\n"
    else:
        raise("ValueError", "office.csv : dialecte inconnu '" + str(dialect) + "' (rfc, unix, excel)")
    if dec == null:
        dec = "."
    if dec == delimiter:
        raise("ValueError", "office.csv : la décimale et le séparateur doivent différer")
    return [nl, dec]

func stringify(rows, delimiter=",", dialect="rfc", decimal=null, quote_all=false, newline=null):
    if type(rows) != "list":
        raise("TypeError", "office.csv.stringify : liste de lignes attendue")
    dn := _dialect(dialect, delimiter, decimal, newline)
    out := []
    for r in rows:
        cells := []
        for v in r:
            append(cells, _quote_field(_field(v, dn[1]), delimiter, quote_all))
        append(out, string.join(delimiter, cells))
        append(out, dn[0])
    return string.join("", out)

func records_columns(records):
    cols := []
    seen := {}
    for rec in records:
        for k in keys(rec):
            if not contains_key(seen, k):
                seen[k] = true
                append(cols, k)
    return cols

func stringify_records(records, columns=null, delimiter=",", dialect="rfc", decimal=null):
    cols := columns
    if cols == null:
        cols = records_columns(records)
    rows := [cols]
    for rec in records:
        row := []
        for c in cols:
            append(row, u.get(rec, c, null))
        append(rows, row)
    return stringify(rows, delimiter, dialect, decimal)

func _write(path, text, dialect, bom):
    b := bom
    if b == null:
        b = dialect == "excel"
    data := u.utf8_encode(text)
    if b:
        data = u.concat([[239, 187, 191], data])
    io.write_bytes(path, data)

func save(path, rows, delimiter=",", dialect="rfc", bom=null, decimal=null):
    _write(path, stringify(rows, delimiter, dialect, decimal), dialect, bom)

func save_records(path, records, columns=null, delimiter=",", dialect="rfc", bom=null, decimal=null):
    _write(path, stringify_records(records, columns, delimiter, dialect, decimal), dialect, bom)
