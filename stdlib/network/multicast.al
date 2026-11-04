# ALEX STANDARD LIBRARY — network.multicast
#
# Multidiffusion IP (multicast) en UDP, IPv4 et IPv6 : abonnement à des groupes (IGMP / MLD par le système),
# envoi au groupe, durée de vie (TTL / hop limit), boucle locale, choix de l'interface ; découverte SSDP (UPnP).
#
#   s := MulticastSocket("239.1.2.3", 5000)          rejoint le groupe et écoute sur le port
#   s.send("bonjour à tous")                          envoi au groupe (TTL 1 par défaut : réseau local)
#   d := s.receive(2.0)                               network.udp.Datagram (text, host, port)
#   s.join("239.1.2.4") ; s.leave("239.1.2.3") ; s.close()
#   sender("239.1.2.3", 5000).send(...)               émetteur seul (sans abonnement)
#   ssdp_search("ssdp:all", 2.0)                      équipements UPnP du réseau (list de dict d'en-têtes)
#
# Plusieurs programmes de la machine peuvent écouter le même groupe et le même port (SO_REUSEADDR / SO_REUSEPORT).
#
# Erreurs : NetworkError (abonnement refusé, pas de route multicast...), TimeoutError, ArgumentError.
#
# Exemple
#   use network.multicast as mc
#   r := mc.MulticastSocket("239.255.0.1", 4446)
#   mc.sender("239.255.0.1", 4446).send("ping")
#   print(r.receive(1.0).text())

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use time as _time
use network.socket as _sk
use network.udp as _udp
use network.ipaddress as _ip

const SSDP_GROUP := "239.255.255.250"
const SSDP_PORT := 1900
const MDNS_GROUP := "224.0.0.251"
const MDNS_GROUP6 := "ff02::fb"
const ALL_HOSTS := "224.0.0.1"

# Vrai si l'adresse est un groupe multicast (224.0.0.0/4 ou ff00::/8).
func is_multicast(address):
    try:
        return _ip.ip_address(address).is_multicast()
    catch e:
        return false

func _check_group(group):
    if not is_multicast(group):
        raise("ArgumentError", "multicast : « " + str(group) + " » n'est pas une adresse de groupe (224.0.0.0/4, ff00::/8)")
    return _ip.ip_address(group)

func _mc(sock, op, group, iface):
    r := _n.multicast(sock._h("multicast"), op, group, iface)
    if _sk.is_error(r):
        _sk.fail("multicast " + op + " " + group, r)

class MulticastSocket:
    # group : groupe à rejoindre (ou null : aucun) ; port : port d'écoute ; iface : IPv4 = adresse locale de
    # l'interface, IPv6 = nom d'interface ("" : choix du système) ; ttl : portée des envois (1 : réseau local) ;
    # loop : recevoir ses propres envois.
    func init(group, port, iface="", ttl=1, loop=true, reuse=true, family=null):
        fam := family
        if fam == null:
            fam = 4
            if group != null:
                fam = _check_group(group).version
        self.family = fam
        self.port = port
        self.iface = iface
        if iface == null:
            self.iface = ""
        self.groups = []
        self.sock = _sk.Socket(fam, "udp")
        try:
            if reuse:
                self.sock.set_option("reuse_address", true)
                try:
                    self.sock.set_option("reuse_port", true)
                catch e:
                    ignored := e
            if port != null:
                self.sock.bind("", port)
            self.set_ttl(ttl)
            self.set_loop(loop)
            if self.iface != "":
                self._set_iface(self.iface)
            if group != null:
                self.join(group)
        catch e:
            self.sock.close()
            raise(e)
        self.default_group = group

    func _set_iface(iface):
        g := ALL_HOSTS
        if self.family == 6:
            g = "ff02::1"
        _mc(self.sock, "interface", g, iface)

    # Rejoint un groupe (sur l'interface du socket, ou `iface`).
    func join(group, iface=null):
        g := _check_group(group)
        if g.version != self.family:
            raise("ArgumentError", "multicast : groupe IPv" + str(g.version) + " sur un socket IPv" + str(self.family))
        i := iface
        if i == null:
            i = self.iface
        _mc(self.sock, "join", g.str(), i)
        append(self.groups, g.str())
        return self

    func leave(group, iface=null):
        g := _check_group(group)
        i := iface
        if i == null:
            i = self.iface
        _mc(self.sock, "leave", g.str(), i)
        kept := []
        for x in self.groups:
            if x != g.str():
                append(kept, x)
        self.groups = kept
        return self

    func set_ttl(ttl):
        if type(ttl) != "int" or ttl < 0 or ttl > 255:
            raise("ArgumentError", "multicast : TTL entier 0..255 attendu")
        self.sock.set_option("multicast_ttl", ttl)
        self.ttl = ttl

    func set_loop(on):
        self.sock.set_option("multicast_loop", on)

    func set_interface(iface):
        self.iface = iface
        self._set_iface(iface)

    # Envoie au groupe (défaut : celui du constructeur) ; rend le nombre d'octets.
    func send(data, group=null, port=null):
        g := group
        if g == null:
            g = self.default_group
        if g == null:
            raise("ArgumentError", "multicast.send : aucun groupe de destination")
        p := port
        if p == null:
            p = self.port
        return self.sock.send_to(data, _check_group(g).str(), p)

    # Envoie à une adresse quelconque (réponse unicast, par exemple).
    func send_to(data, host, port):
        return self.sock.send_to(data, host, port)

    # Prochain datagramme (network.udp.Datagram) ; TimeoutError après timeout secondes.
    func receive(timeout=null, max=65536):
        r := self.sock.recv_from(max, timeout)
        return _udp.Datagram(r[0], r[1], r[2])

    func try_receive(max=65536):
        try:
            return self.receive(0, max)
        catch e:
            if e.type == "TimeoutError":
                return null
            raise(e)

    # Tous les datagrammes reçus pendant `duration` secondes.
    func collect(duration, max_items=1000):
        out := []
        end := _time.monotonic() + duration
        while len(out) < max_items:
            left := end - _time.monotonic()
            if left <= 0:
                break
            try:
                append(out, self.receive(left))
            catch e:
                if e.type == "TimeoutError":
                    break
                raise(e)
        return out

    func local_port():
        return self.sock.local_address()[1]

    func close():
        for g in self.groups:
            try:
                _mc(self.sock, "leave", g, self.iface)
            catch e:
                ignored := e
        self.groups = []
        self.sock.close()

    func __enter__():
        return self

    func __exit__(t, v, tb):
        self.close()
        return false

# Émetteur seul vers group:port (aucun abonnement, port local choisi par le système).
func sender(group, port, ttl=1, iface="", loop=true):
    g := _check_group(group)
    s := MulticastSocket(null, null, iface, ttl, loop, false, g.version)
    s.default_group = g.str()
    s.port = port
    return s

# ---------------------------------------------------------------- SSDP (UPnP)

# Recherche SSDP (M-SEARCH) : réponses des équipements pendant `timeout` secondes, en dict d'en-têtes (noms en
# minuscules) avec « _host » (adresse de l'équipement). target : « ssdp:all », « upnp:rootdevice »,
# « urn:schemas-upnp-org:device:MediaRenderer:1 »...
func ssdp_search(target="ssdp:all", timeout=2.0, mx=1, iface=""):
    s := MulticastSocket(null, 0, iface, 2, true, false, 4)
    try:
        msg := "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: " + str(mx) + "\r\nST: " + target + "\r\nUSER-AGENT: Alex/1.0 UPnP/1.1 network.multicast/1.0\r\n\r\n"
        s.send(msg, SSDP_GROUP, SSDP_PORT)
        out := []
        seen := {}
        for d in s.collect(timeout):
            h := parse_ssdp(d.text())
            if h == null:
                continue
            h["_host"] = d.host
            key := d.host + "|" + str(h["usn"] if "usn" in h else "") + "|" + str(h["location"] if "location" in h else "")
            if not contains_key(seen, key):
                seen[key] = true
                append(out, h)
        s.close()
        return out
    catch e:
        s.close()
        raise(e)

# En-têtes d'un message SSDP (réponse « HTTP/1.1 200 OK » ou annonce « NOTIFY ») ; null s'il n'en est pas un.
func parse_ssdp(text):
    lines := _s.split(_s.replace(text, "\r\n", "\n"), "\n")
    if len(lines) == 0:
        return null
    first := lines[0]
    if not (_s.starts_with(first, "HTTP/1.1 200") or _s.starts_with(first, "NOTIFY ") or _s.starts_with(first, "M-SEARCH ")):
        return null
    out := {"_start": first}
    for l in lines[1:len(lines)]:
        c := _s.find(l, ":")
        if c > 0:
            out[_s.lower(_s.trim(_s.substring(l, 0, c)))] = _s.trim(_s.substring(l, c + 1, len(l)))
    return out

# Annonce SSDP « ssdp:alive » d'un service local (location : URL de sa description).
func ssdp_announce(location, nt, usn, max_age=1800, iface=""):
    s := sender(SSDP_GROUP, SSDP_PORT, 2, iface)
    try:
        msg := "NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=" + str(max_age) + "\r\nLOCATION: " + location + "\r\nNT: " + nt + "\r\nNTS: ssdp:alive\r\nSERVER: Alex/1.0 UPnP/1.1 network.multicast/1.0\r\nUSN: " + usn + "\r\n\r\n"
        n := s.send(msg)
        s.close()
        return n
    catch e:
        s.close()
        raise(e)
