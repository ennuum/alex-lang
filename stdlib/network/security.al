# ALEX STANDARD LIBRARY — network.security
#
# Sécurité des applications réseau.
#
#   Aléa et secrets   random_bytes, random_token (base64 URL), random_hex, constant_time_equals
#   Empreintes        digest, hmac_sign / hmac_verify (libcrypto d'OpenSSL si présent, sinon module crypto)
#   Valeurs signées   sign_value / unsign_value (horodatées, durée de validité), jetons CSRF
#   Mots de passe     hash_password / verify_password (PBKDF2-HMAC-SHA256, sel aléatoire, format
#                     « pbkdf2_sha256$itérations$sel$empreinte »), needs_rehash
#   Requêtes sortantes  check_url / is_safe_url : refuse les destinations internes (SSRF) — boucle locale,
#                     réseaux privés, lien local, métadonnées de nuage — après résolution DNS
#   Redirections      is_safe_redirect : pas de redirection ouverte vers un autre site
#   En-têtes          security_headers (HSTS, CSP, X-Content-Type-Options...), build_csp
#   Débit             RateLimiter (seau à jetons par clé : adresse IP, utilisateur...)
#
# Erreurs : SecurityError (URL ou valeur refusée, signature invalide ou expirée), TypeError.
#
# Exemple
#   use network.security as sec
#   h := sec.hash_password("correct horse")
#   print(sec.verify_password("correct horse", h))          # true
#   jeton := sec.sign_value("utilisateur=42", secret)
#   print(sec.unsign_value(jeton, secret, 3600))             # utilisateur=42 (ou SecurityError)
#   sec.check_url("http://169.254.169.254/latest/")          # SecurityError : adresse interne

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use _native_tls as _t
use crypto as _crypto
use time as _time
use network.encoding as _enc
use network.url as _url
use network.dns as _dns
use network.ipaddress as _ip

func _fail(message):
    raise("SecurityError", "security : " + message)

func _raw(data):
    t := type(data)
    if t == "str":
        return data
    if t == "list" or t == "tuple":
        return _n.from_bytes(data)
    raise("TypeError", "network.security : str ou liste d'octets attendue (obtenu '" + t + "')")

# ---------------------------------------------------------------- aléa

# n octets aléatoires du système (str brute).
func random_bytes(n=32):
    return _n.random_bytes(n)

# Jeton aléatoire imprévisible en base64 URL (nbytes octets d'entropie ; 32 -> 43 caractères).
func random_token(nbytes=32):
    return _enc.base64_encode(_n.random_bytes(nbytes), true)

func random_hex(nbytes=16):
    return _enc.hex_encode(_n.random_bytes(nbytes))

# Entier aléatoire uniforme dans [0, n) (rejet : aucun biais de modulo).
func random_below(n):
    if type(n) != "int" or n < 1 or n > 4294967296:
        raise("ArgumentError", "security.random_below : entier 1..2^32 attendu")
    limit := (4294967296 // n) * n
    while true:
        b := _n.to_bytes(_n.random_bytes(4))
        v := ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3])
        if v < limit:
            return v % n

const _ALNUM := "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"

# Code lisible sans caractères ambigus (0/O, 1/l/I) : codes de vérification, mots de passe temporaires.
func random_code(length=10, alphabet=_ALNUM):
    out := []
    i := 0
    while i < length:
        append(out, str(alphabet[random_below(len(alphabet))]))
        i += 1
    return _s.join("", out)

# Égalité en temps constant (ne révèle pas la position du premier écart).
func constant_time_equals(a, b):
    x := _n.to_bytes(_raw(a))
    y := _n.to_bytes(_raw(b))
    diff := len(x) ^ len(y)
    n := len(x)
    if len(y) < n:
        n = len(y)
    i := 0
    while i < n:
        diff = diff | (x[i] ^ y[i])
        i += 1
    return diff == 0

# ---------------------------------------------------------------- empreintes et HMAC

func _check_algo(algo):
    if algo != "md5" and algo != "sha1" and algo != "sha256" and algo != "sha512" and algo != "sha384" and algo != "sha224":
        raise("ArgumentError", "security : algorithme inconnu '" + str(algo) + "'")

# Empreinte (str brute) : md5, sha1, sha224, sha256, sha384, sha512 (les deux du milieu exigent OpenSSL).
func digest(data, algo="sha256"):
    _check_algo(algo)
    raw := _raw(data)
    r := null
    if _t.supported():
        r = _t.digest(algo, raw)
    if r != null:
        return r
    if algo == "sha224" or algo == "sha384":
        _fail(algo + " exige OpenSSL (libcrypto)")
    return _n.from_bytes(_crypto.hash_bytes(algo, _n.to_bytes(raw)))

func digest_hex(data, algo="sha256"):
    return _enc.hex_encode(digest(data, algo))

func hmac(key, data, algo="sha256"):
    _check_algo(algo)
    k := _raw(key)
    d := _raw(data)
    r := null
    if _t.supported():
        r = _t.hmac(algo, k, d)
    if r != null:
        return r
    return _n.from_bytes(_crypto.hmac_bytes(algo, _n.to_bytes(k), _n.to_bytes(d)))

# Signature HMAC en hexadécimal.
func hmac_sign(key, data, algo="sha256"):
    return _enc.hex_encode(hmac(key, data, algo))

func hmac_verify(key, data, signature, algo="sha256"):
    return constant_time_equals(hmac_sign(key, data, algo), _s.lower(signature))

func pbkdf2(password, salt, iterations, length=32, algo="sha256"):
    p := _raw(password)
    s := _raw(salt)
    r := null
    if _t.supported():
        r = _t.pbkdf2(algo, p, s, iterations, length)
    if r != null:
        return r
    return _n.from_bytes(_crypto.pbkdf2_bytes(_n.to_bytes(p), _n.to_bytes(s), iterations, length, algo))

# ---------------------------------------------------------------- valeurs signées

# « valeur.horodatage.signature » (base64 URL) : intègre et datée, NON chiffrée (ne pas y mettre de secret).
func sign_value(value, secret, now=null, salt="alex.signed"):
    if type(value) != "str":
        raise("TypeError", "security.sign_value : str attendue")
    t := now
    if t == null:
        t = _time.time()
    payload := _enc.base64_encode(value, true) + "." + str(to_int(t))
    sig := _enc.base64_encode(hmac(_raw(secret) + salt, payload), true)
    return payload + "." + sig

# Valeur d'origine si la signature est valide et, avec max_age, si elle date de moins de max_age secondes.
func unsign_value(token, secret, max_age=null, now=null, salt="alex.signed"):
    if type(token) != "str":
        _fail("jeton signé invalide")
    parts := _s.split(token, ".")
    if len(parts) != 3:
        _fail("jeton signé mal formé")
    payload := parts[0] + "." + parts[1]
    expected := _enc.base64_encode(hmac(_raw(secret) + salt, payload), true)
    if not constant_time_equals(expected, parts[2]):
        _fail("signature invalide")
    ts := 0
    for c in parts[1]:
        if c < '0' or c > '9':
            _fail("horodatage invalide")
    ts = to_int(parts[1])
    if max_age != null:
        t := now
        if t == null:
            t = _time.time()
        if t - ts > max_age:
            _fail("jeton expiré")
    return _enc.base64_decode(parts[0], true)

# Jeton anti-CSRF lié à une session (aléa + HMAC) ; vérification par check_csrf_token.
func make_csrf_token(secret, session_id):
    nonce := random_token(16)
    return nonce + "." + _enc.base64_encode(hmac(_raw(secret), nonce + "|" + str(session_id)), true)

func check_csrf_token(token, secret, session_id):
    if type(token) != "str":
        return false
    parts := _s.split(token, ".")
    if len(parts) != 2:
        return false
    expected := _enc.base64_encode(hmac(_raw(secret), parts[0] + "|" + str(session_id)), true)
    return constant_time_equals(expected, parts[1])

# ---------------------------------------------------------------- mots de passe

const PASSWORD_ITERATIONS := 600000

# Empreinte de mot de passe « pbkdf2_sha256$itérations$sel$empreinte » (sel de 16 octets, 32 octets dérivés).
# Sans OpenSSL, PBKDF2 est calculé en ALEX : beaucoup plus lent, baisser `iterations` en connaissance de cause.
func hash_password(password, iterations=PASSWORD_ITERATIONS, salt=null):
    if type(password) != "str":
        raise("TypeError", "security.hash_password : str attendue")
    s := salt
    if s == null:
        s = random_token(16)
    dk := pbkdf2(password, s, iterations, 32, "sha256")
    return "pbkdf2_sha256$" + str(iterations) + "$" + s + "$" + _enc.base64_encode(dk, true)

func verify_password(password, encoded):
    if type(password) != "str" or type(encoded) != "str":
        return false
    parts := _s.split(encoded, "$")
    if len(parts) != 4 or parts[0] != "pbkdf2_sha256":
        return false
    for c in parts[1]:
        if c < '0' or c > '9':
            return false
    it := to_int(parts[1])
    if it < 1:
        return false
    dk := pbkdf2(password, parts[2], it, 32, "sha256")
    return constant_time_equals(_enc.base64_encode(dk, true), parts[3])

# Vrai si l'empreinte a été calculée avec moins d'itérations que demandé (à recalculer à la prochaine connexion).
func needs_rehash(encoded, iterations=PASSWORD_ITERATIONS):
    parts := _s.split(encoded, "$")
    if len(parts) != 4 or parts[0] != "pbkdf2_sha256":
        return true
    return to_int(parts[1]) < iterations

# ---------------------------------------------------------------- SSRF

# Destinations internes refusées par défaut (en plus de la boucle locale, des réseaux privés et du lien local).
const BLOCKED_NETWORKS := ["0.0.0.0/8", "100.64.0.0/10", "192.0.0.0/24", "198.18.0.0/15", "224.0.0.0/4", "240.0.0.0/4", "64:ff9b::/96", "ff00::/8", "fc00::/7", "fe80::/10"]

# Vrai si l'adresse IP n'est pas joignable publiquement (boucle locale, privée, lien local — dont les
# métadonnées de nuage 169.254.169.254 —, CGNAT, multicast, réservée, non spécifiée).
func is_internal_address(address):
    a := _ip.ip_address(address)
    m := a.ipv4_mapped()
    if m != null:
        a = m
    if a.is_loopback() or a.is_private() or a.is_link_local() or a.is_unspecified() or a.is_multicast() or a.is_reserved() or a.is_shared() or a.is_broadcast():
        return true
    for n in BLOCKED_NETWORKS:
        if _ip.ip_network(n).contains(a):
            return true
    return false

# Contrôle une URL avant une requête sortante dont la destination vient d'un tiers. Lève SecurityError si le
# schéma n'est pas permis ou si l'hôte (ou UNE de ses adresses résolues) est interne. Rend la liste des adresses
# vérifiées : se connecter à l'une d'elles (et non re-résoudre le nom) ferme la porte au « DNS rebinding ».
func check_url(target, schemes=null, allow_internal=false, allowed_hosts=null):
    allowed := schemes
    if allowed == null:
        allowed = ["http", "https"]
    u := null
    try:
        u = _url.parse(target)
    catch e:
        _fail("URL invalide : " + str(target))
    ok := false
    for s in allowed:
        if s == u.scheme:
            ok = true
    if not ok:
        _fail("schéma « " + u.scheme + " » non permis")
    if u.host == null or u.host == "":
        _fail("hôte manquant")
    if allowed_hosts != null:
        found := false
        for h in allowed_hosts:
            if _s.lower(h) == u.host or (_s.starts_with(h, ".") and _s.ends_with(u.host, _s.lower(h))):
                found = true
        if not found:
            _fail("hôte « " + u.host + " » hors de la liste autorisée")
    addrs := []
    if _ip.is_ip(u.host):
        addrs = [u.host]
    else:
        try:
            addrs = _dns.resolve(u.host)
        catch e:
            _fail("nom introuvable : " + u.host)
    if not allow_internal:
        for a in addrs:
            if is_internal_address(a):
                _fail("destination interne refusée : " + u.host + " -> " + a)
    return addrs

func is_safe_url(target, schemes=null, allow_internal=false):
    try:
        check_url(target, schemes, allow_internal)
        return true
    catch e:
        if e.type == "SecurityError":
            return false
        raise(e)

# Vrai si `target` (redirection demandée par un client, paramètre « next »...) reste sur un hôte permis :
# chemin relatif « /x » (mais pas « //x » ni « /\x »), ou URL absolue d'un hôte de allowed_hosts.
func is_safe_redirect(target, allowed_hosts=null, require_https=false):
    if type(target) != "str" or target == "":
        return false
    t := _s.trim(target)
    for c in t:
        if _s.ord(c) < 32:
            return false
    if _s.starts_with(t, "/"):
        return not (_s.starts_with(t, "//") or _s.starts_with(t, "/\\"))
    try:
        u := _url.parse(t)
        if u.scheme != "https" and (require_https or u.scheme != "http"):
            return false
        if allowed_hosts == null:
            return false
        for h in allowed_hosts:
            if _s.lower(h) == u.host:
                return true
        return false
    catch e:
        return false

# ---------------------------------------------------------------- en-têtes de sécurité

# Valeur de Content-Security-Policy depuis un dict directive -> liste de sources (ou str).
func build_csp(directives):
    out := []
    for k in keys(directives):
        v := directives[k]
        if type(v) == "list":
            append(out, k + " " + _s.join(" ", v))
        elif v == true or v == "":
            append(out, k)
        else:
            append(out, k + " " + str(v))
    return _s.join("; ", out)

# En-têtes recommandés pour une réponse HTTP (dict). hsts_seconds : null pour ne pas envoyer HSTS (à n'envoyer
# qu'en HTTPS) ; csp : str, dict (build_csp) ou null ; frame : "DENY", "SAMEORIGIN" ou null.
func security_headers(hsts_seconds=31536000, csp="default-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'", frame="DENY", referrer="strict-origin-when-cross-origin", include_subdomains=true):
    h := {"X-Content-Type-Options": "nosniff", "Referrer-Policy": referrer, "Cross-Origin-Opener-Policy": "same-origin", "Permissions-Policy": "camera=(), microphone=(), geolocation=()"}
    if frame != null:
        h["X-Frame-Options"] = frame
    if csp != null:
        if type(csp) == "dict":
            h["Content-Security-Policy"] = build_csp(csp)
        else:
            h["Content-Security-Policy"] = csp
    if hsts_seconds != null:
        v := "max-age=" + str(hsts_seconds)
        if include_subdomains:
            v += "; includeSubDomains"
        h["Strict-Transport-Security"] = v
    return h

# ---------------------------------------------------------------- limitation de débit

class RateLimiter:
    # rate : jetons rendus par seconde ; burst : capacité du seau (requêtes possibles d'un coup) ;
    # max_keys : clés suivies au plus (les plus anciennes sont oubliées).
    func init(rate, burst, max_keys=100000, clock=null):
        if rate <= 0 or burst < 1:
            raise("ArgumentError", "security.RateLimiter : rate > 0 et burst >= 1 attendus")
        self.rate = rate * 1.0
        self.burst = burst * 1.0
        self.max_keys = max_keys
        self.clock = clock
        self.buckets = {}     # clé -> [jetons, dernière mise à jour]
        self.denied = 0

    func _now():
        if self.clock != null:
            return self.clock()
        return _time.monotonic()

    func _bucket(key, now):
        if not contains_key(self.buckets, key):
            if len(keys(self.buckets)) >= self.max_keys:
                self._evict(now)
            self.buckets[key] = [self.burst, now]
        b := self.buckets[key]
        elapsed := now - b[1]
        if elapsed > 0:
            b[0] = b[0] + elapsed * self.rate
            if b[0] > self.burst:
                b[0] = self.burst
            b[1] = now
        return b

    func _evict(now):
        # oublie les seaux pleins (inactifs) ; à défaut, tout
        kept := {}
        for k in keys(self.buckets):
            b := self.buckets[k]
            if b[0] + (now - b[1]) * self.rate < self.burst:
                kept[k] = b
        if len(keys(kept)) >= self.max_keys:
            kept = {}
        self.buckets = kept

    # Consomme `cost` jetons pour `key` ; false (requête à refuser, 429) s'il n'y en a pas assez.
    func allow(key, cost=1):
        now := self._now()
        b := self._bucket(key, now)
        if b[0] >= cost:
            b[0] = b[0] - cost
            return true
        self.denied += 1
        return false

    # Secondes à attendre avant que `cost` jetons soient disponibles (0 si c'est déjà le cas).
    func retry_after(key, cost=1):
        now := self._now()
        b := self._bucket(key, now)
        if b[0] >= cost:
            return 0.0
        return (cost - b[0]) / self.rate

    func remaining(key):
        return self._bucket(key, self._now())[0]

    func reset(key=null):
        if key == null:
            self.buckets = {}
        elif contains_key(self.buckets, key):
            self.buckets[key] = [self.burst, self._now()]
