# ALEX STANDARD LIBRARY — office.xlsx_styles
# Styles de cellules SpreadsheetML (xl/styles.xml) : polices, remplissages, bordures, alignement, formats
# numériques ; registre dédupliqué pour l'écriture, décodage pour la lecture ; détection des formats de date ;
# rendu d'une valeur selon un format numérique Excel (« # ##0,00 € », « 0% », « dd/mm/yyyy »...).
#
#   use office.xlsx_styles as xs
#   style := {"bold": true, "color": "FFFFFF", "fill": "4472C4", "align": "center", "border": "thin",
#             "number_format": "#,##0.00"}
#   ws.set("B2", 1234.5, style)                       # voir xlsx_sheets
#   xs.format_value(1234.5, "#,##0.00")               # "1,234.50"   (xs.set_locale("fr") -> "1 234,50")
#   xs.format_value(45366, "dd/mm/yyyy")              # "15/03/2024"
#   xs.is_date_format("yyyy-mm-dd hh:mm")             # true
#
# STYLE (dict, toutes les clés facultatives)
#   police     font (nom) size bold italic underline (true | "double") strike color superscript subscript
#   fond       fill (couleur, motif plein) pattern ("solid" par défaut, "gray125", "darkGrid"...) fill2 (couleur du motif)
#   bordures   border (true = "thin", ou "thin" "medium" "thick" "dashed" "dotted" "double" "hair") border_color
#              border_left border_right border_top border_bottom (mêmes valeurs, prioritaires)
#   alignement align ("left" "center" "right" "justify" "fill" "general" "centerContinuous") valign ("top"
#              "center" "bottom") wrap indent rotation shrink
#   nombre     number_format (code Excel ; alias : "integer" "decimal" "percent" "date" "datetime" "time"
#              "currency" "euro" "text" "thousands")
#   protection locked hidden
# REGISTRE   StyleRegistry() : xf_index(style) -> indice cellXfs  to_xml() -> nœud styleSheet
#            parse(texte_xml) -> StyleReader : style_of(xf) -> dict   is_date_xf(xf)   number_format_of(xf)
# FORMATS    format_value(v, code)  is_date_format(code)  builtin_format(id)  BUILTIN_FORMATS
#            set_locale("en" | "fr")  (séparateurs décimal / milliers et noms des mois / jours)
#            merge_styles(a, b) -> nouveau dict (b prioritaire)
# Erreurs : ValueError (valeur de style invalide), XMLError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.xlsx_cells as xc
use time

const BUILTIN_FORMATS := {"0": "General", "1": "0", "2": "0.00", "3": "#,##0", "4": "#,##0.00", "9": "0%", "10": "0.00%", "11": "0.00E+00", "12": "# ?/?", "13": "# ??/??", "14": "mm-dd-yy", "15": "d-mmm-yy", "16": "d-mmm", "17": "mmm-yy", "18": "h:mm AM/PM", "19": "h:mm:ss AM/PM", "20": "h:mm", "21": "h:mm:ss", "22": "m/d/yy h:mm", "37": "#,##0 ;(#,##0)", "38": "#,##0 ;[Red](#,##0)", "39": "#,##0.00;(#,##0.00)", "40": "#,##0.00;[Red](#,##0.00)", "45": "mm:ss", "46": "[h]:mm:ss", "47": "mmss.0", "48": "##0.0E+0", "49": "@"}
const _ALIASES := {"integer": "0", "decimal": "0.00", "percent": "0%", "percent2": "0.00%", "date": "yyyy-mm-dd", "datetime": "yyyy-mm-dd hh:mm:ss", "time": "hh:mm:ss", "currency": "#,##0.00 [$€-40C]", "euro": "#,##0.00 [$€-40C]", "dollar": "[$$-409]#,##0.00", "text": "@", "thousands": "#,##0", "scientific": "0.00E+00", "date_fr": "dd/mm/yyyy"}
const _BORDER_STYLES := ["thin", "medium", "thick", "dashed", "dotted", "double", "hair", "mediumDashed", "dashDot", "mediumDashDot", "dashDotDot", "mediumDashDotDot", "slantDashDot"]

_locale := {"decimal": ".", "thousands": ",", "months": ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"], "days": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"], "am": "AM", "pm": "PM"}

func set_locale(code):
    if code == "fr":
        _locale["decimal"] = ","
        _locale["thousands"] = " "
        _locale["months"] = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
        _locale["days"] = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
    elif code == "en":
        _locale["decimal"] = "."
        _locale["thousands"] = ","
        _locale["months"] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        _locale["days"] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    else:
        raise("ValueError", "set_locale : 'en' ou 'fr' attendu")

func builtin_format(ident):
    k := str(ident)
    if contains_key(BUILTIN_FORMATS, k):
        return BUILTIN_FORMATS[k]
    return null

func resolve_format(code):
    if code == null:
        return null
    if contains_key(_ALIASES, code):
        return _ALIASES[code]
    return code

func merge_styles(a, b):
    return u.merge(a, b)

# ---------------------------------------------------------------------------------------------- formats

# Retire les parties entre guillemets, échappées (\x, _x, *x) et les blocs [..] (sauf [h] [m] [s]).
func _strip_literals(code):
    out := []
    cs := u.chars(code)
    i := 0
    n := len(cs)
    while i < n:
        c := cs[i]
        if c == "\"":
            i = i + 1
            while i < n and cs[i] != "\"":
                i = i + 1
            i = i + 1
            continue
        if c == "\\" or c == "_" or c == "*":
            i = i + 2
            continue
        if c == "[":
            j := i
            while j < n and cs[j] != "]":
                j = j + 1
            inner := string.lower(string.join("", _n.bytes_slice(cs, i + 1, j)))
            if inner == "h" or inner == "hh" or inner == "m" or inner == "mm" or inner == "s" or inner == "ss":
                append(out, inner)
            i = j + 1
            continue
        append(out, c)
        i = i + 1
    return string.join("", out)

func is_date_format(code):
    if code == null:
        return false
    c := resolve_format(code)
    first := c
    k := string.find(c, ";")
    if k >= 0:
        first = _n.str_slice(c, 0, k)
    s := string.lower(_strip_literals(first))
    if s == "general" or s == "@":
        return false
    for ch in ["y", "d", "h", "s"]:
        if string.contains(s, ch):
            return true
    if string.contains(s, "m") and not string.contains(s, "0") and not string.contains(s, "#"):
        return true
    return false

func _sections(code):
    out := []
    buf := []
    inq := false
    for c in code:
        ch := str(c)
        if ch == "\"":
            inq = not inq
        if ch == ";" and not inq:
            append(out, string.join("", buf))
            buf = []
        else:
            append(buf, ch)
    append(out, string.join("", buf))
    return out

func _group(intpart):
    sep := _locale["thousands"]
    out := ""
    n := len(intpart)
    i := 0
    for c in intpart:
        if i > 0 and (n - i) % 3 == 0:
            out = out + sep
        out = out + str(c)
        i = i + 1
    return out

# Arrondi décimal sûr en texte (évite 2.675 -> 2.67 dû au binaire) : demi loin de zéro.
func _fixed(x, decimals):
    v := u.round_to(to_float(x), decimals)
    s := u.format_number(v if v >= 0 else -v)
    if string.contains(s, "E"):
        s = u.format_number(u.round_to(v if v >= 0 else -v, decimals) + 0.0)
        if string.contains(s, "E"):
            # très grand ou très petit : notation fixe
            if (v if v >= 0 else -v) < 1:
                s = "0"
    ip := s
    fp := ""
    k := string.find(s, ".")
    if k >= 0:
        ip = _n.str_slice(s, 0, k)
        fp = _n.str_slice(s, k + 1, null)
    while len(fp) < decimals:
        fp = fp + "0"
    if len(fp) > decimals:
        fp = _n.str_slice(fp, 0, decimals)
    return [ip, fp]

func _format_number_section(x, sec):
    s := sec
    # couleurs / conditions [Red] [>100] : ignorées ; [$€-40C] : symbole conservé
    out_prefix := ""
    literal := []
    cs := u.chars(s)
    pattern := []
    i := 0
    n := len(cs)
    percent := 0
    while i < n:
        c := cs[i]
        if c == "\"":
            j := i + 1
            buf := ""
            while j < n and cs[j] != "\"":
                buf = buf + cs[j]
                j = j + 1
            append(pattern, ["lit", buf])
            i = j + 1
            continue
        if c == "\\":
            if i + 1 < n:
                append(pattern, ["lit", cs[i + 1]])
            i = i + 2
            continue
        if c == "_":
            append(pattern, ["lit", " "])
            i = i + 2
            continue
        if c == "*":
            i = i + 2
            continue
        if c == "[":
            j := i + 1
            buf := ""
            while j < n and cs[j] != "]":
                buf = buf + cs[j]
                j = j + 1
            if string.starts_with(buf, "$"):
                sym := _n.str_slice(buf, 1, null)
                dash := string.find(sym, "-")
                if dash >= 0:
                    sym = _n.str_slice(sym, 0, dash)
                append(pattern, ["lit", sym])
            i = j + 1
            continue
        if c == "%":
            percent = percent + 1
            append(pattern, ["lit", "%"])
            i = i + 1
            continue
        if c == "0" or c == "#" or c == "?" or c == "." or c == ",":
            append(pattern, ["num", c])
            i = i + 1
            continue
        if c == "E" or c == "e":
            if i + 1 < n and (cs[i + 1] == "+" or cs[i + 1] == "-"):
                append(pattern, ["exp", cs[i + 1]])
                i = i + 2
                continue
        append(pattern, ["lit", c])
        i = i + 1
    # analyse du motif numérique
    num_spec := ""
    exp_digits := -1
    after_exp := false
    for p in pattern:
        if p[0] == "num" and not after_exp:
            num_spec = num_spec + p[1]
        elif p[0] == "exp":
            after_exp = true
            exp_digits = 0
        elif p[0] == "num" and after_exp:
            exp_digits = exp_digits + 1
    v := to_float(x)
    k := 0
    while k < percent:
        v = v * 100.0
        k = k + 1
    # virgules finales = division par 1000
    while string.ends_with(num_spec, ","):
        num_spec = _n.str_slice(num_spec, 0, len(num_spec) - 1)
        v = v / 1000.0
    dot := string.find(num_spec, ".")
    int_spec := num_spec
    frac_spec := ""
    if dot >= 0:
        int_spec = _n.str_slice(num_spec, 0, dot)
        frac_spec = _n.str_slice(num_spec, dot + 1, null)
    grouping := string.contains(int_spec, ",")
    int_spec = string.replace(int_spec, ",", "")
    decimals := len(frac_spec)
    min_frac := string.count(frac_spec, "0")
    min_int := string.count(int_spec, "0")
    neg := v < 0
    av := -v if neg else v
    body := ""
    if exp_digits >= 0:
        e := 0
        if av != 0:
            while av >= 10.0:
                av = av / 10.0
                e = e + 1
            while av < 1.0:
                av = av * 10.0
                e = e - 1
        parts := _fixed(av, decimals)
        if parts[0] == "10":
            parts = _fixed(1.0, decimals)
            e = e + 1
        es := str(-e if e < 0 else e)
        while len(es) < exp_digits:
            es = "0" + es
        body = parts[0] + (_locale["decimal"] + parts[1] if decimals > 0 else "") + "E" + ("-" if e < 0 else "+") + es
    else:
        parts := _fixed(av, decimals)
        ip := parts[0]
        fp := parts[1]
        # zéros non significatifs facultatifs (#) dans la partie décimale
        while len(fp) > min_frac and string.ends_with(fp, "0"):
            fp = _n.str_slice(fp, 0, len(fp) - 1)
        if ip == "0" and min_int == 0:
            ip = ""
        while len(ip) < min_int:
            ip = "0" + ip
        if grouping:
            ip = _group(ip)
        body = ip
        if decimals > 0 and (fp != "" or min_frac > 0):
            body = body + _locale["decimal"] + fp
        elif dot >= 0 and decimals == 0:
            body = body
    # recomposition : littéraux avant / après le premier bloc numérique
    out := []
    placed := false
    for p in pattern:
        if p[0] == "lit":
            append(out, p[1])
        elif not placed:
            append(out, body)
            placed = true
    if not placed:
        append(out, body)
    return [neg, string.join("", out)]

func _date_format(serial, code):
    d := u.serial_to_date(serial)
    cs := u.chars(code)
    n := len(cs)
    out := []
    ampm := string.contains(string.upper(code), "AM/PM") or string.contains(string.upper(code), "A/P")
    # premier passage : jetons
    toks := []
    i := 0
    while i < n:
        c := cs[i]
        lc := string.lower(c)
        if c == "\"":
            j := i + 1
            buf := ""
            while j < n and cs[j] != "\"":
                buf = buf + cs[j]
                j = j + 1
            append(toks, ["lit", buf])
            i = j + 1
            continue
        if c == "\\":
            if i + 1 < n:
                append(toks, ["lit", cs[i + 1]])
            i = i + 2
            continue
        if c == "[":
            j := i + 1
            buf := ""
            while j < n and cs[j] != "]":
                buf = buf + cs[j]
                j = j + 1
            bl := string.lower(buf)
            if bl == "h" or bl == "hh":
                append(toks, ["H", bl])
            elif bl == "m" or bl == "mm":
                append(toks, ["M", bl])
            elif bl == "s" or bl == "ss":
                append(toks, ["S", bl])
            i = j + 1
            continue
        if string.upper(_n.str_slice(code, i, i + 5)) == "AM/PM":
            append(toks, ["ampm", ""])
            i = i + 5
            continue
        if lc == "y" or lc == "m" or lc == "d" or lc == "h" or lc == "s":
            j := i
            while j < n and string.lower(cs[j]) == lc:
                j = j + 1
            append(toks, [lc, j - i])
            i = j
            continue
        if c == "." and i + 1 < n and cs[i + 1] == "0":
            j := i + 1
            while j < n and cs[j] == "0":
                j = j + 1
            append(toks, ["frac", j - i - 1])
            i = j
            continue
        append(toks, ["lit", c])
        i = i + 1
    # « m » après h ou avant s = minutes
    k := 0
    while k < len(toks):
        if toks[k][0] == "m":
            prev := k - 1
            while prev >= 0 and toks[prev][0] == "lit":
                prev = prev - 1
            nxt := k + 1
            while nxt < len(toks) and toks[nxt][0] == "lit":
                nxt = nxt + 1
            if (prev >= 0 and (toks[prev][0] == "h" or toks[prev][0] == "H")) or (nxt < len(toks) and (toks[nxt][0] == "s" or toks[nxt][0] == "S")):
                toks[k] = ["min", toks[k][1]]
        k = k + 1
    hour := d["hour"]
    total_secs := to_float(serial) * 86400.0
    for t in toks:
        kind := t[0]
        cnt := t[1]
        if kind == "lit":
            append(out, cnt)
        elif kind == "y":
            append(out, u.pad_left(str(d["year"] % 100), 2, "0") if cnt <= 2 else str(d["year"]))
        elif kind == "m":
            if cnt == 1:
                append(out, str(d["month"]))
            elif cnt == 2:
                append(out, u.pad_left(str(d["month"]), 2, "0"))
            elif cnt == 3:
                append(out, _n.str_slice(_locale["months"][d["month"] - 1], 0, 3))
            elif cnt == 5:
                append(out, _n.str_slice(_locale["months"][d["month"] - 1], 0, 1))
            else:
                append(out, _locale["months"][d["month"] - 1])
        elif kind == "d":
            if cnt == 1:
                append(out, str(d["day"]))
            elif cnt == 2:
                append(out, u.pad_left(str(d["day"]), 2, "0"))
            else:
                wd := 0
                try:
                    wd = time.weekday(d["year"], d["month"], d["day"])
                catch e:
                    wd = 0
                name := _locale["days"][wd]
                append(out, _n.str_slice(name, 0, 3) if cnt == 3 else name)
        elif kind == "h":
            hh := hour
            if ampm:
                hh = hour % 12
                if hh == 0:
                    hh = 12
            append(out, u.pad_left(str(hh), 2, "0") if cnt >= 2 else str(hh))
        elif kind == "min":
            append(out, u.pad_left(str(d["minute"]), 2, "0") if cnt >= 2 else str(d["minute"]))
        elif kind == "s":
            append(out, u.pad_left(str(d["second"]), 2, "0") if cnt >= 2 else str(d["second"]))
        elif kind == "H":
            append(out, u.pad_left(str(to_int(total_secs) // 3600), len(cnt), "0"))
        elif kind == "M":
            append(out, u.pad_left(str(to_int(total_secs) // 60), len(cnt), "0"))
        elif kind == "S":
            append(out, u.pad_left(str(to_int(total_secs)), len(cnt), "0"))
        elif kind == "frac":
            f := total_secs - to_float(to_int(total_secs))
            s := u.format_number(u.round_to(f, cnt))
            k2 := string.find(s, ".")
            frac := _n.str_slice(s, k2 + 1, null) if k2 >= 0 else ""
            append(out, _locale["decimal"] + u.pad_right(frac, cnt, "0"))
        elif kind == "ampm":
            append(out, _locale["am"] if hour < 12 else _locale["pm"])
    return string.join("", out)

# Texte affiché pour une valeur et un code de format Excel (sous-ensemble large : sections, milliers, décimales,
# pourcentages, notation scientifique, littéraux, symboles monétaires, dates et heures, durées [h]).
func format_value(v, code):
    c := resolve_format(code)
    if v == null:
        return ""
    if type(v) == "str":
        secs := _sections(c if c != null else "General")
        if len(secs) >= 4:
            return string.replace(_strip_text(secs[3]), "@", v)
        return v
    if type(v) == "bool":
        return "TRUE" if v else "FALSE"
    if xc.is_error(v):
        return v.code
    if u.is_date_dict(v):
        v = xc.coerce_number(v)
    if c == null or string.lower(c) == "general":
        return _general(v)
    if c == "@":
        return u.to_text(v)
    if is_date_format(c):
        try:
            return _date_format(v, _sections(c)[0])
        catch e:
            return _general(v)
    secs := _sections(c)
    sec := secs[0]
    signed := true
    if to_float(v) < 0 and len(secs) >= 2:
        sec = secs[1]
        signed = false
        v = -to_float(v)
    elif to_float(v) == 0 and len(secs) >= 3:
        sec = secs[2]
    if string.lower(string.trim(sec)) == "general":
        return _general(v)
    r := _format_number_section(v, sec)
    if r[0] and signed:
        return "-" + r[1]
    return r[1]

func _strip_text(sec):
    return string.replace(sec, "\"", "")

func _general(v):
    if type(v) == "int":
        return str(v)
    f := to_float(v)
    if f == to_float(to_int(f)) and (f if f >= 0 else -f) < 100000000000.0:
        return str(to_int(f))
    s := u.format_number(u.round_to(f, 10) if (f if f >= 0 else -f) < 100000000000.0 else f)
    return string.replace(s, ".", _locale["decimal"])

# ---------------------------------------------------------------------------------------------- registre (écriture)

func _bool(v):
    return v == true

func _font_key(s):
    return u.to_text(u.get(s, "font", "Calibri")) + "|" + u.to_text(u.get(s, "size", 11)) + "|" + u.to_text(_bool(u.get(s, "bold", false))) + "|" + u.to_text(_bool(u.get(s, "italic", false))) + "|" + u.to_text(u.get(s, "underline", false)) + "|" + u.to_text(_bool(u.get(s, "strike", false))) + "|" + u.to_text(u.get(s, "color", "")) + "|" + u.to_text(u.get(s, "superscript", false)) + u.to_text(u.get(s, "subscript", false))

func _font_xml(s):
    kids := []
    if _bool(u.get(s, "bold", false)):
        append(kids, x.el("b"))
    if _bool(u.get(s, "italic", false)):
        append(kids, x.el("i"))
    if _bool(u.get(s, "strike", false)):
        append(kids, x.el("strike"))
    un := u.get(s, "underline", false)
    if un == true:
        append(kids, x.el("u"))
    elif type(un) == "str" and un != "none":
        append(kids, x.el("u", {"val": un}))
    if u.get(s, "superscript", false) == true:
        append(kids, x.el("vertAlign", {"val": "superscript"}))
    elif u.get(s, "subscript", false) == true:
        append(kids, x.el("vertAlign", {"val": "subscript"}))
    append(kids, x.el("sz", {"val": u.format_number(u.get(s, "size", 11))}))
    col := u.get(s, "color", null)
    if col != null:
        append(kids, x.el("color", {"rgb": "FF" + u.color_hex(col)}))
    append(kids, x.el("name", {"val": u.get(s, "font", "Calibri")}))
    append(kids, x.el("family", {"val": "2"}))
    if u.get(s, "font", "Calibri") == "Calibri":
        append(kids, x.el("scheme", {"val": "minor"}))
    return x.el("font", null, kids)

func _fill_key(s):
    return u.to_text(u.get(s, "fill", "")) + "|" + u.to_text(u.get(s, "pattern", "")) + "|" + u.to_text(u.get(s, "fill2", ""))

func _fill_xml(s):
    col := u.get(s, "fill", null)
    pat := u.get(s, "pattern", "solid")
    attrs := {"patternType": pat}
    kids := []
    if col != null:
        append(kids, x.el("fgColor", {"rgb": "FF" + u.color_hex(col)}))
        f2 := u.get(s, "fill2", null)
        if f2 != null:
            append(kids, x.el("bgColor", {"rgb": "FF" + u.color_hex(f2)}))
        else:
            append(kids, x.el("bgColor", {"indexed": "64"}))
    return x.el("fill", null, [x.el("patternFill", attrs, kids)])

func _side(s, name):
    v := u.get(s, "border_" + name, null)
    if v == null:
        v = u.get(s, "border", null)
    if v == null or v == false or v == "none":
        return null
    if v == true:
        v = "thin"
    ok := false
    for b in _BORDER_STYLES:
        if b == v:
            ok = true
    if not ok:
        raise("ValueError", "style de bordure inconnu : '" + u.to_text(v) + "'")
    return v

func _border_key(s):
    k := ""
    for side in ["left", "right", "top", "bottom"]:
        k = k + u.to_text(_side(s, side)) + "|"
    return k + u.to_text(u.get(s, "border_color", ""))

func _border_xml(s):
    kids := []
    col := u.get(s, "border_color", null)
    for side in ["left", "right", "top", "bottom"]:
        st := _side(s, side)
        if st == null:
            append(kids, x.el(side))
        else:
            ck := [x.el("color", {"rgb": "FF" + u.color_hex(col)})] if col != null else [x.el("color", {"indexed": "64"})]
            append(kids, x.el(side, {"style": st}, ck))
    append(kids, x.el("diagonal"))
    return x.el("border", null, kids)

func _has_font(s):
    for k in ["font", "size", "bold", "italic", "underline", "strike", "color", "superscript", "subscript"]:
        if contains_key(s, k) and s[k] != null:
            return true
    return false

func _has_fill(s):
    return u.get(s, "fill", null) != null or (u.get(s, "pattern", null) != null and u.get(s, "pattern", null) != "none")

func _has_border(s):
    for k in ["border", "border_left", "border_right", "border_top", "border_bottom"]:
        v := u.get(s, k, null)
        if v != null and v != false and v != "none":
            return true
    return false

func _align_attrs(s):
    a := {}
    h := u.get(s, "align", null)
    if h != null:
        hl := string.lower(h)
        if hl == "centre":
            hl = "center"
        if hl == "centercontinuous":
            hl = "centerContinuous"
        a["horizontal"] = hl
    v := u.get(s, "valign", null)
    if v != null:
        vl := string.lower(v)
        if vl == "middle" or vl == "centre":
            vl = "center"
        a["vertical"] = vl
    if u.get(s, "wrap", false) == true:
        a["wrapText"] = "1"
    if u.get(s, "indent", null) != null:
        a["indent"] = str(u.get(s, "indent", 0))
    if u.get(s, "rotation", null) != null:
        a["textRotation"] = str(u.get(s, "rotation", 0))
    if u.get(s, "shrink", false) == true:
        a["shrinkToFit"] = "1"
    return a

class StyleRegistry:
    func init():
        self.fonts = [_font_xml({})]
        self._font_keys = {_font_key({}): 0}
        self.fills = [x.el("fill", null, [x.el("patternFill", {"patternType": "none"})]), x.el("fill", null, [x.el("patternFill", {"patternType": "gray125"})])]
        self._fill_keys = {}
        self.borders = [_border_xml({})]
        self._border_keys = {_border_key({}): 0}
        self.num_fmts = []
        self._fmt_ids = {}
        self.xfs = [x.el("xf", {"numFmtId": "0", "fontId": "0", "fillId": "0", "borderId": "0", "xfId": "0"})]
        self._xf_keys = {}

    func _num_fmt_id(code):
        c := resolve_format(code)
        if c == null:
            return 0
        for k in keys(BUILTIN_FORMATS):
            if BUILTIN_FORMATS[k] == c:
                return to_int(_n.num_parse(k))
        if contains_key(self._fmt_ids, c):
            return self._fmt_ids[c]
        ident := 164 + len(self.num_fmts)
        append(self.num_fmts, x.el("numFmt", {"numFmtId": str(ident), "formatCode": c}))
        self._fmt_ids[c] = ident
        return ident

    func xf_index(style):
        if style == null or len(keys(style)) == 0:
            return 0
        s := style
        font_id := 0
        if _has_font(s):
            k := _font_key(s)
            if not contains_key(self._font_keys, k):
                self._font_keys[k] = len(self.fonts)
                append(self.fonts, _font_xml(s))
            font_id = self._font_keys[k]
        fill_id := 0
        if _has_fill(s):
            k := _fill_key(s)
            if not contains_key(self._fill_keys, k):
                self._fill_keys[k] = len(self.fills)
                append(self.fills, _fill_xml(s))
            fill_id = self._fill_keys[k]
        border_id := 0
        if _has_border(s):
            k := _border_key(s)
            if not contains_key(self._border_keys, k):
                self._border_keys[k] = len(self.borders)
                append(self.borders, _border_xml(s))
            border_id = self._border_keys[k]
        fmt_id := self._num_fmt_id(u.get(s, "number_format", null))
        al := _align_attrs(s)
        locked := u.get(s, "locked", null)
        hidden := u.get(s, "hidden", null)
        key := str(font_id) + "|" + str(fill_id) + "|" + str(border_id) + "|" + str(fmt_id) + "|" + u.to_text(al) + "|" + u.to_text(locked) + u.to_text(hidden)
        if contains_key(self._xf_keys, key):
            return self._xf_keys[key]
        attrs := {"numFmtId": str(fmt_id), "fontId": str(font_id), "fillId": str(fill_id), "borderId": str(border_id), "xfId": "0"}
        if fmt_id != 0:
            attrs["applyNumberFormat"] = "1"
        if font_id != 0:
            attrs["applyFont"] = "1"
        if fill_id != 0:
            attrs["applyFill"] = "1"
        if border_id != 0:
            attrs["applyBorder"] = "1"
        kids := []
        if len(keys(al)) > 0:
            attrs["applyAlignment"] = "1"
            append(kids, x.el("alignment", al))
        if locked != null or hidden != null:
            attrs["applyProtection"] = "1"
            pa := {}
            if locked != null:
                pa["locked"] = "1" if locked else "0"
            if hidden != null:
                pa["hidden"] = "1" if hidden else "0"
            append(kids, x.el("protection", pa))
        idx := len(self.xfs)
        append(self.xfs, x.el("xf", attrs, kids))
        self._xf_keys[key] = idx
        return idx

    func to_xml():
        kids := []
        if len(self.num_fmts) > 0:
            append(kids, x.el("numFmts", {"count": str(len(self.num_fmts))}, self.num_fmts))
        append(kids, x.el("fonts", {"count": str(len(self.fonts))}, self.fonts))
        append(kids, x.el("fills", {"count": str(len(self.fills))}, self.fills))
        append(kids, x.el("borders", {"count": str(len(self.borders))}, self.borders))
        append(kids, x.el("cellStyleXfs", {"count": "1"}, [x.el("xf", {"numFmtId": "0", "fontId": "0", "fillId": "0", "borderId": "0"})]))
        append(kids, x.el("cellXfs", {"count": str(len(self.xfs))}, self.xfs))
        append(kids, x.el("cellStyles", {"count": "1"}, [x.el("cellStyle", {"name": "Normal", "xfId": "0", "builtinId": "0"})]))
        append(kids, x.el("dxfs", {"count": "0"}))
        append(kids, x.el("tableStyles", {"count": "0", "defaultTableStyle": "TableStyleMedium2", "defaultPivotStyle": "PivotStyleLight16"}))
        return x.el("styleSheet", {"xmlns": x.NS["x"]}, kids)

# ---------------------------------------------------------------------------------------------- lecture

func _color_of(el):
    if el == null:
        return null
    rgb := x.attr(el, "rgb", null)
    if rgb != null and len(rgb) >= 6:
        return string.upper(_n.str_slice(rgb, len(rgb) - 6, null))
    return null

func _read_font(f):
    s := {}
    for c in x.children(f):
        ln := x.local_name(c["tag"])
        if ln == "b":
            s["bold"] = x.attr_bool(c, "val", true)
        elif ln == "i":
            s["italic"] = x.attr_bool(c, "val", true)
        elif ln == "strike":
            s["strike"] = x.attr_bool(c, "val", true)
        elif ln == "u":
            v := x.attr(c, "val", "single")
            s["underline"] = true if v == "single" else v
        elif ln == "sz":
            s["size"] = _n.num_parse(x.attr(c, "val", "11"))
        elif ln == "color":
            col := _color_of(c)
            if col != null:
                s["color"] = col
        elif ln == "name":
            s["font"] = x.attr(c, "val", "Calibri")
        elif ln == "vertAlign":
            v := x.attr(c, "val", "")
            if v == "superscript":
                s["superscript"] = true
            elif v == "subscript":
                s["subscript"] = true
    return s

func _read_fill(f):
    s := {}
    pf := x.first(f, "patternFill")
    if pf != null:
        pt := x.attr(pf, "patternType", "none")
        if pt != "none" and pt != "gray125":
            col := _color_of(x.first(pf, "fgColor"))
            if col != null:
                s["fill"] = col
            if pt != "solid":
                s["pattern"] = pt
    return s

func _read_border(b):
    s := {}
    col := null
    for side in ["left", "right", "top", "bottom"]:
        e := x.first(b, side)
        if e != null and x.attr(e, "style", null) != null:
            s["border_" + side] = x.attr(e, "style")
            c := _color_of(x.first(e, "color"))
            if c != null:
                col = c
    if col != null:
        s["border_color"] = col
    sides := 0
    st := null
    for side in ["left", "right", "top", "bottom"]:
        if contains_key(s, "border_" + side):
            sides = sides + 1
            st = s["border_" + side]
    if sides == 4 and s["border_left"] == st and s["border_right"] == st and s["border_top"] == st and s["border_bottom"] == st:
        out := {"border": st}
        if col != null:
            out["border_color"] = col
        return out
    return s

class StyleReader:
    func init():
        self.formats = {}
        self.xfs = []
        self._styles = []

    func style_of(xf):
        if xf == null or xf < 0 or xf >= len(self._styles):
            return null
        s := self._styles[xf]
        if len(keys(s)) == 0:
            return null
        return s

    func number_format_of(xf):
        if xf == null or xf < 0 or xf >= len(self.xfs):
            return null
        fid := self.xfs[xf]
        if contains_key(self.formats, str(fid)):
            return self.formats[str(fid)]
        return builtin_format(fid)

    func is_date_xf(xf):
        if xf == null or xf < 0 or xf >= len(self.xfs):
            return false
        fid := self.xfs[xf]
        if (fid >= 14 and fid <= 22) or (fid >= 45 and fid <= 47) or (fid >= 27 and fid <= 36) or (fid >= 50 and fid <= 58):
            return true
        return is_date_format(self.number_format_of(xf))

func parse(text):
    r := StyleReader()
    root := x.parse(text)
    nf := x.first(root, "numFmts")
    if nf != null:
        for f in x.children(nf, "numFmt"):
            r.formats[x.attr(f, "numFmtId", "")] = x.attr(f, "formatCode", "General")
    fonts := []
    fl := x.first(root, "fonts")
    if fl != null:
        for f in x.children(fl, "font"):
            append(fonts, _read_font(f))
    fills := []
    fil := x.first(root, "fills")
    if fil != null:
        for f in x.children(fil, "fill"):
            append(fills, _read_fill(f))
    borders := []
    bl := x.first(root, "borders")
    if bl != null:
        for b in x.children(bl, "border"):
            append(borders, _read_border(b))
    cx := x.first(root, "cellXfs")
    if cx != null:
        idx := 0
        for xf in x.children(cx, "xf"):
            fid := x.attr_int(xf, "numFmtId", 0)
            append(r.xfs, fid)
            s := {}
            font_id := x.attr_int(xf, "fontId", 0)
            if font_id > 0 and font_id < len(fonts):
                base := fonts[0] if len(fonts) > 0 else {}
                for k in keys(fonts[font_id]):
                    v := fonts[font_id][k]
                    if not contains_key(base, k) or base[k] != v:
                        s[k] = v
            fill_id := x.attr_int(xf, "fillId", 0)
            if fill_id >= 0 and fill_id < len(fills):
                for k in keys(fills[fill_id]):
                    s[k] = fills[fill_id][k]
            border_id := x.attr_int(xf, "borderId", 0)
            if border_id >= 0 and border_id < len(borders):
                for k in keys(borders[border_id]):
                    s[k] = borders[border_id][k]
            if fid != 0:
                code := r.formats[str(fid)] if contains_key(r.formats, str(fid)) else builtin_format(fid)
                if code != null:
                    s["number_format"] = code
            al := x.first(xf, "alignment")
            if al != null:
                h := x.attr(al, "horizontal", null)
                if h != null and h != "general":
                    s["align"] = h
                v := x.attr(al, "vertical", null)
                if v != null and v != "bottom":
                    s["valign"] = v
                if x.attr_bool(al, "wrapText", false):
                    s["wrap"] = true
                ind := x.attr_int(al, "indent", 0)
                if ind > 0:
                    s["indent"] = ind
                rot := x.attr_int(al, "textRotation", 0)
                if rot != 0:
                    s["rotation"] = rot
            append(r._styles, s)
            idx = idx + 1
    return r

func _install():
    xc.set_formatter(format_value)

_install()
