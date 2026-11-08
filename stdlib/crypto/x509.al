# ALEX STANDARD LIBRARY — crypto.x509
#
# Certificats X.509 et clés privées en PEM / DER, en ALEX pur : ce que demande TLS 1.3 sans OpenSSL
# (network.tls13). Lecture des certificats et des clés, vérification d'une chaîne jusqu'à une ancre de confiance
# (client), création de certificats auto-signés de développement (sans outil externe).
#
#   use crypto.x509 as x509
#   certs := x509.load_certificates(io.read_raw("site.pem"))    # liste de Certificate, feuille d'abord
#   cle := x509.load_private_key(io.read_raw("site.key"))       # PrivateKey : .kind « ec » / « rsa », .curve, .key
#   x509.key_matches(certs[0], cle)                             # la clé privée est-elle celle du certificat ?
#   certs[0].subject_cn, certs[0].dns_names, certs[0].not_after, certs[0].public_key
#   x509.verify_chain(chaine, ancres, "example.org")           # client : chaîne jusqu'à une ancre, nom, dates
#   pem := x509.self_signed("localhost", ["localhost", "127.0.0.1", "::1"], 365)   # [certificat, clé] (PEM)
#
# Clés privées : PKCS#8 (« PRIVATE KEY »), SEC1 (« EC PRIVATE KEY ») et PKCS#1 (« RSA PRIVATE KEY ») ; courbes
# P-256 et P-384, RSA d'au moins 2048 bits. Refusées avec un message clair : clés chiffrées (« ENCRYPTED PRIVATE
# KEY », en-tête Proc-Type), Ed25519 / Ed448, RSA-PSS restreintes, autres courbes.
# Erreurs : ValueError (« x509 : ... »).

from core use len, type, to_int
from collections use append
use string as _s
use crypto as _c
use crypto.der as der
use crypto.bigint as bn
use crypto.ec as ec
use crypto.rsa as rsa
use time as _time
use security.random_secure as _rnd

OID_EC_PUBLIC_KEY := "1.2.840.10045.2.1"
OID_RSA := "1.2.840.113549.1.1.1"
OID_RSA_PSS := "1.2.840.113549.1.1.10"
OID_P256 := "1.2.840.10045.3.1.7"
OID_P384 := "1.3.132.0.34"
OID_ED25519 := "1.3.101.112"
OID_ED448 := "1.3.101.113"
OID_CN := "2.5.4.3"
OID_SAN := "2.5.29.17"
OID_BASIC_CONSTRAINTS := "2.5.29.19"
OID_SHA256 := "2.16.840.1.101.3.4.2.1"
OID_SHA384 := "2.16.840.1.101.3.4.2.2"
OID_SHA512 := "2.16.840.1.101.3.4.2.3"
_SIG_ALGS := {"1.2.840.10045.4.3.2": ["ec", "sha256"], "1.2.840.10045.4.3.3": ["ec", "sha384"],
              "1.2.840.10045.4.3.4": ["ec", "sha512"], "1.2.840.113549.1.1.11": ["pkcs1", "sha256"],
              "1.2.840.113549.1.1.12": ["pkcs1", "sha384"], "1.2.840.113549.1.1.13": ["pkcs1", "sha512"]}

func _fail(message):
    raise("ValueError", "x509 : " + message)

func _curve_name(oid):
    if oid == OID_P256:
        return "P-256"
    if oid == OID_P384:
        return "P-384"
    _fail("courbe non prise en charge (OID " + oid + ") : P-256 ou P-384 attendue")

func _algo_name(oid):
    if oid == OID_ED25519:
        return "Ed25519"
    if oid == OID_ED448:
        return "Ed448"
    if oid == OID_RSA_PSS:
        return "RSA-PSS restreinte"
    return "OID " + oid

# ---------------------------------------------------------------- PEM

# Blocs PEM d'un texte : liste de [étiquette, octets DER] (« CERTIFICATE », « PRIVATE KEY »...), dans l'ordre.
func pem_blocks(text):
    if type(text) != "str":
        _fail("pem_blocks : texte attendu")
    out := []
    label := null
    body := []
    headers := false
    for raw in _s.split(_s.replace(text, "\r", ""), "\n"):
        line := _s.strip(raw)
        if label == null:
            if _s.starts_with(line, "-----BEGIN ") and _s.ends_with(line, "-----"):
                label = _s.substring(line, 11, len(line) - 5)
                body = []
                headers = false
            continue
        if _s.starts_with(line, "-----END "):
            if line != "-----END " + label + "-----":
                _fail("PEM : fin « " + line + " » sans début correspondant")
            if headers:
                _fail("PEM : bloc « " + label + " » chiffré (en-têtes Proc-Type / DEK-Info) : déchiffrez la clé d'abord (openssl pkey -in cle.pem -out claire.pem)")
            der_bytes := null
            try:
                der_bytes = _c.base64_decode(_s.join("", body))
            catch e:
                _fail("PEM : base64 invalide dans « " + label + " »")
            append(out, [label, der_bytes])
            label = null
            continue
        if _s.contains(line, ":"):
            headers = true
            continue
        if line != "":
            append(body, line)
    if label != null:
        _fail("PEM : bloc « " + label + " » non terminé")
    return out

func _text_of(data):
    if type(data) == "str":
        return data
    return _s.byte_pack(data)

# ---------------------------------------------------------------- clés

class PrivateKey:
    # kind : « ec » ou « rsa » ; curve : « P-256 » / « P-384 » (ec) ; key : crypto.ec.PrivateKey ou
    # crypto.rsa.PrivateKey ; bits : taille du module RSA ou de la courbe.
    func init(kind, key, curve=null):
        self.kind = kind
        self.key = key
        self.curve = curve
        if kind == "rsa":
            self.bits = bn.bit_length(key.n)
        else:
            self.bits = 256 if curve == "P-256" else 384

    func public_key():
        return self.key.public

func _ec_private(b, node, curve_oid):
    # ECPrivateKey (SEC 1, C.4) : SEQUENCE { 1, OCTET STRING d, [0] courbe OPTIONAL, [1] public OPTIONAL }
    it := der.items(b, node, der.SEQUENCE, "ECPrivateKey")
    if len(it) < 2 or der.small_int(b, it[0]) != 1:
        _fail("ECPrivateKey : version 1 attendue")
    d := der.octet_string(b, it[1])
    oid := curve_oid
    for x in it[2:len(it)]:
        if x[0] == der.context(0):
            inner := der.children(b, x)
            if len(inner) != 1:
                _fail("ECPrivateKey : paramètres de courbe invalides")
            o := der.oid(b, inner[0])
            if oid != null and o != oid:
                _fail("ECPrivateKey : courbe différente de celle de l'enveloppe PKCS#8")
            oid = o
    if oid == null:
        _fail("ECPrivateKey : courbe non indiquée")
    name := _curve_name(oid)
    c := ec.curve(name)
    if len(d) > c.size:
        _fail("ECPrivateKey : clé trop longue pour " + name)
    return PrivateKey("ec", ec.private_key(c, d), name)

func _rsa_private(b, node):
    # RSAPrivateKey (RFC 8017, A.1.2) : version, n, e, d, p, q, dp, dq, qinv
    it := der.items(b, node, der.SEQUENCE, "RSAPrivateKey")
    if len(it) < 9:
        _fail("RSAPrivateKey : éléments manquants")
    if der.small_int(b, it[0]) != 0:
        _fail("RSAPrivateKey : clé à plusieurs nombres premiers non prise en charge")
    v := []
    k := 1
    while k < 9:
        append(v, der.integer(b, it[k]))
        k += 1
    if bn.bit_length(v[0]) < 2048:
        _fail("clé RSA de " + str(bn.bit_length(v[0])) + " bits : 2048 au moins")
    return PrivateKey("rsa", rsa.PrivateKey(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]))

func _pkcs8(b):
    # PrivateKeyInfo (RFC 5208 / 5958) : SEQUENCE { version, AlgorithmIdentifier, OCTET STRING clé, ... }
    top := der.expect(b, 0, der.SEQUENCE, "PrivateKeyInfo")
    it := der.children(b, top)
    if len(it) < 3:
        _fail("PrivateKeyInfo : éléments manquants")
    alg := der.items(b, it[1], der.SEQUENCE, "AlgorithmIdentifier")
    oid := der.oid(b, alg[0])
    inner := der.octet_string(b, it[2])
    if oid == OID_EC_PUBLIC_KEY:
        if len(alg) < 2:
            _fail("clé EC sans courbe")
        return _ec_private(inner, der.read(inner, 0), der.oid(b, alg[1]))
    if oid == OID_RSA:
        return _rsa_private(inner, der.read(inner, 0))
    _fail("type de clé non pris en charge (" + _algo_name(oid) + ") : clé EC P-256 / P-384 ou RSA attendue")

# Clé privée depuis un DER (PKCS#8, ou kind = « ec » / « rsa » pour SEC1 / PKCS#1).
func private_key_from_der(b, kind="pkcs8"):
    if kind == "pkcs8":
        return _pkcs8(b)
    if kind == "ec":
        return _ec_private(b, der.read(b, 0), null)
    if kind == "rsa":
        return _rsa_private(b, der.read(b, 0))
    _fail("forme de clé inconnue " + str(kind))

# Première clé privée d'un texte PEM (str ou octets).
func load_private_key(data):
    for blk in pem_blocks(_text_of(data)):
        label := blk[0]
        if label == "PRIVATE KEY":
            return _pkcs8(blk[1])
        if label == "EC PRIVATE KEY":
            return private_key_from_der(blk[1], "ec")
        if label == "RSA PRIVATE KEY":
            return private_key_from_der(blk[1], "rsa")
        if label == "ENCRYPTED PRIVATE KEY":
            _fail("clé privée chiffrée (« ENCRYPTED PRIVATE KEY ») : déchiffrez-la d'abord (openssl pkey -in cle.pem -out claire.pem)")
    _fail("aucune clé privée PEM (PRIVATE KEY, EC PRIVATE KEY, RSA PRIVATE KEY) trouvée")

# ---------------------------------------------------------------- certificats

class Certificate:
    func init(der_bytes):
        self.der = der_bytes
        b := der_bytes
        top := der.expect(b, 0, der.SEQUENCE, "Certificate")
        if top[2] != len(b):
            _fail("certificat : octets en trop après la structure")
        parts := der.children(b, top)
        if len(parts) != 3:
            _fail("certificat : tbsCertificate, signatureAlgorithm, signatureValue attendus")
        tbs := der.items(b, parts[0], der.SEQUENCE, "tbsCertificate")
        i := 0
        self.version = 1
        if tbs[0][0] == der.context(0):
            self.version = der.small_int(b, der.children(b, tbs[0])[0]) + 1
            i = 1
        self.serial = bn.to_hex(der.integer(b, tbs[i]))
        self.tbs = b[top[1]:parts[0][2]]                 # tbsCertificate encodé (ce que signe l'émetteur)
        self.signature_algorithm = _sig_alg(b, parts[1])
        self.signature = der.bit_string(b, parts[2])
        self.issuer_raw = b[tbs[i + 1][2]:tbs[i + 2][2]]  # noms encodés : comparés octet à octet
        self.subject_raw = b[tbs[i + 3][2]:tbs[i + 4][2]]
        self.is_ca = false
        self.issuer = _name(b, tbs[i + 2])
        validity := der.items(b, tbs[i + 3], der.SEQUENCE, "Validity")
        self.not_before = der.time_text(b, validity[0])
        self.not_after = der.time_text(b, validity[1])
        self.subject = _name(b, tbs[i + 4])
        pk := _spki(b, tbs[i + 5])
        self.key_kind = pk[0]                # « ec » ou « rsa »
        self.public_key = pk[1]              # crypto.ec.PublicKey ou crypto.rsa.PublicKey
        self.curve = pk[2]                   # « P-256 » / « P-384 », ou null
        self.subject_cn = _find(self.subject, OID_CN)
        self.dns_names = []
        self.ip_addresses = []
        for x in tbs[i + 6:len(tbs)]:
            if x[0] == der.context(3):
                exts := der.children(b, x)
                if len(exts) == 1:
                    for e in der.items(b, exts[0], der.SEQUENCE, "Extensions"):
                        self._extension(b, e)

    func _extension(b, e):
        f := der.items(b, e, der.SEQUENCE, "Extension")
        oid := der.oid(b, f[0])
        if oid == OID_BASIC_CONSTRAINTS:
            v := der.octet_string(b, f[len(f) - 1])
            bc := der.children(v, der.expect(v, 0, der.SEQUENCE, "basicConstraints"))
            if len(bc) > 0 and bc[0][0] == der.BOOLEAN and bc[0][2] - bc[0][1] == 1:
                self.is_ca = v[bc[0][1]] != 0
            return
        if oid != OID_SAN:
            return
        v := der.octet_string(b, f[len(f) - 1])
        for g in der.children(v, der.expect(v, 0, der.SEQUENCE, "subjectAltName")):
            if g[0] == 130:
                append(self.dns_names, _s.byte_pack(der.content(v, g)))
            elif g[0] == 135:
                append(self.ip_addresses, der.content(v, g))

func _name(b, node):
    out := []
    for rdn in der.items(b, node, der.SEQUENCE, "Name"):
        for atv in der.items(b, rdn, der.SET, "RelativeDistinguishedName"):
            p := der.items(b, atv, der.SEQUENCE, "AttributeTypeAndValue")
            v := null
            try:
                v = der.text(b, p[1])
            catch e:
                v = null
            append(out, [der.oid(b, p[0]), v])
    return out

func _find(name, oid):
    for p in name:
        if p[0] == oid:
            return p[1]
    return null

func _spki(b, node):
    it := der.items(b, node, der.SEQUENCE, "SubjectPublicKeyInfo")
    alg := der.items(b, it[0], der.SEQUENCE, "AlgorithmIdentifier")
    oid := der.oid(b, alg[0])
    bits := der.bit_string(b, it[1])
    if oid == OID_EC_PUBLIC_KEY:
        name := _curve_name(der.oid(b, alg[1]))
        return ["ec", ec.public_key(ec.curve(name), bits), name]
    if oid == OID_RSA:
        k := der.items(bits, der.read(bits, 0), der.SEQUENCE, "RSAPublicKey")
        return ["rsa", rsa.PublicKey(der.integer(bits, k[0]), der.integer(bits, k[1])), null]
    return ["unsupported", null, _algo_name(oid)]

# Algorithme de signature d'un certificat : [« ec » / « pkcs1 » / « pss », empreinte], ou [null, OID].
func _sig_alg(b, node):
    it := der.items(b, node, der.SEQUENCE, "signatureAlgorithm")
    oid := der.oid(b, it[0])
    if oid in _SIG_ALGS:
        return _SIG_ALGS[oid]
    if oid == OID_RSA_PSS and len(it) > 1:
        # RSASSA-PSS-params : [0] hashAlgorithm (SHA-1 par défaut : refusé), [2] saltLength (20 par défaut)
        h := null
        salt := 20
        for p in der.children(b, it[1]):
            if p[0] == der.context(0):
                o := der.oid(b, der.children(b, der.children(b, p)[0])[0])
                if o == OID_SHA256:
                    h = "sha256"
                elif o == OID_SHA384:
                    h = "sha384"
                elif o == OID_SHA512:
                    h = "sha512"
            elif p[0] == der.context(2):
                salt = der.small_int(b, der.children(b, p)[0])
        if h != null:
            return ["pss", h, salt]
    return [null, oid]

func certificate_from_der(b):
    return Certificate(b)

# Certificats d'un texte PEM (str ou octets), dans l'ordre du fichier (feuille d'abord, puis intermédiaires).
func load_certificates(data):
    out := []
    for blk in pem_blocks(_text_of(data)):
        if blk[0] == "CERTIFICATE":
            append(out, Certificate(blk[1]))
    if len(out) == 0:
        _fail("aucun certificat PEM (« BEGIN CERTIFICATE ») trouvé")
    return out

# La clé privée correspond-elle à la clé publique du certificat ?
func key_matches(cert, key):
    pub := cert.public_key
    if key.kind != cert.key_kind or pub == null:
        return false
    if key.kind == "rsa":
        try:
            return bn.eq(pub.n, key.key.n) and bn.eq(pub.e, key.key.e)
        catch e:
            return false
    try:
        return pub.curve.name == key.curve and pub.to_bytes() == key.key.public_bytes()
    catch e:
        return false

# ---------------------------------------------------------------- vérification (client TLS)

# Le certificat cert est-il signé par la clé de issuer ?
func signed_by(cert, issuer):
    a := cert.signature_algorithm
    pub := issuer.public_key
    if a[0] == null or pub == null:
        return false
    try:
        if a[0] == "ec":
            return issuer.key_kind == "ec" and ec.verify_der(pub, cert.tbs, cert.signature, a[1])
        if issuer.key_kind != "rsa":
            return false
        if a[0] == "pkcs1":
            return rsa.verify_pkcs1(pub, cert.tbs, cert.signature, a[1])
        return rsa.verify_pss(pub, cert.tbs, cert.signature, a[1], a[2])
    catch e:
        return false

func _lower(t):
    return _s.lower(t)

# Le nom d'hôte (ou l'adresse IP en texte) figure-t-il dans le certificat ? Joker « *.domaine » sur un seul niveau ;
# le CN ne compte que si le certificat n'a pas d'extension subjectAltName.
func matches_host(cert, host):
    h := _lower(host)
    ip := _ip_bytes(h)
    if ip != null:
        for a in cert.ip_addresses:
            if a == ip:
                return true
        return false
    names := cert.dns_names
    if len(names) == 0 and len(cert.ip_addresses) == 0 and cert.subject_cn != null:
        names = [cert.subject_cn]
    for n in names:
        p := _lower(n)
        if p == h:
            return true
        if _s.starts_with(p, "*.") :
            rest := _s.substring(p, 1, len(p))
            dot := _s.find(h, ".")
            if dot > 0 and _s.substring(h, dot, len(h)) == rest:
                return true
    return false

func _ip_bytes(h):
    if _s.contains(h, ":"):
        return _ip6_bytes(h)
    parts := _s.split(h, ".")
    if len(parts) != 4:
        return null
    out := []
    for p in parts:
        if p == "" or len(p) > 3:
            return null
        v := 0
        for c in p:
            ch := str(c)
            if ch < "0" or ch > "9":
                return null
            v = v * 10 + (_s.ord(ch) - 48)
        if v > 255:
            return null
        append(out, v)
    return out

# Date UTC courante au format des certificats (« AAAA-MM-JJThh:mm:ssZ »).
func utc_now():
    return utc_text(_time.time())

func _two(n):
    return ("0" if n < 10 else "") + str(n)

# Secondes depuis 1970 -> texte UTC (algorithme des jours civils de H. Hinnant).
func utc_text(seconds):
    s := to_int(seconds)
    days := s // 86400
    rem := s - days * 86400
    z := days + 719468
    era := z // 146097
    doe := z - era * 146097
    yoe := (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    y := yoe + era * 400
    doy := doe - (365 * yoe + yoe // 4 - yoe // 100)
    mp := (5 * doy + 2) // 153
    d := doy - (153 * mp + 2) // 5 + 1
    m := mp + 3 if mp < 10 else mp - 9
    if m <= 2:
        y += 1
    return str(y) + "-" + _two(m) + "-" + _two(d) + "T" + _two(rem // 3600) + ":" + _two((rem // 60) % 60) + ":" + _two(rem % 60) + "Z"

func valid_at(cert, now):
    return cert.not_before <= now and now <= cert.not_after

# Vérifie une chaîne reçue (feuille d'abord) contre des ancres de confiance : la feuille est l'une des ancres
# (certificat épinglé), ou une suite de signatures mène de la feuille à une ancre en passant par des certificats
# d'autorité de la chaîne ; dates de chaque maillon et nom d'hôte (host null : non contrôlé). ValueError sinon.
func verify_chain(chain, anchors, host=null, now=null):
    if len(chain) == 0:
        _fail("chaîne vide")
    t := now if now != null else utc_now()
    leaf := chain[0]
    if host != null and not matches_host(leaf, host):
        _fail("le certificat ne couvre pas « " + host + " » (noms : " + _s.join(", ", leaf.dns_names) + ")")
    if not valid_at(leaf, t):
        _fail("certificat hors de sa période de validité (" + leaf.not_before + " — " + leaf.not_after + ")")
    for a in anchors:
        if a.der == leaf.der:
            return true
    cur := leaf
    depth := 0
    while depth < 8:
        for a in anchors:
            if a.subject_raw == cur.issuer_raw and signed_by(cur, a):
                if not valid_at(a, t):
                    _fail("autorité de confiance expirée (" + str(a.subject_cn) + ")")
                return true
        nxt := null
        for c in chain[1:len(chain)]:
            if nxt == null and c.is_ca and c.subject_raw == cur.issuer_raw and signed_by(cur, c):
                nxt = c
        if nxt == null:
            _fail("aucune autorité de confiance ne signe ce certificat (émetteur : " + str(_find(cur.issuer, OID_CN)) + ")")
        if not valid_at(nxt, t):
            _fail("certificat intermédiaire expiré (" + str(nxt.subject_cn) + ")")
        cur = nxt
        depth += 1
    _fail("chaîne trop longue")

# Certificats d'un fichier PEM d'autorités (ca_file, magasin du système) : ceux qu'on ne sait pas lire sont ignorés.
func load_trust(data):
    out := []
    for blk in pem_blocks(_text_of(data)):
        if blk[0] == "CERTIFICATE" or blk[0] == "TRUSTED CERTIFICATE":
            try:
                append(out, Certificate(blk[1]))
            catch e:
                ignored := e
    return out

# Adresse IPv6 en texte (« ::1 », « fe80::1 », forme complète) -> 16 octets, ou null.
func _ip6_bytes(h):
    t := h
    if _s.starts_with(t, "[") and _s.ends_with(t, "]"):
        t = _s.substring(t, 1, len(t) - 1)
    halves := _s.split(t, "::")
    if len(halves) > 2:
        return null
    head := _hex_groups(halves[0])
    tail := []
    if len(halves) == 2:
        tail = _hex_groups(halves[1])
    if head == null or tail == null:
        return null
    n := len(head) + len(tail)
    if (len(halves) == 1 and n != 8) or n > 8 or (len(halves) == 2 and n == 8):
        return null
    groups := head + [0] * (8 - n) + tail
    out := []
    for g in groups:
        append(out, g >> 8)
        append(out, g & 255)
    return out

func _hex_groups(part):
    if part == "":
        return []
    out := []
    for g in _s.split(part, ":"):
        if g == "" or len(g) > 4:
            return null
        v := 0
        for c in g:
            d := _s.find("0123456789abcdef", _s.lower(str(c)))
            if d < 0:
                return null
            v = v * 16 + d
        append(out, v)
    return out

# ---------------------------------------------------------------- création (certificats de développement)

func _oid_der(dotted):
    p := []
    for x in _s.split(dotted, "."):
        append(p, to_int(x))
    body := []
    vals := [p[0] * 40 + p[1]] + p[2:len(p)]
    for v0 in vals:
        v := v0
        chunk := [v & 127]
        v = v >> 7
        while v > 0:
            chunk = [(v & 127) | 128] + chunk
            v = v >> 7
        body = body + chunk
    return der.encode(der.OID, body)

# INTEGER positif depuis des octets big-endian.
func _int_der(b):
    i := 0
    while i < len(b) - 1 and b[i] == 0:
        i += 1
    v := b[i:len(b)]
    if len(v) == 0:
        v = [0]
    if v[0] >= 128:
        v = [0] + v
    return der.encode(der.INTEGER, v)

func _seq(body):
    return der.encode(der.SEQUENCE, body)

func _bits(b):
    return der.encode(der.BIT_STRING, [0] + b)

func _octets(b):
    return der.encode(der.OCTET_STRING, b)

# Date (secondes depuis 1970) : UTCTime avant 2050, GeneralizedTime ensuite (RFC 5280, 4.1.2.5).
func _time_der(seconds):
    t := utc_text(seconds)
    digits := _s.replace(_s.replace(_s.replace(t, "-", ""), ":", ""), "T", "")
    if to_int(_s.substring(t, 0, 4)) < 2050:
        return der.encode(der.UTC_TIME, _c.utf8_encode(_s.substring(digits, 2, len(digits))))
    return der.encode(der.GENERALIZED_TIME, _c.utf8_encode(digits))

func _ext(oid, critical, value):
    body := _oid_der(oid)
    if critical:
        body = body + [der.BOOLEAN, 1, 255]
    return _seq(body + _octets(value))

# Texte PEM d'un DER (lignes de 64 caractères).
func pem_encode(der_bytes, label):
    b := _c.base64_encode(der_bytes)
    out := "-----BEGIN " + label + "-----\n"
    i := 0
    n := _s.byte_len(b)
    while i < n:
        j := n
        if i + 64 < n:
            j = i + 64
        out = out + _s.byte_slice(b, i, j) + "\n"
        i = j
    return out + "-----END " + label + "-----\n"

# Certificat auto-signé de DÉVELOPPEMENT : clé EC P-256 neuve, signature ECDSA-SHA256, X.509 v3 avec
# subjectAltName (noms DNS et adresses IPv4 / IPv6 de names ; common_name par défaut), basicConstraints
# CA:FALSE, keyUsage digitalSignature, extendedKeyUsage serverAuth / clientAuth, subjectKeyIdentifier. Valable
# days jours à partir d'une minute avant now (secondes depuis 1970). Rend [certificat PEM, clé privée PEM
# (PKCS#8)].
func self_signed(common_name="localhost", names=null, days=365, now=null):
    if days < 1 or days > 36500:
        _fail("self_signed : days hors de 1..36500")
    sans := names
    if sans == null:
        sans = [common_name]
    c := ec.curve("P-256")
    priv := null
    while priv == null:
        try:
            priv = ec.private_key(c, _rnd.random_bytes(32))
        catch e:
            priv = null
    d := bn.to_bytes(priv.d, 32)
    pub := priv.public_bytes()
    alg := _seq(_oid_der(OID_EC_PUBLIC_KEY) + _oid_der(OID_P256))
    spki := _seq(alg + _bits(pub))
    pkcs8 := _seq(_int_der([0]) + alg + _octets(_seq(_int_der([1]) + _octets(d) + der.encode(der.context(1), _bits(pub)))))
    name := _seq(der.encode(der.SET, _seq(_oid_der(OID_CN) + der.encode(der.UTF8_STRING, _c.utf8_encode(common_name)))))
    sig_alg := _seq(_oid_der("1.2.840.10045.4.3.2"))
    serial := _rnd.random_bytes(16)
    serial[0] = (serial[0] & 127) | 64
    t := to_int(_time.time())
    if now != null:
        t = to_int(now)
    validity := _seq(_time_der(t - 60) + _time_der(t + days * 86400))
    entries := []
    for n in sans:
        ip := _ip_bytes(_s.lower(n))
        if ip != null:
            entries = entries + der.encode(der.context(7, false), ip)
        else:
            entries = entries + der.encode(der.context(2, false), _c.utf8_encode(n))
    exts := _ext(OID_SAN, false, _seq(entries))
    exts = exts + _ext(OID_BASIC_CONSTRAINTS, true, _seq([]))
    exts = exts + _ext("2.5.29.15", true, der.encode(der.BIT_STRING, [7, 128]))
    exts = exts + _ext("2.5.29.37", false, _seq(_oid_der("1.3.6.1.5.5.7.3.1") + _oid_der("1.3.6.1.5.5.7.3.2")))
    exts = exts + _ext("2.5.29.14", false, _octets(_c.sha256_bytes(pub)[0:20]))
    tbs := _seq(der.encode(der.context(0), _int_der([2])) + _int_der(serial) + sig_alg + name + validity + name + spki + der.encode(der.context(3), _seq(exts)))
    sig := ec.sign_der(priv, tbs, "sha256")
    cert := _seq(tbs + sig_alg + _bits(sig))
    return [pem_encode(cert, "CERTIFICATE"), pem_encode(pkcs8, "PRIVATE KEY")]
