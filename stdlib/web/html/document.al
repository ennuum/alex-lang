# ALEX STANDARD LIBRARY — web.html.document
#
# Document : un document HTML complet — déclaration <!DOCTYPE html>, élément racine <html> avec <head> et <body>.
# Un Document neuf a déjà le squelette recommandé (langue, encodage UTF-8, fenêtre d'affichage, titre).
#
#   use web.html.document as dm
#   use web.html.element_factory as f
#   doc := dm.Document("Mon site", "fr")
#   doc.body().append(f.h("h1", "Bienvenue"))
#   doc.title()                 # Mon site
#   doc.find("h1").text_content()
#   doc.to_html()               # <!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">…</head><body>…</body></html>
#   doc.pretty()                # même chose, indentée
#
# Voir web.html.head (méta-données, feuilles de style, scripts) et web.html.body pour enrichir un document.
# Erreurs : HtmlError.

from core use len, type
from collections use append
use string as _s
use web.html.html_errors as _err
use web.html.element as _el
use web.html.text_node as _text
use web.html.document_type as _doctype
use web.html.html_serializer as _ser

const NODE_TYPE := "document"

class Document:
    # skeleton=false : document vide (utilisé par l'analyseur). lang / charset à false : non déclarés.
    func init(title=null, lang="fr", charset="utf-8", viewport=true, skeleton=true):
        self.node_type = NODE_TYPE
        self.children = []
        self.parent = null
        self.mode = _doctype.STANDARDS
        self.url = null               # URL d'origine (analyse d'une page téléchargée)
        self.issues = []              # écarts relevés par l'analyseur (web.html.html_errors.Issue)
        if skeleton:
            self.append(_doctype.html5())
            html := _el.Element("html", {"lang": lang} if lang != null and lang != false and lang != "" else null)
            head := _el.Element("head")
            if charset != null and charset != false:
                head.append(_el.Element("meta", {"charset": charset}))
            if viewport:
                head.append(_el.Element("meta", {"name": "viewport", "content": "width=device-width, initial-scale=1"}))
            if title != null:
                head.append(_el.Element("title", null, [str(title)]))
            html.append(head)
            html.append(_el.Element("body"))
            self.append(html)

    func append(child):
        for n in _el.to_nodes(child):
            if n.parent != null and n.parent.node_type == "element":
                n.parent.remove_child(n)
            n.parent = self
            append(self.children, n)
        return self

    func remove_child(child):
        out := []
        for c in self.children:
            if c != child:
                append(out, c)
        self.children = out
        child.parent = null
        return self

    func index_of(child):
        i := 0
        for c in self.children:
            if c == child:
                return i
            i += 1
        return -1

    func replace_child(new_child, old_child):
        i := self.index_of(old_child)
        if i < 0:
            _err.html_error("Document.replace_child", "l'ancien nœud n'est pas un enfant")
        old_child.parent = null
        new_child.parent = self
        self.children[i] = new_child
        return self

    func elements():
        out := []
        for c in self.children:
            if c.node_type == "element":
                append(out, c)
        return out

    # ---------------------------------------------------------------- structure

    func doctype():
        for c in self.children:
            if c.node_type == "doctype":
                return c
        return null

    # Élément racine <html> (créé s'il manque).
    func html():
        for c in self.children:
            if c.node_type == "element" and c.tag == "html":
                return c
        h := _el.Element("html")
        self.append(h)
        return h

    func document_element():
        return self.html()

    func _section(tag):
        root := self.html()
        for c in root.children:
            if c.node_type == "element" and c.tag == tag:
                return c
        e := _el.Element(tag)
        if tag == "head":
            root.prepend(e)
        else:
            root.append(e)
        return e

    # <head> (créé s'il manque).
    func head():
        return self._section("head")

    # <body> (créé s'il manque).
    func body():
        return self._section("body")

    func title():
        t := self.head().find("title")
        if t == null:
            return null
        return _s.trim(t.text_content())

    func set_title(text):
        t := self.head().find("title")
        if t == null:
            t = _el.Element("title")
            self.head().append(t)
        t.set_text(text)
        return self

    func lang():
        return self.html().get("lang")

    func set_lang(lang):
        self.html().set("lang", lang)
        return self

    # Encodage déclaré (<meta charset> ou http-equiv Content-Type), ou null.
    func charset():
        m := self.head().find("meta[charset]")
        if m != null:
            return _s.lower(m.get("charset"))
        m = self.head().find("meta[http-equiv=content-type i]")
        if m != null:
            c := m.get("content", "")
            k := _s.find(_s.lower(c), "charset=")
            if k >= 0:
                return _s.lower(_s.trim(c[k + 8:len(c)]))
        return null

    # URL de base (<base href>), ou null.
    func base_url():
        b := self.head().find("base[href]")
        if b == null:
            return null
        return b.get("href")

    # ---------------------------------------------------------------- recherche

    func descendants():
        out := []
        for c in self.children:
            if c.node_type == "element":
                append(out, c)
                for d in c.descendants():
                    append(out, d)
        return out

    func find(selector):
        return _el.select_one(self, selector)

    func find_all(selector):
        return _el.select(self, selector)

    func find_by_id(id):
        for e in self.descendants():
            if e.attributes.get_text("id") == id:
                return e
        return null

    func get_element_by_id(id):
        return self.find_by_id(id)

    func find_by_tag(tag):
        t := _s.lower(tag)
        out := []
        for e in self.descendants():
            if e.tag == t:
                append(out, e)
        return out

    func walk(fn):
        for c in self.children:
            r := fn(c, 0)
            if c.node_type == "element" and r != false:
                c.walk(fn, 1)

    # ---------------------------------------------------------------- contenu

    func text_content():
        return _ser.text_content(self.body())

    func to_html(options=null):
        return _ser.serialize(self, options)

    func pretty(indent="  "):
        return _ser.serialize(self, _ser.pretty(indent))

    func clone():
        d := Document(null, false, false, false, false)
        d.mode = self.mode
        d.url = self.url
        for c in self.children:
            ch := c.clone(true) if c.node_type == "element" else c.clone()
            d.append(ch)
        return d

    func __str__():
        return self.to_html()

func document(title=null, lang="fr", charset="utf-8"):
    return Document(title, lang, charset)

func empty():
    return Document(null, false, false, false, false)

func is_document(value):
    return _el.is_node(value) and value.node_type == NODE_TYPE
