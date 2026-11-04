# ALEX STANDARD LIBRARY — network.utils
#
# Outils communs : octets bruts (une `str` transporte des octets, comme dans network.socket), entiers en ordre
# réseau, « hôte:port », ports libres ou ouverts, adresse locale, tailles lisibles, noms d'hôte valides.
#
# Octets
#   Une donnée binaire est une `str` d'octets bruts (b* : taille, tranche, recherche EN OCTETS) ou une
#   list[int] d'octets 0..255 ; raw(x) accepte les deux et rend la forme str.
#
# Exemple
#   use network.utils as nu
#   nu.split_host_port("[::1]:8080")        # ("::1", 8080)
#   nu.pack_u32(258)                          # "\x00\x00\x01\x02" (4 octets)
#   nu.unpack_u16(nu.pack_u16(513), 0)        # 513
#   nu.free_port()                            # port TCP libre sur 127.0.0.1
#   nu.human_bytes(1536)                      # "1.5 Kio"

from core use len, type, to_int
from collections use append
use string as _s
use _native_net as _n
use network.socket as _sk
use network.dns as _dns
use network.tcp as _tcp
use os as _os
use time as _time

# ---------------------------------------------------------------- octets

# Forme str (octets bruts) d'une str ou d'une list[int] d'octets.
func raw(data):
    t := type(data)
    if t == "str":
        return data
    if t == "list" or t == "tuple":
        return _n.from_bytes(data)
    if data == null:
        return ""
    raise("TypeError", "network.utils.raw : str ou liste d'octets attendue (obtenu '" + t + "')")

# Liste d'octets d'une str (octets UTF-8) ou d'une liste.
func to_bytes(data):
    if type(data) == "list":
        return data
    return _n.to_bytes(raw(data))

func from_bytes(data):
    return _n.from_bytes(data)

# Taille en octets.
func byte_len(data):
    if type(data) == "list":
        return len(data)
    return _n.blen(data)

func byte_slice(data, start, end=null):
    n := _n.blen(data)
    if end == null or end > n:
        end = n
    if start < 0:
        start = 0
    if start >= end:
        return ""
    return _n.bslice(data, start, end)

# Position (en octets) de needle dans data à partir de start, ou -1.
func byte_find(data, needle, start=0):
    return _n.bfind(data, needle, start)

# Octet (0..255) à la position i.
func byte_at(data, i):
    return _n.to_bytes(_n.bslice(data, i, i + 1))[0]

# Concatène des morceaux (str d'octets ou listes).
func concat(parts):
    out := []
    for p in parts:
        append(out, raw(p))
    return _s.join("", out)

# Découpe en morceaux d'au plus size octets.
func chunks(data, size):
    if size < 1:
        raise("ArgumentError", "network.utils.chunks : taille >= 1 attendue")
    out := []
    s := raw(data)
    n := _n.blen(s)
    i := 0
    while i < n:
        j := i + size
        if j > n:
            j = n
        append(out, _n.bslice(s, i, j))
        i = j
    return out

func is_utf8(data):
    return _n.utf8_valid(raw(data))

# Octets aléatoires du système (str brute) — clés, jetons, nonces.
func random_bytes(n):
    return _n.random_bytes(n)

# ---------------------------------------------------------------- entiers en ordre réseau (big-endian)

func _pack(n, size, little):
    out := []
    i := 0
    while i < size:
        append(out, 0)
        i += 1
    v := n
    k := 0
    while k < size:
        b := v & 255
        if little:
            out[k] = b
        else:
            out[size - 1 - k] = b
        v = v >> 8
        k += 1
    return _n.from_bytes(out)

func _unpack(data, offset, size, little):
    if _n.blen(data) < offset + size:
        raise("ArgumentError", "network.utils.unpack : " + str(size) + " octets attendus à la position " + str(offset))
    b := _n.to_bytes(_n.bslice(data, offset, offset + size))
    v := 0
    k := 0
    while k < size:
        if little:
            v = (v << 8) | b[size - 1 - k]
        else:
            v = (v << 8) | b[k]
        k += 1
    return v

func pack_u8(n):
    return _pack(n, 1, false)

func pack_u16(n, little=false):
    return _pack(n, 2, little)

func pack_u24(n, little=false):
    return _pack(n, 3, little)

func pack_u32(n, little=false):
    return _pack(n, 4, little)

func pack_u64(n, little=false):
    return _pack(n, 8, little)

func unpack_u8(data, offset=0):
    return _unpack(data, offset, 1, false)

func unpack_u16(data, offset=0, little=false):
    return _unpack(data, offset, 2, little)

func unpack_u24(data, offset=0, little=false):
    return _unpack(data, offset, 3, little)

func unpack_u32(data, offset=0, little=false):
    return _unpack(data, offset, 4, little)

# Entier signé sur 64 bits (complément à deux, comme les int ALEX).
func unpack_u64(data, offset=0, little=false):
    return _unpack(data, offset, 8, little)

# ---------------------------------------------------------------- affichage

const _HEXD := "0123456789abcdef"

func _hex2(b):
    return str(_HEXD[b >> 4]) + str(_HEXD[b & 15])

# Vidage hexadécimal sur plusieurs lignes : « 00000000  48 65 6c 6c 6f  |Hello| ».
func hexdump(data, width=16):
    b := to_bytes(data)
    lines := []
    i := 0
    while i < len(b):
        hx := []
        txt := ""
        j := i
        while j < i + width:
            if j < len(b):
                append(hx, _hex2(b[j]))
                if b[j] >= 32 and b[j] < 127:
                    txt += str(_s.chr(b[j]))
                else:
                    txt += "."
            else:
                append(hx, "  ")
            j += 1
        off := ""
        v := i
        k := 0
        while k < 8:
            off = str(_HEXD[v & 15]) + off
            v = v >> 4
            k += 1
        append(lines, off + "  " + _s.join(" ", hx) + "  |" + txt + "|")
        i += width
    return _s.join("\n", lines)

# Taille lisible en unités binaires : 1536 -> "1.5 Kio".
func human_bytes(n):
    units := ["o", "Kio", "Mio", "Gio", "Tio", "Pio"]
    v := n * 1.0
    u := 0
    while v >= 1024.0 and u < len(units) - 1:
        v = v / 1024.0
        u += 1
    if u == 0:
        return str(n) + " o"
    return _fmt1(v) + " " + units[u]

# Débit lisible : 1250000 octets/s -> "10.0 Mbit/s".
func human_rate(bytes_per_second):
    bits := bytes_per_second * 8.0
    units := ["bit/s", "kbit/s", "Mbit/s", "Gbit/s", "Tbit/s"]
    u := 0
    while bits >= 1000.0 and u < len(units) - 1:
        bits = bits / 1000.0
        u += 1
    return _fmt1(bits) + " " + units[u]

func _fmt1(v):
    t := to_int(v * 10.0 + 0.5)
    return str(t // 10) + "." + str(t % 10)

# Écriture la plus courte d'un réel qui se relit à l'identique (comme repr() de Python) : 0.1 + 0.2 ->
# « 0.30000000000000004 », 100.0 -> « 100.0 », 1e20 -> « 1e+20 ».
func float_repr(x):
    return _n.repr_float(x)

# ---------------------------------------------------------------- hôtes et ports

# Vrai si p est un port 0..65535 (allow_zero : 0 accepté, « choisi par le système »).
func is_valid_port(p, allow_zero=false):
    if type(p) != "int":
        return false
    if p == 0:
        return allow_zero
    return p > 0 and p <= 65535

# Nom d'hôte valide (RFC 1123) : étiquettes de 1 à 63 caractères [a-z0-9-], sans tiret au bord, 253 au plus.
func is_valid_hostname(name):
    if type(name) != "str" or name == "" or len(name) > 253:
        return false
    h := name
    if _s.ends_with(h, "."):
        h = _s.substring(h, 0, len(h) - 1)
    for label in _s.split(h, "."):
        if label == "" or len(label) > 63:
            return false
        if label[0] == '-' or label[len(label) - 1] == '-':
            return false
        for c in label:
            ok := (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_'
            if not ok:
                return false
    return true

# Vrai si host est un nom ou une adresse IP utilisable.
func is_valid_host(host):
    return _dns.is_ip(host) or is_valid_hostname(host)

# « hôte:port » / « [v6]:port » / « hôte » -> (hôte, port) ; port : default_port si absent.
func split_host_port(text, default_port=null):
    if type(text) != "str" or text == "":
        raise("ArgumentError", "network.utils.split_host_port : texte non vide attendu")
    if text[0] == '[':
        e := _s.find(text, "]")
        if e < 0:
            raise("ArgumentError", "network.utils.split_host_port : « ] » manquant dans '" + text + "'")
        host := _s.substring(text, 1, e)
        rest := _s.substring(text, e + 1, len(text))
        if rest == "":
            return (host, default_port)
        if rest[0] != ':':
            raise("ArgumentError", "network.utils.split_host_port : « : » attendu après « ] » dans '" + text + "'")
        return (host, _parse_port(_s.substring(rest, 1, len(rest)), text))
    if _s.count(text, ":") > 1:     # IPv6 sans crochets : pas de port
        return (text, default_port)
    c := _s.find(text, ":")
    if c < 0:
        return (text, default_port)
    return (_s.substring(text, 0, c), _parse_port(_s.substring(text, c + 1, len(text)), text))

func _parse_port(t, whole):
    if t == "":
        raise("ArgumentError", "network.utils : port vide dans '" + whole + "'")
    for ch in t:
        if ch < '0' or ch > '9':
            raise("ArgumentError", "network.utils : port non numérique dans '" + whole + "'")
    if len(t) > 5:
        raise("ArgumentError", "network.utils : port hors de 0..65535 dans '" + whole + "'")
    p := to_int(t)
    if p > 65535:
        raise("ArgumentError", "network.utils : port hors de 0..65535 dans '" + whole + "'")
    return p

# Inverse de split_host_port (crochets pour IPv6).
func join_host_port(host, port):
    return _sk.format_address(host, port)

# Port TCP libre sur host (le système l'attribue ; il peut être repris entre-temps par un autre programme).
func free_port(host="127.0.0.1"):
    l := _tcp.listen(host, 0, 1, false)
    p := l.port()
    l.close()
    return p

# Vrai si une connexion TCP à host:port aboutit dans le délai.
func is_port_open(host, port, timeout=1.0):
    try:
        c := _tcp.connect(host, port, timeout)
        c.close()
        return true
    catch e:
        if e.type == "NetworkError" or e.type == "TimeoutError" or e.type == "DnsError":
            return false
        raise(e)

# Attend qu'un service accepte les connexions sur host:port (au plus timeout secondes) ; false sinon.
func wait_for_port(host, port, timeout=10.0, interval=0.05):
    end := _time.monotonic() + timeout
    while true:
        left := end - _time.monotonic()
        if left <= 0:
            return false
        step := 1.0
        if left < step:
            step = left
        if is_port_open(host, port, step):
            return true
        if _time.monotonic() + interval >= end:
            return false
        _time.sleep(interval)

# Adresse IP locale qu'utiliserait le système pour joindre `probe` (aucun paquet n'est envoyé : un socket UDP
# « connecté » choisit seulement sa route). Repli : boucle locale.
func local_ip(family=4, probe=null):
    target := probe
    if target == null:
        target = "192.0.2.1"
        if family == 6:
            target = "2001:db8::1"
    loopback := "127.0.0.1"
    if family == 6:
        loopback = "::1"
    try:
        s := _sk.Socket(family, "udp")
        try:
            s.connect(target, 9, 1.0)
            a := s.local_address()[0]
            s.close()
            if a == "0.0.0.0" or a == "::":
                return loopback
            return a
        catch e:
            s.close()
            return loopback
    catch e:
        return loopback

func hostname():
    return _os.hostname()

# Nom de domaine complet (FQDN) de la machine, si le résolveur le connaît ; sinon le nom court.
func fqdn(name=null):
    h := name
    if h == null:
        h = hostname()
    try:
        a := _dns.resolve_one(h)
        r := _dns.reverse(a)
        if r != null and _s.contains(r, "."):
            return r
    catch e:
        ignored := e
    return h

# ---------------------------------------------------------------- texte de protocole

# Lignes d'un texte (fins « \r\n » ou « \n »), sans la fin de ligne.
func split_lines(text):
    out := []
    for l in _s.split(text, "\n"):
        if _s.ends_with(l, "\r"):
            l = _s.substring(l, 0, len(l) - 1)
        append(out, l)
    if len(out) > 0 and out[len(out) - 1] == "":
        out = out[0:len(out) - 1]
    return out

# Normalise les fins de ligne en « \r\n » (protocoles Internet).
func to_crlf(text):
    t := _s.replace(text, "\r\n", "\n")
    t = _s.replace(t, "\r", "\n")
    return _s.replace(t, "\n", "\r\n")

# Vrai si s contient un retour chariot, un saut de ligne ou un NUL (injection d'en-tête ou de commande).
func has_control_breaks(s):
    return _s.contains(s, "\r") or _s.contains(s, "\n") or _s.contains(s, "\x00")

# Lève ArgumentError si s ne peut pas figurer sur une seule ligne de protocole.
func check_single_line(s, what="valeur"):
    if type(s) != "str":
        raise("TypeError", "network : " + what + " : str attendue (obtenu '" + type(s) + "')")
    if has_control_breaks(s):
        raise("ArgumentError", "network : " + what + " : retour à la ligne interdit (injection de protocole)")
    return s
