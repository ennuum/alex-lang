# ALEX STANDARD LIBRARY — crypto.poly1305
# Poly1305 (RFC 8439, 2.5) et le chiffrement authentifié ChaCha20-Poly1305 (RFC 8439, 2.8).
# Poly1305 : cinq limbes de 26 bits (produits < 2^58, tiennent dans un entier ALEX de 64 bits).
#
#   use crypto.poly1305 as p1305
#   tag := p1305.mac(cle32, message)                       # 16 octets ; clé à usage unique
#   boite := p1305.seal(cle32, nonce12, clair, aad)        # ChaCha20-Poly1305 : chiffré || étiquette
#   clair := p1305.open(cle32, nonce12, boite, aad)        # AuthenticationError si altéré
#
# Octets : listes d'entiers 0..255. Vérifié contre la RFC 8439 et OpenSSL dans tests/stdlib2/test_crypto_tls.al.
# Erreurs : ValueError (tailles), AuthenticationError.

from core use len, type
from collections use append
use crypto as _c

const _M26 := 67108863

func _fail(message):
    raise("ValueError", "poly1305 : " + message)

func _le32(b, i):
    return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)

# Étiquette Poly1305 de msg avec la clé (r || s) de 32 octets.
func mac(key, msg):
    if len(key) != 32:
        _fail("clé de 32 octets attendue")
    # r « bridé » (clamp), découpé en limbes de 26 bits
    r0 := _le32(key, 0) & 67108863
    r1 := (_le32(key, 3) >> 2) & 67108611
    r2 := (_le32(key, 6) >> 4) & 67092735
    r3 := (_le32(key, 9) >> 6) & 66076671
    r4 := (_le32(key, 12) >> 8) & 1048575
    s1 := r1 * 5
    s2 := r2 * 5
    s3 := r3 * 5
    s4 := r4 * 5
    h0 := 0
    h1 := 0
    h2 := 0
    h3 := 0
    h4 := 0
    n := len(msg)
    i := 0
    blk := [0] * 17                    # 16 octets du bloc (+ 1 de marge pour le 1 d'un bloc partiel)
    while i < n:
        m := n - i
        hibit := 0
        if m >= 16:
            j := 0
            while j < 16:
                blk[j] = msg[i + j]
                j += 1
            hibit = 16777216                # 1 << 24 : le bit 128 du bloc
        else:
            j := 0
            while j < m:
                blk[j] = msg[i + j]
                j += 1
            blk[m] = 1                      # bloc partiel : 1 juste après les octets, puis des zéros
            j = m + 1
            while j < 17:
                blk[j] = 0
                j += 1
        h0 = h0 + (_le32(blk, 0) & _M26)
        h1 = h1 + ((_le32(blk, 3) >> 2) & _M26)
        h2 = h2 + ((_le32(blk, 6) >> 4) & _M26)
        h3 = h3 + ((_le32(blk, 9) >> 6) & _M26)
        h4 = h4 + ((_le32(blk, 12) >> 8) | hibit)
        d0 := h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1
        d1 := h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2
        d2 := h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3
        d3 := h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4
        d4 := h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0
        c := d0 >> 26
        h0 = d0 & _M26
        d1 += c
        c = d1 >> 26
        h1 = d1 & _M26
        d2 += c
        c = d2 >> 26
        h2 = d2 & _M26
        d3 += c
        c = d3 >> 26
        h3 = d3 & _M26
        d4 += c
        c = d4 >> 26
        h4 = d4 & _M26
        h0 += c * 5
        c = h0 >> 26
        h0 = h0 & _M26
        h1 += c
        i += 16
    # réduction complète modulo 2^130 - 5
    c := h1 >> 26
    h1 = h1 & _M26
    h2 += c
    c = h2 >> 26
    h2 = h2 & _M26
    h3 += c
    c = h3 >> 26
    h3 = h3 & _M26
    h4 += c
    c = h4 >> 26
    h4 = h4 & _M26
    h0 += c * 5
    c = h0 >> 26
    h0 = h0 & _M26
    h1 += c
    g0 := h0 + 5
    c = g0 >> 26
    g0 = g0 & _M26
    g1 := h1 + c
    c = g1 >> 26
    g1 = g1 & _M26
    g2 := h2 + c
    c = g2 >> 26
    g2 = g2 & _M26
    g3 := h3 + c
    c = g3 >> 26
    g3 = g3 & _M26
    g4 := h4 + c - 67108864
    # g4 < 0 : h < p, garder h ; sinon h - p = g (choix sans branche dépendante des données)
    mask := (g4 >> 63) ^ -1                 # tous les bits à 1 si g4 >= 0
    nm := mask ^ -1
    h0 = (h0 & nm) | (g0 & mask)
    h1 = (h1 & nm) | (g1 & mask)
    h2 = (h2 & nm) | (g2 & mask)
    h3 = (h3 & nm) | (g3 & mask)
    h4 = (h4 & nm) | (g4 & mask)
    # h mod 2^128, puis + s
    f0 := (h0 | (h1 << 26)) & 4294967295
    f1 := ((h1 >> 6) | (h2 << 20)) & 4294967295
    f2 := ((h2 >> 12) | (h3 << 14)) & 4294967295
    f3 := ((h3 >> 18) | (h4 << 8)) & 4294967295
    f0 = f0 + _le32(key, 16)
    f1 = f1 + _le32(key, 20) + (f0 >> 32)
    f2 = f2 + _le32(key, 24) + (f1 >> 32)
    f3 = f3 + _le32(key, 28) + (f2 >> 32)
    out := []
    for f in [f0, f1, f2, f3]:
        append(out, f & 255)
        append(out, (f >> 8) & 255)
        append(out, (f >> 16) & 255)
        append(out, (f >> 24) & 255)
    return out

# ---------------------------------------------------------------- ChaCha20-Poly1305 (RFC 8439, 2.8)

func _pad16(out, n):
    r := n % 16
    if r != 0:
        k := 0
        while k < 16 - r:
            append(out, 0)
            k += 1

func _le64(out, n):
    k := 0
    while k < 8:
        append(out, (n >> (8 * k)) & 255)
        k += 1

func _aead_tag(key, nonce, aad, ct):
    otk := _c.chacha20(key, nonce, [0] * 32, 0)
    m := []
    for b in aad:
        append(m, b)
    _pad16(m, len(aad))
    for b in ct:
        append(m, b)
    _pad16(m, len(ct))
    _le64(m, len(aad))
    _le64(m, len(ct))
    return mac(otk, m)

func _check(key, nonce):
    if len(key) != 32:
        _fail("chacha20-poly1305 : clé de 32 octets attendue")
    if len(nonce) != 12:
        _fail("chacha20-poly1305 : nonce de 12 octets attendu")

# Chiffré || étiquette (16 octets).
func seal(key, nonce, plaintext, aad=null):
    _check(key, nonce)
    a := aad if aad != null else []
    ct := _c.chacha20(key, nonce, plaintext, 1)
    return ct + _aead_tag(key, nonce, a, ct)

# Clair si l'étiquette est bonne (comparaison en temps constant), sinon AuthenticationError.
func open(key, nonce, sealed, aad=null):
    _check(key, nonce)
    a := aad if aad != null else []
    if len(sealed) < 16:
        raise("AuthenticationError", "chacha20-poly1305 : message trop court")
    ct := sealed[0:len(sealed) - 16]
    want := _aead_tag(key, nonce, a, ct)
    diff := 0
    i := 0
    while i < 16:
        diff = diff | (want[i] ^ sealed[len(ct) + i])
        i += 1
    if diff != 0:
        raise("AuthenticationError", "chacha20-poly1305 : étiquette d'authentification invalide")
    return _c.chacha20(key, nonce, ct, 1)
