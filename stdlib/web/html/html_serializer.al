# ALEX STANDARD LIBRARY — web.html.html_serializer
#
# Sérialisation d'un arbre HTML (Document, Element, TextNode, CommentNode, RawHtml, DocumentType) en texte, selon
# l'algorithme du WHATWG (§13.3) : éléments vides sans balise fermante, texte échappé, contenu de <script> et
# <style> laissé brut mais incapable de fermer son élément, attributs échappés.
#
# Options :
#   pretty            indentation des éléments de bloc (le contenu en ligne et <pre> restent intacts)
#   indent            unité d'indentation (« ␠␠ » par défaut)
#   sort_attributes   attributs triés par nom (sortie déterministe pour des tests ou des empreintes)
#   xhtml             éléments vides fermés « <br /> » (compatibilité XML)
#   omit_comments     commentaires supprimés
#
#   use web.html.html_serializer as ser
#   ser.serialize(element)                         # <ul><li>a</li></ul>
#   ser.serialize(document, ser.Options(true))     # version indentée
#   ser.inner_html(element)                        # contenu seul
#
# Les nœuds sont reconnus par leur champ node_type : document, element, text, comment, raw, doctype.

from core use len, type
from collections use append
use string as _s
use web.html.html_errors as _err
use web.html.html_escape as _esc

const VOID_ELEMENTS := ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr", "param", "keygen", "basefont", "bgsound", "frame"]
const RAW_TEXT_ELEMENTS := ["script", "style", "xmp", "iframe", "noembed", "noframes", "plaintext"]
const ESCAPABLE_RAW_TEXT_ELEMENTS := ["textarea", "title"]
const PRESERVE_WHITESPACE := ["pre", "textarea", "script", "style", "listing", "xmp", "plaintext"]
const INLINE_ELEMENTS := ["a", "abbr", "b", "bdi", "bdo", "br", "button", "cite", "code", "data", "dfn", "em", "i", "img", "input", "kbd", "label", "mark", "meter", "output", "picture", "progress", "q", "ruby", "rp", "rt", "s", "samp", "select", "small", "span", "strong", "sub", "sup", "svg", "time", "u", "var", "wbr", "del", "ins", "slot", "math", "audio", "video", "canvas", "embed", "object", "iframe", "textarea"]

class Options:
    func init(pretty=false, indent="  ", sort_attributes=false, xhtml=false, omit_comments=false):
        self.pretty = pretty
        self.indent = indent
        self.sort_attributes = sort_attributes
        self.xhtml = xhtml
        self.omit_comments = omit_comments

func compact():
    return Options()

func pretty(indent="  "):
    return Options(true, indent)

func is_void(tag):
    return _s.lower(tag) in VOID_ELEMENTS

func is_raw_text(tag):
    return _s.lower(tag) in RAW_TEXT_ELEMENTS

func is_inline(tag):
    return _s.lower(tag) in INLINE_ELEMENTS

# ---------------------------------------------------------------- sérialisation

func serialize(node, options=null):
    o := options if options != null else Options()
    out := []
    _write(node, o, out, 0, false)
    text := _s.join("", out)
    if o.pretty:
        text = _s.trim(text)
        if node.node_type == "document":
            text = text + "\n"
    return text

# Contenu d'un élément ou d'un document, sans la balise englobante.
func inner_html(node, options=null):
    o := options if options != null else Options()
    out := []
    if node.node_type == "element" and is_raw_text(node.tag):
        for c in node.children:
            append(out, _raw_child(node.tag, c))
        return _s.join("", out)
    for c in node.children:
        _write(c, o, out, 0, false)
    return _s.join("", out)

func _raw_child(tag, child):
    if child.node_type == "text":
        t := _s.lower(tag)
        if t == "script":
            return _esc.escape_script(child.text)
        if t == "style":
            return _esc.escape_style(child.text)
        return _neutralize_end(t, child.text)
    if child.node_type == "raw":
        return child.markup
    return ""

func _neutralize_end(tag, text):
    low := _s.lower(text)
    if not _s.contains(low, "</" + tag):
        return text
    out := []
    i := 0
    n := len(text)
    pat := "</" + tag
    while i < n:
        if text[i] == '<' and _s.starts_with(low[i:i + len(pat) if i + len(pat) <= n else n], pat):
            append(out, "&lt;")
            i += 1
            continue
        append(out, str(text[i]))
        i += 1
    return _s.join("", out)

func _nl(o, level):
    return "\n" + _s.repeat(o.indent, level)

func _all_inline(node):
    for c in node.children:
        if c.node_type == "element" and not is_inline(c.tag):
            return false
        if c.node_type == "comment" or c.node_type == "doctype":
            return false
    return true

func _write(node, o, out, level, inline_ctx):
    t := node.node_type
    if t == "document":
        for c in node.children:
            _write(c, o, out, level, false)
        return
    if t == "doctype":
        append(out, node.to_html())
        return
    if t == "text":
        if o.pretty and not inline_ctx:
            s := _s.trim(node.text)
            if s == "":
                return
            append(out, _nl(o, level) + _esc.escape_text(s))
            return
        append(out, _esc.escape_text(node.text))
        return
    if t == "comment":
        if o.omit_comments:
            return
        if o.pretty and not inline_ctx:
            append(out, _nl(o, level))
        append(out, node.to_html())
        return
    if t == "raw":
        if o.pretty and not inline_ctx:
            append(out, _nl(o, level))
        append(out, node.markup)
        return
    if t != "element":
        _err.html_error("html_serializer.serialize", "nœud inconnu (node_type " + str(t) + ")")
    tag := node.tag
    block := o.pretty and not inline_ctx
    if block:
        append(out, _nl(o, level))
    append(out, "<" + tag + node.attributes.render(o.sort_attributes))
    if is_void(tag):
        append(out, " />" if o.xhtml else ">")
        return
    append(out, ">")
    ltag := _s.lower(tag)
    if is_raw_text(ltag) or ltag in ESCAPABLE_RAW_TEXT_ELEMENTS:
        if is_raw_text(ltag):
            for c in node.children:
                append(out, _raw_child(ltag, c))
        else:
            for c in node.children:
                if c.node_type == "text":
                    append(out, _esc.escape_text(c.text))
                elif c.node_type == "raw":
                    append(out, c.markup)
        append(out, "</" + tag + ">")
        return
    if ltag in PRESERVE_WHITESPACE or not o.pretty:
        for c in node.children:
            _write(c, o, out, level + 1, true)
        append(out, "</" + tag + ">")
        return
    if inline_ctx or _all_inline(node):
        for c in node.children:
            _write(c, o, out, level + 1, true)
        append(out, "</" + tag + ">")
        return
    for c in node.children:
        _write(c, o, out, level + 1, false)
    append(out, _nl(o, level) + "</" + tag + ">")

# Texte d'un nœud (concaténation des textes descendants, hors commentaires).
func text_content(node):
    t := node.node_type
    if t == "text":
        return node.text
    if t == "raw":
        return node.text_content()
    if t == "element" or t == "document":
        out := []
        for c in node.children:
            append(out, text_content(c))
        return _s.join("", out)
    return ""
