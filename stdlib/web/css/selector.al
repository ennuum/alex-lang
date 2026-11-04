# ALEX STANDARD LIBRARY — web.css.selector
#
# Sélecteurs CSS : objet Selector (analyse, spécificité, comparaison), construction, et CORRESPONDANCE avec des
# éléments — ceux de web.html (Element) comme ceux de web.dom (Element), reconnus automatiquement par un
# adaptateur. C'est le moteur qu'utilisent la cascade (web.css.stylesheet) et web.dom.query_selector.
#
#   use web.css.selector as sel
#   s := sel.Selector("nav > a.actif:not([hidden])")
#   s.specificity()                     # (0, 2, 2)
#   s.matches(element)                  # vrai / faux
#   sel.select(document, "ul li:nth-child(odd)")   # éléments correspondants (ordre du document)
#   sel.first(document, "#menu")
#   sel.compound("button", ["primaire"], "envoyer", {"type": "submit"})   # button#envoyer.primaire[type="submit"]
#   sel.descendant("nav", "a"), sel.child("ul", "li")
#
# Pseudo-classes évaluées : structure (:first-child, :nth-child(an+b of S), :only-of-type, :empty, :root,
# :scope), logique (:not, :is, :where, :has), formulaires (:checked, :disabled, :enabled, :required,
# :optional, :read-only, :read-write, :placeholder-shown), liens (:link, :any-link), :lang(), et les états
# d'interaction (:hover, :focus, :focus-visible, :focus-within, :active, :visited...) fournis par l'adaptateur.
# Un sélecteur à pseudo-élément (::before) ne correspond à aucun élément.
#
# Erreurs : CssSelectorError (sélecteur invalide).

from core use len, type
from collections use append
use string as _s
use web.css.css_errors as _err
use web.css.selector_parser as _sp

# ---------------------------------------------------------------- adaptateurs

# Éléments de web.html (tag, attributes, parent, elements()).
class HtmlAdapter:
    func tag(e):
        return e.tag

    func attr(e, name):
        return e.attributes.get_text(name)

    func parent(e):
        p := e.parent
        if p != null and p.node_type == "element":
            return p
        return null

    func children(e):
        if e.node_type == "document":
            out := []
            for c in e.children:
                if c.node_type == "element":
                    append(out, c)
            return out
        return e.elements()

    func siblings(e):
        p := e.parent
        if p == null:
            return [e]
        return self.children(p)

    func is_empty(e):
        for c in e.children:
            if c.node_type == "element" or (c.node_type == "text" and c.text != ""):
                return false
        return true

    func is_element(n):
        return n.node_type == "element"

    func state(e, name):
        try:
            return name in e.states
        catch err:
            return false

# Éléments de web.dom (local_name, get_attribute(), parent_element(), element_children()).
class DomAdapter:
    func tag(e):
        return e.local_name

    func attr(e, name):
        return e.get_attribute(name)

    func parent(e):
        return e.parent_element()

    func children(e):
        return e.element_children()

    func siblings(e):
        p := e.parent_node
        if p == null:
            return [e]
        return p.element_children()

    func is_empty(e):
        return e.is_empty_for_selector()

    func is_element(n):
        return n.node_type == 1

    func state(e, name):
        return e.selector_state(name)

_html := [null]
_dom := [null]

# Adaptateur convenant à un élément ou un document (web.dom si le nœud a local_name ou node_type entier).
func adapter_for(node):
    is_dom := false
    try:
        is_dom = type(node.node_type) == "int"
    catch e:
        is_dom = false
    if is_dom:
        if _dom[0] == null:
            _dom[0] = DomAdapter()
        return _dom[0]
    if _html[0] == null:
        _html[0] = HtmlAdapter()
    return _html[0]

# ---------------------------------------------------------------- correspondance

func _list(sel):
    if type(sel) == "str":
        return _sp.parse(sel)
    if isinstance(sel, Selector):
        return sel.list
    return sel

# Vrai si l'élément correspond à la liste de sélecteurs (texte, Selector ou SelectorList).
func matches(el, sel, adapter=null, scope=null):
    a := adapter if adapter != null else adapter_for(el)
    lst := _list(sel)
    for c in lst.items:
        if c.last().pseudo_element != null:
            continue
        if _match_complex(a, el, c.parts, len(c.parts) - 1, scope):
            return true
    return false

func _match_complex(a, el, parts, idx, scope):
    if not _match_compound(a, el, parts[idx][1], scope):
        return false
    comb := parts[idx][0]
    if idx == 0:
        if comb == null:
            return true
        # sélecteur relatif (:has(> x)) : ancré sur scope
        return _relative_anchor(a, el, comb, scope)
    if comb == ">":
        p := a.parent(el)
        return p != null and _match_complex(a, p, parts, idx - 1, scope)
    if comb == " ":
        p := a.parent(el)
        while p != null:
            if _match_complex(a, p, parts, idx - 1, scope):
                return true
            p = a.parent(p)
        return false
    if comb == "+":
        prev := _previous(a, el)
        return prev != null and _match_complex(a, prev, parts, idx - 1, scope)
    if comb == "~":
        sib := a.siblings(el)
        for s in sib:
            if s == el:
                return false
            if _match_complex(a, s, parts, idx - 1, scope):
                return true
        return false
    return false

func _relative_anchor(a, el, comb, scope):
    if scope == null:
        return true
    if comb == ">":
        return a.parent(el) == scope
    if comb == " ":
        p := a.parent(el)
        while p != null:
            if p == scope:
                return true
            p = a.parent(p)
        return false
    if comb == "+":
        return _previous(a, el) == scope
    if comb == "~":
        for s in a.siblings(el):
            if s == el:
                return false
            if s == scope:
                return true
        return false
    return false

func _previous(a, el):
    prev := null
    for s in a.siblings(el):
        if s == el:
            return prev
        prev = s
    return null

func _match_compound(a, el, cp, scope):
    if cp.tag != null and cp.tag != "*" and _s.lower(a.tag(el)) != cp.tag:
        return false
    if cp.nesting and scope != null and el != scope:
        return false
    for i in cp.ids:
        if a.attr(el, "id") != i:
            return false
    if len(cp.classes) > 0:
        cls := a.attr(el, "class")
        if cls == null:
            return false
        have := _tokens(cls)
        for c in cp.classes:
            if not (c in have):
                return false
    for at in cp.attrs:
        if not _match_attr(a, el, at):
            return false
    for ps in cp.pseudos:
        if not _match_pseudo(a, el, ps[0], ps[1], scope):
            return false
    return true

func _tokens(text):
    out := []
    for t in _s.split(_s.replace(_s.replace(text, "\t", " "), "\n", " "), " "):
        if t != "":
            append(out, t)
    return out

func _match_attr(a, el, at):
    v := a.attr(el, at[0])
    if v == null:
        return false
    op := at[1]
    if op == null:
        return true
    want := at[2]
    if at[3] == "i":
        v = _s.lower(v)
        want = _s.lower(want)
    if op == "=":
        return v == want
    if op == "~=":
        return want in _tokens(v)
    if op == "|=":
        return v == want or _s.starts_with(v, want + "-")
    if op == "^=":
        return want != "" and _s.starts_with(v, want)
    if op == "$=":
        return want != "" and _s.ends_with(v, want)
    if op == "*=":
        return want != "" and _s.contains(v, want)
    return false

func _position(a, el, nth, of_type, from_end, scope):
    sib := a.siblings(el)
    pool := []
    for s in sib:
        if of_type and _s.lower(a.tag(s)) != _s.lower(a.tag(el)):
            continue
        if nth != null and nth.of != null and not matches(s, nth.of, a, scope):
            continue
        append(pool, s)
    i := 0
    while i < len(pool):
        if pool[i] == el:
            return (len(pool) - i) if from_end else i + 1
        i += 1
    return 0

func _has(a, el, lst, scope):
    for c in lst.items:
        comb := c.parts[0][0]
        if comb == "+" or comb == "~":
            for s in a.siblings(el):
                if s != el and _match_complex(a, s, c.parts, len(c.parts) - 1, el):
                    return true
        else:
            for d in _descendants(a, el):
                if _match_complex(a, d, c.parts, len(c.parts) - 1, el if comb != null else el):
                    if comb == null:
                        # sans combinateur : descendant
                        return true
                    return true
    return false

func _descendants(a, el):
    out := []
    stack := [el]
    while len(stack) > 0:
        cur := stack[len(stack) - 1]
        stack = stack[0:len(stack) - 1]
        kids := a.children(cur)
        k := len(kids) - 1
        while k >= 0:
            append(out, kids[k])
            append(stack, kids[k])
            k -= 1
    return out

func _lang_of(a, el):
    e := el
    while e != null:
        l := a.attr(e, "lang")
        if l != null:
            return _s.lower(l)
        e = a.parent(e)
    return null

func _match_pseudo(a, el, name, arg, scope):
    t := _s.lower(a.tag(el))
    if name == "not":
        return not matches(el, arg, a, scope)
    if name == "is" or name == "where" or name == "matches" or name == "any" or name == "-webkit-any":
        return matches(el, arg, a, scope)
    if name == "has":
        return _has(a, el, arg, scope)
    if name == "first-child":
        return _position(a, el, null, false, false, scope) == 1
    if name == "last-child":
        return _position(a, el, null, false, true, scope) == 1
    if name == "only-child":
        return len(a.siblings(el)) == 1
    if name == "first-of-type":
        return _position(a, el, null, true, false, scope) == 1
    if name == "last-of-type":
        return _position(a, el, null, true, true, scope) == 1
    if name == "only-of-type":
        return _position(a, el, null, true, false, scope) == 1 and _position(a, el, null, true, true, scope) == 1
    if name == "nth-child":
        return arg.matches(_position(a, el, arg, false, false, scope))
    if name == "nth-last-child":
        return arg.matches(_position(a, el, arg, false, true, scope))
    if name == "nth-of-type":
        return arg.matches(_position(a, el, null, true, false, scope))
    if name == "nth-last-of-type":
        return arg.matches(_position(a, el, null, true, true, scope))
    if name == "empty":
        return a.is_empty(el)
    if name == "root":
        return a.parent(el) == null and t == "html"
    if name == "scope":
        return el == scope if scope != null else (a.parent(el) == null)
    if name == "checked" and isinstance(a, DomAdapter):
        return a.state(el, "checked")
    if name == "placeholder-shown" and isinstance(a, DomAdapter):
        return a.attr(el, "placeholder") != null and a.state(el, "placeholder-shown")
    if name == "checked":
        return a.attr(el, "checked") != null or (t == "option" and a.attr(el, "selected") != null) or a.state(el, "checked")
    if name == "disabled":
        return t in ["button", "input", "select", "textarea", "option", "optgroup", "fieldset"] and a.attr(el, "disabled") != null
    if name == "enabled":
        return t in ["button", "input", "select", "textarea", "option", "optgroup", "fieldset"] and a.attr(el, "disabled") == null
    if name == "required":
        return a.attr(el, "required") != null
    if name == "optional":
        return t in ["input", "select", "textarea"] and a.attr(el, "required") == null
    if name == "read-only":
        return not (t in ["input", "textarea"] and a.attr(el, "readonly") == null and a.attr(el, "disabled") == null) and a.attr(el, "contenteditable") == null
    if name == "read-write":
        return (t in ["input", "textarea"] and a.attr(el, "readonly") == null and a.attr(el, "disabled") == null) or a.attr(el, "contenteditable") != null
    if name == "placeholder-shown":
        return a.attr(el, "placeholder") != null and (a.attr(el, "value") == null or a.attr(el, "value") == "")
    if name == "link" or name == "any-link":
        return t in ["a", "area"] and a.attr(el, "href") != null
    if name == "defined":
        return true
    if name == "lang":
        l := _lang_of(a, el)
        want := _s.lower(_s.trim(_s.replace(_s.replace(arg, "\"", ""), "'", "")))
        return l != null and (l == want or _s.starts_with(l, want + "-"))
    if name == "dir":
        d := null
        e := el
        while e != null and d == null:
            d = a.attr(e, "dir")
            e = a.parent(e)
        return (d if d != null else "ltr") == _s.trim(arg)
    if name == "open":
        return a.attr(el, "open") != null
    return a.state(el, name)

# Éléments descendants de root (document ou élément) qui correspondent, en ordre de document.
func select(root, sel, adapter=null):
    a := adapter if adapter != null else adapter_for(root)
    lst := _list(sel)
    scope := root
    out := []
    for d in _descendants(a, root):
        if matches(d, lst, a, scope if a.is_element(root) else null):
            append(out, d)
    return out

func first(root, sel, adapter=null):
    a := adapter if adapter != null else adapter_for(root)
    lst := _list(sel)
    for d in _descendants(a, root):
        if matches(d, lst, a, root if a.is_element(root) else null):
            return d
    return null

# Premier ancêtre (l'élément compris) qui correspond, ou null.
func closest(el, sel, adapter=null):
    a := adapter if adapter != null else adapter_for(el)
    lst := _list(sel)
    e := el
    while e != null:
        if matches(e, lst, a):
            return e
        e = a.parent(e)
    return null

# ---------------------------------------------------------------- objet et construction

class Selector:
    func init(text):
        self.text = _s.trim(str(text))
        self.list = _sp.parse(self.text)

    func specificity():
        return _sp.max_specificity(self.list)

    func matches(el, adapter=null):
        return matches(el, self.list, adapter)

    func to_css():
        return self.list.to_css()

    func __str__():
        return self.to_css()

    func __len__():
        return len(self.list.items)

    func has_pseudo_element():
        for c in self.list.items:
            if c.last().pseudo_element != null:
                return true
        return false

func parse(text):
    return Selector(text)

func is_valid(text):
    return _sp.is_valid(text)

func specificity(text):
    return _sp.max_specificity(text)

func compare(a, b):
    return _sp.compare_specificity(specificity(a), specificity(b))

func _q(v):
    return "\"" + _s.replace(str(v), "\"", "\\\"") + "\""

# Sélecteur composé : balise, classes, id, attributs (dict ; true -> [attr]).
func compound(tag=null, classes=null, id=null, attributes=null, pseudo=null):
    out := tag if tag != null else ""
    if id != null:
        out = out + "#" + id
    if classes != null:
        for c in classes:
            out = out + "." + c
    if attributes != null:
        for k in attributes:
            v := attributes[k]
            if v == true:
                out = out + "[" + k + "]"
            else:
                out = out + "[" + k + "=" + _q(v) + "]"
    if pseudo != null:
        out = out + ":" + pseudo
    return out if out != "" else "*"

func descendant(a, b):
    return str(a) + " " + str(b)

func child(a, b):
    return str(a) + " > " + str(b)

func adjacent(a, b):
    return str(a) + " + " + str(b)

func sibling(a, b):
    return str(a) + " ~ " + str(b)

func any_of(selectors):
    parts := []
    for x in selectors:
        append(parts, str(x))
    return ":is(" + _s.join(", ", parts) + ")"

func group(selectors):
    parts := []
    for x in selectors:
        append(parts, str(x))
    return _s.join(", ", parts)
