# ALEX STANDARD LIBRARY — web.html.head
#
# L'en-tête <head> d'un document : le construire (head(...)) ou le modifier dans un Document existant (titre,
# méta-données, feuilles de style, scripts, préchargements). Les fonctions qui modifient évitent les doublons :
# set_meta remplace une méta-donnée de même nom, add_stylesheet n'ajoute pas deux fois la même feuille.
#
#   use web.html.document as dm
#   use web.html.head as hd
#   doc := dm.Document("Accueil")
#   hd.set_description(doc, "Page d'accueil")
#   hd.add_stylesheet(doc, "/static/site.css")
#   hd.add_script(doc, "/static/app.js")
#   hd.set_canonical(doc, "https://exemple.org/")
#   hd.add_preconnect(doc, "https://cdn.exemple.org")
#   hd.get_meta(doc, "description")       # Page d'accueil
#
#   h := hd.head("Titre", [md.description("…")])   # <head> neuf : charset, viewport, titre, puis les nœuds donnés
#
# Erreurs : HtmlError.

from core use len, type
from collections use append
use string as _s
use web.html.html_errors as _err
use web.html.element as _el
use web.html.metadata as _md
use web.html.stylesheets as _css
use web.html.scripts as _js

# <head> complet : charset, viewport, <title>, puis children.
func head(title=null, children=null, charset="utf-8", viewport=true):
    h := _el.Element("head")
    if charset != null and charset != false:
        h.append(_md.charset(charset))
    if viewport:
        h.append(_md.viewport())
    if title != null:
        h.append(_el.Element("title", null, [str(title)]))
    if children != null:
        h.append(children)
    return h

func _head_of(target):
    if target.node_type == "document":
        return target.head()
    if target.node_type == "element" and target.tag == "head":
        return target
    _err.html_error("head", "Document ou élément <head> attendu")

# Ajoute des nœuds à <head> (avant les scripts déjà présents si before_scripts).
func add(target, nodes, before_scripts=false):
    h := _head_of(target)
    if before_scripts:
        first := h.find("script")
        if first != null and first.parent == h:
            h.insert_before(nodes, first)
            return h
    h.append(nodes)
    return h

func title(target):
    t := _head_of(target).find("title")
    if t == null:
        return null
    return t.text_content()

func set_title(target, text):
    h := _head_of(target)
    t := h.find("title")
    if t == null:
        t = _el.Element("title")
        h.append(t)
    t.set_text(text)
    return t

# Contenu d'une méta-donnée (name ou property), ou null.
func get_meta(target, name):
    return _md.read(_head_of(target), name)

# Fixe une méta-donnée (remplace celle de même nom ou propriété).
func set_meta(target, name, content, is_property=false):
    h := _head_of(target)
    for m in h.find_all("meta"):
        if (not is_property and m.get("name") == name) or (is_property and m.get("property") == name):
            m.set("content", str(content))
            return m
    m := _md.property(name, content) if is_property else _md.meta(name, content)
    h.append(m)
    return m

func remove_meta(target, name):
    h := _head_of(target)
    n := 0
    for m in h.find_all("meta"):
        if m.get("name") == name or m.get("property") == name:
            m.remove()
            n += 1
    return n

func set_description(target, text):
    return set_meta(target, "description", text)

func set_robots(target, index=true, follow=true):
    return set_meta(target, "robots", _md.robots(index, follow).get("content"))

func set_charset(target, charset="utf-8"):
    h := _head_of(target)
    m := h.find("meta[charset]")
    if m == null:
        h.prepend(_md.charset(charset))
    else:
        m.set("charset", charset)
    return h

func set_canonical(target, url):
    h := _head_of(target)
    l := h.find("link[rel=canonical]")
    if l == null:
        h.append(_md.canonical(url))
    else:
        l.set("href", url)
    return h

func set_base(target, href, base_target=null):
    h := _head_of(target)
    b := h.find("base")
    if b == null:
        # <base> doit précéder toute URL relative : juste après les méta-données d'encodage
        h.insert(1 if h.find("meta[charset]") != null else 0, _md.base(href, base_target))
    else:
        b.set("href", href)
        b.set("target", base_target)
    return h

# Ajoute une feuille de style (pas de doublon sur href).
func add_stylesheet(target, href, media=null, integrity=null):
    h := _head_of(target)
    for l in h.find_all("link[rel=stylesheet]"):
        if l.get("href") == href:
            return l
    l := _css.stylesheet(href, media, integrity)
    add(h, l, true)
    return l

func add_style(target, css, nonce=null):
    s := _css.style(css, null, nonce)
    _head_of(target).append(s)
    return s

# Ajoute un script (pas de doublon sur src) ; defer par défaut.
func add_script(target, src, defer=true, async_load=false, module=false, integrity=null, nonce=null):
    h := _head_of(target)
    for s in h.find_all("script[src]"):
        if s.get("src") == src:
            return s
    s := _js.script(src, defer, async_load, module, integrity, null, nonce)
    h.append(s)
    return s

func add_inline_script(target, code, nonce=null):
    s := _js.inline(code, nonce)
    _head_of(target).append(s)
    return s

# Indications de ressources (rel=preload, prefetch, preconnect, dns-prefetch).
func add_preload(target, href, kind, media_type=null, crossorigin=null):
    l := _el.Element("link", {"rel": "preload", "href": href, "as": kind, "type": media_type, "crossorigin": crossorigin})
    add(target, l, true)
    return l

func add_prefetch(target, href):
    l := _el.Element("link", {"rel": "prefetch", "href": href})
    _head_of(target).append(l)
    return l

func add_preconnect(target, origin, crossorigin=false):
    l := _el.Element("link", {"rel": "preconnect", "href": origin, "crossorigin": "anonymous" if crossorigin else null})
    add(target, l, true)
    return l

func add_dns_prefetch(target, origin):
    l := _el.Element("link", {"rel": "dns-prefetch", "href": origin})
    add(target, l, true)
    return l

func add_icon(target, href, media_type=null, sizes=null):
    l := _md.icon(href, media_type, sizes)
    _head_of(target).append(l)
    return l

# Ajoute Open Graph, carte Twitter / X, description et canonique (voir metadata.seo).
func add_seo(target, title_text, description=null, url=null, image=null, site_name=null):
    for e in _md.seo(title_text, description, url, image, site_name):
        if e.tag == "meta" and e.get("name") == "description":
            set_description(target, description)
        elif e.tag == "link":
            set_canonical(target, url)
        else:
            _head_of(target).append(e)
    return _head_of(target)

func add_json_ld(target, data):
    s := _md.json_ld(data)
    _head_of(target).append(s)
    return s

# Ordre recommandé : charset, viewport, base, title, puis le reste dans l'ordre existant.
func reorder(target):
    h := _head_of(target)
    first := []
    rest := []
    for c in h.children:
        if c.node_type == "element" and ((c.tag == "meta" and (c.has("charset") or c.get("name") == "viewport")) or c.tag == "base" or c.tag == "title"):
            append(first, c)
        else:
            append(rest, c)
    rank := (c) => 0 if c.has("charset") else (1 if c.get("name") == "viewport" else (2 if c.tag == "base" else 3))
    ordered := []
    for r in [0, 1, 2, 3]:
        for c in first:
            if rank(c) == r:
                append(ordered, c)
    h.clear()
    h.append(ordered + rest)
    return h
