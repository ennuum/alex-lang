# ALEX STANDARD LIBRARY — web.dom.tree_operations
#
# Parcours et manipulations d'arbre : NodeFilter (masques what_to_show, résultats ACCEPT / REJECT / SKIP),
# TreeWalker et NodeIterator du standard, et fonctions utilitaires (descendants, ancêtres, profondeur,
# ancêtre commun, ordre du document, insertion après, envelopper / désenvelopper, déplacer, chemin).
#
#   use web.dom.tree_operations as tree
#   w := tree.TreeWalker(document.body(), tree.SHOW_ELEMENT)
#   n := w.next_node()                       # premier élément descendant
#   it := tree.NodeIterator(root, tree.SHOW_TEXT)
#   t := it.next_node()                      # premier texte
#   tree.wrap(element, document.create_element("div"))   # place element dans le nouveau div
#   tree.unwrap(div)                         # remplace div par ses enfants
#   tree.common_ancestor(a, b), tree.depth(n), tree.path_to(n)   # « html > body > ul:nth-child(2) … »
#
# Erreurs : NotSupportedError (filtre invalide), HierarchyRequestError (déplacement impossible).

from core use len, type
from collections use append
use string as _s
use web.dom.dom_errors as _err

const FILTER_ACCEPT := 1
const FILTER_REJECT := 2
const FILTER_SKIP := 3

const SHOW_ALL := 4294967295
const SHOW_ELEMENT := 1
const SHOW_ATTRIBUTE := 2
const SHOW_TEXT := 4
const SHOW_CDATA_SECTION := 8
const SHOW_PROCESSING_INSTRUCTION := 64
const SHOW_COMMENT := 128
const SHOW_DOCUMENT := 256
const SHOW_DOCUMENT_TYPE := 512
const SHOW_DOCUMENT_FRAGMENT := 1024

func _mask_shows(mask, node_type):
    return (mask & (1 << (node_type - 1))) != 0

# Filtre : fonction(nœud) -> ACCEPT / REJECT / SKIP (ou booléen), objet avec accept_node, ou null.
func _apply_filter(walker, node):
    if not _mask_shows(walker.what_to_show, node.node_type):
        return FILTER_SKIP
    f := walker.filter
    if f == null:
        return FILTER_ACCEPT
    is_obj := false
    try:
        m := f.accept_node
        is_obj = true
    catch e:
        is_obj = false
    r := f.accept_node(node) if is_obj else f(node)
    if r == true:
        return FILTER_ACCEPT
    if r == false or r == null:
        return FILTER_SKIP
    return r

class TreeWalker:
    func init(root, what_to_show=4294967295, filter=null):
        self.root = root
        self.what_to_show = what_to_show
        self.filter = filter
        self.current_node = root

    func _accept(n):
        return _apply_filter(self, n)

    func parent_node():
        n := self.current_node
        while n != null and n != self.root:
            n = n.parent_node
            if n != null and self._accept(n) == FILTER_ACCEPT:
                self.current_node = n
                return n
        return null

    func _traverse_children(first):
        n := self.current_node.first_child() if first else self.current_node.last_child()
        while n != null:
            r := self._accept(n)
            if r == FILTER_ACCEPT:
                self.current_node = n
                return n
            if r == FILTER_SKIP:
                c := n.first_child() if first else n.last_child()
                if c != null:
                    n = c
                    continue
            while n != null:
                sib := n.next_sibling() if first else n.previous_sibling()
                if sib != null:
                    n = sib
                    break
                p := n.parent_node
                if p == null or p == self.root or p == self.current_node:
                    return null
                n = p
        return null

    func first_child():
        return self._traverse_children(true)

    func last_child():
        return self._traverse_children(false)

    func _traverse_siblings(nxt):
        n := self.current_node
        if n == self.root:
            return null
        while true:
            sib := n.next_sibling() if nxt else n.previous_sibling()
            while sib != null:
                n = sib
                r := self._accept(n)
                if r == FILTER_ACCEPT:
                    self.current_node = n
                    return n
                sib = n.first_child() if nxt else n.last_child()
                if r == FILTER_REJECT or sib == null:
                    sib = n.next_sibling() if nxt else n.previous_sibling()
            n = n.parent_node
            if n == null or n == self.root:
                return null
            if self._accept(n) == FILTER_ACCEPT:
                return null

    func next_sibling():
        return self._traverse_siblings(true)

    func previous_sibling():
        return self._traverse_siblings(false)

    func next_node():
        n := self.current_node
        r := FILTER_ACCEPT
        while true:
            while r != FILTER_REJECT and n.first_child() != null:
                n = n.first_child()
                r = self._accept(n)
                if r == FILTER_ACCEPT:
                    self.current_node = n
                    return n
            temp := n
            sib := null
            while temp != null:
                if temp == self.root:
                    return null
                sib = temp.next_sibling()
                if sib != null:
                    n = sib
                    break
                temp = temp.parent_node
            if temp == null:
                return null
            r = self._accept(n)
            if r == FILTER_ACCEPT:
                self.current_node = n
                return n

    func previous_node():
        n := self.current_node
        while n != self.root:
            sib := n.previous_sibling()
            while sib != null:
                n = sib
                r := self._accept(n)
                while r != FILTER_REJECT and n.last_child() != null:
                    n = n.last_child()
                    r = self._accept(n)
                if r == FILTER_ACCEPT:
                    self.current_node = n
                    return n
                sib = n.previous_sibling()
            if n == self.root or n.parent_node == null:
                return null
            n = n.parent_node
            if self._accept(n) == FILTER_ACCEPT:
                self.current_node = n
                return n
        return null

    # Tous les nœuds acceptés à partir de la position courante.
    func collect():
        out := []
        n := self.next_node()
        while n != null:
            append(out, n)
            n = self.next_node()
        return out

class NodeIterator:
    func init(root, what_to_show=4294967295, filter=null):
        self.root = root
        self.what_to_show = what_to_show
        self.filter = filter
        self.reference_node = root
        self.pointer_before_reference = true

    func _following(n):
        if n.first_child() != null:
            return n.first_child()
        x := n
        while x != null and x != self.root:
            if x.next_sibling() != null:
                return x.next_sibling()
            x = x.parent_node
        return null

    func _preceding(n):
        if n == self.root:
            return null
        p := n.previous_sibling()
        if p == null:
            return n.parent_node
        while p.last_child() != null:
            p = p.last_child()
        return p

    func next_node():
        n := self.reference_node
        before := self.pointer_before_reference
        while true:
            if not before:
                n = self._following(n)
                if n == null:
                    return null
            before = false
            if _apply_filter(self, n) == FILTER_ACCEPT:
                self.reference_node = n
                self.pointer_before_reference = false
                return n

    func previous_node():
        n := self.reference_node
        before := self.pointer_before_reference
        while true:
            if before:
                n = self._preceding(n)
                if n == null:
                    return null
            before = true
            if _apply_filter(self, n) == FILTER_ACCEPT:
                self.reference_node = n
                self.pointer_before_reference = true
                return n

    func detach():
        return null

# ---------------------------------------------------------------- utilitaires

func _walk(n, out, with_self):
    if with_self:
        append(out, n)
    for c in n.nodes:
        _walk(c, out, true)

# Descendants (ordre du document) ; with_self : le nœud lui-même en tête.
func descendants(node, with_self=false):
    out := []
    _walk(node, out, with_self)
    return out

func elements(node):
    out := []
    for n in descendants(node):
        if n.node_type == 1:
            append(out, n)
    return out

func texts(node):
    out := []
    for n in descendants(node):
        if n.node_type == 3:
            append(out, n)
    return out

func ancestors(node):
    return node.ancestors()

func depth(node):
    return len(node.ancestors())

func common_ancestor(a, b):
    chain := [a] + a.ancestors()
    n := b
    while n != null:
        for x in chain:
            if x == n:
                return n
        n = n.parent_node
    return null

func insert_after(node, reference):
    p := reference.parent_node
    if p == null:
        _err.hierarchy("insert_after", "la référence n'a pas de parent")
    return p.insert_before(node, reference.next_sibling())

# Place node dans wrapper (wrapper prend sa place).
func wrap(node, wrapper):
    p := node.parent_node
    if p != null:
        p.replace_child(wrapper, node)
    wrapper.append_child(node)
    return wrapper

# Remplace node par ses enfants.
func unwrap(node):
    p := node.parent_node
    if p == null:
        return []
    kids := []
    for c in node.nodes:
        append(kids, c)
    for c in kids:
        p.insert_before(c, node)
    p.remove_child(node)
    return kids

func move(node, new_parent, before=null):
    return new_parent.insert_before(node, before)

func empty(node):
    node.replace_children([])
    return node

func index_in_parent(node):
    return node.index()

# Chemin lisible d'un élément (« html > body > ul:nth-child(2) > li:nth-child(1) »).
func path_to(node):
    parts := []
    n := node
    while n != null and n.node_type == 1:
        name := n.local_name
        i := n.get_attribute("id")
        if i != null and i != "":
            name = name + "#" + i
        elif n.parent_node != null and n.parent_node.node_type == 1:
            k := 1
            for c in n.parent_node.nodes:
                if c == n:
                    break
                if c.node_type == 1:
                    k += 1
            name = name + ":nth-child(" + str(k) + ")"
        parts = [name] + parts
        n = n.parent_node
    return _s.join(" > ", parts)

# Nombre de nœuds par type (« element », « text »…) dans un sous-arbre.
func statistics(node):
    names := {1: "element", 3: "text", 4: "cdata", 7: "pi", 8: "comment", 9: "document", 10: "doctype", 11: "fragment"}
    out := {}
    for n in descendants(node, true):
        k := names[n.node_type] if n.node_type in names else str(n.node_type)
        out[k] = (out[k] if k in out else 0) + 1
    return out
