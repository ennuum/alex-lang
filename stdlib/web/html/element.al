# ALEX STANDARD LIBRARY — web.html.element
#
# Element : un élément HTML (balise, attributs, enfants, parent) et l'API d'arbre qui va avec : ajout et retrait
# d'enfants, navigation, recherche par sélecteur CSS, texte, sérialisation.
#
# Enfants acceptés partout (append, constructeur...) : Element, TextNode, CommentNode, RawHtml, str (devient un
# TextNode échappé), nombre, liste (aplatie), null (ignoré).
#
#   use web.html.element as el
#   ul := el.Element("ul", {"class": "menu"})
#   ul.append(el.Element("li", null, ["Accueil"])).append(el.Element("li", {"class": "actif"}, ["Contact"]))
#   ul.find("li.actif").text_content()       # Contact
#   len(ul.find_all("li"))                   # 2
#   ul.to_html()                             # <ul class="menu"><li>Accueil</li><li class="actif">Contact</li></ul>
#   ul.first_element().closest("ul") == ul   # true
#
# Sélecteurs pris en charge : type, *, #id, .classe, [attr], [attr=v], [attr~=v], [attr^=v], [attr$=v],
# [attr*=v], [attr|=v], :first-child, :last-child, :only-child, :nth-child(an+b | odd | even),
# :nth-of-type(...), :first-of-type, :last-of-type, :not(simple), :empty, :checked, :disabled, :enabled,
# combinateurs « ␠ », « > », « + », « ~ », et listes « a, b ».
#
# Erreurs : HtmlTagError (nom de balise), HtmlError (enfant d'un élément vide, nœud invalide, sélecteur invalide).

from core use len, type
from collections use append
use string as _s
use web.html.html_errors as _err
use web.html.attributes as _attrs
use web.html.text_node as _text
use web.html.html_serializer as _ser

const NODE_TYPE := "element"

# Nom de balise valide : lettre ASCII, puis lettres, chiffres, « - », « _ », « : », « . » (éléments personnalisés,
# espaces de noms SVG / MathML).
func is_valid_tag(tag):
    if type(tag) != "str" or len(tag) == 0:
        return false
    c0 := tag[0]
    if not ((c0 >= 'a' and c0 <= 'z') or (c0 >= 'A' and c0 <= 'Z')):
        return false
    for c in tag:
        if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_' or c == ':' or c == '.' or _s.ord(c) >= 128):
            return false
    return true

# Nœud d'arbre reconnu (champ node_type).
func is_node(value):
    if type(value) != "instance":
        return false
    try:
        t := value.node_type
        return t == "element" or t == "text" or t == "comment" or t == "raw" or t == "doctype" or t == "document"
    catch e:
        return false

# Liste de nœuds depuis une valeur d'enfant (voir en-tête).
func to_nodes(value):
    out := []
    _collect(value, out)
    return out

func _collect(value, out):
    if value == null or value == false:
        return
    t := type(value)
    if t == "str":
        append(out, _text.TextNode(value))
        return
    if t == "int" or t == "float" or t == "char":
        append(out, _text.TextNode(str(value)))
        return
    if t == "list" or t == "tuple":
        for v in value:
            _collect(v, out)
        return
    if is_node(value):
        if value.node_type == "document":
            _err.html_error("element", "un Document ne peut pas être l'enfant d'un élément")
        append(out, value)
        return
    _err.html_error("element", "enfant invalide de type " + t)

class Element:
    func init(tag, attributes=null, children=null):
        if not is_valid_tag(tag):
            _err.tag_error("Element", "nom de balise invalide '" + str(tag) + "'")
        self.node_type = NODE_TYPE
        self.tag = _s.lower(tag) if not _s.contains(tag, ":") else tag
        self.attributes = _attrs.from_data(attributes)
        self.children = []
        self.parent = null
        if children != null:
            self.extend(children)

    # ---------------------------------------------------------------- enfants

    func is_void():
        return _ser.is_void(self.tag)

    func _adopt(node):
        if self.is_void():
            _err.html_error("Element.append", "<" + self.tag + "> est un élément vide : il ne peut pas avoir d'enfant")
        if node.node_type == "element":
            p := self
            while p != null:
                if p == node:
                    _err.html_error("Element.append", "un élément ne peut pas devenir son propre descendant")
                p = p.parent
        if node.parent != null:
            node.parent.remove_child(node)
        node.parent = self

    # Ajoute un ou plusieurs enfants à la fin ; renvoie l'élément (chaînage).
    func append(child):
        for n in to_nodes(child):
            self._adopt(n)
            append(self.children, n)
        return self

    func extend(children):
        return self.append(children)

    # Ajoute et renvoie l'enfant (utile pour construire en profondeur).
    func add(child):
        nodes := to_nodes(child)
        self.append(nodes)
        if len(nodes) == 1:
            return nodes[0]
        return nodes

    func prepend(child):
        return self.insert(0, child)

    func insert(index, child):
        nodes := to_nodes(child)
        i := index
        if i < 0:
            i = len(self.children) + i
        if i < 0:
            i = 0
        if i > len(self.children):
            i = len(self.children)
        for n in nodes:
            self._adopt(n)
        if i > len(self.children):
            i = len(self.children)
        self.children = self.children[0:i] + nodes + self.children[i:len(self.children)]
        return self

    func index_of(child):
        i := 0
        for c in self.children:
            if c == child:
                return i
            i += 1
        return -1

    func insert_before(child, reference):
        i := self.index_of(reference)
        if i < 0:
            _err.html_error("Element.insert_before", "le nœud de référence n'est pas un enfant")
        return self.insert(i, child)

    func insert_after(child, reference):
        i := self.index_of(reference)
        if i < 0:
            _err.html_error("Element.insert_after", "le nœud de référence n'est pas un enfant")
        return self.insert(i + 1, child)

    func remove_child(child):
        out := []
        found := false
        for c in self.children:
            if c == child and not found:
                found = true
            else:
                append(out, c)
        if found:
            self.children = out
            child.parent = null
        return self

    func replace_child(new_child, old_child):
        i := self.index_of(old_child)
        if i < 0:
            _err.html_error("Element.replace_child", "l'ancien nœud n'est pas un enfant")
        self.remove_child(old_child)
        return self.insert(i, new_child)

    # Détache l'élément de son parent ; renvoie l'élément.
    func remove():
        if self.parent != null:
            self.parent.remove_child(self)
        return self

    func replace_with(node):
        if self.parent == null:
            _err.html_error("Element.replace_with", "élément sans parent")
        self.parent.replace_child(node, self)
        return node

    # Entoure l'élément par wrapper (qui prend sa place).
    func wrap(wrapper):
        if self.parent != null:
            self.parent.replace_child(wrapper, self)
        wrapper.append(self)
        return wrapper

    # Remplace l'élément par ses enfants.
    func unwrap():
        if self.parent == null:
            _err.html_error("Element.unwrap", "élément sans parent")
        p := self.parent
        i := p.index_of(self)
        kids := self.children
        self.children = []
        p.remove_child(self)
        for k in kids:
            k.parent = null
        p.insert(i, kids)
        return p

    func clear():
        for c in self.children:
            c.parent = null
        self.children = []
        return self

    func is_empty():
        return len(self.children) == 0

    # ---------------------------------------------------------------- navigation

    func elements():
        out := []
        for c in self.children:
            if c.node_type == "element":
                append(out, c)
        return out

    func first_child():
        if len(self.children) == 0:
            return null
        return self.children[0]

    func last_child():
        if len(self.children) == 0:
            return null
        return self.children[len(self.children) - 1]

    func first_element():
        for c in self.children:
            if c.node_type == "element":
                return c
        return null

    func last_element():
        es := self.elements()
        if len(es) == 0:
            return null
        return es[len(es) - 1]

    func _siblings():
        if self.parent == null or self.parent.node_type != "element" and self.parent.node_type != "document":
            return [self]
        return self.parent.elements() if self.parent.node_type == "element" else _doc_elements(self.parent)

    func next_element():
        sib := self._siblings()
        i := 0
        while i < len(sib):
            if sib[i] == self and i + 1 < len(sib):
                return sib[i + 1]
            i += 1
        return null

    func previous_element():
        sib := self._siblings()
        i := 0
        while i < len(sib):
            if sib[i] == self and i > 0:
                return sib[i - 1]
            i += 1
        return null

    # Position (0...) parmi les éléments frères.
    func element_index():
        sib := self._siblings()
        i := 0
        while i < len(sib):
            if sib[i] == self:
                return i
            i += 1
        return 0

    func ancestors():
        out := []
        p := self.parent
        while p != null and p.node_type == "element":
            append(out, p)
            p = p.parent
        return out

    # Tous les éléments descendants, en ordre de document.
    func descendants():
        out := []
        _descend(self, out)
        return out

    # Appelle fn(nœud, profondeur) sur chaque nœud descendant (ordre de document) ; fn rend false pour ne pas
    # descendre dans un élément.
    func walk(fn, depth=0):
        for c in self.children:
            r := fn(c, depth)
            if c.node_type == "element" and r != false:
                c.walk(fn, depth + 1)

    func root():
        p := self
        while p.parent != null:
            p = p.parent
        return p

    # ---------------------------------------------------------------- recherche

    func find_all(selector):
        groups := parse_selector(selector)
        out := []
        for e in self.descendants():
            if _matches_groups(e, groups):
                append(out, e)
        return out

    func find(selector):
        groups := parse_selector(selector)
        for e in self.descendants():
            if _matches_groups(e, groups):
                return e
        return null

    func matches(selector):
        return _matches_groups(self, parse_selector(selector))

    # Premier ancêtre (lui-même compris) qui correspond.
    func closest(selector):
        groups := parse_selector(selector)
        p := self
        while p != null and p.node_type == "element":
            if _matches_groups(p, groups):
                return p
            p = p.parent
        return null

    func find_by_id(id):
        for e in self.descendants():
            if e.attributes.get_text("id") == id:
                return e
        return null

    func find_by_tag(tag):
        t := _s.lower(tag)
        out := []
        for e in self.descendants():
            if e.tag == t:
                append(out, e)
        return out

    func find_by_class(name):
        out := []
        for e in self.descendants():
            if e.attributes.has_class(name):
                append(out, e)
        return out

    # ---------------------------------------------------------------- attributs

    func get(name, fallback=null):
        return self.attributes.get_text(name, fallback)

    func set(name, value):
        self.attributes.set(name, value)
        return self

    func set_attributes(data):
        self.attributes.update(data)
        return self

    func has(name):
        return self.attributes.has(name)

    func remove_attribute(name):
        self.attributes.remove(name)
        return self

    func id():
        return self.attributes.id()

    func classes():
        return self.attributes.classes()

    func has_class(name):
        return self.attributes.has_class(name)

    func add_class(name):
        self.attributes.add_class(name)
        return self

    func remove_class(name):
        self.attributes.remove_class(name)
        return self

    func toggle_class(name, on=null):
        self.attributes.toggle_class(name, on)
        return self

    func set_style(prop, value):
        self.attributes.set_style(prop, value)
        return self

    func data(name, fallback=null):
        return self.attributes.data(name, fallback)

    func set_data(name, value):
        self.attributes.set_data(name, value)
        return self

    # ---------------------------------------------------------------- contenu

    func text_content():
        return _ser.text_content(self)

    # Remplace le contenu par un texte (échappé au rendu).
    func set_text(text):
        self.clear()
        if text != null and text != "":
            self.append(_text.TextNode(str(text)))
        return self

    func inner_html(options=null):
        return _ser.inner_html(self, options)

    func to_html(options=null):
        return _ser.serialize(self, options)

    func pretty(indent="  "):
        return _ser.serialize(self, _ser.pretty(indent))

    func clone(deep=true):
        e := Element(self.tag, self.attributes.copy())
        if deep:
            for c in self.children:
                ch := c.clone() if c.node_type != "element" else c.clone(true)
                ch.parent = e
                append(e.children, ch)
        return e

    # Chemin lisible (diagnostics) : « html > body > div#contenu > p:nth-child(2) ».
    func path():
        parts := []
        p := self
        while p != null and p.node_type == "element":
            label := p.tag
            i := p.id()
            if i != null:
                label = label + "#" + i
            elif p.parent != null and len(p._siblings()) > 1:
                label = label + ":nth-child(" + str(p.element_index() + 1) + ")"
            parts = [label] + parts
            p = p.parent
        return _s.join(" > ", parts)

    func __str__():
        return self.to_html()

    func __len__():
        return len(self.children)

    func __contains__(node):
        return self.index_of(node) >= 0

func _doc_elements(doc):
    out := []
    for c in doc.children:
        if c.node_type == "element":
            append(out, c)
    return out

func _descend(node, out):
    for c in node.children:
        if c.node_type == "element":
            append(out, c)
            _descend(c, out)

# Raccourci : element("p", {"class": "x"}, ["texte"]).
func element(tag, attributes=null, children=null):
    return Element(tag, attributes, children)

func is_element(value):
    return is_node(value) and value.node_type == NODE_TYPE

# Éléments d'un arbre (document ou élément) qui correspondent au sélecteur.
func select(node, selector):
    groups := parse_selector(selector)
    out := []
    for e in _all_elements(node):
        if _matches_groups(e, groups):
            append(out, e)
    return out

func select_one(node, selector):
    groups := parse_selector(selector)
    for e in _all_elements(node):
        if _matches_groups(e, groups):
            return e
    return null

func _all_elements(node):
    out := []
    if node.node_type == "element":
        append(out, node)
    _descend(node, out)
    return out

# ---------------------------------------------------------------- sélecteurs CSS

func _sel_error(selector, why):
    _err.html_error("element.parse_selector", "sélecteur invalide '" + selector + "' : " + why)

func _is_ident_char(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_' or _s.ord(c) >= 128 or c == '\\'

# Groupes de sélecteurs : liste de chaînes [(combinateur, composé)] (le premier combinateur est null).
func parse_selector(selector):
    if type(selector) != "str" or _s.trim(selector) == "":
        _err.html_error("element.parse_selector", "sélecteur vide")
    groups := []
    for g in _split_top(selector, ','):
        t := _s.trim(g)
        if t == "":
            _sel_error(selector, "groupe vide")
        append(groups, _parse_complex(t, selector))
    return groups

# Découpe sur sep hors parenthèses, crochets et guillemets.
func _split_top(text, sep):
    out := []
    depth := 0
    quote := null
    cur := []
    for c in text:
        if quote != null:
            append(cur, str(c))
            if c == quote:
                quote = null
        elif c == '"' or c == '\'':
            quote = c
            append(cur, str(c))
        elif c == '(' or c == '[':
            depth += 1
            append(cur, str(c))
        elif c == ')' or c == ']':
            depth -= 1
            append(cur, str(c))
        elif c == sep and depth == 0:
            append(out, _s.join("", cur))
            cur = []
        else:
            append(cur, str(c))
    append(out, _s.join("", cur))
    return out

func _parse_complex(text, full):
    parts := []
    comb := null
    cur := []
    depth := 0
    quote := null
    i := 0
    n := len(text)
    while i < n:
        c := text[i]
        if quote != null:
            append(cur, str(c))
            if c == quote:
                quote = null
            i += 1
            continue
        if c == '"' or c == '\'':
            quote = c
            append(cur, str(c))
            i += 1
            continue
        if c == '(' or c == '[':
            depth += 1
        elif c == ')' or c == ']':
            depth -= 1
        if depth == 0 and (c == ' ' or c == '\t' or c == '\n' or c == '>' or c == '+' or c == '~'):
            if len(cur) > 0:
                append(parts, (comb, _parse_compound(_s.join("", cur), full)))
                cur = []
                comb = " "
            if c == '>' or c == '+' or c == '~':
                if len(parts) == 0:
                    _sel_error(full, "combinateur sans sélecteur à gauche")
                comb = str(c)
            i += 1
            continue
        append(cur, str(c))
        i += 1
    if len(cur) == 0:
        _sel_error(full, "combinateur sans sélecteur à droite")
    append(parts, (comb, _parse_compound(_s.join("", cur), full)))
    return parts

func _read_ident(text, i):
    j := i
    while j < len(text) and _is_ident_char(text[j]):
        j += 1
    return j

func _parse_compound(text, full):
    c := {"tag": null, "id": null, "classes": [], "attrs": [], "pseudos": []}
    i := 0
    n := len(text)
    if n > 0 and text[0] == '*':
        i = 1
    elif n > 0 and _is_ident_char(text[0]):
        j := _read_ident(text, 0)
        c["tag"] = _s.lower(text[0:j])
        i = j
    while i < n:
        ch := text[i]
        if ch == '#':
            j := _read_ident(text, i + 1)
            if j == i + 1:
                _sel_error(full, "« # » sans identifiant")
            c["id"] = text[i + 1:j]
            i = j
        elif ch == '.':
            j := _read_ident(text, i + 1)
            if j == i + 1:
                _sel_error(full, "« . » sans nom de classe")
            append(c["classes"], text[i + 1:j])
            i = j
        elif ch == '[':
            close := _find_close(text, i, '[', ']')
            if close < 0:
                _sel_error(full, "« [ » sans « ] »")
            append(c["attrs"], _parse_attr_sel(text[i + 1:close], full))
            i = close + 1
        elif ch == ':':
            j := i + 1
            if j < n and text[j] == ':':
                j += 1
            k := _read_ident(text, j)
            name := _s.lower(text[j:k])
            arg := null
            if k < n and text[k] == '(':
                close := _find_close(text, k, '(', ')')
                if close < 0:
                    _sel_error(full, "« ( » sans « ) »")
                arg = _s.trim(text[k + 1:close])
                k = close + 1
            if not (name in ["first-child", "last-child", "only-child", "nth-child", "nth-last-child", "nth-of-type", "first-of-type", "last-of-type", "not", "empty", "checked", "disabled", "enabled", "root", "required", "optional"]):
                _sel_error(full, "pseudo-classe non prise en charge « :" + name + " »")
            if name == "not":
                if arg == null:
                    _sel_error(full, ":not sans argument")
                arg = _parse_compound(arg, full)
            append(c["pseudos"], (name, arg))
            i = k
        else:
            _sel_error(full, "caractère inattendu « " + str(ch) + " »")
    return c

func _find_close(text, i, open, close):
    depth := 0
    quote := null
    j := i
    while j < len(text):
        c := text[j]
        if quote != null:
            if c == quote:
                quote = null
        elif c == '"' or c == '\'':
            quote = c
        elif c == open:
            depth += 1
        elif c == close:
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return -1

func _parse_attr_sel(text, full):
    ops := ["~=", "^=", "$=", "*=", "|=", "="]
    for op in ops:
        k := _s.find(text, op)
        if k > 0:
            name := _s.lower(_s.trim(text[0:k]))
            v := _s.trim(text[k + len(op):len(text)])
            insensitive := false
            if _s.ends_with(v, " i") or _s.ends_with(v, " I"):
                insensitive = true
                v = _s.trim(v[0:len(v) - 2])
            if len(v) >= 2 and (v[0] == '"' or v[0] == '\'') and v[len(v) - 1] == v[0]:
                v = v[1:len(v) - 1]
            return (name, op, v, insensitive)
    name := _s.lower(_s.trim(text))
    if name == "":
        _sel_error(full, "attribut vide")
    return (name, null, null, false)

func _matches_groups(el, groups):
    for g in groups:
        if _match_complex(el, g, len(g) - 1):
            return true
    return false

func _match_complex(el, parts, idx):
    if not _match_compound(el, parts[idx][1]):
        return false
    if idx == 0:
        return true
    comb := parts[idx][0]
    if comb == ">":
        p := el.parent
        return p != null and p.node_type == "element" and _match_complex(p, parts, idx - 1)
    if comb == " ":
        p := el.parent
        while p != null and p.node_type == "element":
            if _match_complex(p, parts, idx - 1):
                return true
            p = p.parent
        return false
    if comb == "+":
        prev := el.previous_element()
        return prev != null and _match_complex(prev, parts, idx - 1)
    if comb == "~":
        prev := el.previous_element()
        while prev != null:
            if _match_complex(prev, parts, idx - 1):
                return true
            prev = prev.previous_element()
        return false
    return false

func _match_compound(el, c):
    if c["tag"] != null and el.tag != c["tag"] and _s.lower(el.tag) != c["tag"]:
        return false
    if c["id"] != null and el.attributes.get_text("id") != c["id"]:
        return false
    if len(c["classes"]) > 0:
        have := el.attributes.classes()
        for k in c["classes"]:
            if not (k in have):
                return false
    for a in c["attrs"]:
        if not _match_attr(el, a):
            return false
    for p in c["pseudos"]:
        if not _match_pseudo(el, p[0], p[1]):
            return false
    return true

func _match_attr(el, a):
    v := el.attributes.get_text(a[0])
    if v == null:
        return false
    op := a[1]
    if op == null:
        return true
    want := a[2]
    if a[3]:
        v = _s.lower(v)
        want = _s.lower(want)
    if op == "=":
        return v == want
    if op == "~=":
        for t in _s.split(v, " "):
            if t == want:
                return true
        return false
    if op == "^=":
        return want != "" and _s.starts_with(v, want)
    if op == "$=":
        return want != "" and _s.ends_with(v, want)
    if op == "*=":
        return want != "" and _s.contains(v, want)
    if op == "|=":
        return v == want or _s.starts_with(v, want + "-")
    return false

# a, b de « an+b » (odd, even, 3, 2n+1, -n+3) ; null si invalide.
func _nth_parse(arg):
    t := _s.lower(_s.replace(arg, " ", ""))
    if t == "odd":
        return (2, 1)
    if t == "even":
        return (2, 0)
    k := _s.find(t, "n")
    if k < 0:
        return (0, _int(t))
    a_text := t[0:k]
    b_text := t[k + 1:len(t)]
    a := 1
    if a_text == "-":
        a = -1
    elif a_text != "" and a_text != "+":
        a = _int(a_text)
    b := 0
    if b_text != "":
        b = _int(b_text)
    return (a, b)

func _int(text):
    t := text
    sign := 1
    if _s.starts_with(t, "+"):
        t = t[1:len(t)]
    elif _s.starts_with(t, "-"):
        sign = -1
        t = t[1:len(t)]
    if t == "":
        _err.html_error("element", "nombre attendu dans :nth-*")
    n := 0
    for c in t:
        if c < '0' or c > '9':
            _err.html_error("element", "nombre attendu dans :nth-* ('" + text + "')")
        n = n * 10 + (_s.ord(c) - 48)
    return sign * n

func _nth_ok(ab, pos):
    a := ab[0]
    b := ab[1]
    if a == 0:
        return pos == b
    d := pos - b
    if d % a != 0:
        return false
    return d // a >= 0

func _match_pseudo(el, name, arg):
    sib := el._siblings()
    if name == "first-child":
        return len(sib) > 0 and sib[0] == el
    if name == "last-child":
        return len(sib) > 0 and sib[len(sib) - 1] == el
    if name == "only-child":
        return len(sib) == 1
    if name == "nth-child":
        return _nth_ok(_nth_parse(arg), el.element_index() + 1)
    if name == "nth-last-child":
        return _nth_ok(_nth_parse(arg), len(sib) - el.element_index())
    if name == "nth-of-type" or name == "first-of-type" or name == "last-of-type":
        same := []
        for s in sib:
            if s.tag == el.tag:
                append(same, s)
        pos := 0
        i := 0
        while i < len(same):
            if same[i] == el:
                pos = i + 1
            i += 1
        if name == "first-of-type":
            return pos == 1
        if name == "last-of-type":
            return pos == len(same)
        return _nth_ok(_nth_parse(arg), pos)
    if name == "not":
        return not _match_compound(el, arg)
    if name == "empty":
        for c in el.children:
            if c.node_type == "element" or (c.node_type == "text" and c.text != ""):
                return false
        return true
    if name == "checked":
        return el.attributes.has("checked") or el.attributes.has("selected")
    if name == "disabled":
        return el.attributes.has("disabled")
    if name == "enabled":
        return el.tag in ["input", "button", "select", "textarea", "option", "fieldset"] and not el.attributes.has("disabled")
    if name == "required":
        return el.attributes.has("required")
    if name == "optional":
        return el.tag in ["input", "select", "textarea"] and not el.attributes.has("required")
    if name == "root":
        return el.parent == null or el.parent.node_type == "document"
    return false
