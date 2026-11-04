# ALEX STANDARD LIBRARY — network.config
#
# Configuration commune des clients réseau : délais, identification (User-Agent), TLS (vérification, autorité),
# mandataires (proxies), redirections, tailles maximales, réserve de connexions, nouvelles tentatives.
#
# Une configuration globale (defaults()) sert de valeur par défaut aux clients (network.http_client,
# network.smtp, network.ftp...) ; chaque client peut recevoir sa propre copie modifiée.
#
# Variables d'environnement lues par from_env() (et par defaults() au premier appel) :
#   HTTP_PROXY / http_proxy, HTTPS_PROXY / https_proxy, ALL_PROXY / all_proxy, NO_PROXY / no_proxy
#   SSL_CERT_FILE (autorité de certification), ALEX_NET_TIMEOUT (délai global en secondes),
#   ALEX_NET_USER_AGENT, ALEX_NET_VERIFY (« 0 » : pas de vérification TLS — tests seulement)
#
# Exemple
#   use network.config as cfg
#   c := cfg.defaults().copy()
#   c.set("timeout", 5.0)
#   c.set("user_agent", "mon-outil/1.0")
#   print(c.proxy_for("https"))           # mandataire HTTPS du système, ou null

from core use len, type, to_float
from collections use append, keys, contains_key
use string as _s
use json as _json
use io as _io
use os as _os
use network.ipaddress as _ip

const VERSION := "1.0"
const USER_AGENT := "Alex-network/1.0"

# Clés reconnues et valeurs par défaut.
func _base():
    return {"connect_timeout": 10.0, "timeout": 30.0, "user_agent": USER_AGENT, "verify": true, "ca_file": null, "cert_file": null, "key_file": null, "proxies": {}, "no_proxy": [], "max_redirects": 10, "max_body": 104857600, "max_header_bytes": 65536, "keep_alive": true, "pool_size": 10, "pool_idle_timeout": 60.0, "retries": 0, "retry_backoff": 0.2, "accept_compressed": true, "trust_env": true, "family": 0}

_TYPES := {"connect_timeout": "timeout", "timeout": "timeout", "user_agent": "str", "verify": "bool", "ca_file": "str?", "cert_file": "str?", "key_file": "str?", "proxies": "dict", "no_proxy": "list", "max_redirects": "int", "max_body": "int", "max_header_bytes": "int", "keep_alive": "bool", "pool_size": "int", "pool_idle_timeout": "timeout", "retries": "int", "retry_backoff": "number", "accept_compressed": "bool", "trust_env": "bool", "family": "int"}

func _check(key, value):
    if not contains_key(_TYPES, key):
        raise("ArgumentError", "network.config : clé inconnue '" + str(key) + "'")
    t := _TYPES[key]
    vt := type(value)
    ok := true
    if t == "timeout":
        ok = value == null or ((vt == "int" or vt == "float") and value >= 0)
    elif t == "number":
        ok = (vt == "int" or vt == "float") and value >= 0
    elif t == "str":
        ok = vt == "str"
    elif t == "str?":
        ok = value == null or vt == "str"
    elif t == "bool":
        ok = vt == "bool"
    elif t == "int":
        ok = vt == "int" and value >= 0
    elif t == "dict":
        ok = vt == "dict"
    elif t == "list":
        ok = vt == "list"
    if not ok:
        raise("TypeError", "network.config : valeur invalide pour '" + key + "' : " + str(value) + " (" + t + " attendu)")

class Config:
    func init(values=null):
        self.values = _base()
        if values != null:
            self.update(values)

    func get(key, default=null):
        if contains_key(self.values, key):
            return self.values[key]
        return default

    func set(key, value):
        _check(key, value)
        self.values[key] = value
        return self

    func update(values):
        for k in keys(values):
            self.set(k, values[k])
        return self

    func copy():
        c := Config()
        for k in keys(self.values):
            v := self.values[k]
            if type(v) == "dict":
                d := {}
                for kk in keys(v):
                    d[kk] = v[kk]
                v = d
            elif type(v) == "list":
                l := []
                for x in v:
                    append(l, x)
                v = l
            c.values[k] = v
        return c

    func to_dict():
        return self.copy().values

    # Mandataire (URL) pour un schéma (« http », « https »...), en tenant compte de « all ».
    func proxy_for(scheme):
        p := self.values["proxies"]
        k := _s.lower(scheme)
        if contains_key(p, k) and p[k] != null and p[k] != "":
            return p[k]
        if contains_key(p, "all") and p["all"] != null and p["all"] != "":
            return p["all"]
        return null

    # Vrai si host doit être joint directement (liste no_proxy : noms, suffixes « .exemple.org », « * », IP/CIDR).
    func bypass_proxy(host, port=null):
        return matches_no_proxy(host, self.values["no_proxy"], port)

    func str():
        return "Config(" + _json.stringify(self.values) + ")"

func _env(names):
    for n in names:
        v := _os.getenv(n)
        if v != null and v != "":
            return v
    return null

# Liste NO_PROXY découpée (virgules ou espaces).
func parse_no_proxy(text):
    out := []
    if text == null:
        return out
    for part in _s.split(_s.replace(text, " ", ","), ","):
        p := _s.lower(_s.trim(part))
        if p != "":
            append(out, p)
    return out

# Vrai si host (et port) correspondent à une entrée NO_PROXY.
func matches_no_proxy(host, entries, port=null):
    if host == null:
        return false
    h := _s.lower(host)
    if _s.starts_with(h, "[") and _s.ends_with(h, "]"):
        h = _s.substring(h, 1, len(h) - 1)
    for e in entries:
        entry := e
        eport := null
        if not _s.starts_with(entry, "[") and _s.count(entry, ":") == 1:
            c := _s.find(entry, ":")
            eport = _s.substring(entry, c + 1, len(entry))
            entry = _s.substring(entry, 0, c)
        if eport != null and port != null and eport != str(port):
            continue
        if entry == "*":
            return true
        if _s.contains(entry, "/"):
            if _cidr_match(h, entry):
                return true
            continue
        if _s.starts_with(entry, "*."):
            entry = _s.substring(entry, 1, len(entry))
        if _s.starts_with(entry, "."):
            if _s.ends_with(h, entry) or h == _s.substring(entry, 1, len(entry)):
                return true
        elif h == entry or _s.ends_with(h, "." + entry):
            return true
    return false

func _cidr_match(host, cidr):
    if not _ip.is_ip(host):
        return false
    try:
        return _ip.ip_network(cidr, false).contains(host)
    catch e:
        return false

# Configuration lue dans l'environnement (voir l'en-tête).
func from_env(base=null):
    c := base
    if c == null:
        c = Config()
    else:
        c = c.copy()
    proxies := {}
    hp := _env(["http_proxy", "HTTP_PROXY"])
    sp := _env(["https_proxy", "HTTPS_PROXY"])
    ap := _env(["all_proxy", "ALL_PROXY"])
    if hp != null:
        proxies["http"] = hp
    if sp != null:
        proxies["https"] = sp
    if ap != null:
        proxies["all"] = ap
    c.values["proxies"] = proxies
    c.values["no_proxy"] = parse_no_proxy(_env(["no_proxy", "NO_PROXY"]))
    ca := _env(["SSL_CERT_FILE"])
    if ca != null:
        c.values["ca_file"] = ca
    t := _env(["ALEX_NET_TIMEOUT"])
    if t != null:
        c.values["timeout"] = to_float(t)
    ua := _env(["ALEX_NET_USER_AGENT"])
    if ua != null:
        c.values["user_agent"] = ua
    vf := _env(["ALEX_NET_VERIFY"])
    if vf != null and (vf == "0" or _s.lower(vf) == "false" or _s.lower(vf) == "no"):
        c.values["verify"] = false
    return c

_DEFAULTS := [null]

# Configuration globale partagée (créée depuis l'environnement au premier appel).
func defaults():
    if _DEFAULTS[0] == null:
        _DEFAULTS[0] = from_env()
    return _DEFAULTS[0]

# Remplace la configuration globale (null : la recharger depuis l'environnement au prochain appel).
func set_defaults(config):
    _DEFAULTS[0] = config

# Raccourcis sur la configuration globale.
func get(key, default=null):
    return defaults().get(key, default)

func set(key, value):
    defaults().set(key, value)

# Configuration depuis un fichier JSON (objet clé -> valeur), par-dessus `base` (défaut : configuration neuve).
func load(path, base=null):
    c := base
    if c == null:
        c = Config()
    else:
        c = c.copy()
    v := _json.parse(_io.read_file(path))
    if type(v) != "dict":
        raise("TypeError", "network.config.load : objet JSON attendu dans " + path)
    c.update(v)
    return c

func save(config, path):
    _io.write_file(path, _json.pretty(config.values))
