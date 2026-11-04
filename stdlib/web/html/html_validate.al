# ALEX STANDARD LIBRARY — web.html.html_validate
#
# Validation d'un document ou d'un arbre HTML : conformité (structure, identifiants, attributs), accessibilité
# (textes alternatifs, étiquettes de formulaire, titres, langue) et sécurité (URL javascript:, liens target=_blank,
# gestionnaires d'événements en ligne). Chaque problème est une Issue (web.html.html_errors) : niveau error,
# warning ou info, code stable, message, chemin de l'élément.
#
#   use web.html.html_validate as hv
#   issues := hv.validate(doc)
#   for i in issues:
#       print(str(i))            # error [img-alt] <img> sans attribut alt (html > body > img)
#   hv.is_valid(doc)             # true si aucune erreur (les avertissements sont permis)
#   hv.check(doc)                # HtmlValidationError s'il y a au moins une erreur
#   print(hv.report(issues))     # résumé lisible
#
# Codes : doctype, html-lang, charset, title, viewport, unknown-element, obsolete-element, duplicate-id,
# invalid-id, img-alt, img-src, link-href, link-target-blank, unsafe-url, inline-handler, input-type,
# control-label, label-for, button-name, heading-order, multiple-h1, iframe-title, iframe-sandbox,
# nested-interactive, list-item-parent, table-structure, option-parent, block-in-p, boolean-false,
# obsolete-attribute, empty-heading, multiple-main, viewport-zoom, form-action, empty-link.
#
# Erreurs : HtmlValidationError (check).

from core use len, type
from collections use append
use string as _s
use web.html.html_errors as _err
use web.html.attribute_value as _av
use web.html.element_factory as _factory
use web.html.html_serializer as _ser

const INPUT_TYPES := ["button", "checkbox", "color", "date", "datetime-local", "email", "file", "hidden", "image", "month", "number", "password", "radio", "range", "reset", "search", "submit", "tel", "text", "time", "url", "week"]
const SANDBOX_TOKENS := ["allow-downloads", "allow-forms", "allow-modals", "allow-orientation-lock", "allow-pointer-lock", "allow-popups", "allow-popups-to-escape-sandbox", "allow-presentation", "allow-same-origin", "allow-scripts", "allow-top-navigation", "allow-top-navigation-by-user-activation", "allow-top-navigation-to-custom-protocols", "allow-storage-access-by-user-activation"]
const INTERACTIVE := ["a", "button", "details", "embed", "iframe", "label", "select", "textarea", "input"]
const BLOCK_IN_P := ["address", "article", "aside", "blockquote", "details", "dialog", "div", "dl", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "main", "menu", "nav", "ol", "p", "pre", "section", "table", "ul"]
const OBSOLETE_ATTRIBUTES := ["align", "bgcolor", "border", "cellpadding", "cellspacing", "frameborder", "marginheight", "marginwidth", "scrolling", "valign", "hspace", "vspace", "background", "clear", "nowrap"]
const UNLABELLED_INPUTS := ["hidden", "submit", "reset", "button", "image"]

class Options:
    func init(accessibility=true, security=true, structure=true, document=true):
        self.accessibility = accessibility
        self.security = security
        self.structure = structure
        self.document = document

class _State:
    func init(options):
        self.o = options
        self.issues = []
        self.ids = {}
        self.labels_for = []
        self.label_targets = []
        self.headings = []
        self.h1_count = 0
        self.main_count = 0

    func add(level, code, message, el):
        where := el.path() if el != null else null
        append(self.issues, _err.Issue(level, code, message, where))

func _elements(node):
    if node.node_type == "element":
        return [node] + node.descendants()
    return node.descendants()

func _has_ancestor(el, tags):
    p := el.parent
    while p != null and p.node_type == "element":
        if p.tag in tags:
            return true
        p = p.parent
    return false

func _accessible_name(el):
    for a in ["aria-label", "aria-labelledby", "title"]:
        v := el.get(a)
        if v != null and _s.trim(v) != "":
            return v
    t := _s.trim(_ser.text_content(el))
    if t != "":
        return t
    for img in el.find_all("img[alt]"):
        if _s.trim(img.get("alt")) != "":
            return img.get("alt")
    return null

func _in_foreign(el):
    return _has_ancestor(el, ["svg", "math"]) or el.tag == "svg" or el.tag == "math"

# Problèmes du document ou de l'arbre (liste d'Issue, dans l'ordre du document).
func validate(node, options=null):
    o := options if options != null else Options()
    st := _State(o)
    if node.node_type == "document" and o.document:
        _check_document(node, st)
    for el in _elements(node):
        _check_element(el, st)
    if o.accessibility:
        _check_headings(st)
        for target in st.labels_for:
            if not (target[0] in st.ids):
                st.add(_err.ERROR, "label-for", "<label for=\"" + target[0] + "\"> ne désigne aucun élément", target[1])
    return st.issues

func _check_document(doc, st):
    d := doc.doctype()
    if d == null:
        st.add(_err.ERROR, "doctype", "<!DOCTYPE html> manquant (le navigateur passe en mode quirks)", null)
    elif not d.is_html5():
        st.add(_err.WARNING, "doctype", "DOCTYPE ancien : préférer <!DOCTYPE html>", null)
    html := doc.html()
    lang := html.get("lang")
    if lang == null or _s.trim(lang) == "":
        st.add(_err.ERROR, "html-lang", "<html> sans attribut lang (langue nécessaire aux lecteurs d'écran)", html)
    cs := doc.charset()
    if cs == null:
        st.add(_err.ERROR, "charset", "encodage non déclaré : ajouter <meta charset=\"utf-8\">", null)
    elif cs != "utf-8" and cs != "utf8":
        st.add(_err.WARNING, "charset", "encodage " + cs + " : UTF-8 est recommandé", null)
    t := doc.title()
    if t == null or t == "":
        st.add(_err.ERROR, "title", "<title> manquant ou vide", null)
    vp := doc.head().find("meta[name=viewport]")
    if vp == null:
        st.add(_err.INFO, "viewport", "pas de <meta name=\"viewport\"> : rendu mobile dégradé", null)
    elif st.o.accessibility:
        c := _s.lower(_s.replace(vp.get("content", ""), " ", ""))
        if _s.contains(c, "user-scalable=no") or _s.contains(c, "maximum-scale=1,") or _s.ends_with(c, "maximum-scale=1"):
            st.add(_err.WARNING, "viewport-zoom", "le zoom est bloqué (user-scalable=no / maximum-scale=1) : gênant pour l'accessibilité", vp)

func _check_element(el, st):
    o := st.o
    tag := el.tag
    foreign := _in_foreign(el)
    if o.structure and not foreign:
        if _factory.is_obsolete(tag):
            st.add(_err.WARNING, "obsolete-element", "<" + tag + "> est obsolète", el)
        elif not _factory.is_known(tag) and not _factory.is_custom(tag):
            st.add(_err.WARNING, "unknown-element", "élément inconnu <" + tag + ">", el)
    # identifiants
    id := el.get("id")
    if id != null:
        if id == "" or _s.contains(id, " ") or _s.contains(id, "\t") or _s.contains(id, "\n"):
            st.add(_err.ERROR, "invalid-id", "id vide ou avec des espaces (« " + id + " »)", el)
        elif id in st.ids:
            st.add(_err.ERROR, "duplicate-id", "id « " + id + " » utilisé plusieurs fois", el)
        else:
            st.ids[id] = true
    # attributs
    for e in el.attributes.entries:
        name := _s.lower(e[0])
        v := e[1]
        if o.structure and _av.is_boolean(name) and type(v) == "str" and _s.lower(v) == "false":
            st.add(_err.WARNING, "boolean-false", name + "=\"false\" ACTIVE l'attribut (un attribut booléen est vrai dès qu'il est présent)", el)
        if o.structure and name in OBSOLETE_ATTRIBUTES and not foreign and not (name == "border" and tag == "img"):
            st.add(_err.INFO, "obsolete-attribute", "attribut de présentation obsolète « " + name + " » (utiliser CSS)", el)
        if o.security and _av.is_event_handler(name):
            st.add(_err.INFO, "inline-handler", "gestionnaire en ligne « " + name + " » (incompatible avec une CSP stricte)", el)
        if o.security and _av.is_url_attribute(name) and type(v) == "str" and not _av.is_safe_url(v, ["http", "https", "mailto", "tel", "ftp", "sms", "data-image"]):
            st.add(_err.WARNING, "unsafe-url", "URL potentiellement dangereuse dans " + name + " (« " + v[0:40] + " »)", el)
    if tag == "main" and not el.has("hidden"):
        st.main_count += 1
        if st.main_count == 2:
            st.add(_err.ERROR, "multiple-main", "plusieurs <main> visibles", el)
    if tag in ["h1", "h2", "h3", "h4", "h5", "h6"]:
        append(st.headings, (_s.ord(tag[1]) - 48, el))
        if tag == "h1":
            st.h1_count += 1
        if o.accessibility and _accessible_name(el) == null:
            st.add(_err.WARNING, "empty-heading", "titre <" + tag + "> vide", el)
    if tag == "img":
        if not el.has("src") and not el.has("srcset"):
            st.add(_err.ERROR, "img-src", "<img> sans src", el)
        if o.accessibility and el.get("alt") == null and el.get("role") != "presentation" and el.get("aria-hidden") != "true":
            st.add(_err.ERROR, "img-alt", "<img> sans attribut alt (alt=\"\" pour une image décorative)", el)
    if tag == "a":
        href := el.get("href")
        if href == null and el.get("role") == null:
            st.add(_err.INFO, "link-href", "<a> sans href n'est pas un lien navigable", el)
        if o.security and el.get("target") == "_blank":
            rel := _av.split_tokens(el.get("rel", ""))
            if href != null and not ("noopener" in rel) and not ("noreferrer" in rel) and (_s.starts_with(href, "http:") or _s.starts_with(href, "https:") or _s.starts_with(href, "//")):
                st.add(_err.INFO, "link-target-blank", "lien externe target=\"_blank\" sans rel=\"noopener\"", el)
        if o.accessibility and href != null and _accessible_name(el) == null:
            st.add(_err.ERROR, "empty-link", "lien sans texte ni nom accessible", el)
    if tag == "input":
        t := _s.lower(el.get("type", "text"))
        if not (t in INPUT_TYPES):
            st.add(_err.ERROR, "input-type", "type d'input inconnu « " + t + " »", el)
        if o.accessibility and not (t in UNLABELLED_INPUTS):
            _check_label(el, st)
        if t == "image" and o.accessibility and el.get("alt") == null:
            st.add(_err.ERROR, "img-alt", "<input type=\"image\"> sans alt", el)
    if (tag == "select" or tag == "textarea") and o.accessibility:
        _check_label(el, st)
    if tag == "label":
        f := el.get("for")
        if f != null:
            append(st.labels_for, (f, el))
    if tag == "button" and o.accessibility and _accessible_name(el) == null:
        st.add(_err.ERROR, "button-name", "<button> sans texte ni nom accessible", el)
    if tag == "iframe":
        if o.accessibility and (el.get("title") == null or _s.trim(el.get("title")) == ""):
            st.add(_err.WARNING, "iframe-title", "<iframe> sans title", el)
        sb := el.get("sandbox")
        if sb != null:
            for tok in _av.split_tokens(sb):
                if not (_s.lower(tok) in SANDBOX_TOKENS):
                    st.add(_err.ERROR, "iframe-sandbox", "jeton sandbox inconnu « " + tok + " »", el)
            toks := _av.split_tokens(_s.lower(sb))
            if o.security and "allow-scripts" in toks and "allow-same-origin" in toks:
                st.add(_err.WARNING, "iframe-sandbox", "allow-scripts + allow-same-origin annule la protection du bac à sable", el)
    if tag == "form" and el.get("action") != null and o.security and not _av.is_safe_url(el.get("action")):
        st.add(_err.ERROR, "form-action", "action de formulaire dangereuse", el)
    if o.structure and not foreign:
        _check_structure(el, st)

func _check_label(el, st):
    for a in ["aria-label", "aria-labelledby", "title"]:
        if el.get(a) != null:
            return
    if _has_ancestor(el, ["label"]):
        return
    id := el.get("id")
    if id != null:
        for lab in el.root().find_all("label[for]"):
            if lab.get("for") == id:
                return
    st.add(_err.WARNING, "control-label", "champ <" + el.tag + "> sans étiquette (<label>, aria-label...)", el)

func _parent_tag(el):
    if el.parent == null or el.parent.node_type != "element":
        return null
    return el.parent.tag

func _check_structure(el, st):
    tag := el.tag
    p := _parent_tag(el)
    if p == null:
        return
    if tag == "li" and not (p in ["ul", "ol", "menu"]):
        st.add(_err.ERROR, "list-item-parent", "<li> hors de <ul>, <ol> ou <menu> (parent <" + p + ">)", el)
    if (tag == "dt" or tag == "dd") and not (p == "dl" or (p == "div" and _parent_tag(el.parent) == "dl")):
        st.add(_err.ERROR, "list-item-parent", "<" + tag + "> hors de <dl>", el)
    if tag == "tr" and not (p in ["table", "thead", "tbody", "tfoot"]):
        st.add(_err.ERROR, "table-structure", "<tr> hors d'un tableau", el)
    if (tag == "td" or tag == "th") and p != "tr":
        st.add(_err.ERROR, "table-structure", "<" + tag + "> hors de <tr>", el)
    if tag == "option" and not (p in ["select", "datalist", "optgroup"]):
        st.add(_err.ERROR, "option-parent", "<option> hors de <select>, <datalist> ou <optgroup>", el)
    if tag in BLOCK_IN_P and p == "p":
        st.add(_err.ERROR, "block-in-p", "<" + tag + "> dans <p> (le navigateur fermera le paragraphe)", el)
    if tag in INTERACTIVE and not (tag == "input" and el.get("type") == "hidden"):
        if _has_ancestor(el, ["a", "button"]):
            st.add(_err.ERROR, "nested-interactive", "élément interactif <" + tag + "> dans <a> ou <button>", el)

func _check_headings(st):
    if st.h1_count > 1:
        st.add(_err.INFO, "multiple-h1", str(st.h1_count) + " titres <h1> : un seul est recommandé", null)
    prev := 0
    for h in st.headings:
        level := h[0]
        if prev > 0 and level > prev + 1:
            st.add(_err.WARNING, "heading-order", "saut de niveau de titre : <h" + str(prev) + "> puis <h" + str(level) + ">", h[1])
        prev = level

# Vrai si aucune Issue de niveau error.
func is_valid(node, options=null):
    return _err.count_errors(validate(node, options)) == 0

# HtmlValidationError (avec la première erreur et leur nombre) si le document a des erreurs ; rend les Issue sinon.
func check(node, options=null):
    issues := validate(node, options)
    errors := []
    for i in issues:
        if i.level == _err.ERROR:
            append(errors, i)
    if len(errors) > 0:
        _err.validation_error("html_validate.check", str(len(errors)) + " erreur(s), dont : " + str(errors[0]))
    return issues

# Résumé texte : une ligne par problème, puis le décompte.
func report(issues):
    lines := []
    e := 0
    w := 0
    n := 0
    for i in issues:
        append(lines, str(i))
        if i.level == _err.ERROR:
            e += 1
        elif i.level == _err.WARNING:
            w += 1
        else:
            n += 1
    append(lines, str(e) + " erreur(s), " + str(w) + " avertissement(s), " + str(n) + " information(s)")
    return _s.join("\n", lines)

# Problèmes filtrés par niveau minimal (error, warning ou info).
func filter(issues, level=_err.WARNING):
    rank := {"error": 3, "warning": 2, "info": 1}
    out := []
    for i in issues:
        if rank[i.level] >= rank[level]:
            append(out, i)
    return out
