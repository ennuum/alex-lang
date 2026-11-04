# alex: native
# ALEX STANDARD LIBRARY — network_driver.network_packet
#
# Paquets au-dessus d'Ethernet, construits et analysés directement dans un PacketBuffer (sans copie) :
#   - adresses IPv4 (entier 32 bits <-> « 10.0.2.15 »), somme de contrôle Internet (RFC 1071) ;
#   - ARP (requête / réponse), IPv4 (en-tête de 20 octets, somme de contrôle), ICMP (écho), UDP (avec
#     pseudo-en-tête) ;
#   - Packet : analyse d'une trame reçue (Ethernet -> ARP / IPv4 -> ICMP / UDP / TCP) avec vérification des
#     sommes de contrôle, et description lisible.
#
#   use network_driver.network_packet as np
#   b := pool.get()
#   np.build_icmp_echo(b, mon_mac, passerelle_mac, np.ip("10.0.2.15"), np.ip("10.0.2.2"), 1, 1, "ping")
#   carte.send(b)
#   p := np.parse(recu)
#   if p.is_icmp_reply():
#       print(p.describe())
#
# Compilable en natif (# alex: native).

use hw
use network_driver.ethernet as eth
use network_driver.network_buffer as nbuf
from network_driver.network_buffer use PacketBuffer

const PROTO_ICMP := 1
const PROTO_TCP := 6
const PROTO_UDP := 17

const ARP_REQUEST := 1
const ARP_REPLY := 2

const ICMP_ECHO_REPLY := 0
const ICMP_UNREACHABLE := 3
const ICMP_ECHO_REQUEST := 8

# « a.b.c.d » -> entier ; -1 si invalide.
func ip(text: str) -> int:
    v := 0
    part := 0
    digits := 0
    dots := 0
    for ch in text:
        c := str(ch)
        if c == ".":
            if digits == 0 or part > 255:
                return -1
            v = (v << 8) | part
            part = 0
            digits = 0
            dots += 1
        else:
            d := _digit(c)
            if d < 0:
                return -1
            part = part * 10 + d
            digits += 1
    if dots != 3 or digits == 0 or part > 255:
        return -1
    return (v << 8) | part

func _digit(c: str) -> int:
    ds := "0123456789"
    k := 0
    while k < 10:
        if c == str(ds[k]):
            return k
        k += 1
    return -1

func ip_text(v: int) -> str:
    return str((v >> 24) & 255) + "." + str((v >> 16) & 255) + "." + str((v >> 8) & 255) + "." + str(v & 255)

# Somme partielle (16 bits gros-boutistes) des n octets à addr, ajoutée à acc.
func sum16(addr: int, n: int, acc: int) -> int:
    s := acc
    k := 0
    while k + 1 < n:
        s += (hw.peek8(addr + k) << 8) | hw.peek8(addr + k + 1)
        k += 2
    if k < n:
        s += hw.peek8(addr + k) << 8
    return s

func fold(s: int) -> int:
    v := s
    while v > 0xFFFF:
        v = (v & 0xFFFF) + (v >> 16)
    return (~v) & 0xFFFF

func checksum(addr: int, n: int) -> int:
    return fold(sum16(addr, n, 0))

# ---------------------------------------------------------------- construction
# Chaque fonction construit le paquet complet (Ethernet compris) dans b, vidé auparavant.

func build_arp(b: PacketBuffer, op: int, src_mac: int, src_ip: int, dst_mac: int, dst_ip: int):
    b.reset()
    a := b.put(28)
    eth.write16be(a, 1)              # Ethernet
    eth.write16be(a + 2, eth.TYPE_IPV4)
    hw.poke8(a + 4, 6)
    hw.poke8(a + 5, 4)
    eth.write16be(a + 6, op)
    eth.write_mac(a + 8, src_mac)
    eth.write32be(a + 14, src_ip)
    target := dst_mac
    if op == ARP_REQUEST:
        target = 0
    eth.write_mac(a + 18, target)
    eth.write32be(a + 24, dst_ip)
    h := b.push(14)
    eth.write_header(h, dst_mac, src_mac, eth.TYPE_ARP)
    b.pad_to(eth.MIN_FRAME)

# En-tête IPv4 devant la charge utile déjà placée dans b.
func push_ipv4(b: PacketBuffer, src: int, dst: int, proto: int, ident: int, ttl: int):
    total := b.length + 20
    h := b.push(20)
    hw.poke8(h, 0x45)
    hw.poke8(h + 1, 0)
    eth.write16be(h + 2, total)
    eth.write16be(h + 4, ident & 0xFFFF)
    eth.write16be(h + 6, 0x4000)     # ne pas fragmenter
    hw.poke8(h + 8, ttl)
    hw.poke8(h + 9, proto)
    eth.write16be(h + 10, 0)
    eth.write32be(h + 12, src)
    eth.write32be(h + 16, dst)
    eth.write16be(h + 10, checksum(h, 20))

func push_ethernet(b: PacketBuffer, dst_mac: int, src_mac: int, ethertype: int):
    h := b.push(14)
    eth.write_header(h, dst_mac, src_mac, ethertype)
    b.pad_to(eth.MIN_FRAME)

func build_icmp_echo(b: PacketBuffer, src_mac: int, dst_mac: int, src: int, dst: int, ident: int, seq: int, payload: str):
    b.reset()
    a := b.put(8)
    b.put_string(payload)
    n := b.length
    hw.poke8(a, ICMP_ECHO_REQUEST)
    hw.poke8(a + 1, 0)
    eth.write16be(a + 2, 0)
    eth.write16be(a + 4, ident)
    eth.write16be(a + 6, seq)
    eth.write16be(a + 2, checksum(a, n))
    push_ipv4(b, src, dst, PROTO_ICMP, seq, 64)
    push_ethernet(b, dst_mac, src_mac, eth.TYPE_IPV4)

func build_udp(b: PacketBuffer, src_mac: int, dst_mac: int, src: int, dst: int, sport: int, dport: int, payload: str):
    b.reset()
    a := b.put(8)
    b.put_string(payload)
    n := b.length
    eth.write16be(a, sport)
    eth.write16be(a + 2, dport)
    eth.write16be(a + 4, n)
    eth.write16be(a + 6, 0)
    s := (src >> 16) + (src & 0xFFFF) + (dst >> 16) + (dst & 0xFFFF) + PROTO_UDP + n
    c := fold(sum16(a, n, s))
    if c == 0:
        c = 0xFFFF
    eth.write16be(a + 6, c)
    push_ipv4(b, src, dst, PROTO_UDP, 1, 64)
    push_ethernet(b, dst_mac, src_mac, eth.TYPE_IPV4)

# ---------------------------------------------------------------- analyse
class Packet:
    valid: bool := false
    dst_mac: int := 0
    src_mac: int := 0
    ethertype: int := 0
    vlan: int := -1
    arp_op: int := 0
    sender_mac: int := 0
    sender_ip: int := 0
    target_mac: int := 0
    target_ip: int := 0
    src_ip: int := 0
    dst_ip: int := 0
    protocol: int := 0
    ttl: int := 0
    ip_checksum_ok: bool := false
    icmp_type: int := -1
    icmp_code: int := 0
    icmp_id: int := 0
    icmp_seq: int := 0
    src_port: int := 0
    dst_port: int := 0
    l4_checksum_ok: bool := false
    payload: int := 0         # adresse de la charge utile (après les en-têtes connus)
    payload_length: int := 0
    length: int := 0

    func init():
        self.valid = false

    func is_arp() -> bool:
        return self.ethertype == eth.TYPE_ARP and self.arp_op != 0

    func is_ipv4() -> bool:
        return self.ethertype == eth.TYPE_IPV4 and self.protocol != 0

    func is_icmp_reply() -> bool:
        return self.is_ipv4() and self.protocol == PROTO_ICMP and self.icmp_type == ICMP_ECHO_REPLY

    func is_udp() -> bool:
        return self.is_ipv4() and self.protocol == PROTO_UDP

    func payload_string() -> str:
        return hw.string_at(self.payload, self.payload_length)

    func describe() -> str:
        if not self.valid:
            return "trame invalide (" + str(self.length) + " octets)"
        t := eth.mac_text(self.src_mac) + " -> " + eth.mac_text(self.dst_mac) + " " + eth.type_name(self.ethertype)
        if self.is_arp():
            if self.arp_op == ARP_REQUEST:
                t = t + " : qui a " + ip_text(self.target_ip) + " ? demande " + ip_text(self.sender_ip)
            else:
                t = t + " : " + ip_text(self.sender_ip) + " est à " + eth.mac_text(self.sender_mac)
        elif self.is_ipv4():
            t = t + " " + ip_text(self.src_ip) + " -> " + ip_text(self.dst_ip) + " ttl " + str(self.ttl)
            if self.protocol == PROTO_ICMP:
                t = t + " ICMP type " + str(self.icmp_type) + " id " + str(self.icmp_id) + " seq " + str(self.icmp_seq)
            elif self.protocol == PROTO_UDP:
                t = t + " UDP " + str(self.src_port) + " -> " + str(self.dst_port) + " (" + str(self.payload_length) + " octets)"
            elif self.protocol == PROTO_TCP:
                t = t + " TCP " + str(self.src_port) + " -> " + str(self.dst_port)
            else:
                t = t + " protocole " + str(self.protocol)
            if not self.ip_checksum_ok:
                t = t + " [somme IP fausse]"
        return t

func parse(b: PacketBuffer) -> Packet:
    return parse_at(b.data(), b.length)

func parse_at(addr: int, n: int) -> Packet:
    p := Packet()
    p.length = n
    if n < 14:
        return p
    p.valid = true
    p.dst_mac = eth.dst_of(addr)
    p.src_mac = eth.src_of(addr)
    p.ethertype = eth.type_of(addr)
    p.vlan = eth.vlan_of(addr)
    h := eth.header_size(addr)
    a := addr + h
    rest := n - h
    p.payload = a
    p.payload_length = rest
    if p.ethertype == eth.TYPE_ARP and rest >= 28:
        p.arp_op = eth.read16be(a + 6)
        p.sender_mac = eth.read_mac(a + 8)
        p.sender_ip = eth.read32be(a + 14)
        p.target_mac = eth.read_mac(a + 18)
        p.target_ip = eth.read32be(a + 24)
        return p
    if p.ethertype != eth.TYPE_IPV4 or rest < 20:
        return p
    ihl := (hw.peek8(a) & 15) * 4
    total := eth.read16be(a + 2)
    if total > rest:
        total = rest
    p.protocol = hw.peek8(a + 9)
    p.ttl = hw.peek8(a + 8)
    p.src_ip = eth.read32be(a + 12)
    p.dst_ip = eth.read32be(a + 16)
    p.ip_checksum_ok = checksum(a, ihl) == 0
    l4 := a + ihl
    l4n := total - ihl
    p.payload = l4
    p.payload_length = l4n
    if p.protocol == PROTO_ICMP and l4n >= 8:
        p.icmp_type = hw.peek8(l4)
        p.icmp_code = hw.peek8(l4 + 1)
        p.icmp_id = eth.read16be(l4 + 4)
        p.icmp_seq = eth.read16be(l4 + 6)
        p.l4_checksum_ok = checksum(l4, l4n) == 0
        p.payload = l4 + 8
        p.payload_length = l4n - 8
    elif (p.protocol == PROTO_UDP or p.protocol == PROTO_TCP) and l4n >= 8:
        p.src_port = eth.read16be(l4)
        p.dst_port = eth.read16be(l4 + 2)
        if p.protocol == PROTO_UDP:
            s := (p.src_ip >> 16) + (p.src_ip & 0xFFFF) + (p.dst_ip >> 16) + (p.dst_ip & 0xFFFF) + PROTO_UDP + l4n
            p.l4_checksum_ok = eth.read16be(l4 + 6) == 0 or fold(sum16(l4, l4n, s)) == 0
            p.payload = l4 + 8
            p.payload_length = l4n - 8
        else:
            off := (hw.peek8(l4 + 12) >> 4) * 4
            p.payload = l4 + off
            p.payload_length = l4n - off
    return p
