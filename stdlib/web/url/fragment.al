# ALEX STANDARD LIBRARY — web.url.fragment
#
# Fragment d'URL (RFC 3986 §3.5) : la partie après « # ». Jamais envoyé au serveur ; il désigne une ancre de la
# page (identifiant d'élément HTML), un état d'application monopage, ou une directive de texte (« :~:text= »).
#
#   use web.url.fragment as fr
#   fr.encode("section 2")            # section%202
#   fr.decode("caf%C3%A9")            # café
#   fr.serialize("top")               # #top
#   fr.to_element_id("Résumé 2024")   # résumé-2024    (identifiant utilisable comme ancre)
#   fr.text_directive("phrase exacte")   # :~:text=phrase%20exacte
#
# Un fragment absent (null) diffère d'un fragment vide ("") : « http://h/# » garde son « # ».

from core use len
from collections use append
use string as _s
use web.url.percent_encoding as _pe

# Encode les caractères interdits (espace, « " », « < », « > », « ` », non ASCII) en gardant les « %XX ».
func encode(text):
    if text == null:
        return null
    return _pe.encode_fragment(text)

func decode(text):
    if text == null:
        return null
    return _pe.decode(text)

func normalize(text):
    if text == null:
        return null
    return _pe.normalize(encode(text))

# « #fragment », ou "" s'il est absent.
func serialize(text):
    if text == null:
        return ""
    return "#" + text

# Sépare « adresse#fragment » : (adresse, fragment ou null).
func split(text):
    i := _s.find(text, "#")
    if i < 0:
        return (text, null)
    return (text[0:i], text[i + 1:len(text)])

# Identifiant d'ancre depuis un titre : minuscules, espaces et ponctuation -> « - », tirets fusionnés.
func to_element_id(title):
    out := []
    dash := false
    for c in _s.lower(_s.trim(title)):
        o := _s.ord(c)
        keep := (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_' or o >= 128
        if keep:
            append(out, str(c))
            dash = false
        elif not dash and len(out) > 0:
            append(out, "-")
            dash = true
    while len(out) > 0 and out[len(out) - 1] == "-":
        out = out[0:len(out) - 1]
    return _s.join("", out)

# Directive de fragment de texte (« Scroll To Text Fragment ») : #:~:text=début[,fin].
func text_directive(start, end=null):
    out := ":~:text=" + _pe.encode(start)
    if end != null:
        out = out + "," + _pe.encode(end)
    return out
