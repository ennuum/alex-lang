# ALEX STANDARD LIBRARY — web.html.html_parser
#
# Analyseur HTML tolérant, sur le modèle de l'algorithme du WHATWG (§13.2) : il lit le HTML « du monde réel »
# comme un navigateur et produit un Document (web.html.document) ou des fragments.
#
# Ce qu'il fait comme un navigateur :
#   - <html>, <head> et <body> implicites ; méta-données rangées dans <head> ;
#   - fermetures implicites : <p> avant un bloc, <li>, <dt>/<dd>, <option>, <tr>/<td>/<th>, <thead>/<tbody>... ;
#     <tbody> inséré pour un <tr> placé directement dans <table> ;
#   - éléments vides (<br>, <img>…), « /> » ignoré sur un élément HTML non vide ;
#   - texte brut dans <script>, <style> (aucune balise reconnue), texte RCDATA dans <title>, <textarea> ;
#   - références de caractères décodées (2 231 nommées, numériques, règles des attributs) ;
#   - attribut en double : le premier gagne ; balise fermante orpheline ignorée.
# Chaque écart est noté dans doc.issues (web.html.html_errors.Issue, avec la ligne) ; strict=true lève
# HtmlParseError au premier écart de niveau « error ».
#
#   use web.html.html_parser as hp
#   doc := hp.parse("<title>T</title><p>Un<p>Deux &amp; trois<ul><li>a<li>b</ul>")
#   doc.title()                                 # T
#   len(doc.find_all("p")), len(doc.find_all("li"))   # 2 2
#   nodes := hp.parse_fragment("<b>gras</b> et <i>italique</i>")
#   hp.parse_element("<a href='/x'>lien</a>").get("href")   # /x
#   hp.sanitize("<p onclick='x()'>ok<script>mal()</script><a href='javascript:x'>l</a></p>")
#   # <p>ok<a>l</a></p>
#
# Erreurs : HtmlParseError (mode strict), TypeError.

from core use len, type
from collections use append, pop
use string as _s
use web.html.html_errors as _err
use web.html.html_escape as _esc
use web.html.attribute_value as _av
use web.html.element as _el
use web.html.text_node as _text
use web.html.comment_node as _comment
use web.html.document_type as _doctype
use web.html.document as _document
use web.html.html_serializer as _ser

const HEAD_ELEMENTS := ["base", "basefont", "bgsound", "link", "meta", "noscript", "script", "style", "template", "title"]
const CLOSES_P := ["address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "main", "menu", "nav", "ol", "p", "pre", "search", "section", "summary", "table", "ul", "listing", "xmp", "plaintext"]
const HEADINGS := ["h1", "h2", "h3", "h4", "h5", "h6"]
const SCOPE_BOUNDARIES := ["applet", "caption", "html", "table", "td", "th", "marquee", "object", "template", "svg", "math"]
const TABLE_SECTIONS := ["thead", "tbody", "tfoot"]
const FORMATTING := ["a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong", "tt", "u"]
# Éléments dont la balise fermante est facultative (pas d'avertissement quand elle est implicite).
const LIST_BOUNDARIES := ["ul", "ol", "dl", "menu", "table", "td", "th", "caption", "body", "html", "template", "button", "object", "marquee", "applet"]
const OPTIONAL_END := ["p", "li", "dt", "dd", "option", "optgroup", "tr", "td", "th", "thead", "tbody", "tfoot", "colgroup", "caption", "rb", "rt", "rtc", "rp", "html", "head", "body"]

# ---------------------------------------------------------------- jetons

func _is_space(c):
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or _s.ord(c) == 12

func _is_alpha(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')

# Position de sub dans text à partir de start (indices en caractères), ou -1 ; sans copier text.
func find_from(text, sub, start=0):
    n := len(text)
    m := len(sub)
    if m == 0:
        return start
    first := sub[0]
    i := start
    while i <= n - m:
        if text[i] == first and text[i:i + m] == sub:
            return i
        i += 1
    return -1

class _Tokenizer:
    func init(text):
        self.text = text
        self.pos = 0
        self.n = len(text)
        self.line = 1
        self.raw_tag = null        # élément à texte brut en cours (script, style...)
        self.rcdata = false        # title, textarea : références décodées
        self.issues = []
        self.low = null

    func _issue(code, message):
        append(self.issues, _err.warning_issue(code, message, null, self.line))

    func _advance_to(j):
        k := self.pos
        while k < j:
            if self.text[k] == '\n':
                self.line += 1
            k += 1
        self.pos = j

    # Prochain jeton : dict type (start, end, text, comment, doctype, eof).
    func next():
        if self.pos >= self.n:
            return {"type": "eof"}
        if self.raw_tag != null:
            return self._raw_text()
        t := self.text
        c := t[self.pos]
        if c == '<' and self.pos + 1 < self.n:
            d := t[self.pos + 1]
            if d == '!':
                if t[self.pos:self.pos + 4] == "<!--":
                    return self._comment()
                if _s.upper(t[self.pos:self.pos + 9]) == "<!DOCTYPE":
                    return self._doctype()
                if t[self.pos:self.pos + 9] == "<![CDATA[":
                    return self._cdata()
                return self._bogus_comment(2)
            if d == '/':
                if self.pos + 2 < self.n and _is_alpha(t[self.pos + 2]):
                    return self._tag(true)
                if self.pos + 2 < self.n and t[self.pos + 2] == '>':
                    self._issue("empty-end-tag", "balise fermante vide « </> » ignorée")
                    self._advance_to(self.pos + 3)
                    return self.next()
                return self._bogus_comment(2)
            if _is_alpha(d):
                return self._tag(false)
            if d == '?':
                return self._bogus_comment(1)
        return self._text()

    func _text():
        t := self.text
        j := self.pos + 1
        while j < self.n:
            if t[j] == '<' and j + 1 < self.n:
                d := t[j + 1]
                if _is_alpha(d) or d == '/' or d == '!' or d == '?':
                    break
            j += 1
        raw := t[self.pos:j]
        self._advance_to(j)
        return {"type": "text", "text": _esc.unescape(raw)}

    # Texte en minuscules (calculé une fois, pour chercher les balises fermantes sans tenir compte de la casse).
    func _lower():
        if self.low == null:
            self.low = _s.lower(self.text)
        return self.low

    func _raw_text():
        t := self.text
        tag := self.raw_tag
        low := self._lower()
        pat := "</" + tag
        j := self.pos
        end := -1
        while true:
            k := find_from(low, pat, j)
            if k < 0:
                break
            after := k + len(pat)
            if after >= self.n or _is_space(t[after]) or t[after] == '>' or t[after] == '/':
                end = k
                break
            j = k + 1
        if end < 0:
            end = self.n
            self._issue("eof-in-raw-text", "fin du document dans <" + tag + "> (balise fermante manquante)")
        raw := t[self.pos:end]
        self._advance_to(end)
        rc := self.rcdata
        self.raw_tag = null
        self.rcdata = false
        if raw == "":
            return self.next()
        return {"type": "text", "text": _esc.unescape(raw) if rc else raw, "raw": not rc}

    func _comment():
        t := self.text
        start := self.pos + 4
        if t[start:start + 1] == ">" or t[start:start + 2] == "->":
            self._issue("abrupt-comment", "commentaire fermé trop tôt")
            self._advance_to(start + (1 if t[start:start + 1] == ">" else 2))
            return {"type": "comment", "text": ""}
        k := find_from(t, "-->", start)
        if k < 0:
            k2 := find_from(t, "--!>", start)
            if k2 >= 0:
                self._advance_to(k2 + 4)
                return {"type": "comment", "text": t[start:k2]}
            self._issue("eof-in-comment", "commentaire non fermé")
            self._advance_to(self.n)
            return {"type": "comment", "text": t[start:self.n]}
        self._advance_to(k + 3)
        return {"type": "comment", "text": t[start:k]}

    func _bogus_comment(skip):
        t := self.text
        start := self.pos + skip
        k := find_from(t, ">", start)
        end := self.n if k < 0 else k
        self._issue("bogus-comment", "construction « <! », « <? » ou « </ » inattendue traitée comme commentaire")
        text := t[start:end]
        self._advance_to(end + 1 if end < self.n else self.n)
        return {"type": "comment", "text": text}

    func _cdata():
        t := self.text
        start := self.pos + 9
        k := find_from(t, "]]>", start)
        end := self.n if k < 0 else k
        text := t[start:end]
        self._advance_to(end + 3 if k >= 0 else self.n)
        return {"type": "text", "text": text, "cdata": true}

    func _doctype():
        t := self.text
        start := self.pos + 9
        k := find_from(t, ">", start)
        end := self.n if k < 0 else k
        body := t[start:end]
        self._advance_to(end + 1 if k >= 0 else self.n)
        return {"type": "doctype", "text": body}

    func _tag(is_end):
        t := self.text
        i := self.pos + (2 if is_end else 1)
        j := i
        while j < self.n and not _is_space(t[j]) and t[j] != '/' and t[j] != '>':
            j += 1
        name := _s.lower(t[i:j])
        attrs := []
        seen := []
        self_closing := false
        i = j
        while true:
            while i < self.n and (_is_space(t[i]) or (t[i] == '/' and not (i + 1 < self.n and t[i + 1] == '>'))):
                i += 1
            if i >= self.n:
                self._issue("eof-in-tag", "fin du document dans la balise <" + name + ">")
                break
            if t[i] == '>':
                i += 1
                break
            if t[i] == '/' and i + 1 < self.n and t[i + 1] == '>':
                self_closing = true
                i += 2
                break
            a := i
            if t[i] == '=':
                i += 1
            while i < self.n and not _is_space(t[i]) and t[i] != '/' and t[i] != '>' and t[i] != '=':
                i += 1
            aname := _s.lower(t[a:i])
            while i < self.n and _is_space(t[i]):
                i += 1
            value := ""
            if i < self.n and t[i] == '=':
                i += 1
                while i < self.n and _is_space(t[i]):
                    i += 1
                if i < self.n and (t[i] == '"' or t[i] == '\''):
                    q := t[i]
                    i += 1
                    v0 := i
                    while i < self.n and t[i] != q:
                        i += 1
                    value = t[v0:i]
                    if i < self.n:
                        i += 1
                else:
                    v0 := i
                    while i < self.n and not _is_space(t[i]) and t[i] != '>':
                        i += 1
                    value = t[v0:i]
                value = _esc.unescape(value, true)
            if aname in seen:
                self._issue("duplicate-attribute", "attribut « " + aname + " » en double dans <" + name + "> (le premier est gardé)")
            elif _av.is_valid_name(aname):
                append(seen, aname)
                append(attrs, [aname, value])
            else:
                self._issue("invalid-attribute-name", "nom d'attribut invalide « " + aname + " » ignoré")
        self._advance_to(i)
        if is_end:
            return {"type": "end", "tag": name}
        return {"type": "start", "tag": name, "attrs": attrs, "self_closing": self_closing}

# ---------------------------------------------------------------- construction de l'arbre

class _Builder:
    func init(doc, strict, fragment_root=null):
        self.doc = doc
        self.strict = strict
        self.issues = []
        self.stack = []
        self.fragment = fragment_root != null
        self.head_done = false
        self.body_started = false
        self.foreign_depth = 0
        if fragment_root != null:
            append(self.stack, fragment_root)

    func issue(level, code, message, line):
        i := _err.Issue(level, code, message, null, line)
        append(self.issues, i)
        if self.strict and level == _err.ERROR:
            _err.parse_error("html_parser", message + " (ligne " + str(line) + ")")

    func current():
        if len(self.stack) == 0:
            return null
        return self.stack[len(self.stack) - 1]

    func _tags():
        out := []
        for e in self.stack:
            append(out, e.tag)
        return out

    func _html():
        if self.fragment:
            return self.stack[0]
        if len(self.stack) == 0:
            h := null
            for c in self.doc.children:
                if c.node_type == "element" and c.tag == "html":
                    h = c
            if h == null:
                h = _el.Element("html")
                self.doc.append(h)
            append(self.stack, h)
        return self.stack[0]

    func _head():
        h := self._html()
        for c in h.children:
            if c.node_type == "element" and c.tag == "head":
                return c
        hd := _el.Element("head")
        h.prepend(hd)
        return hd

    # Assure <body> ouvert et en pile (après <head>).
    func _ensure_body():
        if self.fragment or self.body_started:
            return
        h := self._html()
        body := null
        for c in h.children:
            if c.node_type == "element" and c.tag == "body":
                body = c
        self._head()
        if body == null:
            body = _el.Element("body")
            h.append(body)
        # pile : html, body
        self.stack = [h, body]
        self.body_started = true
        self.head_done = true

    func _insert(node):
        cur := self.current()
        if cur == null:
            self.doc.append(node)
        else:
            cur.append(node)

    func in_scope(tag, extra=null):
        i := len(self.stack) - 1
        while i >= 0:
            t := self.stack[i].tag
            if t == tag:
                return true
            if t in SCOPE_BOUNDARIES:
                return false
            if extra != null and t in extra:
                return false
            i -= 1
        return false

    # Ferme jusqu'à tag compris (implicitement) ; rend false si tag n'est pas ouvert.
    func close_to(tag, line, explicit=false):
        i := len(self.stack) - 1
        while i >= 0:
            if self.stack[i].tag == tag:
                break
            i -= 1
        if i < 0 or (self.fragment and i == 0):
            return false
        while len(self.stack) > i:
            e := pop(self.stack)
            if e.tag != tag and not (e.tag in OPTIONAL_END) and explicit:
                self.issue(_err.WARNING, "unclosed-element", "<" + e.tag + "> fermé implicitement par </" + tag + ">", line)
            if e.tag in ["svg", "math"] and self.foreign_depth > 0:
                self.foreign_depth -= 1
        return true

    func close_if_current(tags):
        cur := self.current()
        if cur != null and cur.tag in tags:
            pop(self.stack)
            return true
        return false

    func text(tok, line):
        data := tok["text"]
        cur := self.current()
        if not self.body_started and not self.fragment:
            if _is_blank(data):
                # espaces avant <body> : gardés dans <head> seulement s'il est ouvert
                if cur != null and cur.tag != "html":
                    cur.append(_text.TextNode(data))
                return
            if cur != null and cur.tag in ["title", "style", "script", "noscript", "template"]:
                cur.append(_text.TextNode(data))
                return
            self._ensure_body()
        cur = self.current()
        if cur != null and cur.tag in ["table", "tbody", "thead", "tfoot", "tr"] and not _is_blank(data):
            self.issue(_err.WARNING, "text-in-table", "texte directement dans <" + cur.tag + "> (déplacé hors de la table par les navigateurs)", line)
        if cur != null and len(cur.children) > 0:
            last := cur.children[len(cur.children) - 1]
            if last.node_type == "text":
                last.text = last.text + data
                return
        self._insert(_text.TextNode(data))

    func comment(tok, line):
        self._insert(_comment.CommentNode(tok["text"]))

    func doctype(tok, line):
        if self.fragment or len(self.stack) > 0 or self.doc.doctype() != null:
            self.issue(_err.WARNING, "misplaced-doctype", "<!DOCTYPE> inattendu ignoré", line)
            return
        d := _doctype.parse(tok["text"])
        self.doc.append(d)
        self.doc.mode = d.mode()
        if not d.is_html5():
            self.issue(_err.INFO, "legacy-doctype", "DOCTYPE ancien (mode " + d.mode() + ")", line)

    func start(tok, line, tokenizer):
        tag := tok["tag"]
        attrs := tok["attrs"]
        if not _el.is_valid_tag(tag):
            self.issue(_err.WARNING, "invalid-tag", "nom de balise invalide <" + tag + "> traité comme texte", line)
            self.text({"text": "<" + tag + ">"}, line)
            return
        if not self.fragment:
            if tag == "html":
                h := self._html()
                for a in attrs:
                    if not h.attributes.has(a[0]):
                        h.set(a[0], a[1])
                return
            if tag == "head":
                if self.head_done or self.body_started:
                    self.issue(_err.WARNING, "misplaced-head", "<head> en double ignoré", line)
                    return
                hd := self._head()
                for a in attrs:
                    hd.set(a[0], a[1])
                self.stack = [self._html(), hd]
                return
            if tag == "body":
                if self.body_started:
                    b := self.stack[1] if len(self.stack) > 1 else null
                    if b != null:
                        for a in attrs:
                            if not b.attributes.has(a[0]):
                                b.set(a[0], a[1])
                    self.issue(_err.WARNING, "misplaced-body", "<body> en double", line)
                    return
                self._ensure_body()
                b := self.stack[1]
                for a in attrs:
                    b.set(a[0], a[1])
                return
            if not self.body_started and tag in HEAD_ELEMENTS and not self.head_done:
                hd := self._head()
                if self.current() == null or self.current().tag == "html":
                    self.stack = [self._html(), hd]
            elif not self.body_started:
                self._ensure_body()
        cur := self.current()
        ctags := self._tags()
        # fermetures implicites
        if tag in CLOSES_P and self.in_scope("p", ["button"]):
            self.close_to("p", line)
        if tag == "li":
            self._close_list_item(["li"], line)
        elif tag == "dt" or tag == "dd":
            self._close_list_item(["dt", "dd"], line)
        elif tag == "option":
            self.close_if_current(["option"])
        elif tag == "optgroup":
            self.close_if_current(["option"])
            self.close_if_current(["optgroup"])
        elif tag in HEADINGS:
            cur = self.current()
            if cur != null and cur.tag in HEADINGS:
                self.issue(_err.WARNING, "nested-heading", "<" + tag + "> dans <" + cur.tag + "> : le titre précédent est fermé", line)
                pop(self.stack)
        elif tag == "a" and "a" in self._tags():
            self.issue(_err.WARNING, "nested-link", "<a> dans <a> : le lien précédent est fermé", line)
            self.close_to("a", line)
        elif tag == "form" and "form" in self._tags():
            self.issue(_err.WARNING, "nested-form", "<form> imbriqué ignoré", line)
            return
        elif tag in TABLE_SECTIONS:
            self._close_table_part(["td", "th", "tr", "thead", "tbody", "tfoot"], line)
        elif tag == "tr":
            self._close_table_part(["td", "th", "tr"], line)
            cur = self.current()
            if cur != null and cur.tag == "table":
                tb := _el.Element("tbody")
                cur.append(tb)
                append(self.stack, tb)
        elif tag == "td" or tag == "th":
            self._close_table_part(["td", "th"], line)
            cur = self.current()
            if cur != null and cur.tag == "table":
                tb := _el.Element("tbody")
                cur.append(tb)
                append(self.stack, tb)
                cur = tb
            if cur != null and cur.tag in TABLE_SECTIONS:
                tr := _el.Element("tr")
                cur.append(tr)
                append(self.stack, tr)
        elif tag == "col":
            cur = self.current()
            if cur != null and cur.tag == "table":
                cg := _el.Element("colgroup")
                cur.append(cg)
                append(self.stack, cg)
        e := _el.Element(tag)
        for a in attrs:
            e.attributes.entries = e.attributes.entries + [[a[0], a[1]]]
        self._insert(e)
        if tag == "svg" or tag == "math":
            self.foreign_depth += 1
        void := _ser.is_void(tag)
        if void:
            return
        if tok["self_closing"]:
            if self.foreign_depth > 0:
                if tag == "svg" or tag == "math":
                    self.foreign_depth -= 1
                return
            self.issue(_err.WARNING, "non-void-self-closing", "« /> » ignoré sur l'élément non vide <" + tag + ">", line)
        append(self.stack, e)
        if tag in _ser.RAW_TEXT_ELEMENTS:
            tokenizer.raw_tag = tag
        elif tag == "title" or tag == "textarea":
            tokenizer.raw_tag = tag
            tokenizer.rcdata = true

    # Ferme l'élément de liste ouvert le plus proche (li, ou dt / dd), sans traverser une autre liste.
    func _close_list_item(tags, line):
        i := len(self.stack) - 1
        while i >= 0:
            t := self.stack[i].tag
            if t in tags:
                self.close_to(t, line)
                return
            if t in LIST_BOUNDARIES:
                return
            i -= 1

    func _close_table_part(tags, line):
        while true:
            cur := self.current()
            if cur == null or not (cur.tag in tags):
                return
            pop(self.stack)

    func end(tok, line):
        tag := tok["tag"]
        if not self.fragment:
            if tag == "head":
                if not self.body_started:
                    self.head_done = true
                    self.stack = [self._html()]
                return
            if tag == "body" or tag == "html":
                # rien après </body> : le contenu suivant reste dans <body>
                return
        if tag == "br":
            self.issue(_err.WARNING, "end-br", "</br> traité comme <br>", line)
            self.start({"tag": "br", "attrs": [], "self_closing": false}, line, null)
            return
        if _ser.is_void(tag):
            self.issue(_err.WARNING, "void-end-tag", "balise fermante </" + tag + "> d'un élément vide ignorée", line)
            return
        if tag == "p" and not self.in_scope("p", ["button"]):
            self.issue(_err.WARNING, "orphan-end-p", "</p> sans <p> ouvert : paragraphe vide inséré", line)
            self._ensure_body()
            self._insert(_el.Element("p"))
            return
        if not (tag in self._tags()):
            self.issue(_err.ERROR, "orphan-end-tag", "balise fermante </" + tag + "> sans balise ouvrante (ignorée)", line)
            return
        self.close_to(tag, line, true)

    func finish(line):
        for e in self.stack:
            if not (e.tag in OPTIONAL_END) and not (self.fragment and e == self.stack[0]):
                self.issue(_err.WARNING, "unclosed-at-eof", "<" + e.tag + "> non fermé en fin de document", line)
        if not self.fragment:
            self._ensure_body()

func _is_blank(text):
    for c in text:
        if not _is_space(c):
            return false
    return true

func _run(text, doc, strict, root):
    if type(text) != "str":
        raise("TypeError", "html_parser : str attendue (obtenu " + type(text) + ")")
    t := text
    if _s.starts_with(t, str(_s.chr(65279))):
        t = t[1:len(t)]      # BOM
    tk := _Tokenizer(t)
    b := _Builder(doc, strict, root)
    while true:
        line := tk.line
        tok := tk.next()
        ty := tok["type"]
        if ty == "eof":
            break
        if ty == "text":
            b.text(tok, line)
        elif ty == "start":
            b.start(tok, line, tk)
        elif ty == "end":
            b.end(tok, line)
        elif ty == "comment":
            b.comment(tok, line)
        elif ty == "doctype":
            b.doctype(tok, line)
    b.finish(tk.line)
    issues := tk.issues + b.issues
    if strict:
        for i in tk.issues:
            if i.code == "eof-in-tag" or i.code == "eof-in-comment" or i.code == "eof-in-raw-text":
                _err.parse_error("html_parser", i.message + " (ligne " + str(i.line) + ")")
    return issues

# ---------------------------------------------------------------- API

# Document complet ; doc.issues : écarts relevés. strict : HtmlParseError au premier écart grave.
func parse(text, strict=false):
    doc := _document.Document(null, false, false, false, false)
    doc.issues = _run(text, doc, strict, null)
    if doc.doctype() == null:
        doc.mode = _doctype.QUIRKS
        append(doc.issues, _err.info_issue("missing-doctype", "pas de <!DOCTYPE html> : mode quirks", null, 1))
    return doc

# Liste de nœuds d'un fragment (contexte : intérieur d'un élément context, <body> par défaut).
func parse_fragment(text, context="div", strict=false):
    root := _el.Element(context)
    _run(text, null, strict, root)
    nodes := root.children
    root.children = []
    for n in nodes:
        n.parent = null
    return nodes

# Premier élément d'un fragment (null s'il n'y en a pas).
func parse_element(text):
    for n in parse_fragment(text):
        if n.node_type == "element":
            return n
    return null

# Écarts relevés à l'analyse (sans garder l'arbre).
func check(text):
    return parse(text).issues

# ---------------------------------------------------------------- assainissement

const SAFE_TAGS := ["a", "abbr", "b", "bdi", "bdo", "blockquote", "br", "caption", "cite", "code", "col", "colgroup", "dd", "del", "dfn", "div", "dl", "dt", "em", "figcaption", "figure", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "img", "ins", "kbd", "li", "mark", "ol", "p", "pre", "q", "rp", "rt", "ruby", "s", "samp", "small", "span", "strong", "sub", "sup", "table", "tbody", "td", "tfoot", "th", "thead", "time", "tr", "u", "ul", "var", "wbr", "picture", "source", "details", "summary"]
const SAFE_ATTRIBUTES := {"*": ["class", "id", "title", "lang", "dir"], "a": ["href", "rel", "target", "hreflang"], "img": ["src", "alt", "width", "height", "srcset", "sizes", "loading"], "source": ["srcset", "type", "media", "sizes"], "td": ["colspan", "rowspan", "headers"], "th": ["colspan", "rowspan", "scope", "headers"], "col": ["span"], "colgroup": ["span"], "ol": ["start", "reversed", "type"], "li": ["value"], "time": ["datetime"], "q": ["cite"], "blockquote": ["cite"], "del": ["cite", "datetime"], "ins": ["cite", "datetime"], "abbr": ["title"], "details": ["open"]}
# Contenu supprimé avec l'élément (et non seulement la balise).
const DROP_WITH_CONTENT := ["script", "style", "iframe", "object", "embed", "template", "noscript", "frame", "frameset", "applet", "svg", "math", "head", "title", "textarea", "select", "button", "form", "input", "link", "meta", "base"]

func _allowed(tag, name, attributes):
    if "*" in attributes and name in attributes["*"]:
        return true
    if tag in attributes and name in attributes[tag]:
        return true
    return false

func _clean(node, out_parent, tags, attributes, schemes, link_rel):
    for c in node.children:
        t := c.node_type
        if t == "text":
            out_parent.append(_text.TextNode(c.text))
        elif t == "element":
            if c.tag in DROP_WITH_CONTENT:
                continue
            if c.tag in tags:
                e := _el.Element(c.tag)
                for a in c.attributes.entries:
                    name := a[0]
                    if not _allowed(c.tag, name, attributes):
                        continue
                    if _av.is_url_attribute(name) and not _av.is_safe_url(a[1], schemes):
                        continue
                    e.attributes.set(name, a[1])
                if c.tag == "a" and link_rel != null and link_rel != false and e.has("href"):
                    if e.get("target") == "_blank" or link_rel != "":
                        e.set("rel", link_rel if link_rel != "" else "noopener noreferrer")
                out_parent.append(e)
                if not e.is_void():
                    _clean(c, e, tags, attributes, schemes, link_rel)
            else:
                _clean(c, out_parent, tags, attributes, schemes, link_rel)

# HTML assaini : seules les balises et attributs autorisés restent ; scripts, styles, gestionnaires d'événements
# et URL dangereuses (javascript:, data: non image...) disparaissent. link_rel : rel imposé aux liens (false :
# inchangé ; "" : « noopener noreferrer » sur target=_blank seulement).
func sanitize(html, tags=SAFE_TAGS, attributes=SAFE_ATTRIBUTES, schemes=_av.SAFE_SCHEMES, link_rel="nofollow noopener noreferrer"):
    root := _el.Element("div")
    for n in parse_fragment(html):
        root.append(n)
    out := _el.Element("div")
    _clean(root, out, tags, attributes, schemes, link_rel)
    return out.inner_html()

const INVISIBLE := ["script", "style", "template", "noscript", "head", "title"]

# Texte visible d'un document ou fragment HTML : balises retirées, références décodées, contenu de script,
# style, template et noscript ignoré.
func to_text(html):
    root := _el.Element("div")
    for n in parse_fragment(html):
        root.append(n)
    out := []
    _visible(root, out)
    return _s.join("", out)

func _visible(node, out):
    for c in node.children:
        if c.node_type == "text":
            append(out, c.text)
        elif c.node_type == "element" and not (c.tag in INVISIBLE):
            _visible(c, out)
