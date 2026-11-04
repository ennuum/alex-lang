# ALEX STANDARD LIBRARY — security.capability
#
# Sécurité par capacités :
#   1. Jetons de capacité SIGNÉS (à la manière des « macaroons ») : un émetteur détenant une clé secrète
#      délivre un jeton portant une ressource, des droits et une échéance ; tout détenteur peut l'ATTÉNUER
#      (ajouter des restrictions : moins de droits, échéance plus proche, condition) sans la clé, mais personne
#      ne peut l'étendre. La vérification recalcule la chaîne de HMAC.
#   2. Capacités d'OBJETS dans le processus : facet(objet, méthodes) ne laisse passer que certaines méthodes ;
#      revocable(objet) donne un mandataire et une fonction de révocation.
#
#   use security.capability as cap
#   em := cap.Issuer(cle_secrete)
#   jeton := em.issue("fichiers/rapport.pdf", ["read", "write"], 3600)       # valable 1 h
#   lecture := cap.attenuate(jeton, {"rights": ["read"]})                    # sans la clé
#   c := em.verify(lecture)                    # Capability ; SignatureError si falsifié, expiré...
#   print(c.allows("read"), c.allows("write")) # true false
#   em.require(lecture, "write", "fichiers/rapport.pdf")       # PermissionError
#   lecteur := cap.facet(document, ["lire", "taille"])
#   lecteur.call("lire")                       # ok ; lecteur.call("effacer") -> PermissionError
#   r := cap.revocable(service) ; r[0].call("ping") ; r[1]() ; r[0].call("ping")   # PermissionError
#
# Restrictions (caveats) : rights (sous-ensemble), expires (horodatage), resource_prefix, subject, max_uses
# (comptabilisé par l'émetteur, pour ce jeton précis), et toute clé « ctx:* » comparée au contexte passé à verify.
# Erreurs : SignatureError (signature, format), PermissionError (droit, expiration, contexte), ArgumentError.

from core use len, type, to_int
from collections use append
use string as _s
use json as _json
use time as _time
use crypto as _c
use _native_reflect as _r
use security.security as _sec
use security.crypto_provider as _cp
use security.random_secure as _rnd

func _sig(key, data):
    return _cp.hmac("sha256", key, data)

func _encode(body, sig):
    return _c.base64_encode(_c.utf8_encode(_json.stringify(body)), true) + "." + _c.base64_encode(sig, true)

func _decode(token):
    parts := _s.split(token, ".")
    if len(parts) != 2:
        raise("SignatureError", "jeton de capacité mal formé")
    body := null
    sig := null
    try:
        body = _json.parse(_c.utf8_decode(_c.base64_decode(parts[0], true)))
        sig = _c.base64_decode(parts[1], true)
    catch e:
        raise("SignatureError", "jeton de capacité illisible")
    if type(body) != "dict" or not ("id" in body) or not ("caveats" in body):
        raise("SignatureError", "jeton de capacité invalide")
    return [body, sig]

class Capability:
    func init(id, resource, rights, expires, caveats):
        self.id = id
        self.resource = resource
        self.rights = rights
        self.expires = expires
        self.caveats = caveats

    func allows(right):
        return right in self.rights or "*" in self.rights

    func covers(resource):
        if resource == null:
            return true
        return resource == self.resource or (_s.ends_with(self.resource, "/*") and _s.starts_with(resource, _s.substring(self.resource, 0, len(self.resource) - 1)))

    func remaining():
        if self.expires == null:
            return null
        return self.expires - _time.time()

    func to_dict():
        return {"id": self.id, "resource": self.resource, "rights": self.rights, "expires": self.expires, "caveats": self.caveats}

class Issuer:
    func init(key, name="émetteur"):
        k := _sec.to_bytes(key)
        if len(k) < 16:
            raise("ArgumentError", "Issuer : clé d'au moins 16 octets attendue")
        self.key = k
        self.name = name
        self.revoked = {}
        self.uses = {}

    func issue(resource, rights, ttl=null, extra=null):
        cav := [{"rights": rights}]
        exp := null
        if ttl != null:
            exp = _time.time() + ttl
            append(cav, {"expires": exp})
        if extra != null:
            append(cav, extra)
        body := {"id": _rnd.token_hex(12), "issuer": self.name, "resource": resource, "caveats": []}
        sig := _sig(self.key, body["id"] + "|" + resource)
        for c in cav:
            sig = _sig(sig, _json.stringify(c))
            append(body["caveats"], c)
        return _encode(body, sig)

    func revoke(token_or_id):
        id := token_or_id
        if _s.contains(token_or_id, "."):
            id = _decode(token_or_id)[0]["id"]
        self.revoked[id] = true

    # Vérifie la chaîne de signatures et les restrictions ; Capability.
    func verify(token, context=null):
        d := _decode(token)
        body := d[0]
        sig := _sig(self.key, body["id"] + "|" + body["resource"])
        for c in body["caveats"]:
            sig = _sig(sig, _json.stringify(c))
        if not _sec.constant_time_equals(sig, d[1]):
            raise("SignatureError", "jeton de capacité : signature invalide (falsifié ou autre émetteur)")
        if body["id"] in self.revoked:
            raise("PermissionError", "jeton de capacité révoqué")
        ukey := _c.hex_encode(d[1])
        rights := null
        expires := null
        resource := body["resource"]
        now := _time.time()
        for c in body["caveats"]:
            for k in c:
                v := c[k]
                if k == "rights":
                    if rights == null:
                        rights = v
                    else:
                        rights = [r for r in rights if r in v]
                elif k == "expires":
                    if expires == null or v < expires:
                        expires = v
                elif k == "resource_prefix":
                    if not _s.starts_with(resource, v) and not _s.ends_with(resource, "/*"):
                        raise("PermissionError", "jeton de capacité : ressource hors du préfixe " + v)
                    resource = v + "*"
                elif k == "subject" or _s.starts_with(k, "ctx:"):
                    key := k
                    if _s.starts_with(k, "ctx:"):
                        key = _s.substring(k, 4, len(k))
                    if context == null or not (key in context) or not (context[key] == v):
                        raise("PermissionError", "jeton de capacité : condition « " + key + " = " + str(v) + " » non remplie")
                elif k == "max_uses":
                    n := 0
                    if ukey in self.uses:
                        n = self.uses[ukey]
                    if n >= v:
                        raise("PermissionError", "jeton de capacité : nombre d'utilisations épuisé")
        if expires != null and now >= expires:
            raise("PermissionError", "jeton de capacité expiré")
        if rights == null:
            rights = []
        if ukey in self.uses:
            self.uses[ukey] += 1
        else:
            self.uses[ukey] = 1
        return Capability(body["id"], resource, rights, expires, body["caveats"])

    func require(token, right, resource=null, context=null):
        c := self.verify(token, context)
        if not c.allows(right):
            raise("PermissionError", "jeton de capacité : droit « " + right + " » non accordé")
        if resource != null and not c.covers(resource) and not _s.starts_with(resource, _s.replace(c.resource, "*", "")):
            raise("PermissionError", "jeton de capacité : ressource « " + resource + " » non couverte")
        return c

# Ajoute une restriction à un jeton existant (sans la clé de l'émetteur).
func attenuate(token, caveat):
    d := _decode(token)
    body := d[0]
    append(body["caveats"], caveat)
    sig := _sig(d[1], _json.stringify(caveat))
    return _encode(body, sig)

func inspect(token):
    return _decode(token)[0]

# ---- capacités d'objets ----
class Facet:
    func init(target, methods, name="facette", parent=null):
        self._target = target
        self._methods = methods
        self._revoked = false
        self._parent = parent
        self.name = name

    func allowed():
        return self._methods[:]

    func call(method, *args):
        if self._revoked:
            raise("PermissionError", self.name + " : capacité révoquée")
        if self._methods != null and not (method in self._methods):
            raise("PermissionError", self.name + " : méthode « " + method + " » non accordée")
        if self._parent != null:
            return self._parent.call(method, *args)
        m := _r.method(self._target, method)
        if m == null:
            raise("AttributeError", self.name + " : méthode « " + method + " » inconnue")
        return m(*args)

    func revoke():
        self._revoked = true

    func narrow(methods):
        keep := [m for m in methods if self._methods == null or m in self._methods]
        return Facet(null, keep, self.name, self)

func facet(target, methods, name="facette"):
    return Facet(target, methods, name)

# [mandataire, révoquer()]
func revocable(target, methods=null):
    f := Facet(target, methods, "capacité révocable")
    return [f, () => f.revoke()]
