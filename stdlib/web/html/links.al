# ALEX STANDARD LIBRARY — web.html.links
#
# Liens : <a> (internes, externes, courriel, téléphone, téléchargement, ancres), menus de navigation accessibles,
# éléments <link> (preload, preconnect, alternate…), et traitements sur les liens d'un arbre : extraction,
# réécriture, conversion en URL absolues (web.url).
#
#   use web.html.links as ln
#   ln.a("/contact", "Contact")                       # <a href="/contact">Contact</a>
#   ln.external("https://alex.dev", "Site")           # target="_blank" rel="noopener noreferrer"
#   ln.mailto("contact@exemple.org", null, "Question")    # href="mailto:contact@exemple.org?subject=Question"
#   ln.tel("+33 1 23 45 67 89")                        # href="tel:+33123456789"
#   ln.nav([("Accueil", "/"), ("Blog", "/blog")], "/blog")   # aria-current="page" sur le lien actif
#   ln.hrefs(doc)                                      # toutes les cibles de liens
#   ln.absolutize(doc, "https://exemple.org/a/")       # href / src relatifs -> absolus
#
# Erreurs : HtmlError, erreurs de web.url (absolutize sur une base invalide).

from core use len, type
from collections use append, keys
use string as _s
use web.html.html_errors as _err
use web.html.element as _el
use web.html.element_factory as _f
use web.html.attribute_value as _av
use web.url.url as _url
use web.url.percent_encoding as _pe
use web.url.form_url_encoding as _form

func a(href, content=null, attributes=null):
    return _el.Element("a", _f.merge_attributes({"href": href}, attributes), content if content != null else href)

# Lien vers un autre site, ouvert dans un nouvel onglet, sans exposer la page d'origine (noopener, noreferrer).
func external(href, content=null, attributes=null, new_tab=true):
    base := {"href": href, "rel": "noopener noreferrer"}
    if new_tab:
        base["target"] = "_blank"
    return _el.Element("a", _f.merge_attributes(base, attributes), content if content != null else href)

# Lien courriel ; subject / body encodés.
func mailto(address, content=null, subject=null, body=null, cc=null):
    href := "mailto:" + _pe.encode(address, "@.+")
    params := []
    if subject != null:
        append(params, ("subject", subject))
    if body != null:
        append(params, ("body", body))
    if cc != null:
        append(params, ("cc", cc))
    if len(params) > 0:
        parts := []
        for p in params:
            append(parts, p[0] + "=" + _pe.encode(p[1]))
        href = href + "?" + _s.join("&", parts)
    return _el.Element("a", {"href": href}, content if content != null else address)

# Lien téléphone (espaces, points, tirets et parenthèses retirés de l'URL).
func tel(number, content=null):
    digits := []
    for c in str(number):
        if (c >= '0' and c <= '9') or c == '+':
            append(digits, str(c))
    return _el.Element("a", {"href": "tel:" + _s.join("", digits)}, content if content != null else number)

# Lien de téléchargement ; filename : nom proposé (null : celui de l'URL).
func download(href, content=null, filename=null):
    return _el.Element("a", {"href": href, "download": filename if filename != null else true}, content if content != null else href)

# Lien vers une ancre de la page (#id).
func anchor(id, content):
    return _el.Element("a", {"href": "#" + id}, content)

# Lien d'évitement « aller au contenu » (accessibilité), à placer en premier dans <body>.
func skip_link(target_id="contenu", content="Aller au contenu"):
    return _el.Element("a", {"href": "#" + target_id, "class": "skip-link"}, content)

# Menu de navigation : items = liste de (texte, href) ; current : href de la page courante (aria-current="page").
func nav(items, current=null, label="Navigation principale", attributes=null):
    ul := _el.Element("ul")
    for it in items:
        attrs := {"href": it[1]}
        if current != null and it[1] == current:
            attrs["aria-current"] = "page"
        ul.append(_el.Element("li", null, [_el.Element("a", attrs, it[0])]))
    return _el.Element("nav", _f.merge_attributes({"aria-label": label}, attributes), [ul])

# Pagination : liens précédent / pages / suivant ; url_for(n) rend l'URL de la page n.
func pagination(current, total, url_for, window=2, label="Pagination"):
    ul := _el.Element("ul", {"class": "pagination"})
    if current > 1:
        ul.append(_el.Element("li", null, [_el.Element("a", {"href": url_for(current - 1), "rel": "prev"}, "Précédent")]))
    n := 1
    while n <= total:
        if n == 1 or n == total or (n >= current - window and n <= current + window):
            if n == current:
                ul.append(_el.Element("li", null, [_el.Element("a", {"href": url_for(n), "aria-current": "page"}, str(n))]))
            else:
                ul.append(_el.Element("li", null, [_el.Element("a", {"href": url_for(n)}, str(n))]))
        elif n == current - window - 1 or n == current + window + 1:
            ul.append(_el.Element("li", {"aria-hidden": "true"}, "…"))
        n += 1
    if current < total:
        ul.append(_el.Element("li", null, [_el.Element("a", {"href": url_for(current + 1), "rel": "next"}, "Suivant")]))
    return _el.Element("nav", {"aria-label": label}, [ul])

# ---------------------------------------------------------------- éléments <link>

func link(rel, href, attributes=null):
    return _el.Element("link", _f.merge_attributes({"rel": rel, "href": href}, attributes))

# kind : valeur de « as » (script, style, font, image, fetch...) ; les polices exigent crossorigin.
func preload(href, kind, media_type=null):
    attrs := {"rel": "preload", "href": href, "as": kind, "type": media_type}
    if kind == "font" or kind == "fetch":
        attrs["crossorigin"] = "anonymous"
    return _el.Element("link", attrs)

func prefetch(href):
    return link("prefetch", href)

func preconnect(origin, crossorigin=false):
    return _el.Element("link", {"rel": "preconnect", "href": origin, "crossorigin": "anonymous" if crossorigin else null})

func dns_prefetch(origin):
    return link("dns-prefetch", origin)

func next_page(href):
    return link("next", href)

func prev_page(href):
    return link("prev", href)

# ---------------------------------------------------------------- traitements

# Cibles des liens <a href> d'un arbre (document ou élément), dans l'ordre.
func hrefs(node):
    out := []
    for e in node.find_all("a[href]"):
        append(out, e.get("href"))
    return out

# Liens sous forme de (texte, href).
func extract(node):
    out := []
    for e in node.find_all("a[href]"):
        append(out, (_s.trim(e.text_content()), e.get("href")))
    return out

# Vrai si href pointe vers un autre hôte que host (liens relatifs : internes).
func is_external(href, host):
    if href == null:
        return false
    u := _url.try_parse(href)
    if u == null or u.host == null:
        return false
    return _s.lower(u.hostname()) != _s.lower(host)

# Applique fn(valeur) -> nouvelle valeur à chaque attribut d'URL (href, src, action, poster...) ; null : retiré.
func rewrite(node, fn, attributes=null):
    names := attributes if attributes != null else ["href", "src", "action", "formaction", "poster", "cite", "data"]
    n := 0
    for e in node.find_all("*"):
        for name in names:
            v := e.get(name)
            if v != null:
                nv := fn(v)
                if nv != v:
                    e.set(name, nv)
                    n += 1
    return n

# Rend absolues les URL relatives (base : URL de la page, ou <base href> du document si base est null).
func absolutize(node, base=null):
    b := base
    if b == null and node.node_type == "document":
        b = node.base_url()
    if b == null:
        _err.html_error("links.absolutize", "URL de base requise")
    base_url := _url.parse(b)
    return rewrite(node, (v) => _join(base_url, v))

func _join(base_url, v):
    if _s.starts_with(v, "#") or _s.starts_with(_s.lower(v), "javascript:") or _s.starts_with(_s.lower(v), "data:") or _s.starts_with(_s.lower(v), "mailto:"):
        return v
    try:
        return base_url.join(v).href()
    catch e:
        return v

# Ajoute rel="noopener noreferrer" (et target="_blank" si new_tab) aux liens externes d'un arbre.
func mark_external(node, host, new_tab=false):
    n := 0
    for e in node.find_all("a[href]"):
        if is_external(e.get("href"), host):
            e.attributes.set("rel", _av.join_tokens(_av.split_tokens(e.get("rel", "")) + ["noopener", "noreferrer"]))
            if new_tab:
                e.set("target", "_blank")
            n += 1
    return n
