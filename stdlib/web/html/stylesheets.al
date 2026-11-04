# ALEX STANDARD LIBRARY — web.html.stylesheets
#
# Feuilles de style : liens <link rel="stylesheet">, blocs <style> (contenu neutralisé : impossible de fermer
# l'élément depuis le CSS), et petit générateur de CSS depuis des dict ALEX (règles, requêtes média, @font-face,
# variables).
#
#   use web.html.stylesheets as css
#   css.stylesheet("/static/site.css")                       # <link rel="stylesheet" href="/static/site.css">
#   css.stylesheet("https://cdn/x.css", "print", "sha384-…") # media + intégrité (crossorigin ajouté)
#   regles := css.rules({"body": {"margin": 0, "font_family": "system-ui"}, ".carte:hover": {"color": "red"}})
#   css.style(regles)                                        # <style>body { margin: 0; font-family: system-ui }…</style>
#   css.media("(max-width: 600px)", {"nav": {"display": "none"}})
#   css.inline({"color": "red", "margin_top": "1em"})        # color: red; margin-top: 1em
#
# Erreurs : HtmlError (sélecteur ou propriété vide), TypeError.

from core use len, type
from collections use append, keys
use string as _s
use web.html.html_errors as _err
use web.html.element as _el
use web.html.attribute_value as _av

# <link rel="stylesheet"> ; integrity : empreinte SRI (« sha384-… ») ; crossorigin ajouté avec integrity.
func stylesheet(href, media=null, integrity=null, crossorigin=null, attributes=null):
    attrs := {"rel": "stylesheet", "href": href, "media": media, "integrity": integrity}
    if integrity != null and crossorigin == null:
        crossorigin = "anonymous"
    attrs["crossorigin"] = crossorigin
    e := _el.Element("link", attrs)
    if attributes != null:
        e.set_attributes(attributes)
    return e

# Feuille alternative (sélectionnable par l'utilisateur) : title obligatoire.
func alternate_stylesheet(href, title):
    return _el.Element("link", {"rel": "alternate stylesheet", "href": href, "title": title})

# Préchargement d'une feuille (rel=preload as=style).
func preload(href):
    return _el.Element("link", {"rel": "preload", "href": href, "as": "style"})

# <style> ; css : texte ou dict de règles (voir rules) ; nonce : jeton CSP.
func style(css, media=null, nonce=null):
    text := css
    if type(css) == "dict":
        text = rules(css)
    return _el.Element("style", {"media": media, "nonce": nonce}, [str(text)])

# Nom de propriété ALEX -> CSS : font_size -> font-size ; « --var » gardé.
func property_name(name):
    n := str(name)
    if _s.starts_with(n, "--"):
        return n
    return _s.replace(n, "_", "-")

func _value(v):
    if type(v) == "int" or type(v) == "float":
        return str(v)
    if type(v) == "list" or type(v) == "tuple":
        parts := []
        for x in v:
            append(parts, str(x))
        return _s.join(", ", parts)
    return str(v)

# Déclarations « a: b; c: d » depuis un dict (valeurs null / false ignorées).
func declarations(props, separator="; "):
    out := []
    for k in keys(props):
        v := props[k]
        if v == null or v == false:
            continue
        p := property_name(k)
        if p == "":
            _err.html_error("stylesheets.declarations", "nom de propriété vide")
        append(out, p + ": " + _value(v))
    return _s.join(separator, out)

# Valeur d'attribut style depuis un dict.
func inline(props):
    return _av.style_text(props)

# Une règle : « sélecteur { déclarations } ».
func rule(selector, props):
    if _s.trim(str(selector)) == "":
        _err.html_error("stylesheets.rule", "sélecteur vide")
    return str(selector) + " { " + declarations(props) + " }"

# Plusieurs règles depuis un dict sélecteur -> déclarations (un dict imbriqué dont la clé commence par « @ » est
# un bloc : « @media … »).
func rules(sheet, pretty=false):
    out := []
    for sel in keys(sheet):
        v := sheet[sel]
        if _s.starts_with(sel, "@"):
            append(out, sel + " { " + rules(v) + " }")
        elif type(v) == "dict":
            append(out, rule(sel, v))
        else:
            append(out, str(v))
    return _s.join("\n" if pretty else " ", out)

func media(query, sheet):
    return "@media " + query + " { " + rules(sheet) + " }"

func supports(condition, sheet):
    return "@supports " + condition + " { " + rules(sheet) + " }"

# @font-face ; sources : liste de (url, format) ou str.
func font_face(family, sources, weight=null, style_name=null, display="swap", unicode_range=null):
    src := sources
    if type(sources) == "list" or type(sources) == "tuple":
        parts := []
        for s in sources:
            if type(s) == "str":
                append(parts, "url(\"" + s + "\")")
            else:
                append(parts, "url(\"" + s[0] + "\") format(\"" + s[1] + "\")")
        src = _s.join(", ", parts)
    props := {"font-family": "\"" + family + "\"", "src": src, "font-weight": weight, "font-style": style_name, "font-display": display, "unicode-range": unicode_range}
    return "@font-face { " + declarations(props) + " }"

# Variables CSS sur :root (ou un autre sélecteur) : vars({"couleur": "#333"}) -> « :root { --couleur: #333 } ».
func variables(values, selector=":root"):
    props := {}
    for k in keys(values):
        name := k if _s.starts_with(k, "--") else "--" + _s.replace(k, "_", "-")
        props[name] = values[k]
    return rule(selector, props)

# Référence à une variable : var("--couleur", "black").
func var(name, fallback=null):
    n := name if _s.starts_with(name, "--") else "--" + name
    if fallback != null:
        return "var(" + n + ", " + str(fallback) + ")"
    return "var(" + n + ")"

# Réinitialisation minimale (box-sizing, marges, images fluides).
func minimal_reset():
    return rules({"*, *::before, *::after": {"box-sizing": "border-box"}, "body": {"margin": 0, "line-height": 1.5}, "img, picture, video, canvas, svg": {"display": "block", "max-width": "100%"}, "input, button, textarea, select": {"font": "inherit"}})

# href des feuilles liées d'un document ou d'un arbre.
func linked(node):
    out := []
    for l in node.find_all("link[rel]"):
        if "stylesheet" in _av.split_tokens(_s.lower(l.get("rel", ""))):
            append(out, l.get("href"))
    return out
