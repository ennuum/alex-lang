# ALEX STANDARD LIBRARY — office.xlsx_cells
# Cellules de tableur : valeur typée, formule, style, lien, commentaire ; valeurs d'erreur (#DIV/0!, #N/A...) ;
# conversion entre valeurs ALEX et représentation SpreadsheetML (attribut t, élément v).
#
#   use office.xlsx_cells as xc
#   c := xc.Cell(2, 3)                              # ligne 2, colonne 3 (C2)
#   c.value = 42.5
#   c.formula = "SUM(A1:A10)"                       # sans « = » initial (accepté et retiré s'il est présent)
#   c.style = {"bold": true, "number_format": "0.00"}
#   c.ref()                                         # "C2"
#   xc.error("#N/A")                                # valeur d'erreur
#
# Cell(row, col, value=null) : row col value formula style (dict, voir xlsx_styles) hyperlink comment
#   ref()  coordinate() -> [row, col]  is_empty()  is_formula()  data_type() -> "n" | "s" | "b" | "d" | "e" | "str" | null
#   display(fmt=null) -> texte affiché (format numérique appliqué, voir xlsx_styles.format_value)
# ErrorValue(code) : code ("#DIV/0!", "#N/A", "#NAME?", "#NULL!", "#NUM!", "#REF!", "#VALUE!", "#SPILL!", "#CALC!")
#   error(code) -> ErrorValue   is_error(v)   ERRORS
# Valeurs : null (vide), int, float, str, bool, date (dict year/month/day[/hour/minute/second] — écrite en
#   numéro de série avec un format de date), ErrorValue.
# Fonctions : key(row, col) (clé entière de dictionnaire)  unkey(k) -> [row, col]  normalize_formula(f)
#   value_kind(v)  coerce_number(v) -> nombre ou ErrorValue (règles d'Excel)  to_display(v)
# Erreurs : ValueError, TypeError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.utils as u

const ERRORS := ["#NULL!", "#DIV/0!", "#VALUE!", "#REF!", "#NAME?", "#NUM!", "#N/A", "#GETTING_DATA", "#SPILL!", "#CALC!"]
const MAX_ROW := 1048576
const MAX_COL := 16384

class ErrorValue:
    func init(code):
        self.code = code

    func __str__():
        return self.code

func error(code):
    ok := false
    for e in ERRORS:
        if e == code:
            ok = true
    if not ok:
        raise("ValueError", "valeur d'erreur inconnue : '" + u.to_text(code) + "'")
    return ErrorValue(code)

func is_error(v):
    return isinstance(v, ErrorValue)

func key(row, col):
    return row * 16385 + col

func unkey(k):
    return [k // 16385, k % 16385]

func normalize_formula(f):
    if f == null:
        return null
    t := string.trim(u.to_text(f))
    if string.starts_with(t, "="):
        t = string.trim(_n.str_slice(t, 1, null))
    if t == "":
        return null
    return t

# "null" | "number" | "text" | "bool" | "date" | "error"
func value_kind(v):
    t := type(v)
    if v == null:
        return "null"
    if t == "int" or t == "float":
        return "number"
    if t == "str":
        return "text"
    if t == "bool":
        return "bool"
    if u.is_date_dict(v):
        return "date"
    if isinstance(v, ErrorValue):
        return "error"
    return "text"

# Valeur -> nombre selon Excel : null -> 0, bool -> 0/1, texte numérique -> nombre, date -> sérial ; sinon #VALUE!.
func coerce_number(v):
    t := type(v)
    if t == "int" or t == "float":
        return v
    if v == null:
        return 0
    if t == "bool":
        return 1 if v else 0
    if t == "str":
        n := _n.num_parse(v)
        if n != null:
            return n
        tt := string.trim(v)
        if string.ends_with(tt, "%"):
            p := _n.num_parse(_n.str_slice(tt, 0, len(tt) - 1))
            if p != null:
                return to_float(p) / 100.0
        return ErrorValue("#VALUE!")
    if u.is_date_dict(v):
        return u.date_to_serial(v["year"], v["month"], v["day"], u.get(v, "hour", 0), u.get(v, "minute", 0), u.get(v, "second", 0))
    if isinstance(v, ErrorValue):
        return v
    return ErrorValue("#VALUE!")

func to_display(v):
    if v == null:
        return ""
    if isinstance(v, ErrorValue):
        return v.code
    t := type(v)
    if t == "bool":
        return "VRAI" if v else "FAUX"
    if u.is_date_dict(v):
        if u.get(v, "hour", 0) == 0 and u.get(v, "minute", 0) == 0 and u.get(v, "second", 0) == 0:
            return u.iso_date(v)
        return u.iso_datetime(v, false)
    return u.to_text(v)

class Cell:
    func init(row, col, value=null):
        self.row = row
        self.col = col
        self.value = value
        self.formula = null
        self.style = null
        self.hyperlink = null
        self.comment = null
        self.array_ref = null

    func ref():
        return u.cell_ref(self.row, self.col)

    func coordinate():
        return [self.row, self.col]

    func is_formula():
        return self.formula != null

    func is_empty():
        return self.value == null and self.formula == null

    func set_formula(f):
        self.formula = normalize_formula(f)
        return self

    func data_type():
        k := value_kind(self.value)
        if k == "null":
            return "str" if self.formula != null else null
        if k == "number" or k == "date":
            return "n"
        if k == "text":
            return "str" if self.formula != null else "s"
        if k == "bool":
            return "b"
        if k == "error":
            return "e"
        return "s"

    func display(fmt=null):
        if fmt == null and self.style != null:
            fmt = u.get(self.style, "number_format", null)
        if fmt == null or u.is_date_dict(self.value) or type(self.value) == "str":
            return to_display(self.value)
        v := self.value
        if type(v) != "int" and type(v) != "float":
            return to_display(v)
        return _format_hook(v, fmt)

# Point d'extension : xlsx_styles installe son formateur (évite une dépendance circulaire).
_formatter := null

func set_formatter(f):
    _formatter = f

func _format_hook(v, fmt):
    if _formatter == null:
        return u.to_text(v)
    return _formatter(v, fmt)
