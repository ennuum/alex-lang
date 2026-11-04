# ALEX STANDARD LIBRARY — office.pdf_reader
# Lecture des fichiers PDF (1.0 à 2.0) : objets, table de références croisées (classique, flux XRef, hybride,
# mises à jour incrémentales), flux d'objets, filtres (FlateDecode, LZWDecode, ASCIIHexDecode, ASCII85Decode,
# RunLengthDecode, prédicteurs PNG / TIFF), chiffrement standard (RC4 40 à 128 bits, AES-128, AES-256 ; mot de
# passe utilisateur ou propriétaire), arbre des pages avec héritage, informations, XMP, signets, pièces jointes.
# Un fichier abîmé (table XRef fausse ou absente) est reconstruit en parcourant les objets.
#
#   use office.pdf_reader as reader
#   doc := reader.open("rapport.pdf")              # reader.open(chemin, "motdepasse") pour un PDF protégé
#   doc.page_count()
#   p := doc.page(0)                               # Page : boîtes, rotation, ressources, contenu
#   p.width()  p.height()  p.rotation()
#   doc.info()                                     # {"Title": "...", "Author": "...", ...}
#   doc.outlines()                                 # [{"title", "page", "level"}]
#
# MODÈLE DES OBJETS
#   nombre -> int / float ; booléen ; null ; nom -> str commençant par « / » ("/Page") ; chaîne -> PdfString
#   (octets ; .text() décode UTF-16BE / UTF-8 / PDFDocEncoding) ; tableau -> list ; dictionnaire -> dict dont les
#   clés sont les noms SANS « / » (d["Type"] == "/Page") ; référence -> Ref(num, gen) ; flux -> Stream (dict, raw).
#   is_name(v)  name_of(v) ("/Page" -> "Page")  is_ref(v)
# PdfFile : version  trailer  catalog  encrypted  get(v) (résout une référence)  object(num, gen=0)
#   decode(stream) -> octets   stream_dict(v)   page_count()  page(i) -> Page   pages() -> [Page]
#   info() -> dict de textes   xmp() -> texte XMP ou null   outlines()   attachments() -> [{"name", "data"}]
#   page_index(ref) -> indice   objects() -> numéros d'objets   named_destinations()
# Page : doc ref dict index  media_box() crop_box() -> [x0, y0, x1, y1]  width() height() (boîte visible, rotation
#   comprise)  rotation()  resources()  contents() -> octets (flux de contenu concaténés)  annotations() -> dicts
#   links() -> [{"rect", "uri" | "page"}]
# Fonctions : open(chemin_ou_octets, password="")  from_bytes(octets, password="")  parse_value(tokens, i)
#   tokens(data, start, end) (jetons natifs)  decode_text(octets) (texte de chaîne PDF)  PDF_DOC_ENCODING
# Erreurs : PDFError (fichier illisible), UnsupportedError (filtre ou chiffrement non pris en charge),
#   PDFError « mot de passe incorrect ».

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use office.errors as errors
use office.utils as u
use office.compression as compression

# ---------------------------------------------------------------------------------------------- objets

class Ref:
    func init(num, gen=0):
        self.num = num
        self.gen = gen

    func key():
        return self.num * 65536 + self.gen

    func __str__():
        return str(self.num) + " " + str(self.gen) + " R"

class PdfString:
    func init(data, hexa=false):
        self.data = data
        self.hex = hexa

    func text():
        return decode_text(self.data)

    func __str__():
        return self.text()

class Stream:
    func init(d, raw, num=0, gen=0):
        self.dict = d
        self.raw = raw
        self.num = num
        self.gen = gen
        self.decrypted = false

func is_name(v):
    return type(v) == "str" and string.starts_with(v, "/")

func name_of(v):
    if is_name(v):
        return _n.str_slice(v, 1, null)
    return null

func is_ref(v):
    return isinstance(v, Ref)

func is_stream(v):
    return isinstance(v, Stream)

func is_string(v):
    return isinstance(v, PdfString)

# PDFDocEncoding : octets 0x18..0x1F et 0x80..0xAD diffèrent de Latin-1.
const PDF_DOC_ENCODING := {24: 728, 25: 711, 26: 710, 27: 729, 28: 733, 29: 731, 30: 730, 31: 732, 128: 8226, 129: 8224, 130: 8225, 131: 8230, 132: 8212, 133: 8211, 134: 402, 135: 8260, 136: 8249, 137: 8250, 138: 8722, 139: 8240, 140: 8222, 141: 8220, 142: 8221, 143: 8216, 144: 8217, 145: 8218, 146: 8482, 147: 64257, 148: 64258, 149: 321, 150: 338, 151: 352, 152: 376, 153: 381, 154: 305, 155: 322, 156: 339, 157: 353, 158: 382, 160: 8364}

func decode_text(b):
    n := len(b)
    if n >= 2 and b[0] == 254 and b[1] == 255:
        return u.utf16_decode(_n.bytes_slice(b, 2, null), true)
    if n >= 2 and b[0] == 255 and b[1] == 254:
        return u.utf16_decode(_n.bytes_slice(b, 2, null), false)
    if n >= 3 and b[0] == 239 and b[1] == 187 and b[2] == 191:
        return _n.utf8_decode(_n.bytes_slice(b, 3, null), false)
    special := false
    for x in b:
        if (x >= 24 and x <= 31) or (x >= 128 and x <= 160):
            special = true
            break
    if not special:
        return _n.latin1_decode(b)
    out := []
    for x in b:
        if contains_key(PDF_DOC_ENCODING, x):
            append(out, str(string.chr(PDF_DOC_ENCODING[x])))
        else:
            append(out, str(string.chr(x)))
    return string.join("", out)

# ---------------------------------------------------------------------------------------------- jetons -> valeurs

func tokens(data, start=0, end=null, stop_obj=false, max_tokens=null):
    return _n.pdf_tokens(data, start, end, stop_obj, max_tokens)

# Analyse une valeur à partir du jeton i ; renvoie [valeur, i_suivant]. Les mots-clés inconnus (opérateurs de
# contenu) sont renvoyés sous la forme {"op": nom}.
func parse_value(toks, i):
    t := toks[i]
    k := t[0]
    if k == "n":
        # référence « n g R » ?
        if i + 2 < len(toks) and toks[i + 1][0] == "n" and toks[i + 2][0] == "k" and toks[i + 2][1] == "R" and type(t[1]) == "int" and type(toks[i + 1][1]) == "int":
            return [Ref(t[1], toks[i + 1][1]), i + 3]
        return [t[1], i + 1]
    if k == "/":
        return ["/" + t[1], i + 1]
    if k == "s":
        return [PdfString(t[1], false), i + 1]
    if k == "x":
        return [PdfString(t[1], true), i + 1]
    if k == "[":
        arr := []
        j := i + 1
        while j < len(toks) and toks[j][0] != "]":
            r := parse_value(toks, j)
            append(arr, r[0])
            j = r[1]
        return [arr, j + 1]
    if k == "<<":
        d := {}
        j := i + 1
        while j < len(toks) and toks[j][0] != ">>":
            kt := toks[j]
            if kt[0] != "/":
                j = j + 1
                continue
            if j + 1 >= len(toks) or toks[j + 1][0] == ">>":
                d[kt[1]] = null
                j = j + 1
                continue
            r := parse_value(toks, j + 1)
            d[kt[1]] = r[0]
            j = r[1]
        return [d, j + 1]
    if k == "k":
        w := t[1]
        if w == "true":
            return [true, i + 1]
        if w == "false":
            return [false, i + 1]
        if w == "null":
            return [null, i + 1]
        return [{"op": w}, i + 1]
    if k == "i":
        return [{"inline_data": t[1]}, i + 1]
    # délimiteur orphelin
    return [null, i + 1]

# ---------------------------------------------------------------------------------------------- filtres

func _predict(data, params):
    if params == null or type(params) != "dict":
        return data
    pred := u.get(params, "Predictor", 1)
    if pred == 1:
        return data
    colors := u.get(params, "Colors", 1)
    bpc := u.get(params, "BitsPerComponent", 8)
    columns := u.get(params, "Columns", 1)
    bpp := (colors * bpc + 7) // 8
    stride := (columns * colors * bpc + 7) // 8
    if pred == 2:
        if bpc != 8:
            return data
        out := []
        n := len(data)
        i := 0
        while i < n:
            if (i % stride) >= bpp:
                append(out, (data[i] + out[i - bpp]) & 255)
            else:
                append(out, data[i])
            i = i + 1
        return out
    # PNG (10..15) : un octet de filtre par ligne
    out := []
    prior := _n.bytes_fill(stride, 0)
    n := len(data)
    pos := 0
    while pos < n:
        ft := data[pos]
        pos = pos + 1
        row := _n.bytes_slice(data, pos, pos + stride)
        pos = pos + stride
        while len(row) < stride:
            append(row, 0)
        x := 0
        while x < stride:
            a := row[x - bpp] if x >= bpp else 0
            b := prior[x]
            v := row[x]
            if ft == 1:
                v = v + a
            elif ft == 2:
                v = v + b
            elif ft == 3:
                v = v + (a + b) // 2
            elif ft == 4:
                c := prior[x - bpp] if x >= bpp else 0
                p := a + b - c
                pa := p - a if p >= a else a - p
                pb := p - b if p >= b else b - p
                pc := p - c if p >= c else c - p
                if pa <= pb and pa <= pc:
                    v = v + a
                elif pb <= pc:
                    v = v + b
                else:
                    v = v + c
            row[x] = v & 255
            x = x + 1
        for v in row:
            append(out, v)
        prior = row
    return out

func _ascii85(data):
    out := []
    group := []
    for b in data:
        if b == 126:
            break
        if b == 122 and len(group) == 0:
            append(out, 0)
            append(out, 0)
            append(out, 0)
            append(out, 0)
            continue
        if b < 33 or b > 117:
            continue
        append(group, b - 33)
        if len(group) == 5:
            v := (((group[0] * 85 + group[1]) * 85 + group[2]) * 85 + group[3]) * 85 + group[4]
            append(out, (v >> 24) & 255)
            append(out, (v >> 16) & 255)
            append(out, (v >> 8) & 255)
            append(out, v & 255)
            group = []
    if len(group) > 1:
        m := len(group)
        while len(group) < 5:
            append(group, 84)
        v := (((group[0] * 85 + group[1]) * 85 + group[2]) * 85 + group[3]) * 85 + group[4]
        bs := [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]
        k := 0
        while k < m - 1:
            append(out, bs[k])
            k = k + 1
    return out

func _runlength(data):
    out := []
    i := 0
    n := len(data)
    while i < n:
        l := data[i]
        if l == 128:
            break
        if l < 128:
            k := 0
            while k <= l and i + 1 + k < n:
                append(out, data[i + 1 + k])
                k = k + 1
            i = i + l + 2
        else:
            if i + 1 < n:
                k := 0
                while k < 257 - l:
                    append(out, data[i + 1])
                    k = k + 1
            i = i + 2
    return out

func _flate(data):
    if len(data) == 0:
        return data
    # zlib (en-tête 2 octets) le plus souvent ; tolère un flux brut, une somme Adler fausse ou un flux tronqué
    if len(data) >= 2 and (data[0] & 15) == 8 and (data[0] * 256 + data[1]) % 31 == 0:
        try:
            return compression.inflate_partial(_n.bytes_slice(data, 2, null))[0]
        catch e:
            null
    try:
        return compression.inflate_partial(data)[0]
    catch e:
        errors.fail(errors.PDF, "flux FlateDecode corrompu")

const IMAGE_FILTERS := ["DCTDecode", "JPXDecode", "CCITTFaxDecode", "JBIG2Decode", "DCT", "CCF"]

# Applique la chaîne de filtres. stop_at_image : s'arrête avant un filtre d'image (renvoie [octets, filtre]).
func apply_filters(data, filters, params, stop_at_image=false):
    fs := filters
    ps := params
    if fs == null:
        return [data, null]
    if type(fs) != "list":
        fs = [fs]
    if type(ps) != "list":
        ps = [ps]
    out := data
    i := 0
    for f in fs:
        nm := name_of(f) if is_name(f) else u.to_text(f)
        p := ps[i] if i < len(ps) else null
        if nm == "FlateDecode" or nm == "Fl":
            out = _predict(_flate(out), p)
        elif nm == "LZWDecode" or nm == "LZW":
            early := u.get(p, "EarlyChange", 1) if type(p) == "dict" else 1
            out = _predict(_n.lzw_decode(out, early), p)
        elif nm == "ASCIIHexDecode" or nm == "AHx":
            k := _n.bytes_find(out, [62], 0)
            out = _n.hex_decode(_n.latin1_decode(out if k < 0 else _n.bytes_slice(out, 0, k)))
        elif nm == "ASCII85Decode" or nm == "A85":
            src := out
            if len(src) >= 2 and src[0] == 60 and src[1] == 126:
                src = _n.bytes_slice(src, 2, null)
            out = _ascii85(src)
        elif nm == "RunLengthDecode" or nm == "RL":
            out = _runlength(out)
        elif nm == "Crypt":
            out = out
        else:
            ok := false
            for img in IMAGE_FILTERS:
                if img == nm:
                    ok = true
            if ok:
                return [out, nm]
            errors.fail(errors.UNSUPPORTED, "filtre PDF non pris en charge : " + nm)
        i = i + 1
    return [out, null]

# ---------------------------------------------------------------------------------------------- chiffrement

const _PAD := [40, 191, 78, 94, 78, 117, 138, 65, 100, 0, 78, 86, 255, 250, 1, 8, 46, 46, 0, 182, 208, 104, 62, 128, 47, 12, 169, 254, 100, 83, 105, 122]

func _str_bytes(v):
    if isinstance(v, PdfString):
        return v.data
    return []

func _pad_pw(pw):
    b := u.cp1252_encode(pw, 63) if type(pw) == "str" else pw
    out := _n.bytes_slice(b, 0, 32)
    k := 0
    while len(out) < 32:
        append(out, _PAD[k])
        k = k + 1
    return out

class _Security:
    func init(enc, id0):
        self.v = u.get(enc, "V", 0)
        self.r = u.get(enc, "R", 2)
        self.o = _str_bytes(u.get(enc, "O", null))
        self.u = _str_bytes(u.get(enc, "U", null))
        self.oe = _str_bytes(u.get(enc, "OE", null))
        self.ue = _str_bytes(u.get(enc, "UE", null))
        self.p = u.get(enc, "P", 0)
        self.length = u.get(enc, "Length", 40)
        self.id0 = id0
        self.encrypt_metadata = u.get(enc, "EncryptMetadata", true)
        self.aes = false
        self.key = null
        self.stm_identity = false
        self.str_identity = false
        if self.v >= 4:
            cf := u.get(enc, "CF", {})
            stmf := name_of(u.get(enc, "StmF", "/Identity"))
            strf := name_of(u.get(enc, "StrF", "/Identity"))
            self.stm_identity = stmf == "Identity"
            self.str_identity = strf == "Identity"
            f := u.get(cf, stmf if not self.stm_identity else strf, {})
            cfm := name_of(u.get(f, "CFM", "/V2"))
            self.aes = cfm == "AESV2" or cfm == "AESV3"
            if u.get(f, "Length", null) != null and self.v == 4:
                l := u.get(f, "Length", 16)
                self.length = l * 8 if l <= 32 else l
        if self.v < 2:
            self.length = 40
        if self.v == 4 and self.length < 128:
            self.length = 128

    func _p_bytes():
        p := self.p
        if p < 0:
            p = p + 4294967296
        return u.pack_u32le(p)

    func _key_r4(pw):
        n := self.length // 8 if self.r >= 3 else 5
        data := u.concat([_pad_pw(pw), self.o, self._p_bytes(), self.id0])
        if self.r >= 4 and not self.encrypt_metadata:
            data = u.concat([data, [255, 255, 255, 255]])
        h := _n.md5(data)
        if self.r >= 3:
            k := 0
            while k < 50:
                h = _n.md5(_n.bytes_slice(h, 0, n))
                k = k + 1
        return _n.bytes_slice(h, 0, n)

    func _check_user_r4(key):
        if self.r == 2:
            return _n.rc4(key, _PAD) == _n.bytes_slice(self.u, 0, 32)
        h := _n.rc4(key, _n.md5(u.concat([_PAD, self.id0])))
        k := 1
        while k <= 19:
            kk := []
            for b in key:
                append(kk, b ^ k)
            h = _n.rc4(kk, h)
            k = k + 1
        return h == _n.bytes_slice(self.u, 0, 16)

    func _owner_to_user(pw):
        n := self.length // 8 if self.r >= 3 else 5
        h := _n.md5(_pad_pw(pw))
        if self.r >= 3:
            k := 0
            while k < 50:
                h = _n.md5(h)
                k = k + 1
        key := _n.bytes_slice(h, 0, n)
        data := self.o
        if self.r == 2:
            return _n.rc4(key, data)
        k := 19
        while k >= 0:
            kk := []
            for b in key:
                append(kk, b ^ k)
            data = _n.rc4(kk, data)
            k = k - 1
        return data

    func _hash_r6(pw, salt, udata):
        k := _n.sha2(u.concat([pw, salt, udata]), 256)
        if self.r == 5:
            return k
        rnd := 0
        while true:
            k1 := []
            unit := u.concat([pw, k, udata])
            c := 0
            while c < 64:
                for b in unit:
                    append(k1, b)
                c = c + 1
            e := _n.aes_cbc_encrypt(_n.bytes_slice(k, 0, 16), _n.bytes_slice(k, 16, 32), k1)
            s := 0
            q := 0
            while q < 16:
                s = s + e[q]
                q = q + 1
            m := s % 3
            k = _n.sha2(e, 256 if m == 0 else (384 if m == 1 else 512))
            rnd = rnd + 1
            if rnd >= 64 and e[len(e) - 1] <= rnd - 32:
                break
        return _n.bytes_slice(k, 0, 32)

    func _auth_r6(pw):
        p := _n.bytes_slice(_n.utf8_encode(pw), 0, 127)
        # utilisateur
        if self._hash_r6(p, _n.bytes_slice(self.u, 32, 40), []) == _n.bytes_slice(self.u, 0, 32):
            ik := self._hash_r6(p, _n.bytes_slice(self.u, 40, 48), [])
            return _n.aes_cbc_decrypt(ik, u.concat([_n.bytes_fill(16, 0), self.ue]), false)
        # propriétaire
        u48 := _n.bytes_slice(self.u, 0, 48)
        if self._hash_r6(p, _n.bytes_slice(self.o, 32, 40), u48) == _n.bytes_slice(self.o, 0, 32):
            ik := self._hash_r6(p, _n.bytes_slice(self.o, 40, 48), u48)
            return _n.aes_cbc_decrypt(ik, u.concat([_n.bytes_fill(16, 0), self.oe]), false)
        return null

    func authenticate(pw):
        if self.r >= 5:
            k := self._auth_r6(pw)
            if k == null:
                return false
            self.key = k
            return true
        key := self._key_r4(pw)
        if self._check_user_r4(key):
            self.key = key
            return true
        up := self._owner_to_user(pw)
        key2 := self._key_r4(up)
        if self._check_user_r4(key2):
            self.key = key2
            return true
        return false

    func _obj_key(num, gen):
        if self.r >= 5:
            return self.key
        extra := [num & 255, (num >> 8) & 255, (num >> 16) & 255, gen & 255, (gen >> 8) & 255]
        data := u.concat([self.key, extra])
        if self.aes:
            data = u.concat([data, [115, 65, 108, 84]])
        h := _n.md5(data)
        n := len(self.key) + 5
        if n > 16:
            n = 16
        return _n.bytes_slice(h, 0, n)

    func decrypt(data, num, gen, is_stream):
        if (is_stream and self.stm_identity) or (not is_stream and self.str_identity):
            return data
        key := self._obj_key(num, gen)
        if self.aes:
            if len(data) < 16:
                return []
            return _n.aes_cbc_decrypt(key, data, true)
        return _n.rc4(key, data)

# ---------------------------------------------------------------------------------------------- document

class PdfFile:
    func init(data, password=""):
        self.data = data
        self.n = len(data)
        self.version = "1.4"
        self.xref = {}
        self.trailer = {}
        self._cache = {}
        self._objstm_cache = {}
        self.security = null
        self.encrypted = false
        self.repaired = false
        self._pages = null
        self._loading = {}
        self._header()
        try:
            self._load_xref()
        catch e:
            if e.type == "PDFError" or e.type == "ValueError" or e.type == "IndexError" or e.type == "KeyError" or e.type == "TypeError" or e.type == "CompressionError":
                self._repair()
            else:
                raise(e)
        if not contains_key(self.trailer, "Root"):
            self._repair()
        self._setup_security(password)
        self.catalog = self.get(u.get(self.trailer, "Root", null))
        if type(self.catalog) != "dict":
            self._repair()
            self.catalog = self.get(u.get(self.trailer, "Root", null))
            if type(self.catalog) != "dict":
                errors.fail(errors.PDF, "catalogue PDF introuvable")
        cv := u.get(self.catalog, "Version", null)
        if is_name(cv):
            self.version = name_of(cv)

    func _header():
        p := _n.bytes_find(self.data, [37, 80, 68, 70, 45], 0)
        if p < 0 or p > 1024:
            errors.fail(errors.PDF, "ce n'est pas un fichier PDF (en-tête %PDF- absent)")
        self.offset_base = p
        v := _n.latin1_decode(_n.bytes_slice(self.data, p + 5, p + 8))
        self.version = v

    # ---------------------------------------------------------- XRef
    func _load_xref():
        tail := self.n - 2048
        if tail < 0:
            tail = 0
        sx := _n.bytes_rfind(self.data, _n.utf8_encode("startxref"), -1)
        if sx < 0:
            errors.fail(errors.PDF, "startxref introuvable")
        tk := _n.pdf_tokens(self.data, sx + 9, sx + 40, false, 1)[0]
        if len(tk) == 0 or tk[0][0] != "n":
            errors.fail(errors.PDF, "startxref invalide")
        off := tk[0][1]
        seen := {}
        first := true
        while off != null and not contains_key(seen, off):
            seen[off] = true
            tr := self._read_xref_at(off)
            if tr == null:
                errors.fail(errors.PDF, "table de références croisées illisible à l'offset " + str(off))
            if first:
                self.trailer = tr
                first = false
            else:
                for k in keys(tr):
                    if not contains_key(self.trailer, k):
                        self.trailer[k] = tr[k]
            stm := u.get(tr, "XRefStm", null)
            if stm != null and not contains_key(seen, stm):
                self._read_xref_at(stm)
            off = u.get(tr, "Prev", null)

    func _set(num, entry):
        if not contains_key(self.xref, num):
            self.xref[num] = entry

    func _read_xref_at(off):
        if off < 0 or off >= self.n:
            # décalage par rapport à un en-tête déplacé
            if off + self.offset_base < self.n:
                off = off + self.offset_base
            else:
                return null
        head := _n.latin1_decode(_n.bytes_slice(self.data, off, off + 4))
        if head == "xref":
            return self._read_classic(off + 4)
        # flux XRef
        toks := _n.pdf_tokens(self.data, off, off + 4096, true)[0]
        if len(toks) < 3 or toks[2][0] != "k" or toks[2][1] != "obj":
            if self.offset_base > 0:
                return self._read_xref_at(off + self.offset_base) if off < self.offset_base * 2 else null
            return null
        obj := self._parse_object_at(off, toks[0][1], toks[1][1])
        if not isinstance(obj, Stream):
            return null
        d := obj.dict
        if name_of(u.get(d, "Type", "")) != "XRef":
            return null
        data := apply_filters(obj.raw, u.get(d, "Filter", null), u.get(d, "DecodeParms", null))[0]
        w := u.get(d, "W", [1, 2, 1])
        size := u.get(d, "Size", 0)
        index := u.get(d, "Index", [0, size])
        rec := w[0] + w[1] + w[2]
        pos := 0
        ii := 0
        while ii + 1 < len(index):
            start := index[ii]
            count := index[ii + 1]
            k := 0
            while k < count and pos + rec <= len(data):
                f := [1, 0, 0]
                j := 0
                p := pos
                while j < 3:
                    v := 0
                    m := 0
                    while m < w[j]:
                        v = (v << 8) | data[p]
                        p = p + 1
                        m = m + 1
                    if w[j] > 0:
                        f[j] = v
                    j = j + 1
                num := start + k
                if f[0] == 1:
                    self._set(num, ["n", f[1], f[2]])
                elif f[0] == 2:
                    self._set(num, ["c", f[1], f[2]])
                elif f[0] == 0:
                    self._set(num, ["f", 0, 0])
                pos = pos + rec
                k = k + 1
            ii = ii + 2
        return d

    func _read_classic(pos):
        # jetons jusqu'à « trailer » + dictionnaire
        end := _n.bytes_find(self.data, _n.utf8_encode("trailer"), pos)
        if end < 0:
            return null
        toks := _n.pdf_tokens(self.data, pos, end)[0]
        i := 0
        n := len(toks)
        while i + 1 < n:
            if toks[i][0] != "n" or toks[i + 1][0] != "n":
                i = i + 1
                continue
            start := toks[i][1]
            count := toks[i + 1][1]
            i = i + 2
            k := 0
            while k < count and i + 2 < n:
                o := toks[i][1]
                g := toks[i + 1][1]
                t := toks[i + 2][1]
                if t == "n" and o > 0:
                    self._set(start + k, ["n", o, g])
                elif t == "f":
                    self._set(start + k, ["f", 0, 0])
                i = i + 3
                k = k + 1
        tt := _n.pdf_tokens(self.data, end + 7, end + 7 + 65536, false)[0]
        if len(tt) == 0 or tt[0][0] != "<<":
            return null
        return parse_value(tt, 0)[0]

    # Reconstruction : recherche de tous les « n g obj » du fichier.
    func _repair():
        self.repaired = true
        self.xref = {}
        self._cache = {}
        pos := 0
        pat := _n.utf8_encode(" obj")
        roots := []
        while true:
            p := _n.bytes_find(self.data, pat, pos)
            if p < 0:
                break
            # remonte « num gen »
            q := p - 1
            while q >= 0 and self.data[q] >= 48 and self.data[q] <= 57:
                q = q - 1
            gen_start := q + 1
            if q >= 0 and self.data[q] == 32:
                r := q - 1
                while r >= 0 and self.data[r] >= 48 and self.data[r] <= 57:
                    r = r - 1
                num_start := r + 1
                if num_start < q and gen_start < p:
                    num := to_int(_n.latin1_decode(_n.bytes_slice(self.data, num_start, q)))
                    gen := to_int(_n.latin1_decode(_n.bytes_slice(self.data, gen_start, p)))
                    self.xref[num] = ["n", num_start, gen]
            pos = p + 4
        # objets compressés : flux /ObjStm
        for num in keys(self.xref):
            try:
                o := self.object(num)
                if isinstance(o, Stream) and name_of(u.get(o.dict, "Type", "")) == "ObjStm":
                    self._index_objstm(num, o)
                if type(o) == "dict" and name_of(u.get(o, "Type", "")) == "Catalog":
                    append(roots, num)
                if isinstance(o, Stream) and name_of(u.get(o.dict, "Type", "")) == "XRef":
                    for k in ["Root", "Info", "ID", "Encrypt"]:
                        if contains_key(o.dict, k) and not contains_key(self.trailer, k):
                            self.trailer[k] = o.dict[k]
            catch e:
                continue
        # dernier « trailer » du fichier
        tp := _n.bytes_rfind(self.data, _n.utf8_encode("trailer"), -1)
        if tp >= 0:
            tt := _n.pdf_tokens(self.data, tp + 7, tp + 7 + 65536, false)[0]
            if len(tt) > 0 and tt[0][0] == "<<":
                tr := parse_value(tt, 0)[0]
                for k in keys(tr):
                    if k != "Prev" and k != "XRefStm":
                        self.trailer[k] = tr[k]
        if not contains_key(self.trailer, "Root") and len(roots) > 0:
            self.trailer["Root"] = Ref(roots[len(roots) - 1], 0)
        if not contains_key(self.trailer, "Root"):
            errors.fail(errors.PDF, "PDF irréparable : catalogue introuvable")

    func _index_objstm(num, stm):
        dec := self.decode(stm)
        n := u.get(stm.dict, "N", 0)
        first := u.get(stm.dict, "First", 0)
        toks := _n.pdf_tokens(dec, 0, first)[0]
        k := 0
        while k < n and 2 * k + 1 < len(toks):
            onum := toks[2 * k][1]
            if not contains_key(self.xref, onum) or self.xref[onum][0] != "n":
                self.xref[onum] = ["c", num, k]
            k = k + 1

    # ---------------------------------------------------------- objets
    func _parse_object_at(off, num, gen):
        window := 4096
        while true:
            end := off + window
            if end > self.n:
                end = self.n
            res := _n.pdf_tokens(self.data, off, end, true)
            toks := res[0]
            last := toks[len(toks) - 1] if len(toks) > 0 else null
            complete := last != null and last[0] == "k" and (last[1] == "endobj" or last[1] == "stream")
            if not complete and end < self.n:
                window = window * 4
                continue
            if len(toks) < 3 or toks[2][0] != "k" or toks[2][1] != "obj":
                errors.fail(errors.PDF, "objet " + str(num) + " introuvable à l'offset " + str(off))
            if len(toks) == 3:
                return null
            r := parse_value(toks, 3)
            val := r[0]
            nxt := r[1]
            if nxt < len(toks) and toks[nxt][0] == "k" and toks[nxt][1] == "stream":
                return self._read_stream(val, toks[nxt][2], num, gen)
            return val

    func _read_stream(d, after_kw, num, gen):
        p := after_kw
        if p < self.n and self.data[p] == 13:
            p = p + 1
        if p < self.n and self.data[p] == 10:
            p = p + 1
        length := u.get(d, "Length", null)
        if isinstance(length, Ref):
            if contains_key(self._loading, length.key()):
                length = null
            else:
                length = self.get(length)
        ok := false
        if type(length) == "int" and length >= 0 and p + length <= self.n:
            # contrôle : « endstream » doit suivre
            tail := _n.latin1_decode(_n.bytes_slice(self.data, p + length, p + length + 32))
            if string.contains(tail, "endstream"):
                ok = true
        if not ok:
            e := _n.bytes_find(self.data, _n.utf8_encode("endstream"), p)
            if e < 0:
                e = self.n
            length = e - p
            # retire la fin de ligne qui précède endstream
            while length > 0 and (self.data[p + length - 1] == 10 or self.data[p + length - 1] == 13):
                length = length - 1
        return Stream(d, _n.bytes_slice(self.data, p, p + length), num, gen)

    func _decrypt_obj(v, num, gen):
        if self.security == null:
            return v
        if isinstance(v, PdfString):
            return PdfString(self.security.decrypt(v.data, num, gen, false), v.hex)
        if type(v) == "list":
            out := []
            for x in v:
                append(out, self._decrypt_obj(x, num, gen))
            return out
        if type(v) == "dict":
            out := {}
            for k in keys(v):
                out[k] = self._decrypt_obj(v[k], num, gen)
            return out
        if isinstance(v, Stream):
            d := self._decrypt_obj(v.dict, num, gen)
            t := name_of(u.get(d, "Type", ""))
            raw := v.raw
            if t != "XRef" and not (t == "Metadata" and not self.security.encrypt_metadata):
                fl := u.get(d, "Filter", null)
                identity := false
                if type(fl) == "list" and len(fl) > 0 and name_of(fl[0]) == "Crypt":
                    identity = true
                if not identity:
                    raw = self.security.decrypt(raw, num, gen, true)
            s := Stream(d, raw, num, gen)
            s.decrypted = true
            return s
        return v

    func object(num, gen=0):
        if contains_key(self._cache, num):
            return self._cache[num]
        if not contains_key(self.xref, num):
            return null
        e := self.xref[num]
        val := null
        self._loading[num * 65536 + gen] = true
        try:
            if e[0] == "n":
                val = self._parse_object_at(e[1], num, e[2])
                if self.security != null and num != self._encrypt_num:
                    val = self._decrypt_obj(val, num, e[2])
            elif e[0] == "c":
                val = self._from_objstm(e[1], e[2], num)
        catch err:
            collections.remove(self._loading, num * 65536 + gen)
            if err.type == "PDFError" or err.type == "IndexError" or err.type == "ValueError":
                val = null
                self._cache[num] = null
                return null
            raise(err)
        collections.remove(self._loading, num * 65536 + gen)
        self._cache[num] = val
        return val

    func _from_objstm(stm_num, index, num):
        if not contains_key(self._objstm_cache, stm_num):
            stm := self.object(stm_num)
            if not isinstance(stm, Stream):
                return null
            dec := self.decode(stm)
            n := u.get(stm.dict, "N", 0)
            first := u.get(stm.dict, "First", 0)
            head := _n.pdf_tokens(dec, 0, first)[0]
            offsets := []
            k := 0
            while k < n and 2 * k + 1 < len(head):
                append(offsets, [head[2 * k][1], head[2 * k + 1][1]])
                k = k + 1
            self._objstm_cache[stm_num] = [dec, offsets, first]
        c := self._objstm_cache[stm_num]
        offsets := c[1]
        if index >= len(offsets):
            return null
        start := c[2] + offsets[index][1]
        end := c[2] + offsets[index + 1][1] if index + 1 < len(offsets) else len(c[0])
        toks := _n.pdf_tokens(c[0], start, end)[0]
        if len(toks) == 0:
            return null
        return parse_value(toks, 0)[0]

    func get(v):
        guard := 0
        while isinstance(v, Ref) and guard < 32:
            v = self.object(v.num, v.gen)
            guard = guard + 1
        return v

    func objects():
        out := []
        for k in keys(self.xref):
            if self.xref[k][0] != "f":
                append(out, k)
        return u.sort(out)

    func stream_dict(v):
        o := self.get(v)
        if isinstance(o, Stream):
            return o.dict
        return o

    func decode(stream, stop_at_image=false):
        s := self.get(stream)
        if not isinstance(s, Stream):
            return []
        d := s.dict
        r := apply_filters(s.raw, self.get(u.get(d, "Filter", null)), self.get(u.get(d, "DecodeParms", u.get(d, "DP", null))), stop_at_image)
        return r[0]

    # Filtre d'image restant (DCTDecode...) ou null, après décodage des filtres génériques.
    func decode_image(stream):
        s := self.get(stream)
        d := s.dict
        return apply_filters(s.raw, self.get(u.get(d, "Filter", null)), self.get(u.get(d, "DecodeParms", u.get(d, "DP", null))), true)

    # ---------------------------------------------------------- chiffrement
    func _setup_security(password):
        self._encrypt_num = -1
        enc_ref := u.get(self.trailer, "Encrypt", null)
        if enc_ref == null:
            return null
        if isinstance(enc_ref, Ref):
            self._encrypt_num = enc_ref.num
        enc := self.get(enc_ref)
        if type(enc) != "dict":
            return null
        filt := name_of(u.get(enc, "Filter", "/Standard"))
        if filt != "Standard":
            errors.fail(errors.UNSUPPORTED, "gestionnaire de sécurité PDF non pris en charge : " + u.to_text(filt))
        ids := self.get(u.get(self.trailer, "ID", null))
        id0 := []
        if type(ids) == "list" and len(ids) > 0 and isinstance(ids[0], PdfString):
            id0 = ids[0].data
        sec := _Security(enc, id0)
        if sec.r > 6:
            errors.fail(errors.UNSUPPORTED, "révision de chiffrement PDF non prise en charge : " + str(sec.r))
        if not sec.authenticate(password):
            errors.fail(errors.PDF, "mot de passe incorrect pour ce PDF chiffré")
        self.security = sec
        self.encrypted = true
        # les objets déjà lus (avant authentification) doivent être relus déchiffrés
        self._cache = {}
        self._objstm_cache = {}

    # ---------------------------------------------------------- pages
    func _collect_pages(node_ref, inherited, out, depth):
        if depth > 64:
            return null
        node := self.get(node_ref)
        if type(node) != "dict":
            return null
        inh := u.merge(inherited, null)
        for k in ["Resources", "MediaBox", "CropBox", "Rotate"]:
            if contains_key(node, k):
                inh[k] = node[k]
        t := name_of(u.get(node, "Type", ""))
        kids := self.get(u.get(node, "Kids", null))
        if t == "Pages" or (t == null and kids != null) or (t != "Page" and type(kids) == "list"):
            if type(kids) == "list":
                for kid in kids:
                    self._collect_pages(kid, inh, out, depth + 1)
            return null
        append(out, Page(self, node_ref if isinstance(node_ref, Ref) else null, node, inh, len(out)))

    func pages():
        if self._pages == null:
            out := []
            root := u.get(self.catalog, "Pages", null)
            self._collect_pages(root, {}, out, 0)
            self._pages = out
        return self._pages

    func page_count():
        return len(self.pages())

    func page(i):
        ps := self.pages()
        if i < 0:
            i = i + len(ps)
        if i < 0 or i >= len(ps):
            raise("IndexError", "page " + str(i) + " absente (" + str(len(ps)) + " pages)")
        return ps[i]

    func page_index(ref):
        if not isinstance(ref, Ref):
            return -1
        i := 0
        for p in self.pages():
            if p.ref != null and p.ref.num == ref.num:
                return i
            i = i + 1
        return -1

    # ---------------------------------------------------------- métadonnées
    func info():
        out := {}
        d := self.get(u.get(self.trailer, "Info", null))
        if type(d) != "dict":
            return out
        for k in keys(d):
            v := self.get(d[k])
            if isinstance(v, PdfString):
                out[k] = v.text()
            elif is_name(v):
                out[k] = name_of(v)
            elif type(v) == "int" or type(v) == "float" or type(v) == "bool":
                out[k] = v
        return out

    func xmp():
        m := self.get(u.get(self.catalog, "Metadata", null))
        if not isinstance(m, Stream):
            return null
        return _n.utf8_decode(self.decode(m), false)

    func _name_tree(node, out, depth):
        n := self.get(node)
        if type(n) != "dict" or depth > 32:
            return null
        names := self.get(u.get(n, "Names", null))
        if type(names) == "list":
            i := 0
            while i + 1 < len(names):
                k := self.get(names[i])
                append(out, [k.text() if isinstance(k, PdfString) else u.to_text(k), names[i + 1]])
                i = i + 2
        kids := self.get(u.get(n, "Kids", null))
        if type(kids) == "list":
            for kid in kids:
                self._name_tree(kid, out, depth + 1)

    func named_destinations():
        out := {}
        names := self.get(u.get(self.catalog, "Names", null))
        if type(names) == "dict" and contains_key(names, "Dests"):
            items := []
            self._name_tree(names["Dests"], items, 0)
            for it in items:
                out[it[0]] = it[1]
        dests := self.get(u.get(self.catalog, "Dests", null))
        if type(dests) == "dict":
            for k in keys(dests):
                out[k] = dests[k]
        return out

    # Indice de page d'une destination (tableau, nom ou chaîne nommée) ; -1 si inconnu.
    func dest_page(dest, named=null):
        d := self.get(dest)
        if isinstance(d, PdfString) or is_name(d):
            key := d.text() if isinstance(d, PdfString) else name_of(d)
            nd := named if named != null else self.named_destinations()
            if not contains_key(nd, key):
                return -1
            d = self.get(nd[key])
        if type(d) == "dict":
            d = self.get(u.get(d, "D", null))
        if type(d) == "list" and len(d) > 0:
            if isinstance(d[0], Ref):
                return self.page_index(d[0])
            if type(d[0]) == "int":
                return d[0]
        return -1

    func outlines():
        out := []
        ol := self.get(u.get(self.catalog, "Outlines", null))
        if type(ol) != "dict":
            return out
        named := self.named_destinations()
        self._walk_outline(u.get(ol, "First", null), 1, out, named, {})
        return out

    func _walk_outline(node_ref, level, out, named, seen):
        cur := node_ref
        guard := 0
        while cur != null and guard < 10000:
            if isinstance(cur, Ref):
                if contains_key(seen, cur.num):
                    return null
                seen[cur.num] = true
            node := self.get(cur)
            if type(node) != "dict":
                return null
            title := self.get(u.get(node, "Title", null))
            page := -1
            if contains_key(node, "Dest"):
                page = self.dest_page(node["Dest"], named)
            elif contains_key(node, "A"):
                a := self.get(node["A"])
                if type(a) == "dict" and name_of(u.get(a, "S", "")) == "GoTo":
                    page = self.dest_page(u.get(a, "D", null), named)
            append(out, {"title": title.text() if isinstance(title, PdfString) else "", "page": page, "level": level})
            if contains_key(node, "First"):
                self._walk_outline(node["First"], level + 1, out, named, seen)
            cur = u.get(node, "Next", null)
            guard = guard + 1

    func attachments():
        out := []
        names := self.get(u.get(self.catalog, "Names", null))
        if type(names) != "dict" or not contains_key(names, "EmbeddedFiles"):
            return out
        items := []
        self._name_tree(names["EmbeddedFiles"], items, 0)
        for it in items:
            spec := self.get(it[1])
            if type(spec) != "dict":
                continue
            ef := self.get(u.get(spec, "EF", null))
            if type(ef) != "dict":
                continue
            f := u.get(ef, "UF", u.get(ef, "F", null))
            fname := self.get(u.get(spec, "UF", u.get(spec, "F", null)))
            append(out, {"name": fname.text() if isinstance(fname, PdfString) else it[0], "data": self.decode(f)})
        return out

class Page:
    func init(doc, ref, d, inherited, index):
        self.doc = doc
        self.ref = ref
        self.dict = d
        self.inherited = inherited
        self.index = index

    func _box(key):
        v := self.doc.get(u.get(self.inherited, key, null))
        if type(v) != "list" or len(v) < 4:
            return null
        out := []
        for x in v:
            append(out, to_float(self.doc.get(x)))
        x0 := out[0] if out[0] < out[2] else out[2]
        x1 := out[2] if out[0] < out[2] else out[0]
        y0 := out[1] if out[1] < out[3] else out[3]
        y1 := out[3] if out[1] < out[3] else out[1]
        return [x0, y0, x1, y1]

    func media_box():
        b := self._box("MediaBox")
        return b if b != null else [0.0, 0.0, 612.0, 792.0]

    func crop_box():
        b := self._box("CropBox")
        return b if b != null else self.media_box()

    func rotation():
        r := self.doc.get(u.get(self.inherited, "Rotate", 0))
        if type(r) != "int":
            return 0
        r = r % 360
        if r < 0:
            r = r + 360
        return r

    func width():
        b := self.crop_box()
        r := self.rotation()
        return b[3] - b[1] if r == 90 or r == 270 else b[2] - b[0]

    func height():
        b := self.crop_box()
        r := self.rotation()
        return b[2] - b[0] if r == 90 or r == 270 else b[3] - b[1]

    func resources():
        r := self.doc.get(u.get(self.inherited, "Resources", null))
        return r if type(r) == "dict" else {}

    func contents():
        c := self.doc.get(u.get(self.dict, "Contents", null))
        if c == null:
            return []
        parts := []
        if type(c) == "list":
            for s in c:
                append(parts, self.doc.decode(s))
                append(parts, [10])
        else:
            append(parts, self.doc.decode(c))
        return u.concat(parts)

    func annotations():
        out := []
        a := self.doc.get(u.get(self.dict, "Annots", null))
        if type(a) != "list":
            return out
        for x in a:
            d := self.doc.get(x)
            if type(d) == "dict":
                append(out, d)
        return out

    func links():
        out := []
        for a in self.annotations():
            if name_of(u.get(a, "Subtype", "")) != "Link":
                continue
            rect := []
            for v in self.doc.get(u.get(a, "Rect", [])):
                append(rect, to_float(self.doc.get(v)))
            act := self.doc.get(u.get(a, "A", null))
            if type(act) == "dict":
                s := name_of(u.get(act, "S", ""))
                if s == "URI":
                    uri := self.doc.get(u.get(act, "URI", null))
                    append(out, {"rect": rect, "uri": uri.text() if isinstance(uri, PdfString) else u.to_text(uri)})
                elif s == "GoTo":
                    append(out, {"rect": rect, "page": self.doc.dest_page(u.get(act, "D", null))})
            elif contains_key(a, "Dest"):
                append(out, {"rect": rect, "page": self.doc.dest_page(a["Dest"])})
        return out

func from_bytes(data, password=""):
    if type(data) != "list":
        raise("TypeError", "pdf_reader.from_bytes : liste d'octets attendue")
    return PdfFile(data, password)

func open(src, password=""):
    if type(src) == "list":
        return PdfFile(src, password)
    if type(src) != "str":
        raise("TypeError", "pdf_reader.open : chemin ou octets attendus")
    if not io.file_exists(src):
        raise("IoError", "fichier introuvable : " + src)
    return PdfFile(io.read_bytes(src), password)
