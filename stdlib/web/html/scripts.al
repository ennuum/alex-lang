# ALEX STANDARD LIBRARY — web.html.scripts
#
# Scripts : <script src> (defer, async, module, intégrité SRI, nonce CSP), scripts en ligne au contenu neutralisé
# (« </script » ne peut pas fermer l'élément), données JSON embarquées sans risque d'injection, cartes d'import,
# <noscript>.
#
#   use web.html.scripts as js
#   js.script("/static/app.js")                         # <script src="/static/app.js" defer></script>
#   js.module("/static/main.mjs")                       # <script type="module" src="…"></script>
#   js.inline("console.log('</script>')")              # contenu neutralisé : <\/script>
#   js.json_data("etat-initial", {"user": "<Zoé>"})     # <script type="application/json" id="etat-initial">{"user":"<Zoé>"}</script>
#   js.importmap({"imports": {"lodash": "/vendor/lodash.js"}})
#   js.noscript("JavaScript est désactivé.")
#
# Par défaut, script() ajoute defer (le HTML est analysé sans attendre le script) ; async_load=true le remplace.
# Erreurs : HtmlError (combinaison invalide), TypeError.

from core use len, type
from collections use append, keys
use string as _s
use json as _json
use web.html.html_errors as _err
use web.html.html_escape as _esc
use web.html.element as _el
use web.html.raw_html as _raw
use web.html.attribute_value as _av

# <script src> ; integrity : empreinte SRI (crossorigin="anonymous" ajouté) ; nonce : jeton CSP.
func script(src, defer=true, async_load=false, module=false, integrity=null, crossorigin=null, nonce=null, attributes=null):
    attrs := {"src": src}
    if module:
        attrs["type"] = "module"
    if async_load:
        attrs["async"] = true
    elif defer and not module:
        attrs["defer"] = true
    if integrity != null:
        attrs["integrity"] = integrity
        if crossorigin == null:
            crossorigin = "anonymous"
    attrs["crossorigin"] = crossorigin
    attrs["nonce"] = nonce
    e := _el.Element("script", attrs)
    if attributes != null:
        e.set_attributes(attributes)
    return e

# Script module ES (différé par nature).
func module(src, integrity=null, nonce=null):
    return script(src, false, false, true, integrity, null, nonce)

# Script de repli pour les navigateurs sans modules.
func nomodule(src):
    return _el.Element("script", {"src": src, "nomodule": true, "defer": true})

# Script en ligne ; code neutralisé au rendu (voir html_escape.escape_script).
func inline(code, nonce=null, module=false):
    attrs := {"nonce": nonce}
    if module:
        attrs["type"] = "module"
    return _el.Element("script", attrs, [str(code)])

# Données JSON pour le script de la page (lecture : JSON.parse(document.getElementById(id).textContent)).
func json_data(id, value):
    text := _esc.escape_json_for_script(_json.stringify(value, null, false))
    return _el.Element("script", {"type": "application/json", "id": id}, [_raw.RawHtml(text)])

# Carte d'import des modules ES : {"imports": {...}, "scopes": {...}}.
func importmap(mapping):
    text := _esc.escape_json_for_script(_json.stringify(mapping, null, false))
    return _el.Element("script", {"type": "importmap"}, [_raw.RawHtml(text)])

# Préchargement d'un module.
func modulepreload(href):
    return _el.Element("link", {"rel": "modulepreload", "href": href})

func noscript(content):
    return _el.Element("noscript", null, content)

# Valeur JS sûre à insérer dans un script en ligne (JSON neutralisé) : inline("const cfg = " + js.literal(cfg) + ";").
func literal(value):
    return _esc.escape_json_for_script(_json.stringify(value, null, false))

# src des scripts externes d'un document ou d'un arbre.
func sources(node):
    out := []
    for s in node.find_all("script[src]"):
        append(out, s.get("src"))
    return out

# Scripts en ligne (texte) d'un arbre — utile pour calculer des empreintes CSP.
func inline_sources(node):
    out := []
    for s in node.find_all("script"):
        if not s.has("src"):
            append(out, s.text_content())
    return out

# Retire les scripts et les gestionnaires d'événements en ligne d'un arbre (modifié sur place) ; rend le nombre
# d'éléments ou d'attributs retirés.
func strip_scripts(node):
    n := 0
    for s in node.find_all("script"):
        s.remove()
        n += 1
    for e in node.find_all("*"):
        for name in e.attributes.names():
            if _av.is_event_handler(name):
                e.attributes.remove(name)
                n += 1
            elif _av.is_url_attribute(name) and not _av.is_safe_url(e.get(name)):
                e.attributes.remove(name)
                n += 1
    return n
