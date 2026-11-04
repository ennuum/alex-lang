# ALEX STANDARD LIBRARY — office.ods
# Classeurs OpenDocument (.ods, LibreOffice Calc) en lecture et écriture, avec le modèle de classeur d'office.excel
# (Workbook / Worksheet / Cell) : valeurs typées (nombres, textes, booléens, dates, heures, pourcentages),
# formules (traduites entre la syntaxe Excel et OpenFormula : [.A1], [$Feuille.A1:.B2], « ; »), valeurs en cache,
# styles de cellules (police, couleurs, fond, bordures, alignement, retour à la ligne, formats numériques convertis
# vers / depuis les styles de données ODF), fusions, largeurs de colonnes, hauteurs de lignes, lignes / colonnes
# masquées, volets figés, filtre automatique, plages nommées, liens, commentaires, images.
#
#   use office.ods as ods
#   use office.excel as excel
#   wb := excel.new("Ventes")
#   ws := wb.active_sheet()
#   ws.append(["Produit", "Qté", "Prix", "Total"], {"bold": true, "fill": "D9E2F3"})
#   ws.append(["Pommes", 3, 1.5, "=B2*C2"])
#   ods.save(wb, "ventes.ods")
#
#   wb2 := ods.read("ventes.ods")            # -> excel.Workbook (formules en syntaxe Excel, valeurs en cache)
#   wb2.sheet(0).get("D2")                   # 4.5
#   wb2.save("ventes.xlsx")                  # conversion ODS -> XLSX
#
# read(chemin_ou_octets, calculate=false) -> excel.Workbook   read_rows(src, feuille=null) -> lignes
# write(wb, calculate=true) -> octets   save(wb, chemin, calculate=true) -> chemin
# Formules : to_openformula("SUM(A1:B2)", "Feuil1") -> "of:=SUM([.A1:.B2])"   from_openformula("of:=...") -> "SUM(A1:B2)"
# Formats : data_style_xml(code_excel, nom) -> nœud number:*-style   excel_format(nœud_style_de_données) -> code
# Limites : les graphiques ne sont pas exportés (ils le sont en XLSX) ; mise en forme conditionnelle et
#   validations ignorées.
# Erreurs : ODFError, FormatError, ArchiveError, XMLError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use office.errors as errors
use office.utils as u
use office.xml as x
use office.core as core
use office.odf as odf
use office.excel as excel
use office.xlsx_cells as xc
use office.xlsx_styles as xs
use office.xlsx_images as xi

const _NS_CONFIG := "urn:oasis:names:tc:opendocument:xmlns:config:1.0"
const _NS_OOO := "http://openoffice.org/2004/office"
const _MS_FUNCS := ["CONCAT", "TEXTJOIN", "IFS", "SWITCH", "MAXIFS", "MINIFS", "XLOOKUP", "XMATCH", "IFNA"]

# ============================================================================================== formules

func _is_alpha(ch):
    o := string.ord(ch)
    return (o >= 65 and o <= 90) or (o >= 97 and o <= 122)

func _is_dig(ch):
    o := string.ord(ch)
    return o >= 48 and o <= 57

func _is_name(ch):
    return _is_alpha(ch) or _is_dig(ch) or ch == "_" or ch == "." or string.ord(ch) > 127

# Essaie de lire une référence de cellule / colonne / ligne à partir de i : renvoie [texte, fin] ou null.
func _cell_at(cs, i):
    n := len(cs)
    k := i
    if k < n and cs[k] == "$":
        k = k + 1
    a := k
    while k < n and _is_alpha(cs[k]):
        k = k + 1
    letters := k - a
    if k < n and cs[k] == "$":
        k = k + 1
    b := k
    while k < n and _is_dig(cs[k]):
        k = k + 1
    digits := k - b
    if letters > 3 or (letters == 0 and digits == 0):
        return null
    if letters > 0 and digits == 0:
        return [string.join("", _n.bytes_slice(cs, i, k)), k, "col"]
    if letters == 0:
        return [string.join("", _n.bytes_slice(cs, i, k)), k, "row"]
    return [string.join("", _n.bytes_slice(cs, i, k)), k, "cell"]

func _quote_of_sheet(name):
    simple := true
    for c in name:
        ch := str(c)
        if not (_is_name(ch)) or ch == ".":
            simple = false
    if simple and len(name) > 0 and not _is_dig(str(name[0])):
        return name
    return "'" + string.replace(name, "'", "''") + "'"

# Excel -> OpenFormula ("of:=...")
func to_openformula(formula, sheet=null):
    f := u.to_text(formula)
    if string.starts_with(f, "="):
        f = _n.str_slice(f, 1, null)
    cs := u.chars(f)
    n := len(cs)
    out := []
    i := 0
    brace := 0
    while i < n:
        c := cs[i]
        if c == "\"":
            j := i + 1
            while j < n:
                if cs[j] == "\"":
                    if j + 1 < n and cs[j + 1] == "\"":
                        j = j + 2
                        continue
                    break
                j = j + 1
            append(out, string.join("", _n.bytes_slice(cs, i, j + 1 if j < n else n)))
            i = j + 1
            continue
        if c == "{":
            brace = brace + 1
            append(out, c)
            i = i + 1
            continue
        if c == "}":
            brace = brace - 1
            append(out, c)
            i = i + 1
            continue
        if c == ",":
            append(out, ";")
            i = i + 1
            continue
        if c == ";":
            append(out, "|" if brace > 0 else ";")
            i = i + 1
            continue
        prev := cs[i - 1] if i > 0 else ""
        if prev != "" and (_is_name(prev) or prev == "$"):
            append(out, c)
            i = i + 1
            continue
        # préfixe de feuille ?
        sheet_name := null
        k := i
        if c == "'":
            j := i + 1
            buf := ""
            while j < n:
                if cs[j] == "'":
                    if j + 1 < n and cs[j + 1] == "'":
                        buf = buf + "'"
                        j = j + 2
                        continue
                    break
                buf = buf + cs[j]
                j = j + 1
            if j + 1 < n and cs[j + 1] == "!":
                sheet_name = buf
                k = j + 2
        elif _is_name(c):
            j := i
            while j < n and _is_name(cs[j]):
                j = j + 1
            if j < n and cs[j] == "!" and j > i:
                sheet_name = string.join("", _n.bytes_slice(cs, i, j))
                k = j + 1
        r1 := _cell_at(cs, k)
        if r1 != null:
            e := r1[1]
            nxt := cs[e] if e < n else ""
            if nxt == "(" or (nxt != "" and (_is_name(nxt) and nxt != ".")) or (nxt == "." and r1[2] == "cell"):
                r1 = null
        if r1 != null:
            e := r1[1]
            r2 := null
            if e < n and cs[e] == ":":
                r2 = _cell_at(cs, e + 1)
                if r2 != null:
                    e2 := r2[1]
                    if e2 < n and (cs[e2] == "(" or _is_name(cs[e2])):
                        r2 = null
            ok := r1[2] == "cell" or (r2 != null and r2[2] == r1[2])
            if ok:
                sp := "$" + _quote_of_sheet(sheet_name) if sheet_name != null else ""
                if r2 != null:
                    append(out, "[" + sp + "." + r1[0] + ":." + r2[0] + "]")
                    i = r2[1]
                else:
                    append(out, "[" + sp + "." + r1[0] + "]")
                    i = r1[1]
                continue
        # nom de fonction Microsoft
        if _is_alpha(c):
            j := i
            while j < n and _is_name(cs[j]):
                j = j + 1
            if j < n and cs[j] == "(":
                nm := string.upper(string.join("", _n.bytes_slice(cs, i, j)))
                if string.starts_with(nm, "_XLFN."):
                    nm = _n.str_slice(nm, 6, null)
                ms := false
                for m in _MS_FUNCS:
                    if m == nm:
                        ms = true
                append(out, ("COM.MICROSOFT." + nm) if ms else nm)
                i = j
                continue
            append(out, string.join("", _n.bytes_slice(cs, i, j)))
            i = j
            continue
        append(out, c)
        i = i + 1
    return "of:=" + string.join("", out)

# "$Feuille.$A$1" / ".A1" / "'Nom long'.A1" -> [feuille ou null, cellule]
func _of_part(p):
    t := p
    if string.starts_with(t, "$"):
        t = _n.str_slice(t, 1, null)
    if string.starts_with(t, "."):
        return [null, _n.str_slice(t, 1, null)]
    if string.starts_with(t, "'"):
        cs := u.chars(t)
        j := 1
        buf := ""
        while j < len(cs):
            if cs[j] == "'":
                if j + 1 < len(cs) and cs[j + 1] == "'":
                    buf = buf + "'"
                    j = j + 2
                    continue
                break
            buf = buf + cs[j]
            j = j + 1
        rest := string.join("", _n.bytes_slice(cs, j + 1, len(cs)))
        if string.starts_with(rest, "."):
            rest = _n.str_slice(rest, 1, null)
        return [buf, rest]
    dot := -1
    i := 0
    for c in t:
        if str(c) == "." and dot < 0:
            dot = i
        i = i + 1
    if dot < 0:
        return [null, t]
    return [_n.str_slice(t, 0, dot), _n.str_slice(t, dot + 1, null)]

func _split_colon(s):
    parts := []
    buf := ""
    q := false
    for c in s:
        ch := str(c)
        if ch == "'":
            q = not q
        if ch == ":" and not q:
            append(parts, buf)
            buf = ""
        else:
            buf = buf + ch
    append(parts, buf)
    return parts

func _of_ref(inner):
    parts := _split_colon(inner)
    a := _of_part(parts[0])
    s := ""
    if a[0] != null:
        s = u.quote_sheet(a[0]) + "!"
    if len(parts) == 1:
        return s + a[1]
    b := _of_part(parts[1])
    if b[0] != null and a[0] != null and b[0] != a[0]:
        # plage 3D : non prise en charge par Excel sous cette forme ; garde la première feuille
        return s + a[1] + ":" + b[1]
    return s + a[1] + ":" + b[1]

# OpenFormula -> Excel (sans « = »)
func from_openformula(formula):
    f := string.trim(u.to_text(formula))
    for pf in ["of:", "msoxl:", "oooc:"]:
        if string.starts_with(f, pf):
            f = _n.str_slice(f, len(pf), null)
    if string.starts_with(f, "="):
        f = _n.str_slice(f, 1, null)
    cs := u.chars(f)
    n := len(cs)
    out := []
    i := 0
    brace := 0
    while i < n:
        c := cs[i]
        if c == "\"":
            j := i + 1
            while j < n:
                if cs[j] == "\"":
                    if j + 1 < n and cs[j + 1] == "\"":
                        j = j + 2
                        continue
                    break
                j = j + 1
            append(out, string.join("", _n.bytes_slice(cs, i, j + 1 if j < n else n)))
            i = j + 1
            continue
        if c == "[":
            j := i + 1
            q := false
            while j < n and (cs[j] != "]" or q):
                if cs[j] == "'":
                    q = not q
                j = j + 1
            inner := string.join("", _n.bytes_slice(cs, i + 1, j))
            append(out, "#REF!" if string.contains(inner, "#REF") else _of_ref(inner))
            i = j + 1
            continue
        if c == "{":
            brace = brace + 1
        elif c == "}":
            brace = brace - 1
        if c == ";":
            append(out, ",")
            i = i + 1
            continue
        if c == "|" and brace > 0:
            append(out, ";")
            i = i + 1
            continue
        if c == "~":
            append(out, ",")
            i = i + 1
            continue
        if _is_alpha(c):
            j := i
            while j < n and _is_name(cs[j]):
                j = j + 1
            nm := string.join("", _n.bytes_slice(cs, i, j))
            if string.starts_with(string.upper(nm), "COM.MICROSOFT."):
                nm = _n.str_slice(nm, 14, null)
            elif string.starts_with(string.upper(nm), "ORG.OPENOFFICE."):
                nm = _n.str_slice(nm, 15, null)
            append(out, nm)
            i = j
            continue
        append(out, c)
        i = i + 1
    return string.join("", out)

# ============================================================================================== formats

func _strip_brackets(code):
    out := ""
    cs := u.chars(code)
    i := 0
    n := len(cs)
    while i < n:
        c := cs[i]
        if c == "[":
            j := i + 1
            while j < n and cs[j] != "]":
                j = j + 1
            inner := string.join("", _n.bytes_slice(cs, i + 1, j))
            if string.starts_with(inner, "$"):
                sym := _n.str_slice(inner, 1, null)
                dash := string.find(sym, "-")
                if dash >= 0:
                    sym = _n.str_slice(sym, 0, dash)
                if sym != "":
                    out = out + "\"" + sym + "\""
            elif inner == "h" or inner == "hh" or inner == "m" or inner == "mm" or inner == "s" or inner == "ss":
                out = out + inner
            i = j + 1
            continue
        out = out + c
        i = i + 1
    return out

# Découpe un code en jetons : ["lit", texte] ou ["tok", "yyyy"...] ou ["num", partie numérique]
func _fmt_tokens(code):
    toks := []
    cs := u.chars(code)
    n := len(cs)
    i := 0
    while i < n:
        c := cs[i]
        if c == "\"":
            j := i + 1
            while j < n and cs[j] != "\"":
                j = j + 1
            append(toks, ["lit", string.join("", _n.bytes_slice(cs, i + 1, j))])
            i = j + 1
            continue
        if c == "\\" and i + 1 < n:
            append(toks, ["lit", cs[i + 1]])
            i = i + 2
            continue
        if c == "_" and i + 1 < n:
            append(toks, ["lit", " "])
            i = i + 2
            continue
        if c == "*" and i + 1 < n:
            i = i + 2
            continue
        lc := string.lower(c)
        if lc == "y" or lc == "m" or lc == "d" or lc == "h" or lc == "s":
            j := i
            while j < n and string.lower(cs[j]) == lc:
                j = j + 1
            append(toks, ["tok", string.lower(string.join("", _n.bytes_slice(cs, i, j)))])
            i = j
            continue
        if string.upper(_n.str_slice(code, i, i + 5)) == "AM/PM":
            append(toks, ["ampm", ""])
            i = i + 5
            continue
        if c == "0" or c == "#" or c == "?" or c == "," or c == "." or c == "%" or c == "E" or c == "e" or c == "+":
            j := i
            while j < n and (cs[j] == "0" or cs[j] == "#" or cs[j] == "?" or cs[j] == "," or cs[j] == "." or cs[j] == "E" or cs[j] == "e" or cs[j] == "+" or (cs[j] == "-" and j > 0 and (cs[j - 1] == "E" or cs[j - 1] == "e"))):
                j = j + 1
            if j > i:
                append(toks, ["num", string.join("", _n.bytes_slice(cs, i, j))])
                i = j
                if i < n and cs[i] == "%":
                    append(toks, ["pct", "%"])
                    i = i + 1
                continue
            if c == "%":
                append(toks, ["pct", "%"])
                i = i + 1
                continue
        append(toks, ["lit", c])
        i = i + 1
    # littéraux voisins fusionnés
    out := []
    for t in toks:
        if len(out) > 0 and t[0] == "lit" and out[len(out) - 1][0] == "lit":
            out[len(out) - 1] = ["lit", out[len(out) - 1][1] + t[1]]
        else:
            append(out, t)
    return out

func _num_el(spec):
    dec := 0
    ints := 0
    grouping := string.contains(spec, ",")
    dot := string.find(spec, ".")
    ip := spec if dot < 0 else _n.str_slice(spec, 0, dot)
    fp := "" if dot < 0 else _n.str_slice(spec, dot + 1, null)
    for c in ip:
        if str(c) == "0":
            ints = ints + 1
    for c in fp:
        ch := str(c)
        if ch == "0" or ch == "#" or ch == "?":
            dec = dec + 1
    if string.contains(string.upper(spec), "E"):
        ep := string.find(string.upper(spec), "E")
        mant := _n.str_slice(spec, 0, ep)
        md := string.find(mant, ".")
        d2 := 0
        if md >= 0:
            d2 = len(mant) - md - 1
        exp_digits := 0
        for c in _n.str_slice(spec, ep + 1, null):
            if str(c) == "0":
                exp_digits = exp_digits + 1
        return x.el("number:scientific-number", {"number:decimal-places": str(d2), "number:min-integer-digits": "1", "number:min-exponent-digits": str(exp_digits if exp_digits > 0 else 2)}, [])
    a := {"number:decimal-places": str(dec), "number:min-decimal-places": str(dec), "number:min-integer-digits": str(ints)}
    if grouping:
        a["number:grouping"] = "true"
    return x.el("number:number", a, [])

# Code de format Excel -> style de données ODF (null pour « General » / « @ »)
func data_style_xml(code, name):
    c := xs.resolve_format(code)
    if c == null or c == "" or string.lower(c) == "general" or c == "@":
        return null
    sec := c
    # première section seulement (positifs)
    q := false
    k := 0
    for ch in c:
        s := str(ch)
        if s == "\"":
            q = not q
        if s == ";" and not q:
            sec = _n.str_slice(c, 0, k)
            break
        k = k + 1
    sec = _strip_brackets(sec)
    toks := _fmt_tokens(sec)
    if xs.is_date_format(c):
        kids := []
        has_date := false
        has_h := false
        idx := 0
        for t in toks:
            if t[0] == "tok":
                v := t[1]
                l0 := str(v[0])
                if l0 == "y":
                    append(kids, x.el("number:year", {"number:style": "long"} if len(v) >= 3 else null, []))
                    has_date = true
                elif l0 == "d":
                    if len(v) >= 3:
                        append(kids, x.el("number:day-of-week", {"number:style": "long"} if len(v) >= 4 else null, []))
                    else:
                        append(kids, x.el("number:day", {"number:style": "long"} if len(v) == 2 else null, []))
                    has_date = true
                elif l0 == "h":
                    append(kids, x.el("number:hours", {"number:style": "long"} if len(v) >= 2 else null, []))
                    has_h = true
                elif l0 == "s":
                    append(kids, x.el("number:seconds", {"number:style": "long"} if len(v) >= 2 else null, []))
                elif l0 == "m":
                    # minutes si précédé d'une heure ou suivi de secondes
                    is_min := false
                    j := idx - 1
                    while j >= 0:
                        if toks[j][0] == "tok":
                            is_min = str(toks[j][1][0]) == "h"
                            break
                        j = j - 1
                    j = idx + 1
                    while j < len(toks):
                        if toks[j][0] == "tok":
                            if str(toks[j][1][0]) == "s":
                                is_min = true
                            break
                        j = j + 1
                    if is_min and len(v) <= 2:
                        append(kids, x.el("number:minutes", {"number:style": "long"} if len(v) == 2 else null, []))
                    else:
                        a := {}
                        if len(v) == 2 or len(v) == 4:
                            a["number:style"] = "long"
                        if len(v) >= 3:
                            a["number:textual"] = "true"
                        append(kids, x.el("number:month", a if len(keys(a)) > 0 else null, []))
                        has_date = true
            elif t[0] == "ampm":
                append(kids, x.el("number:am-pm", null, []))
            elif t[0] == "lit":
                append(kids, x.el("number:text", null, [t[1]]))
            elif t[0] == "num":
                if string.starts_with(t[1], ".") and len(kids) > 0 and x.local_name(kids[len(kids) - 1]["tag"]) == "seconds":
                    kids[len(kids) - 1]["attrs"]["number:decimal-places"] = str(len(t[1]) - 1)
                else:
                    append(kids, x.el("number:text", null, [t[1]]))
            idx = idx + 1
        tag := "number:date-style" if has_date or not has_h else "number:time-style"
        if string.starts_with(sec, "[h") or string.starts_with(c, "[h"):
            tag = "number:time-style"
        a := {"style:name": name}
        if tag == "number:time-style" and string.contains(c, "[h"):
            a["number:truncate-on-overflow"] = "false"
        return x.el(tag, a, kids)
    kids := []
    pct := false
    seen_num := false
    for t in toks:
        if t[0] == "num" and not seen_num:
            append(kids, _num_el(t[1]))
            seen_num = true
        elif t[0] == "pct":
            pct = true
            append(kids, x.el("number:text", null, ["%"]))
        elif t[0] == "lit" or t[0] == "num" or t[0] == "tok":
            append(kids, x.el("number:text", null, [t[1]]))
    if not seen_num:
        return x.el("number:text-style", {"style:name": name}, [x.el("number:text-content", null, [])])
    return x.el("number:percentage-style" if pct else "number:number-style", {"style:name": name}, kids)

func _lit(t):
    if t == "":
        return ""
    simple := true
    for c in t:
        ch := str(c)
        if not (ch == " " or ch == "€" or ch == "$" or ch == "£" or ch == "-" or ch == "/" or ch == ":" or ch == "(" or ch == ")" or ch == "%" or ch == "," or ch == "."):
            simple = false
    if simple:
        return t
    return "\"" + string.replace(t, "\"", "") + "\""

# Style de données ODF -> code de format Excel
func excel_format(ds):
    if ds == null:
        return null
    tag := x.local_name(ds["tag"])
    out := ""
    for c in x.children(ds):
        ln := x.local_name(c["tag"])
        long := x.attr(c, "number:style", "short") == "long"
        if ln == "number":
            dec := x.attr_int(c, "number:decimal-places", 0)
            ints := x.attr_int(c, "number:min-integer-digits", 1)
            grp := x.attr(c, "number:grouping", "false") == "true"
            ip := string.repeat("0", ints) if ints > 0 else "#"
            if grp:
                while len(ip) < 4:
                    ip = "#" + ip
                ip = _n.str_slice(ip, 0, len(ip) - 3) + "," + _n.str_slice(ip, len(ip) - 3, null)
            out = out + ip + ("." + string.repeat("0", dec) if dec > 0 else "")
        elif ln == "scientific-number":
            dec := x.attr_int(c, "number:decimal-places", 2)
            ed := x.attr_int(c, "number:min-exponent-digits", 2)
            out = out + "0" + ("." + string.repeat("0", dec) if dec > 0 else "") + "E+" + string.repeat("0", ed)
        elif ln == "fraction":
            out = out + "# ?/?"
        elif ln == "text":
            t := x.text(c)
            out = out + (t if t == "%" and tag == "percentage-style" else _lit(t))
        elif ln == "currency-symbol":
            out = out + _lit(x.text(c))
        elif ln == "year":
            out = out + ("yyyy" if long else "yy")
        elif ln == "month":
            tx := x.attr(c, "number:textual", "false") == "true"
            if tx:
                out = out + ("mmmm" if long else "mmm")
            else:
                out = out + ("mm" if long else "m")
        elif ln == "day":
            out = out + ("dd" if long else "d")
        elif ln == "day-of-week":
            out = out + ("dddd" if long else "ddd")
        elif ln == "hours":
            h := "hh" if long else "h"
            if x.attr(ds, "number:truncate-on-overflow", "true") == "false":
                h = "[" + h + "]"
            out = out + h
        elif ln == "minutes":
            out = out + ("mm" if long else "m")
        elif ln == "seconds":
            out = out + ("ss" if long else "s")
            dp := x.attr_int(c, "number:decimal-places", 0)
            if dp > 0:
                out = out + "." + string.repeat("0", dp)
        elif ln == "am-pm":
            out = out + "AM/PM"
        elif ln == "boolean":
            out = out + "BOOLEAN"
        elif ln == "text-content":
            out = out + "@"
    if out == "BOOLEAN" or out == "":
        return null
    return out

# ============================================================================================== écriture

const _BORDER_W := {"hair": "0.25pt solid", "thin": "0.75pt solid", "medium": "1.75pt solid", "thick": "2.5pt solid", "dashed": "0.75pt dashed", "dotted": "0.75pt dotted", "double": "2.25pt double", "mediumDashed": "1.75pt dashed", "dashDot": "0.75pt dashed", "mediumDashDot": "1.75pt dashed", "dashDotDot": "0.75pt dotted", "slantDashDot": "1.75pt dashed"}

func _border_val(spec, color):
    if spec == null or spec == false or spec == "none":
        return null
    s := "thin" if spec == true else spec
    w := u.get(_BORDER_W, s, "0.75pt solid")
    return w + " #" + (u.color_hex(color) if color != null else "000000")

func _col_cm(width_chars):
    px := to_float(to_int(to_float(width_chars) * 7.0 + 5.0))
    return u.format_number(u.round_to(px * 2.54 / 96.0, 4)) + "cm"

func _width_chars(len_text):
    pt := odf.to_pt(len_text)
    if pt == null:
        return null
    px := pt * 96.0 / 72.0
    w := (px - 5.0) / 7.0
    return u.round_to(w if w > 0.5 else 0.5, 2)

class _Writer:
    func init(pkg):
        self.pkg = pkg
        self.bank = odf.StyleBank()
        self.data_styles = {}
        self.ds_nodes = []
        self.n_img = 0
        self.images = {}

    func data_style(code):
        if code == null:
            return null
        if contains_key(self.data_styles, code):
            return self.data_styles[code]
        nm := "N" + str(len(self.ds_nodes) + 100)
        node := data_style_xml(code, nm)
        if node == null:
            self.data_styles[code] = null
            return null
        append(self.ds_nodes, node)
        self.data_styles[code] = nm
        return nm

    func cell_style(st, value):
        code := null
        if st != null:
            code = u.get(st, "number_format", null)
        if code == null and u.is_date_dict(value):
            has_t := u.get(value, "hour", 0) != 0 or u.get(value, "minute", 0) != 0 or u.get(value, "second", 0) != 0
            code = "yyyy-mm-dd hh:mm:ss" if has_t else "yyyy-mm-dd"
        if st == null and code == null:
            return null
        s := st if st != null else {}
        kids := []
        cp := {}
        if u.get(s, "fill", null) != null:
            cp["fo:background-color"] = "#" + u.color_hex(s["fill"])
        bc := u.get(s, "border_color", null)
        allb := _border_val(u.get(s, "border", null), bc)
        sides := {"left": u.get(s, "border_left", null), "right": u.get(s, "border_right", null), "top": u.get(s, "border_top", null), "bottom": u.get(s, "border_bottom", null)}
        any_side := false
        for k in keys(sides):
            if sides[k] != null:
                any_side = true
        if allb != null and not any_side:
            cp["fo:border"] = allb
        elif allb != null or any_side:
            for k in keys(sides):
                v := _border_val(sides[k], bc) if sides[k] != null else allb
                if v != null:
                    cp["fo:border-" + k] = v
        va := u.get(s, "valign", null)
        if va != null:
            cp["style:vertical-align"] = "middle" if va == "center" else va
        if u.get(s, "wrap", false) == true:
            cp["fo:wrap-option"] = "wrap"
        if u.get(s, "rotation", null) != null:
            cp["style:rotation-angle"] = str(to_int(s["rotation"]))
        if u.get(s, "shrink", false) == true:
            cp["style:shrink-to-fit"] = "true"
        if len(keys(cp)) > 0:
            append(kids, x.el("style:table-cell-properties", cp, []))
        al := u.get(s, "align", null)
        if al != null and al != "general":
            pp := {"fo:text-align": u.get({"left": "start", "center": "center", "right": "end", "justify": "justify", "fill": "start", "centerContinuous": "center"}, al, "start")}
            if u.get(s, "indent", null) != null:
                pp["fo:margin-left"] = odf.length(to_float(s["indent"]) * 9.0)
            append(kids, x.el("style:paragraph-properties", pp, []))
        tp := odf.text_props(s)
        if len(keys(tp)) > 0:
            append(kids, x.el("style:text-properties", tp, []))
        attrs := {}
        dsn := self.data_style(code)
        if dsn != null:
            attrs["style:data-style-name"] = dsn
        if len(kids) == 0 and len(keys(attrs)) == 0:
            return null
        return self.bank.add("table-cell", kids, "Default", attrs)

    func image(si):
        key := str(_n.crc32(si.image.data)) + ":" + str(len(si.image.data))
        name := u.get(self.images, key, null)
        if name == null:
            self.n_img = self.n_img + 1
            name = "Pictures/image" + str(self.n_img) + "." + (si.image.format if si.image.format != "jpeg" else "jpg")
            self.pkg.add_file(name, si.image.data, si.image.mime)
            self.images[key] = name
        fr := x.el("draw:frame", {"draw:z-index": "0", "draw:name": si.name if si.name != null else "Image " + str(self.n_img), "svg:width": odf.length(to_float(si.cx) / 12700.0), "svg:height": odf.length(to_float(si.cy) / 12700.0), "svg:x": odf.length(to_float(si.offset_x) / 12700.0), "svg:y": odf.length(to_float(si.offset_y) / 12700.0)}, [x.el("draw:image", {"xlink:href": name, "xlink:type": "simple", "xlink:show": "embed", "xlink:actuate": "onLoad"}, [x.el("text:p", null, [])])])
        if si.description != null and si.description != "":
            append(fr["children"], x.el("svg:desc", null, [si.description]))
        return fr

func _fmt_num(v):
    if type(v) == "int":
        return str(v)
    if type(v) == "bool":
        return "1" if v else "0"
    s := str(v)
    return s

func _value_attrs(v, st):
    a := {}
    t := type(v)
    code := xs.resolve_format(u.get(st, "number_format", null)) if st != null else null
    if v == null:
        return a
    if xc.is_error(v):
        a["office:value-type"] = "string"
        a["office:string-value"] = v.code
        return a
    if t == "bool":
        a["office:value-type"] = "boolean"
        a["office:boolean-value"] = "true" if v else "false"
        return a
    if t == "int" or t == "float":
        if code != null and xs.is_date_format(code) and not string.contains(code, "[h") and to_float(v) >= 1.0:
            f := u.serial_to_date(v)
            a["office:value-type"] = "date"
            a["office:date-value"] = _iso(f)
            return a
        if code != null and xs.is_date_format(code) and to_float(v) < 1.0 and to_float(v) >= 0.0:
            a["office:value-type"] = "time"
            a["office:time-value"] = _duration(to_float(v))
            return a
        a["office:value-type"] = "percentage" if code != null and string.contains(code, "%") else "float"
        a["office:value"] = _fmt_num(v)
        return a
    if u.is_date_dict(v):
        a["office:value-type"] = "date"
        a["office:date-value"] = _iso(v)
        return a
    a["office:value-type"] = "string"
    return a

func _iso(f):
    d := u.iso_date(f)
    h := u.get(f, "hour", 0)
    m := u.get(f, "minute", 0)
    s := to_int(u.get(f, "second", 0))
    if h == 0 and m == 0 and s == 0:
        return d
    return d + "T" + u.pad_left(str(h), 2, "0") + ":" + u.pad_left(str(m), 2, "0") + ":" + u.pad_left(str(s), 2, "0")

func _duration(frac):
    total := to_int(frac * 86400.0 + 0.5)
    return "PT" + u.pad_left(str(total // 3600), 2, "0") + "H" + u.pad_left(str((total // 60) % 60), 2, "0") + "M" + u.pad_left(str(total % 60), 2, "0") + "S"

func _display(c):
    v := c.value
    if v == null:
        return ""
    if xc.is_error(v):
        return v.code
    try:
        return c.display()
    catch e:
        return u.to_text(v)

func _sheet_node(wr, ws, wb):
    ts := wr.bank.add("table", [x.el("style:table-properties", {"table:display": "false" if ws.state != "visible" else "true", "style:writing-mode": "lr-tb"}, [])], null, {"style:master-page-name": "Default"}, "ta")
    t := x.el("table:table", {"table:name": ws.name, "table:style-name": ts}, [])
    max_r := ws.max_row()
    max_c := ws.max_col()
    # images ancrées : indexées par cellule
    imgs := {}
    for si in ws.images:
        p := u.parse_cell(si.anchor)
        k := str(p["row"]) + ":" + str(p["col"])
        if not contains_key(imgs, k):
            imgs[k] = []
        append(imgs[k], si)
        if p["row"] > max_r:
            max_r = p["row"]
        if p["col"] > max_c:
            max_c = p["col"]
    if max_c < 1:
        max_c = 1
    # colonnes
    c := 1
    while c <= max_c:
        props := {}
        if contains_key(ws.col_widths, c):
            props["style:column-width"] = _col_cm(ws.col_widths[c])
            props["style:use-optimal-column-width"] = "false"
        else:
            props["style:column-width"] = _col_cm(8.43)
        cs := wr.bank.add("table-column", [x.el("style:table-column-properties", props, [])])
        a := {"table:style-name": cs, "table:default-cell-style-name": "Default"}
        if contains_key(ws.hidden_cols, c):
            a["table:visibility"] = "collapse"
        col_el := x.el("table:table-column", a, [])
        nodes := t["children"]
        if len(nodes) > 0 and nodes[len(nodes) - 1]["attrs"]["table:style-name"] == cs and u.get(nodes[len(nodes) - 1]["attrs"], "table:visibility", "") == u.get(a, "table:visibility", ""):
            prev := nodes[len(nodes) - 1]
            prev["attrs"]["table:number-columns-repeated"] = str(to_int(u.get(prev["attrs"], "table:number-columns-repeated", "1")) + 1)
        else:
            append(nodes, col_el)
        c = c + 1
    # fusions
    spans := {}
    covered := {}
    for m in ws.merged:
        p := u.parse_range(m)
        spans[str(p["r1"]) + ":" + str(p["c1"])] = [p["r2"] - p["r1"] + 1, p["c2"] - p["c1"] + 1]
        r := p["r1"]
        while r <= p["r2"]:
            cc := p["c1"]
            while cc <= p["c2"]:
                if r != p["r1"] or cc != p["c1"]:
                    covered[str(r) + ":" + str(cc)] = true
                cc = cc + 1
            r = r + 1
        if p["r2"] > max_r:
            max_r = p["r2"]
    # lignes
    by_row := {}
    for cell in ws.cells():
        if not contains_key(by_row, cell.row):
            by_row[cell.row] = {}
        by_row[cell.row][cell.col] = cell
    empty_run := 0
    r := 1
    while r <= max_r:
        rprops := {}
        if contains_key(ws.row_heights, r):
            rprops["style:row-height"] = odf.length(ws.row_heights[r])
            rprops["style:use-optimal-row-height"] = "false"
        rs := wr.bank.add("table-row", [x.el("style:table-row-properties", rprops, [])]) if len(keys(rprops)) > 0 else null
        cells := by_row[r] if contains_key(by_row, r) else {}
        row := x.el("table:table-row", {}, [])
        if rs != null:
            row["attrs"]["table:style-name"] = rs
        if contains_key(ws.hidden_rows, r):
            row["attrs"]["table:visibility"] = "collapse"
        has_content := false
        cc := 1
        last_col := 0
        for k in keys(cells):
            if k > last_col:
                last_col = k
        for k in keys(spans):
            p := string.split(k, ":")
            if to_int(p[0]) == r and to_int(p[1]) > last_col:
                last_col = to_int(p[1])
        for k in keys(covered):
            p := string.split(k, ":")
            if to_int(p[0]) == r and to_int(p[1]) > last_col:
                last_col = to_int(p[1])
        for k in keys(imgs):
            p := string.split(k, ":")
            if to_int(p[0]) == r and to_int(p[1]) > last_col:
                last_col = to_int(p[1])
        while cc <= last_col:
            key := str(r) + ":" + str(cc)
            cell := cells[cc] if contains_key(cells, cc) else null
            if contains_key(covered, key):
                append(row["children"], x.el("table:covered-table-cell", {}, []))
                has_content = true
                cc = cc + 1
                continue
            if cell == null and not contains_key(spans, key) and not contains_key(imgs, key):
                # cellules vides consécutives
                n := 0
                while cc <= last_col and not contains_key(cells, cc) and not contains_key(covered, str(r) + ":" + str(cc)) and not contains_key(spans, str(r) + ":" + str(cc)) and not contains_key(imgs, str(r) + ":" + str(cc)):
                    n = n + 1
                    cc = cc + 1
                append(row["children"], x.el("table:table-cell", {"table:number-columns-repeated": str(n)} if n > 1 else {}, []))
                continue
            el := x.el("table:table-cell", {}, [])
            if cell != null:
                st := cell.style
                sn := wr.cell_style(st, cell.value)
                if sn != null:
                    el["attrs"]["table:style-name"] = sn
                for kk in keys(_value_attrs(cell.value, st)):
                    el["attrs"][kk] = _value_attrs(cell.value, st)[kk]
                if cell.formula != null:
                    el["attrs"]["table:formula"] = to_openformula(cell.formula, ws.name)
                    if cell.value == null:
                        el["attrs"]["office:value-type"] = "string"
                        el["attrs"]["office:string-value"] = ""
                if cell.comment != null:
                    append(el["children"], x.el("office:annotation", null, [x.el("text:p", null, odf.text_nodes(cell.comment))]))
                txt := _display(cell)
                if txt != "" or cell.hyperlink != null:
                    lines := string.split(txt, "\n")
                    for line in lines:
                        kids := odf.text_nodes(line)
                        if cell.hyperlink != null:
                            kids = [x.el("text:a", {"xlink:href": cell.hyperlink, "xlink:type": "simple"}, kids)]
                        append(el["children"], x.el("text:p", null, kids))
                has_content = true
            if contains_key(spans, key):
                el["attrs"]["table:number-rows-spanned"] = str(spans[key][0])
                el["attrs"]["table:number-columns-spanned"] = str(spans[key][1])
                has_content = true
            if contains_key(imgs, key):
                for si in imgs[key]:
                    collections.insert(el["children"], 0, wr.image(si))
                has_content = true
            append(row["children"], el)
            cc = cc + 1
        if len(row["children"]) == 0:
            append(row["children"], x.el("table:table-cell", {"table:number-columns-repeated": str(max_c)} if max_c > 1 else {}, []))
        # lignes vides consécutives regroupées
        prev_nodes := t["children"]
        last := prev_nodes[len(prev_nodes) - 1] if len(prev_nodes) > 0 else null
        if not has_content and last != null and last["tag"] == "table:table-row" and u.get(last, "_empty", false) and x.stringify(x.el("r", row["attrs"], [])) == x.stringify(x.el("r", u.get(last, "_attrs0", {}), [])):
            last["attrs"]["table:number-rows-repeated"] = str(to_int(u.get(last["attrs"], "table:number-rows-repeated", "1")) + 1)
        else:
            if not has_content:
                row["_empty"] = true
                row["_attrs0"] = u.merge(row["attrs"], null)
            append(prev_nodes, row)
        r = r + 1
    if max_r == 0:
        append(t["children"], x.el("table:table-row", null, [x.el("table:table-cell", null, [])]))
    for node in t["children"]:
        if contains_key(node, "_empty"):
            collections.remove(node, "_empty")
        if contains_key(node, "_attrs0"):
            collections.remove(node, "_attrs0")
    return t

func _range_address(sheet, rng):
    p := u.parse_range(rng)
    q := _quote_of_sheet(sheet)
    return q + "." + u.cell_ref(p["r1"], p["c1"]) + ":" + q + "." + u.cell_ref(p["r2"], p["c2"])

# "Feuil1!$A$1:$B$2" -> "$Feuil1.$A$1:.$B$2"
func _named_address(ref, default_sheet):
    parts := u.split_sheet_ref(ref)
    sh := parts[0] if parts[0] != null else default_sheet
    body := parts[1]
    q := "$" + _quote_of_sheet(sh)
    if string.contains(body, ":"):
        ab := string.split(body, ":")
        return q + "." + ab[0] + ":." + ab[1]
    return q + "." + body

func _settings(wb):
    cfg := "config"
    tables := []
    for ws in wb.sheets:
        items := []
        if ws.freeze_cell != null:
            p := u.parse_cell(ws.freeze_cell)
            col := p["col"] - 1
            row := p["row"] - 1
            pairs := [["HorizontalSplitMode", "short", "2" if col > 0 else "0"], ["VerticalSplitMode", "short", "2" if row > 0 else "0"], ["HorizontalSplitPosition", "int", str(col)], ["VerticalSplitPosition", "int", str(row)], ["ActiveSplitRange", "short", "2"], ["PositionLeft", "int", "0"], ["PositionRight", "int", str(col)], ["PositionTop", "int", "0"], ["PositionBottom", "int", str(row)]]
            for pr in pairs:
                append(items, x.el(cfg + ":config-item", {cfg + ":name": pr[0], cfg + ":type": pr[1]}, [pr[2]]))
        append(items, x.el(cfg + ":config-item", {cfg + ":name": "ShowGrid", cfg + ":type": "boolean"}, ["true" if ws.show_grid else "false"]))
        append(tables, x.el(cfg + ":config-item-map-entry", {cfg + ":name": ws.name}, items))
    active := wb.sheets[wb.active].name if wb.active < len(wb.sheets) else wb.sheets[0].name
    view := x.el(cfg + ":config-item-map-entry", null, [x.el(cfg + ":config-item", {cfg + ":name": "ViewId", cfg + ":type": "string"}, ["view1"]), x.el(cfg + ":config-item-map-named", {cfg + ":name": "Tables"}, tables), x.el(cfg + ":config-item", {cfg + ":name": "ActiveTable", cfg + ":type": "string"}, [active])])
    vs := x.el(cfg + ":config-item-set", {cfg + ":name": "ooo:view-settings"}, [x.el(cfg + ":config-item-map-indexed", {cfg + ":name": "Views"}, [view])])
    return x.el("office:document-settings", {"xmlns:office": x.NS["office"], "xmlns:config": _NS_CONFIG, "xmlns:ooo": _NS_OOO, "office:version": odf.VERSION}, [x.el("office:settings", null, [vs])])

func _styles_doc():
    root := odf.document_root("office:document-styles")
    append(root["children"], x.el("office:font-face-decls", null, [x.el("style:font-face", {"style:name": "Liberation Sans", "svg:font-family": "'Liberation Sans'", "style:font-family-generic": "swiss", "style:font-pitch": "variable"}, [])]))
    st := x.el("office:styles", null, [])
    append(st["children"], x.el("style:default-style", {"style:family": "table-cell"}, [x.el("style:paragraph-properties", {"style:tab-stop-distance": "1.25cm"}, []), x.el("style:text-properties", {"style:font-name": "Liberation Sans", "fo:font-size": "10pt", "fo:language": "fr", "fo:country": "FR"}, [])]))
    append(st["children"], x.el("style:style", {"style:name": "Default", "style:family": "table-cell"}, []))
    append(root["children"], st)
    pl := x.el("style:page-layout", {"style:name": "pm1"}, [x.el("style:page-layout-properties", {"fo:page-width": "21cm", "fo:page-height": "29.7cm", "style:print-orientation": "portrait", "fo:margin-top": "2cm", "fo:margin-bottom": "2cm", "fo:margin-left": "2cm", "fo:margin-right": "2cm", "style:writing-mode": "lr-tb"}, [])])
    append(root["children"], x.el("office:automatic-styles", null, [pl]))
    append(root["children"], x.el("office:master-styles", null, [x.el("style:master-page", {"style:name": "Default", "style:page-layout-name": "pm1"}, [])]))
    return root

func write(wb, calculate=true):
    if calculate:
        wb.calculate()
    pkg := odf.new(odf.MIME_ODS)
    pkg.metadata = wb.metadata
    wr := _Writer(pkg)
    tables := []
    for ws in wb.sheets:
        append(tables, _sheet_node(wr, ws, wb))
    sheet_el := x.el("office:spreadsheet", null, [x.el("table:calculation-settings", {"table:case-sensitive": "false", "table:search-criteria-must-apply-to-whole-cell": "true", "table:use-wildcards": "true", "table:use-regular-expressions": "false", "table:automatic-find-labels": "false"}, [])])
    for t in tables:
        append(sheet_el["children"], t)
    if len(keys(wb.defined_names)) > 0:
        ne := x.el("table:named-expressions", null, [])
        for nm in keys(wb.defined_names):
            ref := wb.defined_names[nm]
            r := ref
            if string.starts_with(r, "="):
                r = _n.str_slice(r, 1, null)
            try:
                append(ne["children"], x.el("table:named-range", {"table:name": nm, "table:base-cell-address": "$" + _quote_of_sheet(wb.sheets[0].name) + ".$A$1", "table:cell-range-address": _named_address(r, wb.sheets[0].name)}, []))
            catch e:
                append(ne["children"], x.el("table:named-expression", {"table:name": nm, "table:base-cell-address": "$" + _quote_of_sheet(wb.sheets[0].name) + ".$A$1", "table:expression": to_openformula(r)}, []))
        append(sheet_el["children"], ne)
    filters := []
    k := 0
    for ws in wb.sheets:
        if ws.auto_filter != null:
            append(filters, x.el("table:database-range", {"table:name": "__Anonymous_Sheet_DB__" + str(k), "table:target-range-address": _range_address(ws.name, ws.auto_filter), "table:display-filter-buttons": "true"}, []))
        k = k + 1
    if len(filters) > 0:
        append(sheet_el["children"], x.el("table:database-ranges", null, filters))
    root := odf.document_root("office:document-content")
    append(root["children"], x.el("office:font-face-decls", null, [x.el("style:font-face", {"style:name": "Liberation Sans", "svg:font-family": "'Liberation Sans'", "style:font-family-generic": "swiss", "style:font-pitch": "variable"}, [])]))
    auto := x.el("office:automatic-styles", null, [])
    for n in wr.ds_nodes:
        append(auto["children"], n)
    for n in wr.bank.nodes():
        append(auto["children"], n)
    append(root["children"], auto)
    append(root["children"], x.el("office:body", null, [sheet_el]))
    pkg.set_xml("content.xml", root)
    pkg.set_xml("styles.xml", _styles_doc())
    pkg.set_xml("settings.xml", _settings(wb))
    return pkg.to_bytes()

func save(wb, path, calculate=true):
    io.write_bytes(path, write(wb, calculate))
    return path

# ============================================================================================== lecture

func _parse_duration(s):
    # PT12H30M15S -> fraction de jour
    t := string.upper(s)
    if string.starts_with(t, "P"):
        t = _n.str_slice(t, 1, null)
    days := 0.0
    tp := string.find(t, "T")
    if tp > 0:
        dn := _n.num_parse(_n.str_slice(t, 0, tp - 1))
        if dn != null:
            days = to_float(dn)
    if tp >= 0:
        t = _n.str_slice(t, tp + 1, null)
    total := 0.0
    buf := ""
    for c in t:
        ch := str(c)
        if ch == "H" or ch == "M" or ch == "S":
            v := _n.num_parse(buf)
            if v != null:
                total = total + to_float(v) * (3600.0 if ch == "H" else (60.0 if ch == "M" else 1.0))
            buf = ""
        else:
            buf = buf + ch
    return days + total / 86400.0

func _parse_date(s):
    t := string.trim(s)
    y := to_int(_n.str_slice(t, 0, 4))
    mo := to_int(_n.str_slice(t, 5, 7))
    d := to_int(_n.str_slice(t, 8, 10))
    f := {"year": y, "month": mo, "day": d}
    if len(t) > 11 and str(t[10]) == "T":
        f["hour"] = to_int(_n.str_slice(t, 11, 13))
        f["minute"] = to_int(_n.str_slice(t, 14, 16))
        sec := _n.num_parse(_n.str_slice(t, 17, 19)) if len(t) >= 19 else 0
        f["second"] = to_int(sec) if sec != null else 0
    return f

func _num_value(s):
    v := _n.num_parse(s)
    if v == null:
        return 0
    if type(v) == "float" and v == to_float(to_int(v)) and not string.contains(s, ".") and not string.contains(string.lower(s), "e"):
        return to_int(v)
    if type(v) == "float" and (v > 9007199254740991.0 or v < -9007199254740991.0):
        return v
    if type(v) == "float" and v == to_float(to_int(v)) and string.ends_with(s, ".0"):
        return to_int(v)
    return v

class _Reader:
    func init(pkg, idx):
        self.pkg = pkg
        self.idx = idx
        self.style_cache = {}

    func cell_style(name):
        if name == null or name == "Default":
            return null
        if contains_key(self.style_cache, name):
            return self.style_cache[name]
        idx := self.idx
        st := {}
        f := idx.text_fmt("table-cell", name)
        for k in keys(f):
            if f[k] != false and f[k] != null and k != "font" and k != "size":
                st[k] = f[k]
        s0 := idx.get("table-cell", name)
        own_tp := x.first(s0, "style:text-properties") if s0 != null else null
        if own_tp != null:
            ft := odf.read_text_props(own_tp)
            if u.get(ft, "font", null) != null:
                st["font"] = ft["font"]
            if u.get(ft, "size", null) != null:
                st["size"] = ft["size"]
        cp := idx.props("table-cell", name, "style:table-cell-properties")
        bg := u.get(cp, "fo:background-color", null)
        if bg != null and string.starts_with(bg, "#"):
            st["fill"] = string.upper(_n.str_slice(bg, 1, null))
        b := u.get(cp, "fo:border", null)
        if b != null and b != "none":
            st["border"] = _border_kind(b)
            col := _border_color(b)
            if col != null and col != "000000":
                st["border_color"] = col
        for side in ["left", "right", "top", "bottom"]:
            bs := u.get(cp, "fo:border-" + side, null)
            if bs != null and bs != "none":
                st["border_" + side] = _border_kind(bs)
        va := u.get(cp, "style:vertical-align", null)
        if va != null and va != "automatic":
            st["valign"] = "center" if va == "middle" else va
        if u.get(cp, "fo:wrap-option", "") == "wrap":
            st["wrap"] = true
        rot := u.get(cp, "style:rotation-angle", null)
        if rot != null and rot != "0":
            r := _n.num_parse(rot)
            if r != null:
                st["rotation"] = to_int(r)
        pp := idx.props("table-cell", name, "style:paragraph-properties")
        al := u.get(pp, "fo:text-align", null)
        if al != null:
            mapped := u.get({"start": "left", "left": "left", "center": "center", "end": "right", "right": "right", "justify": "justify"}, al, null)
            if mapped != null:
                st["align"] = mapped
        dsn := null
        for nm in idx.chain("table-cell", name):
            s := idx.get("table-cell", nm)
            if s != null and dsn == null:
                dsn = x.attr(s, "style:data-style-name", null)
        if dsn != null:
            code := excel_format(u.get(idx.data_styles, dsn, null))
            if code != null:
                st["number_format"] = code
        res := st if len(keys(st)) > 0 else null
        self.style_cache[name] = res
        return res

    func image(fr):
        img := x.first(fr, "draw:image")
        if img == null:
            return null
        href := x.attr(img, "xlink:href", "")
        if string.starts_with(href, "./"):
            href = _n.str_slice(href, 2, null)
        if href == "" or not self.pkg.archive.contains(href):
            return null
        data := self.pkg.archive.read(href)
        w := odf.to_pt(x.attr(fr, "svg:width", null))
        h := odf.to_pt(x.attr(fr, "svg:height", null))
        return [data, w, h, x.attr(fr, "draw:name", null)]

func _border_kind(spec):
    s := string.lower(spec)
    if string.contains(s, "double"):
        return "double"
    if string.contains(s, "dashed"):
        return "dashed"
    if string.contains(s, "dotted"):
        return "dotted"
    parts := string.split(s, " ")
    w := odf.to_pt(parts[0], 0.75)
    if w >= 2.2:
        return "thick"
    if w >= 1.2:
        return "medium"
    if w <= 0.3:
        return "hair"
    return "thin"

func _border_color(spec):
    k := string.find(spec, "#")
    if k < 0:
        return null
    return string.upper(_n.str_slice(spec, k + 1, k + 7))

func _cell_text(cell):
    parts := []
    for p in x.children(cell):
        ln := x.local_name(p["tag"])
        if ln == "p" or ln == "h":
            append(parts, odf.node_text(p))
    return string.join("\n", parts)

func _cell_link(cell):
    for a in x.find_all(cell, "text:a"):
        return x.attr(a, "xlink:href", null)
    return null

func _read_sheet(rd, tnode, wb):
    ws := wb.add_sheet(x.attr(tnode, "table:name", null))
    idx := rd.idx
    ts := idx.props("table", x.attr(tnode, "table:style-name", null), "style:table-properties")
    if u.get(ts, "table:display", "true") == "false":
        ws.state = "hidden"
    # colonnes
    col := 1
    for cnode in x.find_all(tnode, "table:table-column"):
        rep := x.attr_int(cnode, "table:number-columns-repeated", 1)
        cp := idx.props("table-column", x.attr(cnode, "table:style-name", null), "style:table-column-properties")
        w := u.get(cp, "style:column-width", null)
        hidden := x.attr(cnode, "table:visibility", "visible") == "collapse"
        k := 0
        while k < rep and col <= 16384:
            if k < 256:
                if w != null:
                    wc := _width_chars(w)
                    if wc != null and (wc < 8.0 or wc > 9.2):
                        ws.col_widths[col] = wc
                if hidden:
                    ws.hidden_cols[col] = true
            col = col + 1
            k = k + 1
            if rep > 256 and k >= 256:
                col = col + (rep - k)
                break
    rows := []
    _rows(tnode, rows)
    r := 1
    for rowinfo in rows:
        row := rowinfo[0]
        rep := rowinfo[1]
        rprops := idx.props("table-row", x.attr(row, "table:style-name", null), "style:table-row-properties")
        rh := u.get(rprops, "style:row-height", null)
        custom_h := u.get(rprops, "style:use-optimal-row-height", "true") == "false"
        hidden := x.attr(row, "table:visibility", "visible") == "collapse"
        k := 0
        while k < rep:
            if custom_h and rh != null:
                ws.row_heights[r] = u.round_to(odf.to_pt(rh), 2)
            if hidden:
                ws.hidden_rows[r] = true
            _read_row(rd, ws, row, r)
            r = r + 1
            k = k + 1
    # images en dehors des cellules (table:shapes)
    for sh in x.children(tnode, "table:shapes"):
        for fr in x.children(sh, "draw:frame"):
            im := rd.image(fr)
            if im != null:
                try:
                    ws.add_image(im[0], "A1", odf.length(im[1]), odf.length(im[2]))
                catch e:
                    continue
    return ws

func _rows(node, out):
    for c in x.children(node):
        ln := x.local_name(c["tag"])
        if ln == "table-row":
            rep := x.attr_int(c, "table:number-rows-repeated", 1)
            append(out, [c, rep])
        elif ln == "table-header-rows" or ln == "table-rows" or ln == "table-row-group":
            _rows(c, out)
    # lignes vides finales (souvent répétées 1 million de fois) retirées
    while len(out) > 0 and _row_empty(out[len(out) - 1][0]):
        collections.pop(out)
    for item in out:
        if item[1] > 1 and _row_empty(item[0]):
            if item[1] > 100000:
                item[1] = 1

func _row_empty(row):
    for c in x.children(row):
        if len(c["children"]) > 0:
            return false
        if x.attr(c, "office:value-type", null) != null or x.attr(c, "table:formula", null) != null:
            return false
        if x.attr(c, "table:number-columns-spanned", null) != null:
            return false
    return true

func _read_row(rd, ws, row, r):
    c := 1
    for cell in x.children(row):
        ln := x.local_name(cell["tag"])
        if ln != "table-cell" and ln != "covered-table-cell":
            continue
        rep := x.attr_int(cell, "table:number-columns-repeated", 1)
        vt := x.attr(cell, "office:value-type", null)
        formula := x.attr(cell, "table:formula", null)
        has_kids := len(x.children(cell)) > 0
        sname := x.attr(cell, "table:style-name", null)
        if vt == null and formula == null and not has_kids:
            cs0 := x.attr_int(cell, "table:number-columns-spanned", 1)
            rs0 := x.attr_int(cell, "table:number-rows-spanned", 1)
            if cs0 > 1 or rs0 > 1:
                ws.merge(u.range_ref(r, c, r + rs0 - 1, c + cs0 - 1))
            if sname != null and sname != "Default" and rep <= 64 and ln == "table-cell":
                st := rd.cell_style(sname)
                if st != null and (contains_key(st, "fill") or contains_key(st, "border")):
                    k := 0
                    while k < rep:
                        ws.cell(r, c + k).style = st
                        k = k + 1
            c = c + rep
            continue
        if ln == "covered-table-cell":
            c = c + rep
            continue
        value := null
        txt := _cell_text(cell)
        if vt == "float" or vt == "percentage" or vt == "currency":
            value = _num_value(x.attr(cell, "office:value", "0"))
        elif vt == "date":
            value = _parse_date(x.attr(cell, "office:date-value", ""))
        elif vt == "time":
            value = _parse_duration(x.attr(cell, "office:time-value", "PT0S"))
        elif vt == "boolean":
            bv := string.lower(x.attr(cell, "office:boolean-value", "false"))
            value = bv == "true" or bv == "1"
        elif vt == "string":
            value = x.attr(cell, "office:string-value", txt)
        elif txt != "":
            value = txt
        st := rd.cell_style(sname)
        if vt == "time" and (st == null or not contains_key(st, "number_format")):
            st = u.merge(st, {"number_format": "hh:mm:ss"})
        if vt == "percentage" and (st == null or not contains_key(st, "number_format")):
            st = u.merge(st, {"number_format": "0%"})
        ex_formula := null
        if formula != null:
            try:
                ex_formula = from_openformula(formula)
            catch e:
                ex_formula = null
            if type(value) == "str":
                for code in xc.ERRORS:
                    if value == code or txt == code:
                        value = xc.error(code)
        link := _cell_link(cell)
        comment := null
        ann := x.first(cell, "office:annotation")
        if ann != null:
            parts := []
            for p in x.children(ann, "text:p"):
                append(parts, odf.node_text(p))
            comment = string.join("\n", parts)
        k := 0
        while k < rep and c + k <= 16384:
            cl := ws.cell(r, c + k)
            cl.value = value
            if ex_formula != null:
                cl.formula = ex_formula
            if st != null:
                cl.style = st
            if link != null:
                cl.hyperlink = link
            if comment != null:
                cl.comment = comment
            k = k + 1
        cs := x.attr_int(cell, "table:number-columns-spanned", 1)
        rsp := x.attr_int(cell, "table:number-rows-spanned", 1)
        if cs > 1 or rsp > 1:
            ws.merge(u.range_ref(r, c, r + rsp - 1, c + cs - 1))
        for fr in x.children(cell, "draw:frame"):
            im := rd.image(fr)
            if im != null:
                try:
                    si := ws.add_image(im[0], u.cell_ref(r, c), odf.length(im[1]), odf.length(im[2]))
                    si.name = im[3]
                catch e:
                    continue
        c = c + rep

func _read_settings(pkg, wb):
    st := pkg.settings()
    if st == null:
        return null
    for m in x.find_all(st, "config:config-item-map-named"):
        if x.attr(m, "config:name", "") != "Tables":
            continue
        for entry in x.children(m, "config:config-item-map-entry"):
            name := x.attr(entry, "config:name", "")
            if not wb.has_sheet(name):
                continue
            ws := wb.sheet(name)
            vals := {}
            for it in x.children(entry, "config:config-item"):
                vals[x.attr(it, "config:name", "")] = x.text(it)
            hm := u.get(vals, "HorizontalSplitMode", "0")
            vm := u.get(vals, "VerticalSplitMode", "0")
            if hm == "2" or vm == "2":
                col := to_int(_n.num_parse(u.get(vals, "HorizontalSplitPosition", "0"))) if hm == "2" else 0
                row := to_int(_n.num_parse(u.get(vals, "VerticalSplitPosition", "0"))) if vm == "2" else 0
                if col > 0 or row > 0:
                    ws.freeze(u.cell_ref(row + 1, col + 1))
            if u.get(vals, "ShowGrid", "true") == "false":
                ws.show_grid = false
    for it in x.find_all(st, "config:config-item"):
        if x.attr(it, "config:name", "") == "ActiveTable":
            nm := x.text(it)
            k := 0
            for ws in wb.sheets:
                if ws.name == nm:
                    wb.active = k
                k = k + 1

# "Feuil1.A1:Feuil1.D10" / "$Feuil1.$A$1:.$B$2" -> [feuille, "A1:D10"]
func _parse_address(addr):
    parts := _split_colon(addr)
    a := _of_part(parts[0])
    if len(parts) == 1:
        return [a[0], string.replace(a[1], "$", "")]
    b := _of_part(parts[1])
    return [a[0], string.replace(a[1], "$", "") + ":" + string.replace(b[1], "$", "")]

func read(src, calculate=false):
    pkg := src if isinstance(src, odf.OdfPackage) else odf.open(src)
    root := pkg.content()
    if root == null:
        errors.fail(errors.ODF, "content.xml absent")
    body := x.first(root, "office:body")
    sheet_el := x.first(body, "office:spreadsheet") if body != null else null
    if sheet_el == null:
        errors.fail(errors.ODF, "pas un classeur OpenDocument (office:spreadsheet absent)")
    idx := odf.StyleIndex([pkg.styles(), root])
    rd := _Reader(pkg, idx)
    wb := excel.Workbook(null)
    wb.sheets = []
    wb.metadata = pkg.metadata
    for t in x.children(sheet_el, "table:table"):
        _read_sheet(rd, t, wb)
    if len(wb.sheets) == 0:
        wb.add_sheet("Feuil1")
    ne := x.first(sheet_el, "table:named-expressions")
    if ne != null:
        for nr in x.children(ne):
            nm := x.attr(nr, "table:name", null)
            if nm == null:
                continue
            if x.local_name(nr["tag"]) == "named-range":
                pa := _parse_address(x.attr(nr, "table:cell-range-address", ""))
                if pa[0] != null:
                    wb.defined_names[nm] = u.quote_sheet(pa[0]) + "!" + _abs(pa[1])
            else:
                wb.defined_names[nm] = from_openformula(x.attr(nr, "table:expression", ""))
    dbr := x.first(sheet_el, "table:database-ranges")
    if dbr != null:
        for d in x.children(dbr, "table:database-range"):
            if x.attr(d, "table:display-filter-buttons", "false") == "true":
                pa := _parse_address(x.attr(d, "table:target-range-address", ""))
                if pa[0] != null and wb.has_sheet(pa[0]):
                    wb.sheet(pa[0]).auto_filter = pa[1]
    _read_settings(pkg, wb)
    if calculate:
        wb.calculate()
    return wb

func _abs(rng):
    out := []
    for part in string.split(rng, ":"):
        p := u.parse_cell(part)
        append(out, u.cell_ref(p["row"], p["col"], true, true))
    return string.join(":", out)

func read_rows(src, sheet=null):
    wb := read(src)
    ws := wb.sheets[0] if sheet == null else wb.sheet(sheet)
    return ws.to_rows()
