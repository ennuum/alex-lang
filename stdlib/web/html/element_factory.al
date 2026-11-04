# ALEX STANDARD LIBRARY — web.html.element_factory
#
# Fabrique d'éléments : la façon courte de construire un arbre HTML depuis du code ALEX.
#
#   h(tag, attributs_ou_enfants, enfants)   attributs facultatifs : h("p", "texte"), h("a", {"href": "/"}, "Accueil")
#   create(tag, attributs, enfants)          forme explicite
#   from_spec(spec)                          notation en listes : ["ul", {"class": "x"}, ["li", "a"], ["li", "b"]]
#   tag_builder("section")                   fonction prête à l'emploi : section({"id": "s"}, [...])
#   fragment(enfants)                        liste de nœuds à insérer d'un coup
#
#   use web.html.element_factory as f
#   carte := f.h("article", {"class": "carte"}, [
#       f.h("h2", "Titre"),
#       f.h("p", ["Texte avec ", f.h("strong", "emphase"), "."]),
#   ])
#   carte.to_html()   # <article class="carte"><h2>Titre</h2><p>Texte avec <strong>emphase</strong>.</p></article>
#   f.from_spec(["ul", ["li", "un"], ["li", {"class": "b"}, "deux"]]).to_html()
#
# Les enfants str sont toujours échappés ; pour du balisage de confiance : f.raw("<svg>…</svg>").
# Erreurs : HtmlTagError, HtmlError.

from core use len, type
from collections use append
use web.html.html_errors as _err
use web.html.element as _el
use web.html.attributes as _attrs
use web.html.text_node as _text
use web.html.comment_node as _comment
use web.html.raw_html as _raw

# Éléments définis par le standard HTML (WHATWG), pour la validation et l'autocomplétion.
const KNOWN_ELEMENTS := ["a", "abbr", "address", "area", "article", "aside", "audio", "b", "base", "bdi", "bdo", "blockquote", "body", "br", "button", "canvas", "caption", "cite", "code", "col", "colgroup", "data", "datalist", "dd", "del", "details", "dfn", "dialog", "div", "dl", "dt", "em", "embed", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr", "html", "i", "iframe", "img", "input", "ins", "kbd", "label", "legend", "li", "link", "main", "map", "mark", "math", "menu", "meta", "meter", "nav", "noscript", "object", "ol", "optgroup", "option", "output", "p", "picture", "pre", "progress", "q", "rp", "rt", "ruby", "s", "samp", "script", "search", "section", "select", "slot", "small", "source", "span", "strong", "style", "sub", "summary", "sup", "svg", "table", "tbody", "td", "template", "textarea", "tfoot", "th", "thead", "time", "title", "tr", "track", "u", "ul", "var", "video", "wbr"]

# Éléments obsolètes (acceptés à l'analyse, signalés par le validateur).
const OBSOLETE_ELEMENTS := ["acronym", "applet", "basefont", "bgsound", "big", "blink", "center", "dir", "font", "frame", "frameset", "isindex", "keygen", "listing", "marquee", "menuitem", "multicol", "nextid", "nobr", "noembed", "noframes", "plaintext", "rb", "rtc", "spacer", "strike", "tt", "xmp", "param"]

func is_known(tag):
    return tag in KNOWN_ELEMENTS

func is_obsolete(tag):
    return tag in OBSOLETE_ELEMENTS

# Élément personnalisé (Web Components) : contient « - », commence par une minuscule.
func is_custom(tag):
    if len(tag) == 0:
        return false
    c := tag[0]
    if not (c >= 'a' and c <= 'z'):
        return false
    for x in tag:
        if x == '-':
            return true
    return false

func _is_attrs(value):
    return type(value) == "dict" or isinstance(value, _attrs.Attributes)

func create(tag, attributes=null, children=null):
    return _el.Element(tag, attributes, children)

# Forme souple : h(tag), h(tag, enfants), h(tag, attributs), h(tag, attributs, enfants).
func h(tag, a=null, b=null):
    if _is_attrs(a):
        return _el.Element(tag, a, b)
    if b != null:
        if a == null:
            return _el.Element(tag, null, b)
        _err.html_error("element_factory.h", "le deuxième argument doit être un dict d'attributs quand un troisième est donné")
    return _el.Element(tag, null, a)

# Ordre libre : make(tag, contenu, attributs) ou make(tag, attributs, contenu) — utilisé par les modules de
# construction (semantic_elements, lists...) pour accepter p("texte", {"class": "x"}) comme p({"class": "x"}, "texte").
func make(tag, a=null, b=null):
    if _is_attrs(a):
        return _el.Element(tag, a, b)
    if _is_attrs(b):
        return _el.Element(tag, b, a)
    if b != null:
        _err.html_error("element_factory.make", "<" + str(tag) + "> : un des deux arguments doit être un dict d'attributs")
    return _el.Element(tag, null, a)

# Fusionne des attributs (dict) : les valeurs de extra l'emportent, class est concaténé.
func merge_attributes(base, extra):
    out := _attrs.from_data(base)
    if extra == null:
        return out
    for e in _attrs.from_data(extra).entries:
        if e[0] == "class":
            out.add_class(e[1] if type(e[1]) == "str" else _join_tokens(e[1]))
        else:
            out.set(e[0], e[1])
    return out

func _join_tokens(v):
    out := ""
    for x in v:
        out = out + " " + str(x)
    return out

func text(value):
    return _text.TextNode(value)

func comment(value):
    return _comment.CommentNode(value)

func raw(markup):
    return _raw.RawHtml(markup)

# Liste de nœuds (str -> TextNode, listes aplaties).
func fragment(children):
    return _el.to_nodes(children)

# Objet appelable qui construit une balise donnée : nav := tag_builder("nav") ; nav({"class": "x"}, [...]).
class TagBuilder:
    func init(tag):
        if not _el.is_valid_tag(tag):
            _err.tag_error("element_factory.tag_builder", "nom de balise invalide '" + str(tag) + "'")
        self.tag = tag

    func __call__(a=null, b=null):
        return h(self.tag, a, b)

func tag_builder(tag):
    return TagBuilder(tag)

# Notation en listes : [balise, attributs?, enfant...] ; un enfant peut être une str, un nœud ou une autre liste
# dont le premier élément est un nom de balise HTML connu ou personnalisé (« mon-widget ») ; toute autre liste est
# une liste d'enfants.
func from_spec(spec):
    if type(spec) == "str" or _el.is_node(spec):
        return spec
    if (type(spec) != "list" and type(spec) != "tuple") or len(spec) == 0 or type(spec[0]) != "str":
        _err.html_error("element_factory.from_spec", "[balise, attributs?, enfants...] attendu")
    tag := spec[0]
    attrs := null
    start := 1
    if len(spec) > 1 and _is_attrs(spec[1]):
        attrs = spec[1]
        start = 2
    e := _el.Element(tag, attrs)
    i := start
    while i < len(spec):
        c := spec[i]
        if (type(c) == "list" or type(c) == "tuple") and len(c) > 0 and type(c[0]) == "str" and (is_known(c[0]) or is_custom(c[0])):
            e.append(from_spec(c))
        else:
            e.append(c)
        i += 1
    return e

# Copie profonde d'un nœud quelconque.
func clone(node):
    if node.node_type == "element":
        return node.clone(true)
    return node.clone()
