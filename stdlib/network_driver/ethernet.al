# alex: native
# ALEX STANDARD LIBRARY — network_driver.ethernet
#
# Couche Ethernet (IEEE 802.3) : adresses MAC (entier de 48 bits), en-tête de trame (destination, source,
# type ou étiquette VLAN 802.1Q), types de protocole (EtherType), CRC-32 de la séquence de contrôle (FCS),
# tailles minimale et maximale des trames.
#
#   use network_driver.ethernet as eth
#   m := eth.parse_mac("52:54:00:12:34:56")
#   print(eth.mac_text(m), eth.is_multicast(m))
#   eth.write_header(adresse, eth.BROADCAST, m, eth.TYPE_ARP)
#   print(eth.crc32_at(adresse, 60))
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use hw

const BROADCAST := 0xFFFFFFFFFFFF
const HEADER := 14
const VLAN_HEADER := 18
const MIN_FRAME := 60          # sans FCS (64 avec)
const MAX_FRAME := 1514        # sans FCS (1518 avec)
const MTU := 1500

const TYPE_IPV4 := 0x0800
const TYPE_ARP := 0x0806
const TYPE_VLAN := 0x8100
const TYPE_IPV6 := 0x86DD
const TYPE_LLDP := 0x88CC

func type_name(t: int) -> str:
    if t == TYPE_IPV4:
        return "IPv4"
    if t == TYPE_ARP:
        return "ARP"
    if t == TYPE_IPV6:
        return "IPv6"
    if t == TYPE_VLAN:
        return "VLAN"
    if t == TYPE_LLDP:
        return "LLDP"
    if t <= 1500:
        return "802.3 (longueur " + str(t) + ")"
    return "type " + str(t)

func _hex2(v: int) -> str:
    d := "0123456789abcdef"
    return str(d[(v >> 4) & 15]) + str(d[v & 15])

# « 52:54:00:12:34:56 »
func mac_text(m: int) -> str:
    out := ""
    k := 5
    while k >= 0:
        out = out + _hex2((m >> (8 * k)) & 255)
        if k > 0:
            out = out + ":"
        k -= 1
    return out

func _hexval(c: str) -> int:
    d := "0123456789abcdef"
    D := "0123456789ABCDEF"
    k := 0
    while k < 16:
        if c == str(d[k]) or c == str(D[k]):
            return k
        k += 1
    return -1

# Adresse en texte (séparateurs « : » ou « - ») -> entier ; -1 si invalide.
func parse_mac(text: str) -> int:
    v := 0
    digits := 0
    for ch in text:
        c := str(ch)
        if c == ":" or c == "-":
            continue
        h := _hexval(c)
        if h < 0:
            return -1
        v = (v << 4) | h
        digits += 1
    if digits != 12:
        return -1
    return v

func is_broadcast(m: int) -> bool:
    return m == BROADCAST

# Bit I/G (le plus faible du premier octet) : multidiffusion (dont diffusion).
func is_multicast(m: int) -> bool:
    return (m >> 40) & 1 == 1

# Bit U/L : adresse administrée localement.
func is_local(m: int) -> bool:
    return (m >> 40) & 2 == 2

func read_mac(addr: int) -> int:
    v := 0
    k := 0
    while k < 6:
        v = (v << 8) | hw.peek8(addr + k)
        k += 1
    return v

func write_mac(addr: int, m: int):
    k := 0
    while k < 6:
        hw.poke8(addr + k, (m >> (8 * (5 - k))) & 255)
        k += 1

# Entiers gros-boutistes (ordre du réseau).
func read16be(addr: int) -> int:
    return (hw.peek8(addr) << 8) | hw.peek8(addr + 1)

func write16be(addr: int, v: int):
    hw.poke8(addr, (v >> 8) & 255)
    hw.poke8(addr + 1, v & 255)

func read32be(addr: int) -> int:
    return (read16be(addr) << 16) | read16be(addr + 2)

func write32be(addr: int, v: int):
    write16be(addr, (v >> 16) & 0xFFFF)
    write16be(addr + 2, v & 0xFFFF)

func write_header(addr: int, dst: int, src: int, ethertype: int):
    write_mac(addr, dst)
    write_mac(addr + 6, src)
    write16be(addr + 12, ethertype)

func dst_of(addr: int) -> int:
    return read_mac(addr)

func src_of(addr: int) -> int:
    return read_mac(addr + 6)

# Type effectif (après une éventuelle étiquette VLAN).
func type_of(addr: int) -> int:
    t := read16be(addr + 12)
    if t == TYPE_VLAN:
        return read16be(addr + 16)
    return t

func vlan_of(addr: int) -> int:
    if read16be(addr + 12) == TYPE_VLAN:
        return read16be(addr + 14) & 0xFFF
    return -1

# Taille de l'en-tête (14, ou 18 avec VLAN).
func header_size(addr: int) -> int:
    if read16be(addr + 12) == TYPE_VLAN:
        return VLAN_HEADER
    return HEADER

_crc_table: list[int] := []

func _table() -> list[int]:
    if len(_crc_table) == 0:
        n := 0
        while n < 256:
            c := n
            k := 0
            while k < 8:
                if c & 1 != 0:
                    c = 0xEDB88320 ^ (c >> 1)
                else:
                    c = c >> 1
                k += 1
            append(_crc_table, c)
            n += 1
    return _crc_table

# CRC-32 IEEE (celui de la FCS Ethernet, de zlib, de PNG) des n octets à addr.
func crc32_at(addr: int, n: int) -> int:
    t := _table()
    c := 0xFFFFFFFF
    k := 0
    while k < n:
        c = t[(c ^ hw.peek8(addr + k)) & 255] ^ (c >> 8)
        k += 1
    return c ^ 0xFFFFFFFF
