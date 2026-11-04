# ALEX STANDARD LIBRARY — web.url.url_errors
#
# Erreurs du paquet web.url. Toutes sont levées avec raise(type, message) ; le message commence par la fonction
# fautive puis décrit le problème, en citant la valeur reçue.
#
#   UrlError            URL invalide (syntaxe générale, composant manquant)
#   UrlSchemeError      schéma invalide (« 1http », caractère interdit)
#   UrlHostError        hôte invalide (caractère interdit, IPv6 mal formée, étiquette trop longue)
#   UrlPortError        port invalide (non numérique, hors de 0..65535)
#   UrlEncodingError    séquence « %XX » invalide, UTF-8 invalide après décodage
#
#   use web.url.url_errors as ue
#   try:
#       url.parse("http://[::1")
#   catch e:
#       if ue.is_url_error(e.type):
#           print(ue.explain(e.type), e.message)

from core use type

const URL := "UrlError"
const SCHEME := "UrlSchemeError"
const HOST := "UrlHostError"
const PORT := "UrlPortError"
const ENCODING := "UrlEncodingError"

func kinds():
    return [URL, SCHEME, HOST, PORT, ENCODING]

func is_url_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func explain(error_type):
    if error_type == URL:
        return "URL invalide : syntaxe générale incorrecte ou composant obligatoire manquant"
    if error_type == SCHEME:
        return "schéma invalide : une lettre puis lettres, chiffres, « + », « - » ou « . »"
    if error_type == HOST:
        return "hôte invalide : nom de domaine, adresse IPv4 ou adresse IPv6 entre crochets attendus"
    if error_type == PORT:
        return "port invalide : entier décimal entre 0 et 65535"
    if error_type == ENCODING:
        return "encodage pour cent invalide : « % » suivi de deux chiffres hexadécimaux, octets UTF-8 valides"
    return "erreur " + str(error_type)

func url_error(fn, message):
    raise(URL, fn + " : " + message)

func scheme_error(fn, message):
    raise(SCHEME, fn + " : " + message)

func host_error(fn, message):
    raise(HOST, fn + " : " + message)

func port_error(fn, message):
    raise(PORT, fn + " : " + message)

func encoding_error(fn, message):
    raise(ENCODING, fn + " : " + message)

# Vérifie qu'une valeur est une str ; TypeError sinon.
func need_str(fn, label, value):
    if type(value) != "str":
        raise("TypeError", fn + " : " + label + " doit être une str (obtenu " + type(value) + ")")
