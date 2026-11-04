# ALEX STANDARD LIBRARY — office.xlsx_formulas
# Formules de tableur : analyse (syntaxe Excel), évaluation (plus de 120 fonctions), décalage des références
# (formules partagées, recopie), extraction des dépendances. Les erreurs de calcul sont des VALEURS
# (xlsx_cells.ErrorValue : #DIV/0!, #N/A, #VALUE!, #REF!, #NAME?, #NUM!) ; une formule mal écrite lève FormulaError.
#
#   use office.xlsx_formulas as f
#   f.evaluate("SUM(A1:A3)*2", resolver)            # resolver : objet fournissant les valeurs des cellules
#   f.evaluate("ROUND(3.14159; 2)")                 # 3.14   (« ; » accepté comme séparateur, à la française)
#   f.shift_formula("A1+$B$1+C$2", 2, 1)            # "B3+$B$1+D$2"
#   f.references("SUM(Feuil2!A1:B2)+C3")            # [{"sheet": "Feuil2", "r1": 1, "c1": 1, "r2": 2, "c2": 2}, ...]
#   f.functions()                                   # noms des fonctions disponibles
#
# parse(formule) -> AST   evaluate(formule_ou_ast, resolver=null, sheet=null)   shift_formula(f, drow, dcol)
# references(f) -> plages référencées   tokenize(f) -> jetons   functions() -> noms   register(nom, fn)
#   (fn reçoit la liste des arguments évalués : scalaires ou Range ; renvoie une valeur)
# resolver : resolver.value(feuille, ligne, col) -> valeur (feuille null = feuille courante)
#   resolver.bounds(feuille) -> [max_ligne, max_col] (plages de colonnes entières)   resolver.name(nom) -> formule ou null
# Range : sheet r1 c1 r2 c2 rows (valeurs 2D)  values() (à plat)  width()  height()
# Opérateurs : + - * / ^ & = <> < > <= >= % ; unaires - + ; plages A1:B2, A:A, 1:1 ; feuilles Feuille!A1, 'Nom long'!A1 ;
#   constantes {1,2;3,4} ; TRUE / FALSE / VRAI / FAUX.
# Fonctions : mathématiques (SUM SUMPRODUCT PRODUCT ROUND ROUNDUP ROUNDDOWN INT TRUNC MOD POWER SQRT EXP LN LOG
#   LOG10 ABS SIGN PI CEILING FLOOR MROUND QUOTIENT GCD LCM FACT EVEN ODD RAND RANDBETWEEN SIN COS TAN ATAN2...),
#   statistiques (AVERAGE AVERAGEA MIN MAX MEDIAN MODE COUNT COUNTA COUNTBLANK STDEV STDEVP VAR VARP LARGE SMALL RANK
#   PERCENTILE QUARTILE CORREL), conditionnelles (SUMIF SUMIFS COUNTIF COUNTIFS AVERAGEIF AVERAGEIFS MAXIFS MINIFS),
#   logiques (IF IFS AND OR NOT XOR IFERROR IFNA SWITCH CHOOSE TRUE FALSE), informations (ISBLANK ISNUMBER ISTEXT
#   ISERROR ISERR ISNA ISLOGICAL ISEVEN ISODD NA N), texte (CONCATENATE CONCAT TEXTJOIN LEN LEFT RIGHT MID UPPER LOWER
#   PROPER TRIM SUBSTITUTE REPLACE FIND SEARCH REPT TEXT VALUE EXACT CHAR CODE T FIXED DOLLAR CLEAN), recherche
#   (VLOOKUP HLOOKUP XLOOKUP LOOKUP INDEX MATCH XMATCH ROW COLUMN ROWS COLUMNS OFFSET? non), dates (DATE TIME YEAR MONTH
#   DAY HOUR MINUTE SECOND TODAY NOW WEEKDAY WEEKNUM EDATE EOMONTH DATEDIF DAYS NETWORKDAYS WORKDAY DATEVALUE),
#   finances (PMT IPMT PPMT FV PV NPV IRR NPER RATE).
#   Les noms français courants sont acceptés (SOMME MOYENNE SI NB NB.SI SOMME.SI RECHERCHEV ARRONDI CONCATENER...).
# Erreurs : FormulaError (syntaxe), les erreurs de calcul sont renvoyées comme ErrorValue.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use math
use random
use time
use office.errors as errors
use office.utils as u
use office.xlsx_cells as xc

# ============================================================================================== jetons

func _fail(msg):
    raise("FormulaError", msg)

func _is_letter(ch):
    o := string.ord(ch)
    return (o >= 65 and o <= 90) or (o >= 97 and o <= 122) or o == 95 or o > 127

func _is_digit(ch):
    o := string.ord(ch)
    return o >= 48 and o <= 57

func _is_name_char(ch):
    return _is_letter(ch) or _is_digit(ch) or ch == "." or ch == "_" or ch == "\\"

# Analyse une référence (sans feuille) "A1", "$A$1", "A1:B2", "A:B", "1:3" -> dict ou null.
func _ref_body(s):
    parts := string.split(s, ":")
    if len(parts) > 2:
        return null
    a := null
    try:
        a = u.parse_cell(parts[0])
    catch e:
        return null
    b := a
    if len(parts) == 2:
        try:
            b = u.parse_cell(parts[1])
        catch e:
            return null
    if len(parts) == 1 and (a["row"] == null or a["col"] == null):
        return null
    if (a["row"] == null) != (b["row"] == null) or (a["col"] == null) != (b["col"] == null):
        return null
    if a["col"] != null and (a["col"] > xc.MAX_COL or b["col"] > xc.MAX_COL):
        return null
    if a["row"] != null and (a["row"] > xc.MAX_ROW or b["row"] > xc.MAX_ROW):
        return null
    return {"a": a, "b": b, "range": len(parts) == 2}

# Jetons : [type, valeur, texte_brut] ; types : num str bool err ref name func op lp rp sep lb rb semi
func tokenize(formula):
    f := xc.normalize_formula(formula)
    if f == null:
        _fail("formule vide")
    cs := u.chars(f)
    n := len(cs)
    toks := []
    i := 0
    while i < n:
        c := cs[i]
        if c == " " or c == "\n" or c == "\t" or c == "\r":
            i = i + 1
            continue
        if c == "\"":
            j := i + 1
            buf := []
            while true:
                if j >= n:
                    _fail("chaîne non terminée dans la formule")
                if cs[j] == "\"":
                    if j + 1 < n and cs[j + 1] == "\"":
                        append(buf, "\"")
                        j = j + 2
                        continue
                    break
                append(buf, cs[j])
                j = j + 1
            s := string.join("", buf)
            append(toks, ["str", s, _n.str_slice(f, i, j + 1)])
            i = j + 1
            continue
        if c == "#":
            found := null
            for e in xc.ERRORS:
                if string.upper(_n.str_slice(f, i, i + len(e))) == e:
                    found = e
                    break
            if found == null:
                _fail("valeur d'erreur inconnue à la position " + str(i + 1))
            append(toks, ["err", found, found])
            i = i + len(found)
            continue
        if _is_digit(c) or (c == "." and i + 1 < n and _is_digit(cs[i + 1])):
            j := i
            while j < n and (_is_digit(cs[j]) or cs[j] == "."):
                j = j + 1
            # plage de lignes « 1:3 »
            if j < n and cs[j] == ":" and not string.contains(_n.str_slice(f, i, j), "."):
                k := j + 1
                if k < n and cs[k] == "$":
                    k = k + 1
                m := k
                while m < n and _is_digit(cs[m]):
                    m = m + 1
                if m > k:
                    body := _n.str_slice(f, i, m)
                    rb := _ref_body(body)
                    if rb != null:
                        append(toks, ["ref", {"sheet": null, "body": rb}, body])
                        i = m
                        continue
            if j < n and (cs[j] == "e" or cs[j] == "E") and j + 1 < n and (_is_digit(cs[j + 1]) or ((cs[j + 1] == "+" or cs[j + 1] == "-") and j + 2 < n and _is_digit(cs[j + 2]))):
                j = j + 2
                while j < n and _is_digit(cs[j]):
                    j = j + 1
            raw := _n.str_slice(f, i, j)
            v := _n.num_parse(raw)
            if v == null:
                _fail("nombre invalide '" + raw + "'")
            append(toks, ["num", v, raw])
            i = j
            continue
        if c == "'" or c == "$" or _is_letter(c):
            start := i
            sheet := null
            if c == "'":
                j := i + 1
                buf := []
                while true:
                    if j >= n:
                        _fail("nom de feuille non terminé")
                    if cs[j] == "'":
                        if j + 1 < n and cs[j + 1] == "'":
                            append(buf, "'")
                            j = j + 2
                            continue
                        break
                    append(buf, cs[j])
                    j = j + 1
                if j + 1 >= n or cs[j + 1] != "!":
                    _fail("'!' attendu après le nom de feuille")
                sheet = string.join("", buf)
                i = j + 2
            j := i
            while j < n and (_is_name_char(cs[j]) or cs[j] == "$"):
                j = j + 1
            word := _n.str_slice(f, i, j)
            if sheet == null and j < n and cs[j] == "!":
                sheet = word
                i = j + 1
                j = i
                while j < n and (_is_name_char(cs[j]) or cs[j] == "$"):
                    j = j + 1
                word = _n.str_slice(f, i, j)
            # plage : mot suivi de « : »
            if j < n and cs[j] == ":":
                k := j + 1
                while k < n and (_is_name_char(cs[k]) or cs[k] == "$"):
                    k = k + 1
                cand := _n.str_slice(f, i, k)
                rb := _ref_body(cand)
                if rb != null:
                    append(toks, ["ref", {"sheet": sheet, "body": rb}, _n.str_slice(f, start, k)])
                    i = k
                    continue
            if sheet == null and j < n and cs[j] == "(":
                append(toks, ["func", string.upper(word), word])
                i = j
                continue
            up := string.upper(word)
            if sheet == null and (up == "TRUE" or up == "VRAI"):
                append(toks, ["bool", true, word])
                i = j
                continue
            if sheet == null and (up == "FALSE" or up == "FAUX"):
                append(toks, ["bool", false, word])
                i = j
                continue
            rb := _ref_body(word)
            if rb != null:
                append(toks, ["ref", {"sheet": sheet, "body": rb}, _n.str_slice(f, start, j)])
            else:
                if sheet != null:
                    _fail("référence invalide '" + _n.str_slice(f, start, j) + "'")
                append(toks, ["name", word, word])
            i = j
            continue
        two := _n.str_slice(f, i, i + 2)
        if two == "<>" or two == "<=" or two == ">=":
            append(toks, ["op", two, two])
            i = i + 2
            continue
        if c == "+" or c == "-" or c == "*" or c == "/" or c == "^" or c == "&" or c == "=" or c == "<" or c == ">" or c == "%":
            append(toks, ["op", c, c])
        elif c == "(":
            append(toks, ["lp", c, c])
        elif c == ")":
            append(toks, ["rp", c, c])
        elif c == "," or c == ";":
            append(toks, ["sep", c, c])
        elif c == "{":
            append(toks, ["lb", c, c])
        elif c == "}":
            append(toks, ["rb", c, c])
        elif c == "@":
            i = i + 1
            continue
        else:
            _fail("caractère inattendu '" + c + "' à la position " + str(i + 1))
        i = i + 1
    return toks

# ============================================================================================== analyse

class _Parser:
    func init(toks):
        self.toks = toks
        self.i = 0
        self.in_array = false

    func peek():
        if self.i < len(self.toks):
            return self.toks[self.i]
        return null

    func next():
        t := self.peek()
        self.i = self.i + 1
        return t

    func expect(kind):
        t := self.next()
        if t == null or t[0] != kind:
            _fail("jeton '" + kind + "' attendu" + ("" if t == null else " (obtenu '" + u.to_text(t[2]) + "')"))
        return t

    func is_op(vals):
        t := self.peek()
        if t == null or t[0] != "op":
            return false
        for v in vals:
            if t[1] == v:
                return true
        return false

    func comparison():
        a := self.concat()
        while self.is_op(["=", "<>", "<", ">", "<=", ">="]):
            op := self.next()[1]
            b := self.concat()
            a = ["bin", op, a, b]
        return a

    func concat():
        a := self.additive()
        while self.is_op(["&"]):
            self.next()
            b := self.additive()
            a = ["bin", "&", a, b]
        return a

    func additive():
        a := self.mult()
        while self.is_op(["+", "-"]):
            op := self.next()[1]
            b := self.mult()
            a = ["bin", op, a, b]
        return a

    func mult():
        a := self.power()
        while self.is_op(["*", "/"]):
            op := self.next()[1]
            b := self.power()
            a = ["bin", op, a, b]
        return a

    func power():
        a := self.postfix()
        while self.is_op(["^"]):
            self.next()
            b := self.postfix()
            a = ["bin", "^", a, b]
        return a

    func postfix():
        a := self.unary()
        while self.is_op(["%"]):
            self.next()
            a = ["pct", a]
        return a

    func unary():
        if self.is_op(["-"]):
            self.next()
            return ["neg", self.unary()]
        if self.is_op(["+"]):
            self.next()
            return self.unary()
        return self.primary()

    func primary():
        t := self.next()
        if t == null:
            _fail("expression incomplète")
        k := t[0]
        if k == "num":
            return ["num", t[1]]
        if k == "str":
            return ["str", t[1]]
        if k == "bool":
            return ["bool", t[1]]
        if k == "err":
            return ["err", t[1]]
        if k == "ref":
            rb := t[1]["body"]
            a := rb["a"]
            b := rb["b"]
            if rb["range"]:
                return ["range", t[1]["sheet"], a["row"], a["col"], b["row"], b["col"]]
            return ["ref", t[1]["sheet"], a["row"], a["col"]]
        if k == "name":
            return ["name", t[1]]
        if k == "func":
            name := t[1]
            self.expect("lp")
            args := []
            if self.peek() != null and self.peek()[0] == "rp":
                self.next()
                return ["call", name, args]
            while true:
                pk := self.peek()
                if pk != null and (pk[0] == "sep" or pk[0] == "rp"):
                    append(args, ["missing"])
                else:
                    append(args, self.comparison())
                t2 := self.next()
                if t2 == null:
                    _fail("')' manquante après les arguments de " + name)
                if t2[0] == "rp":
                    break
                if t2[0] != "sep":
                    _fail("',' ou ')' attendu dans les arguments de " + name)
            return ["call", name, args]
        if k == "lp":
            e := self.comparison()
            self.expect("rp")
            return e
        if k == "lb":
            rows := []
            row := []
            while true:
                neg := false
                if self.is_op(["-"]):
                    self.next()
                    neg = true
                v := self.next()
                if v == null:
                    _fail("constante matricielle non terminée")
                val := null
                if v[0] == "num":
                    val = -v[1] if neg else v[1]
                elif v[0] == "str" or v[0] == "bool":
                    val = v[1]
                elif v[0] == "err":
                    val = xc.ErrorValue(v[1])
                else:
                    _fail("valeur constante attendue dans { }")
                append(row, val)
                sep := self.next()
                if sep == null:
                    _fail("constante matricielle non terminée")
                if sep[0] == "rb":
                    append(rows, row)
                    break
                if sep[0] == "sep" and sep[1] == ";":
                    append(rows, row)
                    row = []
                elif sep[0] != "sep":
                    _fail("séparateur attendu dans { }")
            return ["array", rows]
        _fail("jeton inattendu '" + u.to_text(t[2]) + "'")

func parse(formula):
    toks := tokenize(formula)
    p := _Parser(toks)
    ast := p.comparison()
    if p.peek() != null:
        _fail("texte inattendu '" + u.to_text(p.peek()[2]) + "' dans la formule")
    return ast

# ============================================================================================== références

func shift_formula(formula, drow, dcol):
    toks := tokenize(formula)
    out := []
    for t in toks:
        if t[0] != "ref":
            if t[0] == "str":
                append(out, t[2])
            elif t[0] == "func":
                append(out, t[2] + "")
            else:
                append(out, u.to_text(t[2]))
            continue
        info := t[1]
        rb := info["body"]
        parts := []
        for p in [rb["a"], rb["b"]] if rb["range"] else [rb["a"]]:
            s := ""
            if p["col"] != null:
                c := p["col"] if p["abs_col"] else p["col"] + dcol
                if c < 1 or c > xc.MAX_COL:
                    return "#REF!"
                s = ("$" if p["abs_col"] else "") + u.column_letter(c)
            if p["row"] != null:
                r := p["row"] if p["abs_row"] else p["row"] + drow
                if r < 1 or r > xc.MAX_ROW:
                    return "#REF!"
                s = s + ("$" if p["abs_row"] else "") + str(r)
            append(parts, s)
        prefix := ""
        if info["sheet"] != null:
            prefix = u.quote_sheet(info["sheet"]) + "!"
        append(out, prefix + string.join(":", parts))
    # recolle en respectant les espaces d'origine minimalement : les jetons sont concaténés
    return string.join("", out)

func _collect_refs(ast, out):
    k := ast[0]
    if k == "ref":
        append(out, {"sheet": ast[1], "r1": ast[2], "c1": ast[3], "r2": ast[2], "c2": ast[3]})
    elif k == "range":
        append(out, {"sheet": ast[1], "r1": ast[2], "c1": ast[3], "r2": ast[4], "c2": ast[5]})
    elif k == "bin":
        _collect_refs(ast[2], out)
        _collect_refs(ast[3], out)
    elif k == "neg" or k == "pct":
        _collect_refs(ast[1], out)
    elif k == "call":
        for a in ast[2]:
            _collect_refs(a, out)

func references(formula):
    out := []
    _collect_refs(parse(formula), out)
    return out

# ============================================================================================== valeurs

class Range:
    func init(sheet, r1, c1, r2, c2, rows):
        self.sheet = sheet
        self.r1 = r1
        self.c1 = c1
        self.r2 = r2
        self.c2 = c2
        self.rows = rows

    func height():
        return len(self.rows)

    func width():
        return len(self.rows[0]) if len(self.rows) > 0 else 0

    func values():
        out := []
        for r in self.rows:
            for v in r:
                append(out, v)
        return out

    func at(i, j):
        if i < 0 or i >= len(self.rows) or j < 0 or j >= len(self.rows[i]):
            return xc.ErrorValue("#REF!")
        return self.rows[i][j]

func _err(code):
    return xc.ErrorValue(code)

func _is_err(v):
    return isinstance(v, xc.ErrorValue)

func _is_range(v):
    return isinstance(v, Range)

func _is_num(v):
    t := type(v)
    return t == "int" or t == "float"

func _scalar(v):
    if _is_range(v):
        if v.height() == 1 and v.width() == 1:
            return v.rows[0][0]
        if v.height() >= 1 and v.width() >= 1:
            return v.rows[0][0]
        return _err("#VALUE!")
    if type(v) == "list":
        if len(v) > 0 and type(v[0]) == "list" and len(v[0]) > 0:
            return v[0][0]
        return _err("#VALUE!")
    return v

func _num(v):
    s := _scalar(v)
    if u.is_date_dict(s):
        return xc.coerce_number(s)
    return xc.coerce_number(s)

func _text(v):
    s := _scalar(v)
    if s == null:
        return ""
    if type(s) == "bool":
        return "TRUE" if s else "FALSE"
    if _is_err(s):
        return s
    if u.is_date_dict(s):
        return u.to_text(xc.coerce_number(s))
    return u.to_text(s)

func _bool(v):
    s := _scalar(v)
    t := type(s)
    if t == "bool":
        return s
    if s == null:
        return false
    if t == "int" or t == "float":
        return s != 0
    if t == "str":
        up := string.upper(s)
        if up == "TRUE" or up == "VRAI":
            return true
        if up == "FALSE" or up == "FAUX":
            return false
        return _err("#VALUE!")
    if _is_err(s):
        return s
    return _err("#VALUE!")

func _int_if_whole(x):
    if type(x) == "float" and x == to_float(to_int(x)) and x < 1000000000000000.0 and x > -1000000000000000.0:
        return to_int(x)
    return x

# Valeurs à plat des arguments (plages développées ; textes et booléens des plages ignorés pour les fonctions
# numériques, comme Excel ; ceux saisis directement sont convertis).
func _numbers(args, strict_errors=true):
    out := []
    for a in args:
        if _is_range(a) or type(a) == "list":
            vals := a.values() if _is_range(a) else _flat(a)
            for v in vals:
                if _is_err(v):
                    if strict_errors:
                        return v
                    continue
                if _is_num(v):
                    append(out, v)
                elif u.is_date_dict(v):
                    append(out, xc.coerce_number(v))
        else:
            if a == null:
                continue
            if _is_err(a):
                return a
            n := xc.coerce_number(a)
            if _is_err(n):
                return n
            append(out, n)
    return out

func _flat(l):
    out := []
    for r in l:
        if type(r) == "list":
            for v in r:
                append(out, v)
        else:
            append(out, r)
    return out

func _all_values(args):
    out := []
    for a in args:
        if _is_range(a):
            for v in a.values():
                append(out, v)
        elif type(a) == "list":
            for v in _flat(a):
                append(out, v)
        else:
            append(out, a)
    return out

# ============================================================================================== comparaison

func _type_rank(v):
    t := type(v)
    if t == "int" or t == "float":
        return 1
    if t == "str":
        return 2
    if t == "bool":
        return 3
    return 0

# -1, 0, 1 selon l'ordre d'Excel (nombres < textes < booléens ; textes sans casse ; vide = 0 ou "").
func compare(a, b):
    if u.is_date_dict(a):
        a = xc.coerce_number(a)
    if u.is_date_dict(b):
        b = xc.coerce_number(b)
    if a == null:
        a = "" if type(b) == "str" else (false if type(b) == "bool" else 0)
    if b == null:
        b = "" if type(a) == "str" else (false if type(a) == "bool" else 0)
    ra := _type_rank(a)
    rb := _type_rank(b)
    if ra != rb:
        return -1 if ra < rb else 1
    if ra == 2:
        la := string.lower(a)
        lb := string.lower(b)
        if la < lb:
            return -1
        if la > lb:
            return 1
        return 0
    if ra == 3:
        ia := 1 if a else 0
        ib := 1 if b else 0
        return -1 if ia < ib else (1 if ia > ib else 0)
    if a < b:
        return -1
    if a > b:
        return 1
    return 0

# ============================================================================================== critères (*IF)

func _wild_match(pat, s):
    p := u.chars(string.lower(pat))
    t := u.chars(string.lower(s))
    return _wm(p, 0, t, 0)

func _wm(p, i, t, j):
    while i < len(p):
        c := p[i]
        if c == "~" and i + 1 < len(p):
            if j >= len(t) or t[j] != p[i + 1]:
                return false
            i = i + 2
            j = j + 1
            continue
        if c == "*":
            while i < len(p) and p[i] == "*":
                i = i + 1
            if i == len(p):
                return true
            k := j
            while k <= len(t):
                if _wm(p, i, t, k):
                    return true
                k = k + 1
            return false
        if j >= len(t):
            return false
        if c != "?" and c != t[j]:
            return false
        i = i + 1
        j = j + 1
    return j == len(t)

# Fonction de test pour un critère Excel (">5", "<>abc", "=", "a*", 12, TRUE...).
func criterion(crit):
    c := _scalar(crit)
    if type(c) != "str":
        return (v) => compare(v, c) == 0 and _type_rank(v if v != null else 0) == _type_rank(c) if not u.is_date_dict(v) else compare(v, c) == 0
    op := "="
    rest := c
    for o in ["<>", ">=", "<=", "=", ">", "<"]:
        if string.starts_with(c, o):
            op = o
            rest = _n.str_slice(c, len(o), null)
            break
    num := _n.num_parse(rest)
    has_wild := string.contains(rest, "*") or string.contains(rest, "?")
    return _Criterion(op, rest, num, has_wild).test

class _Criterion:
    func init(op, rest, num, wild):
        self.op = op
        self.rest = rest
        self.num = num
        self.wild = wild

    func test(v):
        op := self.op
        r := 0
        if u.is_date_dict(v):
            v = xc.coerce_number(v)
        if self.num != null and (op != "=" and op != "<>" or _is_num(v)):
            if not _is_num(v):
                return op == "<>"
            r = compare(v, self.num)
        elif self.rest == "" and (op == "=" or op == "<>"):
            empty := v == null or v == ""
            return empty if op == "=" else not empty
        else:
            if op == "=" or op == "<>":
                if v == null or _is_num(v) or type(v) == "bool":
                    if type(v) == "bool":
                        up := string.upper(self.rest)
                        eqb := (up == "TRUE" and v) or (up == "FALSE" and not v)
                        return eqb if op == "=" else not eqb
                    return op == "<>"
                m := _wild_match(self.rest, v) if self.wild else string.lower(v) == string.lower(self.rest)
                return m if op == "=" else not m
            if type(v) != "str":
                return false
            r = compare(v, self.rest)
        if op == "=":
            return r == 0
        if op == "<>":
            return r != 0
        if op == ">":
            return r > 0
        if op == "<":
            return r < 0
        if op == ">=":
            return r >= 0
        return r <= 0

# ============================================================================================== évaluateur

class _NullResolver:
    func value(sheet, r, c):
        return null

    func bounds(sheet):
        return [0, 0]

    func name(n):
        return null

class Evaluator:
    func init(resolver, sheet):
        self.resolver = resolver if resolver != null else _NullResolver()
        self.sheet = sheet
        self.depth = 0

    func ev(ast):
        k := ast[0]
        if k == "num" or k == "str" or k == "bool":
            return ast[1]
        if k == "err":
            return xc.ErrorValue(ast[1])
        if k == "missing":
            return null
        if k == "ref":
            v := self.resolver.value(ast[1], ast[2], ast[3])
            return v
        if k == "range":
            return self.range(ast)
        if k == "name":
            f := self.resolver.name(ast[1])
            if f == null:
                return xc.ErrorValue("#NAME?")
            self.depth = self.depth + 1
            if self.depth > 64:
                return xc.ErrorValue("#REF!")
            r := self.ev(parse(f))
            self.depth = self.depth - 1
            return r
        if k == "array":
            return Range(null, 0, 0, len(ast[1]) - 1, len(ast[1][0]) - 1 if len(ast[1]) > 0 else 0, ast[1])
        if k == "neg":
            v := _num(self.ev(ast[1]))
            if _is_err(v):
                return v
            return -v
        if k == "pct":
            v := _num(self.ev(ast[1]))
            if _is_err(v):
                return v
            return to_float(v) / 100.0
        if k == "bin":
            return self.binop(ast[1], self.ev(ast[2]), self.ev(ast[3]))
        if k == "call":
            return self.call(ast[1], ast[2])
        return xc.ErrorValue("#VALUE!")

    func range(ast):
        sheet := ast[1]
        r1 := ast[2]
        c1 := ast[3]
        r2 := ast[4]
        c2 := ast[5]
        if r1 == null or c1 == null:
            b := self.resolver.bounds(sheet)
            if r1 == null:
                r1 = 1
                r2 = b[0] if b[0] > 0 else 1
            if c1 == null:
                c1 = 1
                c2 = b[1] if b[1] > 0 else 1
        if (r2 - r1 + 1) * (c2 - c1 + 1) > 5000000:
            return xc.ErrorValue("#NUM!")
        rows := []
        r := r1
        while r <= r2:
            line := []
            c := c1
            while c <= c2:
                append(line, self.resolver.value(sheet, r, c))
                c = c + 1
            append(rows, line)
            r = r + 1
        return Range(sheet, r1, c1, r2, c2, rows)

    func binop(op, a, b):
        if op == "&":
            ta := _text(a)
            if _is_err(ta):
                return ta
            tb := _text(b)
            if _is_err(tb):
                return tb
            return ta + tb
        if op == "=" or op == "<>" or op == "<" or op == ">" or op == "<=" or op == ">=":
            sa := _scalar(a)
            sb := _scalar(b)
            if _is_err(sa):
                return sa
            if _is_err(sb):
                return sb
            r := compare(sa, sb)
            if op == "=":
                return r == 0
            if op == "<>":
                return r != 0
            if op == "<":
                return r < 0
            if op == ">":
                return r > 0
            if op == "<=":
                return r <= 0
            return r >= 0
        x1 := _num(a)
        if _is_err(x1):
            return x1
        x2 := _num(b)
        if _is_err(x2):
            return x2
        if op == "+":
            return x1 + x2
        if op == "-":
            return x1 - x2
        if op == "*":
            return x1 * x2
        if op == "/":
            if x2 == 0:
                return xc.ErrorValue("#DIV/0!")
            r := to_float(x1) / to_float(x2)
            return _int_if_whole(r) if type(x1) == "int" and type(x2) == "int" else r
        if op == "^":
            if x1 == 0 and x2 < 0:
                return xc.ErrorValue("#DIV/0!")
            if x1 < 0 and x2 != to_float(to_int(x2)):
                return xc.ErrorValue("#NUM!")
            if type(x1) == "int" and type(x2) == "int" and x2 >= 0:
                return x1 ** x2
            return to_float(x1) ** to_float(x2)
        return xc.ErrorValue("#VALUE!")

    func call(name, args):
        fname := _alias(name)
        if string.starts_with(fname, "_XLFN."):
            fname = _n.str_slice(fname, 6, null)
        if string.starts_with(fname, "_XLWS."):
            fname = _n.str_slice(fname, 6, null)
        lazy := _lazy(self, fname, args)
        if lazy != _NOT_LAZY:
            return lazy
        if not contains_key(_FUNCS, fname):
            return xc.ErrorValue("#NAME?")
        vals := []
        for a in args:
            append(vals, self.ev(a))
        try:
            return _FUNCS[fname](vals)
        catch e:
            if e.type == "ZeroDivisionError":
                return xc.ErrorValue("#DIV/0!")
            if e.type == "IndexError" or e.type == "KeyError":
                return xc.ErrorValue("#REF!")
            if e.type == "ValueError" or e.type == "TypeError":
                return xc.ErrorValue("#VALUE!")
            raise(e)

const _NOT_LAZY := "\u0000notlazy"

# Fonctions à évaluation paresseuse (seule la branche utile est calculée).
func _lazy(ev, name, args):
    if name == "IF":
        if len(args) < 2 or len(args) > 3:
            return xc.ErrorValue("#VALUE!")
        c := _bool(ev.ev(args[0]))
        if _is_err(c):
            return c
        if c:
            v := ev.ev(args[1])
            return 0 if v == null and args[1][0] == "missing" else v
        if len(args) == 3:
            v := ev.ev(args[2])
            return 0 if v == null and args[2][0] == "missing" else v
        return false
    if name == "IFERROR" or name == "IFNA":
        if len(args) != 2:
            return xc.ErrorValue("#VALUE!")
        v := _scalar(ev.ev(args[0]))
        if _is_err(v) and (name == "IFERROR" or v.code == "#N/A"):
            return ev.ev(args[1])
        return v
    if name == "IFS":
        i := 0
        while i + 1 < len(args):
            c := _bool(ev.ev(args[i]))
            if _is_err(c):
                return c
            if c:
                return ev.ev(args[i + 1])
            i = i + 2
        return xc.ErrorValue("#N/A")
    if name == "AND" or name == "OR" or name == "XOR":
        vals := []
        for a in args:
            append(vals, ev.ev(a))
        acc := null
        count := 0
        for v in _all_values(vals):
            if v == null or type(v) == "str":
                if not _is_range_value(vals, v):
                    b := _bool(v)
                    if _is_err(b):
                        return b
                continue
            b := _bool(v)
            if _is_err(b):
                return b
            count = count + 1
            if acc == null:
                acc = b if name != "XOR" else (1 if b else 0)
            elif name == "AND":
                acc = acc and b
            elif name == "OR":
                acc = acc or b
            else:
                acc = acc + (1 if b else 0)
        if count == 0:
            return xc.ErrorValue("#VALUE!")
        if name == "XOR":
            return acc % 2 == 1
        return acc
    if name == "CHOOSE":
        if len(args) < 2:
            return xc.ErrorValue("#VALUE!")
        k := _num(ev.ev(args[0]))
        if _is_err(k):
            return k
        k = to_int(k)
        if k < 1 or k >= len(args):
            return xc.ErrorValue("#VALUE!")
        return ev.ev(args[k])
    if name == "SWITCH":
        if len(args) < 3:
            return xc.ErrorValue("#VALUE!")
        target := _scalar(ev.ev(args[0]))
        i := 1
        while i + 1 < len(args):
            if compare(target, _scalar(ev.ev(args[i]))) == 0:
                return ev.ev(args[i + 1])
            i = i + 2
        if i < len(args):
            return ev.ev(args[i])
        return xc.ErrorValue("#N/A")
    if name == "ROW" or name == "COLUMN":
        if len(args) == 0:
            return xc.ErrorValue("#VALUE!")
        a := args[0]
        if a[0] == "ref":
            return a[2] if name == "ROW" else a[3]
        if a[0] == "range":
            return a[2] if name == "ROW" else a[3]
        return xc.ErrorValue("#VALUE!")
    if name == "ISBLANK" and len(args) == 1:
        v := _scalar(ev.ev(args[0]))
        return v == null
    if name == "ISREF" and len(args) == 1:
        return args[0][0] == "ref" or args[0][0] == "range"
    return _NOT_LAZY

func _is_range_value(vals, v):
    for a in vals:
        if _is_range(a):
            return true
    return false

# ============================================================================================== bibliothèque

_FUNCS := {}

func register(name, fn):
    _FUNCS[string.upper(name)] = fn

func functions():
    out := ["IF", "IFERROR", "IFNA", "IFS", "AND", "OR", "XOR", "CHOOSE", "SWITCH", "ROW", "COLUMN", "ISBLANK", "ISREF"]
    for k in keys(_FUNCS):
        append(out, k)
    return u.sort(out)

const _FR := {"SOMME": "SUM", "MOYENNE": "AVERAGE", "SI": "IF", "NB": "COUNT", "NBVAL": "COUNTA", "NB.VIDE": "COUNTBLANK", "NB.SI": "COUNTIF", "NB.SI.ENS": "COUNTIFS", "SOMME.SI": "SUMIF", "SOMME.SI.ENS": "SUMIFS", "MOYENNE.SI": "AVERAGEIF", "MOYENNE.SI.ENS": "AVERAGEIFS", "RECHERCHEV": "VLOOKUP", "RECHERCHEH": "HLOOKUP", "RECHERCHEX": "XLOOKUP", "EQUIV": "MATCH", "ARRONDI": "ROUND", "ARRONDI.SUP": "ROUNDUP", "ARRONDI.INF": "ROUNDDOWN", "ENT": "INT", "TRONQUE": "TRUNC", "CONCATENER": "CONCATENATE", "CONCAT": "CONCAT", "GAUCHE": "LEFT", "DROITE": "RIGHT", "STXT": "MID", "NBCAR": "LEN", "MAJUSCULE": "UPPER", "MINUSCULE": "LOWER", "NOMPROPRE": "PROPER", "SUPPRESPACE": "TRIM", "SUBSTITUE": "SUBSTITUTE", "TROUVE": "FIND", "CHERCHE": "SEARCH", "TEXTE": "TEXT", "CNUM": "VALUE", "ET": "AND", "OU": "OR", "NON": "NOT", "SIERREUR": "IFERROR", "SI.NON.DISP": "IFNA", "SI.CONDITIONS": "IFS", "AUJOURDHUI": "TODAY", "MAINTENANT": "NOW", "ANNEE": "YEAR", "MOIS": "MONTH", "JOUR": "DAY", "HEURE": "HOUR", "SECONDE": "SECOND", "JOURSEM": "WEEKDAY", "MOIS.DECALER": "EDATE", "FIN.MOIS": "EOMONTH", "PRODUIT": "PRODUCT", "RACINE": "SQRT", "PUISSANCE": "POWER", "ABS": "ABS", "MEDIANE": "MEDIAN", "ECARTYPE": "STDEV", "ECARTYPEP": "STDEVP", "GRANDE.VALEUR": "LARGE", "PETITE.VALEUR": "SMALL", "RANG": "RANK", "INDEX": "INDEX", "LIGNE": "ROW", "COLONNE": "COLUMN", "LIGNES": "ROWS", "COLONNES": "COLUMNS", "ESTVIDE": "ISBLANK", "ESTNUM": "ISNUMBER", "ESTTEXTE": "ISTEXT", "ESTERREUR": "ISERROR", "ESTNA": "ISNA", "CHOISIR": "CHOOSE", "REPT": "REPT", "EXACT": "EXACT", "CAR": "CHAR", "CODE": "CODE", "JOINDRE.TEXTE": "TEXTJOIN", "VPM": "PMT", "VA": "PV", "VC": "FV", "VAN": "NPV", "TRI": "IRR", "MAX.SI.ENS": "MAXIFS", "MIN.SI.ENS": "MINIFS", "SOMMEPROD": "SUMPRODUCT", "MOD": "MOD", "PLAFOND": "CEILING", "PLANCHER": "FLOOR", "ALEA": "RAND", "ALEA.ENTRE.BORNES": "RANDBETWEEN", "DATEDIF": "DATEDIF", "JOURS": "DAYS", "NB.JOURS.OUVRES": "NETWORKDAYS", "SERIE.JOUR.OUVRE": "WORKDAY", "DATEVAL": "DATEVALUE", "TEMPS": "TIME", "NO.SEMAINE": "WEEKNUM", "QUOTIENT": "QUOTIENT", "PGCD": "GCD", "PPCM": "LCM", "FACT": "FACT", "LN": "LN", "LOG": "LOG", "LOG10": "LOG10", "EXP": "EXP", "PI": "PI", "SIGNE": "SIGN", "MODE": "MODE", "VAR": "VAR", "VAR.P": "VARP", "CENTILE": "PERCENTILE", "QUARTILE": "QUARTILE", "COEFFICIENT.CORRELATION": "CORREL", "NBVAL.SI": "COUNTIF", "MAX": "MAX", "MIN": "MIN", "DATE": "DATE", "REMPLACER": "REPLACE", "T": "T", "N": "N", "NA": "NA", "EPURAGE": "CLEAN", "CTXT": "FIXED", "EQUIVX": "XMATCH", "RECHERCHE": "LOOKUP"}

func _alias(name):
    up := string.upper(name)
    if contains_key(_FR, up):
        return _FR[up]
    return up

# ---------------------------------------------------------------------- mathématiques

func _sum(args):
    ns := _numbers(args)
    if _is_err(ns):
        return ns
    s := 0
    for v in ns:
        s = s + v
    return s

func _product(args):
    ns := _numbers(args)
    if _is_err(ns):
        return ns
    if len(ns) == 0:
        return 0
    p := 1
    for v in ns:
        p = p * v
    return p

func _arg_num(args, i, fallback=null):
    if i >= len(args) or args[i] == null:
        if fallback == null:
            return xc.ErrorValue("#VALUE!")
        return fallback
    return _num(args[i])

func _round_impl(args, mode):
    x := _arg_num(args, 0)
    if _is_err(x):
        return x
    d := _arg_num(args, 1, 0)
    if _is_err(d):
        return d
    d = to_int(d)
    f := 10.0 ** to_float(d if d >= 0 else -d)
    v := to_float(x)
    neg := v < 0
    av := -v if neg else v
    scaled := av * f if d >= 0 else av / f
    r := 0.0
    if mode == "round":
        r = to_float(to_int(scaled + 0.5 + 0.000000001))
    elif mode == "up":
        r = to_float(to_int(scaled))
        if scaled - r > 0.0000000001:
            r = r + 1.0
    else:
        r = to_float(to_int(scaled + 0.0000000001))
    res := r / f if d >= 0 else r * f
    if neg:
        res = -res
    return _int_if_whole(res) if d <= 0 else res

func _round(args):
    return _round_impl(args, "round")

func _roundup(args):
    return _round_impl(args, "up")

func _rounddown(args):
    return _round_impl(args, "down")

func _int(args):
    x := _arg_num(args, 0)
    if _is_err(x):
        return x
    return to_int(math.floor(to_float(x)))

func _trunc(args):
    if len(args) > 1:
        return _rounddown(args)
    x := _arg_num(args, 0)
    if _is_err(x):
        return x
    return to_int(x)

func _mod(args):
    a := _arg_num(args, 0)
    b := _arg_num(args, 1)
    if _is_err(a):
        return a
    if _is_err(b):
        return b
    if b == 0:
        return xc.ErrorValue("#DIV/0!")
    if type(a) == "int" and type(b) == "int":
        return a % b
    r := to_float(a) - to_float(b) * math.floor(to_float(a) / to_float(b))
    return r

func _power(args):
    a := _arg_num(args, 0)
    b := _arg_num(args, 1)
    if _is_err(a):
        return a
    if _is_err(b):
        return b
    return Evaluator(null, null).binop("^", a, b)

func _sqrt(args):
    a := _arg_num(args, 0)
    if _is_err(a):
        return a
    if a < 0:
        return xc.ErrorValue("#NUM!")
    return _int_if_whole(to_float(a) ** 0.5) if type(a) == "int" else to_float(a) ** 0.5

func _unary(fn, check=null):
    return _Unary(fn, check).call

class _Unary:
    func init(fn, check):
        self.fn = fn
        self.check = check

    func call(args):
        a := _arg_num(args, 0)
        if _is_err(a):
            return a
        if self.check != null and not self.check(a):
            return xc.ErrorValue("#NUM!")
        r := self.fn(to_float(a))
        if r == null:
            return xc.ErrorValue("#NUM!")
        return r

func _log(args):
    a := _arg_num(args, 0)
    if _is_err(a):
        return a
    b := _arg_num(args, 1, 10)
    if _is_err(b):
        return b
    if a <= 0 or b <= 0 or b == 1:
        return xc.ErrorValue("#NUM!")
    return math.ln(to_float(a)) / math.ln(to_float(b))

func _abs(args):
    a := _arg_num(args, 0)
    if _is_err(a):
        return a
    return -a if a < 0 else a

func _sign(args):
    a := _arg_num(args, 0)
    if _is_err(a):
        return a
    return 1 if a > 0 else (-1 if a < 0 else 0)

func _ceiling(args):
    x := _arg_num(args, 0)
    if _is_err(x):
        return x
    s := _arg_num(args, 1, 1 if x >= 0 else -1)
    if _is_err(s):
        return s
    if s == 0:
        return 0
    if x > 0 and s < 0:
        return xc.ErrorValue("#NUM!")
    q := to_float(x) / to_float(s)
    r := math.ceil(q) if q > 0 else -math.floor(-q)
    if x < 0 and s > 0:
        r = -math.floor(-q)
    return _int_if_whole(to_float(r) * to_float(s))

func _floor(args):
    x := _arg_num(args, 0)
    if _is_err(x):
        return x
    s := _arg_num(args, 1, 1 if x >= 0 else -1)
    if _is_err(s):
        return s
    if s == 0:
        return xc.ErrorValue("#DIV/0!")
    if x > 0 and s < 0:
        return xc.ErrorValue("#NUM!")
    q := to_float(x) / to_float(s)
    r := math.floor(q)
    return _int_if_whole(to_float(r) * to_float(s))

func _mround(args):
    x := _arg_num(args, 0)
    m := _arg_num(args, 1)
    if _is_err(x):
        return x
    if _is_err(m):
        return m
    if m == 0:
        return 0
    if (x > 0 and m < 0) or (x < 0 and m > 0):
        return xc.ErrorValue("#NUM!")
    q := to_float(x) / to_float(m)
    return _int_if_whole(to_float(to_int(q + 0.5 if q >= 0 else q - 0.5)) * to_float(m))

func _quotient(args):
    a := _arg_num(args, 0)
    b := _arg_num(args, 1)
    if _is_err(a):
        return a
    if _is_err(b):
        return b
    if b == 0:
        return xc.ErrorValue("#DIV/0!")
    return to_int(to_float(a) / to_float(b))

func _gcd2(a, b):
    while b != 0:
        t := a % b
        a = b
        b = t
    return a

func _gcd(args):
    ns := _numbers(args)
    if _is_err(ns):
        return ns
    g := 0
    for v in ns:
        if v < 0:
            return xc.ErrorValue("#NUM!")
        g = _gcd2(g, to_int(v))
    return g

func _lcm(args):
    ns := _numbers(args)
    if _is_err(ns):
        return ns
    l := 1
    for v in ns:
        iv := to_int(v)
        if iv < 0:
            return xc.ErrorValue("#NUM!")
        if iv == 0:
            return 0
        l = l * iv // _gcd2(l, iv)
    return l

func _fact(args):
    a := _arg_num(args, 0)
    if _is_err(a):
        return a
    n := to_int(a)
    if n < 0:
        return xc.ErrorValue("#NUM!")
    r := 1
    k := 2
    while k <= n:
        r = r * k
        k = k + 1
    return r

func _even(args):
    a := _arg_num(args, 0)
    if _is_err(a):
        return a
    v := to_float(a)
    s := 1 if v >= 0 else -1
    n := to_int(math.ceil(v if v >= 0 else -v))
    if n % 2 == 1:
        n = n + 1
    return n * s

func _odd(args):
    a := _arg_num(args, 0)
    if _is_err(a):
        return a
    v := to_float(a)
    s := 1 if v >= 0 else -1
    n := to_int(math.ceil(v if v >= 0 else -v))
    if n % 2 == 0:
        n = n + 1
    return n * s

func _rand(args):
    return random.random()

func _randbetween(args):
    a := _arg_num(args, 0)
    b := _arg_num(args, 1)
    if _is_err(a):
        return a
    if _is_err(b):
        return b
    return random.randint(to_int(math.ceil(to_float(a))), to_int(math.floor(to_float(b))))

func _pi(args):
    return math.PI

func _sumproduct(args):
    if len(args) == 0:
        return xc.ErrorValue("#VALUE!")
    arrays := []
    for a in args:
        if _is_range(a):
            append(arrays, a.values())
        else:
            append(arrays, [_scalar(a)])
    n := len(arrays[0])
    for arr in arrays:
        if len(arr) != n:
            return xc.ErrorValue("#VALUE!")
    total := 0
    i := 0
    while i < n:
        p := 1
        for arr in arrays:
            v := arr[i]
            if _is_err(v):
                return v
            p = p * (v if _is_num(v) else 0)
        total = total + p
        i = i + 1
    return total

# ---------------------------------------------------------------------- statistiques

func _average(args):
    ns := _numbers(args)
    if _is_err(ns):
        return ns
    if len(ns) == 0:
        return xc.ErrorValue("#DIV/0!")
    s := 0.0
    for v in ns:
        s = s + to_float(v)
    return _int_if_whole(s / to_float(len(ns)))

func _averagea(args):
    vals := []
    for a in args:
        if _is_range(a):
            for v in a.values():
                if v == null:
                    continue
                if _is_err(v):
                    return v
                append(vals, v if _is_num(v) else (1 if v == true else 0))
        else:
            n := _num(a)
            if _is_err(n):
                return n
            append(vals, n)
    if len(vals) == 0:
        return xc.ErrorValue("#DIV/0!")
    s := 0.0
    for v in vals:
        s = s + to_float(v)
    return s / to_float(len(vals))

func _min(args):
    ns := _numbers(args)
    if _is_err(ns):
        return ns
    if len(ns) == 0:
        return 0
    m := ns[0]
    for v in ns:
        if v < m:
            m = v
    return m

func _max(args):
    ns := _numbers(args)
    if _is_err(ns):
        return ns
    if len(ns) == 0:
        return 0
    m := ns[0]
    for v in ns:
        if v > m:
            m = v
    return m

func _sorted_numbers(args):
    ns := _numbers(args)
    if _is_err(ns):
        return ns
    return u.sort(ns)

func _median(args):
    ns := _sorted_numbers(args)
    if _is_err(ns):
        return ns
    n := len(ns)
    if n == 0:
        return xc.ErrorValue("#NUM!")
    if n % 2 == 1:
        return ns[n // 2]
    return _int_if_whole((to_float(ns[n // 2 - 1]) + to_float(ns[n // 2])) / 2.0)

func _mode(args):
    ns := _numbers(args)
    if _is_err(ns):
        return ns
    counts := {}
    best := null
    best_n := 1
    for v in ns:
        k := u.format_number(v)
        counts[k] = (counts[k] if contains_key(counts, k) else 0) + 1
        if counts[k] > best_n:
            best_n = counts[k]
            best = v
    if best == null:
        return xc.ErrorValue("#N/A")
    return best

func _count(args):
    n := 0
    for a in args:
        if _is_range(a):
            for v in a.values():
                if _is_num(v) or u.is_date_dict(v):
                    n = n + 1
        else:
            if _is_num(a) or u.is_date_dict(a) or type(a) == "bool":
                n = n + 1
            elif type(a) == "str" and _n.num_parse(a) != null:
                n = n + 1
    return n

func _counta(args):
    n := 0
    for a in args:
        if _is_range(a):
            for v in a.values():
                if v != null:
                    n = n + 1
        elif a != null:
            n = n + 1
    return n

func _countblank(args):
    n := 0
    for a in args:
        if _is_range(a):
            for v in a.values():
                if v == null or v == "":
                    n = n + 1
        elif a == null or a == "":
            n = n + 1
    return n

func _variance(args, sample):
    ns := _numbers(args)
    if _is_err(ns):
        return ns
    n := len(ns)
    if n < (2 if sample else 1):
        return xc.ErrorValue("#DIV/0!")
    m := 0.0
    for v in ns:
        m = m + to_float(v)
    m = m / to_float(n)
    s := 0.0
    for v in ns:
        d := to_float(v) - m
        s = s + d * d
    return s / to_float(n - 1 if sample else n)

func _var(args):
    return _variance(args, true)

func _varp(args):
    return _variance(args, false)

func _stdev(args):
    v := _variance(args, true)
    if _is_err(v):
        return v
    return v ** 0.5

func _stdevp(args):
    v := _variance(args, false)
    if _is_err(v):
        return v
    return v ** 0.5

func _large(args):
    ns := _sorted_numbers([args[0]])
    if _is_err(ns):
        return ns
    k := _arg_num(args, 1)
    if _is_err(k):
        return k
    k = to_int(k)
    if k < 1 or k > len(ns):
        return xc.ErrorValue("#NUM!")
    return ns[len(ns) - k]

func _small(args):
    ns := _sorted_numbers([args[0]])
    if _is_err(ns):
        return ns
    k := _arg_num(args, 1)
    if _is_err(k):
        return k
    k = to_int(k)
    if k < 1 or k > len(ns):
        return xc.ErrorValue("#NUM!")
    return ns[k - 1]

func _rank(args):
    x := _arg_num(args, 0)
    if _is_err(x):
        return x
    ns := _numbers([args[1]])
    if _is_err(ns):
        return ns
    asc := len(args) > 2 and args[2] != null and _num(args[2]) != 0
    found := false
    r := 1
    for v in ns:
        if v == x:
            found = true
        if (asc and v < x) or (not asc and v > x):
            r = r + 1
    if not found:
        return xc.ErrorValue("#N/A")
    return r

func _percentile_impl(ns, p):
    n := len(ns)
    if n == 0 or p < 0 or p > 1:
        return xc.ErrorValue("#NUM!")
    pos := to_float(p) * to_float(n - 1)
    lo := to_int(pos)
    frac := pos - to_float(lo)
    if lo + 1 >= n:
        return ns[n - 1]
    return _int_if_whole(to_float(ns[lo]) + frac * (to_float(ns[lo + 1]) - to_float(ns[lo])))

func _percentile(args):
    ns := _sorted_numbers([args[0]])
    if _is_err(ns):
        return ns
    p := _arg_num(args, 1)
    if _is_err(p):
        return p
    return _percentile_impl(ns, p)

func _quartile(args):
    ns := _sorted_numbers([args[0]])
    if _is_err(ns):
        return ns
    q := _arg_num(args, 1)
    if _is_err(q):
        return q
    q = to_int(q)
    if q < 0 or q > 4:
        return xc.ErrorValue("#NUM!")
    return _percentile_impl(ns, to_float(q) / 4.0)

func _correl(args):
    if len(args) != 2 or not _is_range(args[0]) or not _is_range(args[1]):
        return xc.ErrorValue("#VALUE!")
    a := args[0].values()
    b := args[1].values()
    if len(a) != len(b):
        return xc.ErrorValue("#N/A")
    xs := []
    ys := []
    i := 0
    while i < len(a):
        if _is_num(a[i]) and _is_num(b[i]):
            append(xs, to_float(a[i]))
            append(ys, to_float(b[i]))
        i = i + 1
    n := len(xs)
    if n < 2:
        return xc.ErrorValue("#DIV/0!")
    mx := 0.0
    my := 0.0
    for v in xs:
        mx = mx + v
    for v in ys:
        my = my + v
    mx = mx / to_float(n)
    my = my / to_float(n)
    sxy := 0.0
    sxx := 0.0
    syy := 0.0
    i = 0
    while i < n:
        dx := xs[i] - mx
        dy := ys[i] - my
        sxy = sxy + dx * dy
        sxx = sxx + dx * dx
        syy = syy + dy * dy
        i = i + 1
    if sxx == 0 or syy == 0:
        return xc.ErrorValue("#DIV/0!")
    return sxy / ((sxx * syy) ** 0.5)

# ---------------------------------------------------------------------- conditionnelles

func _cells(v):
    if _is_range(v):
        return v.values()
    return [_scalar(v)]

func _sumif(args):
    if len(args) < 2:
        return xc.ErrorValue("#VALUE!")
    crit := _cells(args[0])
    test := criterion(args[1])
    vals := _cells(args[2]) if len(args) > 2 and args[2] != null else crit
    s := 0
    i := 0
    while i < len(crit):
        if test(crit[i]) and i < len(vals) and _is_num(vals[i]):
            s = s + vals[i]
        i = i + 1
    return s

func _countif(args):
    if len(args) != 2:
        return xc.ErrorValue("#VALUE!")
    test := criterion(args[1])
    n := 0
    for v in _cells(args[0]):
        if test(v):
            n = n + 1
    return n

func _averageif(args):
    crit := _cells(args[0])
    test := criterion(args[1])
    vals := _cells(args[2]) if len(args) > 2 and args[2] != null else crit
    s := 0.0
    n := 0
    i := 0
    while i < len(crit):
        if test(crit[i]) and i < len(vals) and _is_num(vals[i]):
            s = s + to_float(vals[i])
            n = n + 1
        i = i + 1
    if n == 0:
        return xc.ErrorValue("#DIV/0!")
    return _int_if_whole(s / to_float(n))

# Indices satisfaisant toutes les paires (plage, critère) à partir de `start`.
func _ifs_mask(args, start):
    if (len(args) - start) % 2 != 0 or len(args) - start < 2:
        return null
    mask := null
    i := start
    while i + 1 < len(args):
        cells := _cells(args[i])
        test := criterion(args[i + 1])
        if mask == null:
            mask = []
            for v in cells:
                append(mask, test(v))
        else:
            if len(cells) != len(mask):
                return null
            k := 0
            while k < len(mask):
                mask[k] = mask[k] and test(cells[k])
                k = k + 1
        i = i + 2
    return mask

func _sumifs(args):
    vals := _cells(args[0])
    mask := _ifs_mask(args, 1)
    if mask == null or len(mask) != len(vals):
        return xc.ErrorValue("#VALUE!")
    s := 0
    i := 0
    while i < len(vals):
        if mask[i] and _is_num(vals[i]):
            s = s + vals[i]
        i = i + 1
    return s

func _countifs(args):
    mask := _ifs_mask(args, 0)
    if mask == null:
        return xc.ErrorValue("#VALUE!")
    n := 0
    for m in mask:
        if m:
            n = n + 1
    return n

func _agg_ifs(args, kind):
    vals := _cells(args[0])
    mask := _ifs_mask(args, 1)
    if mask == null or len(mask) != len(vals):
        return xc.ErrorValue("#VALUE!")
    sel := []
    i := 0
    while i < len(vals):
        if mask[i] and _is_num(vals[i]):
            append(sel, vals[i])
        i = i + 1
    if kind == "avg":
        if len(sel) == 0:
            return xc.ErrorValue("#DIV/0!")
        s := 0.0
        for v in sel:
            s = s + to_float(v)
        return _int_if_whole(s / to_float(len(sel)))
    if len(sel) == 0:
        return 0
    m := sel[0]
    for v in sel:
        if (kind == "max" and v > m) or (kind == "min" and v < m):
            m = v
    return m

func _averageifs(args):
    return _agg_ifs(args, "avg")

func _maxifs(args):
    return _agg_ifs(args, "max")

func _minifs(args):
    return _agg_ifs(args, "min")

# ---------------------------------------------------------------------- logique et informations

func _not(args):
    b := _bool(args[0]) if len(args) == 1 else xc.ErrorValue("#VALUE!")
    if _is_err(b):
        return b
    return not b

func _true(args):
    return true

func _false(args):
    return false

func _isnumber(args):
    v := _scalar(args[0])
    return _is_num(v) or u.is_date_dict(v)

func _istext(args):
    return type(_scalar(args[0])) == "str"

func _isnontext(args):
    return type(_scalar(args[0])) != "str"

func _iserror(args):
    return _is_err(_scalar(args[0]))

func _iserr(args):
    v := _scalar(args[0])
    return _is_err(v) and v.code != "#N/A"

func _isna(args):
    v := _scalar(args[0])
    return _is_err(v) and v.code == "#N/A"

func _islogical(args):
    return type(_scalar(args[0])) == "bool"

func _iseven(args):
    n := _num(args[0])
    if _is_err(n):
        return n
    return to_int(n) % 2 == 0

func _isodd(args):
    n := _num(args[0])
    if _is_err(n):
        return n
    return to_int(n) % 2 != 0

func _na(args):
    return xc.ErrorValue("#N/A")

func _n_fn(args):
    v := _scalar(args[0])
    if _is_num(v):
        return v
    if type(v) == "bool":
        return 1 if v else 0
    if _is_err(v):
        return v
    if u.is_date_dict(v):
        return xc.coerce_number(v)
    return 0

# ---------------------------------------------------------------------- texte

func _concat(args):
    out := []
    for v in _all_values(args):
        t := _text(v)
        if _is_err(t):
            return t
        append(out, t)
    return string.join("", out)

func _textjoin(args):
    if len(args) < 3:
        return xc.ErrorValue("#VALUE!")
    sep := _text(args[0])
    ignore := _bool(args[1])
    parts := []
    i := 2
    while i < len(args):
        for v in _all_values([args[i]]):
            t := _text(v)
            if _is_err(t):
                return t
            if ignore and t == "":
                continue
            append(parts, t)
        i = i + 1
    return string.join(sep, parts)

func _len(args):
    t := _text(args[0])
    if _is_err(t):
        return t
    return len(t)

func _left(args):
    t := _text(args[0])
    if _is_err(t):
        return t
    n := _arg_num(args, 1, 1)
    if _is_err(n):
        return n
    if n < 0:
        return xc.ErrorValue("#VALUE!")
    return _n.str_slice(t, 0, to_int(n))

func _right(args):
    t := _text(args[0])
    if _is_err(t):
        return t
    n := _arg_num(args, 1, 1)
    if _is_err(n):
        return n
    if n < 0:
        return xc.ErrorValue("#VALUE!")
    k := to_int(n)
    if k >= len(t):
        return t
    return _n.str_slice(t, len(t) - k, null)

func _mid(args):
    t := _text(args[0])
    if _is_err(t):
        return t
    s := _arg_num(args, 1)
    n := _arg_num(args, 2)
    if _is_err(s):
        return s
    if _is_err(n):
        return n
    if s < 1 or n < 0:
        return xc.ErrorValue("#VALUE!")
    return _n.str_slice(t, to_int(s) - 1, to_int(s) - 1 + to_int(n))

func _upper(args):
    t := _text(args[0])
    return t if _is_err(t) else _uc(t)

func _uc(t):
    out := []
    for c in t:
        o := string.ord(c)
        if (o >= 97 and o <= 122) or (o >= 224 and o <= 254 and o != 247):
            append(out, str(string.chr(o - 32)))
        elif o == 339:
            append(out, str(string.chr(338)))
        else:
            append(out, str(c))
    return string.join("", out)

func _lc(t):
    out := []
    for c in t:
        o := string.ord(c)
        if (o >= 65 and o <= 90) or (o >= 192 and o <= 222 and o != 215):
            append(out, str(string.chr(o + 32)))
        elif o == 338:
            append(out, str(string.chr(339)))
        else:
            append(out, str(c))
    return string.join("", out)

func _lower(args):
    t := _text(args[0])
    return t if _is_err(t) else _lc(t)

func _proper(args):
    t := _text(args[0])
    if _is_err(t):
        return t
    out := []
    prev_letter := false
    for c in t:
        ch := str(c)
        letter := _is_letter(ch) and ch != "_"
        if letter and not prev_letter:
            append(out, _uc(ch))
        elif letter:
            append(out, _lc(ch))
        else:
            append(out, ch)
        prev_letter = letter
    return string.join("", out)

func _trim(args):
    t := _text(args[0])
    if _is_err(t):
        return t
    parts := []
    for w in string.split(t, " "):
        if w != "":
            append(parts, w)
    return string.join(" ", parts)

func _clean(args):
    t := _text(args[0])
    if _is_err(t):
        return t
    out := []
    for c in t:
        if string.ord(c) >= 32:
            append(out, str(c))
    return string.join("", out)

func _substitute(args):
    t := _text(args[0])
    old := _text(args[1])
    new_t := _text(args[2])
    if _is_err(t):
        return t
    if old == "":
        return t
    if len(args) < 4 or args[3] == null:
        return string.replace(t, old, new_t)
    k := to_int(_num(args[3]))
    pos := -1
    count := 0
    start := 0
    while true:
        p := _n.str_find(t, old, start)
        if p < 0:
            return t
        count = count + 1
        if count == k:
            pos = p
            break
        start = p + len(old)
    return _n.str_slice(t, 0, pos) + new_t + _n.str_slice(t, pos + len(old), null)

func _replace(args):
    t := _text(args[0])
    s := _arg_num(args, 1)
    n := _arg_num(args, 2)
    new_t := _text(args[3])
    if _is_err(t):
        return t
    if _is_err(s) or _is_err(n):
        return xc.ErrorValue("#VALUE!")
    st := to_int(s) - 1
    return _n.str_slice(t, 0, st) + new_t + _n.str_slice(t, st + to_int(n), null)

func _find_impl(args, ci):
    needle := _text(args[0])
    hay := _text(args[1])
    if _is_err(needle):
        return needle
    if _is_err(hay):
        return hay
    s := _arg_num(args, 2, 1)
    if _is_err(s) or s < 1:
        return xc.ErrorValue("#VALUE!")
    p := -1
    if ci:
        hl := _lc(hay)
        nl := _lc(needle)
        if string.contains(nl, "*") or string.contains(nl, "?"):
            k := to_int(s) - 1
            while k <= len(hl):
                j := k
                while j <= len(hl):
                    if _wild_match(nl, _n.str_slice(hl, k, j)):
                        return k + 1
                    j = j + 1
                k = k + 1
            return xc.ErrorValue("#VALUE!")
        p = _n.str_find(hl, nl, to_int(s) - 1)
    else:
        p = _n.str_find(hay, needle, to_int(s) - 1)
    if p < 0:
        return xc.ErrorValue("#VALUE!")
    return p + 1

func _find(args):
    return _find_impl(args, false)

func _search(args):
    return _find_impl(args, true)

func _rept(args):
    t := _text(args[0])
    n := _arg_num(args, 1)
    if _is_err(t):
        return t
    if _is_err(n) or n < 0:
        return xc.ErrorValue("#VALUE!")
    return string.repeat(t, to_int(n))

func _exact(args):
    return _text(args[0]) == _text(args[1])

func _char(args):
    n := _arg_num(args, 0)
    if _is_err(n):
        return n
    k := to_int(n)
    if k < 1 or k > 255:
        return xc.ErrorValue("#VALUE!")
    return u.cp1252_decode([k])

func _code(args):
    t := _text(args[0])
    if _is_err(t) or t == "":
        return xc.ErrorValue("#VALUE!")
    b := u.cp1252_encode(_n.str_slice(t, 0, 1), 63)
    return b[0]

func _t(args):
    v := _scalar(args[0])
    return v if type(v) == "str" else ""

func _value(args):
    v := _scalar(args[0])
    if _is_num(v):
        return v
    t := _text(v)
    if _is_err(t):
        return t
    n := xc.coerce_number(string.replace(string.replace(string.trim(t), ",", ""), "$", ""))
    if _is_err(n):
        try:
            d := u.date_parts(string.trim(t))
            return xc.coerce_number(d)
        catch e:
            return n
    return n

func _text_fn(args):
    v := _scalar(args[0])
    fmt := _text(args[1])
    if _is_err(fmt):
        return fmt
    if _is_err(v):
        return v
    if type(v) == "str":
        n := _n.num_parse(v)
        if n == null:
            return v
        v = n
    return _formatter(v, fmt)

func _fixed_fn(args):
    x := _arg_num(args, 0)
    if _is_err(x):
        return x
    d := _arg_num(args, 1, 2)
    no_commas := len(args) > 2 and _bool(args[2]) == true
    dd := to_int(d)
    code := ("0" if no_commas else "#,##0") + ("." + string.repeat("0", dd) if dd > 0 else "")
    return _formatter(x, code)

func _dollar(args):
    x := _arg_num(args, 0)
    if _is_err(x):
        return x
    d := to_int(_arg_num(args, 1, 2))
    return _formatter(x, "$#,##0" + ("." + string.repeat("0", d) if d > 0 else "") + ";($#,##0" + ("." + string.repeat("0", d) if d > 0 else "") + ")")

_formatter := (v, fmt) => u.to_text(v)

func set_formatter(f):
    _formatter = f

# ---------------------------------------------------------------------- recherche

func _rows_of(v):
    if _is_range(v):
        return v.rows
    return [[_scalar(v)]]

func _vlookup(args):
    if len(args) < 3:
        return xc.ErrorValue("#VALUE!")
    key_ := _scalar(args[0])
    if _is_err(key_):
        return key_
    rows := _rows_of(args[1])
    col := _arg_num(args, 2)
    if _is_err(col):
        return col
    col = to_int(col)
    approx := true
    if len(args) > 3 and args[3] != null:
        b := _bool(args[3])
        approx = b == true
    if col < 1 or (len(rows) > 0 and col > len(rows[0])):
        return xc.ErrorValue("#REF!")
    idx := _lookup_index(key_, _column(rows, 0), approx)
    if idx < 0:
        return xc.ErrorValue("#N/A")
    return rows[idx][col - 1]

func _hlookup(args):
    if len(args) < 3:
        return xc.ErrorValue("#VALUE!")
    key_ := _scalar(args[0])
    rows := _rows_of(args[1])
    r := to_int(_num(args[2]))
    approx := true
    if len(args) > 3 and args[3] != null:
        approx = _bool(args[3]) == true
    if r < 1 or r > len(rows):
        return xc.ErrorValue("#REF!")
    idx := _lookup_index(key_, rows[0], approx)
    if idx < 0:
        return xc.ErrorValue("#N/A")
    return rows[r - 1][idx]

func _column(rows, c):
    out := []
    for r in rows:
        append(out, r[c] if c < len(r) else null)
    return out

# Recherche exacte (avec jokers pour le texte) ou approchée (plus grande valeur <= clé, liste triée).
func _lookup_index(key_, vals, approx):
    if not approx:
        wild := type(key_) == "str" and (string.contains(key_, "*") or string.contains(key_, "?"))
        i := 0
        for v in vals:
            if wild and type(v) == "str":
                if _wild_match(key_, v):
                    return i
            elif v != null and _type_rank(v) == _type_rank(key_) and compare(v, key_) == 0:
                return i
            i = i + 1
        return -1
    best := -1
    i := 0
    for v in vals:
        if v != null and _type_rank(v) == _type_rank(key_):
            c := compare(v, key_)
            if c <= 0:
                best = i
            else:
                break
        i = i + 1
    return best

func _match(args):
    key_ := _scalar(args[0])
    vals := _cells(args[1])
    mt := 1
    if len(args) > 2 and args[2] != null:
        mt = to_int(_num(args[2]))
    idx := -1
    if mt == 0:
        idx = _lookup_index(key_, vals, false)
    elif mt == 1:
        idx = _lookup_index(key_, vals, true)
    else:
        i := 0
        for v in vals:
            if v != null and compare(v, key_) >= 0:
                idx = i
            else:
                break
            i = i + 1
    if idx < 0:
        return xc.ErrorValue("#N/A")
    return idx + 1

func _xmatch(args):
    key_ := _scalar(args[0])
    vals := _cells(args[1])
    mode := 0
    if len(args) > 2 and args[2] != null:
        mode = to_int(_num(args[2]))
    if mode == 2:
        i := 0
        for v in vals:
            if type(v) == "str" and type(key_) == "str" and _wild_match(key_, v):
                return i + 1
            i = i + 1
        return xc.ErrorValue("#N/A")
    idx := _lookup_index(key_, vals, false)
    if idx >= 0:
        return idx + 1
    if mode == -1 or mode == 1:
        best := -1
        i := 0
        for v in vals:
            if v != null and _type_rank(v) == _type_rank(key_):
                c := compare(v, key_)
                if mode == -1 and c < 0 and (best < 0 or compare(v, vals[best]) > 0):
                    best = i
                if mode == 1 and c > 0 and (best < 0 or compare(v, vals[best]) < 0):
                    best = i
            i = i + 1
        if best >= 0:
            return best + 1
    return xc.ErrorValue("#N/A")

func _xlookup(args):
    if len(args) < 3:
        return xc.ErrorValue("#VALUE!")
    pos := _xmatch([args[0], args[1], null if len(args) < 5 else args[4]])
    if _is_err(pos):
        if len(args) > 3 and args[3] != null:
            return args[3]
        return pos
    ret := args[2]
    if _is_range(ret):
        if ret.height() == 1:
            return ret.at(0, pos - 1)
        if ret.width() == 1:
            return ret.at(pos - 1, 0)
        return Range(ret.sheet, 0, 0, 0, ret.width() - 1, [ret.rows[pos - 1]])
    return ret

func _lookup(args):
    key_ := _scalar(args[0])
    vals := _cells(args[1])
    res := _cells(args[2]) if len(args) > 2 else vals
    idx := _lookup_index(key_, vals, true)
    if idx < 0 or idx >= len(res):
        return xc.ErrorValue("#N/A")
    return res[idx]

func _index(args):
    rows := _rows_of(args[0])
    r := to_int(_arg_num(args, 1, 0))
    c := to_int(_arg_num(args, 2, 0)) if len(args) > 2 else 0
    if len(rows) == 1 and len(args) == 2:
        c = r
        r = 1
    if r == 0 and c == 0:
        return args[0]
    if r < 0 or c < 0 or r > len(rows) or (len(rows) > 0 and c > len(rows[0])):
        return xc.ErrorValue("#REF!")
    if r == 0:
        col := []
        for row in rows:
            append(col, [row[c - 1]])
        return Range(null, 0, 0, len(col) - 1, 0, col)
    if c == 0:
        if len(rows[r - 1]) == 1:
            return rows[r - 1][0]
        return Range(null, 0, 0, 0, len(rows[r - 1]) - 1, [rows[r - 1]])
    return rows[r - 1][c - 1]

func _rows_fn(args):
    if _is_range(args[0]):
        return args[0].height()
    return 1

func _columns_fn(args):
    if _is_range(args[0]):
        return args[0].width()
    return 1

# ---------------------------------------------------------------------- dates

func _serial(v):
    s := _scalar(v)
    if u.is_date_dict(s):
        return xc.coerce_number(s)
    if type(s) == "str":
        n := _n.num_parse(s)
        if n != null:
            return n
        try:
            return xc.coerce_number(u.date_parts(string.trim(s)))
        catch e:
            return xc.ErrorValue("#VALUE!")
    return _num(s)

func _date(args):
    y := _arg_num(args, 0)
    m := _arg_num(args, 1)
    d := _arg_num(args, 2)
    if _is_err(y) or _is_err(m) or _is_err(d):
        return xc.ErrorValue("#VALUE!")
    yy := to_int(y)
    if yy < 1900:
        yy = yy + 1900
    mm := to_int(m)
    # mois hors 1..12 : report sur l'année
    yy = yy + (mm - 1) // 12
    mm = (mm - 1) % 12 + 1
    base := u.date_to_serial(yy, mm, 1)
    return base + to_int(d) - 1

func _time_fn(args):
    h := _arg_num(args, 0)
    m := _arg_num(args, 1)
    s := _arg_num(args, 2)
    if _is_err(h) or _is_err(m) or _is_err(s):
        return xc.ErrorValue("#VALUE!")
    t := (to_float(h) * 3600.0 + to_float(m) * 60.0 + to_float(s)) / 86400.0
    return t - to_float(to_int(t))

func _date_part(args, field):
    s := _serial(args[0])
    if _is_err(s):
        return s
    if s < 0:
        return xc.ErrorValue("#NUM!")
    return u.serial_to_date(s)[field]

func _year(args):
    return _date_part(args, "year")

func _month(args):
    return _date_part(args, "month")

func _day(args):
    return _date_part(args, "day")

func _hour(args):
    return _date_part(args, "hour")

func _minute(args):
    return _date_part(args, "minute")

func _second(args):
    return _date_part(args, "second")

func _today(args):
    g := time.localtime()
    return u.date_to_serial(g["year"], g["month"], g["day"])

func _now(args):
    g := time.localtime()
    return u.date_to_serial(g["year"], g["month"], g["day"], g["hour"], g["minute"], to_int(g["second"]))

func _weekday(args):
    s := _serial(args[0])
    if _is_err(s):
        return s
    t := to_int(_arg_num(args, 1, 1))
    d := u.serial_to_date(s)
    wd := time.weekday(d["year"], d["month"], d["day"])
    if t == 1:
        return (wd + 1) % 7 + 1
    if t == 2:
        return wd + 1
    if t == 3:
        return wd
    return xc.ErrorValue("#NUM!")

func _weeknum(args):
    s := _serial(args[0])
    if _is_err(s):
        return s
    d := u.serial_to_date(s)
    t := to_int(_arg_num(args, 1, 1))
    if t == 21:
        return time.iso_calendar(d["year"], d["month"], d["day"])[1]
    jan1 := u.date_to_serial(d["year"], 1, 1)
    j := u.serial_to_date(jan1)
    wd := time.weekday(j["year"], 1, 1)
    start := (wd + 1) % 7 if t == 1 else wd
    return (to_int(s) - jan1 + start) // 7 + 1

func _add_months(s, n, end_of_month):
    d := u.serial_to_date(s)
    m := d["month"] - 1 + n
    y := d["year"] + m // 12
    m = m % 12 + 1
    dim := time.days_in_month(y, m)
    day := dim if end_of_month else (d["day"] if d["day"] <= dim else dim)
    return u.date_to_serial(y, m, day)

func _edate(args):
    s := _serial(args[0])
    n := _arg_num(args, 1)
    if _is_err(s) or _is_err(n):
        return xc.ErrorValue("#VALUE!")
    return _add_months(s, to_int(n), false)

func _eomonth(args):
    s := _serial(args[0])
    n := _arg_num(args, 1)
    if _is_err(s) or _is_err(n):
        return xc.ErrorValue("#VALUE!")
    return _add_months(s, to_int(n), true)

func _days(args):
    a := _serial(args[0])
    b := _serial(args[1])
    if _is_err(a) or _is_err(b):
        return xc.ErrorValue("#VALUE!")
    return to_int(a) - to_int(b)

func _datedif(args):
    a := _serial(args[0])
    b := _serial(args[1])
    unit := string.upper(_text(args[2]))
    if _is_err(a) or _is_err(b):
        return xc.ErrorValue("#VALUE!")
    if a > b:
        return xc.ErrorValue("#NUM!")
    da := u.serial_to_date(a)
    db := u.serial_to_date(b)
    months := (db["year"] - da["year"]) * 12 + db["month"] - da["month"]
    if db["day"] < da["day"]:
        months = months - 1
    if unit == "D":
        return to_int(b) - to_int(a)
    if unit == "M":
        return months
    if unit == "Y":
        return months // 12
    if unit == "YM":
        return months % 12
    if unit == "MD":
        dd := db["day"] - da["day"]
        if dd < 0:
            pm := db["month"] - 1
            py := db["year"]
            if pm == 0:
                pm = 12
                py = py - 1
            dd = dd + time.days_in_month(py, pm)
        return dd
    if unit == "YD":
        y := db["year"]
        anniv := 0
        try:
            anniv = u.date_to_serial(y, da["month"], da["day"] if da["day"] <= time.days_in_month(y, da["month"]) else time.days_in_month(y, da["month"]))
        catch e:
            return xc.ErrorValue("#NUM!")
        if anniv > to_int(b):
            y = y - 1
            anniv = u.date_to_serial(y, da["month"], da["day"] if da["day"] <= time.days_in_month(y, da["month"]) else time.days_in_month(y, da["month"]))
        return to_int(b) - anniv
    return xc.ErrorValue("#NUM!")

func _holidays(v):
    out := {}
    if v == null:
        return out
    for h in _cells(v):
        s := _serial(h)
        if not _is_err(s):
            out[to_int(s)] = true
    return out

func _is_workday(s, hol):
    d := u.serial_to_date(s)
    wd := time.weekday(d["year"], d["month"], d["day"])
    return wd < 5 and not contains_key(hol, s)

func _networkdays(args):
    a := _serial(args[0])
    b := _serial(args[1])
    if _is_err(a) or _is_err(b):
        return xc.ErrorValue("#VALUE!")
    hol := _holidays(args[2] if len(args) > 2 else null)
    lo := to_int(a)
    hi := to_int(b)
    sign := 1
    if lo > hi:
        t := lo
        lo = hi
        hi = t
        sign = -1
    n := 0
    s := lo
    while s <= hi:
        if _is_workday(s, hol):
            n = n + 1
        s = s + 1
    return n * sign

func _workday(args):
    s := _serial(args[0])
    k := _arg_num(args, 1)
    if _is_err(s) or _is_err(k):
        return xc.ErrorValue("#VALUE!")
    hol := _holidays(args[2] if len(args) > 2 else null)
    cur := to_int(s)
    left := to_int(k)
    step := 1 if left >= 0 else -1
    while left != 0:
        cur = cur + step
        if _is_workday(cur, hol):
            left = left - step
    return cur

func _datevalue(args):
    t := _text(args[0])
    if _is_err(t):
        return t
    try:
        return to_int(xc.coerce_number(u.date_parts(string.trim(t))))
    catch e:
        return xc.ErrorValue("#VALUE!")

# ---------------------------------------------------------------------- finances

func _fin_args(args, n):
    out := []
    i := 0
    while i < n:
        v := 0
        if i < len(args) and args[i] != null:
            v = _num(args[i])
            if _is_err(v):
                return v
        append(out, to_float(v))
        i = i + 1
    return out

func _pmt(args):
    a := _fin_args(args, 5)
    if _is_err(a):
        return a
    rate := a[0]
    nper := a[1]
    pv := a[2]
    fv := a[3]
    typ := a[4]
    if nper == 0:
        return xc.ErrorValue("#NUM!")
    if rate == 0:
        return -(pv + fv) / nper
    f := (1.0 + rate) ** nper
    return -(rate * (fv + pv * f)) / ((1.0 + rate * typ) * (f - 1.0))

func _fv(args):
    a := _fin_args(args, 5)
    if _is_err(a):
        return a
    rate := a[0]
    nper := a[1]
    pmt := a[2]
    pv := a[3]
    typ := a[4]
    if rate == 0:
        return -(pv + pmt * nper)
    f := (1.0 + rate) ** nper
    return -(pv * f + pmt * (1.0 + rate * typ) * (f - 1.0) / rate)

func _pv(args):
    a := _fin_args(args, 5)
    if _is_err(a):
        return a
    rate := a[0]
    nper := a[1]
    pmt := a[2]
    fv := a[3]
    typ := a[4]
    if rate == 0:
        return -(fv + pmt * nper)
    f := (1.0 + rate) ** nper
    return -(fv + pmt * (1.0 + rate * typ) * (f - 1.0) / rate) / f

func _ipmt(args):
    a := _fin_args(args, 6)
    if _is_err(a):
        return a
    rate := a[0]
    per := a[1]
    nper := a[2]
    pv := a[3]
    fv := a[4]
    typ := a[5]
    pmt := _pmt([rate, nper, pv, fv, typ])
    if typ == 1 and per == 1:
        return 0.0
    bal := _fv([rate, per - 1.0, pmt, pv, typ])
    r := bal * rate
    if typ == 1:
        r = r / (1.0 + rate)
    return r

func _ppmt(args):
    a := _fin_args(args, 6)
    if _is_err(a):
        return a
    return _pmt([a[0], a[2], a[3], a[4], a[5]]) - _ipmt(args)

func _nper(args):
    a := _fin_args(args, 5)
    if _is_err(a):
        return a
    rate := a[0]
    pmt := a[1]
    pv := a[2]
    fv := a[3]
    typ := a[4]
    if rate == 0:
        if pmt == 0:
            return xc.ErrorValue("#NUM!")
        return -(pv + fv) / pmt
    z := pmt * (1.0 + rate * typ) / rate
    num := z - fv
    den := pv + z
    if den == 0 or num / den <= 0:
        return xc.ErrorValue("#NUM!")
    return math.ln(num / den) / math.ln(1.0 + rate)

func _npv(args):
    rate := _num(args[0])
    if _is_err(rate):
        return rate
    ns := _numbers(_slice_args(args, 1))
    if _is_err(ns):
        return ns
    s := 0.0
    i := 1
    for v in ns:
        s = s + to_float(v) / ((1.0 + to_float(rate)) ** to_float(i))
        i = i + 1
    return s

func _slice_args(args, start):
    out := []
    i := start
    while i < len(args):
        append(out, args[i])
        i = i + 1
    return out

func _irr(args):
    ns := _numbers([args[0]])
    if _is_err(ns):
        return ns
    guess := to_float(_arg_num(args, 1, 0.1))
    r := guess
    k := 0
    while k < 100:
        f := 0.0
        df := 0.0
        i := 0
        for v in ns:
            fv := to_float(v)
            f = f + fv / ((1.0 + r) ** to_float(i))
            df = df - to_float(i) * fv / ((1.0 + r) ** to_float(i + 1))
            i = i + 1
        if df == 0:
            return xc.ErrorValue("#NUM!")
        nr := r - f / df
        if (nr - r if nr > r else r - nr) < 0.0000001:
            return nr
        r = nr
        k = k + 1
    return xc.ErrorValue("#NUM!")

func _rate(args):
    a := _fin_args(args, 6)
    if _is_err(a):
        return a
    nper := a[0]
    pmt := a[1]
    pv := a[2]
    fv := a[3]
    typ := a[4]
    r := a[5] if len(args) > 5 and args[5] != null else 0.1
    k := 0
    while k < 100:
        g := _fv([r, nper, pmt, pv, typ]) - fv
        h := 0.000001
        g2 := _fv([r + h, nper, pmt, pv, typ]) - fv
        d := (g2 - g) / h
        if d == 0:
            return xc.ErrorValue("#NUM!")
        nr := r - g / d
        if (nr - r if nr > r else r - nr) < 0.00000001:
            return nr
        r = nr
        k = k + 1
    return xc.ErrorValue("#NUM!")

func _install():
    register("SUM", _sum)
    register("PRODUCT", _product)
    register("SUMPRODUCT", _sumproduct)
    register("ROUND", _round)
    register("ROUNDUP", _roundup)
    register("ROUNDDOWN", _rounddown)
    register("INT", _int)
    register("TRUNC", _trunc)
    register("MOD", _mod)
    register("POWER", _power)
    register("SQRT", _sqrt)
    register("EXP", _unary((x) => math.exp(x)))
    register("LN", _unary((x) => math.ln(x), (x) => x > 0))
    register("LOG10", _unary((x) => math.ln(x) / math.ln(10.0), (x) => x > 0))
    register("LOG", _log)
    register("ABS", _abs)
    register("SIGN", _sign)
    register("PI", _pi)
    register("CEILING", _ceiling)
    register("CEILING.MATH", _ceiling)
    register("FLOOR", _floor)
    register("FLOOR.MATH", _floor)
    register("MROUND", _mround)
    register("QUOTIENT", _quotient)
    register("GCD", _gcd)
    register("LCM", _lcm)
    register("FACT", _fact)
    register("EVEN", _even)
    register("ODD", _odd)
    register("RAND", _rand)
    register("RANDBETWEEN", _randbetween)
    register("SIN", _unary((x) => math.sin(x)))
    register("COS", _unary((x) => math.cos(x)))
    register("TAN", _unary((x) => math.tan(x)))
    register("ASIN", _unary((x) => math.asin(x), (x) => x >= -1 and x <= 1))
    register("ACOS", _unary((x) => math.acos(x), (x) => x >= -1 and x <= 1))
    register("ATAN", _unary((x) => math.atan(x)))
    register("RADIANS", _unary((x) => x * math.PI / 180.0))
    register("DEGREES", _unary((x) => x * 180.0 / math.PI))
    register("AVERAGE", _average)
    register("AVERAGEA", _averagea)
    register("MIN", _min)
    register("MAX", _max)
    register("MEDIAN", _median)
    register("MODE", _mode)
    register("MODE.SNGL", _mode)
    register("COUNT", _count)
    register("COUNTA", _counta)
    register("COUNTBLANK", _countblank)
    register("VAR", _var)
    register("VAR.S", _var)
    register("VARP", _varp)
    register("VAR.P", _varp)
    register("STDEV", _stdev)
    register("STDEV.S", _stdev)
    register("STDEVP", _stdevp)
    register("STDEV.P", _stdevp)
    register("LARGE", _large)
    register("SMALL", _small)
    register("RANK", _rank)
    register("RANK.EQ", _rank)
    register("PERCENTILE", _percentile)
    register("PERCENTILE.INC", _percentile)
    register("QUARTILE", _quartile)
    register("QUARTILE.INC", _quartile)
    register("CORREL", _correl)
    register("SUMIF", _sumif)
    register("SUMIFS", _sumifs)
    register("COUNTIF", _countif)
    register("COUNTIFS", _countifs)
    register("AVERAGEIF", _averageif)
    register("AVERAGEIFS", _averageifs)
    register("MAXIFS", _maxifs)
    register("MINIFS", _minifs)
    register("NOT", _not)
    register("TRUE", _true)
    register("FALSE", _false)
    register("ISNUMBER", _isnumber)
    register("ISTEXT", _istext)
    register("ISNONTEXT", _isnontext)
    register("ISERROR", _iserror)
    register("ISERR", _iserr)
    register("ISNA", _isna)
    register("ISLOGICAL", _islogical)
    register("ISEVEN", _iseven)
    register("ISODD", _isodd)
    register("NA", _na)
    register("N", _n_fn)
    register("CONCATENATE", _concat)
    register("CONCAT", _concat)
    register("TEXTJOIN", _textjoin)
    register("LEN", _len)
    register("LEFT", _left)
    register("RIGHT", _right)
    register("MID", _mid)
    register("UPPER", _upper)
    register("LOWER", _lower)
    register("PROPER", _proper)
    register("TRIM", _trim)
    register("CLEAN", _clean)
    register("SUBSTITUTE", _substitute)
    register("REPLACE", _replace)
    register("FIND", _find)
    register("SEARCH", _search)
    register("REPT", _rept)
    register("EXACT", _exact)
    register("CHAR", _char)
    register("CODE", _code)
    register("T", _t)
    register("VALUE", _value)
    register("TEXT", _text_fn)
    register("FIXED", _fixed_fn)
    register("DOLLAR", _dollar)
    register("VLOOKUP", _vlookup)
    register("HLOOKUP", _hlookup)
    register("XLOOKUP", _xlookup)
    register("LOOKUP", _lookup)
    register("MATCH", _match)
    register("XMATCH", _xmatch)
    register("INDEX", _index)
    register("ROWS", _rows_fn)
    register("COLUMNS", _columns_fn)
    register("DATE", _date)
    register("TIME", _time_fn)
    register("YEAR", _year)
    register("MONTH", _month)
    register("DAY", _day)
    register("HOUR", _hour)
    register("MINUTE", _minute)
    register("SECOND", _second)
    register("TODAY", _today)
    register("NOW", _now)
    register("WEEKDAY", _weekday)
    register("WEEKNUM", _weeknum)
    register("EDATE", _edate)
    register("EOMONTH", _eomonth)
    register("DAYS", _days)
    register("DATEDIF", _datedif)
    register("NETWORKDAYS", _networkdays)
    register("WORKDAY", _workday)
    register("DATEVALUE", _datevalue)
    register("PMT", _pmt)
    register("IPMT", _ipmt)
    register("PPMT", _ppmt)
    register("FV", _fv)
    register("PV", _pv)
    register("NPER", _nper)
    register("NPV", _npv)
    register("IRR", _irr)
    register("RATE", _rate)

_install()

# Évalue une formule (texte ou AST). resolver : voir l'en-tête ; sheet : feuille courante (pour les messages).
func evaluate(formula, resolver=null, sheet=null):
    ast := formula
    if type(formula) == "str":
        ast = parse(formula)
    ev := Evaluator(resolver, sheet)
    v := ev.ev(ast)
    if _is_range(v):
        return v.at(0, 0)
    if type(v) == "float":
        if v != v or (v - v) != 0.0:
            return xc.ErrorValue("#NUM!")
    return v
