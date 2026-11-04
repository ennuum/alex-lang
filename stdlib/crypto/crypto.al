# ALEX STANDARD LIBRARY — crypto
# Primitives cryptographiques en ALEX pur (aucune primitive C++ dédiée). Vérifiées contre hashlib / hmac /
# RFC 8439 dans tests/test_crypto.al.
#
#   use crypto
#   crypto.sha256("abc")                         # "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
#   crypto.hmac("sha256", "clé", "message")      # hex
#   crypto.pbkdf2("mot de passe", "sel", 10000, 32)   # hex de 64 caractères
#   crypto.base64_encode(crypto.utf8_encode("é"))  # "w6k="
#   crypto.chacha20(key, nonce, data)            # chiffre ET déchiffre (liste d'octets)
#
# DONNÉES : toute fonction qui prend `data` accepte une str (encodée en UTF-8) ou une liste / un tuple d'octets
#   (entiers 0..255). Les « octets » sont toujours des listes d'int ; il n'y a pas de type bytes dédié.
# HACHAGES : md5 sha1 sha256 sha512 -> hexadécimal minuscule ; md5_bytes ... -> liste d'octets ;
#   hash_bytes(algo, data) / hash_hex(algo, data) avec algo = "md5" | "sha1" | "sha256" | "sha512".
#   MD5 et SHA-1 sont CASSÉS pour la sécurité (collisions) : à réserver à la compatibilité / aux sommes de contrôle.
#   Md5() : MD5 incrémental (update / digest / hexdigest), en mémoire constante, pour les gros fichiers et les flux.
# MAC / DÉRIVATION : hmac / hmac_bytes(algo, key, data) ; pbkdf2 / pbkdf2_bytes(password, salt, iterations, length,
#   algo="sha256") (PBKDF2-HMAC, RFC 8018). Comparer des MAC / empreintes avec equals() (temps constant).
# CHIFFREMENT : chacha20(key, nonce, data, counter=1) — ChaCha20 de la RFC 8439 (clé 32 octets, nonce 12 octets).
#   C'est un chiffrement de flux SANS authentification : à combiner avec hmac (chiffrer puis authentifier).
# ENCODAGES : utf8_encode / utf8_decode, hex_encode / hex_decode, base64_encode / base64_decode (url=true : alphabet
#   « URL-safe », sans remplissage à l'encodage).
#
# LIMITES — À LIRE
#   - ALEX n'expose PAS de source d'entropie du système : ce module ne peut pas générer de clés, sels ou nonces sûrs.
#     Fournissez-les vous-même (le module random n'est pas cryptographique). Ne réutilisez jamais un couple
#     (clé, nonce) avec ChaCha20.
#   - Implémentation interprétée : lente (mesuré : 25 à 45 Ko/s selon l'algorithme ; pbkdf2-sha256 ≈ 1 s pour 1000
#     itérations, donc ≈ 2 min pour 100 000). Pas de garantie de résistance aux attaques par canaux auxiliaires, sauf pour equals().
#   - Les messages de plus de 2^61 octets ne sont pas supportés (limite de la longueur sur 64 bits).
# Erreurs : TypeError (type d'argument), ValueError (valeur invalide : octet hors 0..255, hex/base64/UTF-8 mal formé,
#   taille de clé ou de nonce, algorithme inconnu, paramètres hors limites).

from core use len, type
from collections use append, contains_key
use string

const _K256 := [1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221, 3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580, 3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986, 2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895, 666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037, 2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344, 430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779, 1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298]
const _H256 := [1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225]
const _K512 := [4794697086780616226, 8158064640168781261, -5349999486874862801, -1606136188198331460, 4131703408338449720, 6480981068601479193, -7908458776815382629, -6116909921290321640, -2880145864133508542, 1334009975649890238, 2608012711638119052, 6128411473006802146, 8268148722764581231, -9160688886553864527, -7215885187991268811, -4495734319001033068, -1973867731355612462, -1171420211273849373, 1135362057144423861, 2597628984639134821, 3308224258029322869, 5365058923640841347, 6679025012923562964, 8573033837759648693, -7476448914759557205, -6327057829258317296, -5763719355590565569, -4658551843659510044, -4116276920077217854, -3051310485924567259, 489312712824947311, 1452737877330783856, 2861767655752347644, 3322285676063803686, 5560940570517711597, 5996557281743188959, 7280758554555802590, 8532644243296465576, -9096487096722542874, -7894198246740708037, -6719396339535248540, -6333637450476146687, -4446306890439682159, -4076793802049405392, -3345356375505022440, -2983346525034927856, -860691631967231958, 1182934255886127544, 1847814050463011016, 2177327727835720531, 2830643537854262169, 3796741975233480872, 4115178125766777443, 5681478168544905931, 6601373596472566643, 7507060721942968483, 8399075790359081724, 8693463985226723168, -8878714635349349518, -8302665154208450068, -8016688836872298968, -6606660893046293015, -4685533653050689259, -4147400797238176981, -3880063495543823972, -3348786107499101689, -1523767162380948706, -757361751448694408, 500013540394364858, 748580250866718886, 1242879168328830382, 1977374033974150939, 2944078676154940804, 3659926193048069267, 4368137639120453308, 4836135668995329356, 5532061633213252278, 6448918945643986474, 6902733635092675308, 7801388544844847127]
const _H512 := [7640891576956012808, -4942790177534073029, 4354685564936845355, -6534734903238641935, 5840696475078001361, -7276294671716946913, 2270897969802886507, 6620516959819538809]
const _MD5K := [3614090360, 3905402710, 606105819, 3250441966, 4118548399, 1200080426, 2821735955, 4249261313, 1770035416, 2336552879, 4294925233, 2304563134, 1804603682, 4254626195, 2792965006, 1236535329, 4129170786, 3225465664, 643717713, 3921069994, 3593408605, 38016083, 3634488961, 3889429448, 568446438, 3275163606, 4107603335, 1163531501, 2850285829, 4243563512, 1735328473, 2368359562, 4294588738, 2272392833, 1839030562, 4259657740, 2763975236, 1272893353, 4139469664, 3200236656, 681279174, 3936430074, 3572445317, 76029189, 3654602809, 3873151461, 530742520, 3299628645, 4096336452, 1126891415, 2878612391, 4237533241, 1700485571, 2399980690, 4293915773, 2240044497, 1873313359, 4264355552, 2734768916, 1309151649, 4149444226, 3174756917, 718787259, 3951481745]
const _M32 := 4294967295
const _SHA1_H := [1732584193, 4023233417, 2562383102, 271733878, 3285377520]
const _SHA1_K := [1518500249, 1859775393, 2400959708, 3395469782]
const _HEX := "0123456789abcdef"
const _B64 := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
const _B64URL := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

func _fail(message):
    raise("ValueError", "crypto : " + message)

# --- encodages ---------------------------------------------------------------------------------------------

# str -> liste d'octets UTF-8.
func utf8_encode(s):
    if type(s) != "str":
        raise("TypeError", "crypto.utf8_encode : str attendue (obtenu '" + type(s) + "')")
    out := []
    for c in s:
        o := string.ord(c)
        if o < 128:
            append(out, o)
        elif o < 2048:
            append(out, 192 | (o >> 6))
            append(out, 128 | (o & 63))
        elif o < 65536:
            append(out, 224 | (o >> 12))
            append(out, 128 | ((o >> 6) & 63))
            append(out, 128 | (o & 63))
        else:
            append(out, 240 | (o >> 18))
            append(out, 128 | ((o >> 12) & 63))
            append(out, 128 | ((o >> 6) & 63))
            append(out, 128 | (o & 63))
    return out

func _check_bytes(data, fn):
    if type(data) != "list" and type(data) != "tuple":
        raise("TypeError", "crypto." + fn + " : liste d'octets attendue (obtenu '" + type(data) + "')")
    for b in data:
        if type(b) != "int" or b < 0 or b > 255:
            _fail(fn + " : octet invalide " + str(b) + " (entier 0..255 attendu)")

# Liste d'octets UTF-8 -> str. ValueError si la séquence est invalide (tronquée, surlongue, substitut...).
func utf8_decode(data):
    _check_bytes(data, "utf8_decode")
    out := []
    n := len(data)
    i := 0
    while i < n:
        b := data[i]
        need := 0
        cp := 0
        lo := 0
        if b < 128:
            append(out, str(string.chr(b)))
            i = i + 1
            continue
        elif b >= 194 and b <= 223:
            need = 1
            cp = b & 31
            lo = 128
        elif b >= 224 and b <= 239:
            need = 2
            cp = b & 15
            lo = 2048
        elif b >= 240 and b <= 244:
            need = 3
            cp = b & 7
            lo = 65536
        else:
            _fail("utf8_decode : octet de début invalide à l'indice " + str(i))
        if i + need >= n:
            _fail("utf8_decode : séquence tronquée à l'indice " + str(i))
        k := 1
        while k <= need:
            c := data[i + k]
            if (c & 192) != 128:
                _fail("utf8_decode : octet de continuation invalide à l'indice " + str(i + k))
            cp = (cp << 6) | (c & 63)
            k = k + 1
        if cp < lo or cp > 1114111 or (cp >= 55296 and cp <= 57343):
            _fail("utf8_decode : point de code invalide à l'indice " + str(i))
        append(out, str(string.chr(cp)))
        i = i + need + 1
    return string.join("", out)

# Accepte str (UTF-8) ou liste d'octets ; renvoie une NOUVELLE liste d'octets.
func _bytes(data, fn):
    if type(data) == "str":
        return utf8_encode(data)
    _check_bytes(data, fn)
    out := []
    for b in data:
        append(out, b)
    return out

func hex_encode(data):
    _check_bytes(data, "hex_encode")
    out := []
    for b in data:
        append(out, string.substring(_HEX, b >> 4, (b >> 4) + 1))
        append(out, string.substring(_HEX, b & 15, (b & 15) + 1))
    return string.join("", out)

func _hex_val(ch):
    o := string.ord(ch)
    if o >= 48 and o <= 57:
        return o - 48
    if o >= 97 and o <= 102:
        return o - 87
    if o >= 65 and o <= 70:
        return o - 55
    return -1

# Hexadécimal (majuscules / minuscules acceptées) -> liste d'octets.
func hex_decode(text):
    if type(text) != "str":
        raise("TypeError", "crypto.hex_decode : str attendue")
    if len(text) % 2 != 0:
        _fail("hex_decode : longueur impaire")
    out := []
    i := 0
    n := len(text)
    while i < n:
        h := _hex_val(text[i])
        l := _hex_val(text[i + 1])
        if h < 0 or l < 0:
            _fail("hex_decode : caractère non hexadécimal près de l'indice " + str(i))
        append(out, h * 16 + l)
        i = i + 2
    return out

# Liste d'octets -> base64 (alphabet standard avec « = », ou URL-safe sans remplissage si url=true).
func base64_encode(data, url=false):
    _check_bytes(data, "base64_encode")
    alpha := _B64
    if url:
        alpha = _B64URL
    out := []
    n := len(data)
    i := 0
    while i < n:
        b0 := data[i]
        b1 := 0
        b2 := 0
        have := 1
        if i + 1 < n:
            b1 = data[i + 1]
            have = 2
        if i + 2 < n:
            b2 = data[i + 2]
            have = 3
        v := (b0 << 16) | (b1 << 8) | b2
        append(out, string.substring(alpha, (v >> 18) & 63, ((v >> 18) & 63) + 1))
        append(out, string.substring(alpha, (v >> 12) & 63, ((v >> 12) & 63) + 1))
        if have >= 2:
            append(out, string.substring(alpha, (v >> 6) & 63, ((v >> 6) & 63) + 1))
        elif not url:
            append(out, "=")
        if have >= 3:
            append(out, string.substring(alpha, v & 63, (v & 63) + 1))
        elif not url:
            append(out, "=")
        i = i + 3
    return string.join("", out)

# base64 -> liste d'octets. Espaces et fins de ligne ignorés ; le remplissage « = » est facultatif ;
# url=true utilise l'alphabet URL-safe. Tout autre caractère, ou un reste d'un seul symbole, lève ValueError.
func base64_decode(text, url=false):
    if type(text) != "str":
        raise("TypeError", "crypto.base64_decode : str attendue")
    alpha := _B64
    if url:
        alpha = _B64URL
    vals := []
    pad := 0
    for c in text:
        ch := str(c)
        if ch == " " or ch == "\n" or ch == "\r" or ch == "\t":
            continue
        if ch == "=":
            pad = pad + 1
            continue
        if pad > 0:
            _fail("base64_decode : caractère après le remplissage")
        idx := string.find(alpha, ch)
        if idx < 0 or len(ch) != 1:
            _fail("base64_decode : caractère invalide '" + ch + "'")
        append(vals, idx)
    if pad > 2:
        _fail("base64_decode : remplissage excessif")
    if len(vals) % 4 == 1:
        _fail("base64_decode : longueur invalide")
    if pad > 0 and (len(vals) + pad) % 4 != 0:
        _fail("base64_decode : remplissage incorrect")
    out := []
    i := 0
    n := len(vals)
    while i < n:
        v0 := vals[i]
        v1 := vals[i + 1]
        v2 := 0
        v3 := 0
        have := 2
        if i + 2 < n:
            v2 = vals[i + 2]
            have = 3
        if i + 3 < n:
            v3 = vals[i + 3]
            have = 4
        w := (v0 << 18) | (v1 << 12) | (v2 << 6) | v3
        append(out, (w >> 16) & 255)
        if have >= 3:
            append(out, (w >> 8) & 255)
        if have >= 4:
            append(out, w & 255)
        i = i + 4
    return out

# --- utilitaires de mots ------------------------------------------------------------------------------------

func _rotr32(x, n):
    return ((x >> n) | (x << (32 - n))) & _M32

func _rotl32(x, n):
    return ((x << n) | (x >> (32 - n))) & _M32

# Complète `msg` (liste d'octets, modifiée) : 0x80, zéros, longueur en bits sur 8 octets (grand-boutiste ou petit).
func _pad(msg, block, big_endian, lenbytes):
    bitlen := len(msg) * 8
    append(msg, 128)
    while len(msg) % block != block - lenbytes:
        append(msg, 0)
    k := 0
    if lenbytes == 16:
        while k < 8:
            append(msg, 0)
            k = k + 1
    sh := 0
    if big_endian:
        sh = 56
        while sh >= 0:
            append(msg, (bitlen >> sh) & 255)
            sh = sh - 8
    else:
        while sh < 64:
            append(msg, (bitlen >> sh) & 255)
            sh = sh + 8

func _words_be32(out, h):
    for w in h:
        append(out, (w >> 24) & 255)
        append(out, (w >> 16) & 255)
        append(out, (w >> 8) & 255)
        append(out, w & 255)

# --- SHA-256 ------------------------------------------------------------------------------------------------

func _sha256(data):
    msg := _bytes(data, "sha256")
    _pad(msg, 64, true, 8)
    h := []
    for v in _H256:
        append(h, v)
    w := []
    t := 0
    while t < 64:
        append(w, 0)
        t = t + 1
    off := 0
    while off < len(msg):
        i := 0
        while i < 16:
            p := off + i * 4
            w[i] = (msg[p] << 24) | (msg[p + 1] << 16) | (msg[p + 2] << 8) | msg[p + 3]
            i = i + 1
        while i < 64:
            w15 := w[i - 15]
            w2 := w[i - 2]
            s0 := _rotr32(w15, 7) ^ _rotr32(w15, 18) ^ (w15 >> 3)
            s1 := _rotr32(w2, 17) ^ _rotr32(w2, 19) ^ (w2 >> 10)
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & _M32
            i = i + 1
        a := h[0]
        b := h[1]
        c := h[2]
        d := h[3]
        e := h[4]
        f := h[5]
        g := h[6]
        hh := h[7]
        i = 0
        while i < 64:
            S1 := _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25)
            ch := (e & f) ^ ((e ^ _M32) & g)
            t1 := (hh + S1 + ch + _K256[i] + w[i]) & _M32
            S0 := _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22)
            maj := (a & b) ^ (a & c) ^ (b & c)
            t2 := (S0 + maj) & _M32
            hh = g
            g = f
            f = e
            e = (d + t1) & _M32
            d = c
            c = b
            b = a
            a = (t1 + t2) & _M32
            i = i + 1
        h[0] = (h[0] + a) & _M32
        h[1] = (h[1] + b) & _M32
        h[2] = (h[2] + c) & _M32
        h[3] = (h[3] + d) & _M32
        h[4] = (h[4] + e) & _M32
        h[5] = (h[5] + f) & _M32
        h[6] = (h[6] + g) & _M32
        h[7] = (h[7] + hh) & _M32
        off = off + 64
    out := []
    _words_be32(out, h)
    return out

# --- SHA-1 --------------------------------------------------------------------------------------------------

func _sha1(data):
    msg := _bytes(data, "sha1")
    _pad(msg, 64, true, 8)
    h := []
    for v in _SHA1_H:
        append(h, v)
    w := []
    t := 0
    while t < 80:
        append(w, 0)
        t = t + 1
    off := 0
    while off < len(msg):
        i := 0
        while i < 16:
            p := off + i * 4
            w[i] = (msg[p] << 24) | (msg[p + 1] << 16) | (msg[p + 2] << 8) | msg[p + 3]
            i = i + 1
        while i < 80:
            w[i] = _rotl32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
            i = i + 1
        a := h[0]
        b := h[1]
        c := h[2]
        d := h[3]
        e := h[4]
        i = 0
        while i < 80:
            f := 0
            k := 0
            if i < 20:
                f = (b & c) | ((b ^ _M32) & d)
                k = _SHA1_K[0]
            elif i < 40:
                f = b ^ c ^ d
                k = _SHA1_K[1]
            elif i < 60:
                f = (b & c) | (b & d) | (c & d)
                k = _SHA1_K[2]
            else:
                f = b ^ c ^ d
                k = _SHA1_K[3]
            tmp := (_rotl32(a, 5) + f + e + k + w[i]) & _M32
            e = d
            d = c
            c = _rotl32(b, 30)
            b = a
            a = tmp
            i = i + 1
        h[0] = (h[0] + a) & _M32
        h[1] = (h[1] + b) & _M32
        h[2] = (h[2] + c) & _M32
        h[3] = (h[3] + d) & _M32
        h[4] = (h[4] + e) & _M32
        off = off + 64
    out := []
    _words_be32(out, h)
    return out

# --- MD5 ----------------------------------------------------------------------------------------------------

# Index du mot du bloc utilisé à chaque étape (g de la RFC 1321), et décalage de chaque étape.
const _MD5G := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 1, 6, 11, 0, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12, 5, 8, 11, 14, 1, 4, 7, 10, 13, 0, 3, 6, 9, 12, 15, 2, 0, 7, 14, 5, 12, 3, 10, 1, 8, 15, 6, 13, 4, 11, 2, 9]
const _MD5R := [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21]

# Un bloc de 64 octets de msg à partir de off ; h (4 mots) mis à jour. Quatre boucles (une par fonction de
# tour) sans branchement ni appel par étape : c'est la boucle chaude des sommes MD5 de fichiers.
func _md5_block(h, msg, off):
    m := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    p := off
    for i in 0..16:
        m[i] = msg[p] | (msg[p + 1] << 8) | (msg[p + 2] << 16) | (msg[p + 3] << 24)
        p += 4
    a := h[0]
    b := h[1]
    c := h[2]
    d := h[3]
    M := _M32
    for i in 0..16:
        f := ((b & c) | ((b ^ M) & d)) + a + _MD5K[i] + m[i]
        s := _MD5R[i]
        f = f & M
        a = d
        d = c
        c = b
        b = (b + (((f << s) | (f >> (32 - s))) & M)) & M
    for i in 16..32:
        f := ((d & b) | ((d ^ M) & c)) + a + _MD5K[i] + m[_MD5G[i]]
        s := _MD5R[i]
        f = f & M
        a = d
        d = c
        c = b
        b = (b + (((f << s) | (f >> (32 - s))) & M)) & M
    for i in 32..48:
        f := (b ^ c ^ d) + a + _MD5K[i] + m[_MD5G[i]]
        s := _MD5R[i]
        f = f & M
        a = d
        d = c
        c = b
        b = (b + (((f << s) | (f >> (32 - s))) & M)) & M
    for i in 48..64:
        f := (c ^ (b | (d ^ M))) + a + _MD5K[i] + m[_MD5G[i]]
        s := _MD5R[i]
        f = f & M
        a = d
        d = c
        c = b
        b = (b + (((f << s) | (f >> (32 - s))) & M)) & M
    h[0] = (h[0] + a) & M
    h[1] = (h[1] + b) & M
    h[2] = (h[2] + c) & M
    h[3] = (h[3] + d) & M

# MD5 incrémental : update(data) autant de fois que voulu (str ou octets), puis digest() (octets) ou hexdigest().
# Mémoire constante : seuls les octets d'un bloc incomplet sont gardés (sommes de gros fichiers, flux).
#   h := crypto.Md5()
#   h.update(morceau1)
#   h.update(morceau2)
#   print(h.hexdigest())
class Md5:
    func init():
        self.h = [1732584193, 4023233417, 2562383102, 271733878]
        self.pending = []
        self.total = 0

    func update(data):
        b := _bytes(data, "md5")
        self.total += len(b)
        buf := b
        if len(self.pending) > 0:
            buf = self.pending + b
        n := len(buf)
        off := 0
        h := self.h
        while off + 64 <= n:
            _md5_block(h, buf, off)
            off += 64
        self.pending = buf[off:]
        return self

    func digest():
        msg := self.pending[:]
        bitlen := self.total * 8
        append(msg, 128)
        while len(msg) % 64 != 56:
            append(msg, 0)
        for k in 0..8:
            append(msg, (bitlen >> (8 * k)) & 255)
        h := self.h[:]
        off := 0
        while off < len(msg):
            _md5_block(h, msg, off)
            off += 64
        out := []
        for v in h:
            append(out, v & 255)
            append(out, (v >> 8) & 255)
            append(out, (v >> 16) & 255)
            append(out, (v >> 24) & 255)
        return out

    func hexdigest():
        return hex_encode(self.digest())

func _md5(data):
    return Md5().update(data).digest()

# --- SHA-512 (entiers 64 bits signés avec débordement cyclique ; décalages logiques simulés par masque) --------

func _make_masks():
    masks := [0]
    k := 1
    while k <= 64:
        append(masks, masks[k - 1] * 2 + 1)
        k = k + 1
    return masks

const _MASKS := _make_masks()

# Décalage à droite logique et rotation sur 64 bits.
func _shr64(x, n):
    return (x >> n) & _MASKS[64 - n]

func _rotr64(x, n):
    return ((x >> n) & _MASKS[64 - n]) | (x << (64 - n))

func _sha512(data):
    msg := _bytes(data, "sha512")
    _pad(msg, 128, true, 16)
    h := []
    for v in _H512:
        append(h, v)
    w := []
    t := 0
    while t < 80:
        append(w, 0)
        t = t + 1
    off := 0
    while off < len(msg):
        i := 0
        while i < 16:
            p := off + i * 8
            v := 0
            j := 0
            while j < 8:
                v = (v << 8) | msg[p + j]
                j = j + 1
            w[i] = v
            i = i + 1
        while i < 80:
            w15 := w[i - 15]
            w2 := w[i - 2]
            s0 := _rotr64(w15, 1) ^ _rotr64(w15, 8) ^ _shr64(w15, 7)
            s1 := _rotr64(w2, 19) ^ _rotr64(w2, 61) ^ _shr64(w2, 6)
            w[i] = w[i - 16] + s0 + w[i - 7] + s1
            i = i + 1
        a := h[0]
        b := h[1]
        c := h[2]
        d := h[3]
        e := h[4]
        f := h[5]
        g := h[6]
        hh := h[7]
        i = 0
        while i < 80:
            S1 := _rotr64(e, 14) ^ _rotr64(e, 18) ^ _rotr64(e, 41)
            ch := (e & f) ^ (~e & g)
            t1 := hh + S1 + ch + _K512[i] + w[i]
            S0 := _rotr64(a, 28) ^ _rotr64(a, 34) ^ _rotr64(a, 39)
            maj := (a & b) ^ (a & c) ^ (b & c)
            t2 := S0 + maj
            hh = g
            g = f
            f = e
            e = d + t1
            d = c
            c = b
            b = a
            a = t1 + t2
            i = i + 1
        h[0] = h[0] + a
        h[1] = h[1] + b
        h[2] = h[2] + c
        h[3] = h[3] + d
        h[4] = h[4] + e
        h[5] = h[5] + f
        h[6] = h[6] + g
        h[7] = h[7] + hh
        off = off + 128
    out := []
    for v in h:
        sh := 56
        while sh >= 0:
            append(out, (v >> sh) & 255)
            sh = sh - 8
    return out

# --- API de hachage -----------------------------------------------------------------------------------------

func _block_size(algo):
    if algo == "sha512":
        return 128
    return 64

func _check_algo(algo):
    if type(algo) != "str":
        raise("TypeError", "crypto : nom d'algorithme str attendu")
    if algo != "md5" and algo != "sha1" and algo != "sha256" and algo != "sha512":
        _fail("algorithme inconnu '" + algo + "' (md5, sha1, sha256, sha512)")

# Empreinte (liste d'octets) de `data` avec l'algorithme `algo`.
func hash_bytes(algo, data):
    _check_algo(algo)
    if algo == "sha256":
        return _sha256(data)
    if algo == "sha512":
        return _sha512(data)
    if algo == "sha1":
        return _sha1(data)
    return _md5(data)

func hash_hex(algo, data):
    return hex_encode(hash_bytes(algo, data))

func md5_bytes(data):
    return _md5(data)

func sha1_bytes(data):
    return _sha1(data)

func sha256_bytes(data):
    return _sha256(data)

func sha512_bytes(data):
    return _sha512(data)

func md5(data):
    return hex_encode(_md5(data))

func sha1(data):
    return hex_encode(_sha1(data))

func sha256(data):
    return hex_encode(_sha256(data))

func sha512(data):
    return hex_encode(_sha512(data))

# --- HMAC et PBKDF2 -------------------------------------------------------------------------------------------

# Remplissages ipad / opad de la clé (RFC 2104).
func _hmac_pads(algo, key):
    block := _block_size(algo)
    k := _bytes(key, "hmac")
    if len(k) > block:
        k = hash_bytes(algo, k)
    while len(k) < block:
        append(k, 0)
    ipad := []
    opad := []
    for b in k:
        append(ipad, b ^ 54)
        append(opad, b ^ 92)
    return [ipad, opad]

func _hmac_with(algo, pads, msg):
    inner := []
    for b in pads[0]:
        append(inner, b)
    for b in msg:
        append(inner, b)
    outer := []
    for b in pads[1]:
        append(outer, b)
    for b in hash_bytes(algo, inner):
        append(outer, b)
    return hash_bytes(algo, outer)

func hmac_bytes(algo, key, data):
    _check_algo(algo)
    return _hmac_with(algo, _hmac_pads(algo, key), _bytes(data, "hmac"))

func hmac(algo, key, data):
    return hex_encode(hmac_bytes(algo, key, data))

# PBKDF2-HMAC (RFC 8018) : liste de `length` octets dérivés.
func pbkdf2_bytes(password, salt, iterations, length, algo="sha256"):
    _check_algo(algo)
    if type(iterations) != "int" or iterations < 1:
        _fail("pbkdf2 : iterations doit être un entier >= 1")
    if type(length) != "int" or length < 1:
        _fail("pbkdf2 : length doit être un entier >= 1")
    pads := _hmac_pads(algo, password)
    s := _bytes(salt, "pbkdf2")
    hlen := len(hash_bytes(algo, []))
    out := []
    block := 1
    while len(out) < length:
        msg := []
        for b in s:
            append(msg, b)
        append(msg, (block >> 24) & 255)
        append(msg, (block >> 16) & 255)
        append(msg, (block >> 8) & 255)
        append(msg, block & 255)
        u := _hmac_with(algo, pads, msg)
        t := []
        for b in u:
            append(t, b)
        it := 1
        while it < iterations:
            u = _hmac_with(algo, pads, u)
            j := 0
            while j < hlen:
                t[j] = t[j] ^ u[j]
                j = j + 1
            it = it + 1
        for b in t:
            if len(out) < length:
                append(out, b)
        block = block + 1
    return out

func pbkdf2(password, salt, iterations, length, algo="sha256"):
    return hex_encode(pbkdf2_bytes(password, salt, iterations, length, algo))

# Égalité en temps constant (ne s'arrête pas au premier écart) de deux str ou de deux listes d'octets.
func equals(a, b):
    x := _bytes(a, "equals")
    y := _bytes(b, "equals")
    diff := len(x) ^ len(y)
    n := len(x)
    if len(y) < n:
        n = len(y)
    i := 0
    while i < n:
        diff = diff | (x[i] ^ y[i])
        i = i + 1
    return diff == 0

# --- ChaCha20 (RFC 8439) ---------------------------------------------------------------------------------------

func _qr(s, a, b, c, d):
    s[a] = (s[a] + s[b]) & _M32
    s[d] = _rotl32(s[d] ^ s[a], 16)
    s[c] = (s[c] + s[d]) & _M32
    s[b] = _rotl32(s[b] ^ s[c], 12)
    s[a] = (s[a] + s[b]) & _M32
    s[d] = _rotl32(s[d] ^ s[a], 8)
    s[c] = (s[c] + s[d]) & _M32
    s[b] = _rotl32(s[b] ^ s[c], 7)

func _le32(b, p):
    return b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)

# Flux de clé d'un bloc de 64 octets pour (key, counter, nonce).
func _chacha_block(key_words, counter, nonce_words):
    init := [1634760805, 857760878, 2036477234, 1797285236]
    for w in key_words:
        append(init, w)
    append(init, counter & _M32)
    for w in nonce_words:
        append(init, w)
    s := []
    for w in init:
        append(s, w)
    r := 0
    while r < 10:
        _qr(s, 0, 4, 8, 12)
        _qr(s, 1, 5, 9, 13)
        _qr(s, 2, 6, 10, 14)
        _qr(s, 3, 7, 11, 15)
        _qr(s, 0, 5, 10, 15)
        _qr(s, 1, 6, 11, 12)
        _qr(s, 2, 7, 8, 13)
        _qr(s, 3, 4, 9, 14)
        r = r + 1
    out := []
    i := 0
    while i < 16:
        v := (s[i] + init[i]) & _M32
        append(out, v & 255)
        append(out, (v >> 8) & 255)
        append(out, (v >> 16) & 255)
        append(out, (v >> 24) & 255)
        i = i + 1
    return out

# Chiffre (ou déchiffre : l'opération est son propre inverse) `data` avec ChaCha20. key : 32 octets, nonce : 12 octets
# (listes d'octets). Renvoie une liste d'octets. counter : compteur de bloc initial (1 dans la RFC 8439 pour AEAD).
func chacha20(key, nonce, data, counter=1):
    k := _bytes(key, "chacha20")
    nn := _bytes(nonce, "chacha20")
    if len(k) != 32:
        _fail("chacha20 : la clé doit faire 32 octets (obtenu " + str(len(k)) + ")")
    if len(nn) != 12:
        _fail("chacha20 : le nonce doit faire 12 octets (obtenu " + str(len(nn)) + ")")
    if type(counter) != "int" or counter < 0 or counter > _M32:
        _fail("chacha20 : counter doit être un entier 0..4294967295")
    msg := _bytes(data, "chacha20")
    if counter + (len(msg) + 63) // 64 > _M32 + 1:
        _fail("chacha20 : message trop long pour le compteur de 32 bits")
    kw := []
    i := 0
    while i < 8:
        append(kw, _le32(k, i * 4))
        i = i + 1
    nw := []
    i = 0
    while i < 3:
        append(nw, _le32(nn, i * 4))
        i = i + 1
    out := []
    pos := 0
    blk := counter
    while pos < len(msg):
        ks := _chacha_block(kw, blk, nw)
        j := 0
        while j < 64 and pos + j < len(msg):
            append(out, msg[pos + j] ^ ks[j])
            j = j + 1
        pos = pos + 64
        blk = blk + 1
    return out
