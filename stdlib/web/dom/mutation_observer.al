# ALEX STANDARD LIBRARY — web.dom.mutation_observer
#
# MutationObserver : observation des changements d'un arbre DOM (enfants ajoutés / retirés, attributs, texte),
# avec sous-arbre, filtre d'attributs et anciennes valeurs. Les enregistrements sont livrés de façon
# ASYNCHRONE, comme dans un navigateur : à la prochaine micro-tâche si un ordonnanceur est branché
# (web.browser le fait), sinon à l'appel de flush(). take_records() les récupère immédiatement.
#
#   use web.dom.mutation_observer as mo
#   obs := mo.MutationObserver((records, o) => print(len(records), "changement(s)"))
#   obs.observe(liste, {"child_list": true, "subtree": true, "attributes": true, "attribute_old_value": true})
#   liste.append_child(document.create_element("li"))
#   mo.flush(document)                 # livre : « 1 changement(s) »
#   obs.take_records()                 # enregistrements en attente (et les retire)
#   obs.disconnect()
#
# Erreurs : TypeError (options sans childList / attributes / characterData, options incohérentes).

from core use len, type
from collections use append

class MutationRecord:
    func init(kind, target, added_nodes, removed_nodes, previous_sibling, next_sibling, attribute_name, old_value):
        self.type = kind                     # "childList", "attributes", "characterData"
        self.target = target
        self.added_nodes = added_nodes
        self.removed_nodes = removed_nodes
        self.previous_sibling = previous_sibling
        self.next_sibling = next_sibling
        self.attribute_name = attribute_name
        self.attribute_namespace = null
        self.old_value = old_value

    func __str__():
        if self.type == "attributes":
            return "MutationRecord(attributes " + str(self.attribute_name) + ")"
        if self.type == "childList":
            return "MutationRecord(childList +" + str(len(self.added_nodes)) + " -" + str(len(self.removed_nodes)) + ")"
        return "MutationRecord(characterData)"

func _opt(o, a, b, fallback):
    if a in o:
        return o[a]
    if b in o:
        return o[b]
    return fallback

class Options:
    func init(o):
        self.child_list = _opt(o, "child_list", "childList", false)
        self.attributes = _opt(o, "attributes", "attributes", null)
        self.character_data = _opt(o, "character_data", "characterData", null)
        self.subtree = _opt(o, "subtree", "subtree", false)
        self.attribute_old_value = _opt(o, "attribute_old_value", "attributeOldValue", false)
        self.character_data_old_value = _opt(o, "character_data_old_value", "characterDataOldValue", false)
        self.attribute_filter = _opt(o, "attribute_filter", "attributeFilter", null)
        if self.attributes == null:
            self.attributes = self.attribute_old_value or self.attribute_filter != null
        if self.character_data == null:
            self.character_data = self.character_data_old_value
        if not self.child_list and not self.attributes and not self.character_data:
            raise("TypeError", "MutationObserver.observe : childList, attributes ou characterData doit être vrai")
        if self.attribute_old_value and not self.attributes:
            raise("TypeError", "MutationObserver.observe : attributeOldValue sans attributes")
        if self.attribute_filter != null and not self.attributes:
            raise("TypeError", "MutationObserver.observe : attributeFilter sans attributes")

class Registration:
    func init(observer, target, options):
        self.observer = observer
        self.target = target
        self.options = options

# Registre des observateurs d'un document (ou des nœuds hors document) et file des livraisons.
class MutationHub:
    func init():
        self.registrations = []
        self.pending = []           # observateurs ayant des enregistrements
        self.scheduler = null       # fonction(fn) planifiant fn en micro-tâche (web.browser), ou null
        self.scheduled = false

    func register(observer, target, options):
        for r in self.registrations:
            if r.observer == observer and r.target == target:
                r.options = options
                return
        append(self.registrations, Registration(observer, target, options))

    func unregister(observer):
        kept := []
        for r in self.registrations:
            if r.observer != observer:
                append(kept, r)
        self.registrations = kept

    func _interested(r, kind, target, attr_name):
        o := r.options
        if r.target != target:
            if not o.subtree:
                return false
            n := target.parent_node
            found := false
            while n != null:
                if n == r.target:
                    found = true
                    break
                n = n.parent_node
            if not found:
                return false
        if kind == "childList":
            return o.child_list
        if kind == "attributes":
            if not o.attributes:
                return false
            if o.attribute_filter != null and not (attr_name in o.attribute_filter):
                return false
            return true
        if kind == "characterData":
            return o.character_data
        return false

    func queue(kind, target, added, removed, previous, following, attr_name, old_value):
        if len(self.registrations) == 0:
            return
        seen := []
        for r in self.registrations:
            if r.observer in seen:
                continue
            if self._interested(r, kind, target, attr_name):
                append(seen, r.observer)
                keep_old := (kind == "attributes" and r.options.attribute_old_value) or (kind == "characterData" and r.options.character_data_old_value)
                rec := MutationRecord(kind, target, added, removed, previous, following, attr_name, old_value if keep_old else null)
                append(r.observer.records, rec)
                if not (r.observer in self.pending):
                    append(self.pending, r.observer)
        if len(self.pending) > 0 and self.scheduler != null and not self.scheduled:
            self.scheduled = true
            hub := self
            self.scheduler(() => hub.deliver())

    # Livre les enregistrements en attente (les rappels peuvent provoquer d'autres mutations : boucle).
    func deliver():
        self.scheduled = false
        rounds := 0
        while len(self.pending) > 0 and rounds < 100:
            batch := self.pending
            self.pending = []
            for obs in batch:
                recs := obs.take_records()
                if len(recs) > 0:
                    obs.callback(recs, obs)
            rounds += 1

_global := [null]

# Registre des nœuds qui n'appartiennent à aucun document.
func global_hub():
    if _global[0] == null:
        _global[0] = MutationHub()
    return _global[0]

func hub_for(node):
    d := node if node.node_type == 9 else node.owner_document
    if d != null:
        return d.mutation_hub
    return global_hub()

class MutationObserver:
    func init(callback):
        self.callback = callback
        self.records = []
        self.hubs = []

    func observe(target, options=null):
        o := Options(options if options != null else {})
        hub := hub_for(target)
        hub.register(self, target, o)
        if not (hub in self.hubs):
            append(self.hubs, hub)
        return self

    func disconnect():
        for h in self.hubs:
            h.unregister(self)
        self.hubs = []
        self.records = []

    func take_records():
        out := self.records
        self.records = []
        return out

# Livre maintenant les enregistrements d'un document (ou des nœuds hors document si doc est null).
func flush(doc=null):
    if doc != null:
        doc.mutation_hub.deliver()
    global_hub().deliver()
