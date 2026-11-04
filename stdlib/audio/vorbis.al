# ALEX STANDARD LIBRARY — audio.vorbis
#
# Décodage Ogg Vorbis (.ogg) vers du PCM 16 bits entrelacé, pour audio.realtime (musiques, bruitages compressés).
#
#   use audio.vorbis as vorbis
#   d := vorbis.load_pcm16("theme.ogg")     # {"buffer": ffi.Buffer, "frames", "channels", "rate", "decoder"}
#   info := vorbis.probe("theme.ogg")        # {"channels", "rate", "frames", "duration"} sans décoder
#
# DEUX DÉCODEURS
#   « libvorbisfile » : la bibliothèque du système par ffi (libvorbisfile.so.3 sous Linux ; vorbisfile.dll /
#     libvorbisfile-3.dll à côté du programme sous Windows) : rapide, utilisée quand elle est présente.
#   « alex » : décodeur Vorbis I écrit en ALEX (en-têtes, livres de codes, floor 1, résidus 0 / 1 / 2, couplage,
#     fenêtres, recouvrement) ; la transformée (IMDCT) est en code natif. Toujours disponible, plus lent : environ
#     un dixième à un quart de la durée du son selon la machine — préférer le WAV pour les bruitages courts.
#   ALEX_VORBIS=alex force le décodeur ALEX.
# Limites : Vorbis I seulement (floor 0, très rare, refusé), premier flux logique d'un fichier chaîné.
#
# Erreurs : IoError (fichier), ValueError (flux invalide ou non pris en charge).

from core use len, type, to_int
from collections use append
use ffi
use math
use os as _os
use string as _s
use _native_ffi as _nf

# ---------------------------------------------------------------------------------------------------------------------
# Fichier entier dans un ffi.Buffer (libc)
# ---------------------------------------------------------------------------------------------------------------------

_libc := [null]

func _c():
    if _libc[0] == null:
        lib := ffi.Library("c")
        _libc[0] = {"fopen": lib.function("fopen", ["cstr", "cstr"], "ptr"),
                    "fread": lib.function("fread", ["ptr", "u64", "u64", "ptr"], "u64"),
                    "fseek": lib.function("fseek", ["ptr", "i64", "i32"], "i32"),
                    "ftell": lib.function("ftell", ["ptr"], "i64"),
                    "fclose": lib.function("fclose", ["ptr"], "i32")}
    return _libc[0]

func _read_file(path):
    c := _c()
    f := c["fopen"].call2(path, "rb")
    if f == null or f == 0:
        raise("IoError", "audio.vorbis : impossible d'ouvrir '" + path + "'")
    c["fseek"].call3(f, 0, 2)
    n := c["ftell"].call1(f)
    c["fseek"].call3(f, 0, 0)
    if n <= 0:
        c["fclose"].call1(f)
        raise("IoError", "audio.vorbis : fichier vide '" + path + "'")
    b := ffi.Buffer(n)
    got := c["fread"].call([b.address(), 1, n, f])
    c["fclose"].call1(f)
    if got != n:
        b.free()
        raise("IoError", "audio.vorbis : lecture incomplète de '" + path + "'")
    return b

func _fail(msg):
    raise("ValueError", "audio.vorbis : " + msg)

# ---------------------------------------------------------------------------------------------------------------------
# Conteneur Ogg : paquets du premier flux logique
# ---------------------------------------------------------------------------------------------------------------------

class _OggReader:
    func init(buf):
        self.buf = buf
        self.size = buf.size()
        self.pos = 0
        self.serial = null
        self.pending = []          # morceaux du paquet en cours
        self.packets = []          # paquets complets en attente (list d'octets)
        self.last_granule = -1
        self.eos = false

    # Lit la page suivante du flux ; false à la fin du fichier.
    func _page():
        while self.pos + 27 <= self.size:
            if self.buf.read_bytes(self.pos, 4) != "OggS":
                # resynchronisation : chercher la capture suivante
                self.pos += 1
                continue
            hdr := self.buf.read_array("u8", 27, self.pos)
            nseg := hdr[26]
            if self.pos + 27 + nseg > self.size:
                return false
            segs := self.buf.read_array("u8", nseg, self.pos + 27) if nseg > 0 else []
            body := 0
            for sz in segs:
                body += sz
            start := self.pos + 27 + nseg
            if start + body > self.size:
                return false
            serial := hdr[14] | (hdr[15] << 8) | (hdr[16] << 16) | (hdr[17] << 24)
            self.pos = start + body
            if self.serial == null:
                self.serial = serial
            if serial != self.serial:
                continue
            g := 0
            k := 13
            while k >= 6:
                g = (g << 8) | hdr[k]
                k -= 1
            data := self.buf.read_array("u8", body, start) if body > 0 else []
            off := 0
            for sz in segs:
                if sz > 0:
                    append(self.pending, data[off:off + sz])
                off += sz
                if sz < 255:
                    pk := []
                    for part in self.pending:
                        pk = pk + part
                    self.pending = []
                    append(self.packets, pk)
            if g >= 0 and g < 9223372036854775807:
                self.last_granule = g
            if (hdr[5] & 4) != 0:
                self.eos = true
            return true
        return false

    # Paquet suivant (list d'octets) ou null.
    func next():
        while len(self.packets) == 0:
            if self.eos or not self._page():
                return null
        p := self.packets[0]
        self.packets = self.packets[1:len(self.packets)]
        return p

# Position d'échantillon (granule) de la dernière page du premier flux : nombre total d'images.
func _final_granule(buf):
    size := buf.size()
    start := size - 65307
    if start < 0:
        start = 0
    tail := buf.read_bytes(start, size - start)
    last := -1
    pos := 0
    while true:
        k := _s.byte_find(tail, "OggS", pos)
        if k < 0:
            break
        if k + 14 <= _s.byte_len(tail):
            g := 0
            j := 13
            while j >= 6:
                g = (g << 8) | _s.byte_at(tail, k + j)
                j -= 1
            if g >= 0 and g < 9223372036854775807:
                last = g
        pos = k + 1
    return last

# ---------------------------------------------------------------------------------------------------------------------
# Lecteur de bits (ordre Vorbis : bit de poids faible d'abord)
# ---------------------------------------------------------------------------------------------------------------------

class _Bits:
    func init(data):
        self.d = data
        self.n = len(data) * 8
        self.pos = 0
        self.eop = false

    func read(count):
        if count == 0:
            return 0
        if self.pos + count > self.n:
            self.eop = true
            self.pos = self.n
            return 0
        v := 0
        shift := 0
        d := self.d
        p := self.pos
        while count > 0:
            bi := p >> 3
            bo := p & 7
            take := 8 - bo
            if take > count:
                take = count
            v = v | (((d[bi] >> bo) & ((1 << take) - 1)) << shift)
            shift += take
            count -= take
            p += take
        self.pos = p
        return v

    # Les `count` bits suivants (32 au plus) sans avancer (zéros au-delà de la fin).
    func peek(count):
        p := self.pos
        bi := p >> 3
        d := self.d
        nb := len(d)
        w := 0
        if bi < nb:
            w = d[bi]
            if bi + 1 < nb:
                w = w | (d[bi + 1] << 8)
                if bi + 2 < nb:
                    w = w | (d[bi + 2] << 16)
                    if count > 16 and bi + 3 < nb:
                        w = w | (d[bi + 3] << 24)
                        if count > 24 and bi + 4 < nb:
                            w = w | (d[bi + 4] << 32)
        return (w >> (p & 7)) & ((1 << count) - 1)

    func skip(count):
        self.pos += count
        if self.pos > self.n:
            self.pos = self.n
            self.eop = true

func _ilog(x):
    r := 0
    while x > 0:
        r += 1
        x = x >> 1
    return r

func _float32_unpack(x):
    mant := x & 0x1FFFFF
    sign := x & 0x80000000
    exp := (x & 0x7FE00000) >> 21
    v := mant * 1.0
    if sign != 0:
        v = 0.0 - v
    return v * math.pow(2.0, exp - 788.0)

func _lookup1_values(entries, dims):
    r := to_int(math.floor(math.pow(entries * 1.0, 1.0 / dims)))
    while _ipow(r + 1, dims) <= entries:
        r += 1
    while r > 0 and _ipow(r, dims) > entries:
        r -= 1
    return r

func _ipow(b, e):
    v := 1
    k := 0
    while k < e:
        v = v * b
        k += 1
    return v

func _tdiv(a, b):
    q := (a if a >= 0 else 0 - a) // (b if b >= 0 else 0 - b)
    if (a < 0) != (b < 0):
        return 0 - q
    return q

func _bitrev(v, n):
    r := 0
    k := 0
    while k < n:
        r = (r << 1) | (v & 1)
        v = v >> 1
        k += 1
    return r

# ---------------------------------------------------------------------------------------------------------------------
# Livres de codes
# ---------------------------------------------------------------------------------------------------------------------

const _FAST := 10

class _Codebook:
    func init(br):
        if br.read(24) != 0x564342:
            _fail("livre de codes : synchronisation absente")
        self.dims = br.read(16)
        self.entries = br.read(24)
        lens := [0 for i in 0..self.entries]
        ordered := br.read(1)
        if ordered == 0:
            sparse := br.read(1)
            k := 0
            while k < self.entries:
                if sparse == 1:
                    if br.read(1) == 1:
                        lens[k] = br.read(5) + 1
                else:
                    lens[k] = br.read(5) + 1
                k += 1
        else:
            cur_len := br.read(5) + 1
            cur := 0
            while cur < self.entries:
                num := br.read(_ilog(self.entries - cur))
                k := 0
                while k < num and cur + k < self.entries:
                    lens[cur + k] = cur_len
                    k += 1
                cur += num
                cur_len += 1
                if cur_len > 33:
                    _fail("livre de codes ordonné invalide")
        self.lens = lens
        self.lookup_type = br.read(4)
        self.vectors = null
        if self.lookup_type == 1 or self.lookup_type == 2:
            minv := _float32_unpack(br.read(32))
            delta := _float32_unpack(br.read(32))
            vbits := br.read(4) + 1
            seq := br.read(1)
            nvals := _lookup1_values(self.entries, self.dims) if self.lookup_type == 1 else self.entries * self.dims
            mults := []
            k := 0
            while k < nvals:
                append(mults, br.read(vbits))
                k += 1
            self._build_vectors(minv, delta, seq, nvals, mults)
        elif self.lookup_type != 0:
            _fail("type de table de livre de codes inconnu (" + str(self.lookup_type) + ")")
        if br.eop:
            _fail("en-tête de configuration tronqué")
        self._build_huffman()

    func _build_vectors(minv, delta, seq, nvals, mults):
        vecs := []
        e := 0
        while e < self.entries:
            v := []
            last := 0.0
            if self.lookup_type == 1:
                div := 1
                k := 0
                while k < self.dims:
                    off := (e // div) % nvals
                    x := mults[off] * delta + minv + last
                    if seq == 1:
                        last = x
                    append(v, x)
                    div = div * nvals
                    k += 1
            else:
                k := 0
                while k < self.dims:
                    x := mults[e * self.dims + k] * delta + minv + last
                    if seq == 1:
                        last = x
                    append(v, x)
                    k += 1
            append(vecs, v)
            e += 1
        self.vectors = vecs

    func _build_huffman():
        marker := [0 for i in 0..33]
        codes := [0 for i in 0..self.entries]
        used := 0
        single := -1
        i := 0
        while i < self.entries:
            l := self.lens[i]
            if l > 0:
                used += 1
                single = i
                entry := marker[l]
                if l < 32 and (entry >> l) != 0:
                    _fail("livre de codes sur-spécifié")
                codes[i] = entry
                j := l
                while j > 0:
                    if (marker[j] & 1) != 0:
                        if j == 1:
                            marker[1] += 1
                        else:
                            marker[j] = marker[j - 1] << 1
                        break
                    marker[j] += 1
                    j -= 1
                j = l + 1
                while j < 33:
                    if (marker[j] >> 1) == entry:
                        entry = marker[j]
                        marker[j] = marker[j - 1] << 1
                    else:
                        break
                    j += 1
            i += 1
        self.single = single if used == 1 else -1
        fast := [-1 for i in 0..(1 << _FAST)]
        longs := []
        i = 0
        while i < self.entries:
            l := self.lens[i]
            if l > 0:
                r := _bitrev(codes[i], l)
                if l <= _FAST:
                    step := 1 << l
                    f := r
                    while f < (1 << _FAST):
                        fast[f] = i
                        f += step
                else:
                    append(longs, [l, r, i])
            i += 1
        longs = _sort_by_first(longs)
        self.fast = fast
        self.longs = longs

    func decode(br):
        if self.single >= 0:
            br.skip(self.lens[self.single])
            return self.single
        e := self.fast[br.peek(_FAST)]
        if e >= 0:
            br.pos += self.lens[e]
            if br.pos > br.n:
                br.pos = br.n
                br.eop = true
                return -1
            return e
        for it in self.longs:
            if br.peek(it[0]) == it[1]:
                br.skip(it[0])
                return it[2]
        br.eop = true
        return -1

func _sort_by_first(items):
    # tri par insertion (listes courtes)
    out := []
    for it in items:
        k := len(out)
        append(out, it)
        while k > 0 and out[k - 1][0] > it[0]:
            out[k] = out[k - 1]
            k -= 1
        out[k] = it
    return out

# ---------------------------------------------------------------------------------------------------------------------
# Floor 1
# ---------------------------------------------------------------------------------------------------------------------

const _FLOOR1_RANGE := [256, 128, 86, 64]

_inv_db := [null]

func _inverse_db():
    if _inv_db[0] == null:
        t := []
        k := 0
        while k < 256:
            append(t, math.pow(1.0649863, k - 255.0))
            k += 1
        _inv_db[0] = t
    return _inv_db[0]

class _Floor1:
    func init(br):
        parts := br.read(5)
        self.class_list = []
        maxc := -1
        k := 0
        while k < parts:
            c := br.read(4)
            append(self.class_list, c)
            if c > maxc:
                maxc = c
            k += 1
        self.class_dims = []
        self.class_subs = []
        self.class_master = []
        self.sub_books = []
        k = 0
        while k <= maxc:
            append(self.class_dims, br.read(3) + 1)
            sc := br.read(2)
            append(self.class_subs, sc)
            append(self.class_master, br.read(8) if sc > 0 else 0)
            books := []
            j := 0
            while j < (1 << sc):
                append(books, br.read(8) - 1)
                j += 1
            append(self.sub_books, books)
            k += 1
        self.mult = br.read(2) + 1
        rb := br.read(4)
        self.x = [0, 1 << rb]
        for c in self.class_list:
            j := 0
            while j < self.class_dims[c]:
                append(self.x, br.read(rb))
                j += 1
        n := len(self.x)
        # ordre croissant des X et voisins bas / haut
        order := [i for i in 0..n]
        i := 1
        while i < n:
            v := order[i]
            j := i
            while j > 0 and self.x[order[j - 1]] > self.x[v]:
                order[j] = order[j - 1]
                j -= 1
            order[j] = v
            i += 1
        self.order = order
        self.low = [0 for i in 0..n]
        self.high = [0 for i in 0..n]
        i = 2
        while i < n:
            lo := 0
            hi := 1
            lx := -1
            hx := 1 << 30
            j := 0
            while j < i:
                xj := self.x[j]
                if xj < self.x[i] and xj > lx:
                    lx = xj
                    lo = j
                if xj > self.x[i] and xj < hx:
                    hx = xj
                    hi = j
                j += 1
            self.low[i] = lo
            self.high[i] = hi
            i += 1

    # Valeurs Y du paquet, ou null (canal inutilisé).
    func decode(br, books):
        if br.read(1) == 0:
            return null
        rng := _FLOOR1_RANGE[self.mult - 1]
        bits := _ilog(rng - 1)
        y := [br.read(bits), br.read(bits)]
        for c in self.class_list:
            cdim := self.class_dims[c]
            cbits := self.class_subs[c]
            csub := (1 << cbits) - 1
            cval := 0
            if cbits > 0:
                cval = books[self.class_master[c]].decode(br)
            j := 0
            while j < cdim:
                book := self.sub_books[c][cval & csub]
                cval = cval >> cbits
                if book >= 0:
                    append(y, books[book].decode(br))
                else:
                    append(y, 0)
                j += 1
        if br.eop:
            return null
        return y

    # Points (x, y) de la courbe à tracer : segments rendus en code natif (audio_vfloor).
    func points(y, half):
        rng := _FLOOR1_RANGE[self.mult - 1]
        n := len(self.x)
        fy := [0 for i in 0..n]
        flag := [false for i in 0..n]
        fy[0] = y[0]
        fy[1] = y[1]
        flag[0] = true
        flag[1] = true
        i := 2
        while i < n:
            lo := self.low[i]
            hi := self.high[i]
            pred := _render_point(self.x[lo], fy[lo], self.x[hi], fy[hi], self.x[i])
            val := y[i]
            highroom := rng - pred
            lowroom := pred
            room := (highroom if highroom < lowroom else lowroom) * 2
            if val != 0:
                flag[lo] = true
                flag[hi] = true
                flag[i] = true
                if val >= room:
                    if highroom > lowroom:
                        fy[i] = val - lowroom + pred
                    else:
                        fy[i] = pred - val + highroom - 1
                else:
                    if (val & 1) == 1:
                        fy[i] = pred - ((val + 1) // 2)
                    else:
                        fy[i] = pred + (val // 2)
            else:
                fy[i] = pred
            i += 1
        m := self.mult
        hx := 0
        hy := fy[self.order[0]] * m
        pts := [0, hy]
        k := 1
        while k < n:
            idx := self.order[k]
            if flag[idx]:
                hy = fy[idx] * m
                hx = self.x[idx]
                append(pts, hx)
                append(pts, hy)
            k += 1
        if hx < half:
            append(pts, half)
            append(pts, hy)
        return pts

func _render_point(x0, y0, x1, y1, x):
    dy := y1 - y0
    adx := x1 - x0
    ady := dy if dy >= 0 else 0 - dy
    err := ady * (x - x0)
    off := err // adx
    if dy < 0:
        return y0 - off
    return y0 + off

# ---------------------------------------------------------------------------------------------------------------------
# Résidus
# ---------------------------------------------------------------------------------------------------------------------

class _Residue:
    func init(br, kind):
        self.kind = kind
        self.begin = br.read(24)
        self.end = br.read(24)
        self.psize = br.read(24) + 1
        self.classes = br.read(6) + 1
        self.classbook = br.read(8)
        cascade := []
        k := 0
        while k < self.classes:
            low := br.read(3)
            high := br.read(5) if br.read(1) == 1 else 0
            append(cascade, high * 8 + low)
            k += 1
        self.books = []
        for c in cascade:
            row := []
            j := 0
            while j < 8:
                if (c & (1 << j)) != 0:
                    append(row, br.read(8))
                else:
                    append(row, -1)
                j += 1
            append(self.books, row)

    # Décode les vecteurs (listes de half flottants) des canaux non exclus, en place.
    func decode(br, books, vecs, dnd, half):
        if self.kind == 2:
            ch := len(vecs)
            any := false
            for x in dnd:
                if not x:
                    any = true
            if not any:
                return
            big := [0.0 for i in 0..(half * ch)]
            self._decode(br, books, [big], [false], half * ch, 1)
            # désentrelacement
            c := 0
            while c < ch:
                v := vecs[c]
                k := 0
                p := c
                while k < half:
                    v[k] = big[p]
                    p += ch
                    k += 1
                c += 1
            return
        self._decode(br, books, vecs, dnd, half, self.kind)

    func _decode(br, books, vecs, dnd, size, kind):
        beg := self.begin if self.begin < size else size
        end := self.end if self.end < size else size
        nread := end - beg
        if nread <= 0:
            return
        ps := self.psize
        parts := nread // ps
        cb := books[self.classbook]
        cpw := cb.dims
        nch := len(vecs)
        classif := [[0 for i in 0..(parts + cpw)] for c in 0..nch]
        npass := 0
        while npass < 8:
            pc := 0
            while pc < parts:
                if npass == 0:
                    c := 0
                    while c < nch:
                        if not dnd[c]:
                            temp := cb.decode(br)
                            if temp < 0:
                                return
                            i := cpw - 1
                            while i >= 0:
                                classif[c][i + pc] = temp % self.classes
                                temp = temp // self.classes
                                i -= 1
                        c += 1
                i := 0
                while i < cpw and pc < parts:
                    c := 0
                    while c < nch:
                        if not dnd[c]:
                            vq := self.books[classif[c][pc]][npass]
                            if vq >= 0:
                                book := books[vq]
                                off := beg + pc * ps
                                v := vecs[c]
                                if kind == 0:
                                    step := ps // book.dims
                                    j := 0
                                    while j < step:
                                        e := book.decode(br)
                                        if e < 0:
                                            return
                                        vec := book.vectors[e]
                                        k := 0
                                        while k < book.dims:
                                            v[off + j + k * step] += vec[k]
                                            k += 1
                                        j += 1
                                else:
                                    j := 0
                                    while j < ps:
                                        e := book.decode(br)
                                        if e < 0:
                                            return
                                        for x in book.vectors[e]:
                                            v[off + j] += x
                                            j += 1
                        c += 1
                    i += 1
                    pc += 1
            npass += 1

# ---------------------------------------------------------------------------------------------------------------------
# Décodeur ALEX
# ---------------------------------------------------------------------------------------------------------------------

class Decoder:
    func init(buf):
        self.ogg = _OggReader(buf)
        p := self.ogg.next()
        if p == null or len(p) < 30 or p[0] != 1 or _bytes_str(p, 1, 6) != "vorbis":
            _fail("en-tête d'identification Vorbis absent (fichier Ogg Vorbis attendu)")
        br := _Bits(p)
        br.skip(56)
        if br.read(32) != 0:
            _fail("version de Vorbis non prise en charge")
        self.channels = br.read(8)
        self.rate = br.read(32)
        br.skip(96)
        self.bs0 = 1 << br.read(4)
        self.bs1 = 1 << br.read(4)
        if self.channels < 1 or self.rate < 1 or self.bs0 < 64 or self.bs1 < self.bs0 or self.bs1 > 8192:
            _fail("en-tête d'identification invalide")
        p = self.ogg.next()                 # commentaires
        if p == null or p[0] != 3:
            _fail("en-tête de commentaires absent")
        p = self.ogg.next()
        if p == null or p[0] != 5:
            _fail("en-tête de configuration absent")
        self._setup(p)
        self.tables = {}
        self.windows = {}
        ch := self.channels
        self.prev = [ffi.Buffer(8 * self.bs1) for c in 0..ch]      # bloc précédent fenêtré, par canal
        self.cur = [ffi.Buffer(8 * self.bs1) for c in 0..ch]
        self.prev_n = 0
        self.coef = [ffi.Buffer(4 * self.bs1) for c in 0..ch]
        self.pts = ffi.Buffer(8 * 1024)
        self.invdb = ffi.Buffer(8 * 256)
        self.invdb.write_array("f64", _inverse_db())
        self.outch = ch if ch <= 2 else 2
        self.out = null
        self.at = 0

    func _state(n):
        return {"coef": self.coef, "pts": self.pts}

    # Tampon de sortie (PCM 16 bits entrelacé) d'au moins `frames` images.
    func _ensure(frames):
        need := frames * self.outch * 2
        if self.out == null:
            self.out = ffi.Buffer(need if need > 4096 else 4096)
            return
        if self.out.size() >= need:
            return
        o2 := ffi.Buffer(need * 2)
        o2.copy_from(self.out, self.at * self.outch * 2)
        self.out.free()
        self.out = o2

    func free():
        for b in self.prev + self.cur + self.coef:
            b.free()
        self.pts.free()
        self.invdb.free()
        for k in self.tables:
            for b in self.tables[k]:
                if b != null:
                    b.free()
        for k in self.windows:
            self.windows[k].free()

    func _setup(p):
        br := _Bits(p)
        br.skip(56)
        n := br.read(8) + 1
        self.books = []
        k := 0
        while k < n:
            append(self.books, _Codebook(br))
            k += 1
        n = br.read(6) + 1
        k = 0
        while k < n:
            if br.read(16) != 0:
                _fail("transformée temporelle non nulle")
            k += 1
        n = br.read(6) + 1
        self.floors = []
        k = 0
        while k < n:
            t := br.read(16)
            if t != 1:
                _fail("floor de type " + str(t) + " non pris en charge (floor 1 seulement)")
            append(self.floors, _Floor1(br))
            k += 1
        n = br.read(6) + 1
        self.residues = []
        k = 0
        while k < n:
            t := br.read(16)
            if t > 2:
                _fail("résidu de type " + str(t) + " invalide")
            append(self.residues, _Residue(br, t))
            k += 1
        n = br.read(6) + 1
        self.mappings = []
        k = 0
        while k < n:
            if br.read(16) != 0:
                _fail("type de correspondance invalide")
            subs := br.read(4) + 1 if br.read(1) == 1 else 1
            coupling := []
            if br.read(1) == 1:
                steps := br.read(8) + 1
                bits := _ilog(self.channels - 1)
                j := 0
                while j < steps:
                    append(coupling, [br.read(bits), br.read(bits)])
                    j += 1
            if br.read(2) != 0:
                _fail("champ réservé non nul")
            mux := [0 for c in 0..self.channels]
            if subs > 1:
                c := 0
                while c < self.channels:
                    mux[c] = br.read(4)
                    c += 1
            sf := []
            sr := []
            j := 0
            while j < subs:
                br.read(8)
                append(sf, br.read(8))
                append(sr, br.read(8))
                j += 1
            append(self.mappings, {"coupling": coupling, "mux": mux, "floor": sf, "residue": sr})
            k += 1
        n = br.read(6) + 1
        self.modes = []
        k = 0
        while k < n:
            bf := br.read(1)
            br.read(16)
            br.read(16)
            append(self.modes, [bf, br.read(8)])
            k += 1
        if br.read(1) != 1:
            _fail("bit de fin de configuration absent")
        self.mode_bits = _ilog(len(self.modes) - 1)

    # Tables natives de l'IMDCT pour la taille n.
    func _imdct_tables(n):
        if n in self.tables:
            return self.tables[n]
        big := n // 2
        h := big // 2
        vals := []
        k := 0
        while k < h:
            a := math.PI * (k + 0.25) / big
            append(vals, math.cos(a))
            append(vals, math.sin(a))
            k += 1
        k = 0
        while k < h:
            a := math.PI * k / big
            append(vals, math.cos(a))
            append(vals, math.sin(a))
            k += 1
        k = 0
        while k < h // 2:
            a := 2.0 * math.PI * k / h
            append(vals, math.cos(a))
            append(vals, math.sin(a))
            k += 1
        tb := ffi.Buffer(8 * len(vals))
        tb.write_array("f64", vals)
        t := [tb, null, ffi.Buffer(8 * big)]
        self.tables[n] = t
        return t

    # Pente de fenêtre de longueur L (montante), dans un ffi.Buffer de flottants 64 bits.
    func _slope(l):
        if l in self.windows:
            return self.windows[l]
        w := []
        k := 0
        while k < l:
            s := math.sin((k + 0.5) / l * math.PI * 0.5)
            append(w, math.sin(0.5 * math.PI * s * s))
            k += 1
        b := ffi.Buffer(8 * l if l > 0 else 8)
        if l > 0:
            b.write_array("f64", w)
        self.windows[l] = b
        return b

    # Décode un paquet audio et ajoute ses images au tampon de sortie ; rend le nombre d'images produites.
    func decode_packet(p):
        br := _Bits(p)
        if br.read(1) != 0:
            return 0
        mode := self.modes[br.read(self.mode_bits)] if self.mode_bits > 0 else self.modes[0]
        long := mode[0] == 1
        n := self.bs1 if long else self.bs0
        prev_flag := 0
        next_flag := 0
        if long:
            prev_flag = br.read(1)
            next_flag = br.read(1)
        if br.eop:
            return 0
        mp := self.mappings[mode[1]]
        half := n // 2
        ch := self.channels
        floors := []
        nonzero := []
        c := 0
        while c < ch:
            sub := mp["mux"][c]
            fl := self.floors[mp["floor"][sub]]
            y := fl.decode(br, self.books)
            append(floors, y)
            append(nonzero, y != null)
            c += 1
        for cp in mp["coupling"]:
            if nonzero[cp[0]] or nonzero[cp[1]]:
                nonzero[cp[0]] = true
                nonzero[cp[1]] = true
        vecs := [[0.0 for i in 0..half] for c2 in 0..ch]
        nsub := len(mp["floor"])
        s := 0
        while s < nsub:
            sv := []
            dnd := []
            idx := []
            c = 0
            while c < ch:
                if mp["mux"][c] == s:
                    append(sv, vecs[c])
                    append(dnd, not nonzero[c])
                    append(idx, c)
                c += 1
            self.residues[mp["residue"][s]].decode(br, self.books, sv, dnd, half)
            s += 1
        # synthèse en code natif : découplage, courbe de floor, IMDCT, fenêtre, recouvrement -> PCM 16 bits
        st := self._state(n)
        cb := st["coef"]
        c = 0
        while c < ch:
            cb[c].write_array("f64", vecs[c])
            c += 1
        k := len(mp["coupling"]) - 1
        while k >= 0:
            cp := mp["coupling"][k]
            _nf.audio_vcouple(cb[cp[0]]._live(), cb[cp[1]]._live(), half)
            k -= 1
        tabs := self._imdct_tables(n)
        lws := 0
        ln := n // 2
        rws := n // 2
        rn := n // 2
        if long and prev_flag == 0:
            lws = n // 4 - self.bs0 // 4
            ln = self.bs0 // 2
        if long and next_flag == 0:
            rws = 3 * n // 4 - self.bs0 // 4
            rn = self.bs0 // 2
        lw := self._slope(ln)
        rw := self._slope(rn)
        cur := self.cur
        c = 0
        while c < ch:
            if floors[c] == null:
                cur[c].fill(0, 0, 8 * n)
            else:
                sub := mp["mux"][c]
                pts := self.floors[mp["floor"][sub]].points(floors[c], half)
                pb := st["pts"]
                pb.write_array("i64", pts)
                _nf.audio_vfloor(cb[c]._live(), pb._live(), len(pts) // 2, half, self.invdb._live())
                _nf.audio_imdct(cb[c]._live(), cur[c]._live(), n, tabs[0]._live(), tabs[2]._live())
                _nf.audio_vwindow(cur[c]._live(), n, lws, ln, lw._live(), rws, rn, rw._live())
            c += 1
        made := 0
        if self.prev_n > 0:
            pn := self.prev_n
            need := n // 4 + pn // 4
            self._ensure(self.at + need)
            c = 0
            while c < ch and c < self.outch:
                made = _nf.audio_voverlap(self.prev[c]._live(), cur[c]._live(), pn, n, self.out._live(), self.at, c, self.outch)
                c += 1
            self.at += made
        t := self.prev
        self.prev = self.cur
        self.cur = t
        self.prev_n = n
        return made

func _bytes_str(p, a, n):
    return _s.byte_pack(p[a:a + n])

# Décode tout le fichier avec le décodeur ALEX.
func _decode_alex(path):
    buf := _read_file(path)
    total := _final_granule(buf)
    d := Decoder(buf)
    d._ensure(total + d.bs1 if total > 0 else to_int(buf.size() * 8))
    while true:
        p := d.ogg.next()
        if p == null:
            break
        if len(p) > 0:
            d.decode_packet(p)
    buf.free()
    frames := d.at
    if total >= 0 and total < frames:
        frames = total
    out := d.out
    rate := d.rate
    outch := d.outch
    d.free()
    if frames <= 0:
        _fail("aucun échantillon décodé")
    return {"buffer": out, "frames": frames, "channels": outch, "rate": rate, "decoder": "alex"}

# ---------------------------------------------------------------------------------------------------------------------
# libvorbisfile (système)
# ---------------------------------------------------------------------------------------------------------------------

func _vorbisfile():
    names := ["libvorbisfile.so.3", "libvorbisfile.so"]
    if _os.platform() == "windows":
        names = ["vorbisfile.dll", "libvorbisfile.dll", "libvorbisfile-3.dll"]
    elif _os.platform() == "macos":
        names = ["libvorbisfile.3.dylib", "libvorbisfile.dylib"]
    for nm in names:
        try:
            return ffi.Library(nm)
        catch e:
            pass
    return null

func _decode_vorbisfile(lib, path):
    vf := ffi.Buffer(4096)
    if lib.function("ov_fopen", ["cstr", "ptr"], "i32").call2(path, vf.address()) != 0:
        vf.free()
        _fail("libvorbisfile : flux illisible '" + path + "'")
    vi := lib.function("ov_info", ["ptr", "i32"], "ptr").call2(vf.address(), -1)
    ch := ffi.peek(vi + 4, "i32")
    rate := ffi.peek(vi + 8, "i64")
    total := lib.function("ov_pcm_total", ["ptr", "i32"], "i64").call2(vf.address(), -1)
    rd := lib.function("ov_read", ["ptr", "ptr", "i32", "i32", "i32", "i32", "ptr"], "i64")
    clear := lib.function("ov_clear", ["ptr"], "i32")
    if ch < 1 or ch > 2:
        clear.call1(vf.address())
        vf.free()
        raise("ValueError", "use_alex")
    chunk := ffi.Buffer(65536)
    bs := ffi.Buffer(8)
    cap := total * ch * 2 if total > 0 else 1048576
    out := ffi.Buffer(cap)
    off := 0
    while true:
        n := rd.call([vf.address(), chunk.address(), 65536, 0, 2, 1, bs.address()])
        if n <= 0:
            break
        if off + n > cap:
            cap2 := (off + n) * 2
            o2 := ffi.Buffer(cap2)
            o2.copy_from(out, off)
            out.free()
            out = o2
            cap = cap2
        out.copy_from(chunk, n, off)
        off += n
    clear.call1(vf.address())
    vf.free()
    chunk.free()
    bs.free()
    frames := off // (ch * 2)
    if frames <= 0:
        out.free()
        _fail("aucun échantillon décodé")
    return {"buffer": out, "frames": frames, "channels": ch, "rate": rate, "decoder": "libvorbisfile"}

# ---------------------------------------------------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------------------------------------------------

# Décode un fichier .ogg en PCM 16 bits entrelacé (1 ou 2 canaux ; au-delà, les 2 premiers).
func load_pcm16(path):
    if _os.getenv("ALEX_VORBIS") != "alex":
        lib := _vorbisfile()
        if lib != null:
            try:
                return _decode_vorbisfile(lib, path)
            catch e:
                if e.message != "use_alex":
                    raise(e.type, e.message)
    return _decode_alex(path)

# Informations sans décoder : {"channels", "rate", "frames", "duration"}.
func probe(path):
    buf := _read_file(path)
    total := _final_granule(buf)
    d := Decoder(buf)
    buf.free()
    fr := total if total > 0 else 0
    return {"channels": d.channels, "rate": d.rate, "frames": fr, "duration": fr * 1.0 / d.rate}
