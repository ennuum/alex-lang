# ALEX STANDARD LIBRARY — web.dom.selectors
#
# Sélecteurs CSS appliqués aux nœuds web.dom, avec le moteur de web.css.selector (adaptateur DomAdapter) :
# correspondance, ancêtre le plus proche, recherche dans un sous-arbre (portée :scope), spécificité. Les
# sélecteurs analysés sont gardés en cache ; une erreur de syntaxe devient une SyntaxError DOM, comme dans un
# navigateur.
#
#   use web.dom.selectors as sel
#   sel.matches(element, "nav > a.actif")         # vrai / faux
#   sel.closest(element, "section")               # ancêtre (ou l'élément) correspondant, sinon null
#   sel.select_all(document, "ul li:nth-child(odd)")
#   sel.select_first(form, ":scope > input[required]")
#   sel.is_valid("a[")                            # false
#
# Erreurs : SyntaxError (sélecteur invalide).

from core use len, type
from collections use append, keys
use web.dom.dom_errors as _err
use web.css.selector as _css
use web.css.selector_parser as _sp

_cache := [{}]
_adapter := [null]

func adapter():
    if _adapter[0] == null:
        _adapter[0] = _css.DomAdapter()
    return _adapter[0]

# Liste de sélecteurs analysée (cache), ou SyntaxError.
func parse(selector):
    if type(selector) != "str":
        return selector
    c := _cache[0]
    if selector in c:
        return c[selector]
    lst := null
    try:
        lst = _sp.parse(selector)
    catch e:
        _err.syntax("selectors", "« " + selector + " » n'est pas un sélecteur valide")
    if len(c) > 500:
        _cache[0] = {}
        c = _cache[0]
    c[selector] = lst
    return lst

func is_valid(selector):
    try:
        parse(selector)
        return true
    catch e:
        return false

func matches(element, selector, scope=null):
    if element == null or element.node_type != 1:
        return false
    return _css.matches(element, parse(selector), adapter(), scope)

func closest(element, selector):
    lst := parse(selector)
    a := adapter()
    e := element
    while e != null and e.node_type == 1:
        if _css.matches(e, lst, a):
            return e
        e = e.parent_node
    return null

func _walk(node, out):
    for c in node.nodes:
        if c.node_type == 1:
            append(out, c)
            _walk(c, out)
        elif c.node_type == 11:
            _walk(c, out)

# Éléments descendants (ordre du document).
func descendants(root):
    out := []
    _walk(root, out)
    return out

func select_all(root, selector):
    lst := parse(selector)
    a := adapter()
    scope := root if root.node_type == 1 else null
    out := []
    for d in descendants(root):
        if _css.matches(d, lst, a, scope):
            append(out, d)
    return out

func select_first(root, selector):
    lst := parse(selector)
    a := adapter()
    scope := root if root.node_type == 1 else null
    for d in descendants(root):
        if _css.matches(d, lst, a, scope):
            return d
    return null

func specificity(selector):
    return _sp.max_specificity(parse(selector))
