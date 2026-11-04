# alex: native
# ALEX STANDARD LIBRARY — network_driver.network_offload
#
# Délestage (offload) : ce que la carte peut faire à la place du processeur, et l'équivalent logiciel quand
# elle ne le peut pas :
#   - Features : capacités (sommes de contrôle en émission / réception, TSO, retrait / insertion VLAN,
#     dispersion), négociées entre ce que la carte propose et ce que la pile demande ;
#   - sommes de contrôle : en-tête IPv4, TCP / UDP avec pseudo-en-tête (calcul, vérification) ;
#   - VLAN 802.1Q : insertion et retrait de l'étiquette dans un PacketBuffer ;
#   - TSO / GSO logiciel : découpe d'un segment TCP plus grand que le MSS en trames (numéros de séquence,
#     longueurs, identifiants IP, drapeaux FIN / PSH sur la dernière, sommes recalculées) ;
#   - descripteur de contexte e1000 (champs IPCSS / IPCSO / IPCSE / TUCSS / TUCSO / TUCSE) pour une trame.
#
#   use network_driver.network_offload as no
#   f := no.negotiate(no.Features(no.ALL), demande)
#   no.fill_checksums(tampon)              # IPv4 + TCP/UDP calculées en logiciel
#   no.insert_vlan(tampon, 42, 0)
#   segs := no.segment_tcp(gros, 1460, reserve)   # list[PacketBuffer]
#
# Erreurs : OffloadError (trame non IPv4 / non TCP pour TSO, MSS invalide, VLAN déjà présent),
# NoBuffer. Compilable en natif.

from core use len
from collections use append
use hw
use network_driver.ethernet as eth
use network_driver.network_packet as np
use network_driver.network_buffer as nb
from network_driver.network_buffer use PacketBuffer, BufferPool

const RX_CSUM := 1
const TX_CSUM := 2
const TSO := 4
const VLAN_STRIP := 8
const VLAN_INSERT := 16
const SCATTER := 32
const ALL := 63

class Features:
    bits: int := 0

    func init(bits: int):
        self.bits = bits

    func has(f: int) -> bool:
        return self.bits & f == f

    func describe() -> str:
        t := ""
        if self.has(RX_CSUM):
            t = t + " rx-csum"
        if self.has(TX_CSUM):
            t = t + " tx-csum"
        if self.has(TSO):
            t = t + " tso"
        if self.has(VLAN_STRIP):
            t = t + " vlan-strip"
        if self.has(VLAN_INSERT):
            t = t + " vlan-insert"
        if self.has(SCATTER):
            t = t + " sg"
        if t == "":
            return "aucune"
        return t

# Fonctions retenues : demandées ET proposées ; TSO exige TX_CSUM et SCATTER.
func negotiate(device: Features, wanted: int) -> Features:
    b := device.bits & wanted
    if b & TSO != 0 and (b & TX_CSUM == 0 or b & SCATTER == 0):
        b = b & ~TSO
    return Features(b)

# ---------------------------------------------------------------- décalages
# Décalage de l'en-tête IPv4 dans la trame (14, ou 18 avec VLAN) ; -1 si ce n'est pas de l'IPv4.
func l3_offset(b: PacketBuffer) -> int:
    if b.length < 14:
        return -1
    a := b.data()
    h := eth.header_size(a)
    if eth.type_of(a) != eth.TYPE_IPV4 or b.length < h + 20:
        return -1
    return h

func _ihl(b: PacketBuffer, l3: int) -> int:
    return (b.u8(l3) & 15) * 4

func _pseudo(b: PacketBuffer, l3: int, proto: int, l4len: int) -> int:
    src := b.u32(l3 + 12)
    dst := b.u32(l3 + 16)
    return (src >> 16) + (src & 0xFFFF) + (dst >> 16) + (dst & 0xFFFF) + proto + l4len

# Calcule les sommes IPv4 et TCP/UDP de la trame ; renvoie false si ce n'est pas de l'IPv4.
func fill_checksums(b: PacketBuffer) -> bool:
    l3 := l3_offset(b)
    if l3 < 0:
        return false
    ihl := _ihl(b, l3)
    total := b.u16(l3 + 2)
    b.set_u16(l3 + 10, 0)
    b.set_u16(l3 + 10, np.checksum(b.data() + l3, ihl))
    proto := b.u8(l3 + 9)
    l4 := l3 + ihl
    l4len := total - ihl
    if proto == np.PROTO_TCP:
        b.set_u16(l4 + 16, 0)
        b.set_u16(l4 + 16, np.fold(np.sum16(b.data() + l4, l4len, _pseudo(b, l3, proto, l4len))))
    elif proto == np.PROTO_UDP:
        b.set_u16(l4 + 6, 0)
        c := np.fold(np.sum16(b.data() + l4, l4len, _pseudo(b, l3, proto, l4len)))
        if c == 0:
            c = 0xFFFF
        b.set_u16(l4 + 6, c)
    return true

# Vérification à la réception : [ip_ok, l4_ok] (l4_ok vrai si le protocole n'a pas de somme connue).
func verify_checksums(b: PacketBuffer) -> list[bool]:
    out: list[bool] := []
    l3 := l3_offset(b)
    if l3 < 0:
        append(out, false)
        append(out, false)
        return out
    ihl := _ihl(b, l3)
    total := b.u16(l3 + 2)
    append(out, np.checksum(b.data() + l3, ihl) == 0)
    proto := b.u8(l3 + 9)
    l4 := l3 + ihl
    l4len := total - ihl
    if proto == np.PROTO_TCP:
        append(out, np.fold(np.sum16(b.data() + l4, l4len, _pseudo(b, l3, proto, l4len))) == 0)
    elif proto == np.PROTO_UDP:
        if b.u16(l4 + 6) == 0:
            append(out, true)
        else:
            append(out, np.fold(np.sum16(b.data() + l4, l4len, _pseudo(b, l3, proto, l4len))) == 0)
    else:
        append(out, true)
    return out

# ---------------------------------------------------------------- VLAN
func insert_vlan(b: PacketBuffer, vid: int, priority: int):
    if vid < 0 or vid > 4094 or priority < 0 or priority > 7:
        raise("OffloadError", "VLAN " + str(vid) + " / priorité " + str(priority) + " invalide")
    if b.length < 14:
        raise("OffloadError", "insert_vlan : trame trop courte")
    if eth.read16be(b.data() + 12) == eth.TYPE_VLAN:
        raise("OffloadError", "insert_vlan : trame déjà étiquetée")
    old := b.data()
    b.push(4)
    a := b.data()
    hw.copy(a, old, 12)
    eth.write16be(a + 12, eth.TYPE_VLAN)
    eth.write16be(a + 14, (priority << 13) | vid)

# Retire l'étiquette ; renvoie le VID (-1 si la trame n'en avait pas).
func strip_vlan(b: PacketBuffer) -> int:
    if b.length < 18 or eth.read16be(b.data() + 12) != eth.TYPE_VLAN:
        return -1
    a := b.data()
    vid := eth.read16be(a + 14) & 0x0FFF
    k := 11
    while k >= 0:
        hw.poke8(a + 4 + k, hw.peek8(a + k))
        k -= 1
    b.pull(4)
    return vid

# ---------------------------------------------------------------- TSO logiciel
# Découpe une trame TCP/IPv4 dont la charge dépasse mss en trames d'au plus mss octets de charge.
func segment_tcp(b: PacketBuffer, mss: int, pool: BufferPool) -> list[PacketBuffer]:
    if mss < 64 or mss > 9000:
        raise("OffloadError", "MSS " + str(mss) + " invalide")
    l3 := l3_offset(b)
    if l3 < 0 or b.u8(l3 + 9) != np.PROTO_TCP:
        raise("OffloadError", "segment_tcp : trame TCP/IPv4 attendue")
    ihl := _ihl(b, l3)
    l4 := l3 + ihl
    thl := (b.u8(l4 + 12) >> 4) * 4
    hdr := l4 + thl
    total := b.u16(l3 + 2)
    payload := total - ihl - thl
    seq := b.u32(l4 + 4)
    ident := b.u16(l3 + 4)
    flags := b.u8(l4 + 13)
    out: list[PacketBuffer] := []
    off := 0
    k := 0
    while off < payload or (payload == 0 and k == 0):
        n := payload - off
        if n > mss:
            n = mss
        s := pool.get()
        if s == null:
            for x in out:
                pool.put(x)
            raise("NoBuffer", "segment_tcp : plus de tampon")
        s.reset()
        s.copy_from(b.data(), hdr)
        if n > 0:
            s.copy_from(b.data() + hdr + off, n)
        s.set_u16(l3 + 2, ihl + thl + n)
        s.set_u16(l3 + 4, (ident + k) & 0xFFFF)
        s.set_u32(l4 + 4, (seq + off) & 0xFFFFFFFF)
        last := off + n >= payload
        if not last:
            s.set_u8(l4 + 13, flags & ~0x09)
        fill_checksums(s)
        append(out, s)
        off += n
        k += 1
        if payload == 0:
            break
    return out

# Champs du descripteur de contexte e1000 pour une trame : [ipcss, ipcso, ipcse, tucss, tucso, tucse].
func e1000_context(b: PacketBuffer) -> list[int]:
    l3 := l3_offset(b)
    if l3 < 0:
        raise("OffloadError", "contexte e1000 : trame IPv4 attendue")
    ihl := _ihl(b, l3)
    proto := b.u8(l3 + 9)
    l4 := l3 + ihl
    cso := 0
    if proto == np.PROTO_TCP:
        cso = l4 + 16
    elif proto == np.PROTO_UDP:
        cso = l4 + 6
    else:
        raise("OffloadError", "contexte e1000 : TCP ou UDP attendu")
    out: list[int] := []
    append(out, l3)
    append(out, l3 + 10)
    append(out, l4 - 1)
    append(out, l4)
    append(out, cso)
    append(out, 0)
    return out

# Construit une trame TCP/IPv4 (outil de test et de pile minimale) : charge payload, drapeaux flags.
func build_tcp(b: PacketBuffer, src_mac: int, dst_mac: int, src: int, dst: int, sport: int, dport: int, seq: int, ack: int, flags: int, payload: str):
    b.reset()
    a := b.put(20)
    b.put_string(payload)
    eth.write16be(a, sport)
    eth.write16be(a + 2, dport)
    eth.write32be(a + 4, seq)
    eth.write32be(a + 8, ack)
    hw.poke8(a + 12, 0x50)
    hw.poke8(a + 13, flags)
    eth.write16be(a + 14, 65535)
    eth.write16be(a + 16, 0)
    eth.write16be(a + 18, 0)
    np.push_ipv4(b, src, dst, np.PROTO_TCP, 100, 64)
    h := b.push(14)
    eth.write_header(h, dst_mac, src_mac, eth.TYPE_IPV4)
    fill_checksums(b)
