# ALEX STANDARD LIBRARY — web.url.query
#
# Chaîne de requête d'une URL (RFC 3986 §3.4) : la partie après « ? » et avant « # », gardée sous forme ENCODÉE.
# Ce module passe de la forme brute aux paramètres (web.url.query_params) et inversement, et normalise.
#
#   use web.url.query as q
#   q.encode("a=1&b=x y")                # a=1&b=x%20y   (caractères interdits encodés, structure gardée)
#   q.params("a=1&b=x+y").get("b")       # x y
#   q.build({"q": "chat noir", "p": 2})  # q=chat+noir&p=2
#   q.merge("a=1&b=2", {"b": 3, "c": 4}) # a=1&b=3&c=4
#   q.without("a=1&utm_source=x", ["utm_source"])   # a=1
#   q.sorted("b=2&a=1")                  # a=1&b=2
#
# Une requête absente (null) diffère d'une requête vide ("") : « http://h/? » garde son « ? ».

from core use len, type
from collections use append, keys
use string as _s
use web.url.percent_encoding as _pe
use web.url.form_url_encoding as _form
use web.url.query_params as _qp

# Encode les caractères interdits d'une requête brute (espace, « " », « # », « < », « > », non ASCII) en gardant
# « & », « = » et les « %XX » existants. special : schéma spécial (« ' » aussi encodé, comme un navigateur).
func encode(text, special=true):
    if text == null:
        return null
    return _pe.encode_query(text, special)

# Paramètres décodés (QueryParams) d'une requête brute ; null ou "" donnent des paramètres vides.
func params(text):
    if text == null:
        return _qp.QueryParams()
    return _qp.parse(text)

# Requête encodée depuis un dict, une liste de paires ou un QueryParams ; null si data est null.
func build(data):
    if data == null:
        return null
    if isinstance(data, _qp.QueryParams):
        return data.to_string()
    return _form.encode(data)

# Remplace (set) ou ajoute des paramètres : un dict remplace les noms donnés ; une valeur null supprime le nom.
func merge(text, updates):
    p := params(text)
    if type(updates) == "dict":
        for k in keys(updates):
            v := updates[k]
            if v == null:
                p.remove(k)
            else:
                p.set(k, v)
    else:
        p.update(updates)
    return p.to_string()

# Requête sans les noms donnés.
func without(text, names):
    p := params(text)
    for n in names:
        p.remove(n)
    return p.to_string()

# Requête triée par nom (forme canonique pour comparer ou mettre en cache).
func sorted(text):
    return params(text).sort().to_string()

# Normalisation : encodage « %XX » normalisé (hexadécimal majuscule, non réservés décodés).
func normalize(text):
    if text == null:
        return null
    return _pe.normalize(encode(text))

# « ?a=1 », ou "" si la requête est absente.
func serialize(text):
    if text == null:
        return ""
    return "?" + text

# Sépare « chemin?requête » : (chemin, requête ou null).
func split(target):
    i := _s.find(target, "?")
    if i < 0:
        return (target, null)
    return (target[0:i], target[i + 1:len(target)])

func is_empty(text):
    return text == null or text == ""
