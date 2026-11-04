# ALEX STANDARD LIBRARY — web.html
#
# Point d'entrée du paquet web.html : construire, analyser, transformer, valider et produire du HTML5, en ALEX
# pur. Les données textuelles sont TOUJOURS échappées ; seul RawHtml insère du balisage tel quel.
#
# | Module                          | Rôle                                                              |
# |---------------------------------|-------------------------------------------------------------------|
# | web.html (ce module)            | raccourcis : h, document, parse, escape, render, validate         |
# | web.html.document / element     | arbre : Document, Element (sélecteurs CSS, navigation, édition)    |
# | web.html.element_factory        | h(), make(), from_spec() : construction concise                    |
# | web.html.text_node / comment_node / raw_html / document_type | autres nœuds                   |
# | web.html.attributes / attribute_value | attributs (class, style, data-*, booléens)               |
# | web.html.html_parser            | analyse tolérante (comme un navigateur), fragments, sanitize      |
# | web.html.html_serializer / html_writer | sérialisation (compacte / indentée), écriture en flux     |
# | web.html.html_escape            | échappement, 2 231 références nommées                             |
# | web.html.html_validate          | conformité, accessibilité, sécurité                               |
# | web.html.head / body / metadata | en-tête, corps, méta-données, page complète                       |
# | web.html.semantic_elements / links / images / tables / lists / forms / scripts / stylesheets / iframe |
# |                                 | constructeurs spécialisés                                         |
# | web.html.html_errors            | erreurs et Issue                                                  |
#
#   use web.html as html
#   doc := html.document("Accueil")
#   doc.body().append(html.h("main", {"id": "contenu"}, [html.h("h1", "Bonjour <monde>")]))
#   html.render(doc)                         # <!DOCTYPE html><html lang="fr">…<h1>Bonjour &lt;monde&gt;</h1>…
#   page := html.parse("<p class=x>Un<p>Deux")
#   [p.text_content() for p in page.find_all("p.x")]   # ["Un"]
#   html.escape("<script>")                  # &lt;script&gt;
#   html.sanitize("<b onclick=x>ok</b><script>mal()</script>")   # <b>ok</b>
#   html.is_valid(doc)                       # true
#
# Erreurs : HtmlError, HtmlParseError, HtmlAttributeError, HtmlTagError, HtmlValidationError.

from core use len, type
use web.html.html_errors as _err
use web.html.html_escape as _esc
use web.html.element as _el
use web.html.element_factory as _f
use web.html.text_node as _text
use web.html.comment_node as _comment
use web.html.raw_html as _raw
use web.html.document as _document
use web.html.html_parser as _parser
use web.html.html_serializer as _ser
use web.html.html_writer as _writer
use web.html.html_validate as _validate
use web.html.body as _body

# ---------------------------------------------------------------- construction

func h(tag, a=null, b=null):
    return _f.h(tag, a, b)

func element(tag, attributes=null, children=null):
    return _el.Element(tag, attributes, children)

func text(value):
    return _text.TextNode(value)

func comment(value):
    return _comment.CommentNode(value)

func raw(markup):
    return _raw.RawHtml(markup)

func fragment(children):
    return _f.fragment(children)

func from_spec(spec):
    return _f.from_spec(spec)

func document(title=null, lang="fr", charset="utf-8"):
    return _document.Document(title, lang, charset)

# Page complète (voir web.html.body.page).
func page(title, content=null, lang="fr", stylesheets=null, scripts=null, description=null):
    return _body.page(title, content, lang, stylesheets, scripts, description)

func writer(pretty=false, sink=null):
    return _writer.HtmlWriter(pretty, sink)

# ---------------------------------------------------------------- analyse

func parse(text, strict=false):
    return _parser.parse(text, strict)

func parse_fragment(text, context="div"):
    return _parser.parse_fragment(text, context)

func parse_element(text):
    return _parser.parse_element(text)

func sanitize(text):
    return _parser.sanitize(text)

func to_text(text):
    return _parser.to_text(text)

# ---------------------------------------------------------------- sortie

# Texte HTML d'un nœud, d'une liste de nœuds ou d'une str (échappée).
func render(node, pretty=false):
    o := _ser.pretty() if pretty else null
    if type(node) == "list" or type(node) == "tuple":
        out := ""
        for n in _el.to_nodes(node):
            out = out + _ser.serialize(n, o)
        return out
    if type(node) == "str":
        return _esc.escape_text(node)
    return _ser.serialize(node, o)

func escape(text):
    return _esc.escape(text)

func escape_text(text):
    return _esc.escape_text(text)

func unescape(text):
    return _esc.unescape(text)

func strip_tags(text):
    return _esc.strip_tags(text)

# ---------------------------------------------------------------- recherche et validation

func select(node, selector):
    return _el.select(node, selector)

func select_one(node, selector):
    return _el.select_one(node, selector)

func validate(node):
    return _validate.validate(node)

func is_valid(node):
    return _validate.is_valid(node)

func report(node):
    return _validate.report(_validate.validate(node))
