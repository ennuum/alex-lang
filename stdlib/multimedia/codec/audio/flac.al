# ALEX STANDARD LIBRARY — multimedia.codec.audio.flac
#
# Décodeur FLAC (Free Lossless Audio Codec, RFC 9639) écrit en ALEX pur, pour des données NON FIABLES :
#   - métadonnées : STREAMINFO, SEEKTABLE, VORBIS_COMMENT ; position de la première trame ;
#   - trames : synchronisation, en-tête complet (taille de bloc, fréquence, canaux, bits, numéro UTF-8),
#     CRC-8 de l'en-tête et CRC-16 de la trame VÉRIFIÉS ;
#   - sous-trames : constante, verbatim, prédicteur fixe (ordres 0 à 4), LPC (ordres 1 à 32), bits perdus
#     (« wasted bits ») ;
#   - résidus : Rice (paramètre 4 bits) et Rice2 (5 bits), partitions, partitions brutes (échappement) ;
#   - stéréo : indépendante, gauche/côté, côté/droite, milieu/côté ; 1 à 8 canaux, 4 à 32 bits ;
#   - contrôle MD5 du signal décodé (StreamDecoder.md5_ok).
# Sans perte : les entiers décodés sont exactement ceux de l'original.
#
#   use multimedia.codec.audio.flac as flac
#   info := flac.read_header(octets)          # {"rate", "channels", "bits", "samples", "md5", "first_frame", ...}
#   fr := flac.decode_frame(octets, position, info)   # [canaux (listes d'entiers), position suivante, en-tête]
#   tout := flac.decode(octets)               # {"info", "channels": [[...], ...]}  (petits fichiers)
#   ech := flac.to_float(tout["channels"], info["bits"])   # flottants entrelacés -1..1
#
# Erreurs : CorruptDataError (CRC faux, valeur réservée, données tronquées), LimitError, UnsupportedError.

from core use len, to_int
from collections use append
use string as _s
use crypto as _crypto
use multimedia.core.errors as merr
use multimedia.security.limits as lim
use multimedia.metadata.tags as tg

# ------------------------------------------------------------------------------------------- CRC
func _crc8_table():
    t := []
    for i in 0..256:
        c := i
        for k in 0..8:
            if (c & 128) != 0:
                c = ((c << 1) ^ 0x07) & 255
            else:
                c = (c << 1) & 255
        append(t, c)
    return t

func _crc16_table():
    t := []
    for i in 0..256:
        c := i << 8
        for k in 0..8:
            if (c & 0x8000) != 0:
                c = ((c << 1) ^ 0x8005) & 0xFFFF
            else:
                c = (c << 1) & 0xFFFF
        append(t, c)
    return t

CRC8 := _crc8_table()
CRC16 := _crc16_table()

func crc8(b, a, z):
    c := 0
    for k in a..z:
        c = CRC8[c ^ b[k]]
    return c

func crc16(b, a, z):
    c := 0
    for k in a..z:
        c = ((c << 8) & 0xFFFF) ^ CRC16[((c >> 8) ^ b[k]) & 255]
    return c

# ------------------------------------------------------------------------------------------- lecture de bits
class BitReader:
    func init(data, byte_pos, end=null):
        self.data = data
        self.pos = byte_pos * 8
        self.end = (end if end != null else len(data)) * 8

    func _need(n):
        if self.pos + n > self.end:
            merr.corrupt("FLAC", "trame tronquée (lecture au-delà des données)")

    func bits(n):
        if n == 0:
            return 0
        self._need(n)
        d := self.data
        p := self.pos
        out := 0
        left := n
        while left > 0:
            byte := d[p >> 3]
            avail := 8 - (p & 7)
            take := avail if avail < left else left
            out = (out << take) | ((byte >> (avail - take)) & ((1 << take) - 1))
            p += take
            left -= take
        self.pos = p
        return out

    func signed(n):
        if n == 0:
            return 0
        v := self.bits(n)
        if (v >> (n - 1)) != 0:
            return v - (1 << n)
        return v

    func bit():
        return self.bits(1)

    # Nombre de 0 avant le prochain 1 (le 1 est consommé).
    func unary():
        d := self.data
        p := self.pos
        count := 0
        while true:
            if p >= self.end:
                merr.corrupt("FLAC", "code unaire tronqué")
            off := p & 7
            byte := (d[p >> 3] << off) & 255
            if byte == 0:
                count += 8 - off
                p += 8 - off
                continue
            # position du premier 1 dans l'octet décalé
            k := 0
            while (byte & 128) == 0:
                byte = (byte << 1) & 255
                k += 1
            count += k
            p += k + 1
            if p > self.end:
                merr.corrupt("FLAC", "code unaire tronqué")
            self.pos = p
            return count

    func align():
        self.pos = ((self.pos + 7) >> 3) << 3

    func byte_pos():
        return self.pos >> 3

# ------------------------------------------------------------------------------------------- métadonnées
func _u24(b, at):
    return (b[at] << 16) | (b[at + 1] << 8) | b[at + 2]

func _u32le(b, at):
    return b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)

# Métadonnées depuis le début du fichier (au moins jusqu'à la première trame).
func read_header(b, limits=null):
    l := lim.of(limits)
    if len(b) < 42 or b[0] != 102 or b[1] != 76 or b[2] != 97 or b[3] != 67:
        merr.corrupt("FLAC", "signature fLaC absente")
    at := 4
    info := null
    seek := []
    tags := tg.Tags()
    while true:
        if at + 4 > len(b):
            merr.corrupt("FLAC", "métadonnées tronquées")
        hdr := b[at]
        last := (hdr & 128) != 0
        btype := hdr & 127
        size := _u24(b, at + 1)
        p := at + 4
        if p + size > len(b):
            merr.corrupt("FLAC", "bloc de métadonnées de " + str(size) + " octets au-delà des données")
        if btype == 127:
            merr.corrupt("FLAC", "type de bloc de métadonnées invalide")
        if btype == 0:
            if size != 34:
                merr.corrupt("FLAC", "STREAMINFO de " + str(size) + " octets")
            minb := (b[p] << 8) | b[p + 1]
            maxb := (b[p + 2] << 8) | b[p + 3]
            x := _u24(b, p + 10)
            rate := x >> 4
            channels := ((x >> 1) & 7) + 1
            bits := (((x & 1) << 4) | (b[p + 13] >> 4)) + 1
            total := ((b[p + 13] & 15) << 32) | (b[p + 14] << 24) | (b[p + 15] << 16) | (b[p + 16] << 8) | b[p + 17]
            md5 := ""
            hexd := "0123456789abcdef"
            for k in p + 18..p + 34:
                md5 = md5 + _s.substring(hexd, b[k] >> 4, (b[k] >> 4) + 1) + _s.substring(hexd, b[k] & 15, (b[k] & 15) + 1)
            if rate == 0:
                merr.corrupt("FLAC", "fréquence nulle")
            if bits < 4:
                merr.corrupt("FLAC", str(bits) + " bits par échantillon")
            if maxb == 0 or minb > maxb:
                merr.corrupt("FLAC", "tailles de bloc invalides " + str(minb) + " / " + str(maxb))
            l.check_audio(rate, channels)
            if total > 0:
                l.check("max_frames", total)
                l.check("max_duration", 1.0 * total / rate)
            info = {"rate": rate, "channels": channels, "bits": bits, "samples": total, "min_block": minb,
                    "max_block": maxb, "md5": md5}
        elif btype == 3:
            n := size // 18
            for i in 0..n:
                q := p + 18 * i
                sn := 0
                off := 0
                for k in 0..8:
                    sn = (sn << 8) | b[q + k]
                    off = (off << 8) | b[q + 8 + k]
                if b[q] != 255:              # point de réserve : 0xFFFFFFFFFFFFFFFF
                    append(seek, [sn, off])
        elif btype == 4:
            q := p
            end := p + size
            if q + 4 <= end:
                vl := _u32le(b, q)
                q += 4 + vl
                if q + 4 <= end:
                    n := _u32le(b, q)
                    q += 4
                    for i in 0..n:
                        if q + 4 > end:
                            break
                        cl := _u32le(b, q)
                        if q + 4 + cl > end:
                            break
                        kv := _s.byte_pack([b[k] for k in q + 4..q + 4 + cl])
                        eq := _s.find(kv, "=")
                        if eq > 0:
                            tags.set(_s.substring(kv, 0, eq), _s.substring(kv, eq + 1, len(kv)))
                        q += 4 + cl
        at = p + size
        if last:
            break
    if info == null:
        merr.corrupt("FLAC", "STREAMINFO absent")
    info["first_frame"] = at
    info["seektable"] = seek
    info["tags"] = tags
    return info

# ------------------------------------------------------------------------------------------- en-tête de trame
const BLOCK_SIZES := [0, 192, 576, 1152, 2304, 4608, -1, -2, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768]
const RATES := [0, 88200, 176400, 192000, 8000, 16000, 22050, 24000, 32000, 44100, 48000, 96000, -1, -2, -3, -4]
const SIZES := [0, 8, 12, -1, 16, 20, 24, 32]

# Vrai si un en-tête de trame valide (CRC-8 compris) commence à `at`.
func is_frame_start(b, at, info):
    if at + 6 > len(b) or b[at] != 255 or (b[at + 1] & 0xFE) != 0xF8:
        return false
    try:
        parse_frame_header(b, at, info)
        return true
    catch e:
        return false

# [en-tête (dict), position du premier bit des sous-trames].
func parse_frame_header(b, at, info):
    r := BitReader(b, at)
    if r.bits(15) != 0x7FFC:
        merr.corrupt("FLAC", "synchronisation de trame absente à la position " + str(at))
    variable := r.bit() == 1
    bs_code := r.bits(4)
    sr_code := r.bits(4)
    ch_code := r.bits(4)
    sz_code := r.bits(3)
    if r.bit() != 0:
        merr.corrupt("FLAC", "bit réservé non nul dans l'en-tête de trame")
    # numéro de trame ou d'échantillon, codé comme l'UTF-8 (jusqu'à 7 octets)
    first := r.bits(8)
    extra := 0
    num := first
    if (first & 0x80) != 0:
        if (first & 0xE0) == 0xC0:
            extra = 1
            num = first & 0x1F
        elif (first & 0xF0) == 0xE0:
            extra = 2
            num = first & 0x0F
        elif (first & 0xF8) == 0xF0:
            extra = 3
            num = first & 0x07
        elif (first & 0xFC) == 0xF8:
            extra = 4
            num = first & 0x03
        elif (first & 0xFE) == 0xFC:
            extra = 5
            num = first & 0x01
        elif first == 0xFE:
            extra = 6
            num = 0
        else:
            merr.corrupt("FLAC", "numéro de trame mal codé")
        for i in 0..extra:
            c := r.bits(8)
            if (c & 0xC0) != 0x80:
                merr.corrupt("FLAC", "numéro de trame mal codé")
            num = (num << 6) | (c & 0x3F)
    if bs_code == 0:
        merr.corrupt("FLAC", "code de taille de bloc réservé")
    block := BLOCK_SIZES[bs_code]
    if block == -1:
        block = r.bits(8) + 1
    elif block == -2:
        block = r.bits(16) + 1
    rate := RATES[sr_code]
    if rate == 0:
        rate = info["rate"]
    elif rate == -1:
        rate = r.bits(8) * 1000
    elif rate == -2:
        rate = r.bits(16)
    elif rate == -3:
        rate = r.bits(16) * 10
    elif rate == -4:
        merr.corrupt("FLAC", "code de fréquence invalide")
    if ch_code > 10:
        merr.corrupt("FLAC", "affectation des canaux réservée " + str(ch_code))
    channels := ch_code + 1 if ch_code < 8 else 2
    bits := SIZES[sz_code]
    if bits == 0:
        bits = info["bits"]
    elif bits == -1:
        merr.corrupt("FLAC", "code de taille d'échantillon réservé")
    if channels != info["channels"]:
        merr.corrupt("FLAC", "trame à " + str(channels) + " canaux dans un flux à " + str(info["channels"]))
    hend := r.byte_pos()
    if hend >= len(b):
        merr.corrupt("FLAC", "en-tête de trame tronqué")
    if crc8(b, at, hend) != b[hend]:
        merr.corrupt("FLAC", "CRC-8 faux pour l'en-tête de trame à la position " + str(at))
    if info["max_block"] > 0 and block > info["max_block"] and info["max_block"] >= 16:
        merr.corrupt("FLAC", "bloc de " + str(block) + " échantillons au-delà du maximum " + str(info["max_block"]))
    first_sample := num if variable else num * (info["min_block"] if info["min_block"] == info["max_block"] else block)
    return [{"block": block, "rate": rate, "channels": channels, "assignment": ch_code, "bits": bits,
             "variable": variable, "number": num, "first_sample": first_sample}, hend + 1]

# ------------------------------------------------------------------------------------------- sous-trames
func _residual(r, block, order, out):
    method := r.bits(2)
    if method > 1:
        merr.corrupt("FLAC", "méthode de codage du résidu réservée")
    pbits := 4 if method == 0 else 5
    escape := 15 if method == 0 else 31
    porder := r.bits(4)
    parts := 1 << porder
    if (block % parts) != 0 or (block >> porder) < order:
        merr.corrupt("FLAC", "ordre de partition " + str(porder) + " incompatible avec le bloc de " + str(block))
    psize := block >> porder
    for p in 0..parts:
        n := psize - order if p == 0 else psize
        k := r.bits(pbits)
        if k == escape:
            nb := r.bits(5)
            for i in 0..n:
                append(out, r.signed(nb))
        else:
            _rice(r, n, k, out)

# n valeurs Rice de paramètre k, lecture de bits « en ligne » (boucle chaude du décodeur : variables locales).
func _rice(r, n, k, out):
    d := r.data
    p := r.pos
    end := r.end
    mask := (1 << k) - 1
    for i in 0..n:
        # quotient unaire : zéros jusqu'au prochain 1
        q := 0
        while true:
            if p >= end:
                merr.corrupt("FLAC", "résidu tronqué")
            off := p & 7
            byte := (d[p >> 3] << off) & 255
            if byte == 0:
                q += 8 - off
                p += 8 - off
                continue
            while byte < 128:
                byte = byte << 1
                q += 1
                p += 1
            p += 1
            break
        # k bits de poids faible
        low := 0
        if k > 0:
            if p + k > end:
                merr.corrupt("FLAC", "résidu tronqué")
            left := k
            while left > 0:
                avail := 8 - (p & 7)
                take := avail if avail < left else left
                low = (low << take) | ((d[p >> 3] >> (avail - take)) & ((1 << take) - 1))
                p += take
                left -= take
        u := (q << k) | low
        append(out, (u >> 1) ^ -(u & 1))
    r.pos = p

func _subframe(r, block, bps):
    if r.bit() != 0:
        merr.corrupt("FLAC", "bit de remplissage de sous-trame non nul")
    kind := r.bits(6)
    wasted := 0
    if r.bit() == 1:
        wasted = r.unary() + 1
        if wasted >= bps:
            merr.corrupt("FLAC", "bits perdus " + str(wasted) + " pour " + str(bps) + " bits")
        bps = bps - wasted
    s := []
    if kind == 0:
        v := r.signed(bps)
        s = [v for i in 0..block]
    elif kind == 1:
        for i in 0..block:
            append(s, r.signed(bps))
    elif kind >= 8 and kind <= 12:
        order := kind - 8
        if order > block:
            merr.corrupt("FLAC", "ordre du prédicteur supérieur au bloc")
        for i in 0..order:
            append(s, r.signed(bps))
        res := []
        _residual(r, block, order, res)
        if order == 0:
            for x in res:
                append(s, x)
        elif order == 1:
            a := s[0]
            for x in res:
                a = x + a
                append(s, a)
        elif order == 2:
            for j in 0..len(res):
                i := j + 2
                append(s, res[j] + 2 * s[i - 1] - s[i - 2])
        elif order == 3:
            for j in 0..len(res):
                i := j + 3
                append(s, res[j] + 3 * s[i - 1] - 3 * s[i - 2] + s[i - 3])
        else:
            for j in 0..len(res):
                i := j + 4
                append(s, res[j] + 4 * s[i - 1] - 6 * s[i - 2] + 4 * s[i - 3] - s[i - 4])
    elif kind >= 32:
        order := kind - 31
        if order > block:
            merr.corrupt("FLAC", "ordre LPC supérieur au bloc")
        for i in 0..order:
            append(s, r.signed(bps))
        prec := r.bits(4) + 1
        if prec == 16:
            merr.corrupt("FLAC", "précision LPC invalide")
        shift := r.signed(5)
        if shift < 0:
            merr.corrupt("FLAC", "décalage LPC négatif")
        coefs := [r.signed(prec) for i in 0..order]
        res := []
        _residual(r, block, order, res)
        nres := len(res)
        # boucles déroulées pour les ordres courants (1 à 12) : chaque coefficient dans une variable locale
        if order == 1:
            c0 := coefs[0]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 0]) >> shift))
        elif order == 2:
            c0 := coefs[0]
            c1 := coefs[1]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 1] + c1 * s[j + 0]) >> shift))
        elif order == 3:
            c0 := coefs[0]
            c1 := coefs[1]
            c2 := coefs[2]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 2] + c1 * s[j + 1] + c2 * s[j + 0]) >> shift))
        elif order == 4:
            c0 := coefs[0]
            c1 := coefs[1]
            c2 := coefs[2]
            c3 := coefs[3]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 3] + c1 * s[j + 2] + c2 * s[j + 1] + c3 * s[j + 0]) >> shift))
        elif order == 5:
            c0 := coefs[0]
            c1 := coefs[1]
            c2 := coefs[2]
            c3 := coefs[3]
            c4 := coefs[4]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 4] + c1 * s[j + 3] + c2 * s[j + 2] + c3 * s[j + 1] + c4 * s[j + 0]) >> shift))
        elif order == 6:
            c0 := coefs[0]
            c1 := coefs[1]
            c2 := coefs[2]
            c3 := coefs[3]
            c4 := coefs[4]
            c5 := coefs[5]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 5] + c1 * s[j + 4] + c2 * s[j + 3] + c3 * s[j + 2] + c4 * s[j + 1] + c5 * s[j + 0]) >> shift))
        elif order == 7:
            c0 := coefs[0]
            c1 := coefs[1]
            c2 := coefs[2]
            c3 := coefs[3]
            c4 := coefs[4]
            c5 := coefs[5]
            c6 := coefs[6]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 6] + c1 * s[j + 5] + c2 * s[j + 4] + c3 * s[j + 3] + c4 * s[j + 2] + c5 * s[j + 1] + c6 * s[j + 0]) >> shift))
        elif order == 8:
            c0 := coefs[0]
            c1 := coefs[1]
            c2 := coefs[2]
            c3 := coefs[3]
            c4 := coefs[4]
            c5 := coefs[5]
            c6 := coefs[6]
            c7 := coefs[7]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 7] + c1 * s[j + 6] + c2 * s[j + 5] + c3 * s[j + 4] + c4 * s[j + 3] + c5 * s[j + 2] + c6 * s[j + 1] + c7 * s[j + 0]) >> shift))
        elif order == 9:
            c0 := coefs[0]
            c1 := coefs[1]
            c2 := coefs[2]
            c3 := coefs[3]
            c4 := coefs[4]
            c5 := coefs[5]
            c6 := coefs[6]
            c7 := coefs[7]
            c8 := coefs[8]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 8] + c1 * s[j + 7] + c2 * s[j + 6] + c3 * s[j + 5] + c4 * s[j + 4] + c5 * s[j + 3] + c6 * s[j + 2] + c7 * s[j + 1] + c8 * s[j + 0]) >> shift))
        elif order == 10:
            c0 := coefs[0]
            c1 := coefs[1]
            c2 := coefs[2]
            c3 := coefs[3]
            c4 := coefs[4]
            c5 := coefs[5]
            c6 := coefs[6]
            c7 := coefs[7]
            c8 := coefs[8]
            c9 := coefs[9]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 9] + c1 * s[j + 8] + c2 * s[j + 7] + c3 * s[j + 6] + c4 * s[j + 5] + c5 * s[j + 4] + c6 * s[j + 3] + c7 * s[j + 2] + c8 * s[j + 1] + c9 * s[j + 0]) >> shift))
        elif order == 11:
            c0 := coefs[0]
            c1 := coefs[1]
            c2 := coefs[2]
            c3 := coefs[3]
            c4 := coefs[4]
            c5 := coefs[5]
            c6 := coefs[6]
            c7 := coefs[7]
            c8 := coefs[8]
            c9 := coefs[9]
            c10 := coefs[10]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 10] + c1 * s[j + 9] + c2 * s[j + 8] + c3 * s[j + 7] + c4 * s[j + 6] + c5 * s[j + 5] + c6 * s[j + 4] + c7 * s[j + 3] + c8 * s[j + 2] + c9 * s[j + 1] + c10 * s[j + 0]) >> shift))
        elif order == 12:
            c0 := coefs[0]
            c1 := coefs[1]
            c2 := coefs[2]
            c3 := coefs[3]
            c4 := coefs[4]
            c5 := coefs[5]
            c6 := coefs[6]
            c7 := coefs[7]
            c8 := coefs[8]
            c9 := coefs[9]
            c10 := coefs[10]
            c11 := coefs[11]
            for j in 0..nres:
                append(s, res[j] + ((c0 * s[j + 11] + c1 * s[j + 10] + c2 * s[j + 9] + c3 * s[j + 8] + c4 * s[j + 7] + c5 * s[j + 6] + c6 * s[j + 5] + c7 * s[j + 4] + c8 * s[j + 3] + c9 * s[j + 2] + c10 * s[j + 1] + c11 * s[j + 0]) >> shift))
        else:
            for j in 0..nres:
                i := j + order
                acc := 0
                for c in 0..order:
                    acc += coefs[c] * s[i - 1 - c]
                append(s, res[j] + (acc >> shift))
    else:
        merr.corrupt("FLAC", "type de sous-trame réservé " + str(kind))
    if wasted > 0:
        s = [x << wasted for x in s]
    return s

# Décode la trame qui commence à `at` : [canaux (listes d'entiers), position de la trame suivante, en-tête].
func decode_frame(b, at, info):
    ph := parse_frame_header(b, at, info)
    h := ph[0]
    r := BitReader(b, ph[1])
    block := h["block"]
    bps := h["bits"]
    a := h["assignment"]
    chans := []
    for c in 0..h["channels"]:
        extra := 0
        if (a == 8 and c == 1) or (a == 9 and c == 0) or (a == 10 and c == 1):
            extra = 1
        append(chans, _subframe(r, block, bps + extra))
    r.align()
    end := r.byte_pos()
    if end + 2 > len(b):
        merr.corrupt("FLAC", "CRC-16 de trame manquant (fichier tronqué)")
    want := (b[end] << 8) | b[end + 1]
    if crc16(b, at, end) != want:
        merr.corrupt("FLAC", "CRC-16 faux pour la trame à la position " + str(at))
    if a == 8:
        l := chans[0]
        sd := chans[1]
        chans[1] = [l[i] - sd[i] for i in 0..block]
    elif a == 9:
        sd := chans[0]
        rr := chans[1]
        chans[0] = [sd[i] + rr[i] for i in 0..block]
    elif a == 10:
        m := chans[0]
        sd := chans[1]
        left := []
        right := []
        for i in 0..block:
            mm := (m[i] << 1) | (sd[i] & 1)
            append(left, (mm + sd[i]) >> 1)
            append(right, (mm - sd[i]) >> 1)
        chans[0] = left
        chans[1] = right
    return [chans, end + 2, h]

# Canaux d'entiers -> flottants entrelacés (-1..1).
func to_float(chans, bits):
    scale := 1.0 / (1 << (bits - 1))
    out := []
    n := len(chans[0])
    nc := len(chans)
    for i in 0..n:
        for c in 0..nc:
            append(out, chans[c][i] * scale)
    return out

# Octets petit-boutistes de l'échantillon (largeur arrondie à l'octet), comme le MD5 de STREAMINFO.
func _md5_update(acc, chans, bits):
    width := (bits + 7) // 8
    n := len(chans[0])
    for i in 0..n:
        for c in 0..len(chans):
            v := chans[c][i]
            for k in 0..width:
                append(acc, (v >> (8 * k)) & 255)

# Décodeur de flux : trames successives, compteur d'échantillons, contrôle MD5 (si demandé).
class StreamDecoder:
    func init(data, limits=null, check_md5=false):
        self.data = data
        self.info = read_header(data, limits)
        self.pos = self.info["first_frame"]
        self.sample = 0
        self.check_md5 = check_md5 and self.info["md5"] != "00000000000000000000000000000000"
        self._md5_bytes = []
        self.frames = 0

    func at_end():
        if self.info["samples"] > 0 and self.sample >= self.info["samples"]:
            return true
        return self.pos + 2 > len(self.data)

    # Trame suivante : [canaux, numéro du premier échantillon] ou null à la fin.
    func next():
        if self.at_end():
            return null
        r := decode_frame(self.data, self.pos, self.info)
        chans := r[0]
        h := r[2]
        first := self.sample
        n := len(chans[0])
        if self.info["samples"] > 0 and first + n > self.info["samples"]:
            n = self.info["samples"] - first
            chans = [[ch[i] for i in 0..n] for ch in chans]
        if self.check_md5:
            _md5_update(self._md5_bytes, chans, self.info["bits"])
        self.pos = r[1]
        self.sample = first + n
        self.frames += 1
        return [chans, first]

    # Repositionne sur la trame qui commence à `offset` (octets depuis la première trame), échantillon `sample`.
    func jump(offset, sample):
        self.pos = self.info["first_frame"] + offset
        self.sample = sample
        self.check_md5 = false

    func md5_ok():
        if not self.check_md5:
            return null
        return _crypto.md5(self._md5_bytes) == self.info["md5"]

# Décode tout un fichier en mémoire (petits fichiers, tests) : {"info", "channels"}.
func decode(data, limits=null, check_md5=true):
    d := StreamDecoder(data, limits, check_md5)
    chans := [[] for c in 0..d.info["channels"]]
    while true:
        f := d.next()
        if f == null:
            break
        for c in 0..len(chans):
            for x in f[0][c]:
                append(chans[c], x)
    ok := d.md5_ok()
    if ok == false:
        merr.corrupt("FLAC", "MD5 du signal décodé différent de celui de STREAMINFO")
    return {"info": d.info, "channels": chans, "md5_checked": ok == true}
