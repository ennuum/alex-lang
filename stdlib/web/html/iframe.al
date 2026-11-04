# ALEX STANDARD LIBRARY — web.html.iframe
#
# Contenus embarqués : <iframe> sûrs par défaut (title obligatoire pour l'accessibilité, chargement différé,
# bac à sable « sandbox » strict, permissions « allow » explicites, politique de référent), iframe à contenu en
# ligne (srcdoc échappé), vidéos YouTube (domaine sans cookie) et Vimeo, carte OpenStreetMap, <embed>, <object>.
#
#   use web.html.iframe as fr
#   fr.iframe("https://exemple.org/widget", "Météo locale")
#   # <iframe src="…" title="Météo locale" loading="lazy" sandbox="" referrerpolicy="strict-origin-when-cross-origin"></iframe>
#   fr.iframe(url, "Formulaire", ["allow-forms", "allow-scripts"], ["clipboard-write"])
#   fr.srcdoc("<p>Aperçu <b>isolé</b></p>", "Aperçu")      # contenu échappé dans l'attribut srcdoc
#   fr.youtube("dQw4w9WgXcQ", "Clip")                       # youtube-nocookie.com, allowfullscreen
#   fr.openstreetmap(2.29, 48.85, 2.30, 48.86, "Plan")
#
# sandbox : true (défaut) = toutes les restrictions ; liste de jetons = restrictions levées une à une ;
# false = aucun bac à sable (déconseillé). allow-scripts + allow-same-origin ensemble est refusé (cela annulerait le bac à sable).
# Erreurs : HtmlError (title manquant, jeton sandbox inconnu, combinaison dangereuse).

from core use len, type
from collections use append
use string as _s
use web.html.html_errors as _err
use web.html.element as _el
use web.html.element_factory as _f
use web.html.html_serializer as _ser
use web.url.percent_encoding as _pe

const SANDBOX_TOKENS := ["allow-downloads", "allow-forms", "allow-modals", "allow-orientation-lock", "allow-pointer-lock", "allow-popups", "allow-popups-to-escape-sandbox", "allow-presentation", "allow-same-origin", "allow-scripts", "allow-top-navigation", "allow-top-navigation-by-user-activation", "allow-top-navigation-to-custom-protocols", "allow-storage-access-by-user-activation"]

# Fonctionnalités de la politique de permissions (attribut allow), les plus courantes.
const ALLOW_FEATURES := ["accelerometer", "autoplay", "camera", "clipboard-read", "clipboard-write", "encrypted-media", "fullscreen", "geolocation", "gyroscope", "microphone", "midi", "payment", "picture-in-picture", "publickey-credentials-get", "screen-wake-lock", "web-share", "display-capture", "usb", "serial", "bluetooth", "xr-spatial-tracking"]

# Valeur sandbox validée : true -> "" (tout restreint), false -> null (pas d'attribut), liste -> jetons.
func sandbox_value(tokens):
    if tokens == false:
        return null
    if tokens == true or tokens == null:
        return ""
    out := []
    for t in tokens:
        if not (t in SANDBOX_TOKENS):
            _err.html_error("iframe.sandbox", "jeton sandbox inconnu « " + str(t) + " »")
        if not (t in out):
            append(out, t)
    if "allow-scripts" in out and "allow-same-origin" in out:
        _err.html_error("iframe.sandbox", "allow-scripts + allow-same-origin annule la protection du bac à sable")
    return _s.join(" ", out)

# Valeur allow : liste de fonctionnalités (« camera », « fullscreen ») ou de paires (fonctionnalité, origines).
func allow_value(features):
    if features == null:
        return null
    out := []
    for f in features:
        if type(f) == "str":
            append(out, f)
        else:
            append(out, f[0] + " " + f[1])
    return _s.join("; ", out)

func _check_title(fn, title):
    if title == null or _s.trim(str(title)) == "":
        _err.html_error("iframe." + fn, "title requis (décrit le contenu aux technologies d'assistance)")

func iframe(src, title, sandbox=true, allow=null, width=null, height=null, loading="lazy", referrer_policy="strict-origin-when-cross-origin", attributes=null):
    _check_title("iframe", title)
    attrs := {"src": src, "title": title, "width": width, "height": height, "loading": loading, "sandbox": sandbox_value(sandbox), "allow": allow_value(allow), "referrerpolicy": referrer_policy}
    return _el.Element("iframe", _f.merge_attributes(attrs, attributes))

# Iframe dont le contenu est fourni en HTML (texte, Element ou Document) ; isolé par sandbox (sans scripts par défaut).
func srcdoc(content, title, sandbox=true, attributes=null):
    _check_title("srcdoc", title)
    html := content
    if type(content) != "str":
        html = _ser.serialize(content)
    return _el.Element("iframe", _f.merge_attributes({"srcdoc": html, "title": title, "loading": "lazy", "sandbox": sandbox_value(sandbox)}, attributes))

func _video(src, title, width, height):
    # lecteurs tiers (origine distincte) : pas de bac à sable, permissions explicites (recommandation des éditeurs)
    e := iframe(src, title, false, ["accelerometer", "autoplay", "clipboard-write", "encrypted-media", "gyroscope", "picture-in-picture", "web-share"], width, height)
    e.set("allowfullscreen", true)
    return e

# Vidéo YouTube (domaine youtube-nocookie.com : pas de cookie avant la lecture) ; start : secondes.
func youtube(video_id, title, start=null, width=560, height=315, privacy=true):
    host := "https://www.youtube-nocookie.com" if privacy else "https://www.youtube.com"
    src := host + "/embed/" + _pe.encode(video_id)
    if start != null:
        src = src + "?start=" + str(start)
    return _video(src, title, width, height)

func vimeo(video_id, title, width=640, height=360, dnt=true):
    src := "https://player.vimeo.com/video/" + _pe.encode(str(video_id))
    if dnt:
        src = src + "?dnt=1"
    return _video(src, title, width, height)

# Carte OpenStreetMap d'une zone (longitudes / latitudes des coins) avec marqueur facultatif.
func openstreetmap(min_lon, min_lat, max_lon, max_lat, title, marker=null, width=425, height=350):
    bbox := str(min_lon) + "," + str(min_lat) + "," + str(max_lon) + "," + str(max_lat)
    src := "https://www.openstreetmap.org/export/embed.html?bbox=" + _pe.encode(bbox, ",") + "&layer=mapnik"
    if marker != null:
        src = src + "&marker=" + str(marker[0]) + "," + str(marker[1])
    return iframe(src, title, ["allow-scripts", "allow-popups"], null, width, height)

# <embed> (contenu externe : PDF, plug-ins) ; préférer iframe ou object avec repli.
func embed(src, media_type=null, width=null, height=null, title=null):
    return _el.Element("embed", {"src": src, "type": media_type, "width": width, "height": height, "title": title})

# <object> avec contenu de repli (affiché si la ressource ne peut pas l'être).
func object(data, media_type=null, fallback=null, width=null, height=null, title=null):
    return _el.Element("object", {"data": data, "type": media_type, "width": width, "height": height, "title": title}, fallback)

# PDF embarqué avec lien de repli.
func pdf(src, title, width="100%", height=600):
    return object(src, "application/pdf", [_el.Element("a", {"href": src}, "Télécharger le PDF : " + title)], width, height, title)

# Iframes d'un arbre sans sandbox (à auditer).
func unsandboxed(node):
    out := []
    for e in node.find_all("iframe"):
        if e.get("sandbox") == null:
            append(out, e)
    return out
