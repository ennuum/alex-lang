# ALEX STANDARD LIBRARY — network.tls13
#
# Serveur TLS 1.3 (RFC 8446) écrit en ALEX pur, sans OpenSSL : HTTPS dans les exécutables natifs, qui ne chargent
# pas de bibliothèque C. Même interface que network.tls.TlsSocket : web.server s'en sert tel quel (HTTP/1.1, h2
# par ALPN, WebSocket, SSE, fichiers en arrière-plan).
#
#   use network.tls13 as tls13
#   ctx := tls13.ServerContext("site.pem", "site.key", ["h2", "http/1.1"])   # lus une fois, clé contrôlée
#   ts := tls13.wrap_server(sock, ctx, 10.0)          # poignée de main ; TlsSocket13 (send, recv, try_recv...)
#   ts.version, ts.cipher, ts.alpn, ts.server_name   # « TLSv1.3 », « TLS_AES_128_GCM_SHA256 », « h2 », SNI
#
# Pris en charge
#   suites      TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256 (dans cet ordre)
#   groupes     x25519, secp256r1, secp384r1 ; HelloRetryRequest quand le client n'a pas envoyé de part utilisable
#   signatures  ecdsa_secp256r1_sha256, ecdsa_secp384r1_sha384, rsa_pss_rsae_sha256 / 384 / 512
#   extensions  server_name (lu), ALPN (RFC 7301), supported_versions, key_share, signature_algorithms ;
#               KeyUpdate dans les deux sens ; enregistrements de compatibilité (change_cipher_spec)
#   reprise     tickets de session (NewSessionTicket, sans état : chiffrés en AES-256-GCM sous une clé tirée de
#               la clé privée, donc communs aux ouvriers et aux redémarrages ; ALEX_TLS_TICKET_KEY pour la fixer) ;
#               reprise en mode psk_dhe_ke (ECDHE conservé : confidentialité persistante), sans signature ni
#               certificat ; binder vérifié, aussi après HelloRetryRequest ; durée de vie : 1 jour par défaut
# Volontairement absent : TLS 1.2 et antérieurs (un tel client reçoit l'alerte protocol_version), 0-RTT (données
# précoces ignorées comme le prévoit la RFC), mode psk_ke sans ECDHE, certificats clients ; côté client, la
# reprise de session.
#
# Sécurité : enregistrements AEAD à nonce par numéro de séquence, Finished vérifié en temps constant, alertes
# fatales sur toute anomalie. LIMITES : AES par tables et grands entiers à temps variable (crypto.aes, crypto.ec,
# crypto.rsa) : pas de garantie contre les attaques par canaux auxiliaires. Erreurs : TlsError (poignée de main ou
# enregistrement refusé, alerte reçue), TimeoutError, NetworkError (socket), ValueError (certificat ou clé).

from core use len, type, to_int
from collections use append
use string as _s
use time as _time
use io as _io
use os as _os
use crypto as _c
use crypto.hkdf as _hkdf
use crypto.gcm as _gcm
use crypto.poly1305 as _p1305
use crypto.x25519 as _x25519
use crypto.ec as _ec
use crypto.rsa as _rsa
use crypto.x509 as _x509
use crypto.accel as _ax
use security.random_secure as _rnd

# Types d'enregistrements et de messages.
CT_CCS := 20
CT_ALERT := 21
CT_HANDSHAKE := 22
CT_APP := 23

HS_CLIENT_HELLO := 1
HS_SERVER_HELLO := 2
HS_NEW_SESSION_TICKET := 4
HS_END_OF_EARLY_DATA := 5
HS_ENCRYPTED_EXTENSIONS := 8
HS_CERTIFICATE := 11
HS_CERTIFICATE_VERIFY := 15
HS_FINISHED := 20
HS_KEY_UPDATE := 24
HS_MESSAGE_HASH := 254

EXT_SERVER_NAME := 0
EXT_SUPPORTED_GROUPS := 10
EXT_SIGNATURE_ALGORITHMS := 13
EXT_ALPN := 16
EXT_PRE_SHARED_KEY := 41
EXT_PSK_MODES := 45
EXT_EARLY_DATA := 42
EXT_SUPPORTED_VERSIONS := 43
EXT_COOKIE := 44
EXT_KEY_SHARE := 51

# Alertes (RFC 8446, 6).
ALERT_CLOSE_NOTIFY := 0
ALERT_UNEXPECTED_MESSAGE := 10
ALERT_BAD_RECORD_MAC := 20
ALERT_RECORD_OVERFLOW := 22
ALERT_HANDSHAKE_FAILURE := 40
ALERT_ILLEGAL_PARAMETER := 47
ALERT_DECODE_ERROR := 50
ALERT_DECRYPT_ERROR := 51
ALERT_PROTOCOL_VERSION := 70
ALERT_INTERNAL_ERROR := 80
ALERT_MISSING_EXTENSION := 109
ALERT_NO_APPLICATION_PROTOCOL := 120

_ALERT_NAMES := {0: "close_notify", 10: "unexpected_message", 20: "bad_record_mac", 22: "record_overflow",
                 40: "handshake_failure", 42: "bad_certificate", 43: "unsupported_certificate",
                 44: "certificate_revoked", 45: "certificate_expired", 46: "certificate_unknown",
                 47: "illegal_parameter", 48: "unknown_ca", 50: "decode_error", 51: "decrypt_error",
                 70: "protocol_version", 71: "insufficient_security", 80: "internal_error", 86: "inappropriate_fallback",
                 90: "user_canceled", 109: "missing_extension", 110: "unsupported_extension",
                 112: "unrecognized_name", 116: "certificate_required", 120: "no_application_protocol"}

# Suites, par ordre de préférence du serveur.
SUITES := {4865: {"name": "TLS_AES_128_GCM_SHA256", "hash": "sha256", "key": 16, "aead": "gcm"},
           4866: {"name": "TLS_AES_256_GCM_SHA384", "hash": "sha384", "key": 32, "aead": "gcm"},
           4867: {"name": "TLS_CHACHA20_POLY1305_SHA256", "hash": "sha256", "key": 32, "aead": "chacha"}}
SUITE_ORDER := [4865, 4866, 4867]

GROUP_X25519 := 29
GROUP_P256 := 23
GROUP_P384 := 24
GROUP_ORDER := [29, 23, 24]
_GROUP_NAMES := {29: "x25519", 23: "secp256r1", 24: "secp384r1"}

SIG_ECDSA_P256 := 1027       # 0x0403
SIG_ECDSA_P384 := 1283       # 0x0503
SIG_RSA_PSS_256 := 2052      # 0x0804
SIG_RSA_PSS_384 := 2053
SIG_RSA_PSS_512 := 2054

_HRR_RANDOM := [207, 33, 173, 116, 229, 154, 97, 17, 190, 29, 140, 2, 30, 101, 184, 145,
                194, 162, 17, 22, 122, 187, 140, 94, 7, 158, 9, 226, 200, 168, 51, 156]

MAX_PLAINTEXT := 16384
MAX_CIPHERTEXT := 16384 + 256
_MAX_HANDSHAKE := 65536
_EARLY_DATA_BUDGET := 65536

# ---------------------------------------------------------------- erreurs

# Anomalie de protocole : alerte desc à envoyer, puis TlsError.
func _abort(desc, message):
    raise("TlsAlert", str(desc) + "|" + message)

func _alert_name(d):
    if d in _ALERT_NAMES:
        return _ALERT_NAMES[d]
    return "alerte " + str(d)

func _split_abort(msg):
    i := _s.find(msg, "|")
    if i < 0:
        return [ALERT_INTERNAL_ERROR, msg]
    return [to_int(_s.substring(msg, 0, i)), _s.substring(msg, i + 1, len(msg))]

# ---------------------------------------------------------------- octets

func _u16(n):
    return [(n >> 8) & 255, n & 255]

func _u24(n):
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255]

func _u32(n):
    return [(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255]

func _vec8(b):
    return [len(b)] + b

func _vec16(b):
    return _u16(len(b)) + b

func _vec24(b):
    return _u24(len(b)) + b

func _msg(t, body):
    return [t] + _u24(len(body)) + body

func _ext(code, body):
    return _u16(code) + _vec16(body)

# Lecture bornée d'un message : toute sortie des bornes est une decode_error.
class _Reader:
    func init(b, start=0, end=null):
        self.b = b
        self.i = start
        self.end = end if end != null else len(b)

    func _need(n):
        if self.i + n > self.end:
            _abort(ALERT_DECODE_ERROR, "message tronqué")

    func u8():
        self._need(1)
        v := self.b[self.i]
        self.i += 1
        return v

    func u16():
        self._need(2)
        v := (self.b[self.i] << 8) | self.b[self.i + 1]
        self.i += 2
        return v

    func u24():
        self._need(3)
        v := (self.b[self.i] << 16) | (self.b[self.i + 1] << 8) | self.b[self.i + 2]
        self.i += 3
        return v

    func take(n):
        self._need(n)
        v := self.b[self.i:self.i + n]
        self.i += n
        return v

    func vec8():
        return self.take(self.u8())

    func vec16():
        return self.take(self.u16())

    func vec24():
        return self.take(self.u24())

    func done():
        return self.i >= self.end

    func finish(what):
        if self.i != self.end:
            _abort(ALERT_DECODE_ERROR, what + " : octets en trop")

func _u16_list(b, what, minimum=2):
    if len(b) < minimum or len(b) % 2 != 0:
        _abort(ALERT_DECODE_ERROR, what + " : liste invalide")
    out := []
    i := 0
    while i < len(b):
        append(out, (b[i] << 8) | b[i + 1])
        i += 2
    return out

# ---------------------------------------------------------------- ordonnancement des clés (RFC 8446, 7.1)

func _hash(h, data):
    return _ax.hash(h, data)

func _hmac(h, key, data):
    return _ax.hmac(h, key, data)

func expand_label(h, secret, label, context, length):
    full := _c.utf8_encode("tls13 " + label)
    info := _u16(length) + [len(full)] + full + [len(context)] + context
    return _hkdf.expand(h, secret, info, length)

func derive_secret(h, secret, label, transcript_hash):
    return expand_label(h, secret, label, transcript_hash, len(transcript_hash))

# Protection d'un sens du trafic : clé et IV tirés du secret, nonce = IV xor numéro de séquence.
class _Aead:
    func init(suite, secret):
        self.suite = suite
        self.secret = secret
        self.seq = 0
        h := suite["hash"]
        self.key = expand_label(h, secret, "key", [], suite["key"])
        self.iv = expand_label(h, secret, "iv", [], 12)
        # AES-GCM du runtime (crypto.accel) : chiffrement direct des str, sans listes d'octets
        self.native = _ax.native() if suite["aead"] == "gcm" and _ax.has("aes_gcm") else null
        self.raw_key = _s.byte_pack(self.key)
        self.gcm = _gcm.AesGcm(self.key) if suite["aead"] == "gcm" and self.native == null else null

    # Enregistrement protégé (str) : clair intérieur (str) chiffré, étiquette comprise ; header : en-tête (str).
    func seal_str(inner, header):
        if self.native != null:
            return self.native.aes_gcm(true, self.raw_key, _s.byte_pack(self._nonce()), inner, header)
        return _s.byte_pack(self.seal(_s.byte_unpack(inner), _s.byte_unpack(header)))

    # Clair intérieur (str), ou null si l'authentification échoue.
    func open_str(body, header):
        if self.native != null:
            return self.native.aes_gcm(false, self.raw_key, _s.byte_pack(self._nonce()), body, header)
        r := self.open(_s.byte_unpack(body), _s.byte_unpack(header))
        return _s.byte_pack(r) if r != null else null

    func _nonce():
        n := self.iv[0:12]
        s := self.seq
        i := 11
        while s > 0:
            n[i] = n[i] ^ (s & 255)
            s = s >> 8
            i -= 1
        self.seq += 1
        return n

    func seal(plaintext, aad):
        nonce := self._nonce()
        if self.gcm != null:
            return self.gcm.seal(nonce, plaintext, aad)
        return _p1305.seal(self.key, nonce, plaintext, aad)

    # null si l'authentification échoue.
    func open(ciphertext, aad):
        nonce := self._nonce()
        try:
            if self.gcm != null:
                return self.gcm.open(nonce, ciphertext, aad)
            return _p1305.open(self.key, nonce, ciphertext, aad)
        catch e:
            if e.type == "AuthenticationError" or e.type == "ValueError":
                return null
            raise(e)

    # Secret suivant (KeyUpdate).
    func next():
        h := self.suite["hash"]
        return _Aead(self.suite, expand_label(h, self.secret, "traffic upd", [], len(self.secret)))

# ---------------------------------------------------------------- certificat et clé du serveur

_contexts := {}

class ServerContext:
    # Chaîne de certificats (PEM, feuille d'abord) et clé privée (PEM : PKCS#8, SEC1 ou PKCS#1), lues une fois.
    # alpn : protocoles acceptés par ordre de préférence (null : pas d'ALPN). options : {"suites": [codes],
    # "groups": [codes]} pour restreindre ou réordonner (préférence du serveur). ValueError si la clé ne
    # correspond pas au certificat, ou si la clé n'est pas prise en charge.
    func init(cert_file, key_file, alpn=null, options=null):
        self.cert_file = cert_file
        self.key_file = key_file
        self.alpn = alpn
        self.options = options
        o := options if options != null else {}
        self.tickets = o["tickets"] if "tickets" in o else true
        self.ticket_lifetime = o["ticket_lifetime"] if "ticket_lifetime" in o else 86400
        if self.ticket_lifetime < 1 or self.ticket_lifetime > 604800:
            raise("ValueError", "tls13 : ticket_lifetime hors de 1..604800 secondes")
        self.resumptions = 0
        self.suites = o["suites"] if "suites" in o else SUITE_ORDER
        self.groups = o["groups"] if "groups" in o else GROUP_ORDER
        for c in self.suites:
            if not (c in SUITES):
                raise("ValueError", "tls13 : suite inconnue " + str(c))
        for g in self.groups:
            if not (g in GROUP_ORDER):
                raise("ValueError", "tls13 : groupe inconnu " + str(g))
        self.certificates = _x509.load_certificates(_io.read_raw(cert_file))
        self.key = _x509.load_private_key(_io.read_raw(key_file))
        if self.certificates[0].public_key == null:
            raise("ValueError", "tls13 : clé du certificat « " + cert_file + " » non prise en charge (" + str(self.certificates[0].curve) + ")")
        if not _x509.key_matches(self.certificates[0], self.key):
            raise("ValueError", "tls13 : la clé privée « " + key_file + " » ne correspond pas au certificat « " + cert_file + " »")
        self.chain = []
        for c in self.certificates:
            append(self.chain, c.der)
        self.stamp = _stamp(cert_file, key_file)
        # clé des tickets : tirée de la clé privée (mêmes tickets pour tous les ouvriers et après un
        # redémarrage, nouvelle clé avec un nouveau certificat), ou de ALEX_TLS_TICKET_KEY
        fixed := _os.getenv("ALEX_TLS_TICKET_KEY")
        ikm := _c.utf8_encode(fixed) if fixed != null and fixed != "" else _s.byte_unpack(_io.read_raw(key_file))
        self.ticket_key = _s.byte_pack(_hkdf.extract("sha256", _c.utf8_encode("alex tls13 tickets"), ikm))
        self.cert_msg = null
        self.handshakes = 0

    # Ticket de session : [1] || nonce (12) || AES-256-GCM(état) ; état : suite, date de création, masque
    # d'âge, ALPN, SNI, clé pré-partagée.
    func seal_ticket(suite, created, age_add, alpn, sni, psk):
        body := _u16(suite) + _u32(created >> 32) + _u32(created & 4294967295) + _u32(age_add)
        body = body + _vec8(_c.utf8_encode(alpn if alpn != null else "")) + _vec8(_c.utf8_encode(sni if sni != null else "")) + _vec8(psk)
        nonce := _rnd.random_bytes(12)
        ct := _ax.native().aes_gcm(true, self.ticket_key, _s.byte_pack(nonce), _s.byte_pack(body), _s.byte_pack([1])) if _ax.has("aes_gcm") else _s.byte_pack(_gcm.AesGcm(_s.byte_unpack(self.ticket_key)).seal(nonce, body, [1]))
        return [1] + nonce + _s.byte_unpack(ct)

    # État d'un ticket {suite, created, age_add, alpn, sni, psk}, ou null s'il n'est pas de ce serveur.
    func open_ticket(ticket):
        if len(ticket) < 1 + 12 + 16 or ticket[0] != 1:
            return null
        nonce := ticket[1:13]
        body := null
        try:
            if _ax.has("aes_gcm"):
                r := _ax.native().aes_gcm(false, self.ticket_key, _s.byte_pack(nonce), _s.byte_pack(ticket[13:len(ticket)]), _s.byte_pack([1]))
                body = _s.byte_unpack(r) if r != null else null
            else:
                body = _gcm.AesGcm(_s.byte_unpack(self.ticket_key)).open(nonce, ticket[13:len(ticket)], [1])
        catch e:
            body = null
        if body == null:
            return null
        try:
            r := _Reader(body)
            st := {"suite": r.u16()}
            hi := (r.u16() << 16) | r.u16()
            lo := (r.u16() << 16) | r.u16()
            st["created"] = (hi << 32) | lo
            st["age_add"] = (r.u16() << 16) | r.u16()
            st["alpn"] = _s.byte_pack(r.vec8())
            st["sni"] = _s.byte_pack(r.vec8())
            st["psk"] = r.vec8()
            r.finish("ticket")
            return st
        catch e:
            return null

    # Message Certificate (str), construit une fois.
    func certificate_message():
        if self.cert_msg == null:
            entries := []
            for d in self.chain:
                entries = entries + _vec24(d) + [0, 0]
            self.cert_msg = _s.byte_pack(_msg(HS_CERTIFICATE, [0] + _vec24(entries)))
        return self.cert_msg

    # Schéma de signature choisi parmi ceux du client, ou null.
    func signature_scheme(offered):
        if self.key.kind == "ec":
            want := SIG_ECDSA_P256 if self.key.curve == "P-256" else SIG_ECDSA_P384
            return want if want in offered else null
        for s in [SIG_RSA_PSS_256, SIG_RSA_PSS_384, SIG_RSA_PSS_512]:
            if s in offered:
                return s
        return null

    func sign(scheme, content):
        if scheme == SIG_ECDSA_P256:
            return _ec.sign_der(self.key.key, content, "sha256")
        if scheme == SIG_ECDSA_P384:
            return _ec.sign_der(self.key.key, content, "sha384")
        algo := "sha256" if scheme == SIG_RSA_PSS_256 else ("sha384" if scheme == SIG_RSA_PSS_384 else "sha512")
        return _rsa.sign_pss(self.key.key, content, algo)

func _stamp(cert_file, key_file):
    try:
        return str(_os.mtime(cert_file)) + "/" + str(_os.mtime(key_file))
    catch e:
        return ""

# Contexte mémorisé pour ce couple de fichiers (relu si l'un d'eux a changé : renouvellement de certificat).
func context(cert_file, key_file, alpn=null, options=null):
    k := cert_file + "\n" + key_file + "\n" + str(alpn) + "\n" + str(options)
    if k in _contexts:
        c := _contexts[k]
        if c.stamp == _stamp(cert_file, key_file):
            return c
    c := ServerContext(cert_file, key_file, alpn, options)
    _contexts[k] = c
    return c

# ---------------------------------------------------------------- ClientHello

class _Hello:
    func init():
        self.session_id = []
        self.suites = []
        self.exts = {}
        self.ext_order = []
        self.versions = []
        self.groups = []
        self.shares = []
        self.sigalgs = []
        self.alpn = null
        self.server_name = null
        self.early_data = false
        self.psk_modes = []
        self.psk_ids = []                # [identité (octets), âge masqué]
        self.binders = []
        self.binders_len = 0             # octets du vecteur des binders (longueur comprise), en fin de message

func _parse_client_hello(body):
    r := _Reader(body)
    hello := _Hello()
    r.u16()                                    # legacy_version
    r.take(32)                                 # random
    hello.session_id = r.vec8()
    if len(hello.session_id) > 32:
        _abort(ALERT_ILLEGAL_PARAMETER, "legacy_session_id trop long")
    hello.suites = _u16_list(r.vec16(), "cipher_suites")
    comp := r.vec8()
    if r.done():
        _abort(ALERT_PROTOCOL_VERSION, "ClientHello sans extensions : TLS 1.3 exigé")
    er := _Reader(r.vec16())
    r.finish("ClientHello")
    while not er.done():
        code := er.u16()
        data := er.vec16()
        if code in hello.exts:
            _abort(ALERT_ILLEGAL_PARAMETER, "extension " + str(code) + " en double")
        hello.exts[code] = data
        append(hello.ext_order, code)
    if not (EXT_SUPPORTED_VERSIONS in hello.exts):
        _abort(ALERT_PROTOCOL_VERSION, "le client ne propose pas TLS 1.3 (TLS 1.2 et antérieurs non pris en charge)")
    sv := _Reader(hello.exts[EXT_SUPPORTED_VERSIONS])
    hello.versions = _u16_list(sv.vec8(), "supported_versions")
    sv.finish("supported_versions")
    if not (772 in hello.versions):
        _abort(ALERT_PROTOCOL_VERSION, "le client ne propose pas TLS 1.3 (TLS 1.2 et antérieurs non pris en charge)")
    if len(comp) != 1 or comp[0] != 0:
        _abort(ALERT_ILLEGAL_PARAMETER, "compression proposée")
    if EXT_PRE_SHARED_KEY in hello.exts and hello.ext_order[len(hello.ext_order) - 1] != EXT_PRE_SHARED_KEY:
        _abort(ALERT_ILLEGAL_PARAMETER, "pre_shared_key doit être la dernière extension")
    if EXT_SUPPORTED_GROUPS in hello.exts:
        g := _Reader(hello.exts[EXT_SUPPORTED_GROUPS])
        hello.groups = _u16_list(g.vec16(), "supported_groups")
        g.finish("supported_groups")
    if EXT_KEY_SHARE in hello.exts:
        k := _Reader(hello.exts[EXT_KEY_SHARE])
        kr := _Reader(k.vec16())
        k.finish("key_share")
        seen := []
        while not kr.done():
            grp := kr.u16()
            ke := kr.vec16()
            if len(ke) == 0:
                _abort(ALERT_DECODE_ERROR, "key_share vide")
            if grp in seen:
                _abort(ALERT_ILLEGAL_PARAMETER, "key_share : groupe en double")
            append(seen, grp)
            if not (grp in hello.groups):
                _abort(ALERT_ILLEGAL_PARAMETER, "key_share : groupe absent de supported_groups")
            append(hello.shares, [grp, ke])
    if EXT_SIGNATURE_ALGORITHMS in hello.exts:
        s := _Reader(hello.exts[EXT_SIGNATURE_ALGORITHMS])
        hello.sigalgs = _u16_list(s.vec16(), "signature_algorithms")
        s.finish("signature_algorithms")
    if EXT_ALPN in hello.exts:
        a := _Reader(hello.exts[EXT_ALPN])
        ar := _Reader(a.vec16())
        a.finish("ALPN")
        hello.alpn = []
        while not ar.done():
            p := ar.vec8()
            if len(p) == 0:
                _abort(ALERT_DECODE_ERROR, "ALPN : protocole vide")
            append(hello.alpn, _s.byte_pack(p))
        if len(hello.alpn) == 0:
            _abort(ALERT_DECODE_ERROR, "ALPN : liste vide")
    if EXT_SERVER_NAME in hello.exts:
        try:
            sn := _Reader(hello.exts[EXT_SERVER_NAME])
            lr := _Reader(sn.vec16())
            while not lr.done():
                kind := lr.u8()
                name := lr.vec16()
                if kind == 0 and hello.server_name == null:
                    hello.server_name = _s.byte_pack(name)
        catch e:
            if e.type != "TlsAlert":
                raise(e)
            _abort(ALERT_DECODE_ERROR, "server_name invalide")
    hello.early_data = EXT_EARLY_DATA in hello.exts
    if EXT_PSK_MODES in hello.exts:
        pm := _Reader(hello.exts[EXT_PSK_MODES])
        hello.psk_modes = pm.vec8()
        pm.finish("psk_key_exchange_modes")
    if EXT_PRE_SHARED_KEY in hello.exts:
        pr := _Reader(hello.exts[EXT_PRE_SHARED_KEY])
        ir := _Reader(pr.vec16())
        bl := pr.vec16()
        pr.finish("pre_shared_key")
        while not ir.done():
            ident := ir.vec16()
            age := (ir.u16() << 16) | ir.u16()
            if len(ident) == 0:
                _abort(ALERT_DECODE_ERROR, "pre_shared_key : identité vide")
            append(hello.psk_ids, [ident, age])
        br := _Reader(bl)
        while not br.done():
            b := br.vec8()
            if len(b) < 32:
                _abort(ALERT_DECODE_ERROR, "pre_shared_key : binder trop court")
            append(hello.binders, b)
        if len(hello.psk_ids) == 0 or len(hello.psk_ids) != len(hello.binders):
            _abort(ALERT_ILLEGAL_PARAMETER, "pre_shared_key : identités et binders incohérents")
        hello.binders_len = 2 + len(bl)
    return hello

func _choose_suite(hello, order=null):
    for s in (order if order != null else SUITE_ORDER):
        if s in hello.suites:
            return s
    return null

# [groupe, part du client] pour une part utilisable ; [groupe, null] pour demander une part (HelloRetryRequest) ;
# null si aucun groupe commun.
func _choose_group(hello, order=null):
    groups := order if order != null else GROUP_ORDER
    for g in groups:
        for sh in hello.shares:
            if sh[0] == g:
                return [g, sh[1]]
    for g in groups:
        if g in hello.groups:
            return [g, null]
    return null

# Clé éphémère du serveur et secret partagé : [part publique, secret].
func _key_exchange(group, client_share):
    if group == GROUP_X25519:
        if len(client_share) != 32:
            _abort(ALERT_ILLEGAL_PARAMETER, "part x25519 de taille invalide")
        priv := _rnd.random_bytes(32)
        try:
            secret := _x25519.shared(priv, client_share)
            return [_x25519.public_key(priv), secret]
        catch e:
            _abort(ALERT_ILLEGAL_PARAMETER, "part x25519 refusée (point d'ordre faible)")
    name := "P-256" if group == GROUP_P256 else "P-384"
    c := _ec.curve(name)
    if len(client_share) != 1 + 2 * c.size or client_share[0] != 4:
        _abort(ALERT_ILLEGAL_PARAMETER, "part " + name + " : point non compressé attendu")
    pub := null
    try:
        pub = _ec.public_key(c, client_share)
    catch e:
        _abort(ALERT_ILLEGAL_PARAMETER, "part " + name + " : point hors de la courbe")
    priv := null
    while priv == null:
        try:
            priv = _ec.private_key(c, _rnd.random_bytes(c.size))
        catch e:
            priv = null
    return [priv.public_bytes(), _ec.ecdh(priv, pub)]

func _server_hello(random, session_id, suite, exts):
    body := _u16(771) + random + _vec8(session_id) + _u16(suite) + [0] + _vec16(exts)
    return _msg(HS_SERVER_HELLO, body)

# ---------------------------------------------------------------- enregistrements et premier vol du serveur

# Enregistrement(s) de type ct pour data (liste d'octets) : en clair si aead est null, sinon protégés (str).
func _protect(aead, ct, data):
    out := []
    i := 0
    while true:
        n := len(data) - i
        if n > MAX_PLAINTEXT:
            n = MAX_PLAINTEXT
        chunk := data[i:i + n]
        if aead == null:
            append(out, _s.byte_pack([ct, 3, 3] + _u16(len(chunk)) + chunk))
        else:
            header := _s.byte_pack([CT_APP, 3, 3] + _u16(len(chunk) + 17))
            append(out, header)
            append(out, aead.seal_str(_s.byte_pack(chunk + [ct]), header))
        i += n
        if i >= len(data):
            break
    return _s.byte_join(out)

# Enregistrement(s) de type ct pour data (str).
func _protect_str(aead, ct, data):
    n := _s.byte_len(data)
    out := []
    i := 0
    while true:
        m := n - i
        if m > MAX_PLAINTEXT:
            m = MAX_PLAINTEXT
        chunk := _s.byte_slice(data, i, i + m)
        if aead == null:
            append(out, _s.byte_pack([ct, 3, 3] + _u16(m)))
            append(out, chunk)
        else:
            header := _s.byte_pack([CT_APP, 3, 3] + _u16(m + 17))
            append(out, header)
            append(out, aead.seal_str(chunk + _s.byte_pack([ct]), header))
        i += m
        if i >= n:
            break
    return _s.byte_join(out)

# Empreinte d'un transcript tenu en str.
func _hash_s(h, data):
    if h == "sha256" and _ax.has("sha256"):
        return _s.byte_unpack(_ax.native().digest("sha256", data))
    return _hash(h, _s.byte_unpack(data))

_CV_PREFIX := [32] * 64 + _c.utf8_encode("TLS 1.3, server CertificateVerify") + [0]

# Calcul lourd de la poignée de main serveur, sans socket : échange de clés, ServerHello, EncryptedExtensions,
# Certificate, CertificateVerify (signature), Finished, secrets. args (copiables) : [suite, groupe, part du
# client, schéma de signature, legacy_session_id, transcript jusqu'au dernier ClientHello, ALPN choisi,
# change_cipher_spec déjà envoyé] (octets en str). Rend ["ok", vol (str), s_hs, c_hs, c_ap, s_ap, Finished
# attendu du client (str), numéro de séquence d'écriture] ou ["erreur", type, message] : jamais d'exception, pour
# que le message traverse les fils intact.
func _flight(ctx, args):
    try:
        return _flight_unsafe(ctx, args)
    catch e:
        return ["erreur", e.type, e.message]

func _flight_unsafe(ctx, args):
    P := _s.byte_pack
    suite_code := args[0]
    group := args[1]
    scheme := args[3]
    session_id := _s.byte_unpack(args[4])
    transcript := args[5]                      # str : les messages s'y ajoutent sans listes d'octets
    alpn := args[6]
    ccs_sent := args[7]
    psk := _s.byte_unpack(args[8]) if len(args) > 8 and args[8] != null else null
    suite := SUITES[suite_code]
    h := suite["hash"]
    kx := _key_exchange(group, _s.byte_unpack(args[2]))
    sh_exts := _ext(EXT_SUPPORTED_VERSIONS, _u16(772)) + _ext(EXT_KEY_SHARE, _u16(group) + _vec16(kx[0]))
    if psk != null:
        sh_exts = sh_exts + _ext(EXT_PRE_SHARED_KEY, _u16(0))
    sh := P(_server_hello(_rnd.random_bytes(32), session_id, suite_code, sh_exts))
    transcript = transcript + sh
    flight := _protect_str(null, CT_HANDSHAKE, sh)
    if len(session_id) > 0 and not ccs_sent:
        flight = flight + _protect(null, CT_CCS, [1])
    empty_hash := _hash(h, [])
    hl := len(empty_hash)
    zeros := [0] * hl
    early := _hkdf.extract(h, zeros, psk if psk != null else zeros)
    hs := _hkdf.extract(h, derive_secret(h, early, "derived", empty_hash), kx[1])
    th := _hash_s(h, transcript)
    c_hs := derive_secret(h, hs, "c hs traffic", th)
    s_hs := derive_secret(h, hs, "s hs traffic", th)
    exts := []
    if alpn != null:
        exts = _ext(EXT_ALPN, _vec16(_vec8(_c.utf8_encode(alpn))))
    ee := P(_msg(HS_ENCRYPTED_EXTENSIONS, _vec16(exts)))
    cert := ""
    cv := ""
    if psk == null:
        # reprise : ni certificat ni signature (l'authentification vient de la clé pré-partagée)
        cert = ctx.certificate_message()
        transcript = transcript + ee + cert
        content := _CV_PREFIX + _hash_s(h, transcript)
        cv = P(_msg(HS_CERTIFICATE_VERIFY, _u16(scheme) + _vec16(ctx.sign(scheme, content))))
        transcript = transcript + cv
    else:
        transcript = transcript + ee
    fin := P(_msg(HS_FINISHED, _hmac(h, expand_label(h, s_hs, "finished", [], hl), _hash_s(h, transcript))))
    transcript = transcript + fin
    w := _Aead(suite, s_hs)
    flight = flight + _protect_str(w, CT_HANDSHAKE, ee + cert + cv + fin)
    th2 := _hash_s(h, transcript)
    master := _hkdf.extract(h, derive_secret(h, hs, "derived", empty_hash), zeros)
    c_ap := derive_secret(h, master, "c ap traffic", th2)
    s_ap := derive_secret(h, master, "s ap traffic", th2)
    expected := _hmac(h, expand_label(h, c_hs, "finished", [], hl), th2)
    # secret de reprise : transcript jusqu'au Finished du client, dont le contenu est déjà connu
    res_master := derive_secret(h, master, "res master", _hash_s(h, transcript + P(_msg(HS_FINISHED, expected))))
    return ["ok", flight, P(s_hs), P(c_hs), P(c_ap), P(s_ap), P(expected), w.seq, P(res_master)]

# Point d'entrée de premier niveau pour un fil (thread.offload) : contexte relu (et gardé) dans le fil.
func server_flight(cert_file, key_file, alpn, options, args):
    ctx := null
    try:
        ctx = context(cert_file, key_file, alpn, options)
    catch e:
        return ["erreur", e.type, e.message]
    return _flight(ctx, args)

# ---------------------------------------------------------------- session

class TlsSocket13:
    func init(sock, ctx):
        self.socket = sock
        self.ctx = ctx
        self.family = sock.family
        self.kind = "tcp"
        self.timeout = null
        self.closed = false
        self.backend = "alex"
        self.version = "TLSv1.3"
        self.cipher = null
        self.alpn = null
        self.server_name = null
        self.group = null
        self.signature_scheme = null
        self.verify_result = null
        self.peer_subject = null
        self.peer_issuer = null
        self.rbuf = ""                 # octets reçus pas encore traités
        self.plain = ""                # données applicatives déchiffrées
        self.hsbuf = []                # messages de poignée de main en cours de réassemblage
        self.read_aead = null
        self.write_aead = null
        self.suite = null
        self.handshaking = true
        self.peer_closed = false       # close_notify reçu
        self.eof = false               # fin du flux TCP
        self.failed = null             # erreur fatale déjà signalée
        self.sent_close = false
        self.out = ""                  # chiffré pas encore parti (envoi sans attente)
        self.owed = 0                  # octets de clair déjà chiffrés et comptés à l'appel suivant
        self.early_budget = 0
        self.is_client = false
        self.client_opts = null
        self.peer_certificates = null      # client : chaîne reçue du serveur (crypto.x509.Certificate)
        self.strict_eof = false            # vrai : une coupure sans close_notify est une erreur (troncature)
        self.hs = null                     # serveur : état de la poignée de main pas à pas (server_step)
        self.resumed = false               # session reprise par un ticket (sans signature)
        self.session = null                # client : dernier ticket reçu (wrap_client(session=...))
        self.res_master = null

    # ------------------------------------------------------------ enregistrements

    func _raw_send(data, timeout):
        if data != "":
            self.socket.send(data, timeout)

    func _record(ct, payload):
        return _s.byte_pack([ct, 3, 3] + _u16(len(payload)) + payload)

    # Enregistrement(s) de type ct pour data (liste d'octets), chiffrés si une clé d'écriture est en place.
    func _records(ct, data):
        return _protect(self.write_aead, ct, data)

    # Enregistrement complet en tête de rbuf : [type, octets du contenu (str), en-tête (liste)] ou null.
    func _take_record():
        n := _s.byte_len(self.rbuf)
        if n < 5:
            return null
        t := _s.byte_at(self.rbuf, 0)
        if self.handshaking and self.read_aead == null and t != CT_HANDSHAKE and t != CT_ALERT and t != CT_CCS:
            if t >= 32 and t < 127:
                _abort(-1, "le client ne parle pas TLS (requête en clair sur le port HTTPS ?)")
            _abort(ALERT_UNEXPECTED_MESSAGE, "enregistrement de type " + str(t) + " avant la poignée de main")
        if _s.byte_at(self.rbuf, 1) != 3:
            _abort(ALERT_PROTOCOL_VERSION if self.handshaking else ALERT_DECODE_ERROR, "version d'enregistrement invalide")
        l := (_s.byte_at(self.rbuf, 3) << 8) | _s.byte_at(self.rbuf, 4)
        if l > MAX_CIPHERTEXT:
            _abort(ALERT_RECORD_OVERFLOW, "enregistrement trop long (" + str(l) + " octets)")
        if n < 5 + l:
            return null
        header := [t, 3, _s.byte_at(self.rbuf, 2), (l >> 8) & 255, l & 255]
        body := _s.byte_slice(self.rbuf, 5, 5 + l)
        self.rbuf = _s.byte_slice(self.rbuf, 5 + l, n)
        return [t, body, header]

    # Déchiffre un enregistrement : [type intérieur, contenu (str)] ; null pour un enregistrement à ignorer.
    func _unprotect(rec):
        t := rec[0]
        if t == CT_CCS:
            if self.handshaking and _s.byte_len(rec[1]) == 1 and _s.byte_at(rec[1], 0) == 1:
                return null
            _abort(ALERT_UNEXPECTED_MESSAGE, "change_cipher_spec inattendu")
        if self.read_aead == null:
            if _s.byte_len(rec[1]) > MAX_PLAINTEXT:
                _abort(ALERT_RECORD_OVERFLOW, "enregistrement en clair trop long")
            return [t, rec[1]]
        if t != CT_APP:
            _abort(ALERT_UNEXPECTED_MESSAGE, "enregistrement en clair après l'activation du chiffrement")
        inner := self.read_aead.open_str(rec[1], _s.byte_pack(rec[2]))
        if inner == null:
            if self.early_budget > 0:
                # données précoces (0-RTT) refusées : ignorées dans la limite prévue (RFC 8446, 4.2.10)
                self.read_aead.seq -= 1
                self.early_budget -= _s.byte_len(rec[1])
                return null
            _abort(ALERT_BAD_RECORD_MAC, "enregistrement altéré ou mal chiffré")
        self.early_budget = 0
        k := _s.byte_len(inner) - 1
        while k >= 0 and _s.byte_at(inner, k) == 0:
            k -= 1
        if k < 0:
            _abort(ALERT_UNEXPECTED_MESSAGE, "enregistrement sans type de contenu")
        if k > MAX_PLAINTEXT:
            _abort(ALERT_RECORD_OVERFLOW, "clair trop long")
        return [_s.byte_at(inner, k), _s.byte_slice(inner, 0, k)]

    func _fill(deadline):
        left := deadline - _time.monotonic()
        if left <= 0:
            raise("TimeoutError", "tls.handshake(serveur) : délai dépassé")
        data := self.socket.recv(65536, left)
        if data == "":
            self.eof = true
            raise("TlsError", "tls.handshake(serveur) : connexion fermée par le client pendant la poignée de main")
        self.rbuf = self.rbuf + data

    # Message de poignée de main complet déjà réassemblé, ou null.
    func _take_hs_message():
        if len(self.hsbuf) >= 4:
            l := (self.hsbuf[1] << 16) | (self.hsbuf[2] << 8) | self.hsbuf[3]
            if l > _MAX_HANDSHAKE:
                _abort(ALERT_DECODE_ERROR, "message de poignée de main trop long")
            if len(self.hsbuf) >= 4 + l:
                full := self.hsbuf[0:4 + l]
                self.hsbuf = self.hsbuf[4 + l:len(self.hsbuf)]
                return [full[0], full[4:4 + l], full]
        return null

    func _absorb_handshake_record(rec):
        p := self._unprotect(rec)
        if p == null:
            return
        if p[0] == CT_ALERT:
            self._on_alert(_s.byte_unpack(p[1]))
            raise("TlsError", "tls.handshake : le pair a fermé la connexion")
        if p[0] != CT_HANDSHAKE or p[1] == "":
            _abort(ALERT_UNEXPECTED_MESSAGE, "message de poignée de main attendu")
        self.hsbuf = self.hsbuf + _s.byte_unpack(p[1])

    # Prochain message de poignée de main (attente jusqu'à deadline) : [type, corps, octets complets].
    func _read_handshake(deadline):
        while true:
            m := self._take_hs_message()
            if m != null:
                return m
            rec := self._take_record()
            if rec == null:
                self._fill(deadline)
                continue
            self._absorb_handshake_record(rec)

    func _on_alert(b):
        if len(b) != 2:
            _abort(ALERT_DECODE_ERROR, "alerte mal formée")
        if b[1] == ALERT_CLOSE_NOTIFY or b[1] == 90:
            self.peer_closed = true
            return
        self.failed = "alerte reçue du client : " + _alert_name(b[1])
        raise("TlsError", "tls : " + self.failed)

    func _send_alert(desc):
        if self.sent_close:
            return
        self.sent_close = true
        try:
            self.out = ""
            self._raw_send(self._records(CT_ALERT, [1 if desc == ALERT_CLOSE_NOTIFY else 2, desc]), 1.0)
        catch e:
            ignored := e

    # ------------------------------------------------------------ poignée de main serveur

    func handshake(timeout=10.0):
        deadline := _time.monotonic() + (timeout if timeout != null else 3600.0)
        try:
            if self.is_client:
                self._client_handshake(deadline)
            else:
                self._handshake(deadline)
        catch e:
            self._handshake_failed(e)
        if not self.is_client:
            self._server_done()
        self.handshaking = false

    # TlsAlert -> alerte envoyée au pair, puis TlsError ; les autres erreurs passent telles quelles.
    func _handshake_failed(e):
        side := "client" if self.is_client else "serveur"
        if e.type == "TlsAlert":
            a := _split_abort(e.message)
            if a[0] >= 0:
                self._send_alert(a[0])
            self.failed = a[1]
            raise("TlsError", "tls.handshake(" + side + ") : " + a[1] + (" (alerte " + _alert_name(a[0]) + ")" if a[0] >= 0 else ""))
        raise(e)

    # Poignée de main serveur bloquante (délai deadline) : la machine à états, calcul sur place.
    func _handshake(deadline):
        while true:
            r := self._server_step(null)
            if r == "done":
                return
            left := deadline - _time.monotonic()
            if left <= 0:
                raise("TimeoutError", "tls.handshake(serveur) : délai dépassé")
            if r == "write":
                self._flush(left)
            else:
                self._fill(deadline)

    # Poignée de main serveur SANS ATTENTE, pour une boucle d'événements (web.server). Chaque appel avance autant
    # que possible avec les octets déjà arrivés et rend :
    #   « read »   octets du client attendus (attendre que le socket brut soit lisible)
    #   « write »  envoi en attente (réseau plein)
    #   « busy »   calcul en cours sur executor
    #   « done »   connexion prête (send / recv / try_recv)
    # executor : objet {submit(fn, args) -> poignée, done(poignée), result(poignée)} qui exécute server_flight
    # ailleurs (web.server : un fil de thread.offload), de sorte que la boucle ne porte ni l'échange de clés ni la
    # signature (RSA : 35 ms) ; null : calcul sur place. TlsError (alerte envoyée) ou ValueError en cas d'échec.
    func server_step(executor=null):
        r := null
        try:
            r = self._server_step(executor)
        catch e:
            self._handshake_failed(e)
        if r == "done" and self.handshaking:
            self._server_done()
            self.handshaking = false
        return r

    # Session une fois la poignée de main terminée (interface commune avec network.tls.OpenSslAccept).
    func established():
        return self

    func _server_done():
        if self.ctx != null:
            self.ctx.handshakes += 1

    # Message de poignée de main complet sans attendre : [type, corps, octets complets], ou null.
    func _poll_handshake():
        while true:
            m := self._take_hs_message()
            if m != null:
                return m
            rec := self._take_record()
            if rec == null:
                data := self.socket.try_recv(65536)
                if data == null:
                    return null
                if data == "":
                    self.eof = true
                    raise("TlsError", "tls.handshake(serveur) : connexion fermée par le client pendant la poignée de main")
                self.rbuf = self.rbuf + data
                continue
            self._absorb_handshake_record(rec)

    func _server_step(executor):
        if self.hs == null:
            self.hs = {"state": "hello"}
        hs := self.hs
        while true:
            st := hs["state"]
            if self.out != "" and not self._flush(0):
                if st != "busy":
                    return "write"
            if st == "hello" or st == "hello2":
                m := self._poll_handshake()
                if m == null:
                    return "read"
                if st == "hello":
                    self._on_client_hello(m)
                else:
                    self._on_second_hello(m)
            elif st == "compute":
                args := self._flight_args()
                if executor == null:
                    self._on_flight(_flight(self.ctx, args))
                else:
                    hs["job"] = executor.submit(server_flight, [self.ctx.cert_file, self.ctx.key_file, self.ctx.alpn, self.ctx.options, args])
                    hs["state"] = "busy"
            elif st == "busy":
                if not executor.done(hs["job"]):
                    return "busy"
                self._on_flight(executor.result(hs["job"]))
            elif st == "finished":
                m := self._poll_handshake()
                if m == null:
                    return "read"
                self._on_client_finished(m)
                hs["state"] = "done"
            else:
                return "done"

    func _on_client_hello(m):
        ctx := self.ctx
        hs := self.hs
        if m[0] != HS_CLIENT_HELLO:
            _abort(ALERT_UNEXPECTED_MESSAGE, "ClientHello attendu")
        hello := _parse_client_hello(m[1])
        if len(self.hsbuf) > 0:
            _abort(ALERT_UNEXPECTED_MESSAGE, "données après le ClientHello")
        suite_code := _choose_suite(hello, ctx.suites)
        if suite_code == null:
            _abort(ALERT_HANDSHAKE_FAILURE, "aucune suite TLS 1.3 commune (AES-GCM, ChaCha20-Poly1305)")
        h := SUITES[suite_code]["hash"]
        if not (EXT_SIGNATURE_ALGORITHMS in hello.exts):
            _abort(ALERT_MISSING_EXTENSION, "signature_algorithms absente")
        if not (EXT_SUPPORTED_GROUPS in hello.exts) or not (EXT_KEY_SHARE in hello.exts):
            _abort(ALERT_MISSING_EXTENSION, "supported_groups ou key_share absente (échange de clés exigé)")
        scheme := ctx.signature_scheme(hello.sigalgs)
        if scheme == null:
            _abort(ALERT_HANDSHAKE_FAILURE, "aucun schéma de signature commun avec la clé du serveur (" + ctx.key.kind + ")")
        choice := _choose_group(hello, ctx.groups)
        if choice == null:
            _abort(ALERT_HANDSHAKE_FAILURE, "aucun groupe commun (x25519, secp256r1, secp384r1)")
        hs["hello"] = hello
        hs["suite"] = suite_code
        hs["scheme"] = scheme
        hs["choice"] = choice
        hs["transcript"] = m[2]
        hs["ccs"] = false
        hs["psk"] = null
        if choice[1] != null:
            hs["psk"] = self._accept_psk(hello, m[2], suite_code, [])
            hs["state"] = "compute"
            return
        # HelloRetryRequest (RFC 8446, 4.1.4) : le transcript commence par l'empreinte du premier ClientHello
        hrr := _server_hello(_HRR_RANDOM, hello.session_id, suite_code,
                             _ext(EXT_SUPPORTED_VERSIONS, _u16(772)) + _ext(EXT_KEY_SHARE, _u16(choice[0])))
        hs["transcript"] = _msg(HS_MESSAGE_HASH, _hash(h, m[2])) + hrr
        self.out = self.out + self._records(CT_HANDSHAKE, hrr)
        if len(hello.session_id) > 0:
            self.out = self.out + self._record(CT_CCS, [1])
            hs["ccs"] = true
        hs["state"] = "hello2"

    func _on_second_hello(m):
        hs := self.hs
        hello := hs["hello"]
        choice := hs["choice"]
        if m[0] != HS_CLIENT_HELLO:
            _abort(ALERT_UNEXPECTED_MESSAGE, "second ClientHello attendu")
        hello2 := _parse_client_hello(m[1])
        if len(self.hsbuf) > 0:
            _abort(ALERT_UNEXPECTED_MESSAGE, "données après le ClientHello")
        if hello2.session_id != hello.session_id or not (hs["suite"] in hello2.suites):
            _abort(ALERT_ILLEGAL_PARAMETER, "second ClientHello incohérent")
        if len(hello2.shares) != 1 or hello2.shares[0][0] != choice[0]:
            _abort(ALERT_ILLEGAL_PARAMETER, "second ClientHello : part du groupe demandé attendue")
        if self.ctx.signature_scheme(hello2.sigalgs) != hs["scheme"]:
            _abort(ALERT_ILLEGAL_PARAMETER, "second ClientHello incohérent (signatures)")
        hs["psk"] = self._accept_psk(hello2, m[2], hs["suite"], hs["transcript"])
        hs["transcript"] = hs["transcript"] + m[2]
        hs["hello"] = hello2
        hs["choice"] = [choice[0], hello2.shares[0][1]]
        hs["state"] = "compute"

    # Clé pré-partagée du premier ticket proposé, si le ticket est de ce serveur, encore valable, pour la même
    # empreinte et le même nom, en mode psk_dhe_ke ; le binder est vérifié (sinon decrypt_error). null :
    # poignée de main complète. prefix : transcript avant ce ClientHello (après un HelloRetryRequest).
    func _accept_psk(hello, ch, suite_code, prefix):
        ctx := self.ctx
        if not ctx.tickets or len(hello.psk_ids) == 0 or not (1 in hello.psk_modes):
            return null
        st := ctx.open_ticket(hello.psk_ids[0][0])
        if st == null:
            return null
        h := SUITES[suite_code]["hash"]
        if not (st["suite"] in SUITES) or SUITES[st["suite"]]["hash"] != h:
            return null
        age := to_int(_time.time()) - st["created"]
        if age < 0 or age > ctx.ticket_lifetime:
            return null
        if st["sni"] != (hello.server_name if hello.server_name != null else ""):
            return null
        psk := st["psk"]
        empty_hash := _hash(h, [])
        hl := len(empty_hash)
        early := _hkdf.extract(h, [0] * hl, psk)
        fk := expand_label(h, derive_secret(h, early, "res binder", empty_hash), "finished", [], hl)
        expected := _hmac(h, fk, _hash(h, prefix + ch[0:len(ch) - hello.binders_len]))
        if not _c.equals(hello.binders[0], expected):
            _abort(ALERT_DECRYPT_ERROR, "binder de la clé pré-partagée invalide")
        return psk

    # Arguments de server_flight (copiables d'un fil à l'autre : nombres, str, listes).
    func _flight_args():
        hs := self.hs
        hello := hs["hello"]
        ctx := self.ctx
        alpn := null
        if hello.alpn != null and ctx.alpn != null and len(ctx.alpn) > 0:
            for p in ctx.alpn:
                if alpn == null and p in hello.alpn:
                    alpn = p
            if alpn == null:
                _abort(ALERT_NO_APPLICATION_PROTOCOL, "aucun protocole ALPN commun (proposés : " + _s.join(", ", hello.alpn) + ")")
        hs["alpn"] = alpn
        return [hs["suite"], hs["choice"][0], _s.byte_pack(hs["choice"][1]), hs["scheme"], _s.byte_pack(hello.session_id),
                _s.byte_pack(hs["transcript"]), alpn, hs["ccs"], _s.byte_pack(hs["psk"]) if hs["psk"] != null else null]

    # Résultat de server_flight : premier vol à envoyer, clés de la suite de la poignée de main.
    func _on_flight(res):
        hs := self.hs
        if res[0] != "ok":
            if res[1] == "TlsAlert":
                raise("TlsAlert", res[2])
            raise(res[1], res[2])
        suite := SUITES[hs["suite"]]
        self.suite = suite
        self.write_aead = _Aead(suite, _s.byte_unpack(res[2]))
        self.write_aead.seq = res[7]
        self.read_aead = _Aead(suite, _s.byte_unpack(res[3]))
        hs["c_ap"] = _s.byte_unpack(res[4])
        hs["s_ap"] = _s.byte_unpack(res[5])
        hs["expected"] = _s.byte_unpack(res[6])
        hs["res_master"] = _s.byte_unpack(res[8])
        if hs["hello"].early_data:
            self.early_budget = _EARLY_DATA_BUDGET
        self.out = self.out + res[1]
        hs["state"] = "finished"

    func _on_client_finished(m):
        hs := self.hs
        if m[0] != HS_FINISHED:
            _abort(ALERT_UNEXPECTED_MESSAGE, "Finished du client attendu")
        if not _c.equals(m[1], hs["expected"]):
            _abort(ALERT_DECRYPT_ERROR, "Finished du client invalide")
        if len(self.hsbuf) > 0:
            _abort(ALERT_UNEXPECTED_MESSAGE, "données après le Finished du client")
        suite := self.suite
        self.read_aead = _Aead(suite, hs["c_ap"])
        self.write_aead = _Aead(suite, hs["s_ap"])
        self.cipher = suite["name"]
        self.alpn = hs["alpn"]
        self.server_name = hs["hello"].server_name
        self.group = _GROUP_NAMES[hs["choice"][0]]
        self.resumed = hs["psk"] != null
        self.signature_scheme = null if self.resumed else hs["scheme"]
        if self.resumed:
            self.ctx.resumptions += 1
        if self.ctx.tickets:
            self._send_ticket(suite, hs)
        self.hs = null

    # NewSessionTicket (RFC 8446, 4.6.1) : un ticket par connexion, envoyé sans attendre (il part avec la
    # première réponse si le réseau est plein).
    func _send_ticket(suite, hs):
        ctx := self.ctx
        h := suite["hash"]
        nonce := [0]
        psk := expand_label(h, hs["res_master"], "resumption", nonce, len(hs["res_master"]))
        a := _rnd.random_bytes(4)
        age_add := (a[0] << 24) | (a[1] << 16) | (a[2] << 8) | a[3]
        ticket := ctx.seal_ticket(hs["suite"], to_int(_time.time()), age_add, self.alpn, self.server_name, psk)
        nst := _msg(HS_NEW_SESSION_TICKET, _u32(ctx.ticket_lifetime) + _u32(age_add) + _vec8(nonce) + _vec16(ticket) + _vec16([]))
        self.out = self.out + self._records(CT_HANDSHAKE, nst)
        try:
            self._flush(0)
        catch e:
            ignored := e

    # ------------------------------------------------------------ poignée de main client

    func _client_hello(random, session_id, shares, prefix=[]):
        o := self.client_opts
        exts := []
        host := o["server_name"]
        if host != null and _x509._ip_bytes(host) == null:
            nm := _c.utf8_encode(host)
            exts = exts + _ext(EXT_SERVER_NAME, _vec16([0] + _vec16(nm)))
        exts = exts + _ext(EXT_SUPPORTED_VERSIONS, _vec8(_u16(772)))
        groups := []
        for g in GROUP_ORDER:
            groups = groups + _u16(g)
        exts = exts + _ext(EXT_SUPPORTED_GROUPS, _vec16(groups))
        ks := []
        for sh in shares:
            ks = ks + _u16(sh[0]) + _vec16(sh[1])
        exts = exts + _ext(EXT_KEY_SHARE, _vec16(ks))
        sigs := []
        for sg in [SIG_ECDSA_P256, SIG_ECDSA_P384, SIG_RSA_PSS_256, SIG_RSA_PSS_384, SIG_RSA_PSS_512]:
            sigs = sigs + _u16(sg)
        exts = exts + _ext(EXT_SIGNATURE_ALGORITHMS, _vec16(sigs))
        if o["alpn"] != null and len(o["alpn"]) > 0:
            pl := []
            for p in o["alpn"]:
                pl = pl + _vec8(_c.utf8_encode(p))
            exts = exts + _ext(EXT_ALPN, _vec16(pl))
        if o["cookie"] != null:
            exts = exts + _ext(EXT_COOKIE, o["cookie"])
        sess := o["offer"]
        hl := 0
        if sess != null:
            # reprise (RFC 8446, 4.2.11) : psk_dhe_ke, puis pre_shared_key en DERNIÈRE extension ; le binder couvre
            # le ClientHello jusqu'à la liste des binders
            hl = len(sess["psk"])
            age := to_int((_time.time() - sess["received"]) * 1000.0)
            obf := (age + sess["age_add"]) & 4294967295
            exts = exts + _ext(EXT_PSK_MODES, _vec8([1]))
            ids := _vec16(sess["ticket"]) + _u32(obf)
            exts = exts + _ext(EXT_PRE_SHARED_KEY, _vec16(ids) + _vec16(_vec8([0] * hl)))
        suites := []
        for c in SUITE_ORDER:
            suites = suites + _u16(c)
        ch := _msg(HS_CLIENT_HELLO, _u16(771) + random + _vec8(session_id) + _vec16(suites) + [1, 0] + _vec16(exts))
        if sess != null:
            h := SUITES[sess["suite"]]["hash"]
            early := _hkdf.extract(h, [0] * hl, sess["psk"])
            fk := expand_label(h, derive_secret(h, early, "res binder", _hash(h, [])), "finished", [], hl)
            cut := len(ch) - (3 + hl)
            binder := _hmac(h, fk, _hash(h, prefix + ch[0:cut]))
            if o["corrupt_binder"]:
                binder[0] = binder[0] ^ 1          # tests : binder falsifié
            ch = ch[0:cut] + [0, hl + 1, hl] + binder
        return ch

    # [type, version choisie, suite, extensions {code: octets}, aléa] d'un ServerHello (ou HelloRetryRequest).
    func _parse_server_hello(body, session_id):
        r := _Reader(body)
        r.u16()
        random := r.take(32)
        sid := r.vec8()
        suite := r.u16()
        comp := r.u8()
        er := _Reader(r.vec16())
        r.finish("ServerHello")
        if sid != session_id:
            _abort(ALERT_ILLEGAL_PARAMETER, "ServerHello : legacy_session_id différent")
        if not (suite in SUITES):
            _abort(ALERT_ILLEGAL_PARAMETER, "ServerHello : suite non proposée")
        if comp != 0:
            _abort(ALERT_ILLEGAL_PARAMETER, "ServerHello : compression")
        exts := {}
        while not er.done():
            code := er.u16()
            data := er.vec16()
            if code in exts:
                _abort(ALERT_ILLEGAL_PARAMETER, "ServerHello : extension en double")
            exts[code] = data
        if not (EXT_SUPPORTED_VERSIONS in exts) or exts[EXT_SUPPORTED_VERSIONS] != [3, 4]:
            _abort(ALERT_PROTOCOL_VERSION, "le serveur ne répond pas en TLS 1.3")
        return [random == _HRR_RANDOM, suite, exts]

    func _new_share(group):
        if group == GROUP_X25519:
            priv := _rnd.random_bytes(32)
            return [group, _x25519.public_key(priv), priv]
        c := _ec.curve("P-256" if group == GROUP_P256 else "P-384")
        priv := null
        while priv == null:
            try:
                priv = _ec.private_key(c, _rnd.random_bytes(c.size))
            catch e:
                priv = null
        return [group, priv.public_bytes(), priv]

    func _shared_secret(share, server_pub):
        if share[0] == GROUP_X25519:
            if len(server_pub) != 32:
                _abort(ALERT_ILLEGAL_PARAMETER, "part x25519 du serveur invalide")
            try:
                return _x25519.shared(share[2], server_pub)
            catch e:
                _abort(ALERT_ILLEGAL_PARAMETER, "part x25519 du serveur refusée")
        c := share[2].curve
        pub := null
        try:
            pub = _ec.public_key(c, server_pub)
        catch e:
            _abort(ALERT_ILLEGAL_PARAMETER, "part " + c.name + " du serveur hors de la courbe")
        return _ec.ecdh(share[2], pub)

    func _verify_server_signature(scheme, sig, content):
        leaf := self.peer_certificates[0]
        pub := leaf.public_key
        ok := false
        try:
            if scheme == SIG_ECDSA_P256 and leaf.curve == "P-256":
                ok = _ec.verify_der(pub, content, sig, "sha256")
            elif scheme == SIG_ECDSA_P384 and leaf.curve == "P-384":
                ok = _ec.verify_der(pub, content, sig, "sha384")
            elif leaf.key_kind == "rsa" and (scheme == SIG_RSA_PSS_256 or scheme == SIG_RSA_PSS_384 or scheme == SIG_RSA_PSS_512):
                algo := "sha256" if scheme == SIG_RSA_PSS_256 else ("sha384" if scheme == SIG_RSA_PSS_384 else "sha512")
                ok = _rsa.verify_pss(pub, content, sig, algo)
            else:
                _abort(ALERT_ILLEGAL_PARAMETER, "schéma de signature " + str(scheme) + " incompatible avec le certificat")
        catch e:
            if e.type == "TlsAlert":
                raise(e)
            ok = false
        if not ok:
            _abort(ALERT_DECRYPT_ERROR, "signature CertificateVerify du serveur invalide")

    func _client_handshake(deadline):
        o := self.client_opts
        random := _rnd.random_bytes(32)
        session_id := _rnd.random_bytes(32)
        share := self._new_share(GROUP_X25519)
        ch := self._client_hello(random, session_id, [[share[0], share[1]]])
        self._raw_send(self._records(CT_HANDSHAKE, ch), _max(deadline - _time.monotonic(), 0.5))
        transcript := ch
        m := self._read_handshake(deadline)
        if m[0] != HS_SERVER_HELLO:
            _abort(ALERT_UNEXPECTED_MESSAGE, "ServerHello attendu")
        sh := self._parse_server_hello(m[1], session_id)
        if sh[0]:
            # HelloRetryRequest : nouvelle part pour le groupe demandé
            ks := sh[2][EXT_KEY_SHARE] if EXT_KEY_SHARE in sh[2] else null
            if ks == null or len(ks) != 2:
                _abort(ALERT_ILLEGAL_PARAMETER, "HelloRetryRequest sans groupe")
            g := (ks[0] << 8) | ks[1]
            if not (g in GROUP_ORDER) or g == share[0]:
                _abort(ALERT_ILLEGAL_PARAMETER, "HelloRetryRequest : groupe " + str(g) + " non proposé")
            h0 := SUITES[sh[1]]["hash"]
            transcript = _msg(HS_MESSAGE_HASH, _hash(h0, transcript)) + m[2]
            if EXT_COOKIE in sh[2]:
                o["cookie"] = sh[2][EXT_COOKIE]
            share = self._new_share(g)
            ch2 := self._client_hello(random, session_id, [[share[0], share[1]]], transcript)
            self._raw_send(self._records(CT_HANDSHAKE, ch2), _max(deadline - _time.monotonic(), 0.5))
            transcript = transcript + ch2
            hrr_suite := sh[1]
            m = self._read_handshake(deadline)
            if m[0] != HS_SERVER_HELLO:
                _abort(ALERT_UNEXPECTED_MESSAGE, "ServerHello attendu")
            sh = self._parse_server_hello(m[1], session_id)
            if sh[0] or sh[1] != hrr_suite:
                _abort(ALERT_UNEXPECTED_MESSAGE, "second HelloRetryRequest ou suite changée")
        if len(self.hsbuf) > 0:
            _abort(ALERT_UNEXPECTED_MESSAGE, "données après le ServerHello")
        transcript = transcript + m[2]
        suite := SUITES[sh[1]]
        h := suite["hash"]
        if not (EXT_KEY_SHARE in sh[2]):
            _abort(ALERT_MISSING_EXTENSION, "ServerHello sans key_share")
        kr := _Reader(sh[2][EXT_KEY_SHARE])
        g := kr.u16()
        server_pub := kr.vec16()
        kr.finish("key_share")
        if g != share[0]:
            _abort(ALERT_ILLEGAL_PARAMETER, "key_share du serveur pour un autre groupe")
        secret := self._shared_secret(share, server_pub)
        hl := len(_hash(h, []))
        zeros := [0] * hl
        empty_hash := _hash(h, [])
        resumed := false
        sess := o["offer"]
        if EXT_PRE_SHARED_KEY in sh[2]:
            if sess == null or sh[2][EXT_PRE_SHARED_KEY] != [0, 0]:
                _abort(ALERT_ILLEGAL_PARAMETER, "pre_shared_key du serveur : identité non proposée")
            if SUITES[sess["suite"]]["hash"] != h:
                _abort(ALERT_ILLEGAL_PARAMETER, "reprise : suite d'une autre empreinte")
            resumed = true
        early := _hkdf.extract(h, zeros, sess["psk"] if resumed else zeros)
        hs := _hkdf.extract(h, derive_secret(h, early, "derived", empty_hash), secret)
        th := _hash(h, transcript)
        c_hs := derive_secret(h, hs, "c hs traffic", th)
        s_hs := derive_secret(h, hs, "s hs traffic", th)
        self.suite = suite
        self.read_aead = _Aead(suite, s_hs)
        self.write_aead = _Aead(suite, c_hs)      # nos alertes partent désormais chiffrées
        # EncryptedExtensions
        m = self._read_handshake(deadline)
        if m[0] != HS_ENCRYPTED_EXTENSIONS:
            _abort(ALERT_UNEXPECTED_MESSAGE, "EncryptedExtensions attendu")
        er := _Reader(m[1])
        xr := _Reader(er.vec16())
        er.finish("EncryptedExtensions")
        alpn := null
        while not xr.done():
            code := xr.u16()
            data := xr.vec16()
            if code == EXT_ALPN:
                ar := _Reader(data)
                lr := _Reader(ar.vec16())
                ar.finish("ALPN")
                p := _s.byte_pack(lr.vec8())
                lr.finish("ALPN")
                if o["alpn"] == null or not (p in o["alpn"]):
                    _abort(ALERT_ILLEGAL_PARAMETER, "protocole ALPN « " + p + " » non proposé")
                alpn = p
        transcript = transcript + m[2]
        certs := []
        scheme := null
        if not resumed:
            # Certificate
            m = self._read_handshake(deadline)
            if m[0] != HS_CERTIFICATE:
                _abort(ALERT_UNEXPECTED_MESSAGE, "Certificate attendu (certificats clients non pris en charge)")
            cr := _Reader(m[1])
            if len(cr.vec8()) != 0:
                _abort(ALERT_ILLEGAL_PARAMETER, "Certificate : contexte non vide")
            lr2 := _Reader(cr.vec24())
            cr.finish("Certificate")
            certs = []
            while not lr2.done():
                d := lr2.vec24()
                lr2.vec16()
                try:
                    append(certs, _x509.certificate_from_der(d))
                catch e:
                    _abort(42, "certificat illisible : " + e.message)
            if len(certs) == 0:
                _abort(ALERT_DECODE_ERROR, "aucun certificat reçu")
            if certs[0].public_key == null:
                _abort(43, "clé du certificat non prise en charge (" + str(certs[0].curve) + ")")
            self.peer_certificates = certs
            if o["verify"]:
                try:
                    _x509.verify_chain(certs, o["anchors"], o["server_name"])
                catch e:
                    if e.type != "ValueError":
                        raise(e)
                    _abort(48, "certificat refusé : " + e.message)
            transcript = transcript + m[2]
            # CertificateVerify
            m = self._read_handshake(deadline)
            if m[0] != HS_CERTIFICATE_VERIFY:
                _abort(ALERT_UNEXPECTED_MESSAGE, "CertificateVerify attendu")
            vr := _Reader(m[1])
            scheme = vr.u16()
            sig := vr.vec16()
            vr.finish("CertificateVerify")
            content := [32] * 64 + _c.utf8_encode("TLS 1.3, server CertificateVerify") + [0] + _hash(h, transcript)
            self._verify_server_signature(scheme, sig, content)
            transcript = transcript + m[2]
        # Finished du serveur
        m = self._read_handshake(deadline)
        if m[0] != HS_FINISHED:
            _abort(ALERT_UNEXPECTED_MESSAGE, "Finished attendu")
        expected := _hmac(h, expand_label(h, s_hs, "finished", [], hl), _hash(h, transcript))
        if not _c.equals(m[1], expected):
            _abort(ALERT_DECRYPT_ERROR, "Finished du serveur invalide")
        if len(self.hsbuf) > 0:
            _abort(ALERT_UNEXPECTED_MESSAGE, "données après le Finished du serveur")
        transcript = transcript + m[2]
        th2 := _hash(h, transcript)
        master := _hkdf.extract(h, derive_secret(h, hs, "derived", empty_hash), zeros)
        c_ap := derive_secret(h, master, "c ap traffic", th2)
        s_ap := derive_secret(h, master, "s ap traffic", th2)
        # change_cipher_spec de compatibilité, puis Finished du client
        flight := self._record(CT_CCS, [1])
        fin := _msg(HS_FINISHED, _hmac(h, expand_label(h, c_hs, "finished", [], hl), th2))
        flight = flight + self._records(CT_HANDSHAKE, fin)
        self._raw_send(flight, _max(deadline - _time.monotonic(), 0.5))
        self.read_aead = _Aead(suite, s_ap)
        self.write_aead = _Aead(suite, c_ap)
        self.cipher = suite["name"]
        self.alpn = alpn
        self.server_name = o["server_name"]
        self.group = _GROUP_NAMES[share[0]]
        self.signature_scheme = scheme
        self.resumed = resumed
        if resumed:
            self.peer_subject = sess["peer_subject"]
            self.peer_issuer = sess["peer_issuer"]
        else:
            self.peer_subject = certs[0].subject_cn
            self.peer_issuer = _x509._find(certs[0].issuer, _x509.OID_CN)
        self.verify_result = 0 if o["verify"] else null
        # secret de reprise, pour les tickets que le serveur enverra
        self.res_master = derive_secret(h, master, "res master", _hash(h, transcript + fin))


    # ------------------------------------------------------------ données applicatives

    # Traite les enregistrements complets déjà reçus.
    func _process():
        while not self.peer_closed:
            rec := null
            p := null
            try:
                rec = self._take_record()
                if rec == null:
                    return
                p = self._unprotect(rec)
            catch e:
                self._fatal(e)
            if p == null:
                continue
            if p[0] == CT_APP:
                if p[1] != "":
                    self.plain = p[1] if self.plain == "" else self.plain + p[1]
            elif p[0] == CT_ALERT:
                try:
                    self._on_alert(_s.byte_unpack(p[1]))
                catch e:
                    self._fatal(e)
            elif p[0] == CT_HANDSHAKE:
                try:
                    self._post_handshake(_s.byte_unpack(p[1]))
                catch e:
                    self._fatal(e)
            else:
                self._fatal_alert(ALERT_UNEXPECTED_MESSAGE, "type d'enregistrement inattendu " + str(p[0]))

    func _fatal_alert(desc, message):
        self._send_alert(desc)
        self.failed = message
        raise("TlsError", "tls : " + message)

    func _fatal(e):
        if e.type == "TlsAlert":
            a := _split_abort(e.message)
            self._fatal_alert(a[0], a[1])
        raise(e)

    func _post_handshake(data):
        self.hsbuf = self.hsbuf + data
        while len(self.hsbuf) >= 4:
            l := (self.hsbuf[1] << 16) | (self.hsbuf[2] << 8) | self.hsbuf[3]
            if l > _MAX_HANDSHAKE:
                _abort(ALERT_DECODE_ERROR, "message de poignée de main trop long")
            if len(self.hsbuf) < 4 + l:
                return
            t := self.hsbuf[0]
            body := self.hsbuf[4:4 + l]
            self.hsbuf = self.hsbuf[4 + l:len(self.hsbuf)]
            if t == HS_NEW_SESSION_TICKET and self.is_client:
                self._on_ticket(body)
                continue
            if t != HS_KEY_UPDATE:
                _abort(ALERT_UNEXPECTED_MESSAGE, "message de poignée de main inattendu après la connexion (" + str(t) + ")")
            if len(body) != 1 or body[0] > 1:
                _abort(ALERT_ILLEGAL_PARAMETER, "KeyUpdate invalide")
            if len(self.hsbuf) > 0:
                _abort(ALERT_UNEXPECTED_MESSAGE, "KeyUpdate non aligné sur un enregistrement")
            self.read_aead = self.read_aead.next()
            if body[0] == 1:
                self.out = self.out + self._records(CT_HANDSHAKE, _msg(HS_KEY_UPDATE, [0]))
                self.write_aead = self.write_aead.next()
                self._flush(0)

    # Envoie ce qui attend dans self.out ; vrai si tout est parti.
    func _flush(timeout):
        if self.out == "":
            return true
        if timeout == 0:
            n := 0
            try:
                n = self.socket.send(self.out, 0)
            catch e:
                if e.type != "TimeoutError":
                    raise(e)
                n = 0
            self.out = _s.byte_slice(self.out, n, _s.byte_len(self.out))
            return self.out == ""
        self.socket.send(self.out, timeout)
        self.out = ""
        return true

    func _check_open(fn):
        if self.closed:
            raise("ArgumentError", "network.tls13." + fn + " : session fermée")
        if self.failed != null:
            raise("TlsError", "tls : session interrompue (" + self.failed + ")")

    func _t(t):
        return t if t != null else self.timeout

    func set_timeout(t):
        self.timeout = t

    # Envoie data (str) chiffré ; renvoie le nombre d'octets de clair acceptés. Délai nul : n'attend pas et peut
    # n'en accepter qu'une partie (0 si le réseau est plein) ; l'appelant renvoie la suite, comme pour un socket.
    func send(data, timeout=null):
        if type(data) != "str":
            raise("TypeError", "network.tls13.send : str attendue (obtenu '" + type(data) + "')")
        self._check_open("send")
        if self.sent_close:
            raise("TlsError", "tls.send : close_notify déjà envoyé")
        t := self._t(timeout)
        n := _s.byte_len(data)
        if t == 0:
            if not self._flush(0):
                return 0
            skip := self.owed if self.owed < n else n
            self.owed -= skip
            if skip == n:
                return n
            end := skip + MAX_PLAINTEXT
            if end > n:
                end = n
            self.out = self._records(CT_APP, _s.byte_unpack(_s.byte_slice(data, skip, end)))
            if self._flush(0):
                return end
            # l'enregistrement est parti en partie : le dernier octet sera « renvoyé » par l'appelant et ignoré,
            # ce qui le fait revenir tant que la fin du chiffré n'est pas partie
            self.owed = 1
            return end - 1
        self._flush(t)
        skip := self.owed if self.owed < n else n
        self.owed -= skip
        if skip < n:
            self.out = self._records(CT_APP, _s.byte_unpack(_s.byte_slice(data, skip, n)))
            self._flush(t)
        return n

    func send_bytes(data, timeout=null):
        return self.send(_s.byte_pack(data), timeout)

    func _take_plain(max):
        n := _s.byte_len(self.plain)
        if n <= max:
            out := self.plain
            self.plain = ""
            return out
        out := _s.byte_slice(self.plain, 0, max)
        self.plain = _s.byte_slice(self.plain, max, n)
        return out

    # Jusqu'à max octets déchiffrés ; "" : fin du flux (close_notify reçu ou connexion fermée).
    func recv(max=65536, timeout=null):
        self._check_open("recv")
        t := self._t(timeout)
        deadline := _time.monotonic() + t if t != null else null
        while true:
            self._process()
            if self.plain != "":
                return self._take_plain(max)
            if self.peer_closed or self.eof:
                return ""
            left := null
            if deadline != null:
                left = deadline - _time.monotonic()
                if left <= 0:
                    raise("TimeoutError", "tls.recv : délai dépassé")
            data := self.socket.recv(65536, left)
            if data == "":
                self.eof = true
                self._check_truncation()
            else:
                self.rbuf = self.rbuf + data

    func recv_bytes(max=65536, timeout=null):
        return _s.byte_unpack(self.recv(max, timeout))

    # Comme recv sans attendre : null si rien n'est disponible.
    func try_recv(max=65536):
        self._check_open("try_recv")
        self._process()
        if self.plain != "":
            return self._take_plain(max)
        if self.peer_closed or self.eof:
            return ""
        data := self.socket.try_recv(65536)
        if data == null:
            return null
        if data == "":
            self.eof = true
            self._check_truncation()
            return ""
        self.rbuf = self.rbuf + data
        self._process()
        if self.plain != "":
            return self._take_plain(max)
        if self.peer_closed:
            return ""
        return null

    # Client : ticket reçu (RFC 8446, 4.6.1) -> self.session, à donner à wrap_client(session=...) pour reprendre.
    func _on_ticket(body):
        r := _Reader(body)
        lifetime := (r.u16() << 16) | r.u16()
        age_add := (r.u16() << 16) | r.u16()
        nonce := r.vec8()
        ticket := r.vec16()
        r.vec16()
        r.finish("NewSessionTicket")
        if len(ticket) == 0:
            _abort(ALERT_DECODE_ERROR, "NewSessionTicket : ticket vide")
        if lifetime == 0 or self.res_master == null:
            return
        h := self.suite["hash"]
        code := 0
        for c in SUITES:
            if SUITES[c]["name"] == self.suite["name"]:
                code = c
        self.session = {"ticket": ticket, "psk": expand_label(h, self.res_master, "resumption", nonce, len(self.res_master)),
                        "suite": code, "age_add": age_add, "received": _time.time(), "lifetime": lifetime if lifetime < 604800 else 604800,
                        "server_name": self.server_name, "peer_subject": self.peer_subject, "peer_issuer": self.peer_issuer}

    # Envoie KeyUpdate (RFC 8446, 4.6.3) : nouvelles clés d'envoi ; request : le pair renouvelle aussi les siennes.
    func key_update(request=true):
        self._check_open("key_update")
        self.out = self.out + self._records(CT_HANDSHAKE, _msg(HS_KEY_UPDATE, [1 if request else 0]))
        self.write_aead = self.write_aead.next()
        self._flush(self._t(null))

    func _check_truncation():
        if self.strict_eof and not self.peer_closed:
            self.failed = "connexion coupée sans close_notify (troncature possible)"
            raise("TlsError", "tls.recv : " + self.failed)

    # Octets lisibles sans toucher au réseau (données déchiffrées, ou enregistrement complet en attente).
    func pending():
        n := _s.byte_len(self.plain)
        if n > 0:
            return n
        b := _s.byte_len(self.rbuf)
        if b >= 5 and b >= 5 + ((_s.byte_at(self.rbuf, 3) << 8) | _s.byte_at(self.rbuf, 4)):
            return 1
        return 0

    func received_close_notify():
        return self.peer_closed

    func local_address():
        return self.socket.local_address()

    func peer_address():
        return self.socket.peer_address()

    func set_option(name, value):
        self.socket.set_option(name, value)

    # « write » / « both » : envoie close_notify ; la lecture reste possible après « write ».
    func shutdown(how="both"):
        if how == "write" or how == "both":
            if not self.sent_close and self.failed == null:
                try:
                    self._flush(self._t(null))
                catch e:
                    ignored := e
                self._send_alert(ALERT_CLOSE_NOTIFY)
        self.socket.shutdown(how)

    func close():
        if self.closed:
            return
        if not self.sent_close and self.failed == null and not self.handshaking:
            try:
                self._flush(1.0)
            catch e:
                ignored := e
            self._send_alert(ALERT_CLOSE_NOTIFY)
        self.closed = true
        self.socket.close()

    func is_closed():
        return self.closed

# Poignée de main serveur sur un socket accepté (network.socket.Socket) ; ctx : ServerContext. En cas d'échec
# (TlsError, TimeoutError) le socket n'est pas fermé.
func wrap_server(sock, ctx, timeout=10.0):
    s := TlsSocket13(sock, ctx)
    s.handshake(timeout)
    return s

func _max(a, b):
    return a if a > b else b

_trust_cache := {}

# Ancres de confiance : certificats de ca_file, ou du magasin du système (lus une fois).
func trust_anchors(ca_file=null):
    paths := [ca_file] if ca_file != null else ["/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/cert.pem", "/etc/ssl/ca-bundle.pem"]
    for p in paths:
        if _os.exists(p):
            k := p + "|" + _stamp(p, p)
            if not (k in _trust_cache):
                _trust_cache[k] = _x509.load_trust(_io.read_raw(p))
            return _trust_cache[k]
    if ca_file != null:
        raise("ValueError", "tls13 : fichier d'autorités introuvable « " + ca_file + " »")
    raise("ValueError", "tls13 : aucun magasin d'autorités trouvé : donnez ca_file, ou verify=false")

# Poignée de main CLIENT sur un socket connecté. server_name : SNI et nom vérifié ; verify : chaîne contrôlée
# jusqu'à une autorité de ca_file (ou du système), noms et dates (crypto.x509.verify_chain) ; la signature
# CertificateVerify du serveur est toujours vérifiée. Rend un TlsSocket13 (peer_certificates : chaîne reçue).
# session : ts.session d'une connexion précédente au même serveur (ticket reçu après lecture de données) pour
# reprendre sans certificat ni signature ; ts.resumed dit si le serveur l'a acceptée.
func wrap_client(sock, server_name=null, alpn=null, timeout=10.0, verify=true, ca_file=null, session=null, corrupt_binder=false):
    anchors := trust_anchors(ca_file) if verify else []
    s := TlsSocket13(sock, null)
    s.is_client = true
    offer := null
    if session != null and session["server_name"] == server_name and _time.time() - session["received"] < session["lifetime"]:
        offer = session
    s.client_opts = {"server_name": server_name, "alpn": alpn, "verify": verify, "anchors": anchors, "cookie": null,
                     "offer": offer, "corrupt_binder": corrupt_binder}
    s.handshake(timeout)
    return s
