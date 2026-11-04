# ALEX STANDARD LIBRARY — web.dom.node_list
#
# Collections de nœuds : NodeList (statique, comme query_selector_all, ou VIVANTE, comme child_nodes) et
# HTMLCollection (toujours vivante, éléments seulement, accès par id / name). Une collection vivante
# recalcule son contenu à chaque accès depuis l'arbre.
#
#   use web.dom.node_list as nl
#   l := nl.NodeList([a, b])               # statique
#   len(l), l.item(0), l[1]                # 2 a b
#   for n in l: …                          # itérable
#   vivante := nl.NodeList(null, () => parent.child_nodes)   # suit les changements de l'arbre
#   c := nl.HTMLCollection(() => form.elements_list())
#   c.named_item("email")                  # élément d'id ou de name « email »
#
# Erreurs : aucune (item hors limites -> null, comme en JavaScript).

from core use len, type
from collections use append

class NodeList:
    # nodes : liste figée ; source : fonction sans argument renvoyant la liste courante (collection vivante).
    func init(nodes=null, source=null):
        self.nodes = nodes if nodes != null else []
        self.source = source

    func is_live():
        return self.source != null

    func to_list():
        if self.source != null:
            out := []
            for n in self.source():
                append(out, n)
            return out
        return self.nodes

    func length():
        return len(self.to_list())

    func __len__():
        return self.length()

    func item(i):
        l := self.to_list()
        if i < 0 or i >= len(l):
            return null
        return l[i]

    func __getitem__(i):
        return self.to_list()[i]

    func __contains__(node):
        for n in self.to_list():
            if n == node:
                return true
        return false

    func index_of(node):
        i := 0
        for n in self.to_list():
            if n == node:
                return i
            i += 1
        return -1

    func for_each(fn):
        i := 0
        for n in self.to_list():
            fn(n, i)
            i += 1

    func entries():
        out := []
        i := 0
        for n in self.to_list():
            append(out, (i, n))
            i += 1
        return out

    func filter(pred):
        out := []
        for n in self.to_list():
            if pred(n):
                append(out, n)
        return NodeList(out)

    func map(fn):
        out := []
        for n in self.to_list():
            append(out, fn(n))
        return out

    func first():
        return self.item(0)

    func last():
        l := self.to_list()
        return l[len(l) - 1] if len(l) > 0 else null

    func __str__():
        return "NodeList(" + str(self.length()) + ")"

class HTMLCollection extends NodeList:
    func init(source):
        super.init(null, source)

    # Élément dont l'id, puis le name, vaut name.
    func named_item(name):
        for n in self.to_list():
            if n.get_attribute("id") == name:
                return n
        for n in self.to_list():
            if n.get_attribute("name") == name:
                return n
        return null

    func names():
        out := []
        for n in self.to_list():
            for a in ["id", "name"]:
                v := n.get_attribute(a)
                if v != null and v != "" and not (v in out):
                    append(out, v)
        return out

    func __str__():
        return "HTMLCollection(" + str(self.length()) + ")"

func static_list(nodes):
    return NodeList(nodes)

func live_list(source):
    return NodeList(null, source)
