# ALEX STANDARD LIBRARY — web.css.selector_parser
#
# Analyse des sélecteurs CSS (Selectors Level 4) en structures, et calcul de leur spécificité.
#
# Pris en charge : type, *, #id, .classe, [attr], [attr=v], ~=, |=, ^=, $=, *=, drapeaux i / s ; pseudo-classes
# simples (:hover, :first-child, :checked...), fonctionnelles (:not(), :is(), :where(), :has(), :nth-child(an+b
# [of S]), :nth-last-child(), :nth-of-type(), :nth-last-of-type(), :lang(), :dir()) ; pseudo-éléments (::before,
# ::after, ::marker, ::placeholder... et les écritures « :before » historiques) ; combinateurs « ␠ », « > »,
# « + », « ~ » ; sélecteur d'imbrication « & » ; listes « a, b » ; sélecteurs relatifs dans :has(> a).
#
#   use web.css.selector_parser as sp
#   lst := sp.parse("nav > a.actif:not(.x), #menu li:nth-child(2n+1)")
#   len(lst)                                  # 2
#   sp.specificity(lst[1])                    # (1, 1, 1)
#   sp.specificity(sp.parse(":where(#a) p")[0])   # (0, 0, 1)
#   sp.is_valid("a[href")                     # false
#
# Structures : SelectorList = liste de Complex ; Complex.parts = liste de (combinateur, Compound) (le premier
# combinateur vaut null, ou « > » / « + » / « ~ » pour un sélecteur relatif) ; Compound : tag, ids, classes,
# attrs [(nom, op, valeur, drapeau)], pseudos [(nom, argument)], pseudo_element.
#
# Erreurs : CssSelectorError.

from core use len, type, to_int
from collections use append
use string as _s
use web.css.css_errors as _err

const PSEUDO_ELEMENTS := ["before", "after", "first-line", "first-letter", "marker", "placeholder", "selection", "backdrop", "file-selector-button", "cue", "part", "slotted", "spelling-error", "grammar-error", "highlight", "view-transition", "target-text"]
const LEGACY_PSEUDO_ELEMENTS := ["before", "after", "first-line", "first-letter"]
const SELECTOR_ARG := ["not", "is", "where", "has", "matches", "any", "-webkit-any"]
const NTH := ["nth-child", "nth-last-child", "nth-of-type", "nth-last-of-type", "nth-col", "nth-last-col"]
const PSEUDO_CLASSES := ["active", "any-link", "autofill", "blank", "checked", "current", "default", "defined", "disabled", "empty", "enabled", "first", "first-child", "first-of-type", "focus", "focus-visible", "focus-within", "fullscreen", "future", "host", "hover", "in-range", "indeterminate", "invalid", "last-child", "last-of-type", "left", "link", "local-link", "modal", "only-child", "only-of-type", "open", "optional", "out-of-range", "past", "paused", "picture-in-picture", "placeholder-shown", "playing", "popover-open", "read-only", "read-write", "required", "right", "root", "scope", "target", "target-within", "user-invalid", "user-valid", "valid", "visited", "lang", "dir", "state", "host-context"]

class Compound:
    func init():
        self.tag = null              # nom de balise en minuscules, « * », ou null
        self.ids = []
        self.classes = []
        self.attrs = []              # (nom, op ou null, valeur ou null, drapeau « i » / « s » / null)
        self.pseudos = []            # (nom, argument) ; argument : null, str, SelectorList, Nth
        self.pseudo_element = null   # (nom, argument) ou null
        self.nesting = false         # contient « & »

    func is_empty():
        return self.tag == null and len(self.ids) == 0 and len(self.classes) == 0 and len(self.attrs) == 0 and len(self.pseudos) == 0 and self.pseudo_element == null and not self.nesting

    func to_css():
        out := ""
        if self.nesting:
            out = "&"
        if self.tag != null:
            out = out + self.tag
        for i in self.ids:
            out = out + "#" + i
        for c in self.classes:
            out = out + "." + c
        for a in self.attrs:
            out = out + "[" + a[0]
            if a[1] != null:
                out = out + a[1] + "\"" + _s.replace(a[2], "\"", "\\\"") + "\""
                if a[3] != null:
                    out = out + " " + a[3]
            out = out + "]"
        for p in self.pseudos:
            out = out + ":" + p[0]
            if p[1] != null:
                out = out + "(" + _arg_css(p[1]) + ")"
        if self.pseudo_element != null:
            out = out + "::" + self.pseudo_element[0]
            if self.pseudo_element[1] != null:
                out = out + "(" + str(self.pseudo_element[1]) + ")"
        if out == "":
            return "*"
        return out

class Nth:
    func init(a, b, of=null):
        self.a = a
        self.b = b
        self.of = of                 # SelectorList ou null

    # Vrai si la position (1...) correspond à an+b.
    func matches(pos):
        if self.a == 0:
            return pos == self.b
        d := pos - self.b
        if d % self.a != 0:
            return false
        return d // self.a >= 0

    func to_css():
        out := ""
        if self.a == 0:
            out = str(self.b)
        else:
            out = (str(self.a) if self.a != 1 and self.a != -1 else ("-" if self.a == -1 else "")) + "n"
            if self.b > 0:
                out = out + "+" + str(self.b)
            elif self.b < 0:
                out = out + str(self.b)
        if self.of != null:
            out = out + " of " + self.of.to_css()
        return out

class Complex:
    func init(parts):
        self.parts = parts           # [(combinateur, Compound)]

    func to_css():
        out := ""
        i := 0
        for p in self.parts:
            comb := p[0]
            if i == 0:
                if comb != null:
                    out = comb + " "
            elif comb == " ":
                out = out + " "
            else:
                out = out + " " + comb + " "
            out = out + p[1].to_css()
            i += 1
        return out

    func last():
        return self.parts[len(self.parts) - 1][1]

    func pseudo_element():
        return self.last().pseudo_element

class SelectorList:
    func init(items, text=""):
        self.items = items
        self.text = text

    func to_css():
        parts := []
        for c in self.items:
            append(parts, c.to_css())
        return _s.join(", ", parts)

    func __len__():
        return len(self.items)

    func __getitem__(i):
        return self.items[i]

    func __str__():
        return self.to_css()

func _arg_css(arg):
    if type(arg) == "str":
        return arg
    return arg.to_css()

# ---------------------------------------------------------------- analyse

func _fail(full, why):
    _err.selector_error("selector_parser", "sélecteur invalide « " + full + " » : " + why)

func _is_ident_char(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_' or _s.ord(c) >= 128

class _P:
    func init(text, full):
        self.t = text
        self.n = len(text)
        self.i = 0
        self.full = full

    func peek(k=0):
        j := self.i + k
        if j < self.n:
            return self.t[j]
        return null

    func skip_ws():
        moved := false
        while self.i < self.n and (self.t[self.i] == ' ' or self.t[self.i] == '\t' or self.t[self.i] == '\n' or self.t[self.i] == '\r'):
            self.i += 1
            moved = true
        return moved

    func ident():
        out := []
        while self.i < self.n:
            c := self.t[self.i]
            if _is_ident_char(c):
                append(out, str(c))
                self.i += 1
            elif c == '\\' and self.i + 1 < self.n:
                append(out, str(self.t[self.i + 1]))
                self.i += 2
            else:
                break
        return _s.join("", out)

    # Texte jusqu'à la parenthèse fermante correspondante (exclue).
    func paren_body():
        depth := 1
        start := self.i
        quote := null
        while self.i < self.n:
            c := self.t[self.i]
            if quote != null:
                if c == '\\':
                    self.i += 1
                elif c == quote:
                    quote = null
            elif c == '"' or c == '\'':
                quote = c
            elif c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    body := self.t[start:self.i]
                    self.i += 1
                    return body
            self.i += 1
        _fail(self.full, "« ( » sans « ) »")

    func selector_list(relative=false, stop=null):
        items := []
        while true:
            self.skip_ws()
            append(items, self.complex(relative))
            self.skip_ws()
            c := self.peek()
            if c == null:
                break
            if c == ',':
                self.i += 1
                continue
            _fail(self.full, "caractère inattendu « " + str(c) + " »")
        return SelectorList(items, self.t)

    func complex(relative):
        parts := []
        comb := null
        self.skip_ws()
        c0 := self.peek()
        if c0 == '>' or c0 == '+' or c0 == '~':
            if not relative:
                _fail(self.full, "combinateur sans sélecteur à gauche")
            comb = str(c0)
            self.i += 1
            self.skip_ws()
        while true:
            comp := self.compound()
            if comp.is_empty():
                _fail(self.full, "sélecteur vide")
            append(parts, (comb, comp))
            had_ws := self.skip_ws()
            c := self.peek()
            if c == null or c == ',' or c == ')':
                break
            if c == '>' or c == '+' or c == '~':
                comb = str(c)
                self.i += 1
                self.skip_ws()
            elif had_ws:
                comb = " "
            else:
                _fail(self.full, "caractère inattendu « " + str(c) + " »")
        return Complex(parts)

    func compound():
        cp := Compound()
        c := self.peek()
        if c == '*':
            self.i += 1
            cp.tag = "*"
        elif c == '&':
            self.i += 1
            cp.nesting = true
        elif c != null and (_is_ident_char(c) or c == '\\') and not (c >= '0' and c <= '9'):
            cp.tag = _s.lower(self.ident())
        if self.peek() == '|':
            # préfixe d'espace de noms ignoré (ns|tag)
            self.i += 1
            if self.peek() == '*':
                self.i += 1
                cp.tag = "*"
            else:
                cp.tag = _s.lower(self.ident())
        while self.i < self.n:
            c = self.peek()
            if c == '#':
                self.i += 1
                v := self.ident()
                if v == "":
                    _fail(self.full, "« # » sans identifiant")
                append(cp.ids, v)
            elif c == '.':
                self.i += 1
                v := self.ident()
                if v == "":
                    _fail(self.full, "« . » sans nom de classe")
                append(cp.classes, v)
            elif c == '[':
                self.i += 1
                append(cp.attrs, self.attribute())
            elif c == '&':
                self.i += 1
                cp.nesting = true
            elif c == ':':
                self.i += 1
                element := false
                if self.peek() == ':':
                    self.i += 1
                    element = true
                name := _s.lower(self.ident())
                if name == "":
                    _fail(self.full, "pseudo-classe sans nom")
                arg := null
                if self.peek() == '(':
                    self.i += 1
                    body := self.paren_body()
                    arg = self.pseudo_arg(name, body, element)
                if element or (name in LEGACY_PSEUDO_ELEMENTS and arg == null):
                    if cp.pseudo_element != null:
                        _fail(self.full, "deux pseudo-éléments")
                    cp.pseudo_element = (name, arg)
                else:
                    if cp.pseudo_element != null and not (name in ["hover", "focus", "active"]):
                        _fail(self.full, "pseudo-classe après un pseudo-élément")
                    append(cp.pseudos, (name, arg))
            else:
                break
        return cp

    func pseudo_arg(name, body, element):
        if element:
            return _s.trim(body)
        if name in SELECTOR_ARG:
            inner := _P(body, self.full)
            return inner.selector_list(name == "has")
        if name in NTH:
            return parse_nth(body, self.full)
        return _s.trim(body)

    func attribute():
        self.skip_ws()
        name := self.ident()
        if self.peek() == '|' and self.peek(1) != '=':
            self.i += 1
            name = self.ident()
        if name == "":
            _fail(self.full, "attribut sans nom")
        self.skip_ws()
        c := self.peek()
        if c == ']':
            self.i += 1
            return (_s.lower(name), null, null, null)
        op := null
        if c == '=':
            op = "="
            self.i += 1
        elif c != null and str(c) in ["~", "|", "^", "$", "*"] and self.peek(1) == '=':
            op = str(c) + "="
            self.i += 2
        else:
            _fail(self.full, "opérateur d'attribut invalide")
        self.skip_ws()
        q := self.peek()
        v := ""
        if q == '"' or q == '\'':
            self.i += 1
            out := []
            while self.i < self.n and self.t[self.i] != q:
                if self.t[self.i] == '\\' and self.i + 1 < self.n:
                    self.i += 1
                append(out, str(self.t[self.i]))
                self.i += 1
            if self.i >= self.n:
                _fail(self.full, "chaîne non fermée")
            self.i += 1
            v = _s.join("", out)
        else:
            v = self.ident()
            if v == "":
                _fail(self.full, "valeur d'attribut manquante")
        self.skip_ws()
        flag := null
        f := self.peek()
        if f == 'i' or f == 'I' or f == 's' or f == 'S':
            flag = _s.lower(str(f))
            self.i += 1
            self.skip_ws()
        if self.peek() != ']':
            _fail(self.full, "« [ » sans « ] »")
        self.i += 1
        return (_s.lower(name), op, v, flag)

# an+b [of S] -> Nth.
func parse_nth(text, full=null):
    f := full if full != null else text
    t := _s.trim(text)
    of := null
    k := _s.find(_s.lower(t), " of ")
    if k >= 0:
        of = _P(_s.trim(t[k + 4:len(t)]), f).selector_list()
        t = _s.trim(t[0:k])
    t = _s.lower(_s.replace(t, " ", ""))
    if t == "odd":
        return Nth(2, 1, of)
    if t == "even":
        return Nth(2, 0, of)
    n := _s.find(t, "n")
    if n < 0:
        return Nth(0, _int(t, f), of)
    a_text := t[0:n]
    b_text := t[n + 1:len(t)]
    a := 1
    if a_text == "-":
        a = -1
    elif a_text != "" and a_text != "+":
        a = _int(a_text, f)
    b := 0
    if b_text != "":
        b = _int(b_text, f)
    return Nth(a, b, of)

func _int(text, full):
    t := text
    sign := 1
    if _s.starts_with(t, "+"):
        t = t[1:len(t)]
    elif _s.starts_with(t, "-"):
        sign = -1
        t = t[1:len(t)]
    if t == "":
        _fail(full, "nombre attendu dans an+b")
    v := 0
    for c in t:
        if c < '0' or c > '9':
            _fail(full, "nombre attendu dans an+b (« " + text + " »)")
        v = v * 10 + (_s.ord(c) - 48)
    return sign * v

# Liste de sélecteurs ; relative : sélecteurs relatifs permis (« > a », pour :has et l'imbrication).
func parse(text, relative=false):
    if type(text) != "str" or _s.trim(text) == "":
        _err.selector_error("selector_parser", "sélecteur vide")
    return _P(_s.trim(text), text).selector_list(relative)

func is_valid(text):
    try:
        parse(text)
        return true
    catch e:
        return false

# ---------------------------------------------------------------- spécificité

func _max_spec(lst):
    best := (0, 0, 0)
    for c in lst.items:
        s := specificity(c)
        if compare_specificity(s, best) > 0:
            best = s
    return best

# (a, b, c) : identifiants ; classes, attributs, pseudo-classes ; types et pseudo-éléments.
func specificity(complex):
    a := 0
    b := 0
    c := 0
    for p in complex.parts:
        cp := p[1]
        a += len(cp.ids)
        b += len(cp.classes) + len(cp.attrs)
        if cp.tag != null and cp.tag != "*":
            c += 1
        if cp.pseudo_element != null:
            c += 1
        for ps in cp.pseudos:
            name := ps[0]
            if name == "where":
                continue
            if name in ["not", "is", "has", "matches", "any", "-webkit-any"]:
                m := _max_spec(ps[1])
                a += m[0]
                b += m[1]
                c += m[2]
                continue
            b += 1
            if name in NTH and ps[1] != null and ps[1].of != null:
                m := _max_spec(ps[1].of)
                a += m[0]
                b += m[1]
                c += m[2]
    return (a, b, c)

func compare_specificity(x, y):
    i := 0
    while i < 3:
        if x[i] > y[i]:
            return 1
        if x[i] < y[i]:
            return -1
        i += 1
    return 0

# Spécificité la plus forte d'une liste (ou d'un texte) de sélecteurs.
func max_specificity(sel):
    lst := parse(sel) if type(sel) == "str" else sel
    return _max_spec(lst)
