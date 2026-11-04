# ALEX STANDARD LIBRARY — security.credential_store
#
# Coffres de secrets (identifiants, jetons, clés d'API) :
#   CredentialStore(chemin, mot_de_passe)  fichier CHIFFRÉ (enveloppe authentifiée de crypto_provider, clé
#                                          dérivée du mot de passe maître par PBKDF2) écrit atomiquement, mode 0600
#   MemoryCredentialStore()                en mémoire (tests, durée du processus)
#   EnvCredentialStore(préfixe)            lecture seule depuis les variables d'environnement (PRÉFIXE_NOM)
#
#   use security.credential_store as cs
#   coffre := cs.CredentialStore("/home/ana/.config/app/coffre.alexvault", maitre)   # créé s'il n'existe pas
#   coffre.set("github", "ghp_xxx", {"utilisateur": "ana"})
#   print(coffre.get("github"))            # « ghp_xxx » ; coffre.get_entry("github")["meta"]
#   print(coffre.names())                  # ["github"]
#   coffre.change_password(maitre, nouveau)
#   coffre.lock()                          # oublie la clé ; unlock(mot_de_passe) pour rouvrir
#   env := cs.EnvCredentialStore("APP")    # APP_DB_PASSWORD -> env.get("db_password")
#
# Erreurs : AuthenticationError (mot de passe maître faux), CredentialError (secret absent, coffre verrouillé,
# fichier invalide), SignatureError (fichier altéré).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use io as _io
use json as _json
use time as _time
use crypto as _c
use security.security as _sec
use security.crypto_provider as _cp
use security.random_secure as _rnd

const FORMAT := "alex-credential-store"

class _Base:
    func get(name, default=null):
        e := self.get_entry(name)
        if e == null:
            if default != null:
                return default
            raise("CredentialError", "secret absent : '" + name + "'")
        return e["secret"]

    func has(name):
        return self.get_entry(name) != null

    func require(names):
        missing := [n for n in names if not self.has(n)]
        if len(missing) > 0:
            raise("CredentialError", "secrets absents : " + _s.join(", ", missing))
        return true

class MemoryCredentialStore extends _Base:
    func init():
        self.entries = {}

    func set(name, secret, meta=null):
        now := _time.time()
        created := now
        if name in self.entries:
            created = self.entries[name]["created"]
        m := meta
        if m == null:
            m = {}
        self.entries[name] = {"secret": secret, "meta": m, "created": created, "updated": now}
        return self

    func get_entry(name):
        if name in self.entries:
            return self.entries[name]
        return null

    func delete(name):
        if name in self.entries:
            del self.entries[name]
            return true
        return false

    func names():
        return [k for k in self.entries]

class EnvCredentialStore extends _Base:
    func init(prefix=""):
        self.prefix = prefix

    func _var(name):
        v := _s.upper(name)
        if self.prefix != "":
            v = _s.upper(self.prefix) + "_" + v
        return v

    func get_entry(name):
        v := _os.get_env(self._var(name), null)
        if v == null:
            return null
        return {"secret": v, "meta": {"source": "env", "variable": self._var(name)}, "created": null, "updated": null}

    func set(name, secret, meta=null):
        raise("CredentialError", "EnvCredentialStore : lecture seule")

    func names():
        out := []
        p := _s.upper(self.prefix) + "_"
        env := _os.env()
        for k in env:
            if self.prefix == "":
                append(out, _s.lower(k))
            elif _s.starts_with(k, p):
                append(out, _s.lower(_s.substring(k, len(p), len(k))))
        return out

class CredentialStore extends _Base:
    func init(path, password, iterations=null, create=true):
        self.path = path
        self.key = null
        self.entries = {}
        self.salt = null
        self.iterations = iterations
        if _os.exists(path):
            self.unlock(password)
        elif create:
            if self.iterations == null:
                self.iterations = _cp.provider().default_iterations
            self.salt = _rnd.random_bytes(16)
            self.key = _cp.pbkdf2(password, self.salt, self.iterations, 32)
            self.save()
        else:
            raise("CredentialError", "coffre introuvable : " + path)

    func _header():
        return {"format": FORMAT, "version": 1, "kdf": "pbkdf2_sha256", "iterations": self.iterations,
                "salt": _c.base64_encode(self.salt, true)}

    func _aad():
        return _json.stringify(self._header())

    func unlock(password):
        d := null
        try:
            d = _json.parse(_io.read_file(self.path))
        catch e:
            raise("CredentialError", "coffre illisible : " + self.path)
        if type(d) != "dict" or not ("format" in d) or d["format"] != FORMAT:
            raise("CredentialError", "fichier de coffre invalide : " + self.path)
        self.iterations = d["iterations"]
        self.salt = _c.base64_decode(d["salt"], true)
        k := _cp.pbkdf2(password, self.salt, self.iterations, 32)
        plain := null
        try:
            plain = _cp.decrypt_text(k, d["data"], self._aad())
        catch e:
            if e.type == "SignatureError":
                raise("AuthenticationError", "coffre : mot de passe maître incorrect (ou fichier altéré)")
            raise(e.type, e.message)
        self.entries = _json.parse(plain)
        self.key = k
        return self

    func locked():
        return self.key == null

    func lock():
        if self.key != null:
            _sec.wipe(self.key)
        self.key = null
        self.entries = {}

    func _need_open():
        if self.key == null:
            raise("CredentialError", "coffre verrouillé (unlock)")

    func save():
        self._need_open()
        d := self._header()
        d["data"] = _cp.encrypt_text(self.key, _json.stringify(self.entries), self._aad())
        tmp := self.path + ".tmp"
        dir := _dirname(self.path)
        if dir != "" and not _os.exists(dir):
            _os.mkdir_all(dir)
        _io.write_file(tmp, _json.pretty(d))
        try:
            _os.chmod(tmp, 0o600)
        catch e:
            tmp = tmp
        _os.move(tmp, self.path)

    func set(name, secret, meta=null):
        self._need_open()
        now := _time.time()
        created := now
        if name in self.entries:
            created = self.entries[name]["created"]
        m := meta
        if m == null:
            m = {}
        self.entries[name] = {"secret": secret, "meta": m, "created": created, "updated": now}
        self.save()
        return self

    func get_entry(name):
        self._need_open()
        if name in self.entries:
            return self.entries[name]
        return null

    func delete(name):
        self._need_open()
        if name in self.entries:
            del self.entries[name]
            self.save()
            return true
        return false

    func names():
        self._need_open()
        return [k for k in self.entries]

    func change_password(old_password, new_password):
        self._need_open()
        k := _cp.pbkdf2(old_password, self.salt, self.iterations, 32)
        if not _sec.constant_time_equals(k, self.key):
            raise("AuthenticationError", "coffre : ancien mot de passe incorrect")
        self.salt = _rnd.random_bytes(16)
        self.key = _cp.pbkdf2(new_password, self.salt, self.iterations, 32)
        self.save()
        return self

func _dirname(p):
    i := len(p) - 1
    while i >= 0 and p[i] != '/':
        i -= 1
    if i <= 0:
        return ""
    return _s.substring(p, 0, i)

func open(path, password, iterations=null):
    return CredentialStore(path, password, iterations)
