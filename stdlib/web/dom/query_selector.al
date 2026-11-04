# ALEX STANDARD LIBRARY — web.dom.query_selector
#
# Recherche d'éléments dans un sous-arbre DOM, comme les méthodes du navigateur : query_selector(_all) par
# sélecteur CSS, et les accès historiques par id, nom de balise, classes et attribut name. Fonctions
# génériques, utilisées par Element, Document et DocumentFragment.
#
#   use web.dom.query_selector as qs
#   qs.query_selector(document, "#menu a.actif")     # premier élément, ou null
#   qs.query_selector_all(document, "li")            # NodeList statique
#   qs.get_element_by_id(document, "contenu")
#   qs.get_elements_by_tag_name(document, "p")       # HTMLCollection vivante
#   qs.get_elements_by_class_name(document, "carte active")
#   qs.get_elements_by_name(document, "email")
#
# Erreurs : SyntaxError (sélecteur invalide).

from core use len, type
from collections use append
use string as _s
use web.dom.node_list as _nl
use web.dom.selectors as _sel

# Enfants éléments d'un nœud.
func element_children(node):
    out := []
    for c in node.nodes:
        if c.node_type == 1:
            append(out, c)
    return out

func query_selector(root, selector):
    return _sel.select_first(root, selector)

func query_selector_all(root, selector):
    return _nl.NodeList(_sel.select_all(root, selector))

func _first_by_id(node, id):
    for c in node.nodes:
        if c.node_type == 1:
            if c.get_attribute("id") == id:
                return c
            r := _first_by_id(c, id)
            if r != null:
                return r
        elif c.node_type == 11:
            r := _first_by_id(c, id)
            if r != null:
                return r
    return null

func get_element_by_id(root, id):
    if id == null or id == "":
        return null
    return _first_by_id(root, str(id))

func _by_tag(root, name):
    n := _s.lower(name)
    out := []
    for e in _sel.descendants(root):
        if name == "*" or e.local_name == n or e.tag_name == name:
            append(out, e)
    return out

func get_elements_by_tag_name(root, name):
    return _nl.HTMLCollection(() => _by_tag(root, name))

func _by_class(root, names):
    wanted := []
    for w in _s.split(_s.trim(str(names)), " "):
        if w != "":
            append(wanted, w)
    out := []
    if len(wanted) == 0:
        return out
    for e in _sel.descendants(root):
        cls := e.get_attribute("class")
        if cls == null:
            continue
        have := _s.split(cls, " ")
        ok := true
        for w in wanted:
            if not (w in have):
                ok = false
                break
        if ok:
            append(out, e)
    return out

func get_elements_by_class_name(root, names):
    return _nl.HTMLCollection(() => _by_class(root, names))

func _by_name(root, name):
    out := []
    for e in _sel.descendants(root):
        if e.get_attribute("name") == name:
            append(out, e)
    return out

func get_elements_by_name(root, name):
    return _nl.NodeList(null, () => _by_name(root, name))
