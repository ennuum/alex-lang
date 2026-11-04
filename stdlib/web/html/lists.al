# ALEX STANDARD LIBRARY — web.html.lists
#
# Listes : non ordonnées (<ul>), ordonnées (<ol> : début, ordre inverse, type de numérotation), de définitions
# (<dl>), imbriquées depuis des structures ALEX, et lecture inverse d'une liste HTML.
#
#   use web.html.lists as ls
#   ls.ul(["Pain", "Lait", "Œufs"])                           # <ul><li>Pain</li>…</ul>
#   ls.ol(["Préchauffer", "Mélanger", "Cuire"], 1, false, "1")
#   ls.dl({"HTML": "langage de balisage", "CSS": "feuilles de style"})
#   ls.tree([("Fruits", ["Pomme", "Poire"]), ("Légumes", [("Racines", ["Carotte"])])])   # listes imbriquées
#   ls.to_list(element_ul)                                    # ["Pain", "Lait", "Œufs"]
#
# Un élément de liste peut être une valeur, un nœud, ou un Element <li> déjà construit.
# Erreurs : HtmlError (type de numérotation invalide).

from core use len, type
from collections use append, keys
use string as _s
use web.html.html_errors as _err
use web.html.element as _el
use web.html.element_factory as _f

const OL_TYPES := ["1", "a", "A", "i", "I"]

func li(content=null, attributes=null):
    if _el.is_element(content) and content.tag == "li":
        if attributes != null:
            content.set_attributes(attributes)
        return content
    if type(content) == "int" or type(content) == "float":
        return _el.Element("li", attributes, str(content))
    return _el.Element("li", attributes, content)

func _items(container, items):
    for it in items:
        container.append(li(it))
    return container

func ul(items, attributes=null):
    return _items(_el.Element("ul", attributes), items)

# Liste ordonnée ; start : premier numéro ; reversed : décroissante ; kind : « 1 », « a », « A », « i », « I ».
func ol(items, start=null, reversed=false, kind=null, attributes=null):
    if kind != null and not (kind in OL_TYPES):
        _err.html_error("lists.ol", "type de numérotation invalide « " + str(kind) + " » (1, a, A, i, I)")
    attrs := _f.merge_attributes({"start": start, "reversed": reversed, "type": kind}, attributes)
    return _items(_el.Element("ol", attrs), items)

# Menu de commandes (<menu>) : liste de boutons ou de liens.
func menu(items, attributes=null):
    return _items(_el.Element("menu", attributes), items)

# Liste de définitions : dict terme -> définition (une liste = plusieurs définitions), ou liste de paires.
func dl(definitions, attributes=null):
    d := _el.Element("dl", attributes)
    pairs := []
    if type(definitions) == "dict":
        for k in keys(definitions):
            append(pairs, (k, definitions[k]))
    else:
        pairs = definitions
    for p in pairs:
        d.append(_el.Element("dt", null, p[0]))
        defs := p[1]
        if type(defs) == "list" or type(defs) == "tuple":
            for x in defs:
                d.append(_el.Element("dd", null, x))
        else:
            d.append(_el.Element("dd", null, defs))
    return d

# Listes imbriquées : chaque élément est une valeur, ou (libellé, sous-éléments) ; ordered : <ol> à tous les niveaux.
func tree(items, ordered=false, attributes=null):
    root := _el.Element("ol" if ordered else "ul", attributes)
    for it in items:
        if type(it) == "tuple" and len(it) == 2 and (type(it[1]) == "list" or type(it[1]) == "tuple"):
            item := _el.Element("li", null, it[0])
            item.append(tree(it[1], ordered))
            root.append(item)
        else:
            root.append(li(it))
    return root

# Textes des éléments d'une liste (premier niveau seulement).
func to_list(list_element):
    out := []
    for c in list_element.elements():
        if c.tag == "li" or c.tag == "dt" or c.tag == "dd":
            texts := []
            for k in c.children:
                if k.node_type == "element" and (k.tag == "ul" or k.tag == "ol"):
                    continue
                append(texts, _s.trim(_text_of(k)))
            append(out, _s.trim(_s.join(" ", texts)))
    return out

func _text_of(node):
    if node.node_type == "text":
        return node.text
    if node.node_type == "element":
        return node.text_content()
    return ""

# Structure imbriquée inverse de tree() : valeurs ou (libellé, sous-liste).
func to_tree(list_element):
    out := []
    for c in list_element.elements():
        if c.tag != "li":
            continue
        sub := null
        texts := []
        for k in c.children:
            if k.node_type == "element" and (k.tag == "ul" or k.tag == "ol"):
                sub = k
            else:
                append(texts, _s.trim(_text_of(k)))
        label := _s.trim(_s.join(" ", texts))
        if sub != null:
            append(out, (label, to_tree(sub)))
        else:
            append(out, label)
    return out

# Dict depuis une liste de définitions (terme -> première définition).
func dl_to_dict(dl_element):
    out := {}
    term := null
    for c in dl_element.elements():
        if c.tag == "dt":
            term = _s.trim(c.text_content())
        elif c.tag == "dd" and term != null and not (term in out):
            out[term] = _s.trim(c.text_content())
    return out
