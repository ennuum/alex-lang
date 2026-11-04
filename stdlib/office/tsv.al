# ALEX STANDARD LIBRARY — office.tsv
# Valeurs séparées par des tabulations (IANA text/tab-separated-values), le format du copier-coller des tableurs.
# Deux conventions :
#   - "escape" (défaut, « TSV linéaire ») : pas de guillemets ; dans un champ, \t \n \r et \\ s'écrivent avec une
#     barre oblique inverse. Chaque ligne du fichier est exactement une ligne de données.
#   - "quote" : guillemets à la CSV (ce que produit Excel en « Texte (séparateur : tabulation) »).
#
#   use office.tsv as tsv
#   rows := tsv.parse("nom\tâge\nAda\t36\n", true)           # [["nom", "âge"], ["Ada", 36]]
#   tsv.stringify([["a\tb", 1]])                              # "a\\tb\t1\n"
#   recs := tsv.load_records("export.tsv")
#
#   parse(texte, infer=false, mode="escape", decimal=".")     parse_records(texte, infer=true, mode="escape")
#   stringify(lignes, mode="escape", newline="\n")            stringify_records(recs, columns=null, mode="escape")
#   load(chemin, infer=false, mode="escape")  load_records(chemin, ...)  save(chemin, lignes, mode="escape")
#   save_records(chemin, recs, columns=null, mode="escape")
#   escape_field(s)  unescape_field(s)
# Erreurs : CSVError (mode "quote"), ValueError (mode inconnu), TypeError.

from core use len, type
from collections use append, keys, contains_key
use string
use io
use office.utils as u
use office.csv as ocsv

func _check_mode(mode):
    if mode != "escape" and mode != "quote":
        raise("ValueError", "office.tsv : mode inconnu '" + str(mode) + "' (escape, quote)")

func escape_field(s):
    t := string.replace(s, "\\", "\\\\")
    t = string.replace(t, "\t", "\\t")
    t = string.replace(t, "\n", "\\n")
    return string.replace(t, "\r", "\\r")

func unescape_field(s):
    if not string.contains(s, "\\"):
        return s
    out := []
    esc := false
    for c in s:
        ch := str(c)
        if esc:
            if ch == "t":
                append(out, "\t")
            elif ch == "n":
                append(out, "\n")
            elif ch == "r":
                append(out, "\r")
            elif ch == "\\":
                append(out, "\\")
            else:
                append(out, "\\" + ch)
            esc = false
        elif ch == "\\":
            esc = true
        else:
            append(out, ch)
    if esc:
        append(out, "\\")
    return string.join("", out)

func parse(text, infer=false, mode="escape", decimal="."):
    _check_mode(mode)
    if mode == "quote":
        return ocsv.parse(text, "\t", infer, decimal)
    t := text
    if len(t) > 0 and string.ord(t[0]) == 65279:
        t = u.str_slice(t, 1, null)
    out := []
    for line in u.lines(t):
        if line == "":
            continue
        row := []
        for f in string.split(line, "\t"):
            v := unescape_field(f)
            if infer:
                v = ocsv.infer_value(v, decimal)
            append(row, v)
        append(out, row)
    return out

func parse_records(text, infer=true, mode="escape", decimal="."):
    rows := parse(text, false, mode, decimal)
    if len(rows) == 0:
        return []
    header := ocsv._header(rows[0])
    out := []
    r := 1
    while r < len(rows):
        rec := {}
        k := 0
        while k < len(header):
            v := null
            if k < len(rows[r]):
                v = rows[r][k]
                if infer:
                    v = ocsv.infer_value(v, decimal)
            rec[header[k]] = v
            k = k + 1
        append(out, rec)
        r = r + 1
    return out

func stringify(rows, mode="escape", newline="\n", decimal="."):
    _check_mode(mode)
    if mode == "quote":
        return ocsv.stringify(rows, "\t", "unix", decimal, false, newline)
    out := []
    for r in rows:
        cells := []
        for v in r:
            append(cells, escape_field(ocsv._field(v, decimal)))
        append(out, string.join("\t", cells))
        append(out, newline)
    return string.join("", out)

func stringify_records(records, columns=null, mode="escape", newline="\n"):
    cols := columns
    if cols == null:
        cols = ocsv.records_columns(records)
    rows := [cols]
    for rec in records:
        row := []
        for c in cols:
            append(row, u.get(rec, c, null))
        append(rows, row)
    return stringify(rows, mode, newline)

func load(path, infer=false, mode="escape", decimal="."):
    return parse(u.decode_text(io.read_bytes(path)), infer, mode, decimal)

func load_records(path, infer=true, mode="escape", decimal="."):
    return parse_records(u.decode_text(io.read_bytes(path)), infer, mode, decimal)

func save(path, rows, mode="escape", newline="\n"):
    io.write_bytes(path, u.utf8_encode(stringify(rows, mode, newline)))

func save_records(path, records, columns=null, mode="escape", newline="\n"):
    io.write_bytes(path, u.utf8_encode(stringify_records(records, columns, mode, newline)))
