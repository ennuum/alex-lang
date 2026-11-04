# ALEX STANDARD LIBRARY — multimedia.container.metadata
#
# Étiquettes des conteneurs, lues sans décoder le contenu :
#   - RIFF / WAV : liste LIST/INFO (INAM, IART, ICMT...) — lecture et construction du bloc ;
#   - ID3v2.2 / 2.3 / 2.4 (MP3...) : cadres texte (TIT2, TPE1, TALB...) en ISO-8859-1, UTF-16 ou UTF-8,
#     désynchronisation, taille synchsafe ; ID3v1 (128 octets de fin) ;
#   - FLAC : STREAMINFO (fréquence, canaux, bits, nombre d'échantillons) et commentaires Vorbis.
# Les résultats sont des multimedia.metadata.tags.Tags.
#
#   use multimedia.container.metadata as cm
#   t := cm.read_riff_info(octets_du_bloc_LIST)
#   bloc := cm.build_riff_info(tags)             # octets « LIST....INFO... » prêts à écrire
#   id3 := cm.read_id3v2(octets)                 # [Tags, taille de l'étiquette] ou null
#   fl := cm.read_flac(octets)                   # {"rate", "channels", "bits", "samples", "tags"}
#
# Erreurs : CorruptDataError (tailles incohérentes).

from core use len
from collections use append, keys
use string as _s
use multimedia.core.errors as merr
use multimedia.security.validation as val
use multimedia.metadata.tags as tg

func _u32le(v):
    return [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]

# Contenu d'un bloc LIST (sans les 8 octets d'en-tête) commençant par « INFO ».
func read_riff_info(body):
    t := tg.Tags()
    r := val.Reader(body, "LIST/INFO")
    if len(body) < 4 or r.tag(0) != "INFO":
        return t
    at := 4
    while at + 8 <= len(body):
        id := r.tag(at)
        size := r.u32le(at + 4)
        if id == "" or at + 8 + size > len(body):
            break
        t.set(id, _latin_or_utf8([body[k] for k in at + 8..at + 8 + size]))
        at += 8 + size + size % 2
    return t

func build_riff_info(tags):
    fields := tags.to_format("riff")
    body := _s.byte_unpack("INFO")
    for k in keys(fields):
        v := _s.byte_unpack(fields[k]) + [0]
        body = body + _s.byte_unpack(k) + _u32le(len(v)) + v
        if len(v) % 2 == 1:
            body = body + [0]
    if len(body) == 4:
        return []
    return _s.byte_unpack("LIST") + _u32le(len(body)) + body

# Octets -> texte : UTF-8 s'il est valide, sinon ISO-8859-1.
func _latin_or_utf8(b):
    end := len(b)
    while end > 0 and b[end - 1] == 0:
        end -= 1
    bb := [b[k] for k in 0..end]
    if _valid_utf8(bb):
        return _s.byte_pack(bb)
    return _latin1(bb)

func _valid_utf8(b):
    i := 0
    while i < len(b):
        c := b[i]
        n := 0
        if c < 128:
            n = 0
        elif c >= 194 and c <= 223:
            n = 1
        elif c >= 224 and c <= 239:
            n = 2
        elif c >= 240 and c <= 244:
            n = 3
        else:
            return false
        if i + n >= len(b) and n > 0:
            return false
        for k in 1..n + 1:
            if b[i + k] < 128 or b[i + k] > 191:
                return false
        i += n + 1
    return true

func _utf8_of(cp):
    if cp < 128:
        return [cp]
    if cp < 2048:
        return [192 | (cp >> 6), 128 | (cp & 63)]
    if cp < 65536:
        return [224 | (cp >> 12), 128 | ((cp >> 6) & 63), 128 | (cp & 63)]
    return [240 | (cp >> 18), 128 | ((cp >> 12) & 63), 128 | ((cp >> 6) & 63), 128 | (cp & 63)]

func _latin1(b):
    out := []
    for c in b:
        for x in _utf8_of(c):
            append(out, x)
    return _s.byte_pack(out)

func _utf16(b, big):
    out := []
    i := 0
    while i + 1 < len(b):
        u := (b[i] << 8) | b[i + 1] if big else b[i] | (b[i + 1] << 8)
        i += 2
        if u == 0:
            break
        if u >= 0xD800 and u <= 0xDBFF and i + 1 < len(b):
            lo := (b[i] << 8) | b[i + 1] if big else b[i] | (b[i + 1] << 8)
            if lo >= 0xDC00 and lo <= 0xDFFF:
                i += 2
                u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)
        for x in _utf8_of(u):
            append(out, x)
    return _s.byte_pack(out)

func _id3_text(b):
    if len(b) == 0:
        return ""
    enc := b[0]
    data := [b[k] for k in 1..len(b)]
    if enc == 0:
        return _latin1([c for c in data if c != 0])
    if enc == 3:
        return _latin_or_utf8(data)
    if enc == 1 and len(data) >= 2:
        if data[0] == 0xFE and data[1] == 0xFF:
            return _utf16([data[k] for k in 2..len(data)], true)
        if data[0] == 0xFF and data[1] == 0xFE:
            return _utf16([data[k] for k in 2..len(data)], false)
        return _utf16(data, false)
    if enc == 2:
        return _utf16(data, true)
    return ""

func _synchsafe(r, at):
    return (r.u8(at) << 21) | (r.u8(at + 1) << 14) | (r.u8(at + 2) << 7) | r.u8(at + 3)

const ID3V22 := {"TT2": "TIT2", "TP1": "TPE1", "TAL": "TALB", "TP2": "TPE2", "TYE": "TYER", "TCO": "TCON",
    "TRK": "TRCK", "TPA": "TPOS", "TCM": "TCOM", "TCR": "TCOP", "TSS": "TSSE", "COM": "COMM"}

# [Tags, taille totale de l'étiquette] si les données commencent par « ID3 », sinon null.
func read_id3v2(b):
    if len(b) < 10 or b[0] != 73 or b[1] != 68 or b[2] != 51:
        return null
    r := val.Reader(b, "ID3v2")
    ver := b[3]
    flags := b[5]
    size := _synchsafe(r, 6)
    total := 10 + size + (10 if (flags & 16) != 0 else 0)
    if ver < 2 or ver > 4:
        merr.corrupt("ID3v2", "version 2." + str(ver) + " inconnue")
    end := 10 + size
    if end > len(b):
        end = len(b)
    body := [b[k] for k in 10..end]
    if (flags & 128) != 0 and ver < 4:
        # désynchronisation : FF 00 -> FF
        un := []
        k := 0
        while k < len(body):
            append(un, body[k])
            if body[k] == 255 and k + 1 < len(body) and body[k + 1] == 0:
                k += 1
            k += 1
        body = un
    br := val.Reader(body, "ID3v2")
    t := tg.Tags()
    at := 0
    if (flags & 64) != 0 and ver >= 3 and len(body) >= 4:
        ext := _synchsafe(br, 0) if ver == 4 else br.u32be(0) + 4
        at = ext
    hl := 6 if ver == 2 else 10
    while at + hl <= len(body):
        if body[at] == 0:
            break
        id := br.tag(at, 3 if ver == 2 else 4)
        fsize := 0
        if ver == 2:
            fsize = (body[at + 3] << 16) | (body[at + 4] << 8) | body[at + 5]
        elif ver == 3:
            fsize = br.u32be(at + 4)
        else:
            fsize = _synchsafe(br, at + 4)
        if id == "" or fsize <= 0 or at + hl + fsize > len(body):
            break
        data := [body[k] for k in at + hl..at + hl + fsize]
        if ver == 2 and id in ID3V22:
            id = ID3V22[id]
        if len(id) == 4 and _s.starts_with(id, "T") and id != "TXXX":
            t.set(id, _id3_text(data))
        elif id == "COMM" and len(data) > 4:
            # encodage, langue (3), description terminée par 0, texte
            enc := data[0]
            rest := [data[k] for k in 4..len(data)]
            z := 0
            step := 2 if enc == 1 or enc == 2 else 1
            while z + step <= len(rest):
                if rest[z] == 0 and (step == 1 or rest[z + 1] == 0):
                    break
                z += step
            t.set("comment", _id3_text([enc] + [rest[k] for k in z + step..len(rest)]))
        at += hl + fsize
    return [t, total]

func _field(b, a, z):
    return _latin1([b[k] for k in a..z if b[k] != 0])

# ID3v1 : 128 derniers octets « TAG... ».
func read_id3v1(tail):
    if len(tail) < 128:
        return null
    o := len(tail) - 128
    if tail[o] != 84 or tail[o + 1] != 65 or tail[o + 2] != 71:
        return null
    t := tg.Tags()
    t.set("title", _field(tail, o + 3, o + 33))
    t.set("artist", _field(tail, o + 33, o + 63))
    t.set("album", _field(tail, o + 63, o + 93))
    t.set("date", _field(tail, o + 93, o + 97))
    if tail[o + 125] == 0 and tail[o + 126] != 0:
        t.set("track", str(tail[o + 126]))
    return t

# FLAC : {"rate", "channels", "bits", "samples", "duration", "tags"}.
func read_flac(b):
    r := val.Reader(b, "FLAC")
    if r.tag(0) != "fLaC":
        merr.corrupt("FLAC", "signature fLaC absente")
    at := 4
    info := null
    t := tg.Tags()
    while at + 4 <= len(b):
        hdr := r.u8(at)
        last := (hdr & 128) != 0
        btype := hdr & 127
        size := (r.u8(at + 1) << 16) | (r.u8(at + 2) << 8) | r.u8(at + 3)
        val.check_chunk(at + 4, size, len(b), "bloc de métadonnées FLAC")
        p := at + 4
        if btype == 0:
            if size < 34:
                merr.corrupt("FLAC", "STREAMINFO trop court")
            x := (r.u8(p + 10) << 16) | (r.u8(p + 11) << 8) | r.u8(p + 12)
            rate := x >> 4
            channels := ((x >> 1) & 7) + 1
            bits := (((x & 1) << 4) | (r.u8(p + 13) >> 4)) + 1
            samples := ((r.u8(p + 13) & 15) << 32) | r.u32be(p + 14)
            info = {"rate": rate, "channels": channels, "bits": bits, "samples": samples,
                    "duration": (1.0 * samples / rate) if rate > 0 and samples > 0 else null}
        elif btype == 4:
            q := p
            vlen := r.u32le(q)
            q += 4 + vlen
            n := r.u32le(q)
            q += 4
            for i in 0..n:
                if q + 4 > p + size:
                    break
                clen := r.u32le(q)
                if q + 4 + clen > p + size:
                    break
                kv := _s.byte_pack(r.bytes(q + 4, clen))
                eq := _s.find(kv, "=")
                if eq > 0:
                    t.set(_s.substring(kv, 0, eq), _s.substring(kv, eq + 1, len(kv)))
                q += 4 + clen
        at += 4 + size
        if last:
            break
    if info == null:
        merr.corrupt("FLAC", "STREAMINFO absent")
    info["tags"] = t
    return info
