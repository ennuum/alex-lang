# ALEX STANDARD LIBRARY — office.archive
# Archives ZIP (PKWARE APPNOTE) en lecture, écriture et modification : c'est le conteneur de DOCX, XLSX, PPTX, ODT,
# ODS, ODP, EPUB, JAR... Les entrées non modifiées sont recopiées compressées telles quelles (pas de recompression).
#
#   use office.archive as zip
#   a := zip.open("rapport.docx")
#   a.names()                                   # ["[Content_Types].xml", "_rels/.rels", "word/document.xml", ...]
#   xml := a.read_text("word/document.xml")
#   a.write_text("word/document.xml", xml)      # remplace l'entrée
#   a.save("rapport-modifie.docx")
#
#   b := zip.new()
#   b.write("mimetype", "application/vnd.oasis.opendocument.text", false)   # false : non compressé
#   b.write("data/image.png", octets)
#   octets_zip := b.to_bytes()
#
# LECTURE   open(path)  from_bytes(octets)  is_zip(octets_ou_chemin)
#   a.names()  a.contains(nom)  a.info(nom) -> ZipEntry  a.entries() -> [ZipEntry]  a.count()
#   a.read(nom) -> octets (CRC vérifié)   a.read_text(nom) -> str (UTF-8, BOM retiré)   a.read_or(nom, défaut)
#   a.find(prefixe, suffixe="") -> noms     a.comment
# ÉCRITURE  new()   a.write(nom, data, compress=true, level=6, modified=null)   a.write_text(nom, texte, ...)
#   a.remove(nom)  a.rename(ancien, nouveau)  a.to_bytes()  a.save(chemin)
#   a.add_file(chemin, nom=null)  a.add_dir(dossier, prefixe="")
# EXTRACTION a.extract(nom, chemin)   a.extract_all(dossier)  (refuse les noms absolus ou contenant « .. »)
#
# ZipEntry : name, size, compressed_size, method (0 stockée, 8 deflate), crc, modified (dict year..second),
#   is_dir, encrypted, comment, flags.
# Formats : ZIP et ZIP64 en lecture (tailles et décalages 64 bits) ; écriture ZIP classique (entrées < 4 Gio).
#   Noms UTF-8 (drapeau 11) ou CP437. Méthodes 0 et 8 ; les autres (bzip2, LZMA, Deflate64) et le chiffrement
#   lèvent UnsupportedError à la lecture de l'entrée concernée (l'archive reste lisible).
# Dates : `modified` est un dict {year, month, day, hour, minute, second} ; par défaut l'heure UTC courante.
#   a.fixed_time = {...} impose une date unique à toutes les nouvelles entrées (archives reproductibles).
# Erreurs : ArchiveError, UnsupportedError, CompressionError, IoError.

use _native_office as _n
from core use len, type, to_int
from collections use append, keys, contains_key
use string
use io
use os
use filesystem
use time
use office.errors as errors
use office.utils as u
use office.compression as compression

const _SIG_LOCAL := 67324752
const _SIG_CENTRAL := 33639248
const _SIG_EOCD := 101010256
const _SIG_EOCD64 := 101075792
const _SIG_LOC64 := 117853008
const _MAX32 := 4294967295

# CP437, octets 128..255 (noms d'entrées sans drapeau UTF-8).
const _CP437 := [199, 252, 233, 226, 228, 224, 229, 231, 234, 235, 232, 239, 238, 236, 196, 197, 201, 230, 198, 244, 246, 242, 251, 249, 255, 214, 220, 162, 163, 165, 8359, 402, 225, 237, 243, 250, 241, 209, 170, 186, 191, 8976, 172, 189, 188, 161, 171, 187, 9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, 9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, 9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, 945, 223, 915, 960, 931, 963, 181, 964, 934, 920, 937, 948, 8734, 966, 949, 8745, 8801, 177, 8805, 8804, 8992, 8993, 247, 8776, 176, 8729, 183, 8730, 8319, 178, 9632, 160]

func _cp437_decode(b):
    out := []
    for x in b:
        if x < 128:
            append(out, str(string.chr(x)))
        else:
            append(out, str(string.chr(_CP437[x - 128])))
    return string.join("", out)

func _is_ascii(s):
    for c in s:
        if string.ord(c) > 127:
            return false
    return true

func _dos_to_dict(dtime, ddate):
    return {"year": 1980 + (ddate >> 9), "month": (ddate >> 5) & 15, "day": ddate & 31, "hour": dtime >> 11, "minute": (dtime >> 5) & 63, "second": (dtime & 31) * 2}

func _dict_to_dos(m):
    y := m["year"]
    if y < 1980:
        return [0, 33]
    if y > 2107:
        y = 2107
    dtime := (u.get(m, "hour", 0) << 11) | (u.get(m, "minute", 0) << 5) | (to_int(u.get(m, "second", 0)) // 2)
    ddate := ((y - 1980) << 9) | (m["month"] << 5) | m["day"]
    return [dtime, ddate]

func _norm_name(name):
    if type(name) != "str" or name == "":
        raise("ValueError", "archive : nom d'entrée non vide attendu")
    n := string.replace(name, "\\", "/")
    while string.starts_with(n, "/"):
        n = _n.str_slice(n, 1, null)
    if n == "":
        raise("ValueError", "archive : nom d'entrée invalide '" + name + "'")
    return n

class ZipEntry:
    func init(name):
        self.name = name
        self.size = 0
        self.compressed_size = 0
        self.method = 8
        self.crc = 0
        self.modified = {"year": 1980, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0}
        self.is_dir = string.ends_with(name, "/")
        self.encrypted = false
        self.comment = ""
        self.flags = 0
        self.external_attr = 0
        self.header_offset = 0

    func to_dict():
        return {"name": self.name, "size": self.size, "compressed_size": self.compressed_size, "method": self.method, "crc": self.crc, "modified": self.modified, "is_dir": self.is_dir, "encrypted": self.encrypted, "comment": self.comment}

class Archive:
    func init():
        self._recs = {}
        self._order = []
        self._source = null
        self.comment = ""
        self.fixed_time = null

    # ------------------------------------------------------------------ lecture

    func names():
        out := []
        for n in self._order:
            append(out, n)
        return out

    func count():
        return len(self._order)

    func contains(name):
        return contains_key(self._recs, string.replace(name, "\\", "/"))

    func info(name):
        n := string.replace(name, "\\", "/")
        if not contains_key(self._recs, n):
            errors.fail(errors.ARCHIVE, "entrée absente de l'archive : '" + name + "'")
        return self._recs[n]["entry"]

    func entries():
        out := []
        for n in self._order:
            append(out, self._recs[n]["entry"])
        return out

    # Noms commençant par `prefix` et finissant par `suffix`, dans l'ordre de l'archive.
    func find(prefix, suffix=""):
        out := []
        for n in self._order:
            if string.starts_with(n, prefix) and string.ends_with(n, suffix):
                append(out, n)
        return out

    func _raw_of(rec):
        if rec["raw"] != null:
            return rec["raw"]
        e := rec["entry"]
        src := self._source
        lh := e.header_offset
        if lh + 30 > len(src) or u.u32le(src, lh) != _SIG_LOCAL:
            errors.fail(errors.ARCHIVE, "en-tête local invalide pour '" + e.name + "'")
        start := lh + 30 + u.u16le(src, lh + 26) + u.u16le(src, lh + 28)
        if start + e.compressed_size > len(src):
            errors.fail(errors.ARCHIVE, "données tronquées pour '" + e.name + "'")
        raw := _n.bytes_slice(src, start, start + e.compressed_size)
        rec["raw"] = raw
        return raw

    func read(name):
        n := string.replace(name, "\\", "/")
        if not contains_key(self._recs, n):
            errors.fail(errors.ARCHIVE, "entrée absente de l'archive : '" + name + "'")
        rec := self._recs[n]
        if rec["data"] != null:
            return rec["data"]
        e := rec["entry"]
        if e.encrypted:
            errors.fail(errors.UNSUPPORTED, "entrée chiffrée non prise en charge : '" + name + "'")
        raw := self._raw_of(rec)
        data := null
        if e.method == 0:
            data = raw
        elif e.method == 8:
            data = compression.inflate(raw, e.size + 1024)
        else:
            errors.fail(errors.UNSUPPORTED, "méthode de compression " + str(e.method) + " non prise en charge pour '" + name + "'")
        if len(data) != e.size:
            errors.fail(errors.ARCHIVE, "taille incorrecte pour '" + name + "' (" + str(len(data)) + " au lieu de " + str(e.size) + ")")
        if _n.crc32(data, 0) != e.crc:
            errors.fail(errors.ARCHIVE, "CRC-32 incorrect pour '" + name + "' (archive corrompue)")
        return data

    func read_text(name):
        d := self.read(name)
        if len(d) >= 3 and d[0] == 239 and d[1] == 187 and d[2] == 191:
            return _n.utf8_decode(_n.bytes_slice(d, 3, null), false)
        return _n.utf8_decode(d, false)

    func read_or(name, fallback=null):
        if not self.contains(name):
            return fallback
        return self.read(name)

    func read_text_or(name, fallback=null):
        if not self.contains(name):
            return fallback
        return self.read_text(name)

    # ------------------------------------------------------------------ écriture

    func write(name, data, compress=true, level=6, modified=null):
        n := _norm_name(name)
        d := u.bytes_of(data)
        e := ZipEntry(n)
        e.size = len(d)
        e.method = 8 if compress else 0
        m := modified
        if m == null:
            m = self.fixed_time
        if m == null:
            m = time.gmtime()
        e.modified = {"year": m["year"], "month": m["month"], "day": m["day"], "hour": u.get(m, "hour", 0), "minute": u.get(m, "minute", 0), "second": to_int(u.get(m, "second", 0))}
        rec := {"entry": e, "data": d, "raw": null, "level": level, "compress": compress}
        if not contains_key(self._recs, n):
            append(self._order, n)
        self._recs[n] = rec
        return e

    func write_text(name, text, compress=true, level=6, modified=null):
        return self.write(name, _n.utf8_encode(text), compress, level, modified)

    func mkdir(name):
        n := _norm_name(name)
        if not string.ends_with(n, "/"):
            n = n + "/"
        return self.write(n, [], false)

    func remove(name):
        n := string.replace(name, "\\", "/")
        if not contains_key(self._recs, n):
            errors.fail(errors.ARCHIVE, "entrée absente de l'archive : '" + name + "'")
        new_order := []
        for x in self._order:
            if x != n:
                append(new_order, x)
        self._order = new_order
        rest := {}
        for k in keys(self._recs):
            if k != n:
                rest[k] = self._recs[k]
        self._recs = rest

    func rename(old, new_name):
        o := string.replace(old, "\\", "/")
        nn := _norm_name(new_name)
        if not contains_key(self._recs, o):
            errors.fail(errors.ARCHIVE, "entrée absente de l'archive : '" + old + "'")
        if contains_key(self._recs, nn):
            errors.fail(errors.ARCHIVE, "une entrée '" + nn + "' existe déjà")
        rec := self._recs[o]
        if rec["data"] == null:
            self._raw_of(rec)
        rec["entry"].name = nn
        rest := {}
        for k in keys(self._recs):
            if k == o:
                rest[nn] = rec
            else:
                rest[k] = self._recs[k]
        self._recs = rest
        order := []
        for x in self._order:
            if x == o:
                append(order, nn)
            else:
                append(order, x)
        self._order = order

    func add_file(path, name=null):
        n := name
        if n == null:
            n = os.basename(path)
        return self.write(n, io.read_bytes(path))

    # Ajoute récursivement le contenu d'un dossier (noms relatifs au dossier, préfixés par `prefix`).
    func add_dir(directory, prefix=""):
        for p in filesystem.find(directory, null, "file"):
            rel := string.replace(_n.str_slice(p, len(directory), null), "\\", "/")
            while string.starts_with(rel, "/"):
                rel = _n.str_slice(rel, 1, null)
            self.write(prefix + rel, io.read_bytes(p))

    # Sérialise l'archive.
    func to_bytes():
        parts := []
        central := []
        offset := 0
        for n in self._order:
            rec := self._recs[n]
            e := rec["entry"]
            name_b := _n.utf8_encode(e.name)
            flags := 0
            if not _is_ascii(e.name):
                flags = 2048
            payload := null
            if rec["data"] != null:
                d := rec["data"]
                e.crc = _n.crc32(d, 0)
                e.size = len(d)
                if rec["compress"] and len(d) > 0:
                    c := _n.deflate(d, rec["level"])
                    if len(c) < len(d):
                        payload = c
                        e.method = 8
                    else:
                        payload = d
                        e.method = 0
                else:
                    payload = d
                    e.method = 0
            else:
                payload = self._raw_of(rec)
                if e.encrypted:
                    flags = flags | 1
            e.compressed_size = len(payload)
            if e.size > _MAX32 or e.compressed_size > _MAX32 or offset > _MAX32:
                errors.fail(errors.ARCHIVE, "entrée trop grande pour le format ZIP classique : '" + e.name + "'")
            dos := _dict_to_dos(e.modified)
            version := 20 if e.method == 8 else 10
            local := u.concat([u.pack_u32le(_SIG_LOCAL), u.pack_u16le(version), u.pack_u16le(flags), u.pack_u16le(e.method), u.pack_u16le(dos[0]), u.pack_u16le(dos[1]), u.pack_u32le(e.crc), u.pack_u32le(e.compressed_size), u.pack_u32le(e.size), u.pack_u16le(len(name_b)), u.pack_u16le(0), name_b])
            append(parts, local)
            append(parts, payload)
            ext := e.external_attr
            if ext == 0:
                if e.is_dir:
                    ext = (16877 << 16) | 16
                else:
                    ext = 33188 << 16
            comment_b := _n.utf8_encode(e.comment)
            cd := u.concat([u.pack_u32le(_SIG_CENTRAL), u.pack_u16le(788), u.pack_u16le(version), u.pack_u16le(flags), u.pack_u16le(e.method), u.pack_u16le(dos[0]), u.pack_u16le(dos[1]), u.pack_u32le(e.crc), u.pack_u32le(e.compressed_size), u.pack_u32le(e.size), u.pack_u16le(len(name_b)), u.pack_u16le(0), u.pack_u16le(len(comment_b)), u.pack_u16le(0), u.pack_u16le(0), u.pack_u32le(ext), u.pack_u32le(offset), name_b, comment_b])
            append(central, cd)
            e.header_offset = offset
            offset = offset + len(local) + len(payload)
        cd_bytes := u.concat(central)
        count := len(self._order)
        if count > 65535:
            errors.fail(errors.ARCHIVE, "trop d'entrées pour le format ZIP classique (" + str(count) + ")")
        acomment := _n.utf8_encode(self.comment)
        eocd := u.concat([u.pack_u32le(_SIG_EOCD), u.pack_u16le(0), u.pack_u16le(0), u.pack_u16le(count), u.pack_u16le(count), u.pack_u32le(len(cd_bytes)), u.pack_u32le(offset), u.pack_u16le(len(acomment)), acomment])
        append(parts, cd_bytes)
        append(parts, eocd)
        return u.concat(parts)

    func save(path):
        io.write_bytes(path, self.to_bytes())

    # ------------------------------------------------------------------ extraction

    func extract(name, path):
        filesystem.ensure_parent(path)
        io.write_bytes(path, self.read(name))

    func extract_all(directory):
        filesystem.ensure_dir(directory)
        for n in self._order:
            if string.starts_with(n, "/") or string.contains(n, ":") or n == ".." or string.starts_with(n, "../") or string.contains(n, "/../") or string.ends_with(n, "/.."):
                errors.fail(errors.ARCHIVE, "nom d'entrée dangereux refusé : '" + n + "'")
            dest := os.join(directory, n)
            if string.ends_with(n, "/"):
                filesystem.ensure_dir(dest)
            else:
                self.extract(n, dest)

# ---------------------------------------------------------------------------------------------- analyse

func _parse(data):
    n := len(data)
    if n < 22:
        errors.fail(errors.ARCHIVE, "archive ZIP invalide : trop courte")
    # fin du répertoire central : cherchée depuis la fin (commentaire d'au plus 65535 octets)
    lo := n - 65557
    if lo < 0:
        lo = 0
    p := _n.bytes_rfind(data, [80, 75, 5, 6], n - 22)
    while p >= 0 and p >= lo:
        clen := u.u16le(data, p + 20)
        if p + 22 + clen <= n:
            break
        p = _n.bytes_rfind(data, [80, 75, 5, 6], p - 1)
    if p < 0 or p < lo:
        errors.fail(errors.ARCHIVE, "archive ZIP invalide : fin du répertoire central introuvable")
    count := u.u16le(data, p + 10)
    cd_size := u.u32le(data, p + 12)
    cd_off := u.u32le(data, p + 16)
    clen := u.u16le(data, p + 20)
    a := Archive()
    a._source = data
    a.comment = _n.utf8_decode(_n.bytes_slice(data, p + 22, p + 22 + clen), false)
    # ZIP64
    if p >= 20 and u.u32le(data, p - 20) == _SIG_LOC64:
        z64 := u.u64le(data, p - 12)
        if z64 + 56 <= n and u.u32le(data, z64) == _SIG_EOCD64:
            count = u.u64le(data, z64 + 32)
            cd_size = u.u64le(data, z64 + 40)
            cd_off = u.u64le(data, z64 + 48)
    # décalage global (données ajoutées avant l'archive, ex. exécutable auto-extractible)
    shift := 0
    if cd_off + cd_size <= p:
        shift = p - (cd_off + cd_size)
        if u.u32le(data, cd_off) == _SIG_CENTRAL:
            shift = 0
    q := cd_off + shift
    k := 0
    while k < count:
        if q + 46 > n or u.u32le(data, q) != _SIG_CENTRAL:
            errors.fail(errors.ARCHIVE, "répertoire central corrompu (entrée " + str(k) + ")")
        flags := u.u16le(data, q + 8)
        method := u.u16le(data, q + 10)
        dtime := u.u16le(data, q + 12)
        ddate := u.u16le(data, q + 14)
        crc := u.u32le(data, q + 16)
        csize := u.u32le(data, q + 20)
        usize := u.u32le(data, q + 24)
        nlen := u.u16le(data, q + 28)
        xlen := u.u16le(data, q + 30)
        mlen := u.u16le(data, q + 32)
        ext_attr := u.u32le(data, q + 38)
        lho := u.u32le(data, q + 42)
        raw_name := _n.bytes_slice(data, q + 46, q + 46 + nlen)
        name := ""
        if (flags & 2048) != 0:
            name = _n.utf8_decode(raw_name, false)
        else:
            name = _cp437_decode(raw_name)
        name = string.replace(name, "\\", "/")
        # champ extra ZIP64 (0x0001)
        xp := q + 46 + nlen
        xend := xp + xlen
        while xp + 4 <= xend:
            hid := u.u16le(data, xp)
            hsz := u.u16le(data, xp + 2)
            if hid == 1:
                r := xp + 4
                if usize == _MAX32 and r + 8 <= xp + 4 + hsz:
                    usize = u.u64le(data, r)
                    r = r + 8
                if csize == _MAX32 and r + 8 <= xp + 4 + hsz:
                    csize = u.u64le(data, r)
                    r = r + 8
                if lho == _MAX32 and r + 8 <= xp + 4 + hsz:
                    lho = u.u64le(data, r)
            xp = xp + 4 + hsz
        e := ZipEntry(name)
        e.flags = flags
        e.method = method
        e.crc = crc
        e.compressed_size = csize
        e.size = usize
        e.modified = _dos_to_dict(dtime, ddate)
        e.encrypted = (flags & 1) != 0
        e.external_attr = ext_attr
        e.header_offset = lho + shift
        e.comment = _n.utf8_decode(_n.bytes_slice(data, xend, xend + mlen), false)
        if not contains_key(a._recs, name):
            append(a._order, name)
        a._recs[name] = {"entry": e, "data": null, "raw": null, "level": 6, "compress": true}
        q = xend + mlen
        k = k + 1
    return a

func from_bytes(data):
    if type(data) != "list":
        raise("TypeError", "archive.from_bytes : liste d'octets attendue (obtenu '" + type(data) + "')")
    return _parse(data)

func open(path):
    if type(path) != "str":
        raise("TypeError", "archive.open : chemin (str) attendu")
    return _parse(io.read_bytes(path))

func new():
    return Archive()

# Vrai si les octets (ou le fichier) commencent par une signature ZIP.
func is_zip(data_or_path):
    d := data_or_path
    if type(d) == "str":
        if not io.file_exists(d):
            return false
        d = io.read_bytes(d, 0, 4)
    return len(d) >= 4 and d[0] == 80 and d[1] == 75 and (d[2] == 3 or d[2] == 5) and (d[3] == 4 or d[3] == 6)
