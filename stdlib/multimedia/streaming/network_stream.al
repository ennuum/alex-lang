# ALEX STANDARD LIBRARY — multimedia.streaming.network_stream
#
# Format de paquet du flux réseau ALEX (« AMS1 ») et son codage, commun à UDP et TCP :
#   magie « AMS1 » (4) | version (1) | drapeaux (1 : 1 = clé, 2 = fin de flux, 4 = configuration) |
#   séquence u32 | horodatage u64 (échantillons ou µs) | longueur u32 | charge utile | CRC-32 (sur l'ensemble)
# La charge utile d'un flux audio est du PCM s16le entrelacé ; le premier paquet (configuration) porte le format
# en texte « rate=48000;channels=2;format=s16le;frames=480 ». Sur TCP les paquets se suivent (la longueur
# délimite) ; sur UDP un paquet = un datagramme. Tout paquet invalide (magie, version, longueur, CRC) est rejeté.
#
#   use multimedia.streaming.network_stream as ns
#   b := ns.encode(ns.StreamPacket(7, charge, 3360))
#   p := ns.decode(b)                     # StreamPacket, ou CorruptDataError
#   cfg := ns.config_packet(af.AudioFormat(48000, 2, "s16le"), 480)

from core use len, to_int
from collections use append
use string as _s
use office.compression as _z
use audio.audio_format as _af
use multimedia.core.errors as merr
use multimedia.streaming.buffering as jb

const MAGIC := [65, 77, 83, 49]
const VERSION := 1
const KEY := 1
const EOS := 2
const CONFIG := 4
const MAX_PAYLOAD := 1048576

func StreamPacket(seq, payload, timestamp=0, flags=0):
    return jb.StreamPacket(seq, payload, timestamp, flags)

func _u32(v):
    return [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]

func _r32(b, at):
    return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]

func encode(p):
    data := p.payload if p.payload != null else []
    if len(data) > MAX_PAYLOAD:
        merr.fail(merr.LIMIT, "charge utile de " + str(len(data)) + " octets")
    ts := p.timestamp
    out := MAGIC + [VERSION, p.flags & 255] + _u32(p.seq) + _u32((ts >> 32) & 0xFFFFFFFF) + _u32(ts & 0xFFFFFFFF) + _u32(len(data)) + data
    return out + _u32(_z.crc32(out))

const HEADER := 22

# Longueur totale du paquet qui commence en b[0] (en-tête lu), ou -1 s'il manque des octets.
func packet_length(b, at=0):
    if len(b) - at < HEADER:
        return -1
    return HEADER + _r32(b, at + 18) + 4

func decode(b, at=0):
    if len(b) - at < HEADER + 4:
        merr.corrupt("AMS", "paquet tronqué")
    for k in 0..4:
        if b[at + k] != MAGIC[k]:
            merr.corrupt("AMS", "magie absente")
    if b[at + 4] != VERSION:
        merr.corrupt("AMS", "version " + str(b[at + 4]) + " inconnue")
    n := _r32(b, at + 18)
    if n > MAX_PAYLOAD:
        merr.corrupt("AMS", "longueur déclarée " + str(n))
    end := at + HEADER + n
    if end + 4 > len(b):
        merr.corrupt("AMS", "paquet tronqué")
    body := [b[k] for k in at..end]
    if _z.crc32(body) != _r32(b, end):
        merr.corrupt("AMS", "CRC faux")
    ts := (_r32(b, at + 10) << 32) | _r32(b, at + 14)
    return jb.StreamPacket(_r32(b, at + 6), [b[k] for k in at + HEADER..end], ts, b[at + 5])

func config_packet(fmt, frames_per_packet):
    text := "rate=" + str(fmt.rate) + ";channels=" + str(fmt.channels) + ";format=s16le;frames=" + str(frames_per_packet)
    return jb.StreamPacket(0, _s.byte_unpack(text), 0, CONFIG | KEY)

func parse_config(p):
    out := {}
    for kv in _s.split(_s.byte_pack(p.payload), ";"):
        eq := _s.find(kv, "=")
        if eq > 0:
            out[_s.substring(kv, 0, eq)] = _s.substring(kv, eq + 1, len(kv))
    for k in ["rate", "channels", "frames"]:
        if not (k in out):
            merr.corrupt("AMS", "configuration incomplète (" + k + ")")
    return {"format": _af.AudioFormat(to_int(out["rate"]), to_int(out["channels"]), "s16le"), "frames": to_int(out["frames"])}

# Découpe un flux d'octets TCP en paquets ; renvoie [paquets, octets restants].
func split_stream(buf):
    out := []
    at := 0
    while true:
        n := packet_length(buf, at)
        if n < 0 or at + n > len(buf):
            break
        append(out, decode(buf, at))
        at += n
    return [out, [buf[k] for k in at..len(buf)]]
