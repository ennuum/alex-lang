# ALEX STANDARD LIBRARY — office.compression
# Compression sans perte : DEFLATE brut (RFC 1951), enveloppes zlib (RFC 1950) et gzip (RFC 1952), sommes CRC-32 et
# Adler-32. Le cœur DEFLATE est une primitive native (LZ77 à chaînes de hachage + Huffman dynamique, taux comparable
# à zlib) ; les enveloppes et contrôles sont écrits ici.
#
#   use office.compression as z
#   c := z.zlib_compress("texte très répétitif ...")     # octets
#   z.zlib_decompress(c)                                  # octets
#   z.decompress_text(z.gzip_compress("é"))               # "é"   (format détecté automatiquement)
#   z.crc32("123456789")                                  # 3421780262 (0xCBF43926)
#
# DONNÉES : toute fonction accepte une str (encodée en UTF-8) ou une liste d'octets, et renvoie des octets.
# NIVEAUX : 0 (aucune compression, blocs « stored ») à 9 (le plus compact) ; 6 par défaut.
# LIMITE : `limit` (octets) borne la taille décompressée — protection contre les « bombes » de décompression.
#   null = 1 Gio par défaut.
#
#   deflate(data, level=6)             inflate(data, limit=null)           inflate_partial(data, limit) -> [octets, lus]
#   zlib_compress(data, level=6)       zlib_decompress(data, limit=null)   (contrôle de l'en-tête et d'Adler-32)
#   gzip_compress(data, level=6, name=null, mtime=0)                       gzip_decompress(data, limit=null)
#                                      (plusieurs membres concaténés acceptés ; contrôle du CRC et de la taille)
#   compress(data, format="zlib", level=6)   decompress(data, format="auto", limit=null)
#                                      format : "raw" | "zlib" | "gzip" | "auto" (décompression : détection)
#   decompress_text(data, format="auto")      -> str (UTF-8)
#   detect(data) -> "gzip" | "zlib" | "zstd" | "raw"
#   zstd_decompress(data, limit=null, size=null)   Zstandard (RFC 8878 ; trames concaténées, sans dictionnaire),
#                                      décodeur natif ; size : taille attendue si les trames ne l'indiquent pas
#   zstd_decompress_buffer(buffer, offset, length, size) -> ffi.Buffer   (sans passer par une liste d'octets)
#   zstd_content_size(data) -> taille annoncée par les trames, ou -1
#   crc32(data, crc=0)   adler32(data, value=1)
# Erreurs : CompressionError (flux invalide, somme de contrôle fausse, limite dépassée) ; TypeError (argument).

use _native_office as _n
use _native_ffi as _nf
use ffi
use string as _str
from core use len, type
from collections use append
use office.errors as errors
use office.utils as u

const DEFAULT_LIMIT := 1073741824

func _data(data, fn):
    t := type(data)
    if t == "str":
        return _n.utf8_encode(data)
    if t == "list" or t == "tuple":
        return data
    raise("TypeError", "compression." + fn + " : str ou liste d'octets attendue (obtenu '" + t + "')")

func _limit(limit):
    if limit == null:
        return DEFAULT_LIMIT
    return limit

func _level(level, fn):
    if type(level) != "int" or level < 0 or level > 9:
        raise("ValueError", "compression." + fn + " : level doit être un entier de 0 à 9")
    return level

func crc32(data, crc=0):
    return _n.crc32(_data(data, "crc32"), crc)

func adler32(data, value=1):
    return _n.adler32(_data(data, "adler32"), value)

func deflate(data, level=6):
    return _n.deflate(_data(data, "deflate"), _level(level, "deflate"))

# Décompresse un flux DEFLATE brut et renvoie [octets, nombre d'octets d'entrée consommés].
func inflate_partial(data, limit=null):
    try:
        return _n.inflate(_data(data, "inflate"), _limit(limit))
    catch e:
        errors.rethrow(e, errors.COMPRESSION, "DEFLATE invalide")

func inflate(data, limit=null):
    return inflate_partial(data, limit)[0]

func zlib_compress(data, level=6):
    d := _data(data, "zlib_compress")
    lvl := _level(level, "zlib_compress")
    flevel := 2
    if lvl < 2:
        flevel = 0
    elif lvl < 6:
        flevel = 1
    elif lvl > 6:
        flevel = 3
    cmf := 120
    flg := flevel << 6
    flg = flg + (31 - ((cmf * 256 + flg) % 31))
    return u.concat([[cmf, flg], _n.deflate(d, lvl), u.pack_u32be(_n.adler32(d, 1))])

func zlib_decompress(data, limit=null):
    d := _data(data, "zlib_decompress")
    if len(d) < 6:
        errors.fail(errors.COMPRESSION, "zlib : flux trop court")
    cmf := d[0]
    flg := d[1]
    if (cmf & 15) != 8 or (cmf * 256 + flg) % 31 != 0:
        errors.fail(errors.COMPRESSION, "zlib : en-tête invalide")
    if (flg & 32) != 0:
        errors.fail(errors.COMPRESSION, "zlib : dictionnaire prédéfini non pris en charge")
    r := inflate_partial(_n.bytes_slice(d, 2, null), limit)
    out := r[0]
    end := 2 + r[1]
    if end + 4 <= len(d):
        if u.u32be(d, end) != _n.adler32(out, 1):
            errors.fail(errors.COMPRESSION, "zlib : somme Adler-32 incorrecte")
    return out

func gzip_compress(data, level=6, name=null, mtime=0):
    d := _data(data, "gzip_compress")
    lvl := _level(level, "gzip_compress")
    flags := 0
    head := [31, 139, 8]
    extra := []
    if name != null:
        flags = 8
        extra = u.concat([_n.latin1_encode(name, 63), [0]])
    xfl := 0
    if lvl >= 9:
        xfl = 2
    elif lvl <= 1:
        xfl = 4
    return u.concat([head, [flags], u.pack_u32le(mtime), [xfl, 255], extra, _n.deflate(d, lvl), u.pack_u32le(_n.crc32(d, 0)), u.pack_u32le(len(d) & 4294967295)])

func gzip_decompress(data, limit=null):
    d := _data(data, "gzip_decompress")
    parts := []
    pos := 0
    n := len(d)
    lim := _limit(limit)
    total := 0
    while pos < n:
        if pos + 18 > n or d[pos] != 31 or d[pos + 1] != 139:
            if len(parts) > 0:
                break
            errors.fail(errors.COMPRESSION, "gzip : signature absente")
        if d[pos + 2] != 8:
            errors.fail(errors.COMPRESSION, "gzip : méthode de compression inconnue")
        flg := d[pos + 3]
        p := pos + 10
        if (flg & 4) != 0:
            p = p + 2 + u.u16le(d, p)
        if (flg & 8) != 0:
            while p < n and d[p] != 0:
                p = p + 1
            p = p + 1
        if (flg & 16) != 0:
            while p < n and d[p] != 0:
                p = p + 1
            p = p + 1
        if (flg & 2) != 0:
            p = p + 2
        if p >= n:
            errors.fail(errors.COMPRESSION, "gzip : en-tête tronqué")
        r := inflate_partial(_n.bytes_slice(d, p, null), lim - total)
        out := r[0]
        q := p + r[1]
        if q + 8 > n:
            errors.fail(errors.COMPRESSION, "gzip : pied de membre tronqué")
        if u.u32le(d, q) != _n.crc32(out, 0):
            errors.fail(errors.COMPRESSION, "gzip : CRC-32 incorrect")
        if u.u32le(d, q + 4) != (len(out) & 4294967295):
            errors.fail(errors.COMPRESSION, "gzip : taille incorrecte")
        total = total + len(out)
        append(parts, out)
        pos = q + 8
    return u.concat(parts)

func detect(data):
    d := _data(data, "detect")
    if len(d) >= 4 and d[0] == 40 and d[1] == 181 and d[2] == 47 and d[3] == 253:
        return "zstd"
    if len(d) >= 2 and d[0] == 31 and d[1] == 139:
        return "gzip"
    if len(d) >= 2 and (d[0] & 15) == 8 and (d[0] >> 4) <= 7 and (d[0] * 256 + d[1]) % 31 == 0:
        return "zlib"
    return "raw"

func compress(data, format="zlib", level=6):
    if format == "zlib":
        return zlib_compress(data, level)
    if format == "gzip":
        return gzip_compress(data, level)
    if format == "raw" or format == "deflate":
        return deflate(data, level)
    raise("ValueError", "compression.compress : format inconnu '" + str(format) + "' (raw, zlib, gzip)")

func decompress(data, format="auto", limit=null):
    f := format
    if f == "auto":
        f = detect(data)
    if f == "zlib":
        return zlib_decompress(data, limit)
    if f == "gzip":
        return gzip_decompress(data, limit)
    if f == "raw" or f == "deflate":
        return inflate(data, limit)
    if f == "zstd":
        return zstd_decompress(data, limit)
    raise("ValueError", "compression.decompress : format inconnu '" + str(format) + "' (auto, raw, zlib, gzip, zstd)")

# ---------------------------------------------------------------------------------------------------------------------
# Zstandard
# ---------------------------------------------------------------------------------------------------------------------

# Taille du contenu annoncée par les trames zstd (somme), -1 si une trame ne l'indique pas.
func zstd_content_size(data):
    d := _data(data, "zstd_content_size")
    pos := 0
    total := 0
    n := len(d)
    while pos + 4 <= n:
        magic := d[pos] | (d[pos + 1] << 8) | (d[pos + 2] << 16) | (d[pos + 3] << 24)
        if (magic & 4294967280) == 407710288:
            if pos + 8 > n:
                return -1
            pos += 8 + (d[pos + 4] | (d[pos + 5] << 8) | (d[pos + 6] << 16) | (d[pos + 7] << 24))
            continue
        if magic != 4247762216 or pos + 5 > n:
            return -1
        fhd := d[pos + 4]
        fcsf := fhd >> 6
        single := (fhd >> 5) & 1
        dsz := [0, 1, 2, 4][fhd & 3]
        fsz := single if fcsf == 0 else (1 << fcsf)
        if fsz == 0:
            return -1
        o := pos + 5 + (1 - single) + dsz
        if o + fsz > n:
            return -1
        v := 0
        k := 0
        while k < fsz:
            v = v | (d[o + k] << (8 * k))
            k += 1
        if fsz == 2:
            v += 256
        total += v
        # parcourir les blocs jusqu'au dernier
        q := o + fsz
        while true:
            if q + 3 > n:
                return -1
            bh := d[q] | (d[q + 1] << 8) | (d[q + 2] << 16)
            bt := (bh >> 1) & 3
            q += 3 + (1 if bt == 1 else (bh >> 3))
            if (bh & 1) != 0:
                break
        if (fhd & 4) != 0:
            q += 4
        pos = q
    return total

# Décompresse length octets de buffer (ffi.Buffer) à partir de offset ; size = taille exacte attendue.
func zstd_decompress_buffer(buffer, offset, length, size):
    out := ffi.Buffer(size if size > 0 else 1)
    got := -1
    try:
        got = _nf.zstd_decompress(buffer._live(), offset, length, out._live(), size)
    catch e:
        out.free()
        errors.fail(errors.COMPRESSION, "zstd : " + str(e))
    if got != size:
        out.free()
        errors.fail(errors.COMPRESSION, "zstd : taille décompressée " + str(got) + " au lieu de " + str(size))
    return out

func zstd_decompress(data, limit=null, size=null):
    d := _data(data, "zstd_decompress")
    lim := _limit(limit)
    want := size if size != null else zstd_content_size(d)
    src := ffi.Buffer(len(d) if len(d) > 0 else 1)
    src.write_array("u8", d)
    cap := want if want >= 0 else len(d) * 8 + 65536
    while true:
        if cap > lim:
            src.free()
            errors.fail(errors.COMPRESSION, "zstd : limite de taille dépassée")
        out := ffi.Buffer(cap if cap > 0 else 1)
        got := -1
        msg := ""
        try:
            got = _nf.zstd_decompress(src._live(), 0, len(d), out._live(), cap)
        catch e:
            msg = str(e)
        if got >= 0:
            r := out.read_array("u8", got)
            out.free()
            src.free()
            return r
        out.free()
        if want >= 0 or not _str.contains(msg, "plus grande"):
            src.free()
            errors.fail(errors.COMPRESSION, "zstd : " + msg)
        cap = cap * 4

func decompress_text(data, format="auto", limit=null):
    return _n.utf8_decode(decompress(data, format, limit), false)
