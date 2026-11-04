# ALEX STANDARD LIBRARY — web.dom.attributes
#
# Attributs DOM : Attr (nom, valeur, élément propriétaire) et NamedNodeMap (element.attributes : accès par
# nom ou par indice, ordre d'insertion conservé, ajout / retrait de nœuds Attr), validation des noms.
# Les modifications passent par l'élément, qui notifie les MutationObserver (type « attributes »).
#
#   use web.dom.attributes as at
#   m := element.attributes
#   m.length(), m.item(0).name, m.get_named_item("href").value
#   a := at.Attr("data-x", "1")
#   m.set_named_item(a)               # rattache a à l'élément
#   m.remove_named_item("data-x")
#   at.is_valid_name("data x")        # false
#
# Erreurs : InvalidCharacterError (nom invalide), NotFoundError (attribut absent), InUseAttributeError.

from core use len, type
from collections use append
use string as _s
use web.dom.dom_errors as _err
use web.dom.node as _node
from web.dom.node use Node

func is_valid_name(name):
    if type(name) != "str" or len(name) == 0:
        return false
    for c in name:
        o := _s.ord(c)
        if o <= 32 or c == '"' or c == '\'' or c == '>' or c == '/' or c == '=' or o == 127 or (o >= 0xFDD0 and o <= 0xFDEF):
            return false
    return true

func check_name(name, fn="attribute"):
    if not is_valid_name(name):
        _err.invalid_character(fn, "nom d'attribut invalide « " + str(name) + " »")

class Attr extends Node:
    func init(name, value="", owner_element=null, namespace_uri=null):
        check_name(name, "Attr")
        super.init(_node.ATTRIBUTE_NODE, name, owner_element.owner_document if owner_element != null else null)
        self.name = name
        self.value = str(value)
        self.owner_element = owner_element
        self.namespace_uri = namespace_uri
        i := _s.find(name, ":")
        self.prefix = name[0:i] if i > 0 and namespace_uri != null else null
        self.local_name = name[i + 1:len(name)] if i > 0 and namespace_uri != null else name
        self.specified = true

    func set_value(v):
        if self.owner_element != null:
            self.owner_element.set_attribute(self.name, v)
        else:
            self.value = str(v)

    func _clone_self(doc):
        return Attr(self.name, self.value, null, self.namespace_uri)

    func _equal_self(other):
        return other.name == self.name and other.value == self.value

    func text_content():
        return self.value

    func __str__():
        return self.name + "=\"" + self.value + "\""

class NamedNodeMap:
    func init(element):
        self.element = element

    func _list():
        return self.element.attr_list

    func length():
        return len(self._list())

    func __len__():
        return len(self._list())

    func item(i):
        l := self._list()
        if i < 0 or i >= len(l):
            return null
        return l[i]

    func __getitem__(i):
        return self._list()[i]

    func get_named_item(name):
        n := self.element._attr_key(name)
        for a in self._list():
            if a.name == n:
                return a
        return null

    func get_named_item_ns(namespace_uri, local_name):
        for a in self._list():
            if a.namespace_uri == namespace_uri and a.local_name == local_name:
                return a
        return null

    # Rattache un Attr ; renvoie l'ancien de même nom (ou null).
    func set_named_item(attr):
        if attr.owner_element != null and attr.owner_element != self.element:
            _err.in_use_attribute("set_named_item", "l'attribut « " + attr.name + " » appartient déjà à un autre élément")
        old := self.get_named_item(attr.name)
        if old == attr:
            return attr
        old_value := old.value if old != null else null
        kept := []
        replaced := false
        for a in self._list():
            if old != null and a == old:
                append(kept, attr)
                replaced = true
            else:
                append(kept, a)
        if not replaced:
            append(kept, attr)
        self.element.attr_list = kept
        attr.owner_element = self.element
        attr.owner_document = self.element.owner_document
        if old != null:
            old.owner_element = null
        self.element._attribute_changed(attr.name, old_value, attr.value)
        return old

    func remove_named_item(name):
        a := self.get_named_item(name)
        if a == null:
            _err.not_found("remove_named_item", "aucun attribut « " + str(name) + " »")
        self.element.remove_attribute(a.name)
        return a

    func names():
        out := []
        for a in self._list():
            append(out, a.name)
        return out

    # dict nom -> valeur (ordre conservé).
    func to_dict():
        out := {}
        for a in self._list():
            out[a.name] = a.value
        return out

    func __contains__(name):
        return self.get_named_item(name) != null
