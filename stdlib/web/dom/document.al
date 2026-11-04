# ALEX STANDARD LIBRARY — web.dom.document
#
# Document (et DOMImplementation) : racine de l'arbre — éléments racine, head, body, titre, fabriques
# (create_element, create_text_node, create_document_fragment, create_event, create_tree_walker…),
# recherche (get_element_by_id, query_selector…), collections (forms, images, links, scripts), focus
# (active_element, événements focus / blur / focusin / focusout), adoption et importation de nœuds,
# sérialisation, analyse HTML (via web.html), observateurs (mutations, géométrie) et crochets de navigation
# et d'envoi de formulaire utilisés par web.browser.
#
#   use web.dom.document as dd
#   doc := dd.parse_html("<!DOCTYPE html><title>Essai</title><p id=a>Bonjour</p>")
#   doc.title()                                   # Essai
#   doc.get_element_by_id("a").text_content()     # Bonjour
#   p := doc.create_element("p")
#   p.set_text_content("Nouveau")
#   doc.body().append_child(p)
#   doc.to_html()                                 # <!DOCTYPE html><html><head><title>Essai</title></head><body>…
#   doc2 := dd.new_document("Vide")               # squelette HTML5
#
# Erreurs : InvalidCharacterError (nom invalide), NotSupportedError (adoption d'un document),
# HierarchyRequestError.

from core use len, type
from collections use append
use string as _s
use web.dom.dom_errors as _err
use web.dom.node as _node
use web.dom.node_list as _nl
use web.dom.element as _el
use web.dom.text as _text
use web.dom.attributes as _attrs
use web.dom.event as _ev
use web.dom.custom_event as _ce
use web.dom.keyboard_event as _ke
use web.dom.mouse_event as _me
use web.dom.pointer_event as _pe
use web.dom.input_event as _ie
use web.dom.event_target as _et
use web.dom.selectors as _sel
use web.dom.query_selector as _qs
use web.dom.tree_operations as _tree
use web.dom.mutation_observer as _mo
use web.html.html_parser as _hp
from web.dom.node use Node

class Document extends Node:
    func init(content_type="text/html", url="about:blank"):
        super.init(_node.DOCUMENT_NODE, "#document", null)
        self.content_type = content_type
        self.url = url
        self.character_set = "UTF-8"
        self.compat_mode = "CSS1Compat"
        self.ready_state = "loading"
        self.referrer = ""
        self.mutation_hub = _mo.MutationHub()
        self.layout_observers = []
        self.default_view = null
        self._active = null
        self.focus_visible = true
        self.target_id = null
        self.style_sheets = []          # feuilles ajoutées par programme (web.css.stylesheet.Stylesheet)
        self.on_navigate = null         # fn(url, cible) : navigation demandée par un lien
        self.on_submit = null           # fn(formulaire, bouton) : envoi de formulaire accepté
        self.navigations = []           # (url, cible) demandées sans crochet
        self.submissions = []           # (formulaire, entrées) envoyés sans crochet
        self.implementation = DOMImplementation(self)
        self.design_mode = "off"
        self.visibility_state = "visible"
        self.hidden = false
        self.cookie_jar = null          # branché par web.browser (lecture / écriture de document.cookie)

    func is_html():
        return self.content_type == "text/html"

    # ------------------------------------------------------------ structure

    func doctype():
        for c in self.nodes:
            if c.node_type == _node.DOCUMENT_TYPE_NODE:
                return c
        return null

    func document_element():
        for c in self.nodes:
            if c.node_type == _node.ELEMENT_NODE:
                return c
        return null

    func _child_of_root(name):
        r := self.document_element()
        if r == null:
            return null
        for c in r.nodes:
            if c.node_type == _node.ELEMENT_NODE and c.local_name == name:
                return c
        return null

    func head():
        return self._child_of_root("head")

    func body():
        r := self.document_element()
        if r == null:
            return null
        for c in r.nodes:
            if c.node_type == _node.ELEMENT_NODE and (c.local_name == "body" or c.local_name == "frameset"):
                return c
        return null

    func title():
        t := _sel.select_first(self, "title")
        if t == null:
            return ""
        return _collapse(t.text_content())

    func set_title(value):
        t := _sel.select_first(self, "title")
        if t == null:
            h := self.head()
            if h == null:
                return
            t = self.create_element("title")
            h.append_child(t)
        t.set_text_content(value)

    func element_children():
        return _qs.element_children(self)

    func children():
        target := self
        return _nl.HTMLCollection(() => _qs.element_children(target))

    func child_element_count():
        return len(self.element_children())

    # ------------------------------------------------------------ fabriques

    func create_element(local_name, options=null):
        if not _el.is_valid_name(local_name):
            _err.invalid_character("create_element", "nom d'élément invalide « " + str(local_name) + " »")
        e := _el.Element(local_name, self, _el.HTML_NS if self.is_html() else false)
        if options != null and type(options) == "dict" and "is" in options:
            e.set_attribute("is", options["is"])
        return e

    func create_element_ns(namespace_uri, qualified_name):
        i := _s.find(qualified_name, ":")
        prefix := qualified_name[0:i] if i > 0 else null
        local := qualified_name[i + 1:len(qualified_name)] if i > 0 else qualified_name
        return _el.Element(local, self, namespace_uri if namespace_uri != null else false, prefix)

    func create_text_node(data):
        return _text.Text(data, self)

    func create_comment(data):
        return _text.Comment(data, self)

    func create_cdata_section(data):
        if self.is_html():
            _err.not_supported("create_cdata_section", "pas de section CDATA dans un document HTML")
        return _text.CDATASection(data, self)

    func create_processing_instruction(target, data):
        return _text.ProcessingInstruction(target, data, self)

    func create_document_fragment():
        return _node.DocumentFragment(self)

    func create_attribute(name):
        return _attrs.Attr(_s.lower(name) if self.is_html() else name, "")

    # Événement par interface (« Event », « CustomEvent », « KeyboardEvent », « MouseEvent »…).
    func create_event(interface_name):
        k := _s.lower(interface_name)
        if k == "customevent":
            return _ce.CustomEvent("x")
        if k == "keyboardevent" or k == "keyevents":
            return _ke.KeyboardEvent("x")
        if k == "mouseevent" or k == "mouseevents":
            return _me.MouseEvent("x")
        if k == "pointerevent":
            return _pe.PointerEvent("x")
        if k == "inputevent":
            return _ie.InputEvent("x")
        if k == "uievent" or k == "uievents":
            return _ev.UIEvent("x")
        if k == "event" or k == "events" or k == "htmlevents":
            return _ev.Event("x")
        _err.not_supported("create_event", "interface d'événement inconnue « " + interface_name + " »")

    func create_tree_walker(root, what_to_show=4294967295, filter=null):
        return _tree.TreeWalker(root, what_to_show, filter)

    func create_node_iterator(root, what_to_show=4294967295, filter=null):
        return _tree.NodeIterator(root, what_to_show, filter)

    # Copie d'un nœud d'un autre document, adoptée par celui-ci.
    func import_node(node, deep=false):
        if node.node_type == _node.DOCUMENT_NODE:
            _err.not_supported("import_node", "un document ne peut pas être importé")
        c := node.clone_node(deep)
        _node._set_owner(c, self)
        return c

    func adopt_node(node):
        if node.node_type == _node.DOCUMENT_NODE:
            _err.not_supported("adopt_node", "un document ne peut pas être adopté")
        if node.parent_node != null:
            node.parent_node.remove_child(node)
        _node._set_owner(node, self)
        return node

    # ------------------------------------------------------------ recherche

    func get_element_by_id(id):
        return _qs.get_element_by_id(self, id)

    func query_selector(selector):
        return _qs.query_selector(self, selector)

    func query_selector_all(selector):
        return _qs.query_selector_all(self, selector)

    func get_elements_by_tag_name(name):
        return _qs.get_elements_by_tag_name(self, name)

    func get_elements_by_class_name(names):
        return _qs.get_elements_by_class_name(self, names)

    func get_elements_by_name(name):
        return _qs.get_elements_by_name(self, name)

    func forms():
        return self.get_elements_by_tag_name("form")

    func images():
        return self.get_elements_by_tag_name("img")

    func scripts():
        return self.get_elements_by_tag_name("script")

    func links():
        target := self
        return _nl.HTMLCollection(() => _sel.select_all(target, "a[href], area[href]"))

    # ------------------------------------------------------------ focus

    func active_element():
        if self._active != null and self._active.is_connected() and self._active.owner_document == self:
            return self._active
        return self.body()

    func has_focus():
        return self.visibility_state == "visible"

    # Déplace le focus (null : vers le corps) avec blur / focusout puis focus / focusin.
    func set_focus(element):
        old := self._active
        if old == element:
            return
        self._active = element
        if old != null:
            _et.dispatch(old, _ev.focus_event("blur", element), true)
            _et.dispatch(old, _ev.focus_event("focusout", element), true)
        if element != null:
            _et.dispatch(element, _ev.focus_event("focus", old), true)
            _et.dispatch(element, _ev.focus_event("focusin", old), true)

    # Ordre de tabulation : tabindex positifs croissants, puis l'ordre du document.
    func tab_order():
        positives := []
        zeros := []
        for e in _sel.descendants(self):
            if not e.is_focusable():
                continue
            t := e.tab_index()
            if t > 0:
                append(positives, e)
            elif t == 0:
                append(zeros, e)
        i := 1
        while i < len(positives):
            cur := positives[i]
            j := i - 1
            while j >= 0 and positives[j].tab_index() > cur.tab_index():
                positives[j + 1] = positives[j]
                j -= 1
            positives[j + 1] = cur
            i += 1
        return positives + zeros

    # Focus suivant (ou précédent) dans l'ordre de tabulation ; renvoie l'élément focalisé.
    func focus_next(backward=false):
        order := self.tab_order()
        if len(order) == 0:
            return null
        cur := self._active
        idx := -1
        i := 0
        for e in order:
            if e == cur:
                idx = i
            i += 1
        nxt := 0
        if backward:
            nxt = (idx - 1) if idx > 0 else len(order) - 1
        else:
            nxt = (idx + 1) if idx >= 0 and idx + 1 < len(order) else 0
        order[nxt].focus()
        return order[nxt]

    # ------------------------------------------------------------ navigation et formulaires

    func navigate(url, target=null):
        if self.on_navigate != null:
            self.on_navigate(url, target)
        else:
            append(self.navigations, (url, target))

    func submit_form(form, submitter=null):
        if self.on_submit != null:
            self.on_submit(form, submitter)
        else:
            append(self.submissions, (form, form.form_entries(submitter)))

    # ------------------------------------------------------------ observateurs de géométrie

    func register_layout_observer(o):
        if not (o in self.layout_observers):
            append(self.layout_observers, o)

    func unregister_layout_observer(o):
        kept := []
        for x in self.layout_observers:
            if x != o:
                append(kept, x)
        self.layout_observers = kept

    # À appeler après un changement de géométrie (fait par set_layout, le défilement et le redimensionnement).
    func layout_changed():
        for o in self.layout_observers:
            o.check()

    # ------------------------------------------------------------ cycle de vie

    # Termine le chargement : readystatechange, DOMContentLoaded, puis load sur la fenêtre.
    func finish_loading():
        self.ready_state = "interactive"
        _et.dispatch(self, _ev.Event("readystatechange"), true)
        _et.dispatch(self, _ev.Event("DOMContentLoaded", true, false), true)
        self.ready_state = "complete"
        _et.dispatch(self, _ev.Event("readystatechange"), true)
        if self.default_view != null:
            _et.dispatch(self.default_view, _ev.Event("load"), true)

    # ------------------------------------------------------------ divers

    func get_the_parent(event):
        if event.type == "load":
            return null
        return self.default_view

    func _clone_self(doc):
        d := Document(self.content_type, self.url)
        return d

    func clone_node(deep=false):
        d := Document(self.content_type, self.url)
        if deep:
            for c in self.nodes:
                d.append_child(d.import_node(c, true))
        return d

    func to_html():
        return _el.serialize_children(self)

    func outer_html():
        return self.to_html()

    func __str__():
        return "<#document " + self.url + ">"

class DOMImplementation:
    func init(doc):
        self.document = doc

    func create_document_type(name, public_id="", system_id=""):
        return _text.DocumentType(name, public_id, system_id, self.document)

    func create_html_document(title=null):
        return new_document(title)

    func has_feature():
        return true

func _collapse(t):
    parts := []
    for w in _s.split(_s.replace(_s.replace(_s.replace(t, "\n", " "), "\t", " "), "\r", " "), " "):
        if w != "":
            append(parts, w)
    return _s.join(" ", parts)

# Document HTML5 vide : <!DOCTYPE html><html><head><title>…</title></head><body></body></html>.
func new_document(title=null, lang=null):
    d := Document()
    d.append_child(_text.DocumentType("html", "", "", d))
    html := d.create_element("html")
    if lang != null:
        html.set_attribute("lang", lang)
    head := d.create_element("head")
    html.append_child(head)
    if title != null:
        t := d.create_element("title")
        t.set_text_content(title)
        head.append_child(t)
    html.append_child(d.create_element("body"))
    d.append_child(html)
    return d

# Document depuis un document web.html (arbre converti).
func from_html_document(hdoc, url="about:blank"):
    d := Document("text/html", url)
    for h in hdoc.children:
        n := _el.from_html_node(h, d)
        if n != null:
            append(d.nodes, n)
            n.parent_node = d
    if hdoc.doctype() == null:
        d.compat_mode = "BackCompat"
    return d

# Analyse un texte HTML (tolérante, comme un navigateur) en Document DOM.
func parse_html(text, url="about:blank"):
    return from_html_document(_hp.parse(str(text)), url)

# Document XML minimal (sans espaces de noms HTML ; pas d'analyse XML).
func new_xml_document(root_name=null):
    d := Document("application/xml")
    if root_name != null:
        d.append_child(d.create_element_ns(null, root_name))
    return d
