# alex: native
# ALEX STANDARD LIBRARY — network_driver.network_device
#
# Interface réseau vue par la pile au-dessus du pilote :
#
#   interface NetworkDevice
#       name() -> str             « eth0 », « lo »
#       mac() -> int              adresse MAC (48 bits)
#       mtu() -> int
#       link_up() -> bool
#       send(b) -> bool           émet la trame du PacketBuffer (le pilote ne le garde pas : il copie ou attend)
#       receive() -> PacketBuffer?  prochaine trame reçue (à rendre avec recycle), ou null
#       recycle(b)                rend un tampon reçu
#       stats() -> NetworkStats
#
# Fournis ici : LoopbackDevice (« lo » : ce qui est émis est reçu), et NetInterface : interface + adresse IPv4,
# table ARP, réponse automatique aux requêtes ARP et aux échos ICMP (ping), envoi UDP, attente d'un paquet.
#
#   lo := LoopbackDevice(pool)
#   itf := NetInterface(carte, ip("10.0.2.15"), ip("10.0.2.2"))
#   mac := itf.resolve(itf.gateway, 200000)      # ARP
#   print(itf.ping(itf.gateway, 1, 200000))       # vrai si réponse
#
# Compilable en natif (# alex: native).

from collections use append, contains_key
from core use len
use hw
use network_driver.ethernet as eth
use network_driver.network_buffer as nbuf
from network_driver.network_buffer use PacketBuffer, BufferPool
use network_driver.network_packet as np
from network_driver.network_packet use Packet
use network_driver.network_stats as ns
from network_driver.network_stats use NetworkStats

interface NetworkDevice:
    func name() -> str
    func mac() -> int
    func mtu() -> int
    func link_up() -> bool
    func send(b: PacketBuffer) -> bool
    func receive() -> PacketBuffer?
    func recycle(b: PacketBuffer)
    func stats() -> NetworkStats

class LoopbackDevice implements NetworkDevice:
    pool: BufferPool
    queue: list[PacketBuffer] := []
    counters: NetworkStats

    func init(pool: BufferPool):
        self.pool = pool
        self.queue = []
        self.counters = NetworkStats()

    func name() -> str:
        return "lo"

    func mac() -> int:
        return 0

    func mtu() -> int:
        return 65536

    func link_up() -> bool:
        return true

    func send(b: PacketBuffer) -> bool:
        c := self.pool.get()
        if c == null:
            self.counters.tx_dropped += 1
            return false
        c.reset_raw(0)
        c.copy_from(b.data(), b.length)
        append(self.queue, c)
        self.counters.count_tx(b.length)
        return true

    func receive() -> PacketBuffer?:
        if len(self.queue) == 0:
            return null
        b := self.queue[0]
        keep: list[PacketBuffer] := []
        i := 1
        while i < len(self.queue):
            append(keep, self.queue[i])
            i += 1
        self.queue = keep
        self.counters.count_rx(b.length, false, false)
        return b

    func recycle(b: PacketBuffer):
        self.pool.put(b)

    func stats() -> NetworkStats:
        return self.counters

# ---------------------------------------------------------------- interface IPv4 minimale
class NetInterface:
    dev: NetworkDevice
    address: int := 0
    gateway: int := 0
    arp: dict[int, int] := {}
    pool: BufferPool
    log: list[str] := []
    replies: int := 0           # échos ICMP reçus en réponse
    answered: int := 0          # requêtes ARP / ICMP auxquelles on a répondu
    udp_inbox: list[str] := []

    func init(dev: NetworkDevice, address: int, gateway: int):
        self.dev = dev
        self.address = address
        self.gateway = gateway
        self.arp = {}
        self.pool = BufferPool(32)
        self.log = []
        self.replies = 0
        self.answered = 0
        self.udp_inbox = []

    func _buffer() -> PacketBuffer:
        b := self.pool.get()
        if b == null:
            raise("DeviceBusy", "NetInterface : plus de tampons")
        return b

    # Traite les trames reçues (ARP, écho ICMP, UDP) ; renvoie le nombre traité.
    func poll() -> int:
        n := 0
        while true:
            b := self.dev.receive()
            if b == null:
                break
            p := np.parse(b)
            self._handle(p)
            self.dev.recycle(b)
            n += 1
        return n

    func _handle(p: Packet):
        if p.is_arp():
            self.arp[p.sender_ip] = p.sender_mac
            if p.arp_op == np.ARP_REQUEST and p.target_ip == self.address:
                r := self._buffer()
                np.build_arp(r, np.ARP_REPLY, self.dev.mac(), self.address, p.sender_mac, p.sender_ip)
                self.dev.send(r)
                self.pool.put(r)
                self.answered += 1
            return
        if not p.is_ipv4() or p.dst_ip != self.address:
            return
        self.arp[p.src_ip] = p.src_mac
        if p.protocol == np.PROTO_ICMP:
            if p.icmp_type == np.ICMP_ECHO_REPLY:
                self.replies += 1
                append(self.log, "écho de " + np.ip_text(p.src_ip) + " seq " + str(p.icmp_seq))
            elif p.icmp_type == np.ICMP_ECHO_REQUEST:
                r := self._buffer()
                np.build_icmp_echo(r, self.dev.mac(), p.src_mac, self.address, p.src_ip, p.icmp_id, p.icmp_seq, p.payload_string())
                # type 0 (réponse) : corrige le type et la somme
                icmp := r.data() + 34
                hw.poke8(icmp, np.ICMP_ECHO_REPLY)
                eth.write16be(icmp + 2, 0)
                eth.write16be(icmp + 2, np.checksum(icmp, 8 + p.payload_length))
                self.dev.send(r)
                self.pool.put(r)
                self.answered += 1
        elif p.protocol == np.PROTO_UDP:
            append(self.udp_inbox, p.payload_string())

    # Adresse MAC de ip (table ARP, sinon requête ARP et attente d'au plus tries tours) ; -1 si inconnue.
    func resolve(target: int, tries: int) -> int:
        if contains_key(self.arp, target):
            return self.arp[target]
        b := self._buffer()
        np.build_arp(b, np.ARP_REQUEST, self.dev.mac(), self.address, eth.BROADCAST, target)
        self.dev.send(b)
        self.pool.put(b)
        i := 0
        while i < tries:
            self.poll()
            if contains_key(self.arp, target):
                return self.arp[target]
            hw.pause()
            i += 1
        return -1

    # Envoie un écho ICMP à target et attend la réponse ; vrai si elle arrive.
    func ping(target: int, seq: int, tries: int) -> bool:
        m := self.resolve(target, tries)
        if m < 0:
            return false
        before := self.replies
        b := self._buffer()
        np.build_icmp_echo(b, self.dev.mac(), m, self.address, target, 0x4C58, seq, "Alex ping")
        self.dev.send(b)
        self.pool.put(b)
        i := 0
        while i < tries:
            self.poll()
            if self.replies > before:
                return true
            hw.pause()
            i += 1
        return false

    func send_udp(target: int, sport: int, dport: int, payload: str, tries: int) -> bool:
        m := self.resolve(target, tries)
        if m < 0:
            return false
        b := self._buffer()
        np.build_udp(b, self.dev.mac(), m, self.address, target, sport, dport, payload)
        r := self.dev.send(b)
        self.pool.put(b)
        return r
