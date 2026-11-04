# ALEX STANDARD LIBRARY — network.ip_address
#
# Adresses de POINTS DE TERMINAISON (adresse IP + port) et outils autour des adresses : analyse et écriture de
# « hôte:port » (IPv6 entre crochets, zone %eth0), résolution d'un nom en points de terminaison, adresses
# locales, octets réseau, noms de résolution inverse, adresses IPv6 dérivées d'une MAC (EUI-64), et
# anonymisation pour les journaux. Les calculs sur les adresses et réseaux eux-mêmes sont dans
# network.ipaddress (sur lequel ce module s'appuie).
#
#   use network.ip_address as ipa
#   e := ipa.parse_endpoint("[2001:db8::1]:8443")
#   print(e.host, e.port, e.version, str(e))          # 2001:db8::1 8443 6 [2001:db8::1]:8443
#   print(ipa.Endpoint("10.0.0.5", 80).is_private())  # true
#   for p in ipa.resolve_endpoints("localhost", 80):  # points de terminaison IPv4 et IPv6 de localhost
#       print(p)
#   print(ipa.anonymize("192.168.17.42"))             # 192.168.17.0 (IPv6 : /48 conservé)
#   print(ipa.from_bytes([127, 0, 0, 1]), ipa.to_bytes("::1"))
#   print(ipa.link_local_from_mac("00:1a:2b:3c:4d:5e"))    # fe80::21a:2bff:fe3c:4d5e
#   print(ipa.reverse_name("8.8.4.4"))                # 4.4.8.8.in-addr.arpa
#
# Erreurs : ValueError (adresse, port ou MAC invalides), DnsError (résolution).

from core use len, type, to_int
from collections use append
use string as _s
use network.ipaddress as _ip
use network.dns as _dns
use network.network_interface as _ni
use _native_reflect as _r

class Endpoint:
    func init(host, port, scope=null):
        a := _ip.ip_address(host)
        if type(port) != "int" or port < 0 or port > 65535:
            raise("ValueError", "Endpoint : port 0..65535 attendu (obtenu " + str(port) + ")")
        self.address = a
        self.host = a.str()
        if a.scope != null:
            self.host = _s.split(self.host, "%")[0]
        self.scope = scope
        if self.scope == null:
            self.scope = a.scope
        self.port = port
        self.version = a.version

    func is_private():
        return self.address.is_private()

    func is_loopback():
        return self.address.is_loopback()

    func is_global():
        return self.address.is_global()

    func family():
        if self.version == 4:
            return 4
        return 6

    # Forme [hôte]:port pour IPv6, hôte:port pour IPv4.
    func __str__():
        h := self.host
        if self.scope != null:
            h += "%" + self.scope
        if self.version == 6:
            return "[" + h + "]:" + str(self.port)
        return h + ":" + str(self.port)

    func url(scheme="http"):
        return scheme + "://" + str(self)

    func tuple():
        return (self.host, self.port)

    func __eq__(other):
        if type(other) == "str":
            return str(self) == other
        if not (_r.is_instance(other) and _r.has_field(other, "port") and _r.has_field(other, "host")):
            return false
        return self.host == other.host and self.port == other.port

# « hôte:port », « [v6]:port », « v6 » seul (port défaut) ; Endpoint.
func parse_endpoint(text, default_port=null):
    if type(text) != "str" or text == "":
        raise("ValueError", "parse_endpoint : texte non vide attendu")
    host := text
    port := default_port
    if text[0] == '[':
        e := _s.find(text, "]")
        if e < 0:
            raise("ValueError", "parse_endpoint : ']' manquant dans '" + text + "'")
        host = _s.substring(text, 1, e)
        rest := _s.substring(text, e + 1, len(text))
        if rest != "":
            if rest[0] != ':':
                raise("ValueError", "parse_endpoint : ':' attendu après ']' dans '" + text + "'")
            port = _port(_s.substring(rest, 1, len(rest)), text)
    elif _s.count(text, ":") == 1:
        k := _s.find(text, ":")
        host = _s.substring(text, 0, k)
        port = _port(_s.substring(text, k + 1, len(text)), text)
    if port == null:
        raise("ValueError", "parse_endpoint : port absent dans '" + text + "'")
    scope := null
    if _s.contains(host, "%"):
        parts := _s.split(host, "%")
        host = parts[0]
        scope = parts[1]
    return Endpoint(host, port, scope)

func _port(t, whole):
    if len(t) == 0 or len(t) > 5:
        raise("ValueError", "port invalide dans '" + whole + "'")
    for c in t:
        if c < '0' or c > '9':
            raise("ValueError", "port invalide dans '" + whole + "'")
    p := to_int(t)
    if p > 65535:
        raise("ValueError", "port hors limites dans '" + whole + "'")
    return p

func format_endpoint(host, port):
    return str(Endpoint(host, port))

# Points de terminaison d'un nom (ou d'une adresse) ; family : 0, 4 ou 6.
func resolve_endpoints(host, port, family=0):
    if _ip.is_ip(host):
        return [Endpoint(host, port)]
    fam := family
    out := []
    seen := {}
    for a in _dns.lookup(host, port, fam):
        h := a.host
        if not (h in seen):
            seen[h] = true
            append(out, Endpoint(h, port))
    return out

# Adresses IP locales (Endpoint de port 0 non inclus : simples str).
func local_addresses(version=0, include_loopback=false):
    fam := 0
    if version == 4:
        fam = 2
    elif version == 6:
        fam = 10
    try:
        return _ni.addresses(fam, include_loopback)
    catch e:
        return []

func to_bytes(address):
    return _ip.ip_address(address).bytes()

func from_bytes(data):
    b := data
    if type(data) == "str":
        b = _s.byte_unpack(data)
    if len(b) == 4:
        return str(b[0]) + "." + str(b[1]) + "." + str(b[2]) + "." + str(b[3])
    if len(b) == 16:
        groups := []
        i := 0
        while i < 16:
            append(groups, _hex(b[i] * 256 + b[i + 1]))
            i += 2
        return _ip.ip_address(_s.join(":", groups)).str()
    raise("ValueError", "from_bytes : 4 ou 16 octets attendus (obtenu " + str(len(b)) + ")")

func _hex(v):
    d := "0123456789abcdef"
    out := ""
    x := v
    if x == 0:
        return "0"
    while x > 0:
        out = str(d[x % 16]) + out
        x = x // 16
    return out

func reverse_name(address):
    return _ip.ip_address(address).reverse_pointer()

# Anonymisation : IPv4 -> dernier octet à zéro (/24), IPv6 -> /48 conservé.
func anonymize(address, v4_prefix=24, v6_prefix=48):
    a := _ip.ip_address(address)
    p := v4_prefix
    if a.version == 6:
        p = v6_prefix
    return _ip.ip_network(a.str() + "/" + str(p), false).network_address().str()

func _parse_mac(mac):
    t := _s.replace(_s.replace(_s.lower(mac), "-", ":"), ".", "")
    parts := _s.split(t, ":")
    if len(parts) == 1 and len(t) == 12:
        parts = [_s.substring(t, i * 2, i * 2 + 2) for i in 0..6]
    if len(parts) != 6:
        raise("ValueError", "adresse MAC invalide : '" + mac + "'")
    out := []
    for p in parts:
        if len(p) != 2:
            raise("ValueError", "adresse MAC invalide : '" + mac + "'")
        v := 0
        for c in p:
            d := _s.find("0123456789abcdef", str(c))
            if d < 0:
                raise("ValueError", "adresse MAC invalide : '" + mac + "'")
            v = v * 16 + d
        append(out, v)
    return out

# Identifiant d'interface EUI-64 modifié (RFC 4291) d'une MAC : 4 groupes de 16 bits.
func eui64(mac):
    m := _parse_mac(mac)
    b := [m[0] ^ 2, m[1], m[2], 255, 254, m[3], m[4], m[5]]
    return [_hex(b[0] * 256 + b[1]), _hex(b[2] * 256 + b[3]), _hex(b[4] * 256 + b[5]), _hex(b[6] * 256 + b[7])]

func link_local_from_mac(mac):
    return _ip.ip_address("fe80::" + _s.join(":", eui64(mac))).str()

# Adresse IPv6 SLAAC d'un préfixe /64 et d'une MAC.
func slaac_address(prefix64, mac):
    n := _ip.ip_network(prefix64, false)
    if n.prefixlen != 64:
        raise("ValueError", "slaac_address : préfixe /64 attendu")
    base := _s.split(n.network_address().exploded(), ":")
    return _ip.ip_address(_s.join(":", base[:4] + eui64(mac))).str()

func same_family(a, b):
    return _ip.ip_address(a).version == _ip.ip_address(b).version
