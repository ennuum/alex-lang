# ALEX STANDARD LIBRARY — network.certificates
#
# Certificats X.509 (RFC 5280) : lecture PEM / DER, décodage ASN.1 DER, champs utiles (sujet, émetteur, validité,
# noms alternatifs, clé publique, extensions), empreintes, correspondance d'un nom d'hôte (RFC 6125), certificat
# présenté par un serveur TLS, et création de certificats auto-signés de développement (outil `openssl`).
#
#   load(chemin) / parse_pem(texte) -> list[Certificate]      parse_der(octets) -> Certificate
#   cert.subject_cn(), cert.san_dns, cert.not_after, cert.days_remaining(), cert.fingerprint("sha256")
#   cert.matches_hostname("www.exemple.org")
#   fetch(hôte, port) -> Certificate         certificat du serveur (sans le vérifier : pour l'inspecter)
#   check(hôte, port) -> dict                 diagnostic : vérifié ? nom ? jours restants ?
#   generate_self_signed(cert, clé, "localhost", ["localhost", "127.0.0.1"])
#
# La vérification de la chaîne de confiance relève d'OpenSSL (network.tls, verify=true) : ce module ne vérifie
# pas de signature.
#
# Erreurs : CertificateError (PEM / DER / certificat invalide), TlsError, NetworkError.
#
# Exemple
#   use network.certificates as certs
#   c := certs.fetch("exemple.org", 443)
#   print(c.subject_cn(), c.issuer_text(), c.days_remaining(), c.san_dns)

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use _native_tls as _t
use io as _io
use os as _os
use time as _time
use process as _proc
use crypto as _crypto
use network.encoding as _enc
use network.tls as _tls
use network.tcp as _tcp
use network.ipaddress as _ip

func _fail(message):
    raise("CertificateError", "certificates : " + message)

# ---------------------------------------------------------------- PEM

# Blocs PEM d'un texte : liste de (étiquette, octets DER).
func pem_decode(text):
    out := []
    lines := _s.split(_s.replace(text, "\r", ""), "\n")
    label := null
    body := []
    for line in lines:
        l := _s.trim(line)
        if _s.starts_with(l, "-----BEGIN ") and _s.ends_with(l, "-----"):
            label = _s.substring(l, 11, len(l) - 5)
            body = []
        elif _s.starts_with(l, "-----END ") and label != null:
            try:
                append(out, (label, _enc.base64_decode(_s.join("", body))))
            catch e:
                _fail("bloc PEM « " + label + " » : base64 invalide")
            label = null
        elif label != null and l != "" and not _s.contains(l, ":"):
            append(body, l)
    return out

# Bloc PEM (lignes de 64 caractères) pour des octets DER.
func pem_encode(der, label="CERTIFICATE"):
    b64 := _enc.base64_encode(der)
    lines := ["-----BEGIN " + label + "-----"]
    i := 0
    while i < len(b64):
        e := i + 64
        if e > len(b64):
            e = len(b64)
        append(lines, _s.substring(b64, i, e))
        i = e
    append(lines, "-----END " + label + "-----")
    return _s.join("\n", lines) + "\n"

# ---------------------------------------------------------------- ASN.1 DER

const UNIVERSAL := 0
const CONTEXT := 2

class Node:
    func init(cls, constructed, tag, data, start, header_len, length):
        self.cls = cls                    # 0 universel, 1 application, 2 contexte, 3 privé
        self.constructed = constructed
        self.tag = tag                    # numéro de l'étiquette
        self.data = data                  # list[int] de TOUT le document
        self.start = start                # position du premier octet du contenu
        self.header_len = header_len
        self.length = length              # longueur du contenu
        self.children_cache = null

    func end():
        return self.start + self.length

    func content():
        return self.data[self.start:self.start + self.length]

    # Octets DER complets (en-tête + contenu) en str brute.
    func der():
        return _n.from_bytes(self.data[self.start - self.header_len:self.start + self.length])

    func children():
        if self.children_cache == null:
            if not self.constructed:
                _fail("ASN.1 : élément primitif sans enfants")
            self.children_cache = _parse_seq(self.data, self.start, self.end())
        return self.children_cache

    func child(i):
        c := self.children()
        if i >= len(c):
            _fail("ASN.1 : élément " + str(i) + " absent")
        return c[i]

    func is_context(n):
        return self.cls == CONTEXT and self.tag == n

    func as_int():
        b := self.content()
        if len(b) == 0:
            return 0
        if len(b) > 8:
            _fail("ASN.1 : entier trop grand (voir as_hex)")
        v := 0
        if b[0] >= 128:
            v = -1
        for x in b:
            v = (v << 8) | x
        return v

    func as_hex():
        b := self.content()
        while len(b) > 1 and b[0] == 0:
            b = b[1:len(b)]
        return _enc.hex_encode(b)

    func as_bool():
        b := self.content()
        return len(b) > 0 and b[0] != 0

    func as_oid():
        b := self.content()
        if len(b) == 0:
            _fail("ASN.1 : OID vide")
        parts := []
        first := b[0]
        v := 0
        i := 0
        vals := []
        while i < len(b):
            v = (v << 7) | (b[i] & 127)
            if (b[i] & 128) == 0:
                append(vals, v)
                v = 0
            i += 1
        f := vals[0]
        if f < 40:
            append(parts, "0")
            append(parts, str(f))
        elif f < 80:
            append(parts, "1")
            append(parts, str(f - 40))
        else:
            append(parts, "2")
            append(parts, str(f - 80))
        k := 1
        while k < len(vals):
            append(parts, str(vals[k]))
            k += 1
        return _s.join(".", parts)

    # Texte des types chaîne (UTF8String, PrintableString, IA5String, BMPString, T61String...).
    func as_text():
        b := self.content()
        if self.tag == 30:      # BMPString : UTF-16BE
            return _enc.decode_charset(_n.from_bytes(b), "utf-16be", "replace")
        if self.tag == 20:      # T61String : en pratique ISO-8859-1
            raw := _n.from_bytes(b)
            if _n.utf8_valid(raw):
                return raw
            return _enc.decode_charset(raw, "iso-8859-1")
        return _enc.to_text(_n.from_bytes(b))

    # Horodatage Unix d'un UTCTime / GeneralizedTime.
    func as_time():
        t := self.as_text()
        y := 0
        rest := ""
        if self.tag == 23:
            y = to_int(_s.substring(t, 0, 2))
            if y >= 50:
                y += 1900
            else:
                y += 2000
            rest = _s.substring(t, 2, len(t))
        else:
            y = to_int(_s.substring(t, 0, 4))
            rest = _s.substring(t, 4, len(t))
        mo := to_int(_s.substring(rest, 0, 2))
        d := to_int(_s.substring(rest, 2, 4))
        h := to_int(_s.substring(rest, 4, 6))
        mi := to_int(_s.substring(rest, 6, 8))
        sec := 0
        if len(rest) >= 10 and rest[8] >= '0' and rest[8] <= '9':
            sec = to_int(_s.substring(rest, 8, 10))
        return _time.days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + sec

    # Contenu d'une BIT STRING (sans l'octet des bits inutilisés).
    func bit_string():
        b := self.content()
        if len(b) == 0:
            return []
        return b[1:len(b)]

func _read_node(data, pos, limit):
    if pos + 2 > limit:
        _fail("ASN.1 : élément tronqué")
    first := data[pos]
    cls := first >> 6
    constructed := (first & 32) != 0
    tag := first & 31
    p := pos + 1
    if tag == 31:
        tag = 0
        while true:
            if p >= limit:
                _fail("ASN.1 : étiquette tronquée")
            x := data[p]
            p += 1
            tag = (tag << 7) | (x & 127)
            if (x & 128) == 0:
                break
    if p >= limit:
        _fail("ASN.1 : longueur absente")
    lb := data[p]
    p += 1
    length := lb
    if lb >= 128:
        n := lb & 127
        if n == 0 or n > 4:
            _fail("ASN.1 : longueur indéfinie ou trop grande (DER attendu)")
        length = 0
        k := 0
        while k < n:
            if p >= limit:
                _fail("ASN.1 : longueur tronquée")
            length = (length << 8) | data[p]
            p += 1
            k += 1
    if p + length > limit:
        _fail("ASN.1 : contenu tronqué (" + str(length) + " octets annoncés)")
    return Node(cls, constructed, tag, data, p, p - pos, length)

func _parse_seq(data, start, end):
    out := []
    pos := start
    while pos < end:
        node := _read_node(data, pos, end)
        append(out, node)
        pos = node.end()
    return out

# Élément ASN.1 racine d'octets DER (str brute ou liste).
func parse_asn1(der):
    data := der
    if type(der) == "str":
        data = _n.to_bytes(der)
    return _read_node(data, 0, len(data))

# ---------------------------------------------------------------- noms d'OID

_OIDS := {"2.5.4.3": "CN", "2.5.4.4": "SN", "2.5.4.5": "serialNumber", "2.5.4.6": "C", "2.5.4.7": "L", "2.5.4.8": "ST", "2.5.4.9": "street", "2.5.4.10": "O", "2.5.4.11": "OU", "2.5.4.12": "title", "2.5.4.42": "GN", "2.5.4.97": "organizationIdentifier", "1.2.840.113549.1.9.1": "emailAddress", "0.9.2342.19200300.100.1.25": "DC", "0.9.2342.19200300.100.1.1": "UID", "1.2.840.113549.1.1.1": "rsaEncryption", "1.2.840.113549.1.1.5": "sha1WithRSAEncryption", "1.2.840.113549.1.1.11": "sha256WithRSAEncryption", "1.2.840.113549.1.1.12": "sha384WithRSAEncryption", "1.2.840.113549.1.1.13": "sha512WithRSAEncryption", "1.2.840.113549.1.1.10": "rsassaPss", "1.2.840.10045.2.1": "ecPublicKey", "1.2.840.10045.4.3.2": "ecdsa-with-SHA256", "1.2.840.10045.4.3.3": "ecdsa-with-SHA384", "1.2.840.10045.4.3.4": "ecdsa-with-SHA512", "1.3.101.112": "Ed25519", "1.3.101.113": "Ed448", "1.2.840.10045.3.1.7": "prime256v1", "1.3.132.0.34": "secp384r1", "1.3.132.0.35": "secp521r1", "2.5.29.14": "subjectKeyIdentifier", "2.5.29.15": "keyUsage", "2.5.29.17": "subjectAltName", "2.5.29.19": "basicConstraints", "2.5.29.31": "cRLDistributionPoints", "2.5.29.32": "certificatePolicies", "2.5.29.35": "authorityKeyIdentifier", "2.5.29.37": "extKeyUsage", "1.3.6.1.5.5.7.1.1": "authorityInfoAccess", "1.3.6.1.4.1.11129.2.4.2": "ctPrecertificateSCTs", "1.3.6.1.5.5.7.3.1": "serverAuth", "1.3.6.1.5.5.7.3.2": "clientAuth", "1.3.6.1.5.5.7.3.3": "codeSigning", "1.3.6.1.5.5.7.3.4": "emailProtection", "1.3.6.1.5.5.7.3.8": "timeStamping", "1.3.6.1.5.5.7.3.9": "OCSPSigning", "1.3.6.1.5.5.7.48.1": "OCSP", "1.3.6.1.5.5.7.48.2": "caIssuers"}

# Nom court d'un OID (« 2.5.4.3 » -> « CN »), ou l'OID lui-même.
func oid_name(oid):
    if contains_key(_OIDS, oid):
        return _OIDS[oid]
    return oid

const _KEY_USAGES := ["digitalSignature", "nonRepudiation", "keyEncipherment", "dataEncipherment", "keyAgreement", "keyCertSign", "cRLSign", "encipherOnly", "decipherOnly"]

# ---------------------------------------------------------------- certificat

class Certificate:
    func init(der):
        raw := der
        if type(der) == "list":
            raw = _n.from_bytes(der)
        self.der = raw
        root := null
        try:
            root = parse_asn1(raw)
            self._decode(root)
        catch e:
            if e.type == "CertificateError":
                raise(e)
            _fail("certificat X.509 illisible : " + e.message)

    func _decode(root):
        tbs := root.child(0)
        self.signature_algorithm = oid_name(root.child(1).child(0).as_oid())
        fields := tbs.children()
        i := 0
        self.version = 1
        if fields[0].is_context(0):
            self.version = fields[0].child(0).as_int() + 1
            i = 1
        self.serial = fields[i].as_hex()
        sig_alg := fields[i + 1]
        self.issuer = _decode_name(fields[i + 2])
        validity := fields[i + 3]
        self.not_before = validity.child(0).as_time()
        self.not_after = validity.child(1).as_time()
        self.subject = _decode_name(fields[i + 4])
        spki := fields[i + 5]
        self._decode_key(spki)
        self.san_dns = []
        self.san_ip = []
        self.san_email = []
        self.san_uri = []
        self.is_ca = false
        self.path_length = null
        self.key_usage = []
        self.extended_key_usage = []
        self.extensions = []          # [nom, critique]
        self.ocsp_urls = []
        self.ca_issuer_urls = []
        k := i + 6
        while k < len(fields):
            f := fields[k]
            if f.is_context(3):
                for ext in f.child(0).children():
                    self._decode_extension(ext)
            k += 1

    func _decode_key(spki):
        alg := spki.child(0)
        self.key_algorithm = oid_name(alg.child(0).as_oid())
        self.key_curve = null
        self.key_size = null
        if len(alg.children()) > 1 and alg.child(1).tag == 6:
            self.key_curve = oid_name(alg.child(1).as_oid())
        bits := spki.child(1).bit_string()
        if self.key_algorithm == "rsaEncryption":
            try:
                rsa := parse_asn1(bits)
                mod := rsa.child(0).content()
                while len(mod) > 0 and mod[0] == 0:
                    mod = mod[1:len(mod)]
                n := len(mod) * 8
                if len(mod) > 0:
                    top := mod[0]
                    while top < 128:
                        n -= 1
                        top = top << 1
                self.key_size = n
            catch e:
                self.key_size = null
        elif self.key_curve == "prime256v1":
            self.key_size = 256
        elif self.key_curve == "secp384r1":
            self.key_size = 384
        elif self.key_curve == "secp521r1":
            self.key_size = 521
        elif self.key_algorithm == "Ed25519":
            self.key_size = 256

    func _decode_extension(ext):
        parts := ext.children()
        oid := parts[0].as_oid()
        critical := false
        vi := 1
        if len(parts) == 3:
            critical = parts[1].as_bool()
            vi = 2
        append(self.extensions, [oid_name(oid), critical])
        value := parse_asn1(parts[vi].content())
        if oid == "2.5.29.17":
            for gn in value.children():
                if gn.is_context(2):
                    append(self.san_dns, _s.lower(_n.from_bytes(gn.content())))
                elif gn.is_context(7):
                    b := gn.content()
                    if len(b) == 4 or len(b) == 16:
                        append(self.san_ip, _ip.ip_address(_ip_from_bytes(b)).str())
                elif gn.is_context(1):
                    append(self.san_email, _n.from_bytes(gn.content()))
                elif gn.is_context(6):
                    append(self.san_uri, _n.from_bytes(gn.content()))
        elif oid == "2.5.29.19":
            for c in value.children():
                if c.tag == 1:
                    self.is_ca = c.as_bool()
                elif c.tag == 2:
                    self.path_length = c.as_int()
        elif oid == "2.5.29.15":
            b := value.content()
            if len(b) > 1:
                bitsb := b[1:len(b)]
                idx := 0
                for byte in bitsb:
                    bit := 7
                    while bit >= 0:
                        if (byte >> bit) & 1 == 1 and idx < len(_KEY_USAGES):
                            append(self.key_usage, _KEY_USAGES[idx])
                        idx += 1
                        bit -= 1
        elif oid == "2.5.29.37":
            for c in value.children():
                append(self.extended_key_usage, oid_name(c.as_oid()))
        elif oid == "1.3.6.1.5.5.7.1.1":
            for ad in value.children():
                method := ad.child(0).as_oid()
                loc := ad.child(1)
                if loc.is_context(6):
                    u := _n.from_bytes(loc.content())
                    if method == "1.3.6.1.5.5.7.48.1":
                        append(self.ocsp_urls, u)
                    elif method == "1.3.6.1.5.5.7.48.2":
                        append(self.ca_issuer_urls, u)

    # Nom commun (CN) du sujet, ou null.
    func subject_cn():
        return _first(self.subject, "CN")

    func issuer_cn():
        return _first(self.issuer, "CN")

    func subject_text():
        return _name_text(self.subject)

    func issuer_text():
        return _name_text(self.issuer)

    func is_self_signed():
        return _name_text(self.subject) == _name_text(self.issuer)

    # Vrai si le certificat est dans sa période de validité à l'instant `at` (défaut : maintenant).
    func is_valid_at(at=null):
        t := at
        if t == null:
            t = _time.time()
        return t >= self.not_before and t <= self.not_after

    func is_expired(at=null):
        t := at
        if t == null:
            t = _time.time()
        return t > self.not_after

    # Jours entiers restants avant expiration (négatif si expiré).
    func days_remaining(at=null):
        t := at
        if t == null:
            t = _time.time()
        return to_int((self.not_after - t) // 86400)

    # Empreinte « AB:CD:... » (sha256 par défaut, ou sha1).
    func fingerprint(algo="sha256", separator=":"):
        h := null
        if _t.supported():
            h = _t.digest(algo, self.der)
        if h == null:
            h = _n.from_bytes(_crypto_hash(algo, self.der))
        hx := _enc.hex_encode(h, true)
        if separator == "":
            return hx
        parts := []
        i := 0
        while i < len(hx):
            append(parts, _s.substring(hx, i, i + 2))
            i += 2
        return _s.join(separator, parts)

    # Noms DNS couverts (SAN, sinon CN par compatibilité).
    func dns_names():
        if len(self.san_dns) > 0:
            return self.san_dns
        cn := self.subject_cn()
        if cn != null:
            return [_s.lower(cn)]
        return []

    # Vrai si le certificat couvre ce nom d'hôte ou cette adresse IP (RFC 6125 : joker « * » seulement comme
    # étiquette la plus à gauche entière, jamais sur un suffixe public d'un seul niveau).
    func matches_hostname(host):
        h := _s.lower(host)
        if _s.ends_with(h, "."):
            h = _s.substring(h, 0, len(h) - 1)
        if _ip.is_ip(h):
            a := _ip.ip_address(h).str()
            for x in self.san_ip:
                if x == a:
                    return true
            return false
        for pattern in self.dns_names():
            if _match_name(pattern, h):
                return true
        return false

    func to_pem():
        return pem_encode(self.der)

    # Résumé lisible (dict).
    func summary():
        return {"subject": self.subject_text(), "issuer": self.issuer_text(), "serial": self.serial, "not_before": _iso(self.not_before), "not_after": _iso(self.not_after), "dns_names": self.dns_names(), "ip_addresses": self.san_ip, "key": self.key_algorithm + " " + str(self.key_size), "signature": self.signature_algorithm, "is_ca": self.is_ca, "fingerprint_sha256": self.fingerprint()}

    func str():
        return "Certificate(" + self.subject_text() + ", émis par " + self.issuer_text() + ", jusqu'au " + _iso(self.not_after) + ")"

func _crypto_hash(algo, raw):
    return _crypto.hash_bytes(algo, _n.to_bytes(raw))

func _iso(ts):
    d := ts // 86400
    rem := ts - d * 86400
    ymd := _time.civil_from_days(d)
    return str(ymd[0]) + "-" + _pad2(ymd[1]) + "-" + _pad2(ymd[2]) + "T" + _pad2(rem // 3600) + ":" + _pad2((rem % 3600) // 60) + ":" + _pad2(rem % 60) + "Z"

func _pad2(n):
    if n < 10:
        return "0" + str(n)
    return str(n)

func _ip_from_bytes(b):
    if len(b) == 4:
        return _ip.IPv4Address(b)
    return _ip.IPv6Address(b)

func _decode_name(node):
    out := []    # [nom court, valeur] dans l'ordre
    for rdn in node.children():
        for atv in rdn.children():
            oid := atv.child(0).as_oid()
            append(out, [oid_name(oid), atv.child(1).as_text()])
    return out

func _first(name, key):
    for p in name:
        if p[0] == key:
            return p[1]
    return null

func _name_text(name):
    parts := []
    for p in name:
        append(parts, p[0] + "=" + p[1])
    return _s.join(", ", parts)

func _match_name(pattern, host):
    p := _s.lower(pattern)
    if p == host:
        return true
    if not _s.starts_with(p, "*."):
        return false
    rest := _s.substring(p, 1, len(p))         # « .exemple.org »
    if _s.count(rest, ".") < 2:
        return false                             # « *.com » refusé
    if not _s.ends_with(host, rest):
        return false
    label := _s.substring(host, 0, len(host) - len(rest))
    return label != "" and not _s.contains(label, ".")

# Certificat depuis des octets DER.
func parse_der(der):
    return Certificate(der)

# Certificats d'un texte PEM (chaîne : feuille d'abord).
func parse_pem(text):
    out := []
    for block in pem_decode(text):
        if block[0] == "CERTIFICATE" or block[0] == "TRUSTED CERTIFICATE" or block[0] == "X509 CERTIFICATE":
            append(out, Certificate(block[1]))
    if len(out) == 0:
        _fail("aucun bloc CERTIFICATE dans le texte PEM")
    return out

# Certificats d'un fichier PEM ou DER.
func load(path):
    raw := _n.from_bytes(_io.read_bytes(path))
    if _n.bfind(raw, "-----BEGIN", 0) >= 0:
        return parse_pem(raw)
    return [Certificate(raw)]

# ---------------------------------------------------------------- serveurs TLS

# Certificat présenté par un serveur TLS (aucune vérification : pour l'inspecter, même expiré ou auto-signé).
func fetch(host, port=443, timeout=10.0, server_name=null):
    if not _tls.supported():
        raise("IoError", "certificates.fetch : TLS indisponible — " + _tls.why())
    name := server_name
    if name == null:
        name = host
    conn := _tls.connect(host, port, timeout, false, null, null, 0, name)
    try:
        der := _t.peer_certificate(conn.socket.handle)
        if der == null:
            _fail(host + " n'a présenté aucun certificat")
        c := Certificate(der)
        conn.close()
        return c
    catch e:
        conn.close()
        raise(e)

# Diagnostic d'un serveur TLS : chaîne vérifiée par OpenSSL ? nom couvert ? jours restants ? (dict)
func check(host, port=443, timeout=10.0, ca_file=null, warn_days=30):
    out := {"host": host, "port": port, "trusted": false, "error": null, "hostname_ok": false, "days_remaining": null, "expires": null, "subject": null, "issuer": null, "tls_version": null, "warning": null}
    try:
        conn := _tls.connect(host, port, timeout, true, ca_file)
        out["trusted"] = true
        out["tls_version"] = conn.socket.version
        conn.close()
    catch e:
        out["error"] = e.type + " : " + e.message
    c := fetch(host, port, timeout)
    out["hostname_ok"] = c.matches_hostname(host)
    out["days_remaining"] = c.days_remaining()
    out["expires"] = _iso(c.not_after)
    out["subject"] = c.subject_text()
    out["issuer"] = c.issuer_text()
    if c.is_expired():
        out["warning"] = "certificat expiré"
    elif c.days_remaining() < warn_days:
        out["warning"] = "expire dans " + str(c.days_remaining()) + " jours"
    return out

# ---------------------------------------------------------------- certificats de développement

# Crée un certificat auto-signé et sa clé (PEM) avec l'outil `openssl` (absent : IoError). names : noms DNS et
# adresses IP couverts (SAN). key : "ec" (P-256, défaut) ou "rsa" (2048 bits). Rend le Certificate créé.
func generate_self_signed(cert_path, key_path, common_name="localhost", names=null, days=365, key="ec"):
    sans := names
    if sans == null:
        sans = [common_name]
    alt := []
    for n in sans:
        if _ip.is_ip(n):
            append(alt, "IP:" + n)
        else:
            append(alt, "DNS:" + n)
    args := ["req", "-x509", "-nodes", "-days", str(days), "-subj", "/CN=" + common_name, "-keyout", key_path, "-out", cert_path, "-addext", "subjectAltName=" + _s.join(",", alt), "-addext", "basicConstraints=critical,CA:FALSE", "-addext", "keyUsage=digitalSignature,keyEncipherment", "-addext", "extendedKeyUsage=serverAuth,clientAuth"]
    if key == "rsa":
        args = args + ["-newkey", "rsa:2048"]
    else:
        args = args + ["-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1"]
    r := null
    try:
        r = _proc.Command("openssl").args(args).stdout("pipe").stderr("pipe").run(null, 60.0)
    catch e:
        raise("IoError", "certificates.generate_self_signed : outil openssl introuvable (" + e.message + ")")
    if r.code != 0:
        raise("IoError", "certificates.generate_self_signed : openssl a échoué : " + r.stderr)
    return load(cert_path)[0]
