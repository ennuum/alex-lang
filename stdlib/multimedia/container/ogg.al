# ALEX STANDARD LIBRARY — multimedia.container.ogg
#
# Conteneur Ogg (RFC 3533), pour des fichiers NON FIABLES :
#   - pages : capture « OggS », CRC-32 Ogg vérifié, table de segments, positions de granule, drapeaux
#     début / suite / fin de flux ; RESYNCHRONISATION sur la page valide suivante en cas de corruption
#     (avertissement) ;
#   - paquets : réassemblage des segments, y compris à cheval sur plusieurs pages ; flux logiques multiplexés ;
#   - identification des flux par leur premier paquet : FLAC (« \x7FFLAC »), Vorbis, Opus, Theora, Speex ;
#     étiquettes (commentaires Vorbis : Vorbis, Opus, FLAC, Theora) ; durée exacte par la dernière granule
#     (Opus : moins le pre-skip ; Theora : granule décomposée image clé / décalage) ;
#   - OggDemuxer : interface des démultiplexeurs (info, format, read_frame, read_packet, seek, close).
#     L'Ogg FLAC est DÉCODÉ (multimedia.codec.audio.flac) ; pour Vorbis, Opus, Speex et Theora, read_packet donne
#     les paquets bruts (avec granule) et read_frame lève UnsupportedError : aucun décodeur n'est simulé.
#     Recherche : dichotomie sur les granules, puis décodage jusqu'à l'échantillon exact.
#
#   use multimedia.container.ogg as ogg
#   d := ogg.OggDemuxer("musique.oga")
#   print(d.info.describe(), [s.codec for s in d.info.streams])
#   d.seek(30.0)
#   f := d.read_frame(4096)
#   v := ogg.OggDemuxer("film.ogv", null, 1)    # choisit la piste 1 (paquets bruts)
#   p := v.read_packet()                         # Packet : octets, granule dans p.duration... voir read_packet
#
# Erreurs : CorruptDataError, UnsupportedError, LimitError, StateError, MediaError.

from core use len, to_int
from collections use append, keys
use io as _io
use os as _os
use string as _s
use audio.audio_format as _af
use multimedia.core.errors as merr
use multimedia.core.timestamp as ts
use multimedia.core.buffer as mb
use multimedia.core.stream as ms
use multimedia.core.format as mf
use multimedia.security.limits as lim
use multimedia.codec.audio.flac as flac
use multimedia.metadata.tags as tg

const MAX_PAGE := 65307
const WINDOW := 131072
const MAX_WARNINGS := 20

# ------------------------------------------------------------------------------------------- CRC-32 Ogg
func _crc_table():
    t := []
    for i in 0..256:
        c := i << 24
        for k in 0..8:
            if (c & 0x80000000) != 0:
                c = ((c << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
            else:
                c = (c << 1) & 0xFFFFFFFF
        append(t, c)
    return t

CRC := _crc_table()

# CRC d'une page [a, z) dont le champ CRC (octets 22..25) est compté comme nul.
func page_crc(b, a, z):
    c := 0
    for k in a..z:
        x := b[k]
        if k >= a + 22 and k < a + 26:
            x = 0
        c = ((c << 8) & 0xFFFFFFFF) ^ CRC[((c >> 24) ^ x) & 255]
    return c

func _u32le(b, at):
    return b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)

func _u16le(b, at):
    return b[at] | (b[at + 1] << 8)

func _s64le(b, at):
    v := 0
    for k in 0..8:
        v = v | (b[at + k] << (8 * k))
    return v

func _is(b, at, text):
    t := _s.byte_unpack(text)
    if at + len(t) > len(b):
        return false
    for k in 0..len(t):
        if b[at + k] != t[k]:
            return false
    return true

# Page complète et valide à `at` dans b : dict, ou null (capture absente, tronquée, CRC faux -> raison dans "error").
func parse_page(b, at):
    if at + 27 > len(b) or b[at] != 79 or b[at + 1] != 103 or b[at + 2] != 103 or b[at + 3] != 83:
        return {"error": "capture OggS absente"}
    if b[at + 4] != 0:
        return {"error": "version de page " + str(b[at + 4])}
    nseg := b[at + 26]
    if at + 27 + nseg > len(b):
        return {"error": "tronquée"}
    segs := [b[at + 27 + i] for i in 0..nseg]
    body := 0
    for x in segs:
        body += x
    end := at + 27 + nseg + body
    if end > len(b):
        return {"error": "tronquée"}
    crc := _u32le(b, at + 22)
    if page_crc(b, at, end) != crc:
        return {"error": "CRC faux"}
    gl := _u32le(b, at + 6)
    gh := _u32le(b, at + 10)
    granule := -1 if (gl == 0xFFFFFFFF and gh == 0xFFFFFFFF) else (gh << 32) | gl
    flags := b[at + 5]
    return {"error": null, "pos": at, "end": end, "flags": flags, "continued": (flags & 1) != 0,
            "bos": (flags & 2) != 0, "eos": (flags & 4) != 0, "granule": granule, "serial": _u32le(b, at + 14),
            "seq": _u32le(b, at + 18), "segments": segs, "body": at + 27 + nseg}

# ------------------------------------------------------------------------------------------- lecture de pages
class PageReader:
    func init(path, size, start=0):
        self.path = path
        self.size = size
        self.pos = start
        self.buf = []
        self.buf_off = 0
        self.warnings = []
        self.skipped = 0

    func _window(pos):
        if pos >= self.buf_off and pos + MAX_PAGE <= self.buf_off + len(self.buf):
            return
        if pos >= self.buf_off and self.buf_off + len(self.buf) >= self.size and pos < self.buf_off + len(self.buf):
            return
        n := WINDOW
        if pos + n > self.size:
            n = self.size - pos
        self.buf = _io.read_bytes(self.path, pos, n) if n > 0 else []
        self.buf_off = pos

    func _warn(m):
        if len(self.warnings) < MAX_WARNINGS:
            append(self.warnings, m)

    func seek(pos):
        self.pos = pos

    # Page suivante (dict, avec "data" : octets du corps), ou null en fin de fichier.
    func next():
        while self.pos + 27 <= self.size:
            self._window(self.pos)
            rel := self.pos - self.buf_off
            p := parse_page(self.buf, rel)
            if p["error"] == null:
                p["data"] = [self.buf[k] for k in p["body"]..p["end"]]
                p["pos"] = self.pos
                p["end"] = self.buf_off + p["end"]
                self.pos = p["end"]
                return p
            if p["error"] == "tronquée" and self.buf_off + len(self.buf) >= self.size:
                self._warn("dernière page tronquée à l'octet " + str(self.pos) + " (ignorée)")
                self.pos = self.size
                return null
            # resynchronisation : prochaine capture « OggS »
            start := self.pos
            self.pos += 1
            found := false
            while self.pos + 4 <= self.size:
                self._window(self.pos)
                r := self.pos - self.buf_off
                lim_ := len(self.buf) - 4
                while r <= lim_:
                    if self.buf[r] == 79 and self.buf[r + 1] == 103 and self.buf[r + 2] == 103 and self.buf[r + 3] == 83:
                        found = true
                        break
                    r += 1
                self.pos = self.buf_off + r
                if found or self.buf_off + len(self.buf) >= self.size:
                    break
            self.skipped += self.pos - start
            self._warn("page invalide à l'octet " + str(start) + " (" + p["error"] + ") : " + str(self.pos - start) + " octets ignorés")
            if not found:
                self.pos = self.size
        return null

# ------------------------------------------------------------------------------------------- flux logiques
func _comments(b, at, what):
    t := tg.Tags()
    if at + 4 > len(b):
        return t
    vl := _u32le(b, at)
    q := at + 4 + vl
    if q + 4 > len(b):
        return t
    n := _u32le(b, q)
    q += 4
    for i in 0..n:
        if q + 4 > len(b):
            break
        cl := _u32le(b, q)
        if q + 4 + cl > len(b):
            break
        kv := _s.byte_pack([b[k] for k in q + 4..q + 4 + cl])
        eq := _s.find(kv, "=")
        if eq > 0:
            t.set(_s.substring(kv, 0, eq), _s.substring(kv, eq + 1, len(kv)))
        q += 4 + cl
    return t

class LogicalStream:
    func init(serial, index):
        self.serial = serial
        self.index = index
        self.codec = "inconnu"
        self.kind = "data"
        self.headers = []
        self.header_count = 0
        self.rate = null
        self.channels = null
        self.preskip = 0
        self.width = null
        self.height = null
        self.fps_num = null
        self.fps_den = null
        self.kfshift = 0
        self.flac_meta = null
        self.tags = tg.Tags()
        self.last_granule = -1
        self.partial = []

    func identify(p):
        if len(p) >= 13 and p[0] == 0x7F and _is(p, 1, "FLAC") and _is(p, 9, "fLaC"):
            self.codec = "flac"
            self.kind = "audio"
            self.header_count = (p[7] << 8) | p[8]
        elif len(p) >= 30 and p[0] == 1 and _is(p, 1, "vorbis"):
            self.codec = "vorbis"
            self.kind = "audio"
            self.channels = p[11]
            self.rate = _u32le(p, 12)
            self.header_count = 3
        elif len(p) >= 19 and _is(p, 0, "OpusHead"):
            self.codec = "opus"
            self.kind = "audio"
            self.channels = p[9]
            self.preskip = _u16le(p, 10)
            self.rate = 48000
            self.input_rate = _u32le(p, 12)
            self.header_count = 2
        elif len(p) >= 42 and p[0] == 0x80 and _is(p, 1, "theora"):
            self.codec = "theora"
            self.kind = "video"
            self.width = (p[14] << 16) | (p[15] << 8) | p[16]
            self.height = (p[17] << 16) | (p[18] << 8) | p[19]
            self.fps_num = (p[22] << 24) | (p[23] << 16) | (p[24] << 8) | p[25]
            self.fps_den = (p[26] << 24) | (p[27] << 16) | (p[28] << 8) | p[29]
            self.kfshift = ((p[40] & 3) << 3) | (p[41] >> 5)
            self.header_count = 3
        elif len(p) >= 80 and _is(p, 0, "Speex   "):
            self.codec = "speex"
            self.kind = "audio"
            self.rate = _u32le(p, 36)
            self.channels = _u32le(p, 48)
            self.header_count = 2 + _u32le(p, 68)
        elif len(p) >= 8 and _is(p, 0, "fishead"):
            self.codec = "skeleton"
            self.kind = "data"
        self.headers = [p]

    # Paquet d'en-tête supplémentaire (commentaires, métadonnées FLAC...).
    func add_header(p):
        append(self.headers, p)
        if self.codec == "vorbis" and len(p) > 7 and p[0] == 3 and _is(p, 1, "vorbis"):
            self.tags.update(_comments(p, 7, "Vorbis"))
        elif self.codec == "opus" and _is(p, 0, "OpusTags"):
            self.tags.update(_comments(p, 8, "Opus"))
        elif self.codec == "theora" and len(p) > 7 and p[0] == 0x81:
            self.tags.update(_comments(p, 7, "Theora"))
        elif self.codec == "speex" and len(self.headers) == 2:
            self.tags.update(_comments(p, 0, "Speex"))

    func headers_done():
        if self.codec == "flac":
            return self.header_count > 0 and len(self.headers) >= 1 + self.header_count
        if self.header_count == 0:
            return true
        return len(self.headers) >= self.header_count

    # Premier paquet audio FLAC (si le nombre d'en-têtes était inconnu : trame commençant par la synchronisation).
    func is_flac_frame(p):
        return len(p) >= 2 and p[0] == 255 and (p[1] & 0xFE) == 0xF8

    func finish_flac(limits):
        first := self.headers[0]
        meta := _s.byte_unpack("fLaC") + [first[k] for k in 13..len(first)]
        for h in [self.headers[k] for k in 1..len(self.headers)]:
            meta = meta + h
        # drapeau « dernier bloc » sur le dernier en-tête
        at := 4
        last_at := 4
        while at + 4 <= len(meta):
            last_at = at
            size := (meta[at + 1] << 16) | (meta[at + 2] << 8) | meta[at + 3]
            meta[at] = meta[at] & 127
            at += 4 + size
        meta[last_at] = meta[last_at] | 128
        self.flac_meta = flac.read_header(meta + [0, 0], limits)
        self.rate = self.flac_meta["rate"]
        self.channels = self.flac_meta["channels"]
        self.tags.update(self.flac_meta["tags"])

    # Durée (secondes) d'après une granule.
    func granule_seconds(g):
        if g < 0:
            return null
        if self.codec == "opus":
            v := g - self.preskip
            return (1.0 * v / 48000) if v > 0 else 0.0
        if self.codec == "theora":
            frames := (g >> self.kfshift) + (g & ((1 << self.kfshift) - 1))
            if self.fps_num == null or self.fps_num == 0:
                return null
            return 1.0 * frames * self.fps_den / self.fps_num
        if self.rate == null or self.rate == 0:
            return null
        return 1.0 * g / self.rate

# ------------------------------------------------------------------------------------------- démultiplexeur
class OggDemuxer:
    func init(path, limits=null, stream=null):
        self.limits = lim.of(limits)
        self.path = path
        self.closed = false
        if not _os.isfile(path):
            merr.fail(merr.MEDIA, "fichier introuvable : " + str(path))
        self.size = _os.size(path)
        self.limits.check_file_size(self.size)
        self.streams_by_serial = {}
        self.order = []
        self.reader = PageReader(path, self.size)
        self.queue = []
        self._scan_headers()
        self._scan_durations()
        self._build_info()
        self.selected = self._choose(stream)
        sel := self.selected
        self.format = self.info.streams[sel.index].format if sel.kind == "audio" else null
        self.tags = tg.Tags(self.info.tags)        # comme les autres démultiplexeurs (transcode les recopie)
        self.frames = 0
        if sel.codec == "flac":
            self.frames = sel.flac_meta["samples"]
        elif sel.kind == "audio" and sel.last_granule >= 0:
            self.frames = sel.last_granule - sel.preskip if sel.codec == "opus" else sel.last_granule
        self.pending = []
        self.pending_start = 0
        self.pos_frames = 0
        self.ended = false
        self.skip_continued = false
        self.bisect_min = 2 * MAX_PAGE      # en deçà : lecture linéaire
        self.bisect_steps = 0

    func _scan_headers():
        # pages de début : tous les flux (BOS), puis leurs en-têtes ; les paquets de données lus au passage sont
        # mis de côté pour la lecture
        self.data_start = null
        pages := 0
        while true:
            p := self.reader.next()
            if p == null:
                break
            pages += 1
            if pages > 10000:
                merr.corrupt("Ogg", "en-têtes interminables")
            st := null
            if p["serial"] in self.streams_by_serial:
                st = self.streams_by_serial[p["serial"]]
            elif p["bos"] or len(self.order) == 0:
                st = LogicalStream(p["serial"], len(self.order))
                self.streams_by_serial[p["serial"]] = st
                append(self.order, st)
                self.limits.check("max_streams", len(self.order))
            else:
                continue
            for pk in self._packets(st, p):
                if len(st.headers) == 0:
                    st.identify(pk[0])
                elif not st.headers_done() and not (st.codec == "flac" and st.is_flac_frame(pk[0])):
                    st.add_header(pk[0])
                else:
                    if self.data_start == null:
                        self.data_start = p["pos"]
                    append(self.queue, [st.serial, pk[0], pk[1], pk[2]])
            done := true
            for s in self.order:
                if not s.headers_done():
                    done = false
            if done and not p["bos"]:
                break
        if len(self.order) == 0:
            merr.corrupt("Ogg", "aucune page valide")
        if self.data_start == null:
            self.data_start = self.reader.pos
        for s in self.order:
            if s.codec == "flac":
                s.finish_flac(self.limits)

    # Paquets complets d'une page pour un flux : [octets, granule si dernier paquet de la page sinon -1, position page].
    func _packets(st, p):
        out := []
        data := p["data"]
        if not p["continued"]:
            if len(st.partial) > 0:
                self.reader._warn("paquet incomplet abandonné (flux " + str(st.serial) + ")")
            st.partial = []
        elif self.skip_continued:
            st.partial = null
        at := 0
        segs := p["segments"]
        nseg := len(segs)
        for i in 0..nseg:
            n := segs[i]
            if st.partial != null:
                for k in at..at + n:
                    append(st.partial, data[k])
                self.limits.check("max_chunk_bytes", len(st.partial))
            at += n
            if n < 255:
                if st.partial != null:
                    last := true
                    for j in i + 1..nseg:
                        if segs[j] < 255:
                            last = false
                    append(out, [st.partial, p["granule"] if last else -1, p["pos"]])
                st.partial = []
        self.skip_continued = false
        if p["granule"] >= 0:
            st.last_granule = p["granule"]
        return out

    func _scan_durations():
        # dernière granule de chaque flux : pages de fin du fichier
        n := 65536
        while true:
            start := self.size - n if self.size > n else 0
            rd := PageReader(self.path, self.size, start)
            # se placer sur une capture
            found := {}
            while true:
                p := rd.next()
                if p == null:
                    break
                if p["serial"] in self.streams_by_serial and p["granule"] >= 0:
                    found[p["serial"]] = p["granule"]
            for k in keys(found):
                self.streams_by_serial[k].last_granule = found[k]
            missing := false
            for s in self.order:
                if s.kind != "data" and not (s.serial in found):
                    missing = true
            if not missing or start == 0 or n >= 16777216:
                break
            n = n * 4

    func _build_info():
        self.info = ms.MediaInfo(self.path, "ogg", self.size)
        self.info.mime = "audio/ogg"
        all_tags := tg.Tags()
        for s in self.order:
            fmt := null
            if s.kind == "audio" and s.rate != null and s.channels != null and s.channels > 0:
                try:
                    sf := "s16le"
                    if s.codec == "flac":
                        sf = flac_sample_format(s.flac_meta["bits"])
                    fmt = _af.AudioFormat(s.rate, s.channels, sf)
                catch e:
                    self.info.warn("piste " + str(s.index) + " : format audio inhabituel (" + e.message + ")")
            elif s.kind == "video" and s.width != null and s.width > 0 and s.height > 0:
                fn := s.fps_num if s.fps_num != null and s.fps_num > 0 else 25
                fd := s.fps_den if s.fps_den != null and s.fps_den > 0 else 1
                self.limits.check_dimensions(s.width, s.height)
                fmt = mf.VideoFormat(s.width, s.height, "yuv420p", fn, fd)
                self.info.mime = "video/ogg"
            base := ts.for_rate(s.rate) if s.kind == "audio" and s.rate != null and s.rate > 0 else ts.MILLIS
            info := ms.StreamInfo(s.index, s.kind, s.codec, fmt, base)
            info.duration = s.granule_seconds(s.last_granule)
            info.decodable = s.codec == "flac"
            self.info.add_stream(info)
            all_tags.merge_missing(s.tags)
            if s.kind == "audio" and s.codec != "flac":
                self.info.warn(s.codec + " : en-têtes et étiquettes lus, décodage non pris en charge ici (paquets bruts disponibles)")
            elif s.kind == "video":
                self.info.warn(s.codec + " : vidéo décrite, décodage non pris en charge ici")
        self.info.tags = all_tags.to_dict()
        for w in self.reader.warnings:
            self.info.warn(w)

    func _choose(stream):
        if stream != null:
            if stream < 0 or stream >= len(self.order):
                merr.fail(merr.FORMAT, "piste " + str(stream) + " inexistante (" + str(len(self.order)) + " pistes)")
            return self.order[stream]
        for s in self.order:
            if s.codec == "flac":
                return s
        for s in self.order:
            if s.kind == "audio":
                return s
        return self.order[0]

    func _alive():
        if self.closed:
            merr.state("démultiplexeur fermé : " + self.path)

    func stream():
        return self.selected

    func _decodable():
        if self.selected.codec != "flac":
            merr.unsupported("décodage " + self.selected.codec, "paquets bruts disponibles par read_packet()")

    # Prochain paquet de données de la piste choisie : [octets, granule, position de page] ou null.
    func _next_packet():
        while true:
            for i in 0..len(self.queue):
                q := self.queue[i]
                if q[0] == self.selected.serial:
                    self.queue = [self.queue[k] for k in 0..len(self.queue) if k != i]
                    return [q[1], q[2], q[3]]
            self.queue = []
            if self.ended:
                return null
            p := self.reader.next()
            if p == null:
                self.ended = true
                for w in self.reader.warnings:
                    if not (w in self.info.warnings):
                        self.info.warn(w)
                return null
            if not (p["serial"] in self.streams_by_serial):
                continue
            st := self.streams_by_serial[p["serial"]]
            for pk in self._packets(st, p):
                append(self.queue, [st.serial, pk[0], pk[1], pk[2]])

    # Paquet brut : Packet(octets), pts = début (FLAC : premier échantillon ; autres : granule de fin de page
    # rapportée en pts quand le paquet termine la page, sinon -1 dans meta), duration = nombre d'échantillons (FLAC).
    func read_packet(frames=null):
        self._alive()
        r := self._next_packet()
        if r == null:
            return mb.end_of_stream(self.selected.index)
        s := self.selected
        if s.codec == "flac":
            fr := flac.parse_frame_header(r[0], 0, s.flac_meta)[0]
            return mb.Packet(s.index, r[0], ts.Timestamp(fr["first_sample"], ts.for_rate(s.rate)), fr["block"], true)
        p := mb.Packet(s.index, r[0], ts.Timestamp(r[1] if r[1] >= 0 else 0, ts.for_rate(s.rate) if s.rate != null and s.rate > 0 else ts.MILLIS), 0, true)
        p.granule = r[1]
        return p

    func _decode_next():
        r := self._next_packet()
        if r == null:
            return null
        s := self.selected
        res := flac.decode_frame(r[0], 0, s.flac_meta)
        chans := res[0]
        first := res[2]["first_sample"]
        total := s.flac_meta["samples"]
        n := len(chans[0])
        if total > 0 and first + n > total:
            n = total - first if total > first else 0
            chans = [[ch[i] for i in 0..n] for ch in chans]
        return [chans, first]

    func read_frame(frames=4096):
        self._alive()
        self._decodable()
        ch := self.selected.channels
        want := frames * ch
        bits := self.selected.flac_meta["bits"]
        while len(self.pending) < want:
            r := self._decode_next()
            if r == null:
                break
            if len(self.pending) == 0:
                self.pending_start = r[1]
            for x in flac.to_float(r[0], bits):
                append(self.pending, x)
        if len(self.pending) == 0:
            return mb.end_frame("audio")
        take := want if want < len(self.pending) else len(self.pending)
        out := [self.pending[k] for k in 0..take]
        self.pending = [self.pending[k] for k in take..len(self.pending)]
        start := self.pending_start
        self.pending_start = start + take // ch
        self.pos_frames = self.pending_start
        return mb.audio_frame(out, self.format, ts.Timestamp(start, ts.for_rate(self.selected.rate)))

    func read_all(max_frames=null):
        self._decodable()
        out := []
        left := max_frames
        if left == null and self.frames > 0:
            left = self.frames - self.pos_frames
        if left != null:
            self.limits.check("max_decoded_bytes", left * self.selected.channels * 8)
        while left == null or left > 0:
            f := self.read_frame(65536 if left == null or left > 65536 else left)
            if f.eos:
                break
            for x in f.data:
                append(out, x)
            if left != null:
                left -= f.frames()
        return out

    func duration():
        return self.info.streams[self.selected.index].duration

    func tell():
        if self.selected.rate == null:
            return 0.0
        return 1.0 * self.pos_frames / self.selected.rate

    func at_end():
        return len(self.pending) == 0 and self.ended and len(self.queue) == 0

    # Première page (à partir de pos) de la piste choisie qui porte une granule : [position, granule] ou null.
    func _page_at(pos):
        rd := PageReader(self.path, self.size, pos)
        n := 0
        while n < 64:
            p := rd.next()
            if p == null:
                return null
            n += 1
            if p["serial"] == self.selected.serial and p["granule"] >= 0:
                return [p["pos"], p["granule"]]
        return null

    func seek(seconds):
        self._alive()
        self._decodable()
        target := to_int(seconds * self.selected.rate + 0.5)
        if target < 0:
            target = 0
        if self.frames > 0 and target > self.frames:
            target = self.frames
        # dichotomie : dernière page dont la granule (fin) est < cible
        lo := self.data_start
        hi := self.size
        while hi - lo > self.bisect_min:
            mid := (lo + hi) // 2
            self.bisect_steps += 1
            pg := self._page_at(mid)
            if pg == null or pg[1] >= target:
                hi = mid
            else:
                lo = pg[0]
        self.reader = PageReader(self.path, self.size, lo)
        self.queue = []
        self.pending = []
        self.ended = false
        self.selected.partial = []
        self.skip_continued = true
        while true:
            r := self._decode_next()
            if r == null:
                self.pos_frames = target
                self.pending_start = target
                return self.tell()
            first := r[1]
            n := len(r[0][0])
            if first + n > target:
                skip := target - first
                if skip < 0:
                    skip = 0
                self.pending = flac.to_float([[c[i] for i in skip..n] for c in r[0]], self.selected.flac_meta["bits"])
                self.pending_start = first + skip
                self.pos_frames = first + skip
                return self.tell()

    func close():
        self.closed = true
        self.queue = []
        self.pending = []

func flac_sample_format(bits):
    if bits <= 8:
        return "u8"
    if bits <= 16:
        return "s16le"
    if bits <= 24:
        return "s24le"
    return "s32le"
