# ALEX STANDARD LIBRARY — xml
# Analyse et sérialisation XML en ALEX pur (io pour load/save). Sous-ensemble non validant, sans espaces de noms.
#
#   use xml
#   doc := xml.parse("<livre id=\"7\"><titre>Alex &amp; co</titre><vide/></livre>")
#   doc["tag"]                       # "livre"
#   xml.attr(doc, "id")              # "7"
#   xml.text(xml.find(doc, "titre")) # "Alex & co"
#   xml.stringify(doc)               # <livre id="7"><titre>Alex &amp; co</titre><vide/></livre>
#
# MODÈLE : un élément est un dict {"tag": str, "attrs": dict(str -> str), "children": list}. Un enfant est soit un
#   élément, soit une str (texte ; les sections CDATA sont fusionnées dans le texte). Constructeur : xml.element.
# ANALYSE : prologue <?xml ...?>, instructions <?...?>, commentaires et <!DOCTYPE ...> (sans sous-ensemble interne
#   [ ... ]) sont ignorés. Entités reconnues : &lt; &gt; &amp; &quot; &apos; &#N; &#xH; (tout Unicode). Les noms
#   d'éléments/attributs gardent leur préfixe tel quel (« a:b »). Les textes composés uniquement d'espaces sont
#   supprimés, sauf avec keep_whitespace=true.
# ERREURS : raise("XMLError", message) ; pour parse le message contient « ligne L, colonne C ». Sont refusés :
#   balises mal fermées ou mal imbriquées, attribut dupliqué ou sans guillemets, entité inconnue, plusieurs racines,
#   texte hors de la racine, document vide.
# SÉRIALISATION : les attributs sont triés par nom (les dicts n'ont pas d'ordre garanti) ; un élément sans enfant est
#   écrit <a/>. pretty indente de 2 espaces (les éléments qui ne contiennent que du texte restent sur une ligne).

from core use len, type
from collections use append, keys, contains_key
use string
use io

func _fail(message):
    raise("XMLError", message)

# --- entités -----------------------------------------------------------------------------------------------

const _HEX := "0123456789abcdef"

func _digit(ch, base):
    d := string.find(_HEX, string.lower(ch))
    if d < 0 or d >= base or len(ch) != 1:
        return -1
    return d

# Remplace les références d'entités de `s`. Lève XMLError pour une entité inconnue ou mal formée.
func unescape(s):
    if type(s) != "str":
        raise("TypeError", "xml.unescape : chaîne attendue")
    if not string.contains(s, "&"):
        return s
    chars := []
    for c in s:
        append(chars, str(c))
    out := []
    i := 0
    n := len(chars)
    while i < n:
        c := chars[i]
        if c != "&":
            append(out, c)
            i = i + 1
            continue
        j := i + 1
        while j < n and chars[j] != ";" and j - i < 12:
            j = j + 1
        if j >= n or chars[j] != ";":
            _fail("référence d'entité non terminée par ';'")
        name := string.join("", _sub(chars, i + 1, j))
        if name == "lt":
            append(out, "<")
        elif name == "gt":
            append(out, ">")
        elif name == "amp":
            append(out, "&")
        elif name == "quot":
            append(out, "\"")
        elif name == "apos":
            append(out, "'")
        elif len(name) >= 2 and string.substring(name, 0, 1) == "#":
            base := 10
            digits := string.substring(name, 1, len(name))
            if string.substring(digits, 0, 1) == "x":
                base = 16
                digits = string.substring(digits, 1, len(digits))
            if len(digits) == 0:
                _fail("référence numérique vide : &" + name + ";")
            code := 0
            for d in digits:
                v := _digit(str(d), base)
                if v < 0:
                    _fail("référence numérique invalide : &" + name + ";")
                code = code * base + v
            if code < 1 or code > 1114111 or (code >= 55296 and code <= 57343):
                _fail("point de code invalide : &" + name + ";")
            append(out, str(string.chr(code)))
        else:
            _fail("entité inconnue : &" + name + ";")
        i = j + 1
    return string.join("", out)

func _sub(l, a, b):
    out := []
    while a < b:
        append(out, l[a])
        a = a + 1
    return out

# Échappe & < > pour du texte ; avec attr=true échappe aussi " et les fins de ligne / tabulations.
func escape(s, attr=false):
    if type(s) != "str":
        raise("TypeError", "xml.escape : chaîne attendue")
    out := []
    for c in s:
        ch := str(c)
        if ch == "&":
            append(out, "&amp;")
        elif ch == "<":
            append(out, "&lt;")
        elif ch == ">":
            append(out, "&gt;")
        elif attr and ch == "\"":
            append(out, "&quot;")
        elif attr and ch == "\n":
            append(out, "&#10;")
        elif attr and ch == "\t":
            append(out, "&#9;")
        elif attr and ch == "\r":
            append(out, "&#13;")
        else:
            append(out, ch)
    return string.join("", out)

# --- analyse -----------------------------------------------------------------------------------------------

func _is_space(ch):
    return ch == " " or ch == "\n" or ch == "\t" or ch == "\r"

func _is_name_start(ch):
    o := string.ord(ch)
    return (o >= 65 and o <= 90) or (o >= 97 and o <= 122) or ch == "_" or ch == ":" or o > 127

func _is_name_char(ch):
    o := string.ord(ch)
    return _is_name_start(ch) or (o >= 48 and o <= 57) or ch == "-" or ch == "."

class _Parser:
    func init(text, keep_ws):
        self.chars = []
        for c in text:
            append(self.chars, str(c))
        self.n = len(self.chars)
        self.pos = 0
        self.keep_ws = keep_ws

    func error(message):
        line := 1
        col := 1
        i := 0
        while i < self.pos and i < self.n:
            if self.chars[i] == "\n":
                line = line + 1
                col = 1
            else:
                col = col + 1
            i = i + 1
        _fail(message + " (ligne " + str(line) + ", colonne " + str(col) + ")")

    func peek():
        if self.pos < self.n:
            return self.chars[self.pos]
        return null

    # Vrai si le texte à la position courante commence par `lit`.
    func at(lit):
        k := 0
        m := len(lit)
        if self.pos + m > self.n:
            return false
        while k < m:
            if self.chars[self.pos + k] != string.substring(lit, k, k + 1):
                return false
            k = k + 1
        return true

    func skip_ws():
        while self.pos < self.n and _is_space(self.chars[self.pos]):
            self.pos = self.pos + 1

    # Avance jusqu'après `end` ; erreur si absent.
    func skip_until(end, what):
        while self.pos < self.n:
            if self.at(end):
                self.pos = self.pos + len(end)
                return null
            self.pos = self.pos + 1
        self.error(what + " non terminé")

    # Ignore commentaires, PI, DOCTYPE ; renvoie vrai si quelque chose a été sauté.
    func skip_misc():
        if self.at("<!--"):
            self.pos = self.pos + 4
            self.skip_until("-->", "commentaire")
            return true
        if self.at("<?"):
            self.pos = self.pos + 2
            self.skip_until("?>", "instruction de traitement")
            return true
        if self.at("<!DOCTYPE"):
            depth := 0
            while self.pos < self.n:
                ch := self.chars[self.pos]
                if ch == "[":
                    self.error("sous-ensemble interne de DOCTYPE non supporté")
                if ch == ">":
                    self.pos = self.pos + 1
                    return true
                self.pos = self.pos + 1
            self.error("DOCTYPE non terminé")
        return false

    func parse_name():
        ch := self.peek()
        if ch == null or not _is_name_start(ch):
            self.error("nom attendu")
        start := self.pos
        while self.pos < self.n and _is_name_char(self.chars[self.pos]):
            self.pos = self.pos + 1
        return string.join("", _sub(self.chars, start, self.pos))

    func parse_attr_value():
        q := self.peek()
        if q != "\"" and q != "'":
            self.error("valeur d'attribut entre guillemets attendue")
        self.pos = self.pos + 1
        start := self.pos
        while self.pos < self.n and self.chars[self.pos] != q:
            if self.chars[self.pos] == "<":
                self.error("'<' interdit dans une valeur d'attribut")
            self.pos = self.pos + 1
        if self.pos >= self.n:
            self.error("valeur d'attribut non terminée")
        raw := string.join("", _sub(self.chars, start, self.pos))
        self.pos = self.pos + 1
        return self.unesc(raw, start)

    func unesc(raw, at_index):
        save := self.pos
        self.pos = at_index
        v := null
        try:
            v = unescape(raw)
        catch e:
            self.error(e.message)
        self.pos = save
        return v

    func parse_element():
        # précondition : self.chars[self.pos] == "<"
        self.pos = self.pos + 1
        tag := self.parse_name()
        attrs := {}
        while true:
            had_space := self.pos < self.n and _is_space(self.chars[self.pos])
            self.skip_ws()
            ch := self.peek()
            if ch == null:
                self.error("balise <" + tag + "> non terminée")
            if ch == ">":
                self.pos = self.pos + 1
                break
            if ch == "/":
                if not self.at("/>"):
                    self.error("'/>' attendu")
                self.pos = self.pos + 2
                return {"tag": tag, "attrs": attrs, "children": []}
            if not had_space:
                self.error("espace attendu avant l'attribut")
            name := self.parse_name()
            if contains_key(attrs, name):
                self.error("attribut dupliqué '" + name + "'")
            self.skip_ws()
            if self.peek() != "=":
                self.error("'=' attendu après l'attribut '" + name + "'")
            self.pos = self.pos + 1
            self.skip_ws()
            attrs[name] = self.parse_attr_value()
        children := []
        buf := []
        while true:
            if self.pos >= self.n:
                self.error("balise <" + tag + "> non fermée")
            if self.at("</"):
                self.flush(children, buf)
                buf = []
                self.pos = self.pos + 2
                close := self.parse_name()
                if close != tag:
                    self.error("</" + close + "> ne correspond pas à <" + tag + ">")
                self.skip_ws()
                if self.peek() != ">":
                    self.error("'>' attendu")
                self.pos = self.pos + 1
                return {"tag": tag, "attrs": attrs, "children": children}
            if self.at("<![CDATA["):
                self.pos = self.pos + 9
                start := self.pos
                self.skip_until("]]>", "CDATA")
                append(buf, ["cdata", string.join("", _sub(self.chars, start, self.pos - 3))])
                continue
            if self.skip_misc():
                continue
            if self.chars[self.pos] == "<":
                self.flush(children, buf)
                buf = []
                append(children, self.parse_element())
                continue
            start := self.pos
            while self.pos < self.n and self.chars[self.pos] != "<":
                self.pos = self.pos + 1
            append(buf, ["text", string.join("", _sub(self.chars, start, self.pos)), start])

    # Fusionne les morceaux de texte / CDATA accumulés en un seul enfant str.
    func flush(children, buf):
        if len(buf) == 0:
            return null
        parts := []
        for item in buf:
            if item[0] == "cdata":
                append(parts, item[1])
            else:
                append(parts, self.unesc(item[1], item[2]))
        text := string.join("", parts)
        if text == "":
            return null
        if not self.keep_ws and string.trim(text) == "":
            return null
        append(children, text)

# Convertit un texte XML en élément racine. Lève XMLError si le document est invalide.
func parse(text, keep_whitespace=false):
    if type(text) != "str":
        raise("TypeError", "xml.parse : chaîne attendue (obtenu '" + type(text) + "')")
    p := _Parser(text, keep_whitespace)
    if p.n > 0 and p.chars[0] == str(string.chr(65279)):
        p.pos = 1
    root := null
    while true:
        p.skip_ws()
        if p.pos >= p.n:
            break
        if p.skip_misc():
            continue
        if p.chars[p.pos] != "<":
            p.error("texte hors de l'élément racine")
        if root != null:
            p.error("plusieurs éléments racines")
        root = p.parse_element()
    if root == null:
        p.error("document vide : aucun élément racine")
    return root

# Vrai si `text` est un XML valide.
func is_valid(text):
    try:
        parse(text)
    catch e:
        return false
    return true

# --- accès -------------------------------------------------------------------------------------------------

# Construit un élément : element("a", {"k": "v"}, ["texte", element("b")]).
func element(tag, attrs=null, children=null):
    if type(tag) != "str" or tag == "":
        raise("TypeError", "xml.element : tag str non vide attendu")
    a := attrs
    if a == null:
        a = {}
    c := children
    if c == null:
        c = []
    if type(c) == "str" or type(c) == "dict":
        c = [c]
    return {"tag": tag, "attrs": a, "children": c}

func _is_element(x):
    return type(x) == "dict"

# Éléments enfants directs (sans le texte), éventuellement filtrés par tag.
func children(node, tag=null):
    out := []
    for c in node["children"]:
        if _is_element(c) and (tag == null or c["tag"] == tag):
            append(out, c)
    return out

# Premier enfant direct de tag `tag`, ou null.
func find(node, tag):
    for c in node["children"]:
        if _is_element(c) and c["tag"] == tag:
            return c
    return null

# Tous les descendants de tag `tag` (ordre du document, `node` exclu).
func find_all(node, tag):
    out := []
    _collect(node, tag, out)
    return out

func _collect(node, tag, out):
    for c in node["children"]:
        if _is_element(c):
            if c["tag"] == tag:
                append(out, c)
            _collect(c, tag, out)

# Valeur de l'attribut `name`, ou `fallback` (défaut null).
func attr(node, name, fallback=null):
    if contains_key(node["attrs"], name):
        return node["attrs"][name]
    return fallback

# Texte concaténé de l'élément et de ses descendants.
func text(node):
    out := []
    _gather(node, out)
    return string.join("", out)

func _gather(node, out):
    for c in node["children"]:
        if _is_element(c):
            _gather(c, out)
        else:
            append(out, c)

# --- sérialisation -----------------------------------------------------------------------------------------

func _sorted_keys(d):
    ks := []
    for k in keys(d):
        append(ks, k)
    n := len(ks)
    i := 1
    while i < n:
        x := ks[i]
        j := i - 1
        while j >= 0 and ks[j] > x:
            ks[j + 1] = ks[j]
            j = j - 1
        ks[j + 1] = x
        i = i + 1
    return ks

func _open_tag(node, selfclose):
    out := "<" + node["tag"]
    attrs := node["attrs"]
    for k in _sorted_keys(attrs):
        if type(attrs[k]) != "str":
            _fail("stringify : la valeur de l'attribut '" + k + "' doit être une str")
        out = out + " " + k + "=\"" + escape(attrs[k], true) + "\""
    if selfclose:
        return out + "/>"
    return out + ">"

func _check_node(node):
    if type(node) != "dict" or not contains_key(node, "tag") or not contains_key(node, "attrs") or not contains_key(node, "children"):
        _fail("stringify : élément attendu ({\"tag\", \"attrs\", \"children\"})")

func _write(node, out, depth):
    if depth > 200:
        _fail("stringify : profondeur maximale dépassée (structure cyclique ?)")
    _check_node(node)
    if len(node["children"]) == 0:
        append(out, _open_tag(node, true))
        return null
    append(out, _open_tag(node, false))
    for c in node["children"]:
        if _is_element(c):
            _write(c, out, depth + 1)
        elif type(c) == "str":
            append(out, escape(c))
        else:
            _fail("stringify : enfant invalide (type '" + type(c) + "')")
    append(out, "</" + node["tag"] + ">")

# Sérialise un élément sur une ligne. declaration=true ajoute <?xml version="1.0" encoding="UTF-8"?>.
func stringify(node, declaration=false):
    out := []
    if declaration:
        append(out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    _write(node, out, 0)
    return string.join("", out)

func _only_text(node):
    for c in node["children"]:
        if _is_element(c):
            return false
    return true

func _write_pretty(node, out, level, indent, depth):
    if depth > 200:
        _fail("pretty : profondeur maximale dépassée (structure cyclique ?)")
    _check_node(node)
    pad := string.repeat(" ", indent * level)
    if len(node["children"]) == 0:
        append(out, pad + _open_tag(node, true))
    elif _only_text(node):
        parts := []
        for c in node["children"]:
            append(parts, escape(c))
        append(out, pad + _open_tag(node, false) + string.join("", parts) + "</" + node["tag"] + ">")
    else:
        append(out, pad + _open_tag(node, false))
        for c in node["children"]:
            if _is_element(c):
                _write_pretty(c, out, level + 1, indent, depth + 1)
            else:
                t := string.trim(c)
                if t != "":
                    append(out, string.repeat(" ", indent * (level + 1)) + escape(t))
        append(out, pad + "</" + node["tag"] + ">")

# Sérialise avec indentation (2 espaces par défaut) ; le texte mélangé à des éléments est rogné.
func pretty(node, indent=2, declaration=false):
    out := []
    if declaration:
        append(out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    _write_pretty(node, out, 0, indent, 0)
    return string.join("\n", out) + "\n"

func load(path, keep_whitespace=false):
    return parse(io.read_file(path), keep_whitespace)

func save(path, node, declaration=true):
    io.write_file(path, pretty(node, 2, declaration))
