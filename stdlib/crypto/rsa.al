# ALEX STANDARD LIBRARY — crypto.rsa
# RSA (RFC 8017) : signatures RSASSA-PKCS1-v1_5 et RSASSA-PSS (MGF1), avec SHA-256 / SHA-384 / SHA-512.
# La clé privée signe par les restes chinois (p, q, dp, dq, qinv), et chaque signature est revérifiée avec la clé
# publique avant d'être rendue (une faute de calcul ne divulgue pas la clé).
#
#   use crypto.rsa as rsa
#   pub := rsa.PublicKey(n, e)                              # bigint (crypto.bigint)
#   cle := rsa.PrivateKey(n, e, d, p, q, dp, dq, qinv)      # dp, dq, qinv null : calculés
#   sig := rsa.sign_pss(cle, message, "sha256")             # sel aléatoire de la taille de l'empreinte (TLS 1.3)
#   rsa.verify_pss(pub, message, sig, "sha256")             # vrai / faux
#   sig := rsa.sign_pkcs1(cle, message, "sha256")           # déterministe (X.509, JWS RS256)
#   rsa.verify_pkcs1(pub, message, sig, "sha256")
#
# Octets : listes d'entiers 0..255. Vérifié contre OpenSSL dans tests/stdlib2/test_crypto_pk.al.
# LIMITES : exponentiation modulaire à temps variable (crypto.bigint). Erreurs : ValueError (clé, tailles).

from core use len, type
from collections use append
use crypto as _c
use crypto.bigint as bn
use security.random_secure as _rnd

func _fail(message):
    raise("ValueError", "rsa : " + message)

const _DIGEST_INFO := {"sha256": "3031300d060960864801650304020105000420",
                       "sha384": "3041300d060960864801650304020205000430",
                       "sha512": "3051300d060960864801650304020305000440"}

func _hlen(algo):
    if not (algo in _DIGEST_INFO):
        _fail("empreinte sha256, sha384 ou sha512 attendue (obtenu " + str(algo) + ")")
    return len(_c.hash_bytes(algo, []))

class PublicKey:
    func init(n, e):
        if not bn.is_odd(n) or bn.bit_length(n) < 1024:
            _fail("module impair d'au moins 1024 bits attendu")
        self.n = n
        self.e = e
        self.size = (bn.bit_length(n) + 7) // 8
        self.mont = bn.Montgomery(n)

    func _public(m):
        return self.mont.pow(m, self.e)

class PrivateKey:
    func init(n, e, d, p, q, dp=null, dq=null, qinv=null):
        self.public = PublicKey(n, e)
        if not bn.eq(bn.mul(p, q), n):
            _fail("p * q différent de n")
        self.n = n
        self.e = e
        self.d = d
        self.p = p
        self.q = q
        self.dp = dp if dp != null else bn.mod(d, bn.sub(p, [1]))
        self.dq = dq if dq != null else bn.mod(d, bn.sub(q, [1]))
        self.qinv = qinv if qinv != null else bn.modinv(q, p)
        self.mp = bn.Montgomery(p)
        self.mq = bn.Montgomery(q)
        self.size = self.public.size

    # RSASP1 par les restes chinois, vérifié par RSAVP1.
    func _private(c):
        m1 := self.mp.pow(bn.mod(c, self.p), self.dp)
        m2 := self.mq.pow(bn.mod(c, self.q), self.dq)
        diff := bn.sub(m1, bn.mod(m2, self.p)) if bn.cmp(m1, bn.mod(m2, self.p)) >= 0 else bn.sub(bn.add(m1, self.p), bn.mod(m2, self.p))
        h := bn.mod(bn.mul(self.qinv, diff), self.p)
        m := bn.add(m2, bn.mul(h, self.q))
        if not bn.eq(self.public._public(m), bn.mod(c, self.n)):
            _fail("faute de calcul détectée pendant la signature")
        return m

# MGF1 (RFC 8017, B.2.1).
func mgf1(algo, seed, length):
    out := []
    counter := 0
    while len(out) < length:
        c := [(counter >> 24) & 255, (counter >> 16) & 255, (counter >> 8) & 255, counter & 255]
        for b in _c.hash_bytes(algo, seed + c):
            if len(out) < length:
                append(out, b)
        counter += 1
    return out

# ---------------------------------------------------------------- PKCS#1 v1.5 (RFC 8017, 8.2 et 9.2)

func _pkcs1_em(algo, message, k):
    t := _c.hex_decode(_DIGEST_INFO[algo]) + _c.hash_bytes(algo, message)
    if k < len(t) + 11:
        _fail("module trop petit")
    return [0, 1] + [255] * (k - len(t) - 3) + [0] + t

func sign_pkcs1(key, message, algo="sha256"):
    _hlen(algo)
    em := _pkcs1_em(algo, message, key.size)
    return bn.to_bytes(key._private(bn.from_bytes(em)), key.size)

func verify_pkcs1(pub, message, sig, algo="sha256"):
    _hlen(algo)
    if len(sig) != pub.size:
        return false
    s := bn.from_bytes(sig)
    if bn.cmp(s, pub.n) >= 0:
        return false
    em := bn.to_bytes(pub._public(s), pub.size)
    want := _pkcs1_em(algo, message, pub.size)
    diff := 0
    i := 0
    while i < len(em):
        diff = diff | (em[i] ^ want[i])
        i += 1
    return diff == 0

# ---------------------------------------------------------------- PSS (RFC 8017, 8.1 et 9.1)

func _pss_encode(algo, mhash, salt, embits):
    hlen := len(mhash)
    emlen := (embits + 7) // 8
    if emlen < hlen + len(salt) + 2:
        _fail("module trop petit pour PSS")
    h := _c.hash_bytes(algo, [0] * 8 + mhash + salt)
    db := [0] * (emlen - len(salt) - hlen - 2) + [1] + salt
    mask := mgf1(algo, h, emlen - hlen - 1)
    masked := [db[i] ^ mask[i] for i in _range(len(db))]
    masked[0] = masked[0] & (255 >> (8 * emlen - embits))
    return masked + h + [188]

# Signature PSS ; salt_len null : taille de l'empreinte (exigée par TLS 1.3) ; salt : sel imposé (tests).
func sign_pss(key, message, algo="sha256", salt_len=null, salt=null):
    hlen := _hlen(algo)
    s := salt if salt != null else _rnd.random_bytes(salt_len if salt_len != null else hlen)
    embits := bn.bit_length(key.n) - 1
    em := _pss_encode(algo, _c.hash_bytes(algo, message), s, embits)
    return bn.to_bytes(key._private(bn.from_bytes(em)), key.size)

# Vérification PSS ; salt_len null : sel de la taille de l'empreinte.
func verify_pss(pub, message, sig, algo="sha256", salt_len=null):
    hlen := _hlen(algo)
    slen := salt_len if salt_len != null else hlen
    if len(sig) != pub.size:
        return false
    s := bn.from_bytes(sig)
    if bn.cmp(s, pub.n) >= 0:
        return false
    embits := bn.bit_length(pub.n) - 1
    emlen := (embits + 7) // 8
    em := bn.to_bytes(pub._public(s), pub.size)
    if len(em) > emlen:
        if em[0] != 0:
            return false
        em = em[len(em) - emlen:len(em)]
    if emlen < hlen + slen + 2 or em[emlen - 1] != 188:
        return false
    masked := em[0:emlen - hlen - 1]
    h := em[emlen - hlen - 1:emlen - 1]
    if (masked[0] & (255 ^ (255 >> (8 * emlen - embits)))) != 0:
        return false
    mask := mgf1(algo, h, emlen - hlen - 1)
    db := [masked[i] ^ mask[i] for i in _range(len(masked))]
    db[0] = db[0] & (255 >> (8 * emlen - embits))
    k := emlen - hlen - slen - 2
    i := 0
    while i < k:
        if db[i] != 0:
            return false
        i += 1
    if db[k] != 1:
        return false
    salt := db[len(db) - slen:len(db)]
    want := _c.hash_bytes(algo, [0] * 8 + _c.hash_bytes(algo, message) + salt)
    return _c.equals(want, h)

func _range(n):
    out := []
    i := 0
    while i < n:
        append(out, i)
        i += 1
    return out
