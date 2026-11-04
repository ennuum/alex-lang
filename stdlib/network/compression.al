# ALEX STANDARD LIBRARY — network.compression
#
# Codages de contenu HTTP (Content-Encoding / Accept-Encoding, RFC 9110 §8.4) et compression des échanges :
# gzip, deflate (zlib, avec repli sur le DEFLATE brut que certains serveurs envoient), identity. Le moteur
# DEFLATE est celui de office.compression (natif) ; ce module travaille sur des octets bruts (str) comme le reste
# de network.*.
#
#   encode(data, "gzip")              compresse selon un codage
#   decode(data, "gzip, deflate")     décode une liste de codages appliqués dans l'ordre (défait en sens inverse)
#   accept_encoding()                 valeur d'Accept-Encoding pour un client (« gzip, deflate »)
#   choose_encoding(accept)           meilleur codage pris en charge pour un serveur, ou "identity"
#   should_compress(type, taille)     vaut-il la peine de compresser cette réponse ?
#
# Limite : `limit` borne la taille décompressée (bombes de décompression) ; 100 Mio par défaut.
# Erreurs : CompressionError (flux invalide, somme fausse, limite dépassée, codage inconnu).
#
# Exemple
#   use network.compression as nz
#   z := nz.encode("bonjour " * 100, "gzip")
#   print(len(nz.decode(z, "gzip")))      # 800
#   print(nz.choose_encoding("br;q=1, gzip;q=0.8, *;q=0"))   # gzip

from core use len, type
from collections use append
use string as _s
use _native_net as _n
use office.compression as _z
use network.http_headers as _hh

const DEFAULT_LIMIT := 104857600
const SUPPORTED := ["gzip", "deflate", "identity"]
const MIN_SIZE := 256

func _raw(data):
    t := type(data)
    if t == "str":
        return data
    if t == "list" or t == "tuple":
        return _n.from_bytes(data)
    raise("TypeError", "network.compression : str (octets) ou liste d'octets attendue (obtenu '" + t + "')")

func _fail(message):
    raise("CompressionError", "network.compression : " + message)

func _norm(coding):
    c := _s.lower(_s.trim(coding))
    if c == "x-gzip":
        return "gzip"
    return c

# Vrai si le codage est pris en charge (« gzip », « x-gzip », « deflate », « identity »).
func is_supported(coding):
    c := _norm(coding)
    for s in SUPPORTED:
        if s == c:
            return true
    return false

func gzip(data, level=6):
    return _n.from_bytes(_z.gzip_compress(_n.to_bytes(_raw(data)), level))

func gunzip(data, limit=DEFAULT_LIMIT):
    return _n.from_bytes(_z.gzip_decompress(_n.to_bytes(_raw(data)), limit))

# « deflate » au sens HTTP : flux zlib (RFC 1950).
func deflate(data, level=6):
    return _n.from_bytes(_z.zlib_compress(_n.to_bytes(_raw(data)), level))

# Accepte un flux zlib, ou un DEFLATE brut (erreur fréquente des serveurs).
func inflate(data, limit=DEFAULT_LIMIT):
    b := _n.to_bytes(_raw(data))
    if _z.detect(b) == "zlib":
        try:
            return _n.from_bytes(_z.zlib_decompress(b, limit))
        catch e:
            if e.type != "CompressionError":
                raise(e)
    return _n.from_bytes(_z.inflate(b, limit))

func raw_deflate(data, level=6):
    return _n.from_bytes(_z.deflate(_n.to_bytes(_raw(data)), level))

func raw_inflate(data, limit=DEFAULT_LIMIT):
    return _n.from_bytes(_z.inflate(_n.to_bytes(_raw(data)), limit))

# Compresse selon un codage (ou une liste « gzip, deflate », appliquée dans l'ordre).
func encode(data, coding, level=6):
    out := _raw(data)
    for c in _hh.parse_list(coding):
        k := _norm(c)
        if k == "gzip":
            out = gzip(out, level)
        elif k == "deflate":
            out = deflate(out, level)
        elif k == "identity":
            continue
        else:
            _fail("codage non pris en charge « " + c + " »")
    return out

# Décode un corps selon Content-Encoding (codages défaits du dernier au premier). null ou "" : inchangé.
func decode(data, coding, limit=DEFAULT_LIMIT):
    out := _raw(data)
    if coding == null:
        return out
    codings := _hh.parse_list(coding)
    i := len(codings) - 1
    while i >= 0:
        k := _norm(codings[i])
        if k == "gzip":
            out = gunzip(out, limit)
        elif k == "deflate":
            out = inflate(out, limit)
        elif k == "identity" or k == "":
            pass
        else:
            _fail("codage de contenu non pris en charge « " + codings[i] + " »")
        i -= 1
    return out

# Valeur d'Accept-Encoding annoncée par un client.
func accept_encoding():
    return "gzip, deflate"

# Meilleur codage pris en charge pour un en-tête Accept-Encoding (« identity » si rien de mieux n'est accepté,
# null si même identity est refusé : réponse 406 / 415).
func choose_encoding(accept, preferred=null):
    offers := preferred
    if offers == null:
        offers = ["gzip", "deflate"]
    if accept == null:
        return "identity"
    best := null
    bq := 0.0
    for o in offers:
        q := _hh.quality(accept, o)
        if q > bq:
            bq = q
            best = o
    if best != null:
        return best
    # identity est acceptable sauf refus explicite (identity;q=0, ou *;q=0 sans identity)
    explicit := null
    star := null
    for it in _hh.parse_accept(accept):
        if it.value == "identity":
            explicit = it.q
        elif it.value == "*":
            star = it.q
    if explicit != null:
        if explicit > 0:
            return "identity"
        return null
    if star != null and star == 0:
        return null
    return "identity"

const _COMPRESSIBLE := ["text/", "application/json", "application/javascript", "application/xml", "application/xhtml+xml", "application/rss+xml", "application/atom+xml", "application/ld+json", "application/manifest+json", "application/wasm", "image/svg+xml", "application/x-www-form-urlencoded", "application/graphql", "application/grpc-web"]

# Vrai si un contenu de ce type et de cette taille gagne à être compressé (textes, JSON, XML... d'au moins
# min_size octets ; jamais les images, archives ou vidéos déjà compressées).
func should_compress(content_type, size, min_size=MIN_SIZE):
    if size < min_size or content_type == null:
        return false
    ct := _s.lower(content_type)
    for p in _COMPRESSIBLE:
        if _s.starts_with(ct, p):
            return true
    return _s.ends_with(_hh.parse_value(ct)[0], "+json") or _s.ends_with(_hh.parse_value(ct)[0], "+xml")

func crc32(data, crc=0):
    return _z.crc32(_n.to_bytes(_raw(data)), crc)

func adler32(data, value=1):
    return _z.adler32(_n.to_bytes(_raw(data)), value)

# Format d'un flux compressé : "gzip", "zlib" ou "raw".
func detect(data):
    return _z.detect(_n.to_bytes(_raw(data)))
