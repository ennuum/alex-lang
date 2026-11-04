# ALEX STANDARD LIBRARY — web.url.form_url_encoding
#
# Format application/x-www-form-urlencoded (WHATWG URL §5) : celui des formulaires HTML et des chaînes de
# requête. Paires « nom=valeur » séparées par « & », espace encodé « + », tout sauf A-Z a-z 0-9 * - . _ encodé.
#
#   use web.url.form_url_encoding as form
#   form.encode({"q": "chat noir", "page": 2})            # q=chat+noir&page=2
#   form.encode([("tag", "a"), ("tag", "b")])             # tag=a&tag=b
#   form.encode({"tag": ["a", "b"]})                      # tag=a&tag=b
#   form.decode("q=chat+noir&x&y=%C3%A9")                 # [("q", "chat noir"), ("x", ""), ("y", "é")]
#   form.decode_dict("a=1&a=2&b=3")                       # {"a": "2", "b": "3"}   (dernière valeur)
#   form.decode_multi("a=1&a=2&b=3")                      # {"a": ["1", "2"], "b": ["3"]}
#
# Valeurs acceptées par encode : str, int, float, bool (« true » / « false »), null (« »), et listes ou tuples de
# ces valeurs (une paire par élément).
#
# Erreurs : TypeError.

from core use len, type
from collections use append, keys
use string as _s
use web.url.percent_encoding as _pe

# Encode une chaîne selon l'ensemble « application/x-www-form-urlencoded » (espace -> « + »).
func encode_value(text):
    return _pe.encode(value_to_str(text), "*", true)

# Décode une valeur de formulaire (« + » -> espace, « %XX »).
func decode_value(text):
    return _pe.decode(text, true)

# Texte d'une valeur de formulaire.
func value_to_str(v):
    if v == null:
        return ""
    if v == true:
        return "true"
    if v == false:
        return "false"
    t := type(v)
    if t == "str":
        return v
    if t == "int" or t == "float" or t == "char":
        return str(v)
    raise("TypeError", "form_url_encoding : valeur str, nombre, bool ou null attendue (obtenu " + t + ")")

# Paires (nom, valeur) depuis un dict, une liste de paires, ou un objet doté de pairs().
func to_pairs(data):
    out := []
    if data == null:
        return out
    t := type(data)
    if t == "dict":
        for k in keys(data):
            _add_pairs(out, k, data[k])
        return out
    if t == "list" or t == "tuple":
        for p in data:
            if (type(p) != "list" and type(p) != "tuple") or len(p) != 2:
                raise("TypeError", "form_url_encoding : paire (nom, valeur) attendue dans la liste")
            _add_pairs(out, p[0], p[1])
        return out
    if t == "instance":
        return data.pairs()
    raise("TypeError", "form_url_encoding : dict, liste de paires ou QueryParams attendu (obtenu " + t + ")")

func _add_pairs(out, k, v):
    if type(v) == "list" or type(v) == "tuple":
        for x in v:
            append(out, (value_to_str(k), value_to_str(x)))
    else:
        append(out, (value_to_str(k), value_to_str(v)))

# Sérialise des paires / un dict en « a=1&b=x+y ».
func encode(data):
    parts := []
    for p in to_pairs(data):
        append(parts, encode_value(p[0]) + "=" + encode_value(p[1]))
    return _s.join("&", parts)

# Analyse « a=1&b=x+y » en liste de paires (nom, valeur) dans l'ordre ; un « ? » initial est ignoré, les
# morceaux vides (« a=1&&b=2 ») aussi ; « x » sans « = » donne ("x", "").
func decode(text):
    out := []
    if text == null or text == "":
        return out
    t := text
    if t[0] == '?':
        t = t[1:len(t)]
    for piece in _s.split(t, "&"):
        if piece == "":
            continue
        eq := _s.find(piece, "=")
        if eq >= 0:
            append(out, (decode_value(piece[0:eq]), decode_value(piece[eq + 1:len(piece)])))
        else:
            append(out, (decode_value(piece), ""))
    return out

# Dict nom -> dernière valeur.
func decode_dict(text):
    out := {}
    for p in decode(text):
        out[p[0]] = p[1]
    return out

# Dict nom -> liste de toutes les valeurs, dans l'ordre.
func decode_multi(text):
    out := {}
    for p in decode(text):
        if p[0] in out:
            append(out[p[0]], p[1])
        else:
            out[p[0]] = [p[1]]
    return out
