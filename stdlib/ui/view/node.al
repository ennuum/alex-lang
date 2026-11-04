# ALEX STANDARD LIBRARY — ui.view.node (interne)
#
# Un composant décrit par la vue : genre (« button », « column »...), propriétés et enfants. La vue est
# recalculée après chaque événement ; l'état propre à un composant (curseur d'un champ, défilement d'une
# liste, onglet ouvert...) est conservé par le runtime sous le CHEMIN du composant dans l'arbre (indices,
# ou son id quand il en a un).

from core use len, type
from collections use contains_key

class Node:
    func init(kind, props, children=null):
        self.kind = kind
        self.props = props
        if children == null:
            children = []
        self.children = children
        self.id = null
        if contains_key(props, "id"):
            self.id = props["id"]
        # Rempli par le runtime à chaque image.
        self.path = ""
        self.st = null
        self.parent = null
        self.flow = []
        self.layer = 0
        self.x = 0
        self.y = 0
        self.w = 0
        self.h = 0
        self.mw = 0
        self.mh = 0
        self.clip = null

    func get(name, fallback=null):
        if contains_key(self.props, name):
            v := self.props[name]
            if v != null:
                return v
        return fallback

    func set(name, value):
        self.props[name] = value

    func contains(px, py):
        if px < self.x or py < self.y or px >= self.x + self.w or py >= self.y + self.h:
            return false
        c := self.clip
        if c == null:
            return true
        return px >= c[0] and py >= c[1] and px < c[0] + c[2] and py < c[1] + c[3]

func is_node(v):
    return type(v) == "instance" and v.kind != null

# Un texte peut tenir lieu de composant (text(...)).
func coerce(v):
    if v == null:
        return Node("spacer", {"flex": 0})
    if type(v) == "str":
        return Node("text", {"content": v})
    if type(v) == "int" or type(v) == "float":
        return Node("text", {"content": str(v)})
    return v
