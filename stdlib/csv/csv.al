# ALEX STANDARD LIBRARY — csv
# Lecture / écriture CSV (RFC 4180) en ALEX pur (io pour load/save).
#
#   use csv
#   rows := csv.parse("nom,age\nAda,36\n\"Hopper, G.\",85\n")     # [["nom","age"],["Ada","36"],["Hopper, G.","85"]]
#   recs := csv.parse_dict("nom,age\nAda,36\n")                    # [{"nom": "Ada", "age": "36"}]
#   text := csv.stringify([["a", 1], ["b,c", null]])               # a,1\n"b,c",\n
#
# Règles
#   - Séparateur `delimiter` (défaut ","), guillemet `quote` (défaut "\""), tous deux d'un caractère.
#   - Fins de ligne \n, \r\n et \r acceptées ; une fin de ligne finale ne crée pas de ligne vide ; "" -> [].
#   - Un champ entre guillemets peut contenir séparateurs, fins de ligne et "" (guillemet doublé).
#   - Toutes les valeurs lues sont des str (aucune conversion de type : voir core.to_int / to_float).
#   - stringify : null -> champ vide ; int/float/bool -> str(valeur) ; un champ n'est entouré de guillemets que si
#     nécessaire. Sortie terminée par `newline` (défaut "\n"), y compris après la dernière ligne.
# Erreurs : raise("CSVError", message) avec position « ligne L, colonne C » pour parse ; TypeError pour les mauvais types.

from core use len, type
from collections use append, keys, contains_key
use string
use io

func _fail(message):
    raise("CSVError", message)

func _check_char(name, value):
    if type(value) != "str" or len(value) != 1:
        raise("TypeError", "csv : " + name + " doit être une str d'un seul caractère")

func _chars(text):
    out := []
    for c in text:
        append(out, str(c))
    return out

# « ligne L, colonne C » de l'indice i dans chars.
func _where(chars, i):
    line := 1
    col := 1
    k := 0
    while k < i and k < len(chars):
        if chars[k] == "\n":
            line = line + 1
            col = 1
        else:
            col = col + 1
        k = k + 1
    return "ligne " + str(line) + ", colonne " + str(col)

# Convertit un texte CSV en liste de lignes (listes de str). Une ligne vide donne [""].
func parse(text, delimiter=",", quote="\""):
    if type(text) != "str":
        raise("TypeError", "csv.parse : chaîne attendue (obtenu '" + type(text) + "')")
    _check_char("delimiter", delimiter)
    _check_char("quote", quote)
    if delimiter == quote:
        raise("ValueError", "csv : delimiter et quote doivent différer")
    chars := _chars(text)
    n := len(chars)
    rows := []
    i := 0
    while i < n:
        row := []
        done := false
        while not done:
            buf := []
            if i < n and chars[i] == quote:
                start := i
                i = i + 1
                closed := false
                while i < n:
                    d := chars[i]
                    if d == quote:
                        if i + 1 < n and chars[i + 1] == quote:
                            append(buf, quote)
                            i = i + 2
                        else:
                            closed = true
                            i = i + 1
                            break
                    else:
                        append(buf, d)
                        i = i + 1
                if not closed:
                    _fail("guillemet non fermé (" + _where(chars, start) + ")")
                if i < n and chars[i] != delimiter and chars[i] != "\n" and chars[i] != "\r":
                    _fail("caractère inattendu après un champ entre guillemets (" + _where(chars, i) + ")")
            else:
                while i < n and chars[i] != delimiter and chars[i] != "\n" and chars[i] != "\r":
                    if chars[i] == quote:
                        _fail("guillemet inattendu dans un champ non entouré de guillemets (" + _where(chars, i) + ")")
                    append(buf, chars[i])
                    i = i + 1
            append(row, string.join("", buf))
            if i < n and chars[i] == delimiter:
                i = i + 1
            else:
                if i < n:
                    if chars[i] == "\r" and i + 1 < n and chars[i + 1] == "\n":
                        i = i + 1
                    i = i + 1
                done = true
        append(rows, row)
    return rows

# Comme parse, mais la première ligne sert d'en-tête : liste de dicts. Une ligne de longueur différente de
# l'en-tête lève CSVError ; les lignes entièrement vides ([""]) sont ignorées.
func parse_dict(text, delimiter=",", quote="\""):
    rows := parse(text, delimiter, quote)
    if len(rows) == 0:
        return []
    header := rows[0]
    seen := {}
    for h in header:
        if contains_key(seen, h):
            _fail("en-tête dupliqué : '" + h + "'")
        seen[h] = true
    out := []
    r := 1
    while r < len(rows):
        row := rows[r]
        r = r + 1
        if len(row) == 1 and row[0] == "":
            continue
        if len(row) != len(header):
            _fail("la ligne " + str(r) + " a " + str(len(row)) + " champ(s), l'en-tête en a " + str(len(header)))
        rec := {}
        k := 0
        while k < len(header):
            rec[header[k]] = row[k]
            k = k + 1
        append(out, rec)
    return out

func _field_text(v):
    t := type(v)
    if v == null:
        return ""
    if t == "str":
        return v
    if t == "int" or t == "float" or t == "bool":
        return str(v)
    raise("TypeError", "csv.stringify : valeur non sérialisable (type '" + t + "')")

func _encode(v, delimiter, quote):
    s := _field_text(v)
    need := false
    for c in s:
        ch := str(c)
        if ch == delimiter or ch == quote or ch == "\n" or ch == "\r":
            need = true
            break
    if not need:
        return s
    return quote + string.replace(s, quote, quote + quote) + quote

# Sérialise une liste de lignes (listes ou tuples).
func stringify(rows, delimiter=",", quote="\"", newline="\n"):
    _check_char("delimiter", delimiter)
    _check_char("quote", quote)
    if type(newline) != "str":
        raise("TypeError", "csv.stringify : newline doit être une str")
    if type(rows) != "list":
        raise("TypeError", "csv.stringify : liste de lignes attendue (obtenu '" + type(rows) + "')")
    out := []
    for row in rows:
        if type(row) != "list" and type(row) != "tuple":
            raise("TypeError", "csv.stringify : chaque ligne doit être une list ou un tuple")
        cells := []
        for v in row:
            append(cells, _encode(v, delimiter, quote))
        append(out, string.join(delimiter, cells) + newline)
    return string.join("", out)

# Sérialise une liste de dicts. `columns` : ordre des colonnes (défaut : clés du premier dict, triées).
func stringify_dict(records, columns=null, delimiter=",", quote="\"", newline="\n"):
    if type(records) != "list":
        raise("TypeError", "csv.stringify_dict : liste de dicts attendue")
    cols := columns
    if cols == null:
        cols = []
        if len(records) > 0:
            for k in keys(records[0]):
                append(cols, k)
            _sort_strings(cols)
    rows := [cols]
    for rec in records:
        row := []
        for c in cols:
            if contains_key(rec, c):
                append(row, rec[c])
            else:
                append(row, null)
        append(rows, row)
    return stringify(rows, delimiter, quote, newline)

func _sort_strings(l):
    n := len(l)
    i := 1
    while i < n:
        x := l[i]
        j := i - 1
        while j >= 0 and l[j] > x:
            l[j + 1] = l[j]
            j = j - 1
        l[j + 1] = x
        i = i + 1

func load(path, delimiter=",", quote="\""):
    return parse(io.read_file(path), delimiter, quote)

func load_dict(path, delimiter=",", quote="\""):
    return parse_dict(io.read_file(path), delimiter, quote)

func save(path, rows, delimiter=",", quote="\"", newline="\n"):
    io.write_file(path, stringify(rows, delimiter, quote, newline))
