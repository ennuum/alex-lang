# ALEX STANDARD LIBRARY — web.dom.node
#
# Node : la base de l'arbre DOM — type, nom, document propriétaire, parent, enfants (liste vivante),
# frères, insertion / retrait / remplacement avec les contrôles de hiérarchie du standard, fragments,
# clonage, égalité, position relative de deux nœuds, texte (text_content), normalisation, méthodes
# ChildNode / ParentNode (before, after, replace_with, remove, append, prepend, replace_children), et
# notification des mutations (MutationObserver) et chemin de propagation des événements.
#
#   n.append_child(enfant)              n.insert_before(nouveau, reference)     n.remove_child(enfant)
#   n.replace_child(nouveau, ancien)    n.first_child(), n.next_sibling()       n.child_nodes() (vivante)
#   n.contains(autre)                   n.compare_document_position(autre)      n.clone_node(true)
#   n.text_content()                    n.set_text_content("…")                 n.get_root_node()
#   n.before(x, "texte"), n.after(...), n.replace_with(...), n.remove()
#
# Erreurs : HierarchyRequestError (insertion invalide), NotFoundError (référence absente).

from core use len, type
from collections use append
use string as _s
use web.dom.dom_errors as _err
use web.dom.node_list as _nl
use web.dom.query_selector as _qs
use web.dom.mutation_observer as _mo
from web.dom.event_target use EventTarget

const ELEMENT_NODE := 1
const ATTRIBUTE_NODE := 2
const TEXT_NODE := 3
const CDATA_SECTION_NODE := 4
const PROCESSING_INSTRUCTION_NODE := 7
const COMMENT_NODE := 8
const DOCUMENT_NODE := 9
const DOCUMENT_TYPE_NODE := 10
const DOCUMENT_FRAGMENT_NODE := 11

const DOCUMENT_POSITION_DISCONNECTED := 1
const DOCUMENT_POSITION_PRECEDING := 2
const DOCUMENT_POSITION_FOLLOWING := 4
const DOCUMENT_POSITION_CONTAINS := 8
const DOCUMENT_POSITION_CONTAINED_BY := 16
const DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC := 32

# Fabriques enregistrées par les modules de nœuds (text, comment…) pour éviter les importations circulaires.
_factories := {}

func register_factory(kind, fn):
    _factories[kind] = fn

func make(kind, value):
    if not (kind in _factories):
        _err.dom_error("node.make", "fabrique « " + kind + " » non enregistrée (importer web.dom.text)")
    return _factories[kind](value)

func _is_chardata(n):
    t := n.node_type
    return t == TEXT_NODE or t == COMMENT_NODE or t == CDATA_SECTION_NODE or t == PROCESSING_INSTRUCTION_NODE

class Node extends EventTarget:
    func init(node_type, node_name, owner_document=null):
        super.init()
        self.node_type = node_type
        self.node_name = node_name
        self.owner_document = owner_document
        self.parent_node = null
        self.nodes = []                 # enfants (liste interne ; child_nodes() en donne une vue vivante)
        self.user_data = {}

    # ------------------------------------------------------------ navigation

    func child_nodes():
        target := self
        return _nl.NodeList(null, () => target.nodes)

    func has_child_nodes():
        return len(self.nodes) > 0

    func first_child():
        return self.nodes[0] if len(self.nodes) > 0 else null

    func last_child():
        return self.nodes[len(self.nodes) - 1] if len(self.nodes) > 0 else null

    func index():
        p := self.parent_node
        if p == null:
            return -1
        i := 0
        for c in p.nodes:
            if c == self:
                return i
            i += 1
        return -1

    func previous_sibling():
        i := self.index()
        if i <= 0:
            return null
        return self.parent_node.nodes[i - 1]

    func next_sibling():
        i := self.index()
        if i < 0 or i + 1 >= len(self.parent_node.nodes):
            return null
        return self.parent_node.nodes[i + 1]

    func parent_element():
        p := self.parent_node
        if p != null and p.node_type == ELEMENT_NODE:
            return p
        return null

    # Racine de l'arbre (le document s'il est connecté).
    func get_root_node():
        n := self
        while n.parent_node != null:
            n = n.parent_node
        return n

    func is_connected():
        return self.get_root_node().node_type == DOCUMENT_NODE

    # Vrai si other est ce nœud ou un de ses descendants.
    func contains(other):
        n := other
        while n != null:
            if n == self:
                return true
            n = n.parent_node
        return false

    func is_same_node(other):
        return self == other

    func ancestors():
        out := []
        n := self.parent_node
        while n != null:
            append(out, n)
            n = n.parent_node
        return out

    func document():
        if self.node_type == DOCUMENT_NODE:
            return self
        return self.owner_document

    # ------------------------------------------------------------ mutations

    func _hub():
        d := self.document()
        if d == null:
            return _mo.global_hub()
        return d.mutation_hub

    func _notify_children(added, removed, previous, following):
        hub := self._hub()
        if hub != null:
            hub.queue("childList", self, added, removed, previous, following, null, null)

    func _ensure_insertable(node, child):
        t := self.node_type
        if not (t == DOCUMENT_NODE or t == DOCUMENT_FRAGMENT_NODE or t == ELEMENT_NODE):
            _err.hierarchy("insert", "un nœud de type " + str(t) + " ne peut pas avoir d'enfants")
        if node.contains(self):
            _err.hierarchy("insert", "un nœud ne peut pas être inséré dans lui-même ou un de ses descendants")
        if child != null and child.parent_node != self:
            _err.not_found("insert", "le nœud de référence n'est pas un enfant de ce nœud")
        nt := node.node_type
        if not (nt == DOCUMENT_FRAGMENT_NODE or nt == DOCUMENT_TYPE_NODE or nt == ELEMENT_NODE or _is_chardata(node)):
            _err.hierarchy("insert", "type de nœud non insérable : " + str(nt))
        if (nt == TEXT_NODE and t == DOCUMENT_NODE) or (nt == DOCUMENT_TYPE_NODE and t != DOCUMENT_NODE):
            _err.hierarchy("insert", "un " + ("texte" if nt == TEXT_NODE else "doctype") + " ne peut pas être inséré ici")
        if t == DOCUMENT_NODE:
            self._ensure_document_child(node, child)

    func _ensure_document_child(node, child):
        elements := 0
        doctypes := 0
        for c in self.nodes:
            if c.node_type == ELEMENT_NODE:
                elements += 1
            elif c.node_type == DOCUMENT_TYPE_NODE:
                doctypes += 1
        incoming := [node]
        if node.node_type == DOCUMENT_FRAGMENT_NODE:
            incoming = node.nodes
        for n in incoming:
            if n.node_type == TEXT_NODE:
                _err.hierarchy("insert", "texte au niveau du document")
            if n.node_type == ELEMENT_NODE:
                elements += 1
            if n.node_type == DOCUMENT_TYPE_NODE:
                doctypes += 1
        if elements > 1:
            _err.hierarchy("insert", "un document n'a qu'un seul élément racine")
        if doctypes > 1:
            _err.hierarchy("insert", "un document n'a qu'un seul doctype")

    func _adopt(node):
        d := self.document()
        _set_owner(node, d)

    func _detach(child):
        kept := []
        for c in self.nodes:
            if c != child:
                append(kept, c)
        self.nodes = kept
        child.parent_node = null

    # Insère node avant child (null : à la fin) ; un fragment insère ses enfants. Renvoie node.
    func insert_before(node, child=null):
        if child == node:
            child = node.next_sibling()
        self._ensure_insertable(node, child)
        items := [node]
        if node.node_type == DOCUMENT_FRAGMENT_NODE:
            items = []
            for c in node.nodes:
                append(items, c)
            node.nodes = []
            for c in items:
                c.parent_node = null
            node._notify_children([], items, null, null)
        for it in items:
            old := it.parent_node
            if old != null:
                prev := it.previous_sibling()
                nxt := it.next_sibling()
                old._detach(it)
                old._notify_children([], [it], prev, nxt)
        idx := len(self.nodes)
        if child != null:
            idx = child.index()
        previous := self.nodes[idx - 1] if idx > 0 else null
        self.nodes = self.nodes[0:idx] + items + self.nodes[idx:len(self.nodes)]
        for it in items:
            it.parent_node = self
            self._adopt(it)
        if len(items) > 0:
            self._notify_children(items, [], previous, child)
            for it in items:
                it._was_inserted()
        return node

    # Point d'extension : appelé quand le nœud change de document propriétaire.
    func _adopted(doc):
        return null

    # Point d'extension : appelé après l'insertion d'un nœud (éléments : connexion, formulaires…).
    func _was_inserted():
        for c in self.nodes:
            c._was_inserted()

    func append_child(node):
        return self.insert_before(node, null)

    func remove_child(child):
        if child.parent_node != self:
            _err.not_found("remove_child", "le nœud n'est pas un enfant de ce nœud")
        prev := child.previous_sibling()
        nxt := child.next_sibling()
        self._detach(child)
        self._notify_children([], [child], prev, nxt)
        return child

    func replace_child(node, child):
        if child.parent_node != self:
            _err.not_found("replace_child", "le nœud remplacé n'est pas un enfant de ce nœud")
        if node == child:
            return child
        ref := child.next_sibling()
        if ref == node:
            ref = node.next_sibling()
        self._ensure_insertable(node, null)
        prev := child.previous_sibling()
        self._detach(child)
        self._notify_children([], [child], prev, ref)
        self.insert_before(node, ref)
        return child

    # ------------------------------------------------------------ ChildNode / ParentNode

    func _to_node(x):
        if type(x) == "str":
            return make("text", x)
        return x

    func _convert(items):
        if len(items) == 1:
            return self._to_node(items[0])
        frag := make("fragment", self.document())
        for x in items:
            frag.append_child(self._to_node(x))
        return frag

    func remove():
        if self.parent_node != null:
            self.parent_node.remove_child(self)

    func before(items):
        p := self.parent_node
        if p == null:
            return
        p.insert_before(self._convert(_as_list(items)), self)

    func after(items):
        p := self.parent_node
        if p == null:
            return
        p.insert_before(self._convert(_as_list(items)), self.next_sibling())

    func replace_with(items):
        p := self.parent_node
        if p == null:
            return
        node := self._convert(_as_list(items))
        p.replace_child(node, self)

    func append(items):
        lst := _as_list(items)
        if len(lst) == 0:
            return self
        self.insert_before(self._convert(lst), null)
        return self

    func prepend(items):
        lst := _as_list(items)
        if len(lst) == 0:
            return self
        self.insert_before(self._convert(lst), self.first_child())
        return self

    func replace_children(items=null):
        lst := _as_list(items) if items != null else []
        removed := []
        for c in self.nodes:
            append(removed, c)
        for c in removed:
            c.parent_node = null
        self.nodes = []
        if len(removed) > 0:
            self._notify_children([], removed, null, null)
        if len(lst) > 0:
            self.insert_before(self._convert(lst), null)
        return self

    # ------------------------------------------------------------ texte

    func text_content():
        t := self.node_type
        if t == DOCUMENT_NODE or t == DOCUMENT_TYPE_NODE:
            return null
        if _is_chardata(self):
            return self.data
        parts := []
        _collect_text(self, parts)
        return _s.join("", parts)

    func set_text_content(value):
        t := self.node_type
        if t == DOCUMENT_NODE or t == DOCUMENT_TYPE_NODE:
            return
        if _is_chardata(self):
            self.set_data(str(value) if value != null else "")
            return
        v := str(value) if value != null else ""
        self.replace_children([make("text", v)] if v != "" else [])

    func node_value():
        if _is_chardata(self):
            return self.data
        return null

    func set_node_value(v):
        if _is_chardata(self):
            self.set_data(str(v) if v != null else "")

    # Fusionne les textes adjacents et retire les textes vides (dans tout le sous-arbre).
    func normalize():
        i := 0
        while i < len(self.nodes):
            c := self.nodes[i]
            if c.node_type == TEXT_NODE:
                if c.data == "":
                    self.remove_child(c)
                    continue
                while i + 1 < len(self.nodes) and self.nodes[i + 1].node_type == TEXT_NODE:
                    nxt := self.nodes[i + 1]
                    c.set_data(c.data + nxt.data)
                    self.remove_child(nxt)
            else:
                c.normalize()
            i += 1

    # ------------------------------------------------------------ clonage et comparaison

    func _clone_self(doc):
        _err.not_supported("clone_node", "nœud non clonable")

    func clone_node(deep=false):
        return _clone(self, deep, self.document() if self.node_type != DOCUMENT_NODE else null)

    func _equal_self(other):
        return true

    func is_equal_node(other):
        if other == null or other.node_type != self.node_type or other.node_name != self.node_name:
            return false
        if not self._equal_self(other):
            return false
        if len(self.nodes) != len(other.nodes):
            return false
        i := 0
        while i < len(self.nodes):
            if not self.nodes[i].is_equal_node(other.nodes[i]):
                return false
            i += 1
        return true

    func compare_document_position(other):
        if other == self:
            return 0
        if self.get_root_node() != other.get_root_node():
            return DOCUMENT_POSITION_DISCONNECTED + DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC + DOCUMENT_POSITION_PRECEDING
        if other.contains(self):
            return DOCUMENT_POSITION_CONTAINS + DOCUMENT_POSITION_PRECEDING
        if self.contains(other):
            return DOCUMENT_POSITION_CONTAINED_BY + DOCUMENT_POSITION_FOLLOWING
        a := _path_from_root(self)
        b := _path_from_root(other)
        i := 0
        while i < len(a) and i < len(b) and a[i] == b[i]:
            i += 1
        if a[i] < b[i]:
            return DOCUMENT_POSITION_FOLLOWING
        return DOCUMENT_POSITION_PRECEDING

    # ------------------------------------------------------------ événements

    func get_the_parent(event):
        return self.parent_node

    func __str__():
        return "<" + self.node_name + ">"

func _as_list(items):
    if type(items) == "list" or type(items) == "tuple":
        return items
    return [items]

func _collect_text(n, parts):
    for c in n.nodes:
        if c.node_type == TEXT_NODE or c.node_type == CDATA_SECTION_NODE:
            append(parts, c.data)
        elif c.node_type == ELEMENT_NODE or c.node_type == DOCUMENT_FRAGMENT_NODE:
            _collect_text(c, parts)

func _set_owner(n, d):
    if n.node_type == DOCUMENT_NODE:
        return
    n.owner_document = d
    n._adopted(d)
    for c in n.nodes:
        _set_owner(c, d)

# Indices d'enfants de la racine jusqu'au nœud.
func _path_from_root(n):
    out := []
    x := n
    while x.parent_node != null:
        out = [x.index()] + out
        x = x.parent_node
    return out

func _clone(n, deep, doc):
    c := n._clone_self(doc if doc != null else n.owner_document)
    if deep:
        for ch in n.nodes:
            c.append_child(_clone(ch, true, c.document() if c.node_type != DOCUMENT_NODE else c))
    return c

# Ordre du document : vrai si a précède b.
func precedes(a, b):
    return (a.compare_document_position(b) % 8) >= DOCUMENT_POSITION_FOLLOWING

# ---------------------------------------------------------------- fragment

# DocumentFragment : conteneur léger ; inséré, il est remplacé par ses enfants.
class DocumentFragment extends Node:
    func init(owner_document=null):
        super.init(DOCUMENT_FRAGMENT_NODE, "#document-fragment", owner_document)

    func _clone_self(doc):
        return DocumentFragment(doc)

    func children():
        target := self
        return _nl.HTMLCollection(() => _qs.element_children(target))

    func child_element_count():
        return len(_qs.element_children(self))

    func first_element_child():
        l := _qs.element_children(self)
        return l[0] if len(l) > 0 else null

    func last_element_child():
        l := _qs.element_children(self)
        return l[len(l) - 1] if len(l) > 0 else null

    func element_children():
        return _qs.element_children(self)

    func query_selector(selector):
        return _qs.query_selector(self, selector)

    func query_selector_all(selector):
        return _qs.query_selector_all(self, selector)

    func get_element_by_id(id):
        return _qs.get_element_by_id(self, id)

func _make_fragment(doc):
    return DocumentFragment(doc)

register_factory("fragment", _make_fragment)
