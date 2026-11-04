# ALEX STANDARD LIBRARY — web.html.body
#
# Le corps <body> d'un document : le construire, y ajouter du contenu, et assembler une page complète avec la
# structure accessible recommandée (lien d'évitement, <header>, <nav>, <main id="contenu">, <footer>).
#
#   use web.html.body as bd
#   use web.html.semantic_elements as se
#   menu := [("Accueil", "/"), ("Blog", "/blog")]
#   doc := bd.page("Blog", [se.h1("Articles"), se.p("Bienvenue !")], "fr", ["/static/site.css"], ["/static/app.js"], "Le blog d'Alex", menu, "/blog", "© 2026 Alex")
#   doc.pretty()
#
#   bd.append_content(doc, se.p("Ajouté à la fin du contenu principal"))
#   bd.add_class(doc, "theme-sombre")
#   bd.main_region(doc)          # <main> s'il existe, sinon <body>
#
# Erreurs : HtmlError.

from core use len, type
from collections use append
use string as _s
use web.html.html_errors as _err
use web.html.element as _el
use web.html.element_factory as _f
use web.html.document as _document
use web.html.head as _head
use web.html.links as _links

func body(content=null, attributes=null):
    return _el.Element("body", attributes, content)

func _body_of(target):
    if target.node_type == "document":
        return target.body()
    if target.node_type == "element" and target.tag == "body":
        return target
    _err.html_error("body", "Document ou élément <body> attendu")

# Région principale : <main> s'il existe, sinon <body>.
func main_region(target):
    b := _body_of(target)
    m := b.find("main")
    if m != null:
        return m
    return b

# Ajoute du contenu à la région principale.
func append_content(target, content):
    main_region(target).append(content)
    return target

func prepend_content(target, content):
    main_region(target).prepend(content)
    return target

func add_class(target, name):
    _body_of(target).add_class(name)
    return target

func remove_class(target, name):
    _body_of(target).remove_class(name)
    return target

func set_attribute(target, name, value):
    _body_of(target).set(name, value)
    return target

# Regroupe tout le contenu de <body> (hors scripts) dans <main id="contenu"> s'il n'y a pas de <main>.
func wrap_main(target, id="contenu"):
    b := _body_of(target)
    if b.find("main") != null:
        return b.find("main")
    m := _el.Element("main", {"id": id})
    kept := []
    moved := []
    for c in b.children:
        if c.node_type == "element" and c.tag == "script":
            append(kept, c)
        else:
            append(moved, c)
    b.clear()
    m.append(moved)
    b.append(m)
    b.append(kept)
    return m

# Lien d'évitement en tête de <body> vers la région principale (créée au besoin).
func add_skip_link(target, text="Aller au contenu"):
    m := wrap_main(target)
    id := m.get("id")
    if id == null:
        id = "contenu"
        m.set("id", id)
    b := _body_of(target)
    if b.find("a.skip-link") == null:
        b.prepend(_links.skip_link(id, text))
    return target

# Bandeau affiché quand JavaScript est désactivé.
func add_noscript_message(target, text="Cette page fonctionne mieux avec JavaScript activé."):
    _body_of(target).prepend(_el.Element("noscript", null, [_el.Element("p", {"class": "noscript"}, text)]))
    return target

# Squelette de page : liste [header?, main, footer?] prête à mettre dans <body>.
func layout(main_content, header_content=null, footer_content=null, aside_content=null, main_id="contenu"):
    out := []
    if header_content != null:
        append(out, _el.Element("header", null, header_content))
    m := _el.Element("main", {"id": main_id}, main_content)
    append(out, m)
    if aside_content != null:
        append(out, _el.Element("aside", null, aside_content))
    if footer_content != null:
        append(out, _el.Element("footer", null, footer_content))
    return out

# Page complète : Document avec titre, langue, feuilles de style, scripts (defer), description, navigation
# (paires (texte, href), current = href actif), pied de page, et lien d'évitement.
func page(title, content=null, lang="fr", stylesheets=null, scripts=null, description=null, nav_items=null, current=null, footer_content=null, header_content=null):
    doc := _document.Document(title, lang)
    if description != null:
        _head.set_description(doc, description)
    if stylesheets != null:
        for s in stylesheets:
            _head.add_stylesheet(doc, s)
    header := []
    if header_content != null:
        append(header, header_content)
    if nav_items != null:
        append(header, _links.nav(nav_items, current))
    b := doc.body()
    b.append(layout(content, header if len(header) > 0 else null, footer_content))
    b.prepend(_links.skip_link("contenu"))
    if scripts != null:
        for src in scripts:
            _head.add_script(doc, src)
    return doc

# Page d'erreur simple (utilisée par web.server pour 404, 500...).
func error_page(status, title, message=null, lang="fr"):
    content := [_el.Element("h1", null, str(status) + " — " + title)]
    if message != null:
        append(content, _el.Element("p", null, message))
    append(content, _el.Element("p", null, [_el.Element("a", {"href": "/"}, "Retour à l'accueil")]))
    doc := _document.Document(str(status) + " " + title, lang)
    doc.body().append(_el.Element("main", {"id": "contenu"}, content))
    return doc
