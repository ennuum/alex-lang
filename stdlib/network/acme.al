# ALEX STANDARD LIBRARY — network.acme
#
# Client ACME (RFC 8555) : obtenir et renouveler des certificats auprès d'une autorité automatique (Let's
# Encrypt, ou tout serveur ACME : Pebble pour les tests), par le défi http-01. Écrit en ALEX : fonctionne aussi
# dans un exécutable natif (HTTPS par network.tls13, signatures par crypto.ec, CSR par crypto.x509).
#
#   use network.acme as acme
#   if acme.needs_renewal("certs/site.pem", ["exemple.org"]):
#       acme.issue(acme.LETSENCRYPT, "certs/compte.key", "certs/site.pem", "certs/site.key", ["exemple.org"],
#                  "certs/defis", "admin@exemple.org")
#   # le site sert http://exemple.org/.well-known/acme-challenge/<jeton> depuis le dossier certs/defis
#
#   c := acme.Client(acme.LETSENCRYPT_STAGING, cle_compte)       # niveau intermédiaire
#   c.register("admin@exemple.org") ; chaine := c.obtain(["exemple.org"], cle_certificat, "certs/defis")
#
# Compte et certificats : clés EC P-256, signatures ES256. Le défi http-01 est déposé en fichier (<dossier>/<jeton>,
# contenu : autorisation de clé) ; à l'application de le servir sur le port 80 (alweb le fait : server.tls.acme).
# Erreurs : AcmeError (réponse d'erreur de l'autorité, « type : détail »), TimeoutError (validation trop
# longue), NetworkError / TlsError / HttpError (réseau).

from core use len, type, to_int
from collections use append, keys
use string as _s
use time as _time
use io as _io
use os as _os
use json as _json
use crypto as _c
use crypto.ec as _ec
use crypto.bigint as _bn
use crypto.x509 as _x509
use network.http as _http

LETSENCRYPT := "https://acme-v02.api.letsencrypt.org/directory"
LETSENCRYPT_STAGING := "https://acme-staging-v02.api.letsencrypt.org/directory"
CHALLENGE_PATH := "/.well-known/acme-challenge/"

func _fail(message):
    raise("AcmeError", "acme : " + message)

func _b64u(b):
    return _c.base64_encode(b, true)

func _b64u_text(t):
    return _b64u(_c.utf8_encode(t))

# Jeton de défi utilisable comme nom de fichier (alphabet base64url, RFC 8555 8.3).
func valid_token(t):
    if type(t) != "str" or t == "" or _s.byte_len(t) > 256:
        return false
    for ch in t:
        c := str(ch)
        if not (_s.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_", c)):
            return false
    return true

class Client:
    # directory_url : annuaire de l'autorité ; account_key : crypto.x509.PrivateKey EC P-256 (null : clé neuve) ;
    # ca_file / verify : autorité de l'API elle-même (Pebble : son certificat de test).
    func init(directory_url, account_key=null, ca_file=null, verify=true, timeout=30.0):
        self.url = directory_url
        self.key = account_key if account_key != null else _x509.new_ec_key()
        if self.key.kind != "ec" or self.key.curve != "P-256":
            _fail("clé de compte EC P-256 attendue")
        self.ca_file = ca_file
        self.verify = verify
        self.timeout = timeout
        self.dir = null
        self.nonce = null
        self.kid = null
        pub := self.key.key.public_bytes()
        self.x = _b64u(pub[1:33])
        self.y = _b64u(pub[33:65])

    func jwk():
        return {"crv": "P-256", "kty": "EC", "x": self.x, "y": self.y}

    # Empreinte de la clé de compte (RFC 7638) : membres requis, triés, sans espaces.
    func thumbprint():
        return _b64u(_c.sha256_bytes(_c.utf8_encode("{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"" + self.x + "\",\"y\":\"" + self.y + "\"}")))

    # Contenu à servir pour le jeton d'un défi http-01.
    func key_authorization(token):
        return token + "." + self.thumbprint()

    func _req(method, url, body=null, headers=null):
        return _http.request(method, url, body, headers, self.timeout, false, 0, self.verify, self.ca_file)

    func directory():
        if self.dir == null:
            r := self._req("GET", self.url)
            if r.status != 200:
                _fail("annuaire " + self.url + " : statut " + str(r.status))
            self.dir = _json.parse(r.text())
            for k in ["newNonce", "newAccount", "newOrder"]:
                if not (k in self.dir):
                    _fail("annuaire sans « " + k + " »")
        return self.dir

    func _fresh_nonce():
        r := self._req("HEAD", self.directory()["newNonce"])
        n := r.header("Replay-Nonce")
        if n == null:
            _fail("newNonce sans Replay-Nonce")
        return n

    # Corps JWS (sérialisation JSON aplatie) : clé publique (jwk) pour newAccount, identifiant de compte (kid)
    # ensuite ; payload null : POST-as-GET (charge utile vide).
    func _jws(url, payload, use_jwk):
        prot := {"alg": "ES256", "nonce": self.nonce, "url": url}
        if use_jwk or self.kid == null:
            prot["jwk"] = self.jwk()
        else:
            prot["kid"] = self.kid
        p64 := _b64u_text(_json.stringify(prot))
        b64 := "" if payload == null else _b64u_text(_json.stringify(payload))
        sig := _ec.sign(self.key.key, _c.utf8_encode(p64 + "." + b64), "sha256")
        raw := _bn.to_bytes(sig[0], 32) + _bn.to_bytes(sig[1], 32)
        return _json.stringify({"protected": p64, "payload": b64, "signature": _b64u(raw)})

    # Requête signée ; badNonce : nouvel essai avec le jeton fourni par l'erreur (RFC 8555, 6.5).
    func post(url, payload=null, use_jwk=false):
        attempt := 0
        while true:
            if self.nonce == null:
                self.nonce = self._fresh_nonce()
            body := self._jws(url, payload, use_jwk)
            self.nonce = null
            r := self._req("POST", url, body, {"Content-Type": "application/jose+json"})
            n := r.header("Replay-Nonce")
            if n != null:
                self.nonce = n
            if r.status < 400:
                return r
            problem := {}
            try:
                problem = _json.parse(r.text())
            catch e:
                problem = {"detail": r.text()}
            kind := problem["type"] if "type" in problem else "?"
            if kind == "urn:ietf:params:acme:error:badNonce" and attempt < 3:
                attempt += 1
                continue
            detail := problem["detail"] if "detail" in problem else ""
            _fail(_s.replace(str(kind), "urn:ietf:params:acme:error:", "") + " : " + str(detail) + " (" + url + ", statut " + str(r.status) + ")")

    func get_json(url):
        return _json.parse(self.post(url, null).text())

    # Compte (créé, ou retrouvé pour cette clé) ; contact : adresse électronique ou null.
    func register(contact=null, agree_tos=true):
        payload := {"termsOfServiceAgreed": agree_tos}
        if contact != null and contact != "":
            payload["contact"] = ["mailto:" + contact]
        r := self.post(self.directory()["newAccount"], payload, true)
        self.kid = r.header("Location")
        if self.kid == null:
            _fail("newAccount sans Location")
        return _json.parse(r.text())

    func new_order(domains):
        ids := []
        for d in domains:
            append(ids, {"type": "dns", "value": d})
        r := self.post(self.directory()["newOrder"], {"identifiers": ids})
        o := _json.parse(r.text())
        o["url"] = r.header("Location")
        return o

    # Relit url jusqu'à un statut de done (rendu) ou d'échec (AcmeError), en respectant Retry-After.
    func wait(url, done, failed, max_wait=120.0, what="objet"):
        deadline := _time.monotonic() + max_wait
        while true:
            r := self.post(url, null)
            o := _json.parse(r.text())
            st := o["status"] if "status" in o else "?"
            if st in done:
                return o
            if st in failed:
                _fail(what + " " + st + _problem_text(o))
            if _time.monotonic() > deadline:
                raise("TimeoutError", "acme : " + what + " toujours « " + st + " » après " + str(max_wait) + " s")
            pause := 1.0
            ra := r.header("Retry-After")
            if ra != null:
                try:
                    pause = to_int(ra) * 1.0
                catch e:
                    pause = 1.0
            if pause < 0.5:
                pause = 0.5
            if pause > 10.0:
                pause = 10.0
            _time.sleep(pause)

    # Certificat pour domains : commande, défis http-01 déposés dans challenge_dir (fichiers <jeton>, retirés
    # ensuite), validation, CSR de cert_key (PrivateKey EC P-256), finalisation. Rend la chaîne PEM.
    func obtain(domains, cert_key, challenge_dir, max_wait=120.0):
        if self.kid == null:
            self.register()
        order := self.new_order(domains)
        posted := []
        try:
            for az_url in order["authorizations"]:
                az := self.get_json(az_url)
                if az["status"] == "valid":
                    continue
                ch := null
                for c in az["challenges"]:
                    if c["type"] == "http-01":
                        ch = c
                if ch == null:
                    _fail("pas de défi http-01 pour " + str(az["identifier"]["value"]))
                token := ch["token"]
                if not valid_token(token):
                    _fail("jeton de défi invalide")
                if not _os.exists(challenge_dir):
                    _os.mkdir_all(challenge_dir)
                path := _os.join(challenge_dir, token)
                _io.write_file(path, self.key_authorization(token))
                append(posted, path)
                self.post(ch["url"], {})
                self.wait(az_url, ["valid"], ["invalid", "deactivated", "expired", "revoked"], max_wait, "autorisation de " + str(az["identifier"]["value"]))
        finally:
            for p in posted:
                try:
                    _os.remove(p)
                catch e:
                    ignored := e
        o := self.wait(order["url"], ["ready", "valid"], ["invalid"], max_wait, "commande")
        if o["status"] == "ready":
            self.post(order["finalize"], {"csr": _b64u(_x509.csr(cert_key, domains))})
            o = self.wait(order["url"], ["valid"], ["invalid"], max_wait, "commande")
        if not ("certificate" in o):
            _fail("commande valide sans certificat")
        r := self.post(o["certificate"], null)
        chain := r.text()
        if not _s.contains(chain, "-----BEGIN CERTIFICATE-----"):
            _fail("certificat téléchargé illisible")
        return chain

func _problem_text(o):
    if "error" in o and type(o["error"]) == "dict":
        e := o["error"]
        return " : " + str(e["detail"] if "detail" in e else e)
    if "challenges" in o:
        for c in o["challenges"]:
            if "error" in c and type(c["error"]) == "dict" and "detail" in c["error"]:
                return " : " + str(c["error"]["detail"])
    return ""

# Clé de compte lue dans key_file, ou créée (PEM PKCS#8, mode 0600) si le fichier n'existe pas.
func account_key(key_file):
    if _os.exists(key_file):
        return _x509.load_private_key(_io.read_raw(key_file))
    k := _x509.new_ec_key()
    write_private(key_file, _x509.private_key_pem(k))
    return k

# Écrit text dans path d'un coup (fichier temporaire puis renommage) : lisible par le seul propriétaire.
func write_private(path, text):
    d := _os.dirname(path)
    if d != "" and not _os.exists(d):
        _os.mkdir_all(d)
    tmp := path + ".tmp"
    _io.write_file(tmp, text)
    try:
        _os.chmod(tmp, 384)
    catch e:
        ignored := e
    _os.move(tmp, path)

# Comme write_private, droits ordinaires (certificats).
func write_public(path, text):
    d := _os.dirname(path)
    if d != "" and not _os.exists(d):
        _os.mkdir_all(d)
    tmp := path + ".tmp"
    _io.write_file(tmp, text)
    _os.move(tmp, path)

# Faut-il (re)demander le certificat ? Fichier absent ou illisible, auto-signé (certificat d'attente), noms non
# couverts, ou expiration dans moins de days jours (moins du tiers de sa durée de vie s'il est plus court : un
# certificat de 6 jours est renouvelé à 2 jours de la fin, un de 90 jours à 30 jours).
func needs_renewal(cert_file, domains, days=30):
    if not _os.exists(cert_file):
        return true
    try:
        c := _x509.load_certificates(_io.read_raw(cert_file))[0]
        if c.issuer_raw == c.subject_raw:
            return true
        for d in domains:
            if not _x509.matches_host(c, d):
                return true
        # marge : days jours, ou le tiers de la durée de vie pour un certificat court (Let's Encrypt : 6 jours)
        life := _x509.utc_seconds(c.not_after) - _x509.utc_seconds(c.not_before)
        margin := days * 86400
        if life > 0 and life // 3 < margin:
            margin = life // 3
        return _x509.utc_seconds(c.not_after) - to_int(_time.time()) < margin
    catch e:
        return true

# Tout en un (utilisable dans un fil : thread.offload) : compte (clé account_key_file, créée au besoin), nouvelle
# clé de certificat, défis dans challenge_dir, puis écriture de key_file puis cert_file (chaîne complète), chacun
# remplacé d'un coup. Rend {"domains", "not_after"}.
func issue(directory_url, account_key_file, cert_file, key_file, domains, challenge_dir, contact=null, ca_file=null, verify=true, max_wait=120.0):
    c := Client(directory_url, account_key(account_key_file), ca_file, verify)
    c.register(contact)
    k := _x509.new_ec_key()
    chain := c.obtain(domains, k, challenge_dir, max_wait)
    leaf := _x509.load_certificates(chain)[0]
    if not _x509.key_matches(leaf, k):
        _fail("le certificat délivré ne correspond pas à la clé demandée")
    write_private(key_file, _x509.private_key_pem(k))
    write_public(cert_file, chain)
    return {"domains": domains, "not_after": leaf.not_after}
