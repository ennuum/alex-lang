# ALEX STANDARD LIBRARY — crypto.gcm
# AES-GCM (NIST SP 800-38D) : chiffrement authentifié avec données associées, nonce de 96 bits, étiquette de
# 16 octets. GHASH par tables de 4 bits (méthode de Shoup), sur deux mots de 64 bits.
#
#   use crypto.gcm as gcm
#   c := gcm.AesGcm(cle)                          # 16, 24 ou 32 octets ; tables calculées une fois
#   boite := c.seal(nonce12, clair, aad)          # chiffré suivi de l'étiquette (16 octets)
#   clair := c.open(nonce12, boite, aad)          # AuthenticationError si chiffré, aad ou étiquette altérés
#
# Octets : listes d'entiers 0..255. Vérifié contre les vecteurs de test GCM (McGrew et Viega) et OpenSSL dans
# tests/stdlib2/test_crypto_tls.al. Ne jamais réutiliser un nonce avec la même clé.
# Erreurs : ValueError (tailles), AuthenticationError (étiquette refusée ; aucun clair rendu).

from core use len, type
from collections use append
use crypto.aes as _aes
use string as _s
use crypto.accel as _ax

const _M32 := 4294967295
const _LAST4 := [0, 7200, 14400, 9312, 28800, 27808, 18624, 21728, 57600, 64800, 55616, 50528, 37248, 36256, 43456, 46560]

func _fail(message):
    raise("ValueError", "gcm : " + message)

# Décalage logique à droite d'un mot de 64 bits (>> est arithmétique en ALEX).
func _shr(x, n):
    return (x >> n) & ((1 << (64 - n)) - 1)

func _be64(b, i):
    v := 0
    j := 0
    while j < 8:
        v = (v << 8) | b[i + j]
        j += 1
    return v

func _put64(out, v):
    sh := 56
    while sh >= 0:
        append(out, (v >> sh) & 255)
        sh -= 8

class AesGcm:
    func init(k):
        self.raw = _s.byte_pack(k)
        self.fast = _ax.has("aes_gcm")
        if self.fast:
            if len(k) != 16 and len(k) != 24 and len(k) != 32:
                _fail("clé de 16, 24 ou 32 octets attendue (obtenu " + str(len(k)) + ")")
            self.key = null              # tables inutiles : le runtime chiffre (crypto.accel)
            return
        self.key = _aes.key(k)
        h := _aes.encrypt_block(self.key, [0] * 16)
        vh := _be64(h, 0)
        vl := _be64(h, 8)
        hh := [0] * 16
        hl := [0] * 16
        hh[8] = vh
        hl[8] = vl
        i := 4
        while i > 0:
            t := -2233785415175766016 if (vl & 1) != 0 else 0      # 0xe1 << 56
            vl = (vh << 63) | _shr(vl, 1)
            vh = _shr(vh, 1) ^ t
            hh[i] = vh
            hl[i] = vl
            i = i >> 1
        i = 2
        while i <= 8:
            j := 1
            while j < i:
                hh[i + j] = hh[i] ^ hh[j]
                hl[i + j] = hl[i] ^ hl[j]
                j += 1
            i = i * 2
        self.hh = hh
        self.hl = hl

    # x (16 octets, liste) multiplié par H dans GF(2^128) : [haut, bas] (deux mots de 64 bits).
    func _mult(x):
        hh := self.hh
        hl := self.hl
        lo := x[15] & 15
        zh := hh[lo]
        zl := hl[lo]
        i := 15
        while i >= 0:
            lo = x[i] & 15
            hi := x[i] >> 4
            if i != 15:
                rem := zl & 15
                zl = (zh << 60) | _shr(zl, 4)
                zh = _shr(zh, 4) ^ (_LAST4[rem] << 48)
                zh = zh ^ hh[lo]
                zl = zl ^ hl[lo]
            rem := zl & 15
            zl = (zh << 60) | _shr(zl, 4)
            zh = _shr(zh, 4) ^ (_LAST4[rem] << 48)
            zh = zh ^ hh[hi]
            zl = zl ^ hl[hi]
            i -= 1
        return [zh, zl]

    # GHASH(H, A, C) (SP 800-38D, 6.4) : 16 octets.
    func ghash(aad, ct):
        y := [0] * 16
        for part in [aad, ct]:
            n := len(part)
            i := 0
            while i < n:
                j := 0
                while j < 16:
                    if i + j < n:
                        y[j] = y[j] ^ part[i + j]
                    j += 1
                y = self._words_to_bytes(self._mult(y))
                i += 16
        lens := []
        _put64(lens, len(aad) * 8)
        _put64(lens, len(ct) * 8)
        j := 0
        while j < 16:
            y[j] = y[j] ^ lens[j]
            j += 1
        return self._words_to_bytes(self._mult(y))

    func _words_to_bytes(z):
        out := []
        _put64(out, z[0])
        _put64(out, z[1])
        return out

    func _j0(nonce):
        if len(nonce) != 12:
            _fail("nonce de 12 octets attendu (obtenu " + str(len(nonce)) + ")")
        return nonce + [0, 0, 0, 1]

    func _tag(j0, aad, ct):
        s := self.ghash(aad, ct)
        e := _aes.encrypt_block(self.key, j0)
        return [s[i] ^ e[i] for i in _range(16)]

    # Chiffré || étiquette.
    func seal(nonce, plaintext, aad=null):
        a := aad if aad != null else []
        if self.fast:
            if len(nonce) != 12:
                _fail("nonce de 12 octets attendu (obtenu " + str(len(nonce)) + ")")
            return _s.byte_unpack(_ax.native().aes_gcm(true, self.raw, _s.byte_pack(nonce), _s.byte_pack(plaintext), _s.byte_pack(a)))
        j0 := self._j0(nonce)
        ct := _aes.ctr(self.key, _inc32(j0), plaintext)
        return ct + self._tag(j0, a, ct)

    # Clair si l'étiquette est bonne (comparaison en temps constant), sinon AuthenticationError.
    func open(nonce, sealed, aad=null):
        a := aad if aad != null else []
        if len(sealed) < 16:
            raise("AuthenticationError", "gcm : message trop court")
        if self.fast:
            if len(nonce) != 12:
                _fail("nonce de 12 octets attendu (obtenu " + str(len(nonce)) + ")")
            r := _ax.native().aes_gcm(false, self.raw, _s.byte_pack(nonce), _s.byte_pack(sealed), _s.byte_pack(a))
            if r == null:
                raise("AuthenticationError", "gcm : étiquette d'authentification invalide")
            return _s.byte_unpack(r)
        j0 := self._j0(nonce)
        ct := sealed[0:len(sealed) - 16]
        tag := sealed[len(sealed) - 16:len(sealed)]
        want := self._tag(j0, a, ct)
        diff := 0
        i := 0
        while i < 16:
            diff = diff | (want[i] ^ tag[i])
            i += 1
        if diff != 0:
            raise("AuthenticationError", "gcm : étiquette d'authentification invalide")
        return _aes.ctr(self.key, _inc32(j0), ct)

func _inc32(b):
    c := ((b[12] << 24) | (b[13] << 16) | (b[14] << 8) | b[15]) + 1
    c = c & _M32
    return b[0:12] + [c >> 24, (c >> 16) & 255, (c >> 8) & 255, c & 255]

func _range(n):
    out := []
    i := 0
    while i < n:
        append(out, i)
        i += 1
    return out
