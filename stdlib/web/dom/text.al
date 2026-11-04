# ALEX STANDARD LIBRARY — web.dom.text
#
# Nœuds de données : CharacterData (data, longueur, ajout, insertion, suppression, remplacement, extraction,
# avec notification characterData), Text (split_text, whole_text), Comment, CDATASection,
# ProcessingInstruction, et DocumentType (name, public_id, system_id).
#
#   use web.dom.text as tx
#   t := tx.Text("Bonjour le monde")
#   t.length()                        # 16
#   t.substring_data(0, 7)            # Bonjour
#   reste := t.split_text(7)          # t : « Bonjour », reste : « le monde » (inséré après t)
#   t.append_data(" !")
#   tx.Comment("note").data           # note
#   tx.DocumentType("html").node_name # html
#
# Erreurs : IndexSizeError (position hors du texte).

from core use len, type
from collections use append
use string as _s
use web.dom.dom_errors as _err
use web.dom.node as _node
from web.dom.node use Node

class CharacterData extends Node:
    func init(node_type, node_name, data="", owner_document=null):
        super.init(node_type, node_name, owner_document)
        self.data = str(data) if data != null else ""

    func length():
        return len(self.data)

    func set_data(value):
        old := self.data
        self.data = str(value)
        hub := self._hub()
        if hub != null:
            hub.queue("characterData", self, [], [], null, null, null, old)

    func substring_data(offset, count):
        if offset < 0 or offset > len(self.data):
            _err.index_size("substring_data", "position " + str(offset) + " hors du texte")
        return self.data[offset:offset + count]

    func append_data(text):
        self.set_data(self.data + str(text))

    func insert_data(offset, text):
        self.replace_data(offset, 0, text)

    func delete_data(offset, count):
        self.replace_data(offset, count, "")

    func replace_data(offset, count, text):
        if offset < 0 or offset > len(self.data):
            _err.index_size("replace_data", "position " + str(offset) + " hors du texte")
        end := offset + count
        if end > len(self.data):
            end = len(self.data)
        self.set_data(self.data[0:offset] + str(text) + self.data[end:len(self.data)])

    func _equal_self(other):
        return other.data == self.data

    func __str__():
        return self.node_name + "(" + self.data + ")"

class Text extends CharacterData:
    func init(data="", owner_document=null):
        super.init(_node.TEXT_NODE, "#text", data, owner_document)

    func _clone_self(doc):
        return Text(self.data, doc)

    # Coupe le texte à offset : ce nœud garde le début, un nouveau nœud (renvoyé) prend la fin.
    func split_text(offset):
        if offset < 0 or offset > len(self.data):
            _err.index_size("split_text", "position " + str(offset) + " hors du texte")
        rest := Text(self.data[offset:len(self.data)], self.owner_document)
        self.set_data(self.data[0:offset])
        if self.parent_node != null:
            self.parent_node.insert_before(rest, self.next_sibling())
        return rest

    # Texte des nœuds Text contigus (frères) concaténés.
    func whole_text():
        start := self
        while start.previous_sibling() != null and start.previous_sibling().node_type == _node.TEXT_NODE:
            start = start.previous_sibling()
        parts := []
        n := start
        while n != null and n.node_type == _node.TEXT_NODE:
            append(parts, n.data)
            n = n.next_sibling()
        return _s.join("", parts)

    # Vrai si le texte n'est fait que d'espaces (ignoré par :empty ? non : seul l'absence de texte l'est).
    func is_whitespace():
        for c in self.data:
            if not (c == ' ' or c == '\t' or c == '\n' or c == '\r' or _s.ord(c) == 12):
                return false
        return true

class CDATASection extends CharacterData:
    func init(data="", owner_document=null):
        super.init(_node.CDATA_SECTION_NODE, "#cdata-section", data, owner_document)

    func _clone_self(doc):
        return CDATASection(self.data, doc)

class Comment extends CharacterData:
    func init(data="", owner_document=null):
        super.init(_node.COMMENT_NODE, "#comment", data, owner_document)

    func _clone_self(doc):
        return Comment(self.data, doc)

class ProcessingInstruction extends CharacterData:
    func init(target, data="", owner_document=null):
        super.init(_node.PROCESSING_INSTRUCTION_NODE, target, data, owner_document)
        self.target = target

    func _clone_self(doc):
        return ProcessingInstruction(self.target, self.data, doc)

class DocumentType extends Node:
    func init(name="html", public_id="", system_id="", owner_document=null):
        super.init(_node.DOCUMENT_TYPE_NODE, name, owner_document)
        self.name = name
        self.public_id = public_id
        self.system_id = system_id

    func _clone_self(doc):
        return DocumentType(self.name, self.public_id, self.system_id, doc)

    func _equal_self(other):
        return other.name == self.name and other.public_id == self.public_id and other.system_id == self.system_id

    func to_html():
        out := "<!DOCTYPE " + self.name
        if self.public_id != "":
            out = out + " PUBLIC \"" + self.public_id + "\""
            if self.system_id != "":
                out = out + " \"" + self.system_id + "\""
        elif self.system_id != "":
            out = out + " SYSTEM \"" + self.system_id + "\""
        return out + ">"

func _make_text(v):
    return Text(v)

_node.register_factory("text", _make_text)

func text(data):
    return Text(data)

func comment(data):
    return Comment(data)
