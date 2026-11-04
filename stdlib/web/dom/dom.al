# ALEX STANDARD LIBRARY — web.dom
#
# Point d'entrée du paquet web.dom : un DOM conforme au standard (nœuds, éléments, attributs, événements,
# observateurs, fenêtre), en ALEX pur et avec une API en snake_case, pour manipuler du HTML comme le ferait le
# JavaScript d'une page — et tester des pages sans navigateur.
#
# | Module                                   | Rôle                                                         |
# |------------------------------------------|--------------------------------------------------------------|
# | web.dom (ce module)                      | raccourcis : parse, document, window, query, on, click…       |
# | web.dom.document / window                | Document, DOMImplementation ; Window, match_media, styles     |
# | web.dom.node / element / text            | arbre : Node, DocumentFragment, Element, Text, Comment…       |
# | web.dom.attributes / class_list          | Attr, NamedNodeMap ; DOMTokenList (class_list)                |
# | web.dom.node_list / selectors / query_selector | collections ; sélecteurs CSS (web.css.selector)        |
# | web.dom.tree_operations                  | TreeWalker, NodeIterator, wrap / unwrap, chemins              |
# | web.dom.event / event_target / events    | Event, distribution capture / bouillonnement ; simulations    |
# | web.dom.custom_event / keyboard_event / mouse_event / pointer_event / input_event | événements typés |
# | web.dom.mutation_observer / intersection_observer / resize_observer | observateurs              |
# | web.dom.dom_errors                       | DOMException (HierarchyRequestError, NotFoundError…)          |
#
#   use web.dom as dom
#   doc := dom.parse("<!DOCTYPE html><ul id=l><li>Un</li></ul><button>OK</button>")
#   win := dom.window(doc, 390, 844)
#   li := doc.create_element("li")
#   li.set_text_content("Deux")
#   doc.get_element_by_id("l").append_child(li)
#   dom.on(doc.query_selector("button"), "click", (e) => print("clic"))
#   dom.click(doc.query_selector("button"))        # « clic »
#   dom.query_all(doc, "li").length()             # 2
#   win.get_computed_style(li).get("display")     # list-item
#
# Erreurs : DOMException nommées (web.dom.dom_errors), SyntaxError pour un sélecteur invalide.

from core use len, type
use web.dom.dom_errors as _err
use web.dom.document as _doc
use web.dom.window as _win
use web.dom.element as _el
use web.dom.text as _text
use web.dom.node as _node
use web.dom.events as _events
use web.dom.custom_event as _ce
use web.dom.mutation_observer as _mo
use web.dom.query_selector as _qs
use web.dom.selectors as _sel

const ELEMENT_NODE := 1
const TEXT_NODE := 3
const COMMENT_NODE := 8
const DOCUMENT_NODE := 9
const DOCUMENT_FRAGMENT_NODE := 11

func parse(html, url="about:blank"):
    return _doc.parse_html(html, url)

func document(title=null, lang=null):
    return _doc.new_document(title, lang)

func window(document=null, width=1280, height=720, dpr=1):
    d := document if document != null else _doc.new_document()
    return _win.Window(d, width, height, dpr)

# Fragment de nœuds depuis du HTML (DocumentFragment).
func fragment(html, doc=null):
    d := doc if doc != null else _doc.new_document()
    f := d.create_document_fragment()
    for n in _el.from_html_fragment(str(html), "body", d):
        f.append_child(n)
    return f

func query(root, selector):
    return _qs.query_selector(root, selector)

func query_all(root, selector):
    return _qs.query_selector_all(root, selector)

func matches(element, selector):
    return _sel.matches(element, selector)

func on(target, event_type, fn, options=null):
    return _events.on(target, event_type, fn, options)

func fire(target, event_type, detail=null):
    return _events.fire(target, event_type, detail)

func click(element):
    return _events.click(element)

func type_text(element, text):
    return _events.type_text(element, text)

func observe_mutations(target, callback, options=null):
    o := _mo.MutationObserver(callback)
    o.observe(target, options if options != null else {"child_list": true, "subtree": true, "attributes": true, "character_data": true})
    return o

# Livre les enregistrements des observateurs de mutations en attente.
func flush(doc=null):
    _mo.flush(doc)

func serialize(node):
    if node.node_type == 9:
        return node.to_html()
    return _el.serialize(node)
