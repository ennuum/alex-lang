# ALEX STANDARD LIBRARY — web.html.metadata
#
# Méta-données d'une page (éléments de <head>) : encodage, fenêtre d'affichage, description, robots, couleurs,
# politique de référent, Content-Security-Policy, URL canonique, langues alternatives, Open Graph, cartes Twitter /
# X, données structurées JSON-LD (schema.org), icônes et manifeste.
#
#   use web.html.metadata as md
#   md.charset()                               # <meta charset="utf-8">
#   md.viewport()                              # <meta name="viewport" content="width=device-width, initial-scale=1">
#   md.description("Recettes de saison")       # <meta name="description" content="…">
#   md.robots(false, true)                     # <meta name="robots" content="noindex, follow">
#   md.open_graph({"title": "T", "type": "article", "image": "https://…/a.png"})   # liste de <meta property="og:…">
#   md.json_ld({"@context": "https://schema.org", "@type": "Organization", "name": "Alex"})
#   md.seo("Titre", "Description", "https://exemple.org/page", "https://exemple.org/img.png")   # tout d'un coup
#
# Chaque fonction rend un Element (ou une liste d'Element) à placer dans <head> (voir web.html.head).
# Erreurs : HtmlError (valeur invalide), TypeError.

from core use len, type
from collections use append, keys
use string as _s
use json as _json
use web.html.html_errors as _err
use web.html.html_escape as _esc
use web.html.element as _el
use web.html.raw_html as _raw

const REFERRER_POLICIES := ["no-referrer", "no-referrer-when-downgrade", "origin", "origin-when-cross-origin", "same-origin", "strict-origin", "strict-origin-when-cross-origin", "unsafe-url"]

# <meta name="…" content="…">
func meta(name, content):
    return _el.Element("meta", {"name": name, "content": str(content)})

# <meta property="…" content="…"> (Open Graph, RDFa).
func property(name, content):
    return _el.Element("meta", {"property": name, "content": str(content)})

func http_equiv(name, content):
    return _el.Element("meta", {"http-equiv": name, "content": str(content)})

func charset(value="utf-8"):
    return _el.Element("meta", {"charset": value})

func viewport(content="width=device-width, initial-scale=1"):
    return meta("viewport", content)

func description(text):
    return meta("description", text)

func keywords(words):
    if type(words) == "list" or type(words) == "tuple":
        parts := []
        for w in words:
            append(parts, str(w))
        return meta("keywords", _s.join(", ", parts))
    return meta("keywords", words)

func author(name):
    return meta("author", name)

func generator(name="Alex web"):
    return meta("generator", name)

# Directives pour les robots d'indexation ; extra : liste (« noarchive », « max-snippet:50 »…).
func robots(index=true, follow=true, extra=null):
    parts := ["index" if index else "noindex", "follow" if follow else "nofollow"]
    if extra != null:
        for e in extra:
            append(parts, str(e))
    return meta("robots", _s.join(", ", parts))

func theme_color(color, media=null):
    m := meta("theme-color", color)
    if media != null:
        m.set("media", media)
    return m

# Schémas de couleurs pris en charge : « light dark ».
func color_scheme(value="light dark"):
    return meta("color-scheme", value)

func referrer(policy="strict-origin-when-cross-origin"):
    if not (policy in REFERRER_POLICIES):
        _err.html_error("metadata.referrer", "politique de référent inconnue « " + str(policy) + " »")
    return meta("referrer", policy)

# Rechargement / redirection après seconds secondes (déconseillé pour l'accessibilité).
func refresh(seconds, url=null):
    content := str(seconds)
    if url != null:
        content = content + "; url=" + url
    return http_equiv("refresh", content)

# Content-Security-Policy en méta (dict directive -> liste ou str de sources, ou str complète).
func csp(policy):
    if type(policy) == "str":
        return http_equiv("Content-Security-Policy", policy)
    parts := []
    for k in keys(policy):
        v := policy[k]
        if type(v) == "list" or type(v) == "tuple":
            vals := []
            for x in v:
                append(vals, str(x))
            append(parts, k + " " + _s.join(" ", vals))
        elif v == true or v == null or v == "":
            append(parts, k)
        else:
            append(parts, k + " " + str(v))
    return http_equiv("Content-Security-Policy", _s.join("; ", parts))

# <link rel="canonical">
func canonical(url):
    return _el.Element("link", {"rel": "canonical", "href": url})

# Version dans une autre langue : <link rel="alternate" hreflang="en" href="…">.
func alternate(href, hreflang=null, media_type=null, title=null):
    return _el.Element("link", {"rel": "alternate", "href": href, "hreflang": hreflang, "type": media_type, "title": title})

# Icône ; sizes : « 32x32 », « any ».
func icon(href, media_type=null, sizes=null, rel="icon"):
    return _el.Element("link", {"rel": rel, "href": href, "type": media_type, "sizes": sizes})

func apple_touch_icon(href, sizes="180x180"):
    return icon(href, null, sizes, "apple-touch-icon")

func manifest(href="/manifest.webmanifest"):
    return _el.Element("link", {"rel": "manifest", "href": href})

# <base href> : URL de base des liens relatifs (une seule par document).
func base(href, target=null):
    return _el.Element("base", {"href": href, "target": target})

# Open Graph : dict (« title », « type », « image », « url », « description », « site_name », « locale »…) ;
# une valeur liste donne plusieurs balises (plusieurs images).
func open_graph(values):
    out := []
    for k in keys(values):
        v := values[k]
        name := k if _s.starts_with(k, "og:") or _s.contains(k, ":") else "og:" + k
        if type(v) == "list" or type(v) == "tuple":
            for x in v:
                append(out, property(name, x))
        elif v != null:
            append(out, property(name, v))
    return out

# Carte Twitter / X : dict (« card », « site », « title », « description », « image »…).
func twitter_card(values):
    out := []
    for k in keys(values):
        v := values[k]
        if v != null:
            append(out, meta(k if _s.starts_with(k, "twitter:") else "twitter:" + k, v))
    return out

# Données structurées JSON-LD : <script type="application/ld+json"> au contenu échappé.
func json_ld(data):
    return _el.Element("script", {"type": "application/ld+json"}, [_raw.RawHtml(_esc.escape_json_for_script(_json.stringify(data, null, false)))])

# Ensemble SEO courant : description, canonique, Open Graph et carte Twitter / X.
func seo(title, description_text=null, url=null, image=null, site_name=null, locale=null, kind="website"):
    out := []
    if description_text != null:
        append(out, description(description_text))
    if url != null:
        append(out, canonical(url))
    og := {"title": title, "type": kind, "description": description_text, "url": url, "image": image, "site_name": site_name, "locale": locale}
    for e in open_graph(og):
        append(out, e)
    tw := {"card": "summary_large_image" if image != null else "summary", "title": title, "description": description_text, "image": image}
    for e in twitter_card(tw):
        append(out, e)
    return out

# Contenu d'un <meta name> (ou property) dans un document ou un <head>, ou null.
func read(node, name):
    for m in node.find_all("meta"):
        if m.get("name") == name or m.get("property") == name:
            return m.get("content")
    return null

# Toutes les méta-données nommées : dict nom -> contenu.
func read_all(node):
    out := {}
    for m in node.find_all("meta"):
        n := m.get("name")
        if n == null:
            n = m.get("property")
        if n != null:
            out[n] = m.get("content", "")
    return out
