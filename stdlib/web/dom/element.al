# ALEX STANDARD LIBRARY — web.dom.element
#
# Element : attributs (get_attribute, set_attribute, toggle_attribute… et NamedNodeMap), id, classes
# (class_list), données (dataset), style en ligne (style : CSSStyleDeclaration), recherche (matches, closest,
# query_selector…), enfants éléments, HTML (inner_html / outer_html / insert_adjacent_html, analysés par
# web.html), propriétés de formulaires (value, checked, disabled…), focus, click() avec comportements par
# défaut (case à cocher, bouton radio, envoi de formulaire, lien, étiquette), et géométrie simulée
# (set_layout / get_bounding_client_rect) pour les observateurs.
#
#   el := document.create_element("a")
#   el.set_attribute("href", "/aide")
#   el.class_list.add("lien")
#   el.dataset.set("suivi", "menu")            # data-suivi="menu"
#   el.style.set_property("color", "red")      # style="color: red"
#   el.set_inner_html("Aide <b>en ligne</b>")
#   el.outer_html()                            # <a href="/aide" class="lien" data-suivi="menu" style="color: red">Aide <b>en ligne</b></a>
#   el.matches("a.lien"), el.closest("nav")
#
# Erreurs : InvalidCharacterError (nom invalide), SyntaxError (sélecteur ou position invalide),
# HierarchyRequestError, NotFoundError.

from core use len, type, to_int, to_float
from collections use append, keys
use string as _s
use web.dom.dom_errors as _err
use web.dom.node as _node
use web.dom.node_list as _nl
use web.dom.attributes as _attrs
use web.dom.class_list as _cl
use web.dom.text as _text
use web.dom.selectors as _sel
use web.dom.query_selector as _qs
use web.dom.event as _ev
use web.dom.mouse_event as _mouse
use web.dom.event_target as _et
use web.css.declaration as _decl
use web.css.property as _prop
use web.html.html_parser as _hp
use web.html.html_escape as _hesc
from web.dom.node use Node

const HTML_NS := "http://www.w3.org/1999/xhtml"
const SVG_NS := "http://www.w3.org/2000/svg"
const MATHML_NS := "http://www.w3.org/1998/Math/MathML"

const VOID_ELEMENTS := ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr", "param", "keygen", "basefont", "bgsound", "frame"]
const RAW_TEXT := ["script", "style", "xmp", "iframe", "noembed", "noframes", "plaintext", "noscript"]
const FOCUSABLE := ["a", "button", "input", "select", "textarea", "iframe", "summary", "area"]
const FORM_CONTROLS := ["input", "select", "textarea", "button", "fieldset", "output", "object"]

func is_valid_name(name):
    if type(name) != "str" or len(name) == 0:
        return false
    c := name[0]
    if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c == ':' or _s.ord(c) >= 128):
        return false
    for ch in name:
        o := _s.ord(ch)
        if o <= 32 or ch == '<' or ch == '>' or ch == '/' or ch == '"' or ch == '\'' or ch == '=' or ch == '&':
            return false
    return true

# ---------------------------------------------------------------- géométrie

class DOMRect:
    func init(x=0, y=0, width=0, height=0):
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.left = x if width >= 0 else x + width
        self.top = y if height >= 0 else y + height
        self.right = self.left + (width if width >= 0 else -width)
        self.bottom = self.top + (height if height >= 0 else -height)

    func to_dict():
        return {"x": self.x, "y": self.y, "width": self.width, "height": self.height, "top": self.top, "right": self.right, "bottom": self.bottom, "left": self.left}

    func area():
        return self.width * self.height

    # Intersection avec un autre rectangle (rectangle vide si disjoints).
    func intersection(o):
        l := self.left if self.left > o.left else o.left
        t := self.top if self.top > o.top else o.top
        r := self.right if self.right < o.right else o.right
        b := self.bottom if self.bottom < o.bottom else o.bottom
        if r <= l or b <= t:
            return DOMRect(l, t, 0, 0)
        return DOMRect(l, t, r - l, b - t)

    func __str__():
        return "DOMRect(" + str(self.x) + ", " + str(self.y) + ", " + str(self.width) + ", " + str(self.height) + ")"

# ---------------------------------------------------------------- dataset et style

func _data_name(key):
    # « suiviMenu » / « suivi_menu » -> data-suivi-menu
    out := []
    for c in str(key):
        if c >= 'A' and c <= 'Z':
            append(out, "-")
            append(out, _s.lower(str(c)))
        elif c == '_':
            append(out, "-")
        else:
            append(out, str(c))
    return "data-" + _s.join("", out)

func _data_key(attr):
    rest := attr[5:len(attr)]
    out := []
    up := false
    for c in rest:
        if c == '-':
            up = true
        elif up:
            append(out, _s.upper(str(c)))
            up = false
        else:
            append(out, str(c))
    return _s.join("", out)

# element.dataset : attributs data-* vus comme un dictionnaire (clés camelCase ou snake_case).
class DOMStringMap:
    func init(element):
        self.element = element

    func get(key, fallback=null):
        v := self.element.get_attribute(_data_name(key))
        return v if v != null else fallback

    func set(key, value):
        self.element.set_attribute(_data_name(key), str(value))
        return self

    func delete(key):
        self.element.remove_attribute(_data_name(key))
        return self

    func __contains__(key):
        return self.element.has_attribute(_data_name(key))

    func __getitem__(key):
        return self.get(key)

    func keys():
        out := []
        for a in self.element.attr_list:
            if _s.starts_with(a.name, "data-"):
                append(out, _data_key(a.name))
        return out

    func to_dict():
        out := {}
        for a in self.element.attr_list:
            if _s.starts_with(a.name, "data-"):
                out[_data_key(a.name)] = a.value
        return out

# element.style : déclarations de l'attribut style (lecture et écriture).
class CSSStyleDeclaration:
    func init(element):
        self.element = element

    func _decls():
        t := self.element.get_attribute("style")
        if t == null:
            return []
        return _decl.parse_block(t)

    func _write(decls):
        if len(decls) == 0:
            self.element.remove_attribute("style")
        else:
            self.element.set_attribute("style", _decl.to_css(decls))

    func css_text():
        return _decl.to_css(self._decls())

    func set_css_text(text):
        self._write(_decl.parse_block(str(text)))

    func length():
        return len(self._decls())

    func __len__():
        return self.length()

    func item(i):
        d := self._decls()
        if i < 0 or i >= len(d):
            return ""
        return d[i].property

    func get_property_value(name):
        d := _decl.find(self._decls(), name)
        return d.value if d != null else ""

    func get_property_priority(name):
        d := _decl.find(self._decls(), name)
        return "important" if d != null and d.important else ""

    # value vide ou null : retire la propriété ; priority : "important" ou "".
    func set_property(name, value, priority=""):
        n := _prop.canonical(name)
        kept := []
        for d in self._decls():
            if d.property != n:
                append(kept, d)
        if value != null and str(value) != "":
            append(kept, _decl.Declaration(n, str(value), priority == "important"))
        self._write(kept)

    func remove_property(name):
        old := self.get_property_value(name)
        self.set_property(name, null)
        return old

    # Raccourcis : style.get("font_size"), style.set("backgroundColor", "red").
    func get(name):
        return self.get_property_value(name)

    func set(name, value):
        self.set_property(name, value)
        return self

    func to_dict():
        return _decl.to_dict(self._decls())

    func __str__():
        return self.css_text()

# ---------------------------------------------------------------- élément

class Element extends Node:
    func init(local_name, owner_document=null, namespace_uri="http://www.w3.org/1999/xhtml", prefix=null):
        if not is_valid_name(local_name):
            _err.invalid_character("Element", "nom d'élément invalide « " + str(local_name) + " »")
        ns := null if namespace_uri == false else namespace_uri
        html := ns == HTML_NS
        ln := _s.lower(local_name) if html else local_name
        qualified := (prefix + ":" + ln) if prefix != null else ln
        super.init(_node.ELEMENT_NODE, _s.upper(qualified) if html else qualified, owner_document)
        self.local_name = ln
        self.namespace_uri = ns
        self.prefix = prefix
        self.tag_name = self.node_name
        self.attr_list = []
        self.attributes = _attrs.NamedNodeMap(self)
        self.class_list = _cl.DOMTokenList(self, "class")
        self.rel_list = _cl.DOMTokenList(self, "rel", ["alternate", "author", "bookmark", "external", "help", "icon", "license", "manifest", "modulepreload", "next", "nofollow", "noopener", "noreferrer", "opener", "pingback", "preconnect", "prefetch", "preload", "prev", "search", "stylesheet", "tag"])
        self.dataset = DOMStringMap(self)
        self.style = CSSStyleDeclaration(self)
        self.states = []                # états d'interaction simulés : hover, active, visited, target…
        self.layout = null              # DOMRect simulé (set_layout)
        self.scroll_top = 0
        self.scroll_left = 0
        self.shadow_root = null
        self._value = null              # valeur « sale » des champs (modifiée par l'utilisateur ou le script)
        self._checked = null
        self._selectedness = null

    func is_html():
        return self.namespace_uri == HTML_NS

    # ------------------------------------------------------------ attributs

    func _attr_key(name):
        return _s.lower(name) if self.is_html() else name

    func get_attribute(name):
        n := self._attr_key(name)
        for a in self.attr_list:
            if a.name == n:
                return a.value
        return null

    func has_attribute(name):
        return self.get_attribute(name) != null

    func has_attributes():
        return len(self.attr_list) > 0

    func get_attribute_names():
        out := []
        for a in self.attr_list:
            append(out, a.name)
        return out

    func set_attribute(name, value):
        _attrs.check_name(name, "set_attribute")
        n := self._attr_key(name)
        v := str(value) if type(value) != "bool" else ("" if value else "false")
        for a in self.attr_list:
            if a.name == n:
                old := a.value
                a.value = v
                self._attribute_changed(n, old, v)
                return
        append(self.attr_list, _attrs.Attr(n, v, self))
        self._attribute_changed(n, null, v)

    func remove_attribute(name):
        n := self._attr_key(name)
        kept := []
        old := null
        for a in self.attr_list:
            if a.name == n:
                old = a.value
                a.owner_element = null
            else:
                append(kept, a)
        if old != null:
            self.attr_list = kept
            self._attribute_changed(n, old, null)

    # Bascule un attribut booléen ; renvoie sa présence finale.
    func toggle_attribute(name, force=null):
        _attrs.check_name(name, "toggle_attribute")
        has := self.has_attribute(name)
        if has and force != true:
            self.remove_attribute(name)
            return false
        if not has and force != false:
            self.set_attribute(name, "")
            return true
        return has

    func get_attribute_node(name):
        return self.attributes.get_named_item(name)

    func set_attribute_node(attr):
        return self.attributes.set_named_item(attr)

    func get_attribute_ns(namespace_uri, local_name):
        a := self.attributes.get_named_item_ns(namespace_uri, local_name)
        return a.value if a != null else null

    func set_attribute_ns(namespace_uri, qualified_name, value):
        _attrs.check_name(qualified_name, "set_attribute_ns")
        for a in self.attr_list:
            if a.name == qualified_name and a.namespace_uri == namespace_uri:
                old := a.value
                a.value = str(value)
                self._attribute_changed(qualified_name, old, a.value)
                return
        append(self.attr_list, _attrs.Attr(qualified_name, value, self, namespace_uri))
        self._attribute_changed(qualified_name, null, str(value))

    func _attribute_changed(name, old, new_value):
        hub := self._hub()
        if hub != null:
            hub.queue("attributes", self, [], [], null, null, name, old)

    func id():
        v := self.get_attribute("id")
        return v if v != null else ""

    func set_id(v):
        self.set_attribute("id", v)

    func class_name():
        v := self.get_attribute("class")
        return v if v != null else ""

    func set_class_name(v):
        self.set_attribute("class", v)

    # ------------------------------------------------------------ enfants éléments

    func element_children():
        return _qs.element_children(self)

    func children():
        target := self
        return _nl.HTMLCollection(() => _qs.element_children(target))

    func child_element_count():
        return len(self.element_children())

    func first_element_child():
        l := self.element_children()
        return l[0] if len(l) > 0 else null

    func last_element_child():
        l := self.element_children()
        return l[len(l) - 1] if len(l) > 0 else null

    func previous_element_sibling():
        n := self.previous_sibling()
        while n != null and n.node_type != _node.ELEMENT_NODE:
            n = n.previous_sibling()
        return n

    func next_element_sibling():
        n := self.next_sibling()
        while n != null and n.node_type != _node.ELEMENT_NODE:
            n = n.next_sibling()
        return n

    # ------------------------------------------------------------ sélecteurs

    func matches(selector):
        return _sel.matches(self, selector)

    func closest(selector):
        return _sel.closest(self, selector)

    func query_selector(selector):
        return _qs.query_selector(self, selector)

    func query_selector_all(selector):
        return _qs.query_selector_all(self, selector)

    func get_elements_by_tag_name(name):
        return _qs.get_elements_by_tag_name(self, name)

    func get_elements_by_class_name(names):
        return _qs.get_elements_by_class_name(self, names)

    # Interface de web.css.selector.DomAdapter.
    func is_empty_for_selector():
        for c in self.nodes:
            if c.node_type == _node.ELEMENT_NODE or ((c.node_type == _node.TEXT_NODE or c.node_type == _node.CDATA_SECTION_NODE) and c.data != ""):
                return false
        return true

    func selector_state(name):
        if name == "checked":
            return self.checked() or (self.local_name == "option" and self.selected())
        if name == "placeholder-shown":
            return self.value() == ""
        doc := self.owner_document
        active := doc.active_element() if doc != null else null
        if name == "focus":
            return active == self
        if name == "focus-visible":
            return active == self and (doc.focus_visible if doc != null else true)
        if name == "focus-within":
            return active != null and self.contains(active)
        if name == "target":
            return doc != null and doc.target_id != null and self.id() == doc.target_id
        if name == "indeterminate":
            return "indeterminate" in self.states
        if name == "valid":
            return self.check_validity()
        if name == "invalid":
            return self.local_name in ["input", "textarea", "select", "form"] and not self.check_validity()
        if name == "hover" or name == "active":
            e := self
            while e != null:
                if e.node_type == _node.ELEMENT_NODE and name in e.states:
                    return true
                e = e.parent_node
            return false
        return name in self.states

    func set_state(name, on=true):
        if on and not (name in self.states):
            append(self.states, name)
        elif not on:
            kept := []
            for s in self.states:
                if s != name:
                    append(kept, s)
            self.states = kept
        return self

    # ------------------------------------------------------------ HTML

    func inner_html():
        return serialize_children(self)

    func set_inner_html(html):
        nodes := from_html_fragment(str(html), self.local_name, self.owner_document)
        self.replace_children(nodes)

    func outer_html():
        return serialize(self)

    func set_outer_html(html):
        p := self.parent_node
        if p == null:
            return
        if p.node_type == _node.DOCUMENT_NODE:
            _err.fail("NoModificationAllowedError", "set_outer_html", "l'élément racine ne peut pas être remplacé")
        ctx := p.local_name if p.node_type == _node.ELEMENT_NODE else "body"
        nodes := from_html_fragment(str(html), ctx, self.owner_document)
        frag := _node.make("fragment", self.owner_document)
        for n in nodes:
            frag.append_child(n)
        p.replace_child(frag, self)

    # position : beforebegin, afterbegin, beforeend, afterend.
    func insert_adjacent_html(position, html):
        pos := _s.lower(position)
        ctx := self.local_name
        if pos == "beforebegin" or pos == "afterend":
            p := self.parent_node
            ctx = p.local_name if p != null and p.node_type == _node.ELEMENT_NODE else "body"
        frag := _node.make("fragment", self.owner_document)
        for n in from_html_fragment(str(html), ctx, self.owner_document):
            frag.append_child(n)
        self._insert_adjacent(pos, frag)

    func insert_adjacent_element(position, element):
        return self._insert_adjacent(_s.lower(position), element)

    func insert_adjacent_text(position, data):
        self._insert_adjacent(_s.lower(position), _text.Text(str(data), self.owner_document))

    func _insert_adjacent(pos, node):
        if pos == "beforebegin":
            if self.parent_node == null:
                return null
            self.parent_node.insert_before(node, self)
        elif pos == "afterbegin":
            self.insert_before(node, self.first_child())
        elif pos == "beforeend":
            self.append_child(node)
        elif pos == "afterend":
            if self.parent_node == null:
                return null
            self.parent_node.insert_before(node, self.next_sibling())
        else:
            _err.syntax("insert_adjacent", "position inconnue « " + pos + " »")
        return node

    # Texte rendu approximatif : <br> -> saut de ligne, blocs séparés, script / style ignorés.
    func inner_text():
        parts := []
        _rendered_text(self, parts)
        return _s.trim(_s.join("", parts))

    func set_inner_text(value):
        lines := _s.split(str(value), "\n")
        items := []
        i := 0
        while i < len(lines):
            if i > 0:
                append(items, Element("br", self.owner_document))
            if lines[i] != "":
                append(items, _text.Text(lines[i], self.owner_document))
            i += 1
        self.replace_children(items)

    # ------------------------------------------------------------ clonage

    func _clone_self(doc):
        e := Element(self.local_name, doc, self.namespace_uri if self.namespace_uri != null else false, self.prefix)
        for a in self.attr_list:
            append(e.attr_list, _attrs.Attr(a.name, a.value, e, a.namespace_uri))
        if self._value != null:
            e._value = self._value
        if self._checked != null:
            e._checked = self._checked
        return e

    func _equal_self(other):
        if other.namespace_uri != self.namespace_uri or other.local_name != self.local_name or len(other.attr_list) != len(self.attr_list):
            return false
        for a in self.attr_list:
            if other.get_attribute(a.name) != a.value:
                return false
        return true

    # ------------------------------------------------------------ formulaires

    func value():
        t := self.local_name
        if t == "input":
            if self._value != null:
                return self._value
            v := self.get_attribute("value")
            ty := self.input_type()
            if v == null:
                return "on" if ty == "checkbox" or ty == "radio" else ""
            return v
        if t == "textarea":
            return self._value if self._value != null else self.text_content()
        if t == "select":
            for o in self.options():
                if o.selected():
                    return o.value()
            return ""
        if t == "option":
            v := self.get_attribute("value")
            return v if v != null else _collapse(self.text_content())
        if t == "button" or t == "output" or t == "data" or t == "li" or t == "param" or t == "meter" or t == "progress":
            v := self.get_attribute("value")
            return v if v != null else ""
        return self.get_attribute("value")

    func set_value(v):
        t := self.local_name
        if t == "select":
            for o in self.options():
                o._selectedness = o.value() == str(v)
            return
        if t == "input" or t == "textarea":
            self._value = str(v) if v != null else ""
            return
        self.set_attribute("value", v)

    func default_value():
        if self.local_name == "textarea":
            return self.text_content()
        v := self.get_attribute("value")
        return v if v != null else ""

    func input_type():
        if self.local_name != "input":
            return null
        t := self.get_attribute("type")
        return _s.lower(t) if t != null and t != "" else "text"

    func checked():
        if self._checked != null:
            return self._checked
        return self.has_attribute("checked")

    func set_checked(on):
        self._checked = on == true
        if self._checked and self.input_type() == "radio":
            for r in self._radio_group():
                if r != self:
                    r._checked = false

    func _radio_group():
        name := self.get_attribute("name")
        if name == null or name == "":
            return [self]
        root := self.form()
        if root == null:
            root = self.get_root_node()
        out := []
        for e in _sel.descendants(root):
            if e.local_name == "input" and e.input_type() == "radio" and e.get_attribute("name") == name:
                append(out, e)
        return out

    func selected():
        if self._selectedness != null:
            return self._selectedness
        if self.has_attribute("selected"):
            return true
        sel := self.closest("select")
        if sel != null and not sel.has_attribute("multiple"):
            any_selected := false
            for o in sel.options():
                if o._selectedness == true or (o._selectedness == null and o.has_attribute("selected")):
                    any_selected = true
            if not any_selected:
                opts := sel.options()
                return len(opts) > 0 and opts[0] == self
        return false

    func set_selected(on):
        self._selectedness = on == true
        sel := self.closest("select")
        if on and sel != null and not sel.has_attribute("multiple"):
            for o in sel.options():
                if o != self:
                    o._selectedness = false

    func options():
        out := []
        for e in _sel.descendants(self):
            if e.local_name == "option":
                append(out, e)
        return out

    func selected_index():
        i := 0
        for o in self.options():
            if o.selected():
                return i
            i += 1
        return -1

    func disabled():
        if self.has_attribute("disabled"):
            return true
        if self.local_name in FORM_CONTROLS:
            f := self.parent_node
            while f != null and f.node_type == _node.ELEMENT_NODE:
                if f.local_name == "fieldset" and f.has_attribute("disabled"):
                    return true
                f = f.parent_node
        return false

    func set_disabled(on):
        self.toggle_attribute("disabled", on == true)

    func hidden():
        return self.has_attribute("hidden")

    func set_hidden(on):
        self.toggle_attribute("hidden", on == true)

    func form():
        fid := self.get_attribute("form")
        if fid != null and self.owner_document != null:
            f := self.owner_document.get_element_by_id(fid)
            if f != null and f.local_name == "form":
                return f
        e := self.parent_node
        while e != null and e.node_type == _node.ELEMENT_NODE:
            if e.local_name == "form":
                return e
            e = e.parent_node
        return null

    # Contrôles d'un formulaire (ordre du document).
    func elements():
        out := []
        for e in _sel.descendants(self):
            if e.local_name in ["input", "select", "textarea", "button", "fieldset", "output", "object"]:
                append(out, e)
        return out

    # Validation de contraintes simplifiée (required, pattern absent, types email / url / number, min / max).
    func check_validity():
        return self.validation_message() == ""

    func validation_message():
        t := self.local_name
        if t == "form":
            for e in self.elements():
                m := e.validation_message()
                if m != "":
                    return m
            return ""
        if not (t in ["input", "textarea", "select"]) or self.disabled():
            return ""
        v := self.value()
        ty := self.input_type()
        if self.has_attribute("required"):
            if (ty == "checkbox" or ty == "radio") and not self._group_checked():
                return "Cochez cette case pour continuer."
            if not (ty == "checkbox" or ty == "radio") and v == "":
                return "Veuillez renseigner ce champ."
        if v == "":
            return ""
        if ty == "email" and (not _s.contains(v, "@") or _s.starts_with(v, "@") or _s.ends_with(v, "@")):
            return "Adresse électronique invalide."
        if ty == "url" and not _s.contains(v, "://"):
            return "URL invalide."
        if ty == "number" or ty == "range":
            n := null
            try:
                n = _to_number(v)
            catch e:
                return "Veuillez saisir un nombre."
            mn := self.get_attribute("min")
            mx := self.get_attribute("max")
            if mn != null and n < _to_number(mn):
                return "La valeur doit être supérieure ou égale à " + mn + "."
            if mx != null and n > _to_number(mx):
                return "La valeur doit être inférieure ou égale à " + mx + "."
        ml := self.get_attribute("maxlength")
        if ml != null and len(v) > to_int(ml):
            return "Texte trop long."
        mnl := self.get_attribute("minlength")
        if mnl != null and len(v) < to_int(mnl):
            return "Texte trop court."
        return ""

    func _group_checked():
        if self.input_type() == "radio":
            for r in self._radio_group():
                if r.checked():
                    return true
            return false
        return self.checked()

    func select():
        self.set_state("selected-text", true)

    # ------------------------------------------------------------ focus et activation

    func tab_index():
        v := self.get_attribute("tabindex")
        if v != null:
            try:
                return to_int(v)
            catch e:
                pass
        if self.local_name in FOCUSABLE and not (self.local_name == "a" and not self.has_attribute("href")):
            return 0
        return -1

    func is_focusable():
        if self.disabled() or self.hidden():
            return false
        if self.has_attribute("contenteditable") and self.get_attribute("contenteditable") != "false":
            return true
        if self.has_attribute("tabindex"):
            return true
        return self.tab_index() >= 0

    func focus():
        if self.owner_document != null and self.is_focusable() and self.is_connected():
            self.owner_document.set_focus(self)

    func blur():
        if self.owner_document != null and self.owner_document.active_element() == self:
            self.owner_document.set_focus(null)

    # Clic synthétique : distribution d'un click puis comportement par défaut s'il n'est pas annulé.
    func click():
        if self.disabled():
            return false
        ty := self.input_type()
        old_checked := self.checked()
        old_group := []
        if self.local_name == "input" and ty == "checkbox":
            self._checked = not old_checked
        elif self.local_name == "input" and ty == "radio":
            for r in self._radio_group():
                append(old_group, (r, r.checked()))
            self.set_checked(true)
        e := _mouse.MouseEvent("click", {"detail": 1})
        ok := _et.dispatch(self, e)
        if not ok:
            if self.local_name == "input" and ty == "checkbox":
                self._checked = old_checked
            elif self.local_name == "input" and ty == "radio":
                for pair in old_group:
                    pair[0]._checked = pair[1]
            return false
        self._activate(old_checked)
        return true

    func _activate(old_checked):
        t := self.local_name
        ty := self.input_type()
        if t == "input" and (ty == "checkbox" or ty == "radio"):
            if self.checked() != old_checked:
                _et.dispatch(self, _ev.Event("input", true, false, true))
                _et.dispatch(self, _ev.Event("change", true, false))
            return
        if (t == "button" and (self.get_attribute("type") == null or _s.lower(self.get_attribute("type")) == "submit")) or (t == "input" and (ty == "submit" or ty == "image")):
            f := self.form()
            if f != null:
                f.request_submit(self)
            return
        if (t == "button" and _s.lower(self.get_attribute("type") if self.get_attribute("type") != null else "") == "reset") or (t == "input" and ty == "reset"):
            f := self.form()
            if f != null:
                f.reset()
            return
        if t == "label":
            c := self.control()
            if c != null and c != self:
                c.click()
                c.focus()
            return
        if (t == "a" or t == "area") and self.has_attribute("href"):
            doc := self.owner_document
            if doc != null:
                doc.navigate(self.get_attribute("href"), self.get_attribute("target"))
            return
        if t == "summary":
            d := self.parent_node
            if d != null and d.node_type == _node.ELEMENT_NODE and d.local_name == "details":
                d.toggle_attribute("open")
                _et.dispatch(d, _ev.Event("toggle"))

    # Contrôle associé à une étiquette (attribut for, ou premier contrôle descendant).
    func control():
        if self.local_name != "label":
            return null
        f := self.get_attribute("for")
        if f != null and self.owner_document != null:
            return self.owner_document.get_element_by_id(f)
        for e in _sel.descendants(self):
            if e.local_name in ["input", "select", "textarea", "button", "meter", "output", "progress"]:
                return e
        return null

    # Envoi de formulaire : validation (sauf novalidate), événement submit annulable, puis document.on_submit.
    func request_submit(submitter=null):
        if self.local_name != "form":
            _err.dom_error("request_submit", "seul un <form> peut être envoyé")
        novalidate := self.has_attribute("novalidate") or (submitter != null and submitter.has_attribute("formnovalidate"))
        if not novalidate:
            for c in self.elements():
                if not c.check_validity():
                    _et.dispatch(c, _ev.Event("invalid", false, true))
                    return false
        e := _ev.Event("submit", true, true)
        e.submitter = submitter
        if not _et.dispatch(self, e):
            return false
        doc := self.owner_document
        if doc != null:
            doc.submit_form(self, submitter)
        return true

    func submit():
        doc := self.owner_document
        if doc != null:
            doc.submit_form(self, null)

    func reset():
        e := _ev.Event("reset", true, true)
        if not _et.dispatch(self, e):
            return
        for c in self.elements():
            c._value = null
            c._checked = null
            for o in c.options():
                o._selectedness = null

    # Données du formulaire : liste de (nom, valeur) des contrôles « réussis » (comme FormData).
    func form_entries(submitter=null):
        out := []
        for c in self.elements():
            name := c.get_attribute("name")
            if name == null or name == "" or c.disabled():
                continue
            t := c.local_name
            ty := c.input_type()
            if t == "button" or (t == "input" and (ty == "submit" or ty == "image" or ty == "reset" or ty == "button")):
                if c == submitter:
                    append(out, (name, c.value()))
                continue
            if t == "input" and (ty == "checkbox" or ty == "radio"):
                if c.checked():
                    append(out, (name, c.value()))
                continue
            if t == "input" and ty == "file":
                continue
            if t == "select":
                for o in c.options():
                    if o.selected():
                        append(out, (name, o.value()))
                continue
            if t == "fieldset" or t == "output" or t == "object":
                continue
            append(out, (name, c.value()))
        return out

    # ------------------------------------------------------------ géométrie simulée

    func set_layout(x, y, width, height):
        self.layout = DOMRect(x, y, width, height)
        doc := self.owner_document
        if doc != null:
            doc.layout_changed()
        return self

    func get_bounding_client_rect():
        if self.layout == null:
            return DOMRect()
        r := self.layout
        dx := 0
        dy := 0
        doc := self.owner_document
        if doc != null and doc.default_view != null:
            dx = doc.default_view.scroll_x
            dy = doc.default_view.scroll_y
        return DOMRect(r.x - dx, r.y - dy, r.width, r.height)

    func get_client_rects():
        if self.layout == null:
            return []
        return [self.get_bounding_client_rect()]

    func offset_width():
        return self.layout.width if self.layout != null else 0

    func offset_height():
        return self.layout.height if self.layout != null else 0

    func client_width():
        return self.offset_width()

    func client_height():
        return self.offset_height()

    func scroll_into_view(options=null):
        doc := self.owner_document
        if doc != null and doc.default_view != null and self.layout != null:
            doc.default_view.scroll_to(doc.default_view.scroll_x, self.layout.y)

    func __str__():
        out := "<" + self.local_name
        i := self.get_attribute("id")
        if i != null:
            out = out + "#" + i
        c := self.get_attribute("class")
        if c != null and c != "":
            out = out + "." + _s.join(".", _cl.tokens(c))
        return out + ">"

func _to_number(v):
    t := _s.trim(str(v))
    if _s.contains(t, ".") or _s.contains(t, "e") or _s.contains(t, "E"):
        return to_float(t)
    return to_int(t)

func _collapse(t):
    parts := []
    for w in _s.split(_s.trim(_s.replace(_s.replace(_s.replace(t, "\n", " "), "\t", " "), "\r", " ")), " "):
        if w != "":
            append(parts, w)
    return _s.join(" ", parts)

const _BLOCKS := ["address", "article", "aside", "blockquote", "div", "dl", "dt", "dd", "fieldset", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li", "main", "nav", "ol", "p", "pre", "section", "table", "tr", "ul", "details", "summary"]

func _rendered_text(n, parts):
    for c in n.nodes:
        if c.node_type == _node.TEXT_NODE:
            append(parts, c.data)
        elif c.node_type == _node.ELEMENT_NODE:
            t := c.local_name
            if t in ["script", "style", "template", "head", "title", "noscript"] or c.has_attribute("hidden"):
                continue
            if t == "br":
                append(parts, "\n")
                continue
            if t in _BLOCKS and len(parts) > 0 and not _s.ends_with(parts[len(parts) - 1], "\n"):
                append(parts, "\n")
            _rendered_text(c, parts)
            if t in _BLOCKS:
                append(parts, "\n")
            elif t == "td" or t == "th":
                append(parts, "\t")

# ---------------------------------------------------------------- sérialisation HTML

func _escape_text(t):
    out := _s.replace(t, "&", "&amp;")
    out = _s.replace(out, "<", "&lt;")
    out = _s.replace(out, ">", "&gt;")
    return _s.replace(out, " ", "&nbsp;")

func _escape_attr(t):
    out := _s.replace(t, "&", "&amp;")
    out = _s.replace(out, "\"", "&quot;")
    return _s.replace(out, " ", "&nbsp;")

# HTML d'un nœud (algorithme de sérialisation HTML).
func serialize(n):
    parts := []
    _ser(n, parts, false)
    return _s.join("", parts)

func serialize_children(n):
    parts := []
    raw := n.node_type == _node.ELEMENT_NODE and n.local_name in RAW_TEXT
    for c in n.nodes:
        _ser(c, parts, raw)
    return _s.join("", parts)

func _ser(n, parts, raw_parent):
    t := n.node_type
    if t == _node.ELEMENT_NODE:
        name := n.local_name if n.is_html() else (n.prefix + ":" + n.local_name if n.prefix != null else n.local_name)
        append(parts, "<" + name)
        for a in n.attr_list:
            append(parts, " " + a.name + "=\"" + _escape_attr(a.value) + "\"")
        append(parts, ">")
        if n.is_html() and n.local_name in VOID_ELEMENTS:
            return
        raw := n.is_html() and n.local_name in RAW_TEXT
        for c in n.nodes:
            _ser(c, parts, raw)
        append(parts, "</" + name + ">")
    elif t == _node.TEXT_NODE:
        append(parts, n.data if raw_parent else _escape_text(n.data))
    elif t == _node.CDATA_SECTION_NODE:
        append(parts, "<![CDATA[" + n.data + "]]>")
    elif t == _node.COMMENT_NODE:
        append(parts, "<!--" + n.data + "-->")
    elif t == _node.PROCESSING_INSTRUCTION_NODE:
        append(parts, "<?" + n.target + " " + n.data + ">")
    elif t == _node.DOCUMENT_TYPE_NODE:
        append(parts, "<!DOCTYPE " + n.name + ">")
    else:
        for c in n.nodes:
            _ser(c, parts, raw_parent)

# ---------------------------------------------------------------- depuis web.html

func _ns_for(tag, parent_ns):
    if tag == "svg":
        return SVG_NS
    if tag == "math":
        return MATHML_NS
    if parent_ns == SVG_NS and tag == "foreignobject":
        return SVG_NS
    return parent_ns

# Nœud DOM depuis un nœud web.html (élément, texte, commentaire, doctype, html brut).
func from_html_node(h, doc, parent_ns="http://www.w3.org/1999/xhtml"):
    k := h.node_type
    if k == "element":
        ns := _ns_for(_s.lower(h.tag), parent_ns)
        e := Element(h.tag, doc, ns)
        for p in h.attributes.items():
            append(e.attr_list, _attrs.Attr(p[0], p[1], e))
        child_ns := ns if ns != SVG_NS or _s.lower(h.tag) != "foreignobject" else HTML_NS
        for c in h.children:
            x := from_html_node(c, doc, child_ns)
            if x != null:
                append(e.nodes, x)
                x.parent_node = e
        return e
    if k == "text":
        return _text.Text(h.text, doc)
    if k == "comment":
        return _text.Comment(h.text, doc)
    if k == "doctype":
        return _text.DocumentType(h.name, h.public_id, h.system_id, doc)
    if k == "raw":
        return _text.Text(h.markup, doc)
    return null

# Nœuds DOM d'un fragment HTML analysé dans le contexte d'un élément.
func from_html_fragment(html, context="div", doc=null):
    out := []
    for h in _hp.parse_fragment(html, context):
        x := from_html_node(h, doc)
        if x != null:
            append(out, x)
    return out
