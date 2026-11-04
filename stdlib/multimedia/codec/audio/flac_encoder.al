# ALEX STANDARD LIBRARY — multimedia.codec.audio.flac_encoder
#
# Encodeur FLAC (RFC 9639) écrit en ALEX pur, sans perte, relu au bit près par multimedia.codec.audio.flac et par
# ffmpeg / libFLAC :
#   - métadonnées : STREAMINFO (tailles de bloc et de trame, nombre d'échantillons, MD5 du signal), VORBIS_COMMENT
#     (étiquettes) ;
#   - trames de taille fixe (4096 échantillons par défaut), numéro de trame, CRC-8 de l'en-tête, CRC-16 de la trame ;
#   - sous-trames : constante, prédicteur fixe d'ordre 0 à 4 (choisi par trame et par canal), verbatim si rien
#     n'est plus court ; bits perdus (« wasted bits », p. ex. du 16 bits rangé dans 24) ;
#   - stéréo : indépendante, gauche/côté, côté/droite ou milieu/côté, la plus courte par trame ;
#   - résidus : Rice (paramètre 4 bits) ou Rice2 (5 bits), ordre de partition choisi par trame (0 à 6).
# C'est l'équivalent de `flac -1` (pas de LPC) : typiquement 55 à 70 % de la taille du WAV pour de la musique.
#
#   use multimedia.codec.audio.flac_encoder as fe
#   octets := fe.encode([gauche, droite], 44100, 16)          # canaux d'entiers -> fichier .flac en mémoire
#   e := fe.FlacEncoder("sortie.flac", af.AudioFormat(44100, 2, "s16le"), tags)
#   e.write_samples(flottants_entrelaces)                      # ou e.write_channels([[...], [...]])
#   e.close()                                                  # complète STREAMINFO ; renvoie le nombre de trames
#   fe.write_flac("x.flac", flottants, af.CD)
#
# md5=false n'écrit pas l'empreinte (16 zéros, permis par la RFC) : le MD5 en ALEX coûte environ autant que
# l'encodage lui-même.
# Erreurs : FormatError (format, canaux, taille de bloc), StateError (écriture après close).

from core use len, type, to_int
from collections use append, keys
use io as _io
use string as _s
use crypto as _crypto
use audio.audio_format as _af
use multimedia.core.errors as merr
use multimedia.metadata.tags as tg
use multimedia.codec.audio.flac as _flac

const DEFAULT_BLOCK := 4096
const MAX_PARTITION_ORDER := 6

# ------------------------------------------------------------------------------------------- écriture de bits
class BitWriter:
    func init():
        self.out = []
        self.acc = 0
        self.n = 0

    # n bits de poids faible de v (v peut être négatif : complément à deux sur n bits).
    func bits(v, n):
        if n == 0:
            return null
        acc := (self.acc << n) | (v & ((1 << n) - 1))
        k := self.n + n
        out := self.out
        while k >= 8:
            k -= 8
            append(out, (acc >> k) & 255)
        self.acc = acc & ((1 << k) - 1)
        self.n = k

    # q zéros puis un 1.
    func unary(q):
        while q >= 24:
            self.bits(0, 24)
            q -= 24
        self.bits(1, q + 1)

    func align():
        if self.n > 0:
            self.bits(0, 8 - self.n)

    func length():
        return len(self.out)

    # Valeurs signées codées en Rice de paramètre k (boucle chaude : accumulateur local).
    func rice(values, a, z, k):
        acc := self.acc
        n := self.n
        out := self.out
        mask := (1 << k) - 1
        for i in a..z:
            v := values[i]
            u := v << 1 if v >= 0 else ((-v) << 1) - 1
            q := u >> k
            # q zéros, un 1, puis les k bits bas
            while q >= 24:
                acc = acc << 24
                n += 24
                while n >= 8:
                    n -= 8
                    append(out, (acc >> n) & 255)
                acc = acc & ((1 << n) - 1)
                q -= 24
            acc = (((acc << (q + 1)) | 1) << k) | (u & mask)
            n += q + 1 + k
            while n >= 8:
                n -= 8
                append(out, (acc >> n) & 255)
            acc = acc & ((1 << n) - 1)
        self.acc = acc
        self.n = n

# ------------------------------------------------------------------------------------------- choix du codage
# Résidus du prédicteur fixe d'ordre 0 à 4 (différences successives) : list de 5 listes, chacune de longueur
# len(x) - ordre.
func _fixed_residuals(x):
    out := [x]
    cur := x
    for order in 1..5:
        nxt := [cur[i] - cur[i - 1] for i in 1..len(cur)]
        append(out, nxt)
        cur = nxt
    return out

func _abs_sum(v):
    s := 0
    for x in v:
        s += x if x >= 0 else -x
    return s

# Paramètre de Rice pour une partition de n valeurs dont la somme repliée (2|v|) vaut s, et son coût estimé.
func _rice_param(s, n, kmax):
    if n == 0:
        return [0, 0]
    k := 0
    while k < kmax and (n << (k + 1)) < s:
        k += 1
    return [k, n * (k + 1) + (s >> k)]

# Meilleur découpage du résidu d'un prédicteur d'ordre `order` : [ordre de partition, paramètres, méthode, coût].
func _partition(res, block, order):
    pmax := 0
    while pmax < MAX_PARTITION_ORDER and block % (1 << (pmax + 1)) == 0 and (block >> (pmax + 1)) > order:
        pmax += 1
    # sommes repliées par partition au plus fin, regroupées ensuite deux à deux
    parts := 1 << pmax
    psize := block >> pmax
    sums := []
    counts := []
    j := 0
    for p in 0..parts:
        n := psize - order if p == 0 else psize
        s := 0
        for i in j..j + n:
            v := res[i]
            s += (v << 1) if v >= 0 else ((-v) << 1) - 1
        append(sums, s)
        append(counts, n)
        j += n
    best := null
    po := pmax
    while po >= 0:
        params := []
        cost := 4 + 2
        for p in 0..len(sums):
            kc := _rice_param(sums[p], counts[p], 30)
            append(params, kc[0])
            cost += 4 + kc[1]
        method := 0
        for k in params:
            if k > 14:
                method = 1
        if method == 1:
            cost += len(params)
        if best == null or cost < best[3]:
            best = [po, params, method, cost]
        if po > 0:
            sums = [sums[2 * i] + sums[2 * i + 1] for i in 0..len(sums) // 2]
            counts = [counts[2 * i] + counts[2 * i + 1] for i in 0..len(counts) // 2]
        po -= 1
    return best

# Plan d'une sous-trame : {"kind": "constant" | "verbatim" | "fixed", "order", "wasted", "bps", "bits" (coût),
# "res", "part"}.
func _plan(x, bps):
    block := len(x)
    first := x[0]
    same := true
    orall := 0
    for v in x:
        orall = orall | v
        if v != first:
            same = false
    if same:
        return {"kind": "constant", "bits": 8 + bps, "value": first, "wasted": 0, "bps": bps}
    wasted := 0
    if orall != 0:
        while (orall & 1) == 0 and wasted < bps - 1:
            orall = orall >> 1
            wasted += 1
    y := x
    eff := bps - wasted
    if wasted > 0:
        y = [v >> wasted for v in x]
    verbatim := 8 + wasted + eff * block
    res := _fixed_residuals(y)
    # ordre par la somme des valeurs absolues (estimation de libFLAC), puis découpage exact de cet ordre
    order := 0
    bestsum := -1
    for o in 0..5:
        if o >= block:
            break
        s := _abs_sum(res[o])
        if bestsum < 0 or s < bestsum:
            bestsum = s
            order = o
    r := res[order]
    part := _partition(r, block, order)
    cost := 8 + wasted + order * eff + part[3]
    if cost >= verbatim:
        return {"kind": "verbatim", "bits": verbatim, "samples": y, "wasted": wasted, "bps": eff}
    return {"kind": "fixed", "bits": cost, "order": order, "warm": [y[i] for i in 0..order], "res": r,
            "part": part, "wasted": wasted, "bps": eff}

func _write_subframe(w, plan):
    w.bits(0, 1)
    k := plan["kind"]
    if k == "constant":
        w.bits(0, 6)
        w.bits(0, 1)
        w.bits(plan["value"], plan["bps"])
        return null
    w.bits(1 if k == "verbatim" else 8 + plan["order"], 6)
    if plan["wasted"] > 0:
        w.bits(1, 1)
        w.unary(plan["wasted"] - 1)
    else:
        w.bits(0, 1)
    bps := plan["bps"]
    if k == "verbatim":
        for v in plan["samples"]:
            w.bits(v, bps)
        return null
    for v in plan["warm"]:
        w.bits(v, bps)
    part := plan["part"]
    method := part[2]
    w.bits(method, 2)
    w.bits(part[0], 4)
    res := plan["res"]
    parts := 1 << part[0]
    block := len(res) + plan["order"]
    psize := block >> part[0]
    pbits := 4 if method == 0 else 5
    j := 0
    for p in 0..parts:
        n := psize - plan["order"] if p == 0 else psize
        kp := part[1][p]
        w.bits(kp, pbits)
        w.rice(res, j, j + n, kp)
        j += n

# ------------------------------------------------------------------------------------------- en-têtes
func _block_code(n):
    if n == 192:
        return [1, 0, 0]
    for c in 2..6:
        if n == 576 << (c - 2):
            return [c, 0, 0]
    for c in 8..16:
        if n == 256 << (c - 8):
            return [c, 0, 0]
    if n <= 256:
        return [6, n - 1, 8]
    return [7, n - 1, 16]

func _rate_code(rate):
    for c in 1..12:
        if _flac.RATES[c] == rate:
            return [c, 0, 0]
    if rate % 1000 == 0 and rate // 1000 < 256:
        return [12, rate // 1000, 8]
    if rate < 65536:
        return [13, rate, 16]
    if rate % 10 == 0 and rate // 10 < 65536:
        return [14, rate // 10, 16]
    return [0, 0, 0]

func _size_code(bits):
    for c in 1..8:
        if _flac.SIZES[c] == bits:
            return c
    return 0

# Numéro de trame codé comme l'UTF-8 étendu de FLAC (jusqu'à 36 bits).
const _UTF8_LIMITS := [0x800, 0x10000, 0x200000, 0x4000000, 0x80000000]
const _UTF8_LEAD := [0xC0, 0xE0, 0xF0, 0xF8, 0xFC, 0xFE]

func _utf8_number(v):
    if v < 0x80:
        return [v]
    n := 1                                   # octets de continuation (1 à 6)
    while n <= 5 and v >= _UTF8_LIMITS[n - 1]:
        n += 1
    out := [_UTF8_LEAD[n - 1] | (v >> (6 * n))]
    for i in 0..n:
        append(out, 0x80 | ((v >> (6 * (n - 1 - i))) & 0x3F))
    return out

# Une trame complète (octets) : canaux d'entiers de même longueur.
func encode_frame(chans, number, rate, bits):
    block := len(chans[0])
    nch := len(chans)
    # stéréo : la décorrélation la plus courte (bits + 1 pour le canal « côté »)
    assignment := nch - 1
    plans := null
    if nch == 2 and bits < 32:
        l := chans[0]
        r := chans[1]
        side := [l[i] - r[i] for i in 0..block]
        mid := [(l[i] + r[i]) >> 1 for i in 0..block]
        pl := _plan(l, bits)
        pr := _plan(r, bits)
        ps := _plan(side, bits + 1)
        pm := _plan(mid, bits)
        options := [[1, [pl, pr], pl["bits"] + pr["bits"]], [8, [pl, ps], pl["bits"] + ps["bits"]],
                    [9, [ps, pr], ps["bits"] + pr["bits"]], [10, [pm, ps], pm["bits"] + ps["bits"]]]
        best := options[0]
        for o in options:
            if o[2] < best[2]:
                best = o
        assignment = best[0]
        plans = best[1]
    else:
        plans = [_plan(c, bits) for c in chans]
    w := BitWriter()
    w.bits(0x7FFC, 15)
    w.bits(0, 1)                                   # taille de bloc fixe : numéro de trame
    bc := _block_code(block)
    rc := _rate_code(rate)
    w.bits(bc[0], 4)
    w.bits(rc[0], 4)
    w.bits(assignment, 4)
    w.bits(_size_code(bits), 3)
    w.bits(0, 1)
    for b in _utf8_number(number):
        w.bits(b, 8)
    if bc[2] > 0:
        w.bits(bc[1], bc[2])
    if rc[2] > 0:
        w.bits(rc[1], rc[2])
    append(w.out, _flac.crc8(w.out, 0, len(w.out)))     # en-tête aligné sur l'octet : CRC-8 juste après
    for p in plans:
        _write_subframe(w, p)
    w.align()
    crc := _flac.crc16(w.out, 0, len(w.out))
    append(w.out, (crc >> 8) & 255)
    append(w.out, crc & 255)
    return w.out

# ------------------------------------------------------------------------------------------- métadonnées
func _be(v, n):
    return [(v >> (8 * (n - 1 - i))) & 255 for i in 0..n]

func _le32(v):
    return [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]

func streaminfo(rate, channels, bits, min_block, max_block, min_frame, max_frame, total, md5):
    out := _be(min_block, 2) + _be(max_block, 2) + _be(min_frame, 3) + _be(max_frame, 3)
    x := (rate << 44) | ((channels - 1) << 41) | ((bits - 1) << 36) | (total & 0xFFFFFFFFF)
    out = out + _be(x, 8) + (md5 if md5 != null else [0 for i in 0..16])
    return out

func _vorbis_comment(tags):
    vendor := _s.byte_unpack("ALEX multimedia")
    out := _le32(len(vendor)) + vendor
    items := []
    if tags != null:
        # noms Vorbis (track -> TRACKNUMBER...) ; clés sans équivalent gardées telles quelles
        named := tags.to_format("vorbis")
        for k in keys(named):
            append(items, _s.byte_unpack(_s.upper(k) + "=" + str(named[k])))
        mapped := tg.FORMATS["vorbis"]
        for k in keys(tags.values):
            if not (k in mapped):
                append(items, _s.byte_unpack(_s.upper(k) + "=" + str(tags.values[k])))
    out = out + _le32(len(items))
    for it in items:
        out = out + _le32(len(it)) + it
    return out

func _block_header(btype, size, last):
    return [(128 if last else 0) | btype] + _be(size, 3)

# En-tête du fichier : « fLaC », STREAMINFO, VORBIS_COMMENT. STREAMINFO commence à l'octet 8.
func header(rate, channels, bits, block, tags=null, info=null):
    si := info if info != null else streaminfo(rate, channels, bits, block, block, 0, 0, 0, null)
    vc := _vorbis_comment(tags)
    return _s.byte_unpack("fLaC") + _block_header(0, 34, false) + si + _block_header(4, len(vc), true) + vc

# ------------------------------------------------------------------------------------------- encodeur
func _check(rate, channels, bits, block):
    if channels < 1 or channels > 8:
        merr.fail(merr.FORMAT, "FLAC : " + str(channels) + " canaux (1 à 8)")
    if bits < 4 or bits > 32:
        merr.fail(merr.FORMAT, "FLAC : " + str(bits) + " bits par échantillon (4 à 32)")
    if rate < 1 or rate > 1048575:
        merr.fail(merr.FORMAT, "FLAC : fréquence " + str(rate) + " Hz hors limites")
    if block < 16 or block > 65535:
        merr.fail(merr.FORMAT, "FLAC : taille de bloc " + str(block) + " (16 à 65535)")

# Bits par échantillon d'un format audio.audio_format (f32le -> 24 bits).
func bits_of(fmt):
    f := _af.named(fmt)
    sf := f.sample_format
    if sf == "u8":
        return 8
    if sf == "s16le":
        return 16
    if sf == "s24le" or sf == "f32le":
        return 24
    if sf == "s32le":
        return 32
    merr.fail(merr.FORMAT, "FLAC : format d'échantillon « " + str(sf) + " » non pris en charge")

# Flottants entrelacés (-1..1) -> canaux d'entiers sur `bits` bits (arrondis, écrêtés).
func from_float(samples, channels, bits):
    scale := 1 << (bits - 1)
    hi := scale - 1
    lo := -scale
    n := len(samples) // channels
    chans := [[] for c in 0..channels]
    k := 0
    for i in 0..n:
        for c in 0..channels:
            v := to_int(samples[k] * scale + (0.5 if samples[k] >= 0 else -0.5))
            if v > hi:
                v = hi
            elif v < lo:
                v = lo
            append(chans[c], v)
            k += 1
    return chans

# Format audio.audio_format d'une description [fréquence, canaux, bits] ou d'un AudioFormat : [AudioFormat, bits].
func _format(fmt):
    if type(fmt) == "list":
        bits := fmt[2]
        sf := "u8" if bits <= 8 else ("s16le" if bits <= 16 else ("s24le" if bits <= 24 else "s32le"))
        return [_af.AudioFormat(fmt[0], fmt[1], sf), bits]
    f := _af.named(fmt)
    return [f, bits_of(f)]

# Cœur commun aux écrivains FLAC et Ogg FLAC : découpe en blocs, trames numérotées, MD5 du signal, tailles min / max.
class FrameEncoder:
    func init(rate, channels, bits, block_size=DEFAULT_BLOCK, md5=true):
        _check(rate, channels, bits, block_size)
        self.rate = rate
        self.channels = channels
        self.bits = bits
        self.block = block_size
        self.pending = [[] for c in 0..channels]
        self.frames = 0
        self.samples = 0
        self.min_frame = 0
        self.max_frame = 0
        self.md5 = _crypto.Md5() if md5 else null
        self.width = (bits + 7) // 8

    func _frame(chans):
        n := len(chans[0])
        if self.md5 != null:
            buf := []
            width := self.width
            for i in 0..n:
                for c in chans:
                    v := c[i]
                    for k in 0..width:
                        append(buf, (v >> (8 * k)) & 255)
            self.md5.update(buf)
        data := encode_frame(chans, self.frames, self.rate, self.bits)
        size := len(data)
        if self.min_frame == 0 or size < self.min_frame:
            self.min_frame = size
        if size > self.max_frame:
            self.max_frame = size
        self.frames += 1
        self.samples += n
        return [data, n]

    # Ajoute des canaux d'entiers ; renvoie les trames complètes : list de [octets, échantillons].
    func add(chans):
        if len(chans) != self.channels:
            merr.fail(merr.FORMAT, "FLAC : " + str(len(chans)) + " canaux pour un flux à " + str(self.channels))
        for c in 0..self.channels:
            for v in chans[c]:
                append(self.pending[c], v)
        out := []
        b := self.block
        n := len(self.pending[0])
        start := 0
        while n - start >= b:
            append(out, self._frame([p[start:start + b] for p in self.pending]))
            start += b
        if start > 0:
            self.pending = [p[start:] for p in self.pending]
        return out

    # Dernière trame (plus courte), s'il reste des échantillons.
    func finish():
        out := []
        if len(self.pending[0]) > 0:
            append(out, self._frame(self.pending))
            self.pending = [[] for c in 0..self.channels]
        return out

    # STREAMINFO (34 octets) d'après ce qui a été encodé.
    func info():
        md5 := self.md5.digest() if self.md5 != null else null
        return streaminfo(self.rate, self.channels, self.bits, self.block, self.block, self.min_frame, self.max_frame, self.samples, md5)

# Base des écrivains (FlacEncoder, container.ogg_mux.OggFlacMuxer) : flottants, octets PCM, Frame.
class FlacWriter:
    func _setup(fmt, block_size, md5):
        fb := _format(fmt)
        self.format = fb[0]
        self.rate = self.format.rate
        self.channels = self.format.channels
        self.bits = fb[1]
        self.core = FrameEncoder(self.rate, self.channels, self.bits, block_size, md5)
        self.closed = false

    func _alive():
        if self.closed:
            merr.state("encodeur FLAC fermé")

    # À redéfinir : reçoit les trames complètes ([octets, échantillons]).
    func _put(frames):
        return null

    # Canaux d'entiers (une liste par canal, même longueur).
    func write_channels(chans):
        self._alive()
        self._put(self.core.add(chans))
        return len(chans[0])

    # Flottants entrelacés -1..1.
    func write_samples(samples):
        if len(samples) % self.channels != 0:
            merr.fail(merr.FORMAT, str(len(samples)) + " échantillons : pas un nombre entier de trames")
        return self.write_channels(from_float(samples, self.channels, self.bits))

    # Octets PCM du format donné à l'ouverture (même interface que container.mux.WavMuxer).
    func write_bytes(data):
        return self.write_samples(_af.decode(data, self.format))

    func write_packet(p):
        if p.eos:
            return 0
        return self.write_bytes(p.data)

    func write_frame(f):
        if f.eos:
            return 0
        s := f.data
        if f.format.channels != self.channels:
            s = _af.convert_channels(s, f.format.channels, self.channels)
        if f.format.rate != self.rate:
            s = _af.resample(s, f.format.rate, self.rate, self.channels)
        return self.write_samples(s)

    func frames():
        return self.core.frames

    func samples():
        return self.core.samples

    func duration():
        return 1.0 * self.core.samples / self.rate

class FlacEncoder extends FlacWriter:
    # path : fichier écrit progressivement ; fmt : AudioFormat (bits d'après le format d'échantillon) ou
    # [fréquence, canaux, bits] ; tags : multimedia.metadata.tags.Tags.
    func init(path, fmt, tags=null, block_size=DEFAULT_BLOCK, md5=true):
        self._setup(fmt, block_size, md5)
        self.path = path
        self.tags = tags if tags != null else tg.Tags()
        _io.write_bytes(path, header(self.rate, self.channels, self.bits, block_size, self.tags))

    func _put(frames):
        for f in frames:
            _io.write_bytes_at(self.path, f[0], null)

    # Dernière trame (plus courte), puis STREAMINFO définitif (octet 8). Renvoie le nombre de trames écrites.
    func close():
        if self.closed:
            return self.core.frames
        self._put(self.core.finish())
        _io.write_bytes_at(self.path, self.core.info(), 8)
        self.closed = true
        return self.core.frames

# Fichier FLAC complet en mémoire (octets) depuis des canaux d'entiers.
func encode(chans, rate, bits, block_size=DEFAULT_BLOCK, tags=null, md5=true):
    core := FrameEncoder(rate, len(chans), bits, block_size, md5)
    frames := core.add(chans) + core.finish()
    out := header(rate, len(chans), bits, block_size, tags, core.info())
    for f in frames:
        out = out + f[0]
    return out

# Écrit d'un coup des flottants entrelacés dans un FLAC ; renvoie le nombre de trames.
func write_flac(path, samples, fmt, tags=null, md5=true):
    e := FlacEncoder(path, fmt, tags, DEFAULT_BLOCK, md5)
    e.write_samples(samples)
    return e.close()
