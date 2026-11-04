# ALEX STANDARD LIBRARY — network.dns
#
# Résolution de noms par le résolveur du système (getaddrinfo : /etc/hosts, DNS, mDNS... selon la configuration
# de la machine) et résolution inverse.
#
# Erreurs
#   DnsError        le nom ne se résout pas (le message reprend celui du résolveur).
#   TypeError / ArgumentError   argument invalide.
#
# Exemple
#   use network.dns as dns
#   print(dns.resolve("localhost"))     # ["127.0.0.1"] (ou aussi "::1")
#   for a in dns.lookup("example.org", 443):
#       print(a.family, a.host, a.port)

from core use len, type, to_int
from collections use append
use string as _s
use _native_net as _n
use network.socket as _sk

class Address:
    func init(family, host, port):
        self.family = family
        self.host = host
        self.port = port

    func str():
        return _sk.format_address(self.host, self.port)

func _need_host(fn, host):
    if type(host) != "str":
        raise("TypeError", "dns." + fn + " : le nom doit être une str (obtenu '" + type(host) + "')")
    if host == "":
        raise("ArgumentError", "dns." + fn + " : nom vide")

func _family(fn, family):
    if family != 0 and family != 4 and family != 6:
        raise("ArgumentError", "dns." + fn + " : famille 0 (toutes), 4 ou 6 attendue")

# Adresses (Address) de host, dans l'ordre de préférence du système. port : null ou 0..65535 ;
# kind : "tcp" ou "udp".
func lookup(host, port=null, family=0, kind="tcp"):
    _sk._require()
    _need_host("lookup", host)
    _family("lookup", family)
    r := _n.resolve(host, port, family, kind)
    if type(r) == "str":
        raise("DnsError", "dns.lookup('" + host + "') : " + r)
    out := []
    for e in r:
        p := e[2]
        if port == null:
            p = null
        append(out, Address(e[0], e[1], p))
    if len(out) == 0:
        raise("DnsError", "dns.lookup('" + host + "') : aucune adresse")
    return out

# Adresses numériques (str) de host, sans doublon.
func resolve(host, family=0):
    out := []
    for a in lookup(host, null, family):
        append(out, a.host)
    return out

# Première adresse de host (celle que le système préfère).
func resolve_one(host, family=0):
    return resolve(host, family)[0]

# Nom associé à une adresse numérique (résolution inverse), ou null.
func reverse(address):
    _sk._require()
    if not is_ip(address):
        raise("ArgumentError", "dns.reverse : adresse IPv4 ou IPv6 numérique attendue (obtenu '" + str(address) + "')")
    return _n.reverse(address)

# Vrai si s est une adresse IPv4 en notation décimale pointée.
func is_ipv4(s):
    if type(s) != "str":
        return false
    parts := _s.split(s, ".")
    if len(parts) != 4:
        return false
    for p in parts:
        if len(p) == 0 or len(p) > 3:
            return false
        for c in p:
            if c < '0' or c > '9':
                return false
        if len(p) > 1 and p[0] == '0':
            return false
        if to_int(p) > 255:
            return false
    return true

# Vrai si s est une adresse IPv6 numérique (avec éventuellement « :: » et une fin IPv4).
func is_ipv6(s):
    if type(s) != "str" or len(s) < 2:
        return false
    if _s.count(s, "::") > 1:
        return false
    groups := _s.split(s, ":")
    if len(groups) > 8:
        return false
    compressed := _s.contains(s, "::")
    n := 0
    i := 0
    while i < len(groups):
        g := groups[i]
        if g == "":
            i += 1
            continue
        if i == len(groups) - 1 and _s.contains(g, "."):
            if not is_ipv4(g):
                return false
            n += 2
            i += 1
            continue
        if len(g) > 4:
            return false
        for c in _s.lower(g):
            if not ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f')):
                return false
        n += 1
        i += 1
    if compressed:
        return n < 8
    return n == 8 and not _s.starts_with(s, ":") and not _s.ends_with(s, ":")

func is_ip(s):
    return is_ipv4(s) or is_ipv6(s)
