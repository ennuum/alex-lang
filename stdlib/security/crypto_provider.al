# ALEX STANDARD LIBRARY — security.crypto_provider
#
# Fournisseurs cryptographiques interchangeables, avec une API unique :
#   « openssl »  libcrypto (OpenSSL 3) par FFI, si elle est installée : SHA-2 natifs, PBKDF2 natif (EVP_KDF),
#                chiffrement authentifié ChaCha20-Poly1305 et AES-256-GCM (EVP_CIPHER) — rapide
#   « alex »     module crypto en ALEX pur (toujours disponible, lent) : SHA-2, HMAC, PBKDF2, et chiffrement
#                authentifié ChaCha20 + HMAC-SHA256 (« chiffrer puis authentifier »)
# provider() rend le meilleur disponible. Au-dessus : HKDF (RFC 5869), enveloppes chiffrées autoportantes
# (algorithme, nonce aléatoire, données associées authentifiées), hachage de mots de passe.
#
#   use security.crypto_provider as cp
#   p := cp.provider()                                  # OpenSSL si présent, sinon ALEX pur
#   print(p.name, p.hash_hex("sha256", "abc"))
#   cle := cp.generate_key()                            # 32 octets aléatoires (random_secure)
#   boite := cp.encrypt_text(cle, "message secret", "en-tête")    # texte base64 URL
#   print(cp.decrypt_text(cle, boite, "en-tête"))       # « message secret » ; SignatureError si altéré
#   h := cp.hash_password("correct horse")              # « pbkdf2_sha256$iter$sel$empreinte »
#   print(cp.verify_password("correct horse", h))       # true
#   sous_cle := cp.hkdf(cle, 32, "sel", "chiffrement")  # dérivation de clés
#
# Itérations PBKDF2 par défaut : 600 000 avec OpenSSL (recommandation OWASP), 2 000 en ALEX pur (≈ 3 s :
# l'implémentation interprétée est lente — préférer OpenSSL pour les mots de passe).
# Erreurs : SignatureError (authentification de l'enveloppe), SecurityError (algorithme indisponible, enveloppe
# invalide), ArgumentError (taille de clé), TypeError.

from core use len, type, to_int
from collections use append
use string as _s
use crypto as _c
use ffi as _ffi
use security.security as _sec
use security.random_secure as _rnd

const ALG_CHACHA_HMAC := 1
const ALG_CHACHA_POLY := 2
const ALG_AES_GCM := 3
const ALG_NAMES := {1: "chacha20-hmac-sha256", 2: "chacha20-poly1305", 3: "aes-256-gcm"}
const DIGEST_NAMES := {"sha256": "SHA256", "sha512": "SHA512", "sha1": "SHA1", "md5": "MD5"}

func _bytes(d):
    return _sec.to_bytes(d)

func _u64be(n):
    out := []
    i := 7
    while i >= 0:
        append(out, (n >> (8 * i)) & 255)
        i -= 1
    return out

# ---------------------------------------------------------------------------------------------------------
# ALEX pur
# ---------------------------------------------------------------------------------------------------------

class PureProvider:
    func init():
        self.name = "alex"
        self.default_iterations = 2000

    func hash(algo, data):
        return _c.hash_bytes(algo, _bytes(data))

    func hash_hex(algo, data):
        return _c.hex_encode(self.hash(algo, data))

    func hmac(algo, key, data):
        return _c.hmac_bytes(algo, _bytes(key), _bytes(data))

    func pbkdf2(password, salt, iterations, length, algo="sha256"):
        return _c.pbkdf2_bytes(_bytes(password), _bytes(salt), iterations, length, algo)

    func aead_algorithms():
        return [ALG_CHACHA_HMAC]

    func aead_seal(alg, key, nonce, plaintext, aad):
        if alg != ALG_CHACHA_HMAC:
            raise("SecurityError", "fournisseur alex : algorithme " + ALG_NAMES[alg] + " indisponible")
        return _chacha_hmac_seal(self, key, nonce, plaintext, aad)

    func aead_open(alg, key, nonce, ciphertext, tag, aad):
        if alg != ALG_CHACHA_HMAC:
            raise("SecurityError", "fournisseur alex : algorithme " + ALG_NAMES[alg] + " indisponible")
        return _chacha_hmac_open(self, key, nonce, ciphertext, tag, aad)

func _subkeys(p, key):
    return [hkdf_with(p, key, 32, [], "alex-aead-enc"), hkdf_with(p, key, 32, [], "alex-aead-mac")]

func _mac_input(nonce, aad, ct):
    return [65, 88, 1] + nonce + _u64be(len(aad)) + aad + ct

func _chacha_hmac_seal(p, key, nonce, plaintext, aad):
    ks := _subkeys(p, key)
    ct := _c.chacha20(ks[0], nonce, plaintext)
    tag := p.hmac("sha256", ks[1], _mac_input(nonce, aad, ct))
    return [ct, tag]

func _chacha_hmac_open(p, key, nonce, ct, tag, aad):
    ks := _subkeys(p, key)
    expect := p.hmac("sha256", ks[1], _mac_input(nonce, aad, ct))
    if not _sec.constant_time_equals(expect, tag):
        raise("SignatureError", "enveloppe chiffrée : authentification échouée (clé fausse ou données altérées)")
    return _c.chacha20(ks[0], nonce, ct)

# ---------------------------------------------------------------------------------------------------------
# OpenSSL (libcrypto) par FFI
# ---------------------------------------------------------------------------------------------------------

func _buf_of(bytes):
    n := len(bytes)
    if n == 0:
        n = 1
    b := _ffi.Buffer(n)
    if len(bytes) > 0:
        b.write_array("u8", bytes)
    return b

class OpenSslProvider:
    func init():
        self.name = "openssl"
        self.default_iterations = 600000
        lib := null
        for nm in ["crypto", "libcrypto.so.3", "libcrypto.so", "libcrypto.dylib"]:
            if lib == null:
                try:
                    lib = _ffi.Library(nm)
                catch e:
                    lib = null
        if lib == null:
            raise("SecurityError", "OpenSSL (libcrypto) introuvable")
        if not lib.has("EVP_KDF_fetch") or not lib.has("EVP_chacha20_poly1305"):
            raise("SecurityError", "OpenSSL 3 requis (EVP_KDF, EVP_chacha20_poly1305)")
        self.lib = lib
        f := {}
        f["md_by_name"] = lib.function("EVP_get_digestbyname", ["cstr"], "ptr")
        f["digest"] = lib.function("EVP_Digest", ["ptr", "u64", "ptr", "ptr", "ptr", "ptr"], "i32")
        f["kdf_fetch"] = lib.function("EVP_KDF_fetch", ["ptr", "cstr", "ptr"], "ptr")
        f["kdf_ctx_new"] = lib.function("EVP_KDF_CTX_new", ["ptr"], "ptr")
        f["kdf_derive"] = lib.function("EVP_KDF_derive", ["ptr", "ptr", "u64", "ptr"], "i32")
        f["kdf_ctx_free"] = lib.function("EVP_KDF_CTX_free", ["ptr"], "void")
        f["kdf_free"] = lib.function("EVP_KDF_free", ["ptr"], "void")
        f["ctx_new"] = lib.function("EVP_CIPHER_CTX_new", [], "ptr")
        f["ctx_free"] = lib.function("EVP_CIPHER_CTX_free", ["ptr"], "void")
        f["ctx_ctrl"] = lib.function("EVP_CIPHER_CTX_ctrl", ["ptr", "i32", "i32", "ptr"], "i32")
        f["enc_init"] = lib.function("EVP_EncryptInit_ex", ["ptr", "ptr", "ptr", "ptr", "ptr"], "i32")
        f["enc_update"] = lib.function("EVP_EncryptUpdate", ["ptr", "ptr", "ptr", "ptr", "i32"], "i32")
        f["enc_final"] = lib.function("EVP_EncryptFinal_ex", ["ptr", "ptr", "ptr"], "i32")
        f["dec_init"] = lib.function("EVP_DecryptInit_ex", ["ptr", "ptr", "ptr", "ptr", "ptr"], "i32")
        f["dec_update"] = lib.function("EVP_DecryptUpdate", ["ptr", "ptr", "ptr", "ptr", "i32"], "i32")
        f["dec_final"] = lib.function("EVP_DecryptFinal_ex", ["ptr", "ptr", "ptr"], "i32")
        f["chacha_poly"] = lib.function("EVP_chacha20_poly1305", [], "ptr")
        f["aes_gcm"] = lib.function("EVP_aes_256_gcm", [], "ptr")
        self.f = f
        self.mds = {}

    func _md(algo):
        a := _s.lower(algo)
        if not (a in DIGEST_NAMES):
            raise("ValueError", "algorithme de hachage inconnu '" + algo + "'")
        if not (a in self.mds):
            p := self.f["md_by_name"].call([DIGEST_NAMES[a]])
            if p == null or p == 0:
                raise("SecurityError", "OpenSSL : condensé " + algo + " indisponible")
            self.mds[a] = p
        return self.mds[a]

    func hash(algo, data):
        b := _bytes(data)
        inb := _buf_of(b)
        out := _ffi.Buffer(64)
        sz := _ffi.Buffer(4)
        try:
            rc := self.f["digest"].call([inb.address(), len(b), out.address(), sz.address(), self._md(algo), null])
            if rc != 1:
                raise("SecurityError", "OpenSSL : EVP_Digest a échoué")
            return out.read_array("u8", sz.read("u32"))
        finally:
            inb.free()
            out.free()
            sz.free()

    func hash_hex(algo, data):
        return _c.hex_encode(self.hash(algo, data))

    # HMAC (RFC 2104) sur le condensé natif.
    func hmac(algo, key, data):
        block := 64
        if _s.lower(algo) == "sha512":
            block = 128
        k := _bytes(key)
        if len(k) > block:
            k = self.hash(algo, k)
        while len(k) < block:
            append(k, 0)
        ipad := [x ^ 54 for x in k]
        opad := [x ^ 92 for x in k]
        inner := self.hash(algo, ipad + _bytes(data))
        return self.hash(algo, opad + inner)

    func pbkdf2(password, salt, iterations, length, algo="sha256"):
        pw := _bytes(password)
        sl := _bytes(salt)
        kdf := self.f["kdf_fetch"].call([null, "PBKDF2", null])
        if kdf == null or kdf == 0:
            raise("SecurityError", "OpenSSL : PBKDF2 indisponible")
        ctx := self.f["kdf_ctx_new"].call([kdf])
        names := _ffi.Buffer(64)
        names.write_str("pass", 0)
        names.write_str("salt", 8)
        names.write_str("iter", 16)
        names.write_str("digest", 24)
        names.write_str(DIGEST_NAMES[_s.lower(algo)], 32)
        pwb := _buf_of(pw)
        slb := _buf_of(sl)
        itb := _ffi.Buffer(8)
        itb.write("u64", iterations, 0)
        params := _ffi.Buffer(40 * 5)
        out := _ffi.Buffer(length)
        try:
            base := names.address()
            _param(params, 0, base, 5, pwb.address(), len(pw))
            _param(params, 1, base + 8, 5, slb.address(), len(sl))
            _param(params, 2, base + 16, 2, itb.address(), 8)
            _param(params, 3, base + 24, 4, base + 32, len(DIGEST_NAMES[_s.lower(algo)]))
            rc := self.f["kdf_derive"].call([ctx, out.address(), length, params.address()])
            if rc != 1:
                raise("SecurityError", "OpenSSL : EVP_KDF_derive a échoué")
            return out.read_array("u8", length)
        finally:
            self.f["kdf_ctx_free"].call([ctx])
            self.f["kdf_free"].call([kdf])
            names.free()
            pwb.free()
            slb.free()
            itb.free()
            params.free()
            out.free()

    func aead_algorithms():
        return [ALG_CHACHA_POLY, ALG_AES_GCM, ALG_CHACHA_HMAC]

    func _cipher(alg):
        if alg == ALG_CHACHA_POLY:
            return self.f["chacha_poly"].call([])
        if alg == ALG_AES_GCM:
            return self.f["aes_gcm"].call([])
        raise("SecurityError", "algorithme inconnu " + str(alg))

    func aead_seal(alg, key, nonce, plaintext, aad):
        if alg == ALG_CHACHA_HMAC:
            return _chacha_hmac_seal(self, key, nonce, plaintext, aad)
        f := self.f
        ctx := f["ctx_new"].call([])
        kb := _buf_of(key)
        nb := _buf_of(nonce)
        ab := _buf_of(aad)
        pb := _buf_of(plaintext)
        out := _ffi.Buffer(len(plaintext) + 32)
        outl := _ffi.Buffer(4)
        tag := _ffi.Buffer(16)
        try:
            _ok(f["enc_init"].call([ctx, self._cipher(alg), null, kb.address(), nb.address()]), "EncryptInit")
            if len(aad) > 0:
                _ok(f["enc_update"].call([ctx, null, outl.address(), ab.address(), len(aad)]), "EncryptUpdate(aad)")
            n := 0
            if len(plaintext) > 0:
                _ok(f["enc_update"].call([ctx, out.address(), outl.address(), pb.address(), len(plaintext)]), "EncryptUpdate")
                n = outl.read("i32")
            _ok(f["enc_final"].call([ctx, out.address() + n, outl.address()]), "EncryptFinal")
            n += outl.read("i32")
            _ok(f["ctx_ctrl"].call([ctx, 16, 16, tag.address()]), "GET_TAG")
            return [out.read_array("u8", n), tag.read_array("u8", 16)]
        finally:
            f["ctx_free"].call([ctx])
            kb.free()
            nb.free()
            ab.free()
            pb.free()
            out.free()
            outl.free()
            tag.free()

    func aead_open(alg, key, nonce, ct, tag, aad):
        if alg == ALG_CHACHA_HMAC:
            return _chacha_hmac_open(self, key, nonce, ct, tag, aad)
        f := self.f
        ctx := f["ctx_new"].call([])
        kb := _buf_of(key)
        nb := _buf_of(nonce)
        ab := _buf_of(aad)
        cb := _buf_of(ct)
        tb := _buf_of(tag)
        out := _ffi.Buffer(len(ct) + 32)
        outl := _ffi.Buffer(4)
        try:
            _ok(f["dec_init"].call([ctx, self._cipher(alg), null, kb.address(), nb.address()]), "DecryptInit")
            if len(aad) > 0:
                _ok(f["dec_update"].call([ctx, null, outl.address(), ab.address(), len(aad)]), "DecryptUpdate(aad)")
            n := 0
            if len(ct) > 0:
                _ok(f["dec_update"].call([ctx, out.address(), outl.address(), cb.address(), len(ct)]), "DecryptUpdate")
                n = outl.read("i32")
            _ok(f["ctx_ctrl"].call([ctx, 17, len(tag), tb.address()]), "SET_TAG")
            rc := f["dec_final"].call([ctx, out.address() + n, outl.address()])
            if rc != 1:
                raise("SignatureError", "enveloppe chiffrée : authentification échouée (clé fausse ou données altérées)")
            n += outl.read("i32")
            return out.read_array("u8", n)
        finally:
            f["ctx_free"].call([ctx])
            kb.free()
            nb.free()
            ab.free()
            cb.free()
            tb.free()
            out.free()
            outl.free()

func _ok(rc, what):
    if rc != 1:
        raise("SecurityError", "OpenSSL : " + what + " a échoué")

# OSSL_PARAM { const char *key; unsigned int data_type; void *data; size_t data_size; size_t return_size; }
func _param(buf, i, key_addr, data_type, data_addr, size):
    o := i * 40
    buf.write("u64", key_addr, o)
    buf.write("u32", data_type, o + 8)
    buf.write("u64", data_addr, o + 16)
    buf.write("u64", size, o + 24)
    buf.write("i64", -1, o + 32)

# ---------------------------------------------------------------------------------------------------------
# Choix du fournisseur
# ---------------------------------------------------------------------------------------------------------

_providers := {}
_best := [null]

func get_provider(name):
    if name in _providers:
        return _providers[name]
    p := null
    if name == "alex":
        p = PureProvider()
    elif name == "openssl":
        p = OpenSslProvider()
    else:
        raise("SecurityError", "fournisseur cryptographique inconnu '" + name + "'")
    _providers[name] = p
    return p

func register(p):
    _providers[p.name] = p
    return p

func available():
    out := ["alex"]
    try:
        get_provider("openssl")
        out = ["openssl", "alex"]
    catch e:
        out = ["alex"]
    return out

func provider():
    if _best[0] == null:
        try:
            _best[0] = get_provider("openssl")
        catch e:
            _best[0] = get_provider("alex")
    return _best[0]

func use_provider(name):
    _best[0] = get_provider(name)
    return _best[0]

# ---------------------------------------------------------------------------------------------------------
# API de haut niveau
# ---------------------------------------------------------------------------------------------------------

func hash(algo, data):
    return provider().hash(algo, data)

func hash_hex(algo, data):
    return provider().hash_hex(algo, data)

func hmac(algo, key, data):
    return provider().hmac(algo, key, data)

func hmac_hex(algo, key, data):
    return _c.hex_encode(hmac(algo, key, data))

func verify_hmac(algo, key, data, mac):
    m := mac
    if type(mac) == "str":
        m = _c.hex_decode(mac)
    return _sec.constant_time_equals(hmac(algo, key, data), m)

# HKDF-SHA256 (RFC 5869) avec un fournisseur donné.
func hkdf_with(p, ikm, length, salt=null, info="", algo="sha256"):
    hl := 32
    if algo == "sha512":
        hl = 64
    s := salt
    if s == null or len(s) == 0:
        s = [0 for i in 0..hl]
    prk := p.hmac(algo, _bytes(s), _bytes(ikm))
    out := []
    prev := []
    i := 1
    inf := _bytes(info)
    while len(out) < length:
        prev = p.hmac(algo, prk, prev + inf + [i])
        out = out + prev
        i += 1
    return out[:length]

func hkdf(ikm, length=32, salt=null, info=""):
    return hkdf_with(provider(), ikm, length, salt, info)

func pbkdf2(password, salt, iterations, length=32, algo="sha256"):
    return provider().pbkdf2(password, salt, iterations, length, algo)

func generate_key(n=32):
    return _rnd.random_bytes(n)

func _alg_id(name):
    if name == null:
        p := provider()
        return p.aead_algorithms()[0]
    for k in ALG_NAMES:
        if ALG_NAMES[k] == name:
            return k
    raise("SecurityError", "algorithme de chiffrement inconnu '" + name + "' (chacha20-poly1305, aes-256-gcm, chacha20-hmac-sha256)")

func _need_key(key):
    k := _bytes(key)
    if len(k) != 32:
        raise("ArgumentError", "clé de 32 octets attendue (obtenu " + str(len(k)) + ")")
    return k

# Enveloppe : « AX » 1 alg nonce(12) chiffré étiquette ; liste d'octets.
func seal(key, plaintext, aad="", algorithm=null):
    k := _need_key(key)
    alg := _alg_id(algorithm)
    p := provider()
    if not (alg in p.aead_algorithms()):
        p = get_provider("openssl")
    nonce := _rnd.random_bytes(12)
    a := _bytes(aad)
    r := p.aead_seal(alg, k, nonce, _bytes(plaintext), a)
    return [65, 88, 1, alg] + nonce + r[0] + r[1]

func open(key, envelope, aad=""):
    k := _need_key(key)
    e := _bytes(envelope)
    if len(e) < 16 or e[0] != 65 or e[1] != 88 or e[2] != 1:
        raise("SecurityError", "enveloppe chiffrée invalide (en-tête)")
    alg := e[3]
    if not (alg in ALG_NAMES):
        raise("SecurityError", "enveloppe chiffrée : algorithme inconnu " + str(alg))
    tl := 16
    if alg == ALG_CHACHA_HMAC:
        tl = 32
    if len(e) < 16 + tl:
        raise("SecurityError", "enveloppe chiffrée tronquée")
    nonce := e[4:16]
    ct := e[16:len(e) - tl]
    tag := e[len(e) - tl:]
    p := provider()
    if not (alg in p.aead_algorithms()):
        p = get_provider("openssl")
    return p.aead_open(alg, k, nonce, ct, tag, _bytes(aad))

func encrypt_text(key, text, aad="", algorithm=null):
    return _c.base64_encode(seal(key, text, aad, algorithm), true)

func decrypt_text(key, token, aad=""):
    return _c.utf8_decode(open(key, _c.base64_decode(token, true), aad))

func envelope_algorithm(token):
    e := _c.base64_decode(token, true)
    if len(e) < 4:
        return null
    return ALG_NAMES[e[3]]

# « pbkdf2_sha256$itérations$sel$empreinte » (sel et empreinte en base64 URL).
func hash_password(password, iterations=null):
    p := provider()
    it := iterations
    if it == null:
        it = p.default_iterations
    salt := _rnd.random_bytes(16)
    dk := p.pbkdf2(password, salt, it, 32)
    return "pbkdf2_sha256$" + str(it) + "$" + _c.base64_encode(salt, true) + "$" + _c.base64_encode(dk, true)

func verify_password(password, stored):
    parts := _s.split(stored, "$")
    if len(parts) != 4 or parts[0] != "pbkdf2_sha256":
        return false
    it := to_int(parts[1])
    salt := _c.base64_decode(parts[2], true)
    want := _c.base64_decode(parts[3], true)
    dk := provider().pbkdf2(password, salt, it, len(want))
    return _sec.constant_time_equals(dk, want)

func needs_rehash(stored, iterations=null):
    parts := _s.split(stored, "$")
    if len(parts) != 4 or parts[0] != "pbkdf2_sha256":
        return true
    it := iterations
    if it == null:
        it = provider().default_iterations
    return to_int(parts[1]) < it
