# ALEX STANDARD LIBRARY — web.html.html_writer
#
# HtmlWriter : écriture de HTML au fil de l'eau, sans construire d'arbre — pour de très gros documents ou pour
# envoyer une page morceau par morceau (sink : fonction appelée avec chaque morceau, par exemple l'écriture d'une
# réponse HTTP en flux). Les balises ouvertes sont suivies : une fermeture qui ne correspond pas lève HtmlError.
#
#   use web.html.html_writer as hw
#   w := hw.HtmlWriter(true)                  # pretty=true : indentation
#   w.doctype()
#   w.open("html", {"lang": "fr"})
#   w.open("head").element("title", null, "Rapport").close("head")
#   w.open("body")
#   w.element("h1", {"class": "titre"}, "Résultats < 2024")
#   w.open("ul")
#   for x in ["a", "b"]:
#       w.element("li", null, x)
#   w.close_all()
#   page := w.to_string()
#
#   w2 := hw.HtmlWriter(false, (morceau) => connexion.write(morceau))   # écriture directe
#
# Erreurs : HtmlError (fermeture inattendue, contenu dans un élément vide), HtmlTagError, HtmlAttributeError.

from core use len, type
from collections use append, pop
use string as _s
use web.html.html_errors as _err
use web.html.html_escape as _esc
use web.html.attributes as _attrs
use web.html.element as _el
use web.html.html_serializer as _ser

# Éléments de bloc dont le contenu est du texte courant : écrits sur une seule ligne en mode pretty.
const PHRASING_CONTAINERS := ["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "dt", "dd", "td", "th", "caption", "figcaption", "title", "option", "summary", "legend", "label", "blockquote", "address"]

class HtmlWriter:
    func init(pretty=false, sink=null, indent="  "):
        self.pretty = pretty
        self.sink = sink
        self.indent = indent
        self.parts = []
        self.stack = []           # balises ouvertes
        self.inline_depth = 0     # > 0 : à l'intérieur d'un élément en ligne (pas d'indentation)
        self.bytes_written = 0

    func _emit(text):
        if text == "":
            return
        self.bytes_written += _s.byte_len(text)
        if self.sink != null:
            self.sink(text)
        else:
            append(self.parts, text)

    func _newline():
        if self.pretty and self.inline_depth == 0 and (self.bytes_written > 0):
            self._emit("\n" + _s.repeat(self.indent, len(self.stack)))

    func doctype():
        self._emit("<!DOCTYPE html>")
        return self

    # Ouvre une balise (un élément vide est écrit et non empilé).
    func open(tag, attributes=null):
        if not _el.is_valid_tag(tag):
            _err.tag_error("HtmlWriter.open", "nom de balise invalide '" + str(tag) + "'")
        t := _s.lower(tag)
        inline := _ser.is_inline(t)
        if not inline:
            self._newline()
        self._emit("<" + t + _attrs.from_data(attributes).render() + ">")
        if _ser.is_void(t):
            return self
        append(self.stack, t)
        if inline or self.inline_depth > 0 or t in _ser.PRESERVE_WHITESPACE or t in PHRASING_CONTAINERS:
            self.inline_depth += 1
        return self

    # Ferme la dernière balise ouverte (ou vérifie qu'il s'agit de tag).
    func close(tag=null):
        if len(self.stack) == 0:
            _err.html_error("HtmlWriter.close", "aucune balise ouverte")
        top := self.stack[len(self.stack) - 1]
        if tag != null and _s.lower(tag) != top:
            _err.html_error("HtmlWriter.close", "fermeture de </" + _s.lower(tag) + "> alors que <" + top + "> est ouverte")
        pop(self.stack)
        if self.inline_depth > 0:
            self.inline_depth -= 1
            self._emit("</" + top + ">")
        else:
            self._newline()
            self._emit("</" + top + ">")
        return self

    func close_all():
        while len(self.stack) > 0:
            self.close()
        return self

    # Texte échappé (dans <script> / <style> : neutralisé).
    func text(value):
        if len(self.stack) > 0:
            top := self.stack[len(self.stack) - 1]
            if top == "script":
                self._emit(_esc.escape_script(str(value)))
                return self
            if top == "style":
                self._emit(_esc.escape_style(str(value)))
                return self
        if self.pretty and self.inline_depth == 0:
            t := _s.trim(str(value))
            if t == "":
                return self
            self._newline()
            self._emit(_esc.escape_text(t))
            return self
        self._emit(_esc.escape_text(value))
        return self

    # Balisage de confiance, tel quel.
    func raw(markup):
        self._emit(str(markup))
        return self

    func comment(value):
        self._newline()
        self._emit("<!--" + _esc.escape_comment(value) + "-->")
        return self

    # Élément complet : content est un texte, un nœud (Element...) ou une liste de ceux-ci.
    func element(tag, attributes=null, content=null):
        t := _s.lower(tag)
        if _ser.is_void(t):
            if content != null:
                _err.html_error("HtmlWriter.element", "<" + t + "> est un élément vide : pas de contenu")
            return self.open(t, attributes)
        before := self.inline_depth
        self.open(t, attributes)
        self.inline_depth += 1
        self._content(content)
        pop(self.stack)
        self.inline_depth = before
        self._emit("</" + t + ">")
        return self

    func _content(content):
        if content == null:
            return
        t := type(content)
        if t == "list" or t == "tuple":
            for c in content:
                self._content(c)
            return
        if _el.is_node(content):
            self._emit(_ser.serialize(content))
            return
        self.text(str(content))

    # Écrit un nœud (Element, Document...) déjà construit.
    func node(n, pretty=false):
        self._newline()
        self._emit(_ser.serialize(n, _ser.pretty(self.indent) if pretty else null))
        return self

    func depth():
        return len(self.stack)

    func open_tags():
        return self.stack + []

    # Texte accumulé (sans sink) ; les balises encore ouvertes ne sont pas fermées.
    func to_string():
        return _s.join("", self.parts)

    func __str__():
        return self.to_string()

func writer(pretty=false, sink=null):
    return HtmlWriter(pretty, sink)
