# ALEX STANDARD LIBRARY — office.templates
# Gabarits (publipostage) : moteur de substitution à la Mustache / Handlebars pour les textes, et remplissage de
# modèles bureautiques en conservant leur mise en forme — DOCX, XLSX, PPTX, ODT, ODS, ODP, HTML, Markdown, texte.
#
#   use office.templates as tpl
#   tpl.render("Bonjour {{client.nom | upper}}, total : {{total | money}}", {"client": {"nom": "Ada"}, "total": 1234.5})
#       # "Bonjour ADA, total : 1 234,50 €"
#   tpl.render("{{#each lignes}}- {{@index1}}. {{produit}} x{{qte}}\n{{/each}}", data)
#   tpl.fill("modele-facture.docx", data, "facture-042.docx")      # paragraphes, tableaux, en-têtes, pieds
#   tpl.fill("modele.xlsx", data, "rapport.xlsx")                  # {{valeur}} seule dans une cellule : type conservé
#   tpl.fill_many("lettre.odt", destinataires, "sortie/lettre-{{nom}}.odt")
#
# SYNTAXE    {{chemin}} (a.b.c, liste.0, this, ., ../parent, @index @index1 @first @last @key @root)
#            {{chemin | filtre | filtre(arg, arg)}} ou {{chemin | filtre:arg}}   {{! commentaire }}
#            {{{brut}}} (sans échappement en mode "html")   {{#if cond}} ... {{else}} ... {{/if}}
#            {{#unless cond}} ... {{/unless}}   {{#each liste}} ... {{else}} (liste vide) ... {{/each}}
#            {{#with objet}} ... {{/with}}
#            conditions : chemin, littéral, comparaisons == != > >= < <=, not, and, or (de gauche à droite)
# FILTRES    upper lower title capitalize trim default(v) date(fmt="dd/mm/yyyy") number(décimales=2)
#            money(symbole="€", décimales=2) percent(décimales=0) round(n=0) abs join(sep=", ") length first last
#            replace(a, b) truncate(n, suffixe="…") pad(n, car=" ") pad_left(n, car=" ") json yesno(oui="oui", non="non")
#            sum keys values sort reverse lines nl2br escape (dates : dd d mm m mmm mmmm yyyy yy HH H MM SS ;
#            nombres à la française par défaut : options {"locale": "en"} pour 1,234.50)
#            register_filter(nom, fn(valeur, args)) pour ajouter les vôtres
# API        render(gabarit, données, options=null) -> str   compile(gabarit) -> Template (render(données, options))
#            variables(gabarit) -> noms utilisés   check(gabarit) -> null ou message d'erreur
#            fill(modèle, données, sortie=null, options=null) -> chemin ou octets (format d'après l'extension)
#            fill_docx / fill_xlsx / fill_pptx / fill_odt / fill_ods / fill_odp (même signature)
#            fill_many(modèle, liste_de_données, motif_de_sortie, options=null) -> chemins (motif lui-même gabarit)
# Dans les documents : un paragraphe ne contenant que {{#each x}} (ou {{#if c}}) ouvre un bloc répété jusqu'au
#   paragraphe {{/each}} ; une ligne de tableau commençant par {{#each x}} et finissant par {{/each}} est répétée ;
#   un {{...}} réparti sur plusieurs segments de texte est recollé (le format du premier segment s'applique).
#   Classeurs : une ligne dont la première cellule commence par {{#each x}} est répétée vers le bas.
# options : {"mode": "text" | "html", "locale": "fr" | "en", "strict": false (variable absente -> erreur), "missing": ""}
# Erreurs : TemplateError (gabarit mal formé, variable absente en mode strict).

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use filesystem
use office.errors as errors
use office.utils as u
use office.core as core
use office.xml as x
use office.html as ohtml
use office.json as ojson
use office.word as word
use office.docx_paragraphs as dp
use office.docx_tables as dt
use office.excel as excel
use office.xlsx_cells as xc
use office.powerpoint as pp
use office.pptx_shapes as ps
use office.pptx_tables as ptb
use office.pptx_text as pt
use office.pptx_charts as pch
use office.xlsx_formulas as xf
use office.odf as odf
use office.ods as ods
use office.odp as odp

_filters := {}

func _fail(msg):
    raise("TemplateError", msg)

# ============================================================================================== analyse

# Jetons : ["text", s] ["var", expr, raw] ["open", helper, expr] ["else"] ["close", helper]
func _tokenize(src):
    toks := []
    s := u.to_text(src)
    pos := 0
    n := len(s)
    while pos < n:
        a := _n.str_find(s, "{{", pos)
        if a < 0:
            append(toks, ["text", _n.str_slice(s, pos, null)])
            break
        if a > pos:
            append(toks, ["text", _n.str_slice(s, pos, a)])
        raw := _n.str_slice(s, a, a + 3) == "{{{"
        close_tag := "}}}" if raw else "}}"
        b := _n.str_find(s, close_tag, a + (3 if raw else 2))
        if b < 0:
            _fail("balise non fermée à la position " + str(a) + " : « " + _n.str_slice(s, a, a + 30) + " »")
        inner := string.trim(_n.str_slice(s, a + (3 if raw else 2), b))
        pos = b + len(close_tag)
        if inner == "":
            _fail("balise vide à la position " + str(a))
        if string.starts_with(inner, "!"):
            continue
        if string.starts_with(inner, "#"):
            body := string.trim(_n.str_slice(inner, 1, null))
            sp := string.find(body, " ")
            helper := body if sp < 0 else _n.str_slice(body, 0, sp)
            expr := "" if sp < 0 else string.trim(_n.str_slice(body, sp + 1, null))
            if helper != "each" and helper != "if" and helper != "unless" and helper != "with":
                _fail("bloc inconnu : #" + helper + " (each, if, unless, with)")
            if expr == "":
                _fail("#" + helper + " sans expression")
            append(toks, ["open", helper, expr])
            continue
        if string.starts_with(inner, "/"):
            append(toks, ["close", string.trim(_n.str_slice(inner, 1, null))])
            continue
        if inner == "else" or inner == "^":
            append(toks, ["else"])
            continue
        append(toks, ["var", inner, raw])
    return toks

# Arbre : nœuds ["text", s] ["var", expr, raw] ["block", helper, expr, enfants, enfants_else]
func _parse(toks):
    root := []
    stack := [[null, root, null]]
    for t in toks:
        top := stack[len(stack) - 1]
        k := t[0]
        if k == "text" or k == "var":
            append(top[1], t)
        elif k == "open":
            node := ["block", t[1], t[2], [], []]
            append(top[1], node)
            append(stack, [node, node[3], t[1]])
        elif k == "else":
            if top[0] == null:
                _fail("{{else}} en dehors d'un bloc")
            top[1] = top[0][4]
        elif k == "close":
            if top[0] == null:
                _fail("{{/" + t[1] + "}} sans bloc ouvert")
            if top[2] != t[1]:
                _fail("{{/" + t[1] + "}} ferme le bloc #" + top[2])
            collections.pop(stack)
    if len(stack) > 1:
        _fail("bloc #" + stack[len(stack) - 1][2] + " non fermé")
    return root

class Template:
    func init(source):
        self.source = u.to_text(source)
        self.tree = _parse(_tokenize(self.source))

    func render(data, options=null):
        o := options if options != null else {}
        out := []
        _render_nodes(self.tree, [_frame(data, {})], out, o, data)
        return string.join("", out)

func compile(source):
    return Template(source)

func render(source, data, options=null):
    if type(source) == "str" and not string.contains(source, "{{"):
        return source
    return Template(source).render(data, options)

func check(source):
    try:
        Template(source)
        return null
    catch e:
        return e.message

func _collect_vars(nodes, out):
    for nd in nodes:
        if nd[0] == "var":
            p := _split_pipes(nd[1])[0]
            append(out, string.trim(p))
        elif nd[0] == "block":
            append(out, nd[2])
            _collect_vars(nd[3], out)
            _collect_vars(nd[4], out)

func variables(source):
    out := []
    _collect_vars(Template(source).tree, out)
    uniq := []
    for v in out:
        dup := false
        for w in uniq:
            if w == v:
                dup = true
        if not dup:
            append(uniq, v)
    return uniq

# ============================================================================================== évaluation

func _frame(value, meta):
    return {"value": value, "meta": meta}

func _truthy(v):
    if v == null or v == false:
        return false
    t := type(v)
    if t == "str":
        return v != ""
    if t == "int" or t == "float":
        return v != 0
    if t == "list" or t == "tuple" or t == "dict":
        return len(v) > 0
    return true

func _lookup_in(v, name):
    if v == null:
        return [false, null]
    t := type(v)
    if t == "dict":
        if contains_key(v, name):
            return [true, v[name]]
        return [false, null]
    if t == "list" or t == "tuple":
        n := _n.num_parse(name)
        if n != null and type(n) == "int" and n >= 0 and n < len(v):
            return [true, v[n]]
        if name == "length" or name == "count":
            return [true, len(v)]
        return [false, null]
    if t == "str" and (name == "length" or name == "count"):
        return [true, len(v)]
    return [false, null]

func _resolve(path, stack, root, o):
    p := string.trim(path)
    if p == "this" or p == ".":
        return stack[len(stack) - 1]["value"]
    if string.starts_with(p, "@"):
        name := _n.str_slice(p, 1, null)
        if name == "root":
            return root
        if string.starts_with(name, "root."):
            return _resolve(_n.str_slice(name, 5, null), [_frame(root, {})], root, o)
        k := len(stack) - 1
        while k >= 0:
            m := stack[k]["meta"]
            if contains_key(m, name):
                return m[name]
            k = k - 1
        return null
    level := len(stack) - 1
    while string.starts_with(p, "../"):
        p = _n.str_slice(p, 3, null)
        level = level - 1 if level > 0 else 0
    if string.starts_with(p, "this."):
        p = _n.str_slice(p, 5, null)
        parts := string.split(p, ".")
        cur := stack[level]["value"]
        for part in parts:
            r := _lookup_in(cur, part)
            if not r[0]:
                return _missing(path, o)
            cur = r[1]
        return cur
    parts := string.split(p, ".")
    # premier segment : cherché du contexte courant vers la racine
    k := level
    while k >= 0:
        r := _lookup_in(stack[k]["value"], parts[0])
        if r[0]:
            cur := r[1]
            i := 1
            while i < len(parts):
                r2 := _lookup_in(cur, parts[i])
                if not r2[0]:
                    return _missing(path, o)
                cur = r2[1]
                i = i + 1
            return cur
        k = k - 1
    return _missing(path, o)

func _missing(path, o):
    if u.get(o, "strict", false):
        _fail("variable absente : " + path)
    return null

# Découpe aux « | » hors guillemets et parenthèses.
func _split_pipes(expr):
    parts := []
    buf := ""
    q := ""
    depth := 0
    for c in expr:
        ch := str(c)
        if q != "":
            buf = buf + ch
            if ch == q:
                q = ""
            continue
        if ch == "\"" or ch == "'":
            q = ch
            buf = buf + ch
        elif ch == "(":
            depth = depth + 1
            buf = buf + ch
        elif ch == ")":
            depth = depth - 1
            buf = buf + ch
        elif ch == "|" and depth == 0:
            append(parts, string.trim(buf))
            buf = ""
        else:
            buf = buf + ch
    append(parts, string.trim(buf))
    return parts

func _split_args(s):
    args := []
    buf := ""
    q := ""
    for c in s:
        ch := str(c)
        if q != "":
            buf = buf + ch
            if ch == q:
                q = ""
            continue
        if ch == "\"" or ch == "'":
            q = ch
            buf = buf + ch
        elif ch == ",":
            append(args, string.trim(buf))
            buf = ""
        else:
            buf = buf + ch
    if string.trim(buf) != "" or len(args) > 0:
        append(args, string.trim(buf))
    return args

func _literal(tok, stack, root, o):
    t := string.trim(tok)
    if len(t) >= 2 and ((string.starts_with(t, "\"") and string.ends_with(t, "\"")) or (string.starts_with(t, "'") and string.ends_with(t, "'"))):
        return _n.str_slice(t, 1, len(t) - 1)
    if t == "true" or t == "vrai":
        return true
    if t == "false" or t == "faux":
        return false
    if t == "null" or t == "nul":
        return null
    n := _n.num_parse(t)
    if n != null:
        return n
    return _resolve(t, stack, root, o)

func _value(expr, stack, root, o):
    pipes := _split_pipes(expr)
    v := _literal(pipes[0], stack, root, o)
    i := 1
    while i < len(pipes):
        f := pipes[i]
        name := f
        args := []
        lp := string.find(f, "(")
        cp := string.find(f, ":")
        if lp > 0 and string.ends_with(f, ")"):
            name = string.trim(_n.str_slice(f, 0, lp))
            for a in _split_args(_n.str_slice(f, lp + 1, len(f) - 1)):
                append(args, _literal(a, stack, root, o))
        elif cp > 0:
            name = string.trim(_n.str_slice(f, 0, cp))
            for a in _split_args(_n.str_slice(f, cp + 1, null)):
                append(args, _literal(a, stack, root, o))
        v = _apply_filter(name, v, args, o)
        i = i + 1
    return v

# Condition : not, and, or, comparaisons.
func _cond(expr, stack, root, o):
    e := string.trim(expr)
    # or / and (de gauche à droite, hors guillemets)
    parts := _split_words(e, " or ")
    if len(parts) > 1:
        for p in parts:
            if _cond(p, stack, root, o):
                return true
        return false
    parts = _split_words(e, " and ")
    if len(parts) > 1:
        for p in parts:
            if not _cond(p, stack, root, o):
                return false
        return true
    if string.starts_with(e, "not "):
        return not _cond(_n.str_slice(e, 4, null), stack, root, o)
    if string.starts_with(e, "!"):
        return not _cond(_n.str_slice(e, 1, null), stack, root, o)
    for op in [" == ", " != ", " >= ", " <= ", " > ", " < "]:
        cmp := _split_words(e, op)
        if len(cmp) == 2:
            a := _value(cmp[0], stack, root, o)
            b := _value(cmp[1], stack, root, o)
            return _compare(a, b, string.trim(op))
    return _truthy(_value(e, stack, root, o))

func _compare(a, b, op):
    if op == "==":
        return a == b or (_is_num(a) and _is_num(b) and to_float(a) == to_float(b))
    if op == "!=":
        return not _compare(a, b, "==")
    if a == null or b == null:
        return false
    if _is_num(a) and _is_num(b):
        fa := to_float(a)
        fb := to_float(b)
        if op == ">":
            return fa > fb
        if op == ">=":
            return fa >= fb
        if op == "<":
            return fa < fb
        return fa <= fb
    sa := u.to_text(a)
    sb := u.to_text(b)
    if op == ">":
        return sa > sb
    if op == ">=":
        return sa >= sb
    if op == "<":
        return sa < sb
    return sa <= sb

func _is_num(v):
    return type(v) == "int" or type(v) == "float"

func _split_words(e, sep):
    parts := []
    buf := ""
    q := ""
    i := 0
    n := len(e)
    m := len(sep)
    while i < n:
        ch := str(e[i])
        if q != "":
            buf = buf + ch
            if ch == q:
                q = ""
            i = i + 1
            continue
        if ch == "\"" or ch == "'":
            q = ch
            buf = buf + ch
            i = i + 1
            continue
        if _n.str_slice(e, i, i + m) == sep:
            append(parts, buf)
            buf = ""
            i = i + m
            continue
        buf = buf + ch
        i = i + 1
    append(parts, buf)
    return parts

func _render_nodes(nodes, stack, out, o, root):
    for nd in nodes:
        k := nd[0]
        if k == "text":
            append(out, nd[1])
        elif k == "var":
            v := _value(nd[1], stack, root, o)
            s := _to_str(v, o)
            if u.get(o, "mode", "text") == "html" and not nd[2]:
                s = ohtml.escape(s)
            append(out, s)
        else:
            helper := nd[1]
            if helper == "if" or helper == "unless":
                c := _cond(nd[2], stack, root, o)
                if helper == "unless":
                    c = not c
                _render_nodes(nd[3] if c else nd[4], stack, out, o, root)
            elif helper == "with":
                v := _value(nd[2], stack, root, o)
                if _truthy(v):
                    append(stack, _frame(v, {}))
                    _render_nodes(nd[3], stack, out, o, root)
                    collections.pop(stack)
                else:
                    _render_nodes(nd[4], stack, out, o, root)
            elif helper == "each":
                items := _value(nd[2], stack, root, o)
                seq := _items(items)
                if len(seq) == 0:
                    _render_nodes(nd[4], stack, out, o, root)
                    continue
                i := 0
                for it in seq:
                    meta := {"index": i, "index1": i + 1, "first": i == 0, "last": i == len(seq) - 1, "key": it[0], "odd": i % 2 == 1, "even": i % 2 == 0}
                    append(stack, _frame(it[1], meta))
                    _render_nodes(nd[3], stack, out, o, root)
                    collections.pop(stack)
                    i = i + 1

# Éléments d'une itération : [[clé, valeur]...] (listes : indice ; dicts : clé)
func _items(v):
    out := []
    if v == null:
        return out
    t := type(v)
    if t == "list" or t == "tuple":
        i := 0
        for e in v:
            append(out, [i, e])
            i = i + 1
    elif t == "dict":
        for k in keys(v):
            append(out, [k, v[k]])
    elif t == "int" and v > 0:
        i := 0
        while i < v:
            append(out, [i, i + 1])
            i = i + 1
    return out

func _to_str(v, o):
    if v == null:
        return u.get(o, "missing", "")
    t := type(v)
    if t == "str":
        return v
    if t == "bool":
        return ("vrai" if v else "faux") if u.get(o, "locale", "fr") == "fr" else ("true" if v else "false")
    if t == "float" or t == "int":
        if t == "float" and v == to_float(to_int(v)) and v < 1000000000000000.0 and v > -1000000000000000.0:
            return str(to_int(v))
        return _locale_num(str(v), o)
    if u.is_date_dict(v):
        return _date(v, "dd/mm/yyyy" if u.get(o, "locale", "fr") == "fr" else "yyyy-mm-dd", o)
    if xc.is_error(v):
        return v.code
    return u.to_text(v)

func _locale_num(s, o):
    if u.get(o, "locale", "fr") == "fr":
        return string.replace(s, ".", ",")
    return s

# ============================================================================================== filtres

func register_filter(name, fn):
    _filters[name] = fn

func _num_text(v, dec, grouping, o):
    fr := u.get(o, "locale", "fr") == "fr"
    x0 := to_float(v)
    neg := x0 < 0.0
    if neg:
        x0 = -x0
    r := u.round_to(x0, dec)
    ip := to_int(r)
    frac := r - to_float(ip)
    digits := str(ip)
    if grouping:
        groups := []
        while len(digits) > 3:
            collections.insert(groups, 0, _n.str_slice(digits, len(digits) - 3, null))
            digits = _n.str_slice(digits, 0, len(digits) - 3)
        collections.insert(groups, 0, digits)
        digits = string.join(" " if fr else ",", groups)
    s := digits
    if dec > 0:
        f := to_int(u.round_to(frac * math_pow10(dec), 0))
        if f >= to_int(math_pow10(dec)):
            f = 0
        s = s + ("," if fr else ".") + u.pad_left(str(f), dec, "0")
    return ("-" if neg and r != 0.0 else "") + s

func math_pow10(n):
    v := 1.0
    k := 0
    while k < n:
        v = v * 10.0
        k = k + 1
    return v

const _MONTHS_FR := ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
const _MONTHS_EN := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

func _date(v, fmt, o):
    f := null
    try:
        f = u.date_parts(v)
    catch e:
        return u.to_text(v)
    months := _MONTHS_FR if u.get(o, "locale", "fr") == "fr" else _MONTHS_EN
    out := ""
    cs := u.chars(fmt)
    i := 0
    n := len(cs)
    while i < n:
        c := cs[i]
        j := i
        while j < n and cs[j] == c:
            j = j + 1
        run := j - i
        if c == "d":
            out = out + (u.pad_left(str(f["day"]), 2, "0") if run >= 2 else str(f["day"]))
        elif c == "m":
            if run >= 4:
                out = out + months[f["month"] - 1]
            elif run == 3:
                out = out + u.str_slice(months[f["month"] - 1], 0, 3)
            elif run == 2:
                out = out + u.pad_left(str(f["month"]), 2, "0")
            else:
                out = out + str(f["month"])
        elif c == "y":
            out = out + (str(f["year"]) if run >= 3 else u.pad_left(str(f["year"] % 100), 2, "0"))
        elif c == "H":
            out = out + (u.pad_left(str(f["hour"]), 2, "0") if run >= 2 else str(f["hour"]))
        elif c == "M":
            out = out + u.pad_left(str(f["minute"]), 2, "0")
        elif c == "S":
            out = out + u.pad_left(str(f["second"]), 2, "0")
        else:
            out = out + string.repeat(c, run)
        i = j
    return out

func _arg(args, i, fallback):
    if i < len(args) and args[i] != null:
        return args[i]
    return fallback

func _apply_filter(name, v, args, o):
    if contains_key(_filters, name):
        return _filters[name](v, args)
    if name == "upper":
        return string.upper(_to_str(v, o))
    if name == "lower":
        return string.lower(_to_str(v, o))
    if name == "capitalize":
        s := _to_str(v, o)
        return string.upper(u.str_slice(s, 0, 1)) + u.str_slice(s, 1, null) if s != "" else s
    if name == "title":
        words := []
        for w in string.split(_to_str(v, o), " "):
            append(words, string.upper(u.str_slice(w, 0, 1)) + string.lower(u.str_slice(w, 1, null)) if w != "" else w)
        return string.join(" ", words)
    if name == "trim":
        return string.trim(_to_str(v, o))
    if name == "default":
        return v if _truthy(v) else _arg(args, 0, "")
    if name == "date":
        if v == null or v == "":
            return ""
        return _date(v, _arg(args, 0, "dd/mm/yyyy" if u.get(o, "locale", "fr") == "fr" else "yyyy-mm-dd"), o)
    if name == "number":
        if not _is_num(v):
            n := _n.num_parse(_to_str(v, o))
            if n == null:
                return _to_str(v, o)
            v = n
        return _num_text(v, to_int(_arg(args, 0, 2)), _arg(args, 1, true), o)
    if name == "money" or name == "currency":
        if not _is_num(v):
            n := _n.num_parse(_to_str(v, o))
            if n == null:
                return _to_str(v, o)
            v = n
        sym := _arg(args, 0, "€")
        txt := _num_text(v, to_int(_arg(args, 1, 2)), true, o)
        if sym == "$" or sym == "£" or u.get(o, "locale", "fr") != "fr":
            return sym + txt if not string.starts_with(txt, "-") else "-" + sym + _n.str_slice(txt, 1, null)
        return txt + " " + sym
    if name == "percent":
        if not _is_num(v):
            return _to_str(v, o)
        txt := _num_text(to_float(v) * 100.0, to_int(_arg(args, 0, 0)), true, o)
        return txt + (" %" if u.get(o, "locale", "fr") == "fr" else "%")
    if name == "round":
        if not _is_num(v):
            return v
        d := to_int(_arg(args, 0, 0))
        r := u.round_to(to_float(v), d)
        return to_int(r) if d == 0 else r
    if name == "abs":
        if _is_num(v):
            return -v if v < 0 else v
        return v
    if name == "join":
        if type(v) != "list":
            return _to_str(v, o)
        parts := []
        for e in v:
            append(parts, _to_str(e, o))
        return string.join(_arg(args, 0, ", "), parts)
    if name == "length" or name == "count" or name == "size":
        if v == null:
            return 0
        return len(v)
    if name == "first":
        return v[0] if (type(v) == "list" and len(v) > 0) else null
    if name == "last":
        return v[len(v) - 1] if (type(v) == "list" and len(v) > 0) else null
    if name == "replace":
        return string.replace(_to_str(v, o), u.to_text(_arg(args, 0, "")), u.to_text(_arg(args, 1, "")))
    if name == "truncate":
        s := _to_str(v, o)
        n := to_int(_arg(args, 0, 50))
        if len(s) <= n:
            return s
        return u.str_slice(s, 0, n) + _arg(args, 1, "…")
    if name == "pad":
        return u.pad_right(_to_str(v, o), to_int(_arg(args, 0, 10)), _arg(args, 1, " "))
    if name == "pad_left":
        return u.pad_left(_to_str(v, o), to_int(_arg(args, 0, 10)), _arg(args, 1, " "))
    if name == "json":
        return ojson.stringify(ojson.to_json_value(v))
    if name == "yesno":
        return _arg(args, 0, "oui") if _truthy(v) else _arg(args, 1, "non")
    if name == "sum":
        total := 0
        if type(v) == "list":
            for e in v:
                if _is_num(e):
                    total = total + e
                elif len(args) > 0 and type(e) == "dict" and _is_num(u.get(e, args[0], null)):
                    total = total + e[args[0]]
        return total
    if name == "keys":
        return keys(v) if type(v) == "dict" else []
    if name == "values":
        out := []
        if type(v) == "dict":
            for k in keys(v):
                append(out, v[k])
        return out
    if name == "sort":
        if type(v) != "list":
            return v
        if len(args) > 0:
            return u.sort(v, (e) => u.get(e, args[0], null) if type(e) == "dict" else e)
        return u.sort(v, (e) => e)
    if name == "reverse":
        if type(v) == "list":
            out := []
            k := len(v) - 1
            while k >= 0:
                append(out, v[k])
                k = k - 1
            return out
        s := _to_str(v, o)
        return string.join("", _reverse_chars(s))
    if name == "lines":
        return string.split(_to_str(v, o), "\n")
    if name == "nl2br":
        return string.replace(ohtml.escape(_to_str(v, o)), "\n", "<br>")
    if name == "escape":
        return ohtml.escape(_to_str(v, o))
    _fail("filtre inconnu : " + name)

func _reverse_chars(s):
    cs := u.chars(s)
    out := []
    k := len(cs) - 1
    while k >= 0:
        append(out, cs[k])
        k = k - 1
    return out

# Valeur brute d'une cellule « {{expr}} » seule (type conservé), sinon null.
func _single_expr(text):
    t := string.trim(text)
    if not string.starts_with(t, "{{") or not string.ends_with(t, "}}"):
        return null
    if string.starts_with(t, "{{#") or string.starts_with(t, "{{/") or string.starts_with(t, "{{!"):
        return null
    inner := _n.str_slice(t, 2, len(t) - 2)
    if string.contains(inner, "{{") or string.contains(inner, "}}"):
        return null
    if string.starts_with(inner, "{") and string.ends_with(inner, "}"):
        inner = _n.str_slice(inner, 1, len(inner) - 1)
    return string.trim(inner)

func eval_expr(expr, data, options=null):
    return _value(expr, [_frame(data, {})], data, options if options != null else {})

# ============================================================================================== segments de texte

# Recolle les balises {{...}} réparties sur plusieurs segments. texts : liste de textes ; renvoie la nouvelle liste.
func _normalize(texts):
    full := string.join("", texts)
    if not string.contains(full, "{{"):
        return texts
    owner := []
    k := 0
    for t in texts:
        for c in t:
            append(owner, k)
        k = k + 1
    cs := u.chars(full)
    n := len(cs)
    i := 0
    while i + 1 < n:
        if cs[i] == "{" and cs[i + 1] == "{":
            j := i + 2
            while j + 1 < n and not (cs[j] == "}" and cs[j + 1] == "}"):
                j = j + 1
            end := j + 2 if j + 1 < n else n
            while end < n and cs[end] == "}":
                end = end + 1
            o0 := owner[i]
            q := i
            while q < end:
                owner[q] = o0
                q = q + 1
            i = end
            continue
        i = i + 1
    out := []
    for t in texts:
        append(out, [])
    q := 0
    while q < n:
        append(out[owner[q]], cs[q])
        q = q + 1
    res := []
    for chars_ in out:
        append(res, string.join("", chars_))
    return res

func _has_block_tag(s):
    return string.contains(s, "{{#") or string.contains(s, "{{/") or string.contains(s, "{{else}}")

# Marqueur de bloc seul dans un paragraphe : ["open", helper, expr] / ["else"] / ["close", helper] ou null
func _marker(text):
    t := string.trim(text)
    if not string.starts_with(t, "{{") or not string.ends_with(t, "}}"):
        return null
    inner := string.trim(_n.str_slice(t, 2, len(t) - 2))
    if string.contains(inner, "{{") or string.contains(inner, "}}"):
        return null
    if string.starts_with(inner, "#"):
        body := string.trim(_n.str_slice(inner, 1, null))
        sp := string.find(body, " ")
        if sp < 0:
            return null
        return ["open", _n.str_slice(body, 0, sp), string.trim(_n.str_slice(body, sp + 1, null))]
    if string.starts_with(inner, "/"):
        return ["close", string.trim(_n.str_slice(inner, 1, null))]
    if inner == "else":
        return ["else"]
    return null

# Développe les blocs de niveau paragraphe dans une liste d'éléments. text_of(el) -> texte ; clone(el) -> copie ;
# fill(el, stack) remplit les balises d'un élément. Renvoie la nouvelle liste.
func _expand(items, stack, root, o, text_of, clone, fill):
    out := []
    i := 0
    n := len(items)
    while i < n:
        el := items[i]
        mk := _marker(text_of(el))
        if mk != null and mk[0] == "open":
            # recherche du marqueur fermant correspondant
            depth := 1
            j := i + 1
            else_at := -1
            while j < n:
                m2 := _marker(text_of(items[j]))
                if m2 != null:
                    if m2[0] == "open":
                        depth = depth + 1
                    elif m2[0] == "close":
                        depth = depth - 1
                        if depth == 0:
                            break
                    elif m2[0] == "else" and depth == 1:
                        else_at = j
                j = j + 1
            if j >= n:
                _fail("bloc #" + mk[1] + " non fermé dans le document")
            body := []
            alt := []
            k := i + 1
            while k < j:
                if else_at >= 0 and k >= else_at:
                    if k > else_at:
                        append(alt, items[k])
                else:
                    append(body, items[k])
                k = k + 1
            helper := mk[1]
            if helper == "each":
                seq := _items(_value(mk[2], stack, root, o))
                if len(seq) == 0:
                    for e in _expand(_clone_all(alt, clone), stack, root, o, text_of, clone, fill):
                        append(out, e)
                idx := 0
                for it in seq:
                    meta := {"index": idx, "index1": idx + 1, "first": idx == 0, "last": idx == len(seq) - 1, "key": it[0], "odd": idx % 2 == 1, "even": idx % 2 == 0}
                    append(stack, _frame(it[1], meta))
                    for e in _expand(_clone_all(body, clone), stack, root, o, text_of, clone, fill):
                        append(out, e)
                    collections.pop(stack)
                    idx = idx + 1
            elif helper == "with":
                v := _value(mk[2], stack, root, o)
                if _truthy(v):
                    append(stack, _frame(v, {}))
                    for e in _expand(_clone_all(body, clone), stack, root, o, text_of, clone, fill):
                        append(out, e)
                    collections.pop(stack)
                else:
                    for e in _expand(_clone_all(alt, clone), stack, root, o, text_of, clone, fill):
                        append(out, e)
            else:
                c := _cond(mk[2], stack, root, o)
                if helper == "unless":
                    c = not c
                for e in _expand(_clone_all(body if c else alt, clone), stack, root, o, text_of, clone, fill):
                    append(out, e)
            i = j + 1
            continue
        fill(el, stack)
        append(out, el)
        i = i + 1
    return out

func _clone_all(items, clone):
    out := []
    for e in items:
        append(out, clone(e))
    return out

func _render_in(text, stack, root, o):
    if not string.contains(text, "{{"):
        return text
    t := Template(text)
    out := []
    _render_nodes(t.tree, stack, out, o, root)
    return string.join("", out)

# ============================================================================================== DOCX

class _DocxFiller:
    func init(root, o):
        self.root = root
        self.o = o

    func text_of(b):
        if isinstance(b, dp.Paragraph):
            return b.text()
        return ""

    func clone(b):
        return b.copy()

    func fill_runs(p, stack):
        runs := []
        for r in p.runs:
            if r.kind == "text":
                append(runs, r)
        if len(runs) == 0:
            return null
        texts := []
        for r in runs:
            append(texts, r.text)
        full := string.join("", texts)
        if not string.contains(full, "{{"):
            return null
        if _has_block_tag(full):
            runs[0].text = _render_in(full, stack, self.root, self.o)
            k := 1
            while k < len(runs):
                runs[k].text = ""
                k = k + 1
            return null
        norm := _normalize(texts)
        k := 0
        for r in runs:
            r.text = _render_in(norm[k], stack, self.root, self.o)
            k = k + 1

    func fill(b, stack):
        if isinstance(b, dp.Paragraph):
            self.fill_runs(b, stack)
        elif isinstance(b, dt.Table):
            self.fill_table(b, stack)

    func fill_table(t, stack):
        rows := []
        for row in t.rows:
            first := row.cells[0].text() if len(row.cells) > 0 else ""
            last := row.cells[len(row.cells) - 1].text() if len(row.cells) > 0 else ""
            ft := string.trim(first)
            if string.starts_with(ft, "{{#each ") and string.ends_with(string.trim(last), "{{/each}}"):
                close := _n.str_find(ft, "}}", 0)
                expr := string.trim(_n.str_slice(ft, 8, close))
                seq := _items(_value(expr, stack, self.root, self.o))
                idx := 0
                for it in seq:
                    meta := {"index": idx, "index1": idx + 1, "first": idx == 0, "last": idx == len(seq) - 1, "key": it[0], "odd": idx % 2 == 1, "even": idx % 2 == 0}
                    copy := row.copy()
                    _strip_row_markers_docx(copy)
                    append(stack, _frame(it[1], meta))
                    for c in copy.cells:
                        c.paragraphs = self.expand(c.paragraphs, stack)
                    collections.pop(stack)
                    append(rows, copy)
                    idx = idx + 1
                continue
            for c in row.cells:
                c.paragraphs = self.expand(c.paragraphs, stack)
            append(rows, row)
        t.rows = rows

    func expand(items, stack):
        return _expand(items, stack, self.root, self.o, (b) => self.text_of(b), (b) => self.clone(b), (b, st) => self.fill(b, st))

func _strip_row_markers_docx(row):
    first := row.cells[0]
    for p in first.paragraphs:
        if isinstance(p, dp.Paragraph):
            for r in p.runs:
                if r.kind == "text" and string.contains(r.text, "{{#each"):
                    a := _n.str_find(r.text, "{{#each", 0)
                    b := _n.str_find(r.text, "}}", a)
                    r.text = _n.str_slice(r.text, 0, a) + _n.str_slice(r.text, b + 2, null)
            break
    # le marqueur peut être réparti sur plusieurs segments : on recolle d'abord
    last := row.cells[len(row.cells) - 1]
    for p in last.paragraphs:
        if isinstance(p, dp.Paragraph):
            texts := []
            for r in p.runs:
                append(texts, r.text if r.kind == "text" else "")
            norm := _normalize(texts)
            k := 0
            for r in p.runs:
                if r.kind == "text":
                    r.text = string.replace(norm[k], "{{/each}}", "")
                k = k + 1

func fill_docx(src, data, out=null, options=null):
    o := options if options != null else {}
    d := word.open(src)
    f := _DocxFiller(data, o)
    # recolle d'abord les balises (les marqueurs de blocs doivent être lisibles par paragraphe)
    for p in d.paragraphs(true):
        _prenormalize_docx(p)
    stack := [_frame(data, {})]
    d.body = f.expand(d.body, stack)
    d.header = f.expand(d.header, stack)
    d.footer = f.expand(d.footer, stack)
    d.first_header = f.expand(d.first_header, stack)
    d.first_footer = f.expand(d.first_footer, stack)
    if d.metadata.title != "":
        d.metadata.title = _render_in(d.metadata.title, stack, data, o)
    if out == null:
        return d.to_bytes()
    filesystem.ensure_parent(out)
    d.save(out)
    return out

func _prenormalize_docx(p):
    texts := []
    for r in p.runs:
        append(texts, r.text if r.kind == "text" else "")
    if not string.contains(string.join("", texts), "{{"):
        return null
    norm := _normalize(texts)
    k := 0
    for r in p.runs:
        if r.kind == "text":
            r.text = norm[k]
        k = k + 1

# ============================================================================================== XLSX / ODS

func _fill_cell_value(v, stack, root, o):
    if type(v) != "str" or not string.contains(v, "{{"):
        return v
    se := _single_expr(v)
    if se != null:
        r := _value(se, stack, root, o)
        if r == null:
            return null
        t := type(r)
        if t == "int" or t == "float" or t == "bool" or u.is_date_dict(r):
            return r
        return _to_str(r, o)
    return _render_in(v, stack, root, o)

func fill_workbook(wb, data, options=null):
    o := options if options != null else {}
    stack := [_frame(data, {})]
    for ws in wb.sheets:
        r := 1
        while r <= ws.max_row():
            first := ws.find_cell(r, 1)
            ft := first.value if first != null and type(first.value) == "str" else ""
            if string.starts_with(string.trim(ft), "{{#each "):
                close := _n.str_find(string.trim(ft), "}}", 0)
                expr := string.trim(_n.str_slice(string.trim(ft), 8, close))
                seq := _items(_value(expr, stack, data, o))
                # cellules modèles de la ligne
                tmpl := []
                c := 1
                mc := ws.max_col()
                while c <= mc:
                    cell := ws.find_cell(r, c)
                    if cell != null:
                        v := cell.value
                        if type(v) == "str":
                            if string.contains(v, "{{#each"):
                                a := _n.str_find(v, "{{#each", 0)
                                b := _n.str_find(v, "}}", a)
                                v = _n.str_slice(v, 0, a) + _n.str_slice(v, b + 2, null)
                            v = string.replace(v, "{{/each}}", "")
                        fm := cell.formula
                        if fm != null:
                            fm = string.replace(fm, "{{/each}}", "")
                        append(tmpl, [c, v, cell.style, fm])
                    c = c + 1
                n := len(seq)
                if n == 0:
                    ws.delete_rows(r, 1)
                    continue
                if n > 1:
                    ws.insert_rows(r + 1, n - 1)
                    # formules des autres cellules : lignes décalées, plages finissant sur la ligne modèle étendues
                    for oc in ws.cells():
                        if oc.formula != null and (oc.row < r or oc.row >= r + n):
                            oc.formula = _adjust_rows(oc.formula, r, n - 1)
                idx := 0
                for it in seq:
                    meta := {"index": idx, "index1": idx + 1, "first": idx == 0, "last": idx == n - 1, "key": it[0], "odd": idx % 2 == 1, "even": idx % 2 == 0}
                    append(stack, _frame(it[1], meta))
                    for tc in tmpl:
                        cell := ws.cell(r + idx, tc[0])
                        cell.style = tc[2]
                        if tc[3] != null:
                            cell.formula = _shift_formula(tc[3], idx)
                            cell.value = null
                        else:
                            cell.value = _fill_cell_value(tc[1], stack, data, o)
                    collections.pop(stack)
                    idx = idx + 1
                r = r + n
                continue
            c := 1
            mc := ws.max_col()
            while c <= mc:
                cell := ws.find_cell(r, c)
                if cell != null and type(cell.value) == "str" and string.contains(cell.value, "{{"):
                    cell.value = _fill_cell_value(cell.value, stack, data, o)
                c = c + 1
            r = r + 1
        if string.contains(ws.name, "{{"):
            ws.name = _render_in(ws.name, stack, data, o)
    return wb

# Références d'une formule après insertion de `extra` lignes sous la ligne `row` : lignes > row décalées ; une plage
# A{a}:B{row} (a <= row) est étendue jusqu'à row + extra.
func _adjust_rows(f, row, extra):
    cs := u.chars(f)
    n := len(cs)
    out := []
    i := 0
    while i < n:
        c := cs[i]
        if c == "\"":
            j := i + 1
            while j < n and cs[j] != "\"":
                j = j + 1
            append(out, string.join("", _n.bytes_slice(cs, i, j + 1 if j < n else n)))
            i = j + 1
            continue
        prev := cs[i - 1] if i > 0 else ""
        r1 := ods._cell_at(cs, i) if (prev == "" or not (ods._is_name(prev) or prev == "$")) else null
        if r1 != null and r1[2] == "cell":
            e := r1[1]
            if e < n and (cs[e] == "(" or ods._is_name(cs[e])):
                r1 = null
        if r1 != null and r1[2] == "cell":
            e := r1[1]
            r2 := null
            if e < n and cs[e] == ":":
                r2 = ods._cell_at(cs, e + 1)
                if r2 != null and r2[2] != "cell":
                    r2 = null
            a := u.parse_cell(r1[0])
            if r2 != null:
                b := u.parse_cell(r2[0])
                ra := a["row"] + extra if a["row"] > row else a["row"]
                rb := b["row"] + extra if b["row"] >= row and a["row"] <= row else (b["row"] + extra if b["row"] > row else b["row"])
                append(out, u.cell_ref(ra, a["col"], a["abs_row"], a["abs_col"]) + ":" + u.cell_ref(rb, b["col"], b["abs_row"], b["abs_col"]))
                i = r2[1]
            else:
                ra := a["row"] + extra if a["row"] > row else a["row"]
                append(out, u.cell_ref(ra, a["col"], a["abs_row"], a["abs_col"]))
                i = e
            continue
        append(out, c)
        i = i + 1
    return string.join("", out)

func _shift_formula(f, rows):
    if rows == 0:
        return f
    try:
        return xf.shift_formula(f, rows, 0)
    catch e:
        return f

func fill_xlsx(src, data, out=null, options=null):
    wb := excel.open(src)
    fill_workbook(wb, data, options)
    if out == null:
        return wb.to_bytes()
    filesystem.ensure_parent(out)
    wb.save(out)
    return out

func fill_ods(src, data, out=null, options=null):
    wb := ods.read(src)
    fill_workbook(wb, data, options)
    data_out := ods.write(wb)
    if out == null:
        return data_out
    filesystem.ensure_parent(out)
    io.write_bytes(out, data_out)
    return out

# ============================================================================================== PPTX / ODP

class _TfFiller:
    func init(root, o):
        self.root = root
        self.o = o

    func text_of(p):
        return p.text()

    func clone(p):
        return p.copy()

    func fill(p, stack):
        if len(p.runs) == 0:
            return null
        texts := []
        for r in p.runs:
            append(texts, r.text)
        full := string.join("", texts)
        if not string.contains(full, "{{"):
            return null
        if _has_block_tag(full):
            p.runs[0].text = _render_in(full, stack, self.root, self.o)
            k := 1
            while k < len(p.runs):
                p.runs[k].text = ""
                k = k + 1
            return null
        norm := _normalize(texts)
        k := 0
        for r in p.runs:
            r.text = _render_in(norm[k], stack, self.root, self.o)
            k = k + 1

    func frame(tf, stack):
        if tf == null:
            return null
        for p in tf.paragraphs:
            texts := []
            for r in p.runs:
                append(texts, r.text)
            norm := _normalize(texts)
            k := 0
            for r in p.runs:
                r.text = norm[k]
                k = k + 1
        tf.paragraphs = _expand(tf.paragraphs, stack, self.root, self.o, (p) => self.text_of(p), (p) => self.clone(p), (p, st) => self.fill(p, st))

func fill_presentation(prs, data, options=null):
    o := options if options != null else {}
    f := _TfFiller(data, o)
    stack := [_frame(data, {})]
    for s in prs.slides:
        for sh in s.shapes:
            if isinstance(sh, ps.Shape):
                f.frame(sh.text, stack)
            elif isinstance(sh, ptb.SlideTable):
                for row in sh.rows:
                    for cell in row:
                        f.frame(cell.text, stack)
            elif isinstance(sh, pch.SlideChart):
                if sh.title != null and type(sh.title) == "str":
                    sh.title = _render_in(sh.title, stack, data, o)
        if s.notes != null:
            s.notes = _render_in(s.notes, stack, data, o)
    return prs

func fill_pptx(src, data, out=null, options=null):
    prs := pp.open(src)
    fill_presentation(prs, data, options)
    if out == null:
        return prs.to_bytes()
    filesystem.ensure_parent(out)
    prs.save(out)
    return out

func fill_odp(src, data, out=null, options=null):
    prs := odp.read(src)
    fill_presentation(prs, data, options)
    b := odp.write(prs)
    if out == null:
        return b
    filesystem.ensure_parent(out)
    io.write_bytes(out, b)
    return out

# ============================================================================================== ODT (niveau XML)

func _is_para(el):
    return x.is_element(el) and (el["tag"] == "text:p" or el["tag"] == "text:h")

func _odf_text(el):
    if _is_para(el):
        return odf.node_text(el)
    return ""

# Remplace le contenu d'un paragraphe ODF par le texte rendu (style du premier segment conservé).
func _odf_fill_para(p, stack, root, o):
    txt := odf.node_text(p)
    if not string.contains(txt, "{{"):
        return null
    # cas simple : texte réparti dans des nœuds texte / spans sans balise coupée -> remplacement nœud par nœud
    if _odf_inline_ok(p):
        _odf_replace_strings(p, stack, root, o)
        return null
    span_style := null
    for c in p["children"]:
        if x.is_element(c) and c["tag"] == "text:span" and span_style == null:
            span_style = x.attr(c, "text:style-name", null)
    rendered := _render_in(txt, stack, root, o)
    kids := odf.text_nodes(rendered)
    keep := []
    for c in p["children"]:
        if x.is_element(c) and (x.prefix(c["tag"]) == "draw" or c["tag"] == "text:bookmark" or c["tag"] == "text:soft-page-break"):
            append(keep, c)
    if span_style != null:
        p["children"] = keep
        append(p["children"], x.el("text:span", {"text:style-name": span_style}, kids))
    else:
        for k in kids:
            append(keep, k)
        p["children"] = keep

# Vrai si chaque balise {{...}} tient entièrement dans un seul nœud texte.
func _odf_inline_ok(p):
    ok := true
    for t in _odf_strings(p):
        a := _count(t, "{{")
        b := _count(t, "}}")
        if a != b:
            ok = false
    if _has_block_tag(odf.node_text(p)):
        return false
    return ok

func _count(s, sub):
    n := 0
    pos := 0
    while true:
        k := _n.str_find(s, sub, pos)
        if k < 0:
            break
        n = n + 1
        pos = k + len(sub)
    return n

func _odf_strings(node):
    out := []
    for c in node["children"]:
        if type(c) == "str":
            append(out, c)
        elif x.is_element(c) and (c["tag"] == "text:span" or c["tag"] == "text:a"):
            for s in _odf_strings(c):
                append(out, s)
    return out

func _odf_replace_strings(node, stack, root, o):
    k := 0
    while k < len(node["children"]):
        c := node["children"][k]
        if type(c) == "str" and string.contains(c, "{{"):
            rendered := _render_in(c, stack, root, o)
            nodes := odf.text_nodes(rendered)
            collections.pop(node["children"], k)
            j := 0
            for nd in nodes:
                collections.insert(node["children"], k + j, nd)
                j = j + 1
            k = k + j
            continue
        if x.is_element(c) and (c["tag"] == "text:span" or c["tag"] == "text:a"):
            _odf_replace_strings(c, stack, root, o)
        k = k + 1

func _odf_fill_container(node, stack, root, o):
    kids := node["children"]
    new_kids := _expand(kids, stack, root, o, (e) => _odf_text(e), (e) => u.deep_copy(e), (e, st) => _odf_fill_el(e, st, root, o))
    node["children"] = new_kids

func _odf_fill_el(e, stack, root, o):
    if type(e) == "str" or not x.is_element(e):
        return null
    if _is_para(e):
        _odf_fill_para(e, stack, root, o)
        for fr in x.find_all(e, "draw:text-box"):
            _odf_fill_container(fr, stack, root, o)
        return null
    if e["tag"] == "table:table":
        _odf_fill_table(e, stack, root, o)
        return null
    if e["tag"] == "text:list" or e["tag"] == "text:list-item" or e["tag"] == "text:section" or e["tag"] == "table:table-cell" or e["tag"] == "table:table-header-rows" or e["tag"] == "table:table-rows" or e["tag"] == "office:text" or e["tag"] == "style:header" or e["tag"] == "style:footer" or e["tag"] == "style:master-page":
        _odf_fill_container(e, stack, root, o)

func _odf_fill_table(t, stack, root, o):
    out := []
    for row in t["children"]:
        if x.is_element(row) and (row["tag"] == "table:table-header-rows" or row["tag"] == "table:table-rows"):
            _odf_fill_table(row, stack, root, o)
            append(out, row)
            continue
        if not x.is_element(row) or row["tag"] != "table:table-row":
            append(out, row)
            continue
        cells := x.children(row, "table:table-cell")
        first := string.trim(odf.node_text(cells[0])) if len(cells) > 0 else ""
        last := string.trim(odf.node_text(cells[len(cells) - 1])) if len(cells) > 0 else ""
        if string.starts_with(first, "{{#each ") and string.ends_with(last, "{{/each}}"):
            close := _n.str_find(first, "}}", 0)
            expr := string.trim(_n.str_slice(first, 8, close))
            seq := _items(_value(expr, stack, root, o))
            idx := 0
            for it in seq:
                meta := {"index": idx, "index1": idx + 1, "first": idx == 0, "last": idx == len(seq) - 1, "key": it[0], "odd": idx % 2 == 1, "even": idx % 2 == 0}
                copy := u.deep_copy(row)
                _odf_strip_markers(copy)
                append(stack, _frame(it[1], meta))
                for cell in x.children(copy, "table:table-cell"):
                    _odf_fill_container(cell, stack, root, o)
                collections.pop(stack)
                append(out, copy)
                idx = idx + 1
            continue
        for cell in cells:
            _odf_fill_container(cell, stack, root, o)
        append(out, row)
    t["children"] = out

func _odf_strip_markers(row):
    for p in x.find_all(row, "text:p"):
        txt := odf.node_text(p)
        if string.contains(txt, "{{#each") or string.contains(txt, "{{/each}}"):
            t2 := txt
            if string.contains(t2, "{{#each"):
                a := _n.str_find(t2, "{{#each", 0)
                b := _n.str_find(t2, "}}", a)
                t2 = _n.str_slice(t2, 0, a) + _n.str_slice(t2, b + 2, null)
            t2 = string.replace(t2, "{{/each}}", "")
            span_style := null
            for c in p["children"]:
                if x.is_element(c) and c["tag"] == "text:span" and span_style == null:
                    span_style = x.attr(c, "text:style-name", null)
            kids := odf.text_nodes(t2)
            p["children"] = [x.el("text:span", {"text:style-name": span_style}, kids)] if span_style != null else kids

func fill_odt(src, data, out=null, options=null):
    o := options if options != null else {}
    pkg := odf.open(src)
    stack := [_frame(data, {})]
    root := pkg.content()
    body := x.first(root, "office:body")
    txt := x.first(body, "office:text") if body != null else null
    if txt == null:
        errors.fail(errors.ODF, "pas un texte OpenDocument")
    _odf_fill_container(txt, stack, data, o)
    pkg.set_xml("content.xml", root)
    st := pkg.styles()
    if st != null:
        ms := x.first(st, "office:master-styles")
        if ms != null:
            for mp in x.children(ms, "style:master-page"):
                _odf_fill_container(mp, stack, data, o)
                for hf in x.children(mp):
                    _odf_fill_container(hf, stack, data, o)
        pkg.set_xml("styles.xml", st)
    if pkg.metadata.title != "":
        pkg.metadata.title = _render_in(pkg.metadata.title, stack, data, o)
    b := pkg.to_bytes()
    if out == null:
        return b
    filesystem.ensure_parent(out)
    io.write_bytes(out, b)
    return out

# ============================================================================================== aiguillage

func fill(src, data, out=null, options=null):
    fmt := ""
    if type(src) == "str":
        fmt = string.lower(core.extension_of(src))
    if fmt == "" or (fmt != "md" and fmt != "txt" and fmt != "html" and fmt != "htm" and fmt != "csv" and fmt != "tsv" and fmt != "json" and fmt != "xml"):
        fmt = core.detect_format(src)
    if fmt == "docx" or fmt == "dotx" or fmt == "docm":
        return fill_docx(src, data, out, options)
    if fmt == "xlsx" or fmt == "xltx" or fmt == "xlsm":
        return fill_xlsx(src, data, out, options)
    if fmt == "pptx" or fmt == "potx":
        return fill_pptx(src, data, out, options)
    if fmt == "odt" or fmt == "ott":
        return fill_odt(src, data, out, options)
    if fmt == "ods" or fmt == "ots":
        return fill_ods(src, data, out, options)
    if fmt == "odp" or fmt == "otp":
        return fill_odp(src, data, out, options)
    # texte
    o := u.merge({"mode": "html"} if fmt == "html" or fmt == "htm" or fmt == "xml" else {}, options)
    text := u.decode_text(io.read_bytes(src)) if type(src) == "str" else u.decode_text(src)
    res := render(text, data, o)
    if out == null:
        return res
    filesystem.ensure_parent(out)
    io.write_bytes(out, _n.utf8_encode(res))
    return out

func fill_many(src, records, pattern, options=null):
    out := []
    k := 0
    for rec in records:
        ctx := u.merge(rec, {"_n": k + 1}) if type(rec) == "dict" else {"this": rec, "_n": k + 1}
        path := render(pattern, ctx, options)
        append(out, fill(src, rec, path, options))
        k = k + 1
    return out
