# ALEX STANDARD LIBRARY — crypto.der
#
# Lecture DER (X.690) stricte, pour les clés et les certificats (crypto.x509) : chaque élément est décrit par un
# nœud [étiquette, début du contenu, fin du contenu] dans la liste d'octets d'origine, sans copie.
#
#   use crypto.der as der
#   n := der.read(octets, 0)                  # [tag, début, fin] ; der.next_of(n) = fin
#   der.expect(octets, 0, der.SEQUENCE, "certificat")
#   for c in der.children(octets, n): ...     # éléments d'un type construit
#   der.integer(octets, c) ; der.oid(octets, c) ; der.bit_string(octets, c) ; der.content(octets, c)
#
# Longueurs minimales exigées (DER), forme indéfinie refusée, étiquettes sur un seul octet (suffisant pour X.509 et
# les clés). Erreurs : ValueError (« der : ... »).

from core use len
from collections use append
use string as _s
use crypto.bigint as bn

BOOLEAN := 1
INTEGER := 2
BIT_STRING := 3
OCTET_STRING := 4
NULL := 5
OID := 6
UTF8_STRING := 12
SEQUENCE := 48
SET := 49
PRINTABLE_STRING := 19
IA5_STRING := 22
UTC_TIME := 23
GENERALIZED_TIME := 24

func _fail(message):
    raise("ValueError", "der : " + message)

# Étiquette de contexte [n] (construite ou non).
func context(n, constructed=true):
    return (160 if constructed else 128) + n

# Nœud [tag, début, fin] de l'élément qui commence à l'octet i.
func read(b, i, limit=null):
    lim := limit if limit != null else len(b)
    if i + 2 > lim:
        _fail("élément tronqué")
    tag := b[i]
    if (tag & 31) == 31:
        _fail("étiquette sur plusieurs octets non prise en charge")
    l := b[i + 1]
    j := i + 2
    if l >= 128:
        k := l & 127
        if k == 0:
            _fail("longueur indéfinie (BER) refusée")
        if k > 3:
            _fail("longueur trop grande")
        if j + k > lim:
            _fail("longueur tronquée")
        l = 0
        m := 0
        while m < k:
            l = (l << 8) | b[j + m]
            m += 1
        if b[j] == 0 or l < 128:
            _fail("longueur non minimale")
        j += k
    if j + l > lim:
        _fail("contenu tronqué (" + str(l) + " octets annoncés)")
    return [tag, j, j + l]

func next_of(node):
    return node[2]

# Lit un élément d'étiquette tag à l'octet i (ValueError sinon).
func expect(b, i, tag, what="élément", limit=null):
    n := read(b, i, limit)
    if n[0] != tag:
        _fail(what + " : étiquette " + str(tag) + " attendue, " + str(n[0]) + " trouvée")
    return n

# Éléments contenus dans un nœud construit.
func children(b, node):
    out := []
    i := node[1]
    while i < node[2]:
        c := read(b, i, node[2])
        append(out, c)
        i = c[2]
    return out

# Éléments d'un nœud, en vérifiant l'étiquette du nœud.
func items(b, node, tag, what="élément"):
    if node[0] != tag:
        _fail(what + " : étiquette " + str(tag) + " attendue, " + str(node[0]) + " trouvée")
    return children(b, node)

func content(b, node):
    return b[node[1]:node[2]]

# Encodage complet (en-tête compris) d'un élément qui commence à l'octet start.
func encoded(b, start, node):
    return b[start:node[2]]

# INTEGER positif ou nul, en bigint (crypto.bigint) ; encodage minimal exigé.
func integer(b, node):
    if node[0] != INTEGER:
        _fail("INTEGER attendu")
    n := node[2] - node[1]
    if n == 0:
        _fail("INTEGER vide")
    i := node[1]
    if b[i] >= 128:
        _fail("INTEGER négatif")
    if n > 1 and b[i] == 0 and b[i + 1] < 128:
        _fail("INTEGER non minimal")
    return bn.from_bytes(b[i:node[2]])

# INTEGER court en entier ALEX.
func small_int(b, node):
    return bn.to_int(integer(b, node))

# OBJECT IDENTIFIER en notation pointée (« 1.2.840.10045.2.1 »).
func oid(b, node):
    if node[0] != OID:
        _fail("OBJECT IDENTIFIER attendu")
    if node[2] == node[1]:
        _fail("OID vide")
    parts := []
    v := 0
    i := node[1]
    first := true
    while i < node[2]:
        x := b[i]
        if v == 0 and x == 128:
            _fail("OID non minimal")
        v = (v << 7) | (x & 127)
        if v > 4294967295:
            _fail("OID : composante trop grande")
        if x < 128:
            if first:
                if v < 40:
                    append(parts, "0")
                    append(parts, str(v))
                elif v < 80:
                    append(parts, "1")
                    append(parts, str(v - 40))
                else:
                    append(parts, "2")
                    append(parts, str(v - 80))
                first = false
            else:
                append(parts, str(v))
            v = 0
        i += 1
    if b[node[2] - 1] >= 128:
        _fail("OID tronqué")
    out := parts[0]
    k := 1
    while k < len(parts):
        out = out + "." + parts[k]
        k += 1
    return out

# BIT STRING sans bits inutilisés, en octets.
func bit_string(b, node):
    if node[0] != BIT_STRING:
        _fail("BIT STRING attendue")
    if node[2] == node[1]:
        _fail("BIT STRING vide")
    if b[node[1]] != 0:
        _fail("BIT STRING : bits inutilisés non pris en charge")
    return b[node[1] + 1:node[2]]

func octet_string(b, node):
    if node[0] != OCTET_STRING:
        _fail("OCTET STRING attendue")
    return content(b, node)

# Chaîne de caractères (UTF8String, PrintableString, IA5String, T61String) : texte ALEX.
func text(b, node):
    if not (node[0] == UTF8_STRING or node[0] == PRINTABLE_STRING or node[0] == IA5_STRING or node[0] == 20 or node[0] == 30):
        _fail("chaîne attendue (étiquette " + str(node[0]) + ")")
    if node[0] == 30:
        # BMPString : UTF-16 BE, caractères du plan de base seulement
        out := []
        i := node[1]
        while i + 1 < node[2]:
            c := (b[i] << 8) | b[i + 1]
            append(out, c if c < 128 else 63)
            i += 2
        return _pack(out)
    return _pack(content(b, node))

func _pack(l):
    return _s.byte_pack(l)

# Date UTCTime / GeneralizedTime « AAAAMMJJhhmmssZ » en texte normalisé « AAAA-MM-JJThh:mm:ssZ ».
func time_text(b, node):
    t := _pack(content(b, node))
    if node[0] == UTC_TIME:
        if _s.byte_len(t) != 13:
            _fail("UTCTime invalide")
        century := "19" if _s.byte_slice(t, 0, 1) >= "5" else "20"
        t = century + t
    elif node[0] != GENERALIZED_TIME:
        _fail("date attendue")
    if _s.byte_len(t) != 15 or _s.byte_slice(t, 14, 15) != "Z":
        _fail("date : forme AAAAMMJJhhmmssZ attendue")
    return _s.byte_slice(t, 0, 4) + "-" + _s.byte_slice(t, 4, 6) + "-" + _s.byte_slice(t, 6, 8) + "T" + _s.byte_slice(t, 8, 10) + ":" + _s.byte_slice(t, 10, 12) + ":" + _s.byte_slice(t, 12, 14) + "Z"

# ---------------------------------------------------------------- écriture (petits éléments)

func encode_len(n):
    if n < 128:
        return [n]
    if n < 256:
        return [129, n]
    if n < 65536:
        return [130, n >> 8, n & 255]
    return [131, n >> 16, (n >> 8) & 255, n & 255]

func encode(tag, body):
    return [tag] + encode_len(len(body)) + body
