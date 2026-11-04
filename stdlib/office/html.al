# ALEX STANDARD LIBRARY — office.html
# HTML pour la bureautique : analyse tolérante (HTML réel, balises non fermées, attributs sans guillemets),
# extraction de texte, de tableaux et de liens, génération de pages et de tableaux.
#
#   use office.html as html
#   doc := html.parse(texte)                         # arbre {"tag", "attrs", "children"} (même modèle qu'office.xml)
#   html.to_text(doc)                                # texte lisible (paragraphes, listes « • », tableaux tabulés)
#   html.extract_tables(doc)                         # [[["Nom", "Âge"], ["Ada", "36"]], ...]  (colspan / rowspan)
#   html.extract_links(doc)                          # [{"href": "...", "text": "..."}]
#   page := html.document("Rapport", html.table([["a", "b"], [1, 2]]))   # page complète (UTF-8, CSS sobre)
#
# ANALYSE    parse(texte) -> nœud racine "#document"   find_all(n, tag)  find(n, tag)  attr(n, nom, défaut)
#            text(n) (texte brut des descendants)   by_id(n, id)   by_class(n, classe)
# EXTRACTION to_text(n_ou_texte, bullets="• ")   extract_tables(n_ou_texte, header=true)
#            extract_links(n_ou_texte)   extract_images(n_ou_texte) -> [{"src", "alt"}]   title(n_ou_texte)
# GÉNÉRATION render(nœud) -> HTML   el(tag, attrs, children)   escape(s, attr=false)   unescape(s)
#            table(lignes, header=true, caption=null, attrs=null) -> HTML   list_html(items, ordered=false)
#            document(titre, corps_html, css=null, lang="fr") -> page complète   DEFAULT_CSS
# Modèle : comme office.xml, mais noms de balises en minuscules ; les éléments vides (br, img...) n'ont pas
#   d'enfants ; le contenu de script / style est conservé brut et ignoré par to_text.
# Erreurs : TypeError (argument) — l'analyse ne lève jamais d'erreur de syntaxe (HTML tolérant).

use _native_office as _n
from core use len, type, to_int
from collections use append, keys, contains_key
use collections
use string
use office.utils as u
use office.xml as x

const _VOID := {"area": true, "base": true, "br": true, "col": true, "embed": true, "hr": true, "img": true, "input": true, "link": true, "meta": true, "param": true, "source": true, "track": true, "wbr": true}
const _RAW := {"script": true, "style": true, "textarea": true, "title": true}
const _BLOCK := {"address": true, "article": true, "aside": true, "blockquote": true, "div": true, "dl": true, "fieldset": true, "figure": true, "footer": true, "form": true, "h1": true, "h2": true, "h3": true, "h4": true, "h5": true, "h6": true, "header": true, "hr": true, "main": true, "nav": true, "ol": true, "p": true, "pre": true, "section": true, "table": true, "ul": true, "figcaption": true, "details": true, "summary": true}
const _ENTITIES := {"amp": 38, "lt": 60, "gt": 62, "quot": 34, "apos": 39, "nbsp": 160, "iexcl": 161, "cent": 162, "pound": 163, "curren": 164, "yen": 165, "brvbar": 166, "sect": 167, "uml": 168, "copy": 169, "ordf": 170, "laquo": 171, "not": 172, "shy": 173, "reg": 174, "macr": 175, "deg": 176, "plusmn": 177, "sup2": 178, "sup3": 179, "acute": 180, "micro": 181, "para": 182, "middot": 183, "cedil": 184, "sup1": 185, "ordm": 186, "raquo": 187, "frac14": 188, "frac12": 189, "frac34": 190, "iquest": 191, "Agrave": 192, "Aacute": 193, "Acirc": 194, "Atilde": 195, "Auml": 196, "Aring": 197, "AElig": 198, "Ccedil": 199, "Egrave": 200, "Eacute": 201, "Ecirc": 202, "Euml": 203, "Igrave": 204, "Iacute": 205, "Icirc": 206, "Iuml": 207, "ETH": 208, "Ntilde": 209, "Ograve": 210, "Oacute": 211, "Ocirc": 212, "Otilde": 213, "Ouml": 214, "times": 215, "Oslash": 216, "Ugrave": 217, "Uacute": 218, "Ucirc": 219, "Uuml": 220, "Yacute": 221, "THORN": 222, "szlig": 223, "agrave": 224, "aacute": 225, "acirc": 226, "atilde": 227, "auml": 228, "aring": 229, "aelig": 230, "ccedil": 231, "egrave": 232, "eacute": 233, "ecirc": 234, "euml": 235, "igrave": 236, "iacute": 237, "icirc": 238, "iuml": 239, "eth": 240, "ntilde": 241, "ograve": 242, "oacute": 243, "ocirc": 244, "otilde": 245, "ouml": 246, "divide": 247, "oslash": 248, "ugrave": 249, "uacute": 250, "ucirc": 251, "uuml": 252, "yacute": 253, "thorn": 254, "yuml": 255, "OElig": 338, "oelig": 339, "Scaron": 352, "scaron": 353, "Yuml": 376, "fnof": 402, "circ": 710, "tilde": 732, "ndash": 8211, "mdash": 8212, "lsquo": 8216, "rsquo": 8217, "sbquo": 8218, "ldquo": 8220, "rdquo": 8221, "bdquo": 8222, "dagger": 8224, "Dagger": 8225, "bull": 8226, "hellip": 8230, "permil": 8240, "prime": 8242, "lsaquo": 8249, "rsaquo": 8250, "euro": 8364, "trade": 8482, "larr": 8592, "rarr": 8594, "uarr": 8593, "darr": 8595, "harr": 8596, "le": 8804, "ge": 8805, "ne": 8800, "infin": 8734, "asymp": 8776, "minus": 8722, "thinsp": 8201, "ensp": 8194, "emsp": 8195, "zwnj": 8204, "zwj": 8205, "alpha": 945, "beta": 946, "gamma": 947, "delta": 948, "pi": 960, "sigma": 963, "omega": 969, "mu": 956, "lambda": 955, "check": 10003}

# ---------------------------------------------------------------------------------------------- entités

func escape(s, attr=false):
    t := string.replace(u.to_text(s), "&", "&amp;")
    t = string.replace(t, "<", "&lt;")
    t = string.replace(t, ">", "&gt;")
    if attr:
        t = string.replace(t, "\"", "&quot;")
    return t

func unescape(s):
    if not string.contains(s, "&"):
        return s
    out := []
    cs := u.chars(s)
    n := len(cs)
    i := 0
    while i < n:
        c := cs[i]
        if c != "&":
            append(out, c)
            i = i + 1
            continue
        j := i + 1
        while j < n and j - i <= 32 and cs[j] != ";" and cs[j] != "&" and cs[j] != " " and cs[j] != "<":
            j = j + 1
        name := ""
        k := i + 1
        while k < j:
            name = name + cs[k]
            k = k + 1
        ok := false
        if name != "" and str(name[0]) == "#":
            num := u.str_slice(name, 1, null)
            v := null
            if len(num) > 0 and (str(num[0]) == "x" or str(num[0]) == "X"):
                try:
                    b := _n.hex_decode(u.pad_left(u.str_slice(num, 1, null), 8, "0"))
                    v = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
                catch e:
                    v = null
            else:
                v = u.parse_number(num)
            if v != null and type(v) == "int" and v > 0 and v < 1114112 and not (v >= 55296 and v <= 57343):
                append(out, str(string.chr(v)))
                ok = true
        elif contains_key(_ENTITIES, name):
            append(out, str(string.chr(_ENTITIES[name])))
            ok = true
        if ok:
            i = j
            if i < n and cs[i] == ";":
                i = i + 1
        else:
            append(out, "&")
            i = i + 1
    return string.join("", out)

# ---------------------------------------------------------------------------------------------- analyse

func _is_space(ch):
    return ch == " " or ch == "\n" or ch == "\t" or ch == "\r" or ch == "\x0c"

func _closes_p(tag):
    return contains_key(_BLOCK, tag) or tag == "li" or tag == "dt" or tag == "dd"

# Implicite : faut-il fermer l'élément ouvert `open` avant d'ouvrir `tag` ?
func _implicit_close(open, tag):
    if open == "p" and _closes_p(tag):
        return true
    if open == "li" and tag == "li":
        return true
    if (open == "dt" or open == "dd") and (tag == "dt" or tag == "dd"):
        return true
    if (open == "td" or open == "th") and (tag == "td" or tag == "th" or tag == "tr" or tag == "tbody" or tag == "thead" or tag == "tfoot"):
        return true
    if open == "tr" and (tag == "tr" or tag == "tbody" or tag == "thead" or tag == "tfoot"):
        return true
    if (open == "thead" or open == "tbody" or open == "tfoot") and (tag == "tbody" or tag == "thead" or tag == "tfoot"):
        return true
    if open == "option" and (tag == "option" or tag == "optgroup"):
        return true
    return false

func _parse_attrs(s):
    attrs := {}
    cs := u.chars(s)
    n := len(cs)
    i := 0
    while i < n:
        while i < n and (_is_space(cs[i]) or cs[i] == "/"):
            i = i + 1
        if i >= n:
            break
        name := ""
        while i < n and not _is_space(cs[i]) and cs[i] != "=" and cs[i] != "/":
            name = name + cs[i]
            i = i + 1
        while i < n and _is_space(cs[i]):
            i = i + 1
        value := ""
        if i < n and cs[i] == "=":
            i = i + 1
            while i < n and _is_space(cs[i]):
                i = i + 1
            if i < n and (cs[i] == "\"" or cs[i] == "'"):
                q := cs[i]
                i = i + 1
                buf := []
                while i < n and cs[i] != q:
                    append(buf, cs[i])
                    i = i + 1
                i = i + 1
                value = string.join("", buf)
            else:
                buf := []
                while i < n and not _is_space(cs[i]):
                    append(buf, cs[i])
                    i = i + 1
                value = string.join("", buf)
        if name != "":
            ln := string.lower(name)
            if not contains_key(attrs, ln):
                attrs[ln] = unescape(value)
    return attrs

func parse(text):
    if type(text) != "str":
        raise("TypeError", "office.html.parse : texte attendu")
    root := {"tag": "#document", "attrs": {}, "children": []}
    stack := [root]
    low := string.lower(text)
    n := len(text)
    i := 0
    while i < n:
        lt := _n.str_find(text, "<", i)
        if lt < 0:
            lt = n
        if lt > i:
            t := unescape(_n.str_slice(text, i, lt))
            x.append_child(stack[len(stack) - 1], t)
        if lt >= n:
            break
        i = lt
        if _n.str_find(text, "<!--", i) == i:
            e := _n.str_find(text, "-->", i + 4)
            i = n if e < 0 else e + 3
            continue
        nxt := _n.str_slice(text, i + 1, i + 2)
        if nxt == "!" or nxt == "?":
            e := _n.str_find(text, ">", i)
            i = n if e < 0 else e + 1
            continue
        if nxt == "/":
            e := _n.str_find(text, ">", i)
            if e < 0:
                break
            name := string.lower(string.trim(_n.str_slice(text, i + 2, e)))
            sp := string.find(name, " ")
            if sp >= 0:
                name = _n.str_slice(name, 0, sp)
            i = e + 1
            # remonte jusqu'à l'élément de même nom (ignoré s'il n'est pas ouvert)
            k := len(stack) - 1
            while k > 0 and stack[k]["tag"] != name:
                k = k - 1
            if k > 0:
                while len(stack) > k:
                    collections.pop(stack)
            continue
        # balise ouvrante : nom = lettres
        j := i + 1
        while j < n:
            ch := _n.str_slice(text, j, j + 1)
            if _is_space(ch) or ch == ">" or ch == "/":
                break
            j = j + 1
        name := string.lower(_n.str_slice(text, i + 1, j))
        if name == "" or not ((string.ord(name[0]) >= 97 and string.ord(name[0]) <= 122)):
            x.append_child(stack[len(stack) - 1], "<")
            i = i + 1
            continue
        # fin de balise (en respectant les guillemets)
        k := j
        q := ""
        while k < n:
            ch := _n.str_slice(text, k, k + 1)
            if q != "":
                if ch == q:
                    q = ""
            elif ch == "\"" or ch == "'":
                q = ch
            elif ch == ">":
                break
            k = k + 1
        attr_text := _n.str_slice(text, j, k)
        self_closing := string.ends_with(string.trim(attr_text), "/")
        i = k + 1
        while len(stack) > 1 and _implicit_close(stack[len(stack) - 1]["tag"], name):
            collections.pop(stack)
        node := {"tag": name, "attrs": _parse_attrs(attr_text), "children": []}
        x.append_child(stack[len(stack) - 1], node)
        if contains_key(_VOID, name) or self_closing:
            continue
        if contains_key(_RAW, name):
            e := _n.str_find(low, "</" + name, i)
            if e < 0:
                e = n
            content := _n.str_slice(text, i, e)
            if name == "title" or name == "textarea":
                content = unescape(content)
            if content != "":
                x.append_child(node, content)
            g := _n.str_find(text, ">", e)
            i = n if g < 0 else g + 1
            continue
        append(stack, node)
    return root

func _doc(v):
    if type(v) == "str":
        return parse(v)
    return v

func find_all(node, tag):
    return x.find_all(_doc(node), tag)

func find(node, tag):
    return x.find(_doc(node), tag)

func attr(node, name, fallback=null):
    return x.attr(node, name, fallback)

func text(node):
    return x.text(node)

func by_id(node, ident):
    for e in x.iter(_doc(node)):
        if u.get(e["attrs"], "id", null) == ident:
            return e
    return null

func by_class(node, cls):
    out := []
    for e in x.iter(_doc(node)):
        for c in string.split(u.get(e["attrs"], "class", ""), " "):
            if c == cls:
                append(out, e)
                break
    return out

func title(node):
    t := x.find(_doc(node), "title")
    if t == null:
        return ""
    return string.trim(x.text(t))

# ---------------------------------------------------------------------------------------------- texte

func _collapse(s):
    out := []
    prev_space := false
    for c in s:
        ch := str(c)
        if _is_space(ch):
            if not prev_space:
                append(out, " ")
            prev_space = true
        else:
            append(out, ch)
            prev_space = false
    return string.join("", out)

class _TextOut:
    func init(bullets):
        self.parts = []
        self.bullets = bullets
        self.list_stack = []

    func newline(count=1):
        # assure `count` fins de ligne en fin de tampon
        tail := 0
        k := len(self.parts) - 1
        while k >= 0 and self.parts[k] == "\n":
            tail = tail + 1
            k = k - 1
        if k < 0:
            return null
        while tail < count:
            append(self.parts, "\n")
            tail = tail + 1

    func add(s):
        if s == "":
            return null
        if s == " ":
            if len(self.parts) == 0:
                return null
            last := self.parts[len(self.parts) - 1]
            if last == "\n" or last == "\t" or string.ends_with(last, " "):
                return null
        elif len(self.parts) > 0 and (self.parts[len(self.parts) - 1] == "\n" or self.parts[len(self.parts) - 1] == "\t"):
            if string.starts_with(s, " "):
                s = u.str_slice(s, 1, null)
        append(self.parts, s)

func _walk_text(node, out, pre):
    for c in node["children"]:
        if type(c) == "str":
            if pre:
                out.add(c)
            else:
                out.add(_collapse(c))
            continue
        if not x.is_element(c):
            continue
        tag := c["tag"]
        if tag == "script" or tag == "style" or tag == "head" or tag == "template" or tag == "noscript":
            continue
        if tag == "title":
            continue
        if tag == "br":
            append(out.parts, "\n")
            continue
        if tag == "hr":
            out.newline(1)
            out.add("----------")
            out.newline(1)
            continue
        if tag == "img":
            alt := u.get(c["attrs"], "alt", "")
            if alt != "":
                out.add("[" + alt + "]")
            continue
        if tag == "li":
            out.newline(1)
            depth := len(out.list_stack)
            indent := string.repeat("  ", depth - 1 if depth > 0 else 0)
            mark := out.bullets
            if depth > 0 and out.list_stack[depth - 1][0] == "ol":
                out.list_stack[depth - 1][1] = out.list_stack[depth - 1][1] + 1
                mark = str(out.list_stack[depth - 1][1]) + ". "
            append(out.parts, indent + mark)
            _walk_text(c, out, pre)
            out.newline(1)
            continue
        if tag == "ul" or tag == "ol":
            out.newline(1)
            append(out.list_stack, [tag, 0])
            _walk_text(c, out, pre)
            collections.pop(out.list_stack)
            out.newline(1)
            continue
        if tag == "td" or tag == "th":
            _walk_text(c, out, pre)
            append(out.parts, "\t")
            continue
        if tag == "tr":
            out.newline(1)
            _walk_text(c, out, pre)
            if len(out.parts) > 0 and out.parts[len(out.parts) - 1] == "\t":
                collections.pop(out.parts)
            out.newline(1)
            continue
        is_block := contains_key(_BLOCK, tag) or tag == "li" or tag == "tr" or tag == "body" or tag == "caption"
        if is_block:
            out.newline(2 if (tag == "p" or string.starts_with(tag, "h") and len(tag) == 2) else 1)
        _walk_text(c, out, pre or tag == "pre")
        if is_block:
            out.newline(2 if (tag == "p" or string.starts_with(tag, "h") and len(tag) == 2) else 1)

# Texte lisible d'un document HTML (nœud ou texte).
func to_text(node, bullets="• "):
    out := _TextOut(bullets)
    _walk_text(_doc(node), out, false)
    s := string.join("", out.parts)
    lines := []
    for line in string.split(s, "\n"):
        append(lines, _rstrip(line))
    s = string.join("\n", lines)
    while string.contains(s, "\n\n\n"):
        s = string.replace(s, "\n\n\n", "\n\n")
    return string.trim(s)

func _rstrip(s):
    t := s
    while len(t) > 0 and (str(t[len(t) - 1]) == " " or str(t[len(t) - 1]) == "\t"):
        t = u.str_slice(t, 0, len(t) - 1)
    return t

# ---------------------------------------------------------------------------------------------- tableaux, liens

func _rows_of(table):
    out := []
    for c in table["children"]:
        if not x.is_element(c):
            continue
        if c["tag"] == "tr":
            append(out, c)
        elif c["tag"] == "thead" or c["tag"] == "tbody" or c["tag"] == "tfoot":
            for r in x.children(c, "tr"):
                append(out, r)
    return out

# Chaque tableau -> liste de lignes de textes. colspan / rowspan : la valeur est recopiée dans les cases couvertes
# quand fill_spans est vrai, sinon elles reçoivent "".
func extract_tables(node, fill_spans=false):
    tables := []
    for t in x.find_all(_doc(node), "table"):
        grid := []
        pending := {}
        r := 0
        for tr in _rows_of(t):
            row := []
            col := 0
            for cell in x.children(tr):
                if cell["tag"] != "td" and cell["tag"] != "th":
                    continue
                while contains_key(pending, str(r) + ":" + str(col)):
                    append(row, pending[str(r) + ":" + str(col)])
                    col = col + 1
                txt := string.trim(to_text(cell))
                cs := u.parse_number(u.get(cell["attrs"], "colspan", "1"))
                rs := u.parse_number(u.get(cell["attrs"], "rowspan", "1"))
                if cs == null or type(cs) != "int" or cs < 1:
                    cs = 1
                if rs == null or type(rs) != "int" or rs < 1:
                    rs = 1
                k := 0
                while k < cs:
                    append(row, txt if (k == 0 or fill_spans) else "")
                    dr := 1
                    while dr < rs:
                        pending[str(r + dr) + ":" + str(col + k)] = txt if fill_spans else ""
                        dr = dr + 1
                    k = k + 1
                col = col + cs
            while contains_key(pending, str(r) + ":" + str(col)):
                append(row, pending[str(r) + ":" + str(col)])
                col = col + 1
            append(grid, row)
            r = r + 1
        append(tables, grid)
    return tables

func extract_links(node):
    out := []
    for a in x.find_all(_doc(node), "a"):
        href := u.get(a["attrs"], "href", null)
        if href != null:
            append(out, {"href": href, "text": string.trim(_collapse(x.text(a)))})
    return out

func extract_images(node):
    out := []
    for img in x.find_all(_doc(node), "img"):
        append(out, {"src": u.get(img["attrs"], "src", ""), "alt": u.get(img["attrs"], "alt", "")})
    return out

# ---------------------------------------------------------------------------------------------- génération

func el(tag, attrs=null, children=null):
    return x.el(tag, attrs, children)

func _render(node, out):
    if type(node) == "str":
        append(out, escape(node))
        return null
    if node == null:
        return null
    if type(node) == "dict" and contains_key(node, "raw") and not contains_key(node, "tag"):
        append(out, node["raw"])
        return null
    if type(node) != "dict":
        append(out, escape(u.to_text(node)))
        return null
    tag := node["tag"]
    if tag == "#document":
        for c in node["children"]:
            _render(c, out)
        return null
    append(out, "<" + tag)
    for k in keys(node["attrs"]):
        v := node["attrs"][k]
        if v == null or v == false:
            continue
        if v == true:
            append(out, " " + k)
        else:
            append(out, " " + k + "=\"" + escape(u.to_text(v), true) + "\"")
    append(out, ">")
    if contains_key(_VOID, tag):
        return null
    if tag == "script" or tag == "style":
        for c in node["children"]:
            append(out, u.to_text(c))
    else:
        for c in node["children"]:
            _render(c, out)
    append(out, "</" + tag + ">")

func render(node):
    out := []
    _render(node, out)
    return string.join("", out)

func _cell_html(v):
    if u.is_date_dict(v):
        return escape(u.iso_date(v))
    return string.replace(escape(u.to_text(v)), "\n", "<br>")

# Tableau HTML à partir de lignes (la première est l'en-tête si header est vrai). Les nombres sont alignés à droite.
func table(rows, header=true, caption=null, attrs=null):
    out := ["<table"]
    if attrs != null:
        for k in keys(attrs):
            append(out, " " + k + "=\"" + escape(u.to_text(attrs[k]), true) + "\"")
    append(out, ">")
    if caption != null:
        append(out, "<caption>" + escape(caption) + "</caption>")
    start := 0
    if header and len(rows) > 0:
        append(out, "<thead><tr>")
        for v in rows[0]:
            append(out, "<th>" + _cell_html(v) + "</th>")
        append(out, "</tr></thead>")
        start = 1
    append(out, "<tbody>")
    r := start
    while r < len(rows):
        append(out, "<tr>")
        for v in rows[r]:
            if u.is_number(v):
                append(out, "<td class=\"num\">" + _cell_html(v) + "</td>")
            else:
                append(out, "<td>" + _cell_html(v) + "</td>")
        append(out, "</tr>")
        r = r + 1
    append(out, "</tbody></table>")
    return string.join("", out)

func list_html(items, ordered=false):
    tag := "ol" if ordered else "ul"
    out := ["<" + tag + ">"]
    for it in items:
        if type(it) == "list":
            append(out, list_html(it, ordered))
        else:
            append(out, "<li>" + escape(u.to_text(it)) + "</li>")
    append(out, "</" + tag + ">")
    return string.join("", out)

const DEFAULT_CSS := "body{font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;line-height:1.5;max-width:60rem;margin:2rem auto;padding:0 1rem;color:#1f2328;background:#fff}h1,h2,h3,h4{line-height:1.25}table{border-collapse:collapse;margin:1rem 0}th,td{border:1px solid #d0d7de;padding:.35rem .6rem;vertical-align:top}th{background:#f6f8fa;text-align:left}td.num{text-align:right;font-variant-numeric:tabular-nums}img{max-width:100%}section.slide{border:1px solid #d0d7de;border-radius:6px;padding:1rem 1.5rem;margin:1.5rem 0}pre,code{font-family:ui-monospace,Consolas,monospace;background:#f6f8fa}"

func document(title_text, body, css=null, lang="fr"):
    style := css
    if style == null:
        style = DEFAULT_CSS
    return "<!DOCTYPE html>\n<html lang=\"" + escape(lang, true) + "\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>" + escape(title_text) + "</title>\n<style>" + style + "</style>\n</head>\n<body>\n" + body + "\n</body>\n</html>\n"
