# ALEX STANDARD LIBRARY — web.html.attribute_value
#
# Valeurs d'attributs HTML : conversion des valeurs ALEX vers le texte de l'attribut, et règles par attribut.
#
#   | Valeur ALEX              | Rendu                                  |
#   |--------------------------|----------------------------------------|
#   | str, int, float          | name="valeur" (échappée)               |
#   | true                     | name   (attribut booléen présent)      |
#   | false, null              | attribut omis                          |
#   | list / tuple             | jetons séparés par des espaces (class) |
#   | dict pour style          | « clé: valeur; … »                     |
#   | dict pour un autre nom   | JSON (data-config, par exemple)        |
#
#   use web.html.attribute_value as av
#   av.to_text("class", ["btn", "btn-primary"])     # btn btn-primary
#   av.to_text("style", {"color": "red", "margin": 0})   # color: red; margin: 0
#   av.render("disabled", true)                     #  disabled
#   av.render("title", "a \"b\"")                   #  title="a &quot;b&quot;"
#   av.is_valid_name("data-x")                      # true
#   av.is_safe_url("javascript:alert(1)")           # false
#
# Erreurs : HtmlAttributeError (nom invalide), TypeError.

from core use len, type
from collections use append, keys
use string as _s
use json as _json
use web.html.html_errors as _err
use web.html.html_escape as _esc

const BOOLEAN_ATTRIBUTES := ["allowfullscreen", "async", "autofocus", "autoplay", "checked", "controls", "default", "defer", "disabled", "formnovalidate", "hidden", "inert", "ismap", "itemscope", "loop", "multiple", "muted", "nomodule", "novalidate", "open", "playsinline", "readonly", "required", "reversed", "selected", "shadowrootdelegatesfocus", "shadowrootclonable"]

# Attributs dont la valeur est une liste de jetons séparés par des espaces.
const TOKEN_LIST_ATTRIBUTES := ["class", "rel", "sandbox", "accesskey", "headers", "for", "itemprop", "itemref", "itemtype", "ping", "blocking", "sizes", "part", "exportparts"]

# Attributs qui portent une URL (contrôlés par is_safe_url lors de l'assainissement / validation).
const URL_ATTRIBUTES := ["href", "src", "action", "formaction", "poster", "cite", "data", "background", "longdesc", "manifest", "codebase", "ping", "xlink:href", "srcset", "imagesrcset"]

# Schémas autorisés par défaut dans une URL d'attribut.
const SAFE_SCHEMES := ["http", "https", "mailto", "tel", "ftp", "sms", "data-image"]

const _FORBIDDEN_NAME_CHARS := " \t\n\r\"'>/=<`"

func is_boolean(name):
    return _s.lower(name) in BOOLEAN_ATTRIBUTES

func is_token_list(name):
    return _s.lower(name) in TOKEN_LIST_ATTRIBUTES

func is_url_attribute(name):
    return _s.lower(name) in URL_ATTRIBUTES

# Gestionnaire d'événement en ligne (onclick, onload...).
func is_event_handler(name):
    n := _s.lower(name)
    return _s.starts_with(n, "on") and len(n) > 2

# Nom d'attribut valide (WHATWG) : non vide, sans espace, guillemet, « > », « / », « = », « < », contrôle.
func is_valid_name(name):
    if type(name) != "str" or len(name) == 0:
        return false
    for c in name:
        o := _s.ord(c)
        if o < 32 or o == 127 or c in _FORBIDDEN_NAME_CHARS:
            return false
    return true

func check_name(name):
    if not is_valid_name(name):
        _err.attribute_error("attribute_value.check_name", "nom d'attribut invalide '" + str(name) + "'")
    return name

# Nom ALEX -> nom HTML : « data_user_id » reste tel quel ; class_ et for_ (mots réservés) -> class, for ;
# http_equiv -> http-equiv, accept_charset -> accept-charset, aria_* / data_* -> aria-* / data-*.
func html_name(name):
    if name == "class_" or name == "klass" or name == "cls":
        return "class"
    if name == "for_" or name == "html_for":
        return "for"
    if name == "http_equiv":
        return "http-equiv"
    if name == "accept_charset":
        return "accept-charset"
    if _s.starts_with(name, "data_") or _s.starts_with(name, "aria_"):
        return _s.replace(name, "_", "-")
    return name

# Jetons d'une valeur de liste (« a  b c » -> ["a", "b", "c"]).
func split_tokens(value):
    out := []
    if value == null:
        return out
    cur := []
    for c in str(value):
        if c == ' ' or c == '\t' or c == '\n' or c == '\r' or _s.ord(c) == 12:
            if len(cur) > 0:
                append(out, _s.join("", cur))
                cur = []
        else:
            append(cur, str(c))
    if len(cur) > 0:
        append(out, _s.join("", cur))
    return out

func join_tokens(tokens):
    out := []
    for t in tokens:
        if t != null and t != false:
            for x in split_tokens(str(t)):
                if not (x in out):
                    append(out, x)
    return _s.join(" ", out)

# dict CSS -> « a: b; c: d » (noms en snake_case convertis : font_size -> font-size).
func style_text(props):
    out := []
    for k in keys(props):
        v := props[k]
        if v == null or v == false:
            continue
        append(out, _s.replace(str(k), "_", "-") + ": " + str(v))
    return _s.join("; ", out)

# « a: b; c: d » -> dict.
func parse_style(text):
    out := {}
    if text == null:
        return out
    for decl in _s.split(text, ";"):
        c := _s.find(decl, ":")
        if c > 0:
            k := _s.trim(decl[0:c])
            v := _s.trim(decl[c + 1:len(decl)])
            if k != "":
                out[_s.lower(k)] = v
    return out

# Texte de l'attribut pour une valeur ALEX ; null si l'attribut doit être omis ; "" pour un booléen présent.
func to_text(name, value):
    if value == null or value == false:
        return null
    if value == true:
        if is_boolean(name):
            return ""
        return "true"
    t := type(value)
    if t == "str":
        return value
    if t == "int" or t == "float" or t == "char":
        return str(value)
    if t == "list" or t == "tuple":
        if _s.lower(name) == "srcset" or _s.lower(name) == "sizes" or _s.lower(name) == "accept":
            parts := []
            for x in value:
                append(parts, str(x))
            return _s.join(", ", parts)
        return join_tokens(value)
    if t == "dict":
        if _s.lower(name) == "style":
            return style_text(value)
        return _json.stringify(value, null, false)
    return str(value)

# « ␠name="valeur" », « ␠name » (booléen) ou "" (omis).
func render(name, value, quote="\""):
    check_name(name)
    v := to_text(name, value)
    if v == null:
        return ""
    if v == "" and is_boolean(name):
        return " " + name
    return " " + name + "=" + quote + _esc.escape_attribute(v) + quote

# Vrai si l'URL est sûre pour un lien ou une ressource : relative, ou schéma dans schemes. Les espaces et
# contrôles insérés (« java\tscript: ») sont ignorés comme le ferait un navigateur ; « data:image/… » n'est
# accepté que si schemes contient « data-image ».
func is_safe_url(value, schemes=SAFE_SCHEMES):
    if value == null:
        return true
    cleaned := []
    for c in _esc.unescape(str(value), true):
        o := _s.ord(c)
        if o > 32 and o != 127:
            append(cleaned, str(c))
    v := _s.lower(_s.join("", cleaned))
    colon := _s.find(v, ":")
    if colon < 0:
        return true
    for sep in ["/", "?", "#"]:
        k := _s.find(v, sep)
        if k >= 0 and k < colon:
            return true
    scheme := v[0:colon]
    if scheme == "data":
        return "data-image" in schemes and _s.starts_with(v, "data:image/") and not _s.starts_with(v, "data:image/svg")
    return scheme in schemes
