# ALEX STANDARD LIBRARY — crypto.ec
# Courbes elliptiques NIST P-256 et P-384 (FIPS 186-4) : ECDH et ECDSA, nonce déterministe de la RFC 6979.
# Coordonnées jacobiennes (a = -3), corps en représentation de Montgomery (crypto.bigint), fenêtre de 4 bits.
#
#   use crypto.ec as ec
#   c := ec.curve("P-256")                                  # aussi "P-384"
#   cle := ec.private_key(c, octets_32)                    # PrivateKey ; .public (point), .public_bytes()
#   pub := ec.public_key(c, octets_04_x_y)                  # point décodé ET vérifié (sur la courbe)
#   secret := ec.ecdh(cle, pub)                            # coordonnée x du point partagé (32 / 48 octets)
#   sig := ec.sign(cle, message, "sha256")                 # [r, s] (bigint) ; ec.sign_der : DER (TLS, X.509)
#   ec.verify(pub, message, sig, "sha256")                 # vrai / faux ; ec.verify_der pour une signature DER
#
# Octets : listes d'entiers 0..255. Vérifié contre la RFC 6979 (annexe A.2.5) et OpenSSL dans
# tests/stdlib2/test_crypto_pk.al.
# LIMITES : la multiplication scalaire n'est pas en temps constant (fenêtre et additions dépendent du scalaire) :
# pas de garantie contre les attaques temporelles sur la clé privée. Erreurs : ValueError (point ou clé invalide).

from core use len, type
from collections use append
use crypto as _c
use crypto.bigint as bn
use string as _s
use crypto.accel as _ax

func _fail(message):
    raise("ValueError", "ec : " + message)

const _PARAMS := {
    "P-256": {"p": "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff",
              "b": "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b",
              "gx": "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296",
              "gy": "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5",
              "n": "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", "size": 32, "hash": "sha256"},
    "P-384": {"p": "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff",
              "b": "b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef",
              "gx": "aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7",
              "gy": "3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f",
              "n": "ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973", "size": 48, "hash": "sha384"}
}

class Curve:
    func init(name, d):
        self.name = name
        self.p = bn.from_hex(d["p"])
        self.n = bn.from_hex(d["n"])
        self.size = d["size"]
        self.hash = d["hash"]
        self.fp = bn.Montgomery(self.p)          # corps de base
        self.fn = bn.Montgomery(self.n)          # scalaires (ordre du groupe)
        self.b = self.fp.to_mont(bn.from_hex(d["b"]))
        self.one = self.fp.to_mont([1])
        self.three = self.fp.to_mont([3])
        self.g = [self.fp.to_mont(bn.from_hex(d["gx"])), self.fp.to_mont(bn.from_hex(d["gy"])), self.one]
        self._gtab = null
        self.p_raw = _s.byte_pack(bn.to_bytes(self.p, self.size))

    # ------------------------------------------------------------ corps (valeurs de Montgomery, < p)

    func fadd(a, b):
        s := bn.add(a, b)
        return bn.sub(s, self.p) if bn.cmp(s, self.p) >= 0 else s

    func fsub(a, b):
        return bn.sub(a, b) if bn.cmp(a, b) >= 0 else bn.sub(bn.add(a, self.p), b)

    func fmul(a, b):
        return self.fp.mul(a, b)

    func finv(a):
        return self.fp.to_mont(bn.modinv(self.fp.from_mont(a), self.p))

    # ------------------------------------------------------------ points jacobiens [X, Y, Z] ; Z = 0 : infini

    func infinity():
        return [[], self.one, []]

    func is_inf(P):
        return len(P[2]) == 0

    # dbl-2001-b (a = -3)
    func double(P):
        if self.is_inf(P) or len(P[1]) == 0:
            return self.infinity()
        X := P[0]
        Y := P[1]
        Z := P[2]
        delta := self.fmul(Z, Z)
        gamma := self.fmul(Y, Y)
        beta := self.fmul(X, gamma)
        alpha := self.fmul(self.three, self.fmul(self.fsub(X, delta), self.fadd(X, delta)))
        b4 := self.fadd(beta, beta)
        b4 = self.fadd(b4, b4)
        b8 := self.fadd(b4, b4)
        X3 := self.fsub(self.fmul(alpha, alpha), b8)
        yz := self.fadd(Y, Z)
        Z3 := self.fsub(self.fsub(self.fmul(yz, yz), gamma), delta)
        g2 := self.fmul(gamma, gamma)
        g8 := self.fadd(g2, g2)
        g8 = self.fadd(g8, g8)
        g8 = self.fadd(g8, g8)
        Y3 := self.fsub(self.fmul(alpha, self.fsub(b4, X3)), g8)
        return [X3, Y3, Z3]

    # add-2007-bl
    func add(P, Q):
        if self.is_inf(P):
            return Q
        if self.is_inf(Q):
            return P
        z1z1 := self.fmul(P[2], P[2])
        z2z2 := self.fmul(Q[2], Q[2])
        u1 := self.fmul(P[0], z2z2)
        u2 := self.fmul(Q[0], z1z1)
        s1 := self.fmul(P[1], self.fmul(Q[2], z2z2))
        s2 := self.fmul(Q[1], self.fmul(P[2], z1z1))
        h := self.fsub(u2, u1)
        r := self.fsub(s2, s1)
        if len(h) == 0:
            if len(r) == 0:
                return self.double(P)
            return self.infinity()
        r = self.fadd(r, r)
        h2 := self.fadd(h, h)
        i := self.fmul(h2, h2)
        j := self.fmul(h, i)
        v := self.fmul(u1, i)
        X3 := self.fsub(self.fsub(self.fmul(r, r), j), self.fadd(v, v))
        sj := self.fmul(s1, j)
        Y3 := self.fsub(self.fmul(r, self.fsub(v, X3)), self.fadd(sj, sj))
        zz := self.fadd(P[2], Q[2])
        Z3 := self.fmul(self.fsub(self.fsub(self.fmul(zz, zz), z1z1), z2z2), h)
        return [X3, Y3, Z3]

    func _table(P):
        tab := [self.infinity(), P]
        k := 2
        while k < 16:
            append(tab, self.add(tab[k - 1], P) if k % 2 == 1 else self.double(tab[k // 2]))
            k += 1
        return tab

    # k * P (k : bigint), fenêtre fixe de 4 bits.
    func mul(k, P, tab=null):
        if _ax.has("ec_mul"):
            return self._mul_native(k, P)
        t := tab if tab != null else self._table(P)
        acc := self.infinity()
        nbits := bn.bit_length(k)
        top := ((nbits + 3) // 4) * 4 - 4
        while top >= 0:
            acc = self.double(self.double(self.double(self.double(acc))))
            w := 0
            b := 3
            while b >= 0:
                w = (w << 1) | (1 if bn.test_bit(k, top + b) else 0)
                b -= 1
            if w != 0:
                acc = self.add(acc, t[w])
            top -= 4
        return acc

    # k * P par le runtime (crypto.accel) : résultat affine remis en forme jacobienne de Montgomery.
    func _mul_native(k, P):
        if self.is_inf(P) or len(k) == 0:
            return self.infinity()
        a := self.affine(P)
        sz := self.size
        r := _ax.native().ec_mul(self.p_raw, _s.byte_pack(bn.to_bytes(k)), _s.byte_pack(bn.to_bytes(a[0], sz)), _s.byte_pack(bn.to_bytes(a[1], sz)))
        if r == "":
            return self.infinity()
        b := _s.byte_unpack(r)
        return [self.fp.to_mont(bn.from_bytes(b[0:sz])), self.fp.to_mont(bn.from_bytes(b[sz:2 * sz])), self.one]

    func mul_base(k):
        if self._gtab == null:
            self._gtab = self._table(self.g)
        return self.mul(k, self.g, self._gtab)

    # Coordonnées affines (bigint ordinaires) ; erreur pour l'infini.
    func affine(P):
        if self.is_inf(P):
            _fail("point à l'infini")
        if bn.eq(P[2], self.one):
            return [self.fp.from_mont(P[0]), self.fp.from_mont(P[1])]
        zi := self.finv(P[2])
        zi2 := self.fmul(zi, zi)
        x := self.fp.from_mont(self.fmul(P[0], zi2))
        y := self.fp.from_mont(self.fmul(P[1], self.fmul(zi2, zi)))
        return [x, y]

    # Point affine (bigint ordinaires) vérifié : coordonnées < p et y^2 = x^3 - 3x + b.
    func point(x, y):
        if bn.cmp(x, self.p) >= 0 or bn.cmp(y, self.p) >= 0:
            _fail("coordonnée hors du corps")
        X := self.fp.to_mont(x)
        Y := self.fp.to_mont(y)
        lhs := self.fmul(Y, Y)
        x3 := self.fmul(self.fmul(X, X), X)
        rhs := self.fadd(self.fsub(x3, self.fmul(self.three, X)), self.b)
        if not bn.eq(lhs, rhs):
            _fail("le point n'est pas sur la courbe " + self.name)
        return [X, Y, self.one]

    func encode(P):
        a := self.affine(P)
        return [4] + bn.to_bytes(a[0], self.size) + bn.to_bytes(a[1], self.size)

    # Point non compressé 04 || x || y (SEC 1, 2.3.4), vérifié.
    func decode(b):
        if len(b) != 1 + 2 * self.size or b[0] != 4:
            _fail("point non compressé de " + str(1 + 2 * self.size) + " octets attendu")
        return self.point(bn.from_bytes(b[1:1 + self.size]), bn.from_bytes(b[1 + self.size:len(b)]))

_curves := {}

func curve(name):
    if not (name in _PARAMS):
        _fail("courbe inconnue " + str(name) + " (P-256, P-384)")
    if not (name in _curves):
        _curves[name] = Curve(name, _PARAMS[name])
    return _curves[name]

# ---------------------------------------------------------------- clés

class PublicKey:
    func init(c, point):
        self.curve = c
        self.point = point

    func to_bytes():
        return self.curve.encode(self.point)

class PrivateKey:
    func init(c, d):
        self.curve = c
        self.d = d
        self.public = PublicKey(c, c.mul_base(d))

    func public_bytes():
        return self.public.to_bytes()

    func to_bytes():
        return bn.to_bytes(self.d, self.curve.size)

func private_key(c, b):
    d := bn.from_bytes(b)
    if len(d) == 0 or bn.cmp(d, c.n) >= 0:
        _fail("clé privée hors de [1, n - 1]")
    return PrivateKey(c, d)

func public_key(c, b):
    return PublicKey(c, c.decode(b))

# Secret ECDH : coordonnée x de d * Q (SEC 1, 3.3.1).
func ecdh(priv, pub):
    if pub.curve.name != priv.curve.name:
        _fail("courbes différentes")
    P := priv.curve.mul(priv.d, pub.point)
    return bn.to_bytes(priv.curve.affine(P)[0], priv.curve.size)

# ---------------------------------------------------------------- ECDSA (FIPS 186-4, 6 ; RFC 6979)

func _bits2int(c, b):
    x := bn.from_bytes(b)
    excess := len(b) * 8 - bn.bit_length(c.n)
    return bn.shr(x, excess) if excess > 0 else x

func _hmac(algo, k, data):
    return _ax.hmac(algo, k, data)

# Nonce déterministe de la RFC 6979 (3.2) pour la clé x et l'empreinte h1, HMAC avec algo.
func rfc6979_k(c, x, h1, algo):
    rlen := (bn.bit_length(c.n) + 7) // 8
    hlen := len(_c.hash_bytes(algo, []))
    xo := bn.to_bytes(x, rlen)
    ho := bn.to_bytes(bn.mod(_bits2int(c, h1), c.n), rlen)
    V := [1] * hlen
    K := [0] * hlen
    K = _hmac(algo, K, V + [0] + xo + ho)
    V = _hmac(algo, K, V)
    K = _hmac(algo, K, V + [1] + xo + ho)
    V = _hmac(algo, K, V)
    while true:
        T := []
        while len(T) < rlen:
            V = _hmac(algo, K, V)
            T = T + V
        k := _bits2int(c, T[0:rlen])
        if len(k) > 0 and bn.cmp(k, c.n) < 0:
            return k
        K = _hmac(algo, K, V + [0])
        V = _hmac(algo, K, V)

# Signature [r, s] de l'empreinte digest.
func sign_digest(priv, digest, algo=null):
    c := priv.curve
    a := algo if algo != null else c.hash
    e := bn.mod(_bits2int(c, digest), c.n)
    k := rfc6979_k(c, priv.d, digest, a)
    while true:
        r := bn.mod(c.affine(c.mul_base(k))[0], c.n)
        if len(r) > 0:
            s := null
            if _ax.has("mulmod") and _ax.has("modpow"):
                # k^-1 = k^(n - 2) mod n (n premier), produits modulo n : calculs du runtime
                nb := c.size
                t := _ax.native()
                n_raw := _s.byte_pack(bn.to_bytes(c.n, nb))
                kinv := t.modpow(_s.byte_pack(bn.to_bytes(k, nb)), _s.byte_pack(bn.to_bytes(bn.sub(c.n, [2]))), n_raw)
                rd := bn.from_bytes(_s.byte_unpack(t.mulmod(_s.byte_pack(bn.to_bytes(r, nb)), _s.byte_pack(bn.to_bytes(priv.d, nb)), n_raw)))
                sum := bn.add(e, rd)
                if bn.cmp(sum, c.n) >= 0:
                    sum = bn.sub(sum, c.n)
                s = bn.from_bytes(_s.byte_unpack(t.mulmod(kinv, _s.byte_pack(bn.to_bytes(sum, nb)), n_raw)))
            else:
                kinv := bn.modinv(k, c.n)
                s = bn.mod(bn.mul(kinv, bn.add(e, bn.mod(bn.mul(r, priv.d), c.n))), c.n)
            if len(s) > 0:
                return [r, s]
        k = bn.mod(bn.add(k, [1]), c.n)      # cas de probabilité négligeable

func sign(priv, message, algo=null):
    a := algo if algo != null else priv.curve.hash
    return sign_digest(priv, _ax.hash(a, message), a)

func verify_digest(pub, digest, sig):
    c := pub.curve
    r := sig[0]
    s := sig[1]
    if len(r) == 0 or len(s) == 0 or bn.cmp(r, c.n) >= 0 or bn.cmp(s, c.n) >= 0:
        return false
    e := bn.mod(_bits2int(c, digest), c.n)
    w := bn.modinv(s, c.n)
    u1 := bn.mod(bn.mul(e, w), c.n)
    u2 := bn.mod(bn.mul(r, w), c.n)
    X := c.add(c.mul_base(u1), c.mul(u2, pub.point))
    if c.is_inf(X):
        return false
    return bn.eq(bn.mod(c.affine(X)[0], c.n), r)

func verify(pub, message, sig, algo=null):
    a := algo if algo != null else pub.curve.hash
    return verify_digest(pub, _c.hash_bytes(a, message), sig)

# ---------------------------------------------------------------- signatures DER (RFC 3279 : SEQUENCE { r, s })

func _der_int(x):
    b := bn.to_bytes(x)
    if len(b) == 0:
        b = [0]
    if b[0] >= 128:
        b = [0] + b
    return [2] + _der_len(len(b)) + b

func _der_len(n):
    if n < 128:
        return [n]
    if n < 256:
        return [129, n]
    return [130, n >> 8, n & 255]

func sig_to_der(sig):
    body := _der_int(sig[0]) + _der_int(sig[1])
    return [48] + _der_len(len(body)) + body

# [r, s] depuis une signature DER ; encodage strict (longueurs minimales, entiers positifs minimaux).
func sig_from_der(b):
    if len(b) < 8 or b[0] != 48:
        _fail("signature DER : SEQUENCE attendue")
    p := _read_len(b, 1)
    if p[1] + p[0] != len(b):
        _fail("signature DER : longueur incohérente")
    i := p[1]
    out := []
    k := 0
    while k < 2:
        if i >= len(b) or b[i] != 2:
            _fail("signature DER : INTEGER attendu")
        q := _read_len(b, i + 1)
        n := q[0]
        j := q[1]
        if n == 0 or j + n > len(b):
            _fail("signature DER : entier invalide")
        if b[j] >= 128 or (n > 1 and b[j] == 0 and b[j + 1] < 128):
            _fail("signature DER : entier non minimal ou négatif")
        append(out, bn.from_bytes(b[j:j + n]))
        i = j + n
        k += 1
    if i != len(b):
        _fail("signature DER : octets en trop")
    return out

func _read_len(b, i):
    if i >= len(b):
        _fail("signature DER : tronquée")
    if b[i] < 128:
        return [b[i], i + 1]
    if b[i] == 129 and i + 1 < len(b) and b[i + 1] >= 128:
        return [b[i + 1], i + 2]
    _fail("signature DER : longueur non minimale ou trop grande")

func sign_der(priv, message, algo=null):
    return sig_to_der(sign(priv, message, algo))

func verify_der(pub, message, der, algo=null):
    sig := null
    try:
        sig = sig_from_der(der)
    catch e:
        return false
    return verify(pub, message, sig, algo)
