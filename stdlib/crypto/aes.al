# ALEX STANDARD LIBRARY — crypto.aes
# AES (FIPS 197) en ALEX pur, chiffrement seulement (ce que demandent les modes CTR et GCM) : clés de 128, 192 ou
# 256 bits, tables « T » précalculées (quatre consultations par colonne et par tour).
#
#   use crypto.aes as aes
#   k := aes.key(octets_de_la_cle)            # AesKey : clé étendue (une fois par clé)
#   bloc := aes.encrypt_block(k, seize_octets) # liste de 16 octets
#   flux := aes.ctr(k, compteur16, donnees)    # mode CTR (compteur 32 bits du bloc, comme GCM)
#
# Octets : listes d'entiers 0..255 (comme le module crypto). Vérifié contre FIPS 197 (annexe C) et OpenSSL dans
# tests/stdlib2/test_crypto_tls.al.
# LIMITES : les tables rendent les accès mémoire dépendants de la clé : pas de garantie contre les attaques par
# cache (canaux auxiliaires). Erreurs : ValueError (taille de clé ou de bloc).

from core use len, type
from collections use append

const _M32 := 4294967295

func _fail(message):
    raise("ValueError", "aes : " + message)

func _xtime(x):
    y := x << 1
    if y & 256:
        y = y ^ 283
    return y & 255

func _mul(a, b):
    r := 0
    x := a
    y := b
    while y > 0:
        if y & 1:
            r = r ^ x
        x = _xtime(x)
        y = y >> 1
    return r

# Boîte S : inverse dans GF(2^8) (par les puissances du générateur 3) suivi de la transformation affine.
func _make_sbox():
    ex := []
    lg := []
    i := 0
    while i < 256:
        append(lg, 0)
        i += 1
    x := 1
    i = 0
    while i < 255:
        append(ex, x)
        lg[x] = i
        x = x ^ _xtime(x)                # x * 3
        i += 1
    inv := [0]
    i = 1
    while i < 256:
        append(inv, ex[(255 - lg[i]) % 255])
        i += 1
    out := []
    for b in inv:
        s := b
        x := b
        k := 0
        while k < 4:
            x = ((x << 1) | (x >> 7)) & 255
            s = s ^ x
            k += 1
        append(out, s ^ 99)
    return out

const SBOX := _make_sbox()

func _make_t(shift):
    out := []
    for s in SBOX:
        w := (_mul(s, 2) << 24) | (s << 16) | (s << 8) | _mul(s, 3)
        append(out, ((w >> shift) | (w << (32 - shift))) & _M32)
    return out

const _T0 := _make_t(0)
const _T1 := _make_t(8)
const _T2 := _make_t(16)
const _T3 := _make_t(24)
const _RCON := [1, 2, 4, 8, 16, 32, 64, 128, 27, 54]

class AesKey:
    func init(words, rounds):
        self.w = words                   # 4 * (tours + 1) mots de 32 bits
        self.rounds = rounds

# Clé étendue (FIPS 197, 5.2).
func key(k):
    if type(k) != "list" and type(k) != "tuple":
        raise("TypeError", "aes.key : liste d'octets attendue")
    nk := len(k) // 4
    if len(k) != 16 and len(k) != 24 and len(k) != 32:
        _fail("clé de 16, 24 ou 32 octets attendue (obtenu " + str(len(k)) + ")")
    rounds := nk + 6
    w := []
    i := 0
    while i < nk:
        append(w, (k[4 * i] << 24) | (k[4 * i + 1] << 16) | (k[4 * i + 2] << 8) | k[4 * i + 3])
        i += 1
    while i < 4 * (rounds + 1):
        t := w[i - 1]
        if i % nk == 0:
            t = ((t << 8) | (t >> 24)) & _M32
            t = (SBOX[t >> 24] << 24) | (SBOX[(t >> 16) & 255] << 16) | (SBOX[(t >> 8) & 255] << 8) | SBOX[t & 255]
            t = t ^ (_RCON[i // nk - 1] << 24)
        elif nk > 6 and i % nk == 4:
            t = (SBOX[t >> 24] << 24) | (SBOX[(t >> 16) & 255] << 16) | (SBOX[(t >> 8) & 255] << 8) | SBOX[t & 255]
        append(w, w[i - nk] ^ t)
        i += 1
    return AesKey(w, rounds)

# Chiffre un bloc donné par ses quatre mots (big-endian) ; rend quatre mots.
func encrypt_words(k, a0, a1, a2, a3):
    w := k.w
    s0 := a0 ^ w[0]
    s1 := a1 ^ w[1]
    s2 := a2 ^ w[2]
    s3 := a3 ^ w[3]
    r := 1
    o := 4
    while r < k.rounds:
        t0 := _T0[s0 >> 24] ^ _T1[(s1 >> 16) & 255] ^ _T2[(s2 >> 8) & 255] ^ _T3[s3 & 255] ^ w[o]
        t1 := _T0[s1 >> 24] ^ _T1[(s2 >> 16) & 255] ^ _T2[(s3 >> 8) & 255] ^ _T3[s0 & 255] ^ w[o + 1]
        t2 := _T0[s2 >> 24] ^ _T1[(s3 >> 16) & 255] ^ _T2[(s0 >> 8) & 255] ^ _T3[s1 & 255] ^ w[o + 2]
        t3 := _T0[s3 >> 24] ^ _T1[(s0 >> 16) & 255] ^ _T2[(s1 >> 8) & 255] ^ _T3[s2 & 255] ^ w[o + 3]
        s0 = t0
        s1 = t1
        s2 = t2
        s3 = t3
        o += 4
        r += 1
    S := SBOX
    return [((S[s0 >> 24] << 24) | (S[(s1 >> 16) & 255] << 16) | (S[(s2 >> 8) & 255] << 8) | S[s3 & 255]) ^ w[o],
            ((S[s1 >> 24] << 24) | (S[(s2 >> 16) & 255] << 16) | (S[(s3 >> 8) & 255] << 8) | S[s0 & 255]) ^ w[o + 1],
            ((S[s2 >> 24] << 24) | (S[(s3 >> 16) & 255] << 16) | (S[(s0 >> 8) & 255] << 8) | S[s1 & 255]) ^ w[o + 2],
            ((S[s3 >> 24] << 24) | (S[(s0 >> 16) & 255] << 16) | (S[(s1 >> 8) & 255] << 8) | S[s2 & 255]) ^ w[o + 3]]

func _word(b, i):
    return (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]

func encrypt_block(k, block):
    if len(block) != 16:
        _fail("bloc de 16 octets attendu")
    r := encrypt_words(k, _word(block, 0), _word(block, 4), _word(block, 8), _word(block, 12))
    out := []
    for v in r:
        append(out, v >> 24)
        append(out, (v >> 16) & 255)
        append(out, (v >> 8) & 255)
        append(out, v & 255)
    return out

# Mode CTR : chiffre (ou déchiffre) data avec le flux E(compteur), E(compteur + 1)... ; seul le dernier mot du
# compteur (32 bits, modulo 2^32) avance, comme dans GCM (SP 800-38D, inc32).
func ctr(k, counter, data):
    if len(counter) != 16:
        _fail("compteur de 16 octets attendu")
    c0 := _word(counter, 0)
    c1 := _word(counter, 4)
    c2 := _word(counter, 8)
    c3 := _word(counter, 12)
    out := []
    n := len(data)
    i := 0
    while i < n:
        ks := encrypt_words(k, c0, c1, c2, c3)
        c3 = (c3 + 1) & _M32
        j := 0
        while j < 16 and i < n:
            v := ks[j >> 2]
            append(out, data[i] ^ ((v >> (24 - 8 * (j & 3))) & 255))
            i += 1
            j += 1
    return out
