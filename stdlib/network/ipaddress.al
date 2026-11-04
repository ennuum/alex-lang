# ALEX STANDARD LIBRARY — network.ipaddress
#
# Adresses et réseaux IPv4 / IPv6 : analyse stricte, forme canonique (RFC 5952 pour IPv6), classification (privée,
# boucle locale, multicast, documentation...), réseaux CIDR (masques, appartenance, sous-réseaux, hôtes),
# regroupement d'intervalles.
#
# Représentation : une adresse est une suite de groupes de 16 bits (2 pour IPv4, 8 pour IPv6) ; tous les calculs
# sont exacts sur 128 bits sans dépasser les entiers 64 bits d'ALEX.
#
# Erreurs : ValueError (adresse ou réseau invalide), TypeError (argument).
#
# Exemple
#   use network.ipaddress as ip
#   a := ip.ip_address("2001:0db8:0000:0000:0000:0000:0000:0001")
#   print(a.str(), a.version, a.is_documentation())        # 2001:db8::1 6 true
#   n := ip.ip_network("192.168.1.0/24")
#   print(n.contains("192.168.1.42"), n.broadcast().str(), n.num_addresses())   # true 192.168.1.255 256
#   for s in n.subnets(2):
#       print(s.str())                                      # 192.168.1.0/26 ... 192.168.1.192/26
#   print(ip.collapse(["10.0.0.0/25", "10.0.0.128/25"]))    # [10.0.0.0/24]

from core use len, type, to_int
from collections use append, contains_key
use string as _s
use _native_net as _n

func _fail(message):
    raise("ValueError", "ipaddress : " + message)

# ---------------------------------------------------------------- arithmétique sur groupes de 16 bits

func _zeros(n):
    out := []
    i := 0
    while i < n:
        append(out, 0)
        i += 1
    return out

func _copy(g):
    out := []
    for x in g:
        append(out, x)
    return out

# Masque de `prefix` bits à 1 sur n groupes.
func _mask(prefix, n):
    out := []
    i := 0
    while i < n:
        bits := prefix - i * 16
        if bits >= 16:
            append(out, 65535)
        elif bits <= 0:
            append(out, 0)
        else:
            append(out, (65535 << (16 - bits)) & 65535)
        i += 1
    return out

func _and(a, b):
    out := []
    i := 0
    while i < len(a):
        append(out, a[i] & b[i])
        i += 1
    return out

func _or(a, b):
    out := []
    i := 0
    while i < len(a):
        append(out, a[i] | b[i])
        i += 1
    return out

func _not(a):
    out := []
    for x in a:
        append(out, (~x) & 65535)
    return out

func _cmp(a, b):
    i := 0
    while i < len(a):
        if a[i] < b[i]:
            return -1
        if a[i] > b[i]:
            return 1
        i += 1
    return 0

# a + k (k entier, éventuellement négatif) ; ValueError en cas de débordement.
func _add(a, k):
    out := _copy(a)
    carry := k
    i := len(out) - 1
    while i >= 0 and carry != 0:
        v := out[i] + (carry % 65536)
        carry = carry // 65536
        if v >= 65536:
            v -= 65536
            carry += 1
        elif v < 0:
            v += 65536
            carry -= 1
        out[i] = v
        i -= 1
    if carry != 0:
        _fail("dépassement de l'espace d'adressage")
    return out

# Bit numéro `bit` (0 = poids fort) des groupes.
func _bit(a, bit):
    return (a[bit // 16] >> (15 - bit % 16)) & 1

func _set_bit(a, bit):
    out := _copy(a)
    out[bit // 16] = out[bit // 16] | (1 << (15 - bit % 16))
    return out

# Nombre de zéros de poids faible (0..bits).
func _trailing_zeros(a):
    n := 0
    i := len(a) - 1
    while i >= 0:
        x := a[i]
        if x == 0:
            n += 16
        else:
            k := 0
            while (x & 1) == 0:
                x = x >> 1
                k += 1
            return n + k
        i -= 1
    return n

# Différence b - a quand elle tient dans un int (sinon null).
func _distance(a, b):
    d := 0
    i := 0
    while i < len(a):
        d = d * 65536 + (b[i] - a[i])
        if d > 4611686018427387903 or d < -4611686018427387903:
            return null
        i += 1
    return d

# ---------------------------------------------------------------- analyse

func _parse_v4(text):
    parts := _s.split(text, ".")
    if len(parts) != 4:
        _fail("adresse IPv4 invalide '" + text + "' (4 nombres attendus)")
    v := 0
    for p in parts:
        if p == "" or len(p) > 3:
            _fail("adresse IPv4 invalide '" + text + "'")
        for c in p:
            if c < '0' or c > '9':
                _fail("adresse IPv4 invalide '" + text + "'")
        if len(p) > 1 and p[0] == '0':
            _fail("adresse IPv4 invalide '" + text + "' (zéro initial ambigu)")
        x := to_int(p)
        if x > 255:
            _fail("adresse IPv4 invalide '" + text + "' (octet > 255)")
        v = v * 256 + x
    return [(v >> 16) & 65535, v & 65535]

func _hexval(c):
    if c >= '0' and c <= '9':
        return _s.ord(c) - 48
    if c >= 'a' and c <= 'f':
        return _s.ord(c) - 87
    if c >= 'A' and c <= 'F':
        return _s.ord(c) - 55
    return -1

func _parse_v6(text):
    if text == "" or len(text) > 45:
        _fail("adresse IPv6 invalide '" + text + "'")
    if _s.count(text, "::") > 1:
        _fail("adresse IPv6 invalide '" + text + "' (« :: » répété)")
    head := text
    tail := ""
    compressed := false
    i := _s.find(text, "::")
    if i >= 0:
        compressed = true
        head = _s.substring(text, 0, i)
        tail = _s.substring(text, i + 2, len(text))
    hg := _groups6(head, text, tail == "" and not compressed)
    tg := []
    if compressed:
        tg = _groups6(tail, text, true)
    else:
        tg = []
    total := len(hg) + len(tg)
    if compressed:
        if total > 7:
            _fail("adresse IPv6 invalide '" + text + "' (trop de groupes)")
        out := []
        for x in hg:
            append(out, x)
        k := 0
        while k < 8 - total:
            append(out, 0)
            k += 1
        for x in tg:
            append(out, x)
        return out
    if total != 8:
        _fail("adresse IPv6 invalide '" + text + "' (8 groupes attendus)")
    return hg

# Groupes hexadécimaux d'une moitié d'adresse ; la dernière peut être une IPv4 (si allow_v4).
func _groups6(part, whole, allow_v4):
    out := []
    if part == "":
        return out
    pieces := _s.split(part, ":")
    idx := 0
    for p in pieces:
        last := idx == len(pieces) - 1
        if _s.contains(p, "."):
            if not last:
                _fail("adresse IPv6 invalide '" + whole + "' (IPv4 ailleurs qu'à la fin)")
            v4 := _parse_v4(p)
            append(out, v4[0])
            append(out, v4[1])
        else:
            if p == "" or len(p) > 4:
                _fail("adresse IPv6 invalide '" + whole + "'")
            v := 0
            for c in p:
                h := _hexval(c)
                if h < 0:
                    _fail("adresse IPv6 invalide '" + whole + "' (caractère '" + str(c) + "')")
                v = v * 16 + h
            append(out, v)
        idx += 1
    return out

const _HEX := "0123456789abcdef"

func _hex(v):
    if v == 0:
        return "0"
    s := ""
    while v > 0:
        s = str(_HEX[v & 15]) + s
        v = v >> 4
    return s

func _hex4(v):
    return str(_HEX[(v >> 12) & 15]) + str(_HEX[(v >> 8) & 15]) + str(_HEX[(v >> 4) & 15]) + str(_HEX[v & 15])

func _format_v4(g):
    return str(g[0] >> 8) + "." + str(g[0] & 255) + "." + str(g[1] >> 8) + "." + str(g[1] & 255)

# Forme canonique RFC 5952 : minuscules, sans zéros initiaux, plus longue suite (>= 2) de groupes nuls en « :: ».
func _format_v6(g):
    best := -1
    best_len := 0
    i := 0
    while i < 8:
        if g[i] == 0:
            j := i
            while j < 8 and g[j] == 0:
                j += 1
            if j - i > best_len:
                best = i
                best_len = j - i
            i = j
        else:
            i += 1
    mapped := g[0] == 0 and g[1] == 0 and g[2] == 0 and g[3] == 0 and g[4] == 0 and g[5] == 65535
    if mapped:
        return "::ffff:" + _format_v4([g[6], g[7]])
    if best_len < 2:
        parts := []
        for x in g:
            append(parts, _hex(x))
        return _s.join(":", parts)
    left := []
    k := 0
    while k < best:
        append(left, _hex(g[k]))
        k += 1
    right := []
    k = best + best_len
    while k < 8:
        append(right, _hex(g[k]))
        k += 1
    return _s.join(":", left) + "::" + _s.join(":", right)

# ---------------------------------------------------------------- adresses

class IPAddress:
    func init(version, groups, scope=null):
        self.version = version
        self.groups = groups      # list[int] de 16 bits
        self.scope = scope        # zone IPv6 (« eth0 » dans fe80::1%eth0), ou null

    func max_prefixlen():
        return len(self.groups) * 16

    func str():
        if self.version == 4:
            return _format_v4(self.groups)
        s := _format_v6(self.groups)
        if self.scope != null:
            s += "%" + self.scope
        return s

    func __str__():
        return self.str()

    # IPv6 sans abréviation (« 2001:0db8:0000:... ») ; IPv4 inchangée.
    func exploded():
        if self.version == 4:
            return self.str()
        parts := []
        for x in self.groups:
            append(parts, _hex4(x))
        return _s.join(":", parts)

    # Octets réseau (4 ou 16) en str brute.
    func packed():
        out := []
        for x in self.groups:
            append(out, x >> 8)
            append(out, x & 255)
        return _n.from_bytes(out)

    func bytes():
        return _n.to_bytes(self.packed())

    # Valeur entière (IPv4 : 0..2^32-1 ; IPv6 : seulement si elle tient sur 62 bits, sinon ValueError).
    func to_int():
        if self.version == 4:
            return self.groups[0] * 65536 + self.groups[1]
        d := _distance(_zeros(8), self.groups)
        if d == null:
            _fail("to_int : " + self.str() + " dépasse les entiers 64 bits (voir groups)")
        return d

    func _in(cidr):
        return ip_network(cidr).contains(self)

    func is_unspecified():
        for x in self.groups:
            if x != 0:
                return false
        return true

    func is_loopback():
        if self.version == 4:
            return self._in("127.0.0.0/8")
        m := self.ipv4_mapped()
        if m != null:
            return m.is_loopback()
        return _cmp(self.groups, [0, 0, 0, 0, 0, 0, 0, 1]) == 0

    func is_private():
        if self.version == 4:
            return self._in("10.0.0.0/8") or self._in("172.16.0.0/12") or self._in("192.168.0.0/16")
        m := self.ipv4_mapped()
        if m != null:
            return m.is_private()
        return self._in("fc00::/7")

    func is_link_local():
        if self.version == 4:
            return self._in("169.254.0.0/16")
        return self._in("fe80::/10")

    func is_site_local():
        return self.version == 6 and self._in("fec0::/10")

    func is_multicast():
        if self.version == 4:
            return self._in("224.0.0.0/4")
        return self._in("ff00::/8")

    func is_reserved():
        if self.version == 4:
            return self._in("240.0.0.0/4") and not self.is_broadcast()
        return self._in("::/8") and not self.is_unspecified() and not self.is_loopback() and self.ipv4_mapped() == null

    func is_broadcast():
        return self.version == 4 and self.groups[0] == 65535 and self.groups[1] == 65535

    # Espace partagé des opérateurs (CGNAT, RFC 6598).
    func is_shared():
        return self.version == 4 and self._in("100.64.0.0/10")

    # Plages réservées à la documentation (RFC 5737, RFC 3849).
    func is_documentation():
        if self.version == 4:
            return self._in("192.0.2.0/24") or self._in("198.51.100.0/24") or self._in("203.0.113.0/24")
        return self._in("2001:db8::/32")

    func is_benchmarking():
        if self.version == 4:
            return self._in("198.18.0.0/15")
        return self._in("2001:2::/48")

    # Adresse joignable sur Internet (aucune des plages spéciales ci-dessus, ni « ce réseau » 0.0.0.0/8).
    func is_global():
        if self.version == 4:
            if self._in("0.0.0.0/8") or self._in("192.0.0.0/24"):
                return false
        else:
            m := self.ipv4_mapped()
            if m != null:
                return m.is_global()
            special := self._in("2001::/23") and not (self._in("2001::/32") or self._in("2001:3::/32") or self._in("2001:20::/28"))
            if self._in("64:ff9b:1::/48") or self._in("100::/64") or special:
                return false
        return not (self.is_unspecified() or self.is_loopback() or self.is_private() or self.is_link_local() or self.is_site_local() or self.is_multicast() or self.is_reserved() or self.is_broadcast() or self.is_shared() or self.is_documentation() or self.is_benchmarking())

    # IPv4 contenue dans une adresse IPv6 « ::ffff:a.b.c.d », ou null.
    func ipv4_mapped():
        g := self.groups
        if self.version == 6 and g[0] == 0 and g[1] == 0 and g[2] == 0 and g[3] == 0 and g[4] == 0 and g[5] == 65535:
            return IPv4Address([g[6], g[7]])
        return null

    # Forme « ::ffff:a.b.c.d » d'une IPv4 (IPv6 inchangée).
    func to_ipv6_mapped():
        if self.version == 6:
            return self
        return IPv6Address([0, 0, 0, 0, 0, 65535, self.groups[0], self.groups[1]])

    # Nom de la résolution inverse (« 4.3.2.1.in-addr.arpa », quartets pour IPv6).
    func reverse_pointer():
        if self.version == 4:
            g := self.groups
            return str(g[1] & 255) + "." + str(g[1] >> 8) + "." + str(g[0] & 255) + "." + str(g[0] >> 8) + ".in-addr.arpa"
        nibbles := []
        i := 7
        while i >= 0:
            x := self.groups[i]
            append(nibbles, str(_HEX[x & 15]))
            append(nibbles, str(_HEX[(x >> 4) & 15]))
            append(nibbles, str(_HEX[(x >> 8) & 15]))
            append(nibbles, str(_HEX[(x >> 12) & 15]))
            i -= 1
        return _s.join(".", nibbles) + ".ip6.arpa"

    func _same_version(other, op):
        o := other
        if type(o) == "str":
            o = ip_address(o)
        if o.version != self.version:
            raise("TypeError", "ipaddress : " + op + " entre IPv" + str(self.version) + " et IPv" + str(o.version))
        return o

    func compare(other):
        o := self._same_version(other, "comparaison")
        return _cmp(self.groups, o.groups)

    func __eq__(other):
        if other == null:
            return false
        if type(other) == "str":
            try:
                other = ip_address(other)
            catch e:
                return false
        if type(other) == "int" or type(other) == "float" or type(other) == "list":
            return false
        return other.version == self.version and _cmp(self.groups, other.groups) == 0 and self.scope == other.scope

    func __lt__(other):
        return self.compare(other) < 0

    func __le__(other):
        return self.compare(other) <= 0

    func __gt__(other):
        return self.compare(other) > 0

    func __ge__(other):
        return self.compare(other) >= 0

    # Adresse décalée de k (entier) ; ValueError hors de l'espace d'adressage.
    func __add__(k):
        return _make(self.version, _add(self.groups, k))

    func __sub__(other):
        if type(other) == "int":
            return _make(self.version, _add(self.groups, -other))
        o := self._same_version(other, "soustraction")
        d := _distance(o.groups, self.groups)
        if d == null:
            _fail("écart trop grand pour un entier")
        return d

class IPv4Address extends IPAddress:
    # text : « a.b.c.d », entier 0..2^32-1, 4 octets (str brute ou liste), ou groupes [hi, lo].
    func init(value):
        g := null
        t := type(value)
        if t == "int":
            if value < 0 or value > 4294967295:
                _fail("entier IPv4 hors de 0..2^32-1")
            g = [(value >> 16) & 65535, value & 65535]
        elif t == "str" and _n.blen(value) == 4 and not _s.contains(value, "."):
            b := _n.to_bytes(value)
            g = [b[0] * 256 + b[1], b[2] * 256 + b[3]]
        elif t == "str":
            g = _parse_v4(_s.trim(value))
        elif t == "list" and len(value) == 2:
            g = _copy(value)
        elif t == "list" and len(value) == 4:
            g = [value[0] * 256 + value[1], value[2] * 256 + value[3]]
        else:
            raise("TypeError", "ipaddress.IPv4Address : str, int ou 4 octets attendus (obtenu '" + t + "')")
        super.init(4, g, null)

class IPv6Address extends IPAddress:
    # text : forme IPv6 (avec zone « %eth0 » éventuelle), 16 octets, ou groupes (8 entiers de 16 bits).
    func init(value):
        g := null
        scope := null
        t := type(value)
        if t == "str" and _n.blen(value) == 16 and not _s.contains(value, ":"):
            b := _n.to_bytes(value)
            g = []
            i := 0
            while i < 16:
                append(g, b[i] * 256 + b[i + 1])
                i += 2
        elif t == "str":
            text := _s.trim(value)
            p := _s.find(text, "%")
            if p >= 0:
                scope = _s.substring(text, p + 1, len(text))
                text = _s.substring(text, 0, p)
                if scope == "":
                    _fail("zone IPv6 vide dans '" + value + "'")
            g = _parse_v6(text)
        elif t == "list" and len(value) == 8:
            g = _copy(value)
        elif t == "list" and len(value) == 16:
            g = []
            i := 0
            while i < 16:
                append(g, value[i] * 256 + value[i + 1])
                i += 2
        elif t == "int":
            if value < 0:
                _fail("entier IPv6 négatif")
            g = _add(_zeros(8), value)
        else:
            raise("TypeError", "ipaddress.IPv6Address : str, int ou 16 octets attendus (obtenu '" + t + "')")
        super.init(6, g, scope)

func _make(version, groups):
    if version == 4:
        return IPv4Address(groups)
    return IPv6Address(groups)

# Adresse IPv4 ou IPv6 depuis un texte, un entier (IPv4 si < 2^32) ou une adresse existante.
func ip_address(value):
    if isinstance(value, IPAddress):
        return value
    if type(value) == "int":
        if value <= 4294967295:
            return IPv4Address(value)
        return IPv6Address(value)
    if type(value) != "str":
        raise("TypeError", "ipaddress.ip_address : str ou int attendu (obtenu '" + type(value) + "')")
    t := _s.trim(value)
    if _s.starts_with(t, "[") and _s.ends_with(t, "]"):
        t = _s.substring(t, 1, len(t) - 1)
    if _s.contains(t, ":"):
        return IPv6Address(t)
    return IPv4Address(t)

func is_ipv4(text):
    try:
        IPv4Address(text)
        return true
    catch e:
        return false

func is_ipv6(text):
    try:
        IPv6Address(text)
        return true
    catch e:
        return false

func is_ip(text):
    return is_ipv4(text) or is_ipv6(text)

# ---------------------------------------------------------------- réseaux

# Longueur de préfixe d'un masque (« 255.255.255.0 » -> 24), ou -1 s'il n'est pas contigu.
func _prefix_of_mask(groups):
    n := 0
    seen_zero := false
    for x in groups:
        b := 15
        while b >= 0:
            bit := (x >> b) & 1
            if bit == 1:
                if seen_zero:
                    return -1
                n += 1
            else:
                seen_zero = true
            b -= 1
    return n

class IPNetwork:
    # text : « adresse/préfixe », « adresse/masque » (IPv4) ou une adresse seule (préfixe maximal).
    # strict=true : des bits d'hôte à 1 sont une erreur ; false : ils sont mis à zéro.
    func init(text, strict=true):
        addr := null
        prefix := null
        if isinstance(text, IPAddress):
            addr = text
            prefix = text.max_prefixlen()
        elif type(text) == "tuple" or type(text) == "list":
            addr = ip_address(text[0])
            prefix = text[1]
        elif type(text) == "str":
            t := _s.trim(text)
            sl := _s.find(t, "/")
            if sl < 0:
                addr = ip_address(t)
                prefix = addr.max_prefixlen()
            else:
                addr = ip_address(_s.substring(t, 0, sl))
                p := _s.substring(t, sl + 1, len(t))
                if p == "":
                    _fail("préfixe vide dans '" + t + "'")
                if _s.contains(p, "."):
                    if addr.version != 4:
                        _fail("masque pointé réservé à IPv4 : '" + t + "'")
                    m := IPv4Address(p)
                    prefix = _prefix_of_mask(m.groups)
                    if prefix < 0:
                        # masque d'hôte (« 0.0.0.255 ») accepté comme Python
                        prefix = _prefix_of_mask(_not(m.groups))
                        if prefix < 0:
                            _fail("masque non contigu '" + p + "'")
                else:
                    for c in p:
                        if c < '0' or c > '9':
                            _fail("préfixe invalide '" + p + "'")
                    if len(p) > 3:
                        _fail("préfixe invalide '" + p + "'")
                    prefix = to_int(p)
        else:
            raise("TypeError", "ipaddress.IPNetwork : str attendue (obtenu '" + type(text) + "')")
        if type(prefix) != "int" or prefix < 0 or prefix > addr.max_prefixlen():
            _fail("préfixe hors de 0.." + str(addr.max_prefixlen()) + " : " + str(prefix))
        self.version = addr.version
        self.prefixlen = prefix
        m := _mask(prefix, len(addr.groups))
        masked := _and(addr.groups, m)
        if strict and _cmp(masked, addr.groups) != 0:
            _fail(addr.str() + "/" + str(prefix) + " a des bits d'hôte à 1 (strict=false pour les ignorer)")
        self.groups = masked

    func network_address():
        return _make(self.version, self.groups)

    func max_prefixlen():
        return len(self.groups) * 16

    func netmask():
        return _make(self.version, _mask(self.prefixlen, len(self.groups)))

    func hostmask():
        return _make(self.version, _not(_mask(self.prefixlen, len(self.groups))))

    func broadcast():
        return _make(self.version, _or(self.groups, _not(_mask(self.prefixlen, len(self.groups)))))

    func first():
        return self.network_address()

    func last():
        return self.broadcast()

    # Nombre d'adresses (int ; float si plus de 2^62).
    func num_addresses():
        bits := self.max_prefixlen() - self.prefixlen
        if bits <= 62:
            return 1 << bits
        return 2.0 ** bits

    func str():
        return self.network_address().str() + "/" + str(self.prefixlen)

    func __str__():
        return self.str()

    func with_netmask():
        return self.network_address().str() + "/" + self.netmask().str()

    func with_hostmask():
        return self.network_address().str() + "/" + self.hostmask().str()

    # Vrai si l'adresse (ou le réseau entier) appartient à ce réseau.
    func contains(x):
        if type(x) == "str" and _s.contains(x, "/"):
            x = ip_network(x, false)
        if isinstance(x, IPNetwork):
            return self.supernet_of(x)
        a := ip_address(x)
        if a.version != self.version:
            return false
        return _cmp(_and(a.groups, _mask(self.prefixlen, len(self.groups))), self.groups) == 0

    func __contains__(x):
        return self.contains(x)

    func overlaps(other):
        o := ip_network(other, false)
        if o.version != self.version:
            return false
        return self.contains(o.network_address()) or o.contains(self.network_address())

    func subnet_of(other):
        o := ip_network(other, false)
        if o.version != self.version:
            return false
        return o.prefixlen <= self.prefixlen and o.contains(self.network_address())

    func supernet_of(other):
        o := ip_network(other, false)
        if o.version != self.version:
            return false
        return self.prefixlen <= o.prefixlen and self.contains(o.network_address())

    # Adresses utilisables pour des hôtes (sans adresse de réseau ni de diffusion en IPv4 sous /31 ; IPv6 : sans
    # l'adresse anycast du sous-réseau). limit : nombre maximal rendu (null : toutes, refusé au-delà de 2^20).
    func hosts(limit=null):
        total := self.num_addresses()
        start := self.groups
        count := total
        if self.version == 4 and self.prefixlen < 31:
            start = _add(self.groups, 1)
            count = total - 2
        elif self.version == 6 and self.prefixlen < 127:
            start = _add(self.groups, 1)
            count = total - 1
        if limit == null:
            if type(count) == "float" or count > 1048576:
                _fail("hosts : plus de 2^20 adresses dans " + self.str() + " (passer limit)")
        elif type(count) == "float" or count > limit:
            count = limit
        out := []
        g := start
        i := 0
        while i < count:
            append(out, _make(self.version, g))
            i += 1
            if i < count:
                g = _add(g, 1)
        return out

    # Sous-réseaux : prefixlen_diff bits de plus, ou new_prefix (refusé au-delà de 65536 sous-réseaux).
    func subnets(prefixlen_diff=1, new_prefix=null):
        np := self.prefixlen + prefixlen_diff
        if new_prefix != null:
            np = new_prefix
        if np < self.prefixlen or np > self.max_prefixlen():
            _fail("subnets : nouveau préfixe " + str(np) + " invalide pour " + self.str())
        if np - self.prefixlen > 16:
            _fail("subnets : plus de 65536 sous-réseaux")
        count := 1 << (np - self.prefixlen)
        out := []
        g := self.groups
        step_bits := self.max_prefixlen() - np
        i := 0
        while i < count:
            append(out, IPNetwork((_make(self.version, g), np)))
            i += 1
            if i < count:
                g = _add_pow2(g, step_bits)
        return out

    # Réseau englobant (prefixlen_diff bits de moins, ou new_prefix).
    func supernet(prefixlen_diff=1, new_prefix=null):
        np := self.prefixlen - prefixlen_diff
        if new_prefix != null:
            np = new_prefix
        if np < 0 or np > self.prefixlen:
            _fail("supernet : nouveau préfixe " + str(np) + " invalide pour " + self.str())
        return IPNetwork((_make(self.version, self.groups), np), false)

    # Réseaux restants après avoir retiré `other` (inclus dans self).
    func address_exclude(other):
        o := ip_network(other, false)
        if not self.supernet_of(o):
            _fail(o.str() + " n'est pas inclus dans " + self.str())
        out := []
        cur := self
        while cur.prefixlen < o.prefixlen:
            halves := cur.subnets(1)
            if halves[0].supernet_of(o):
                append(out, halves[1])
                cur = halves[0]
            else:
                append(out, halves[0])
                cur = halves[1]
        return out

    func compare(other):
        o := ip_network(other, false)
        if o.version != self.version:
            return self.version - o.version
        c := _cmp(self.groups, o.groups)
        if c != 0:
            return c
        return self.prefixlen - o.prefixlen

    func __eq__(other):
        if other == null:
            return false
        if type(other) == "str":
            try:
                other = ip_network(other)
            catch e:
                return false
        if not isinstance(other, IPNetwork):
            return false
        return other.version == self.version and other.prefixlen == self.prefixlen and _cmp(self.groups, other.groups) == 0

    func __lt__(other):
        return self.compare(other) < 0

    func __le__(other):
        return self.compare(other) <= 0

    func __gt__(other):
        return self.compare(other) > 0

    func __ge__(other):
        return self.compare(other) >= 0

func _add_pow2(g, bits):
    if bits >= len(g) * 16:
        _fail("dépassement de l'espace d'adressage")
    return _add_bit(g, len(g) * 16 - 1 - bits)

# Ajoute 2^(position depuis la fin) : ajoute 1 au bit `bit` (0 = poids fort), avec retenue.
func _add_bit(g, bit):
    out := _copy(g)
    gi := bit // 16
    v := out[gi] + (1 << (15 - bit % 16))
    while true:
        if v < 65536:
            out[gi] = v
            return out
        out[gi] = v - 65536
        gi -= 1
        if gi < 0:
            _fail("dépassement de l'espace d'adressage")
        v = out[gi] + 1

# Réseau depuis un texte (« 10.0.0.0/8 »), une adresse (préfixe maximal) ou un réseau existant.
func ip_network(value, strict=true):
    if isinstance(value, IPNetwork):
        return value
    return IPNetwork(value, strict)

# Adresse avec son réseau (« 192.168.1.10/24 ») : .ip, .network, .str().
class IPInterface:
    func init(text):
        t := str(text)
        sl := _s.find(t, "/")
        if sl < 0:
            self.ip = ip_address(t)
            self.network = IPNetwork(self.ip)
        else:
            self.ip = ip_address(_s.substring(t, 0, sl))
            self.network = IPNetwork(t, false)
        self.version = self.ip.version

    func str():
        return self.ip.str() + "/" + str(self.network.prefixlen)

    func __str__():
        return self.str()

    func with_netmask():
        return self.ip.str() + "/" + self.network.netmask().str()

func ip_interface(text):
    return IPInterface(text)

# Masque IPv4 pointé d'une longueur de préfixe (24 -> « 255.255.255.0 »).
func prefix_to_netmask(prefix, version=4):
    n := 2
    if version == 6:
        n = 8
    return _make(version, _mask(prefix, n)).str()

# Longueur de préfixe d'un masque pointé (« 255.255.255.0 » -> 24) ; ValueError s'il n'est pas contigu.
func netmask_to_prefix(mask):
    a := ip_address(mask)
    p := _prefix_of_mask(a.groups)
    if p < 0:
        _fail("masque non contigu '" + str(mask) + "'")
    return p

# ---------------------------------------------------------------- intervalles

# Plus petite liste de réseaux couvrant exactement [first, last].
func summarize_range(first, last):
    a := ip_address(first)
    b := ip_address(last)
    if a.version != b.version:
        raise("TypeError", "ipaddress.summarize_range : versions différentes")
    if _cmp(a.groups, b.groups) > 0:
        _fail("summarize_range : première adresse après la dernière")
    bits := a.max_prefixlen()
    out := []
    cur := a.groups
    while true:
        # plus grand bloc aligné sur cur qui ne dépasse pas b
        tz := _trailing_zeros(cur)
        if tz > bits:
            tz = bits
        size := tz
        while size > 0:
            end := _or(cur, _not(_mask(bits - size, len(cur))))
            if _cmp(end, b.groups) <= 0:
                break
            size -= 1
        append(out, IPNetwork((_make(a.version, cur), bits - size)))
        end := _or(cur, _not(_mask(bits - size, len(cur))))
        if _cmp(end, b.groups) >= 0:
            return out
        cur = _add(end, 1)

# Regroupe une liste de réseaux (et d'adresses) en la plus petite liste équivalente, triée.
func collapse(networks):
    v4 := []
    v6 := []
    for x in networks:
        n := null
        if isinstance(x, IPNetwork):
            n = x
        elif isinstance(x, IPAddress):
            n = IPNetwork(x)
        else:
            n = ip_network(x, false)
        if n.version == 4:
            append(v4, n)
        else:
            append(v6, n)
    out := []
    for group in [v4, v6]:
        if len(group) == 0:
            continue
        ranges := []
        for n in _sorted_networks(group):
            lo := n.groups
            hi := n.broadcast().groups
            if len(ranges) > 0:
                last := ranges[len(ranges) - 1]
                nxt := null
                try:
                    nxt = _add(last[1], 1)
                catch e:
                    nxt = null
                if _cmp(lo, last[1]) <= 0 or (nxt != null and _cmp(lo, nxt) == 0):
                    if _cmp(hi, last[1]) > 0:
                        last[1] = hi
                    continue
            append(ranges, [lo, hi])
        ver := group[0].version
        for r in ranges:
            for net in summarize_range(_make(ver, r[0]), _make(ver, r[1])):
                append(out, net)
    return out

func _sorted_networks(nets):
    out := []
    for n in nets:
        append(out, n)
    # tri par insertion (listes courtes) : adresse puis préfixe
    i := 1
    while i < len(out):
        x := out[i]
        j := i - 1
        while j >= 0 and out[j].compare(x) > 0:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = x
        i += 1
    return out

# Trie des adresses ou des réseaux (IPv4 avant IPv6).
func sort_addresses(values):
    out := []
    for v in values:
        if isinstance(v, IPAddress) or isinstance(v, IPNetwork):
            append(out, v)
        elif type(v) == "str" and _s.contains(v, "/"):
            append(out, ip_network(v, false))
        else:
            append(out, ip_address(v))
    i := 1
    while i < len(out):
        x := out[i]
        j := i - 1
        while j >= 0 and _order(out[j], x) > 0:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = x
        i += 1
    return out

func _order(a, b):
    if a.version != b.version:
        return a.version - b.version
    c := _cmp(a.groups, b.groups)
    if c != 0:
        return c
    pa := a.max_prefixlen()
    pb := b.max_prefixlen()
    if isinstance(a, IPNetwork):
        pa = a.prefixlen
    if isinstance(b, IPNetwork):
        pb = b.prefixlen
    return pa - pb
