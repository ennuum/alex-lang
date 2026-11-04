# ALEX STANDARD LIBRARY — network.xml_parser
#
# Analyseur XML 1.0 non validant, avec espaces de noms (Namespaces in XML 1.0) :
#
#   parse(texte) -> Document           arbre complet (Element, Text, CData, Comment, PI)
#   parse_events(texte, gestionnaire)  analyse en flux (style SAX) : gestionnaire.start(élément),
#                                      .end(élément), .text(données), .comment(...), .pi(...) — méthodes facultatives
#   events(texte) -> list              mêmes événements en liste : ["start", Element], ["end", Element], ["text", str]...
#
# Le texte est décodé selon la déclaration (« encoding="ISO-8859-1" » sur des octets bruts), BOM retiré, fins de
# ligne normalisées (§2.11), valeurs d'attributs normalisées (§3.3.3). Entités : les 5 prédéfinies, références
# numériques, et entités internes déclarées dans le DOCTYPE (taille d'expansion bornée : pas de « milliard de
# rires ») ; les entités EXTERNES ne sont jamais chargées (pas de XXE).
#
# Arbre : Element(tag, attrs, children) avec ns / local / prefix résolus, parent, line ; méthodes de recherche
# find / find_all / iter (chemins à la ElementTree : « a/b », « .//c », « *[@id='x'] », « {uri}nom »).
#
# Erreurs : XmlError « ligne L, colonne C : ... ».
#
# Exemple
#   use network.xml_parser as xp
#   doc := xp.parse("<carnet><contact id=\"1\"><nom>Ada</nom></contact></carnet>")
#   for c in doc.root.find_all("contact"):
#       print(c.get("id"), c.find("nom").text())

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use network.encoding as _enc
use network.xml_writer as _xw

const XML_NS := "http://www.w3.org/XML/1998/namespace"
const XMLNS_NS := "http://www.w3.org/2000/xmlns/"
const MAX_ENTITY_EXPANSION := 1000000
const MAX_DEPTH := 2000

# ---------------------------------------------------------------- nœuds

class Node:
    func init(kind):
        self.kind = kind          # "document", "element", "text", "cdata", "comment", "pi"
        self.parent = null

class Text extends Node:
    func init(data):
        super.init("text")
        self.data = data

class CData extends Node:
    func init(data):
        super.init("cdata")
        self.data = data

class Comment extends Node:
    func init(data):
        super.init("comment")
        self.data = data

class PI extends Node:
    func init(target, data):
        super.init("pi")
        self.target = target
        self.data = data

class Element extends Node:
    # tag : nom qualifié tel qu'écrit (« atom:entry ») ; attrs : dict nom -> valeur (ordre conservé).
    func init(tag, attrs=null, children=null):
        super.init("element")
        self.tag = tag
        self.attrs = attrs
        if attrs == null:
            self.attrs = {}
        self.children = []
        self.ns = null            # URI de l'espace de noms (après résolution), ou null
        self.prefix = null
        self.local = tag
        c := _s.find(tag, ":")
        if c > 0:
            self.prefix = _s.substring(tag, 0, c)
            self.local = _s.substring(tag, c + 1, len(tag))
        self.nsmap = {}           # préfixes déclarés SUR cet élément ("" : défaut)
        self.line = 0
        if children != null:
            for ch in children:
                self.append(ch)

    # Nom étendu « {uri}local » (ou le nom local sans espace de noms).
    func qname():
        if self.ns == null:
            return self.local
        return "{" + self.ns + "}" + self.local

    func get(name, default=null):
        if contains_key(self.attrs, name):
            return self.attrs[name]
        return default

    func set(name, value):
        _xw.check_name(name)
        self.attrs[name] = str(value)
        return self

    func has(name):
        return contains_key(self.attrs, name)

    func remove_attr(name):
        if contains_key(self.attrs, name):
            d := {}
            for k in keys(self.attrs):
                if k != name:
                    d[k] = self.attrs[k]
            self.attrs = d
        return self

    # Ajoute un enfant (Element, Text..., ou str -> Text).
    func append(child):
        c := child
        if type(child) == "str":
            c = Text(child)
        c.parent = self
        append(self.children, c)
        return c

    func insert(index, child):
        c := child
        if type(child) == "str":
            c = Text(child)
        c.parent = self
        out := []
        i := 0
        for x in self.children:
            if i == index:
                append(out, c)
            append(out, x)
            i += 1
        if index >= len(self.children):
            append(out, c)
        self.children = out
        return c

    func remove(child):
        out := []
        for x in self.children:
            if x != child:
                append(out, x)
        self.children = out
        child.parent = null

    # Éléments enfants directs (tag : filtre facultatif sur le nom, local ou « {uri}local »).
    func elements(tag=null):
        out := []
        for c in self.children:
            if c.kind == "element" and (tag == null or _tag_matches(c, tag)):
                append(out, c)
        return out

    # Texte de tout le sous-arbre (concaténé).
    func text():
        out := []
        _gather_text(self, out)
        return _s.join("", out)

    # Texte des enfants directs seulement.
    func own_text():
        out := []
        for c in self.children:
            if c.kind == "text" or c.kind == "cdata":
                append(out, c.data)
        return _s.join("", out)

    # Remplace le contenu par un texte.
    func set_text(t):
        for c in self.children:
            c.parent = null
        self.children = []
        if t != null and str(t) != "":
            self.append(Text(str(t)))
        return self

    # Tous les éléments du sous-arbre (lui compris), ordre du document ; tag : filtre facultatif.
    func iter(tag=null):
        out := []
        _iter(self, tag, out)
        return out

    # Premier élément correspondant au chemin, ou null. namespaces : dict préfixe -> URI pour « p:nom ».
    func find(path, namespaces=null):
        r := select_path(self, path, namespaces)
        if len(r) == 0:
            return null
        return r[0]

    func find_all(path, namespaces=null):
        return select_path(self, path, namespaces)

    # Texte du premier élément du chemin, ou default.
    func find_text(path, default=null, namespaces=null):
        e := self.find(path, namespaces)
        if e == null:
            return default
        return e.text()

    # URI associée à un préfixe dans la portée de cet élément ("" : espace par défaut), ou null.
    func lookup_namespace(prefix):
        e := self
        while e != null and e.kind == "element":
            if contains_key(e.nsmap, prefix):
                v := e.nsmap[prefix]
                if v == "":
                    return null
                return v
            e = e.parent
        if prefix == "xml":
            return XML_NS
        return null

    # Valeur d'un attribut d'espace de noms (uri, nom local).
    func get_ns(uri, local, default=null):
        for k in keys(self.attrs):
            c := _s.find(k, ":")
            if c > 0 and _s.substring(k, c + 1, len(k)) == local:
                if self.lookup_namespace(_s.substring(k, 0, c)) == uri:
                    return self.attrs[k]
        return default

    func to_string(indent=null):
        return _xw.serialize(self, indent)

    func str():
        return self.to_string()

    func __len__():
        return len(self.elements())

class Document extends Node:
    func init():
        super.init("document")
        self.children = []
        self.root = null
        self.version = "1.0"
        self.encoding = null
        self.standalone = null
        self.doctype = null       # nom de l'élément racine déclaré, ou null
        self.public_id = null
        self.system_id = null
        self.entities = {}

    func append(child):
        child.parent = self
        append(self.children, child)
        if child.kind == "element":
            self.root = child
        return child

    func find(path, namespaces=null):
        if self.root == null:
            return null
        return self.root.find(path, namespaces)

    func find_all(path, namespaces=null):
        if self.root == null:
            return []
        return self.root.find_all(path, namespaces)

    func iter(tag=null):
        if self.root == null:
            return []
        return self.root.iter(tag)

    func to_string(indent=null, declaration=true):
        return _xw.serialize(self, indent, declaration)

    func str():
        return self.to_string()

func _gather_text(node, out):
    for c in node.children:
        if c.kind == "text" or c.kind == "cdata":
            append(out, c.data)
        elif c.kind == "element":
            _gather_text(c, out)

func _iter(node, tag, out):
    if node.kind != "element":
        return
    if tag == null or tag == "*" or _tag_matches(node, tag):
        append(out, node)
    for c in node.children:
        if c.kind == "element":
            _iter(c, tag, out)

# Un nom de recherche correspond à l'élément : « nom » (tag exact ou nom local), « {uri}local », « {*}local »,
# « {}local » (sans espace de noms).
func _tag_matches(el, tag):
    if tag == "*":
        return true
    if _s.starts_with(tag, "{"):
        e := _s.find(tag, "}")
        uri := _s.substring(tag, 1, e)
        local := _s.substring(tag, e + 1, len(tag))
        if local != "*" and local != el.local:
            return false
        if uri == "*":
            return true
        if uri == "":
            return el.ns == null
        return el.ns == uri
    return el.tag == tag or (el.prefix != null and false) or (el.prefix == null and el.local == tag)

# ---------------------------------------------------------------- chemins (sous-ensemble d'ElementTree / XPath)

# Éléments sélectionnés par `path` depuis `node` : étapes séparées par « / » ; « . », « .. », « * », « // »
# (descendants), prédicats [@a], [@a='v'], [n] (1 = premier), [last()], [nom], [nom='texte'], [text()='t'].
func select_path(node, path, namespaces=null):
    p := _s.trim(path)
    if p == "":
        return []
    current := [node]
    if _s.starts_with(p, "/"):
        # chemin absolu : depuis la racine du document
        r := node
        while r.parent != null:
            r = r.parent
        if r.kind == "document":
            current = [r]
        else:
            current = [_Wrapper(r)]
        if _s.starts_with(p, "//"):
            p = "." + p
        else:
            p = _s.substring(p, 1, len(p))
    steps := _split_steps(p)
    descend := false
    for step in steps:
        if step == "":
            descend = true
            continue
        nxt := []
        for n in current:
            for x in _apply_step(n, step, descend, namespaces):
                seen := false
                for y in nxt:
                    if y == x:
                        seen = true
                if not seen:
                    append(nxt, x)
        current = nxt
        descend = false
    out := []
    for n in current:
        if n.kind == "element":
            append(out, n)
    return out

class _Wrapper extends Node:
    # pseudo-document autour d'un élément sans document (chemins absolus)
    func init(root):
        super.init("document")
        self.children = [root]

func _split_steps(p):
    out := []
    cur := ""
    depth := 0
    inq := ""
    for c in p:
        if inq != "":
            cur += str(c)
            if str(c) == inq:
                inq = ""
            continue
        if c == '\'' or c == '"':
            inq = str(c)
            cur += str(c)
        elif c == '[' or c == '{':
            depth += 1
            cur += str(c)
        elif c == ']' or c == '}':
            depth -= 1
            cur += str(c)
        elif c == '/' and depth == 0:
            append(out, cur)
            cur = ""
        else:
            cur += str(c)
    append(out, cur)
    return out

func _children_elements(n):
    out := []
    for c in n.children:
        if c.kind == "element":
            append(out, c)
    return out

func _descendants(n, out):
    for c in n.children:
        if c.kind == "element":
            append(out, c)
            _descendants(c, out)

func _resolve_tag(tag, namespaces):
    if namespaces == null or _s.starts_with(tag, "{"):
        return tag
    c := _s.find(tag, ":")
    if c > 0:
        prefix := _s.substring(tag, 0, c)
        if contains_key(namespaces, prefix):
            return "{" + namespaces[prefix] + "}" + _s.substring(tag, c + 1, len(tag))
    elif contains_key(namespaces, "") and tag != "*":
        return "{" + namespaces[""] + "}" + tag
    return tag

func _apply_step(n, step, descend, namespaces):
    name := step
    preds := []
    b := _s.find(step, "[")
    if b >= 0:
        name = _s.substring(step, 0, b)
        rest := _s.substring(step, b, len(step))
        while _s.starts_with(rest, "["):
            e := _find_close(rest)
            append(preds, _s.substring(rest, 1, e))
            rest = _s.substring(rest, e + 1, len(rest))
    cands := []
    if name == "." or name == "":
        if descend:
            append(cands, n)
            _descendants(n, cands)
        else:
            cands = [n]
    elif name == "..":
        if n.parent != null:
            cands = [n.parent]
    else:
        pool := []
        if descend:
            _descendants(n, pool)
        else:
            pool = _children_elements(n)
        tag := _resolve_tag(name, namespaces)
        for c in pool:
            if _tag_matches(c, tag):
                append(cands, c)
    for pr in preds:
        cands = _filter(cands, _s.trim(pr), namespaces)
    return cands

func _find_close(s):
    depth := 0
    inq := ""
    i := 0
    while i < len(s):
        c := s[i]
        if inq != "":
            if str(c) == inq:
                inq = ""
        elif c == '\'' or c == '"':
            inq = str(c)
        elif c == '[':
            depth += 1
        elif c == ']':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise("XmlError", "chemin : « ] » manquant")

func _unquote(v):
    t := _s.trim(v)
    if len(t) >= 2 and (t[0] == '\'' or t[0] == '"') and t[len(t) - 1] == t[0]:
        return _s.substring(t, 1, len(t) - 1)
    return null

func _filter(cands, pred, namespaces):
    # index numérique / last()
    digits := pred != ""
    for c in pred:
        if c < '0' or c > '9':
            digits = false
    if digits:
        k := to_int(pred)
        if k >= 1 and k <= len(cands):
            return [cands[k - 1]]
        return []
    if pred == "last()":
        if len(cands) == 0:
            return []
        return [cands[len(cands) - 1]]
    out := []
    eq := _s.find(pred, "=")
    if _s.starts_with(pred, "@"):
        if eq < 0:
            name := _s.substring(pred, 1, len(pred))
            for c in cands:
                if c.kind == "element" and c.has(name):
                    append(out, c)
            return out
        name := _s.trim(_s.substring(pred, 1, eq))
        neg := _s.ends_with(name, "!")
        if neg:
            name = _s.trim(_s.substring(name, 0, len(name) - 1))
        val := _unquote(_s.substring(pred, eq + 1, len(pred)))
        for c in cands:
            if c.kind != "element":
                continue
            ok := c.get(name) == val
            if neg:
                ok = c.has(name) and c.get(name) != val
            if ok:
                append(out, c)
        return out
    if _s.starts_with(pred, "text()"):
        val := _unquote(_s.substring(pred, eq + 1, len(pred)))
        for c in cands:
            if c.kind == "element" and c.text() == val:
                append(out, c)
        return out
    if _s.starts_with(pred, "contains(") and _s.ends_with(pred, ")"):
        inner := _s.substring(pred, 9, len(pred) - 1)
        comma := _s.find(inner, ",")
        what := _s.trim(_s.substring(inner, 0, comma))
        needle := _unquote(_s.substring(inner, comma + 1, len(inner)))
        for c in cands:
            if c.kind != "element":
                continue
            hay := ""
            if what == "text()" or what == ".":
                hay = c.text()
            elif _s.starts_with(what, "@"):
                hay = c.get(_s.substring(what, 1, len(what)), "")
            if _s.contains(hay, needle):
                append(out, c)
        return out
    # [enfant] ou [enfant='texte']
    if eq < 0:
        tag := _resolve_tag(pred, namespaces)
        for c in cands:
            if c.kind == "element" and len(c.elements(tag)) > 0:
                append(out, c)
        return out
    tag := _resolve_tag(_s.trim(_s.substring(pred, 0, eq)), namespaces)
    val := _unquote(_s.substring(pred, eq + 1, len(pred)))
    for c in cands:
        if c.kind != "element":
            continue
        for ch in c.elements(tag):
            if ch.text() == val:
                append(out, c)
                break
    return out

# ---------------------------------------------------------------- analyseur

func _is_space(c):
    return c == ' ' or c == '\t' or c == '\n' or c == '\r'

class _Parser:
    func init(text, handler, keep_whitespace, namespaces):
        self.src = text
        self.n = len(text)
        self.pos = 0
        self.handler = handler          # null : construit un Document
        self.keep_ws = keep_whitespace
        self.use_ns = namespaces
        self.doc = Document()
        self.stack = []
        self.expanded = 0

    func fail(message):
        line := 1
        col := 1
        i := 0
        # position (ligne, colonne) recalculée seulement en cas d'erreur
        while i < self.pos and i < self.n:
            if self.src[i] == '\n':
                line += 1
                col = 1
            else:
                col += 1
            i += 1
        raise("XmlError", "XML ligne " + str(line) + ", colonne " + str(col) + " : " + message)

    func peek(k=0):
        if self.pos + k < self.n:
            return self.src[self.pos + k]
        return null

    func starts(lit):
        if self.pos + len(lit) > self.n:
            return false
        return _s.substring(self.src, self.pos, self.pos + len(lit)) == lit

    func expect(lit):
        if not self.starts(lit):
            self.fail("« " + lit + " » attendu")
        self.pos += len(lit)

    func skip_space():
        while self.pos < self.n and _is_space(self.src[self.pos]):
            self.pos += 1

    func find(lit):
        first := lit[0]
        size := len(lit)
        i := self.pos
        while i + size <= self.n:
            if self.src[i] == first and _s.substring(self.src, i, i + size) == lit:
                return i
            i += 1
        return -1

    func name():
        start := self.pos
        if self.pos >= self.n or not _xw._is_name_start(self.src[self.pos]):
            self.fail("nom attendu")
        p := self.pos + 1
        src := self.src
        n := self.n
        while p < n:
            c := src[p]
            if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_' or c == ':' or c == '.':
                p += 1
            elif _s.ord(c) >= 128 and _xw._is_name_char(c):
                p += 1
            else:
                break
        self.pos = p
        return _s.substring(src, start, p)

    func line_now():
        line := 1
        i := 0
        while i < self.pos:
            if self.src[i] == '\n':
                line += 1
            i += 1
        return line

    func run():
        if self.starts("<?xml") and self.peek(5) != null and _is_space(self.peek(5)):
            self.xml_decl()
        self.misc()
        if self.starts("<!DOCTYPE"):
            self.doctype()
            self.misc()
        if self.pos >= self.n or self.peek() != '<':
            self.fail("élément racine attendu")
        self.element()
        self.misc()
        if self.pos < self.n:
            self.fail("contenu après l'élément racine")
        return self.doc

    func xml_decl():
        self.pos += 5
        end := self.find("?>")
        if end < 0:
            self.fail("déclaration XML non terminée")
        body := _s.substring(self.src, self.pos, end)
        self.pos = end + 2
        v := _decl_value(body, "version")
        if v == null:
            self.fail("version absente de la déclaration XML")
        self.doc.version = v
        self.doc.encoding = _decl_value(body, "encoding")
        sa := _decl_value(body, "standalone")
        if sa != null:
            self.doc.standalone = sa == "yes"

    func misc():
        while true:
            self.skip_space()
            if self.starts("<!--"):
                self.comment(null)
            elif self.starts("<?"):
                self.pi(null)
            else:
                return

    func doctype():
        self.pos += 9
        self.skip_space()
        self.doc.doctype = self.name()
        self.skip_space()
        if self.starts("PUBLIC"):
            self.pos += 6
            self.skip_space()
            self.doc.public_id = self.quoted()
            self.skip_space()
            self.doc.system_id = self.quoted()
        elif self.starts("SYSTEM"):
            self.pos += 6
            self.skip_space()
            self.doc.system_id = self.quoted()
        self.skip_space()
        if self.peek() == '[':
            self.pos += 1
            self.internal_subset()
        self.skip_space()
        self.expect(">")

    func quoted():
        q := self.peek()
        if q != '"' and q != '\'':
            self.fail("littéral entre guillemets attendu")
        self.pos += 1
        end := self.find(str(q))
        if end < 0:
            self.fail("littéral non terminé")
        v := _s.substring(self.src, self.pos, end)
        self.pos = end + 1
        return v

    # Sous-ensemble interne : seules les entités générales internes sont retenues ; le reste est sauté.
    func internal_subset():
        while true:
            self.skip_space()
            if self.pos >= self.n:
                self.fail("DOCTYPE non terminé")
            if self.peek() == ']':
                self.pos += 1
                return
            if self.starts("<!--"):
                self.comment(null, false)
            elif self.starts("<?"):
                self.pi(null, false)
            elif self.starts("<!ENTITY"):
                self.pos += 8
                self.skip_space()
                parameter := false
                if self.peek() == '%':
                    parameter = true
                    self.pos += 1
                    self.skip_space()
                name := self.name()
                self.skip_space()
                if self.peek() == '"' or self.peek() == '\'':
                    value := self.quoted()
                    if not parameter and not contains_key(self.doc.entities, name):
                        self.doc.entities[name] = value
                else:
                    # entité externe : déclarée mais jamais chargée
                    while self.pos < self.n and self.peek() != '>':
                        if self.peek() == '"' or self.peek() == '\'':
                            self.quoted()
                        else:
                            self.pos += 1
                    if not parameter:
                        self.doc.entities[name] = null
                self.skip_space()
                self.expect(">")
            elif self.starts("<!"):
                # ELEMENT, ATTLIST, NOTATION : sautés (guillemets respectés)
                while self.pos < self.n and self.peek() != '>':
                    if self.peek() == '"' or self.peek() == '\'':
                        self.quoted()
                    else:
                        self.pos += 1
                self.expect(">")
            elif self.peek() == '%':
                end := self.find(";")
                if end < 0:
                    self.fail("référence d'entité paramètre non terminée")
                self.pos = end + 1
            else:
                self.fail("déclaration inattendue dans le DOCTYPE")

    func comment(parent, emit=true):
        self.pos += 4
        end := self.find("-->")
        if end < 0:
            self.fail("commentaire non terminé")
        data := _s.substring(self.src, self.pos, end)
        if _s.contains(data, "--"):
            self.fail("« -- » interdit dans un commentaire")
        self.pos = end + 3
        if not emit:
            return
        if self.handler != null:
            _call(self.handler, "comment", data)
            return
        c := Comment(data)
        if parent == null:
            self.doc.append(c)
        else:
            parent.append(c)

    func pi(parent, emit=true):
        self.pos += 2
        target := self.name()
        if _s.lower(target) == "xml":
            self.fail("instruction « xml » réservée (déclaration mal placée ?)")
        end := self.find("?>")
        if end < 0:
            self.fail("instruction de traitement non terminée")
        data := _s.trim(_s.substring(self.src, self.pos, end))
        self.pos = end + 2
        if not emit:
            return
        if self.handler != null:
            _call2(self.handler, "pi", target, data)
            return
        p := PI(target, data)
        if parent == null:
            self.doc.append(p)
        else:
            parent.append(p)

    # Remplace les références (&nom; &#n; &#xh;) d'un texte.
    func expand(text, in_attr, depth=0):
        if not _s.contains(text, "&"):
            return text
        out := []
        i := 0
        n := len(text)
        while i < n:
            c := text[i]
            if c != '&':
                j := i
                while j < n and text[j] != '&':
                    j += 1
                append(out, _s.substring(text, i, j))
                i = j
                continue
            semi := i + 1
            while semi < n and text[semi] != ';' and semi - i < 64:
                semi += 1
            if semi >= n or text[semi] != ';':
                self.fail("référence d'entité non terminée")
            ref := _s.substring(text, i + 1, semi)
            i = semi + 1
            if _s.starts_with(ref, "#"):
                cp := 0
                if _s.starts_with(ref, "#x"):
                    hx := _s.substring(ref, 2, len(ref))
                    if hx == "":
                        self.fail("référence de caractère vide")
                    for h in _s.lower(hx):
                        d := _s.find("0123456789abcdef", str(h))
                        if d < 0:
                            self.fail("référence de caractère invalide &" + ref + ";")
                        cp = cp * 16 + d
                        if cp > 1114111:
                            self.fail("référence de caractère hors limites")
                else:
                    ds := _s.substring(ref, 1, len(ref))
                    if ds == "":
                        self.fail("référence de caractère vide")
                    for d in ds:
                        if d < '0' or d > '9':
                            self.fail("référence de caractère invalide &" + ref + ";")
                        cp = cp * 10 + (_s.ord(d) - 48)
                        if cp > 1114111:
                            self.fail("référence de caractère hors limites")
                ch := _s.chr(cp)
                if cp == 0 or not _xw.is_xml_char(ch):
                    self.fail("caractère interdit &" + ref + ";")
                append(out, str(ch))
                continue
            if ref == "lt":
                append(out, "<")
            elif ref == "gt":
                append(out, ">")
            elif ref == "amp":
                append(out, "&")
            elif ref == "quot":
                append(out, "\"")
            elif ref == "apos":
                append(out, "'")
            elif contains_key(self.doc.entities, ref):
                v := self.doc.entities[ref]
                if v == null:
                    self.fail("entité externe « " + ref + " » non chargée (désactivé par sécurité)")
                if depth > 8:
                    self.fail("entités imbriquées trop profondément")
                r := self.expand(v, in_attr, depth + 1)
                self.expanded += len(r)
                if self.expanded > MAX_ENTITY_EXPANSION:
                    self.fail("expansion d'entités trop grande (attaque « milliard de rires » ?)")
                if in_attr and _s.contains(r, "<"):
                    self.fail("« < » interdit dans la valeur d'un attribut (via &" + ref + ";)")
                append(out, r)
            else:
                self.fail("entité inconnue &" + ref + ";")
        return _s.join("", out)

    func element():
        if len(self.stack) >= MAX_DEPTH:
            self.fail("imbrication trop profonde")
        start_pos := self.pos
        self.pos += 1
        tag := self.name()
        attrs := {}
        while true:
            had_space := self.pos < self.n and _is_space(self.src[self.pos])
            self.skip_space()
            c := self.peek()
            if c == null:
                self.fail("balise « " + tag + " » non terminée")
            if c == '>' or c == '/':
                break
            if not had_space:
                self.fail("espace attendu avant un attribut")
            an := self.name()
            self.skip_space()
            self.expect("=")
            self.skip_space()
            q := self.peek()
            if q != '"' and q != '\'':
                self.fail("valeur d'attribut entre guillemets attendue")
            self.pos += 1
            end := self.pos
            while end < self.n and self.src[end] != q:
                ce := self.src[end]
                if ce == '<':
                    self.pos = end
                    self.fail("« < » interdit dans la valeur d'un attribut")
                if ce < ' ' and ce != '\n' and ce != '\t' and ce != '\r':
                    self.pos = end
                    self.fail("caractère interdit dans la valeur d'un attribut")
                end += 1
            if end >= self.n:
                self.fail("valeur d'attribut non terminée")
            raw := _s.substring(self.src, self.pos, end)
            self.pos = end + 1
            raw = _s.replace(_s.replace(_s.replace(raw, "\t", " "), "\n", " "), "\r", " ")
            if contains_key(attrs, an):
                self.fail("attribut « " + an + " » répété")
            attrs[an] = self.expand(raw, true)
        el := Element(tag, attrs)
        el.line = 0
        parent := null
        if len(self.stack) > 0:
            parent = self.stack[len(self.stack) - 1]
        if self.use_ns:
            self.resolve_ns(el, parent)
        empty := false
        if self.peek() == '/':
            self.pos += 1
            empty = true
        self.expect(">")
        if self.handler != null:
            el.parent = parent
            _call(self.handler, "start", el)
        elif parent == null:
            self.doc.append(el)
        else:
            parent.append(el)
        if empty:
            if self.handler != null:
                _call(self.handler, "end", el)
            return
        append(self.stack, el)
        self.content(el)
        self.stack = self.stack[0:len(self.stack) - 1]
        if self.handler != null:
            _call(self.handler, "end", el)

    func resolve_ns(el, parent):
        for k in keys(el.attrs):
            if k == "xmlns":
                el.nsmap[""] = el.attrs[k]
            elif _s.starts_with(k, "xmlns:"):
                p := _s.substring(k, 6, len(k))
                v := el.attrs[k]
                if v == "":
                    self.fail("préfixe « " + p + " » associé à un espace de noms vide")
                if p == "xmlns" or (p == "xml" and v != XML_NS) or (v == XML_NS and p != "xml"):
                    self.fail("déclaration d'espace de noms réservée « " + k + " »")
                el.nsmap[p] = v
        el.parent = parent
        if el.prefix != null:
            if el.prefix == "xmlns":
                self.fail("préfixe « xmlns » interdit pour un élément")
            uri := el.lookup_namespace(el.prefix)
            if uri == null:
                self.fail("préfixe d'espace de noms non déclaré « " + el.prefix + " »")
            el.ns = uri
        else:
            el.ns = el.lookup_namespace("")
        for k in keys(el.attrs):
            c := _s.find(k, ":")
            if c > 0:
                p := _s.substring(k, 0, c)
                if p != "xmlns" and el.lookup_namespace(p) == null:
                    self.fail("préfixe d'attribut non déclaré « " + p + " »")
        el.parent = null

    func emit_text(parent, data, is_cdata):
        if data == "":
            return
        if self.handler != null:
            if is_cdata:
                _call(self.handler, "cdata", data)
            else:
                _call(self.handler, "text", data)
            return
        if not is_cdata and not self.keep_ws and _all_space(data):
            return
        if is_cdata:
            parent.append(CData(data))
        else:
            # fusion avec un nœud texte précédent
            k := len(parent.children)
            if k > 0 and parent.children[k - 1].kind == "text":
                parent.children[k - 1].data = parent.children[k - 1].data + data
            else:
                parent.append(Text(data))

    func content(el):
        while true:
            if self.pos >= self.n:
                self.fail("élément « " + el.tag + " » non fermé")
            c := self.src[self.pos]
            if c == '<':
                if self.starts("</"):
                    self.pos += 2
                    nm := self.name()
                    if nm != el.tag:
                        self.fail("fermeture « " + nm + " » au lieu de « " + el.tag + " »")
                    self.skip_space()
                    self.expect(">")
                    return
                if self.starts("<!--"):
                    self.comment(el)
                elif self.starts("<![CDATA["):
                    self.pos += 9
                    end := self.find("]]>")
                    if end < 0:
                        self.fail("section CDATA non terminée")
                    data := _s.substring(self.src, self.pos, end)
                    self.pos = end + 3
                    self.emit_text(el, data, true)
                elif self.starts("<?"):
                    self.pi(el)
                elif self.starts("<!"):
                    self.fail("déclaration inattendue dans le contenu")
                else:
                    self.element()
            else:
                j := self.pos
                while j < self.n:
                    cj := self.src[j]
                    if cj == '<':
                        break
                    if cj < ' ' and cj != '\n' and cj != '\t' and cj != '\r':
                        self.pos = j
                        self.fail("caractère interdit en XML (U+" + _xw._hex4(_s.ord(cj)) + ")")
                    j += 1
                raw := _s.substring(self.src, self.pos, j)
                if _s.contains(raw, "]]>"):
                    self.fail("« ]]> » interdit dans le texte")
                self.pos = j
                self.emit_text(el, self.expand(raw, false), false)

func _all_space(s):
    for c in s:
        if not _is_space(c):
            return false
    return true

func _call(h, name, arg):
    if type(h) == "dict":
        if contains_key(h, name):
            h[name](arg)
        return
    if name == "start" and _has(h, "start"):
        h.start(arg)
    elif name == "end" and _has(h, "end"):
        h.end(arg)
    elif name == "text" and _has(h, "text"):
        h.text(arg)
    elif name == "cdata":
        if _has(h, "cdata"):
            h.cdata(arg)
        elif _has(h, "text"):
            h.text(arg)
    elif name == "comment" and _has(h, "comment"):
        h.comment(arg)

func _call2(h, name, a, b):
    if type(h) == "dict":
        if contains_key(h, name):
            h[name](a, b)
        return
    if _has(h, "pi"):
        h.pi(a, b)

# Le gestionnaire objet doit déclarer `handles` (liste des événements traités) ; sans cette liste, toutes les
# méthodes sont supposées présentes.
func _has(h, name):
    try:
        hs := h.handles
        for x in hs:
            if x == name:
                return true
        return false
    catch e:
        return true

func _decl_value(body, key):
    i := _s.find(body, key)
    if i < 0:
        return null
    rest := _s.substring(body, i + len(key), len(body))
    eq := _s.find(rest, "=")
    if eq < 0:
        return null
    rest = _s.trim(_s.substring(rest, eq + 1, len(rest)))
    if rest == "":
        return null
    q := rest[0]
    if q != '"' and q != '\'':
        return null
    e := _s.find(_s.substring(rest, 1, len(rest)), str(q))
    if e < 0:
        return null
    return _s.substring(rest, 1, e + 1)

# Texte prêt à analyser : BOM retiré, octets décodés selon la déclaration, fins de ligne normalisées.
func prepare(data):
    raw := data
    if type(data) == "list":
        raw = _n.from_bytes(data)
    if type(raw) != "str":
        raise("TypeError", "xml_parser : str ou octets attendus (obtenu '" + type(raw) + "')")
    b := _n.to_bytes(_n.bslice(raw, 0, 4))
    if len(b) >= 2 and ((b[0] == 255 and b[1] == 254) or (b[0] == 254 and b[1] == 255)):
        raw = _enc.decode_charset(raw, "utf-16")
    elif len(b) >= 3 and b[0] == 239 and b[1] == 187 and b[2] == 191:
        raw = _n.bslice(raw, 3, _n.blen(raw))
    if _s.starts_with(raw, "<?xml"):
        e := _n.bfind(raw, "?>", 0)
        if e > 0:
            enc := _decl_value(_n.bslice(raw, 0, e), "encoding")
            if enc != null:
                cs := _enc.normalize_charset(enc)
                if cs != "utf-8" and cs != "us-ascii" and cs != "utf-16" and _enc.is_supported_charset(cs):
                    raw = _enc.decode_charset(raw, cs)
    if not _n.utf8_valid(raw):
        raise("XmlError", "XML : octets non UTF-8 sans déclaration d'encodage reconnue")
    if _s.contains(raw, "\r"):
        raw = _s.replace(_s.replace(raw, "\r\n", "\n"), "\r", "\n")
    return raw

# Analyse un document complet. keep_whitespace : garder les nœuds texte faits seulement d'espaces ;
# namespaces : résoudre les préfixes (false : noms bruts seulement).
func parse(text, keep_whitespace=false, namespaces=true):
    p := _Parser(prepare(text), null, keep_whitespace, namespaces)
    return p.run()

# Analyse un fragment (un seul élément) et rend son Element.
func parse_element(text, keep_whitespace=false):
    return parse(text, keep_whitespace).root

# Analyse en flux : appelle les méthodes du gestionnaire (objet ou dict de fonctions) : start(Element),
# end(Element), text(str), cdata(str), comment(str), pi(cible, données). Les éléments passés à start n'ont pas
# d'enfants (ils ne sont pas rangés dans un arbre).
func parse_events(text, handler, namespaces=true):
    if handler == null:
        raise("TypeError", "xml_parser.parse_events : gestionnaire attendu")
    p := _Parser(prepare(text), handler, true, namespaces)
    return p.run()

class _Collector:
    func init():
        self.out = []
        self.handles = ["start", "end", "text", "cdata", "comment", "pi"]

    func start(e):
        append(self.out, ["start", e])

    func end(e):
        append(self.out, ["end", e])

    func text(t):
        append(self.out, ["text", t])

    func cdata(t):
        append(self.out, ["cdata", t])

    func comment(t):
        append(self.out, ["comment", t])

    func pi(target, data):
        append(self.out, ["pi", target, data])

# Liste des événements de l'analyse en flux.
func events(text, namespaces=true):
    c := _Collector()
    parse_events(text, c, namespaces)
    return c.out

# Vrai si le texte est un document XML bien formé.
func is_well_formed(text):
    try:
        parse(text)
        return true
    catch e:
        if e.type == "XmlError":
            return false
        raise(e)
