# ALEX STANDARD LIBRARY — web.html.images
#
# Images : <img> accessibles et performantes par défaut (alt obligatoire, chargement différé, décodage
# asynchrone, dimensions pour éviter les sauts de mise en page), images adaptatives (srcset / sizes, <picture>
# avec formats modernes), figures légendées, URL data:, SVG en ligne, cartes d'images.
#
#   use web.html.images as im
#   im.img("/chat.jpg", "Un chat roux", 800, 600)
#   # <img src="/chat.jpg" alt="Un chat roux" width="800" height="600" loading="lazy" decoding="async">
#   im.responsive("/chat-800.jpg", "Un chat", [("/chat-400.jpg", 400), ("/chat-800.jpg", 800)], "(max-width: 600px) 100vw, 50vw")
#   im.picture("/chat.jpg", "Un chat", [("/chat.avif", "image/avif"), ("/chat.webp", "image/webp")])
#   im.figure("/carte.png", "Carte", "Figure 1 — la région")
#   im.decorative("/ornement.svg")                  # alt="" : ignorée par les lecteurs d'écran
#   im.data_uri([137, 80, 78, 71], "image/png")     # data:image/png;base64,iVBORw==
#
# Erreurs : HtmlError (alt manquant : null n'est pas accepté, utiliser decorative()), TypeError.

from core use len, type
from collections use append
use string as _s
use web.html.html_errors as _err
use web.html.element as _el
use web.html.element_factory as _f
use web.html.raw_html as _raw

func _check_alt(fn, alt):
    if alt == null:
        _err.html_error("images." + fn, "texte alternatif requis (alt) ; pour une image décorative : images.decorative()")

# <img> ; loading : « lazy » (défaut) ou « eager » (image visible dès l'ouverture, LCP) ; fetch_priority : high/low/auto.
func img(src, alt, width=null, height=null, loading="lazy", decoding="async", attributes=null, fetch_priority=null):
    _check_alt("img", alt)
    attrs := {"src": src, "alt": alt, "width": width, "height": height, "loading": loading, "decoding": decoding, "fetchpriority": fetch_priority}
    return _el.Element("img", _f.merge_attributes(attrs, attributes))

# Image purement décorative (alt vide, masquée aux technologies d'assistance).
func decorative(src, width=null, height=null, attributes=null):
    attrs := {"src": src, "alt": "", "width": width, "height": height, "loading": "lazy", "decoding": "async"}
    return _el.Element("img", _f.merge_attributes(attrs, attributes))

# Valeur srcset : liste de (url, largeur int -> « 400w » | densité float -> « 2x » | descripteur str).
func srcset(candidates):
    parts := []
    for c in candidates:
        if type(c) == "str":
            append(parts, c)
            continue
        d := c[1]
        if type(d) == "int":
            append(parts, c[0] + " " + str(d) + "w")
        elif type(d) == "float":
            append(parts, c[0] + " " + _density(d) + "x")
        else:
            append(parts, c[0] + " " + str(d))
    return _s.join(", ", parts)

func _density(d):
    t := str(d)
    if _s.ends_with(t, ".0"):
        return t[0:len(t) - 2]
    return t

# Analyse une valeur srcset -> liste de (url, descripteur str ou null).
func parse_srcset(value):
    out := []
    for part in _s.split(value, ","):
        p := _s.trim(part)
        if p == "":
            continue
        sp := _s.find(p, " ")
        if sp < 0:
            append(out, (p, null))
        else:
            append(out, (p[0:sp], _s.trim(p[sp + 1:len(p)])))
    return out

# Image adaptative : src de repli, candidats (url, largeur) et sizes.
func responsive(src, alt, candidates, sizes="100vw", width=null, height=null, attributes=null):
    _check_alt("responsive", alt)
    e := img(src, alt, width, height, "lazy", "async", attributes)
    e.set("srcset", srcset(candidates))
    e.set("sizes", sizes)
    return e

# <picture> : sources = liste de (srcset, type MIME) ou (srcset, type, media) ; fallback : <img src alt>.
func picture(src, alt, sources, width=null, height=null, attributes=null):
    _check_alt("picture", alt)
    p := _el.Element("picture")
    for s in sources:
        attrs := {"srcset": s[0] if type(s[0]) == "str" else srcset(s[0]), "type": s[1] if len(s) > 1 else null, "media": s[2] if len(s) > 2 else null}
        p.append(_el.Element("source", attrs))
    p.append(img(src, alt, width, height, "lazy", "async", attributes))
    return p

# Image légendée : <figure><img><figcaption>.
func figure(src, alt, caption, width=null, height=null, attributes=null):
    _check_alt("figure", alt)
    return _el.Element("figure", attributes, [img(src, alt, width, height), _el.Element("figcaption", null, caption)])

# SVG en ligne (balisage de confiance) avec titre accessible facultatif (role="img" + aria-label).
func inline_svg(markup, title=null):
    if title == null:
        return _raw.RawHtml(markup)
    return _el.Element("span", {"role": "img", "aria-label": title}, [_raw.RawHtml(markup)])

const _B64 := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

# Base64 d'une str d'octets ou d'une liste d'octets.
func base64(data):
    bytes := data if type(data) == "list" else _s.byte_unpack(str(data))
    out := []
    i := 0
    n := len(bytes)
    while i < n:
        b0 := bytes[i]
        b1 := bytes[i + 1] if i + 1 < n else 0
        b2 := bytes[i + 2] if i + 2 < n else 0
        append(out, str(_B64[b0 >> 2]))
        append(out, str(_B64[((b0 & 3) << 4) | (b1 >> 4)]))
        append(out, str(_B64[((b1 & 15) << 2) | (b2 >> 6)]) if i + 1 < n else "=")
        append(out, str(_B64[b2 & 63]) if i + 2 < n else "=")
        i += 3
    return _s.join("", out)

# URL data: pour de petites images (icônes) embarquées dans la page.
func data_uri(data, media_type="image/png"):
    return "data:" + media_type + ";base64," + base64(data)

# Carte d'images : areas = liste de (forme « rect » / « circle » / « poly », coordonnées, href, alt).
func image_map(name, src, alt, areas):
    _check_alt("image_map", alt)
    m := _el.Element("map", {"name": name})
    for a in areas:
        coords := a[1]
        if type(coords) == "list" or type(coords) == "tuple":
            parts := []
            for c in coords:
                append(parts, str(c))
            coords = _s.join(",", parts)
        _check_alt("image_map (zone)", a[3] if len(a) > 3 else null)
        m.append(_el.Element("area", {"shape": a[0], "coords": coords, "href": a[2], "alt": a[3]}))
    return [_el.Element("img", {"src": src, "alt": alt, "usemap": "#" + name}), m]

# Images d'un arbre : liste de dict src / alt / width / height.
func extract(node):
    out := []
    for e in node.find_all("img"):
        append(out, {"src": e.get("src"), "alt": e.get("alt"), "width": e.get("width"), "height": e.get("height")})
    return out

# Images sans attribut alt d'un arbre.
func missing_alt(node):
    out := []
    for e in node.find_all("img"):
        if e.get("alt") == null:
            append(out, e)
    return out

# Ajoute loading="lazy" et decoding="async" aux images qui n'en ont pas (sauf les skip premières, visibles).
func lazy_load(node, skip=1):
    n := 0
    k := 0
    for e in node.find_all("img"):
        k += 1
        if k <= skip:
            continue
        if e.get("loading") == null:
            e.set("loading", "lazy")
            n += 1
        if e.get("decoding") == null:
            e.set("decoding", "async")
    return n
