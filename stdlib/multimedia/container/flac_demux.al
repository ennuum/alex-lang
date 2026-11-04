# ALEX STANDARD LIBRARY — multimedia.container.flac_demux
#
# Démultiplexeur FLAC natif (fichiers .flac) : même interface que WavDemuxer (info, format, frames, read_frame,
# read_packet, read_all, seek, tell, close). Le fichier est lu PAR FENÊTRES (jamais chargé en entier) ; chaque
# trame est décodée par multimedia.codec.audio.flac avec contrôle des CRC. Recherche : point le plus proche de la
# SEEKTABLE puis décodage jusqu'à l'échantillon exact (sans table : depuis la première trame).
# Un fichier tronqué s'arrête à la dernière trame complète, avec un avertissement.
#
#   use multimedia.container.flac_demux as fdx
#   d := fdx.FlacDemuxer("musique.flac")
#   print(d.format.describe(), d.duration(), d.tags.get("title"))
#   d.seek(42.0)
#   f := d.read_frame(4096)                  # Frame audio (flottants), pts exact
#   p := d.read_packet()                     # Packet : une trame FLAC encodée (octets), pts, durée
#
# Erreurs : CorruptDataError, LimitError, StateError (après close), MediaError (fichier absent).

from core use len, to_int
from collections use append
use io as _io
use os as _os
use string as _s
use audio.audio_format as _af
use multimedia.core.errors as merr
use multimedia.core.timestamp as ts
use multimedia.core.buffer as mb
use multimedia.core.stream as ms
use multimedia.security.limits as lim
use multimedia.codec.audio.flac as flac
use multimedia.metadata.tags as tg

const WINDOW := 262144

func sample_format_for(bits):
    if bits <= 8:
        return "u8"
    if bits <= 16:
        return "s16le"
    if bits <= 24:
        return "s24le"
    return "s32le"

class FlacDemuxer:
    func init(path, limits=null):
        self.limits = lim.of(limits)
        self.path = path
        self.closed = false
        if not _os.isfile(path):
            merr.fail(merr.MEDIA, "fichier introuvable : " + str(path))
        self.size = _os.size(path)
        self.limits.check_file_size(self.size)
        self.info = ms.MediaInfo(path, "flac", self.size)
        self.info.mime = "audio/flac"
        self._read_metadata()
        self.buf = []
        self.buf_off = 0
        self.pending = []
        self.pending_start = 0
        self.pos_frames = 0
        self.byte_pos = self.meta["first_frame"]
        self.decoded_to = 0
        self.ended = false
        self._want_raw = false

    func _read_metadata():
        # métadonnées jusqu'à la première trame ; relecture plus large si une image intégrée est grosse
        n := 65536
        while true:
            head := _io.read_bytes(self.path, 0, n if n < self.size else self.size)
            try:
                self.meta = flac.read_header(head, self.limits)
                break
            catch e:
                if e.type == "CorruptDataError" and n < self.size and (_s.contains(e.message, "tronqu") or _s.contains(e.message, "au-delà")):
                    self.limits.check("max_chunk_bytes", n * 4)
                    n = n * 4
                    continue
                raise(e.type, e.message)
        m := self.meta
        self.format = _af.AudioFormat(m["rate"], m["channels"], sample_format_for(m["bits"]))
        self.bits = m["bits"]
        self.tags = m["tags"]
        self.frames = m["samples"]
        self.time_base = ts.for_rate(m["rate"])
        st := ms.StreamInfo(0, "audio", "flac", self.format, self.time_base)
        if self.frames > 0:
            st.duration = 1.0 * self.frames / m["rate"]
        else:
            self.info.warn("nombre total d'échantillons inconnu (0 dans STREAMINFO) : durée inconnue")
        st.frames = self.frames if self.frames > 0 else null
        st.decodable = true
        self.info.add_stream(st)
        self.info.tags = self.tags.to_dict()

    func _alive():
        if self.closed:
            merr.state("démultiplexeur fermé : " + self.path)

    # Fenêtre d'octets couvrant [pos, pos + need) si le fichier le permet.
    func _window(pos, need):
        if pos >= self.buf_off and pos + need <= self.buf_off + len(self.buf):
            return
        n := need if need > WINDOW else WINDOW
        if pos + n > self.size:
            n = self.size - pos
        if n <= 0:
            self.buf = []
            self.buf_off = pos
            return
        self.buf = _io.read_bytes(self.path, pos, n)
        self.buf_off = pos

    # Décode la trame à self.byte_pos : [canaux, premier échantillon, octets de la trame] ou null en fin de fichier.
    func _decode_next():
        if self.ended or self.byte_pos + 2 > self.size:
            self.ended = true
            return null
        if self.frames > 0 and self.decoded_to >= self.frames:
            self.ended = true
            return null
        need := WINDOW
        while true:
            self._window(self.byte_pos, need)
            rel := self.byte_pos - self.buf_off
            try:
                r := flac.decode_frame(self.buf, rel, self.meta)
                h := r[2]
                chans := r[0]
                first := h["first_sample"]
                raw := [self.buf[k] for k in rel..r[1]] if self._want_raw else null
                self.byte_pos = self.buf_off + r[1]
                n := len(chans[0])
                if self.frames > 0 and first + n > self.frames:
                    n = self.frames - first
                    if n < 0:
                        n = 0
                    chans = [[ch[i] for i in 0..n] for ch in chans]
                self.decoded_to = first + n
                return [chans, first, raw, h]
            catch e:
                truncated := e.type == "CorruptDataError" and _s.contains(e.message, "tronqu")
                if truncated and self.buf_off + len(self.buf) < self.size:
                    need = need * 4
                    self.limits.check("max_chunk_bytes", need)
                    continue
                if truncated:
                    self.info.warn("fichier tronqué : lecture arrêtée à la trame à l'octet " + str(self.byte_pos))
                    self.ended = true
                    return null
                raise(e.type, e.message)

    func duration():
        if self.frames > 0:
            return 1.0 * self.frames / self.format.rate
        return null

    func streams():
        return self.info.streams

    func tell():
        return 1.0 * self.pos_frames / self.format.rate

    func tell_frames():
        return self.pos_frames

    func at_end():
        return len(self.pending) == 0 and (self.ended or (self.frames > 0 and self.decoded_to >= self.frames))

    func seek(seconds):
        return self.seek_frames(to_int(seconds * self.format.rate + 0.5))

    func seek_frames(target):
        self._alive()
        if target < 0:
            target = 0
        if self.frames > 0 and target > self.frames:
            target = self.frames
        # meilleur point de la table
        off := 0
        for p in self.meta["seektable"]:
            if p[0] <= target and p[1] >= off:
                off = p[1]
        self.byte_pos = self.meta["first_frame"] + off
        self.ended = false
        self.pending = []
        self.decoded_to = 0
        self._want_raw = false
        while true:
            r := self._decode_next()
            if r == null:
                self.pos_frames = self.decoded_to
                self.pending_start = self.pos_frames
                return self.tell()
            first := r[1]
            n := len(r[0][0])
            if first + n > target:
                skip := target - first
                if skip < 0:
                    skip = 0
                self.pending = flac.to_float([[ch[i] for i in skip..n] for ch in r[0]], self.bits)
                self.pending_start = first + skip
                self.pos_frames = first + skip
                return self.tell()


    # Une trame FLAC encodée (octets) ; paquet de fin de flux à la fin.
    func read_packet(frames=null):
        self._alive()
        if len(self.pending) > 0:
            merr.state("read_packet après read_frame : repositionner d'abord avec seek()")
        self._want_raw = true
        r := self._decode_next()
        self._want_raw = false
        if r == null:
            return mb.end_of_stream(0)
        n := len(r[0][0])
        self.pos_frames = r[1] + n
        return mb.Packet(0, r[2], ts.Timestamp(r[1], self.time_base), n, true)

    func read_frame(frames=4096):
        self._alive()
        if frames <= 0:
            merr.fail(merr.FORMAT, "nombre de trames invalide : " + str(frames))
        ch := self.format.channels
        want := frames * ch
        while len(self.pending) < want:
            r := self._decode_next()
            if r == null:
                break
            if len(self.pending) == 0:
                self.pending_start = r[1]
            for x in flac.to_float(r[0], self.bits):
                append(self.pending, x)
        if len(self.pending) == 0:
            return mb.end_frame("audio")
        take := want if want < len(self.pending) else len(self.pending)
        out := [self.pending[k] for k in 0..take]
        self.pending = [self.pending[k] for k in take..len(self.pending)]
        start := self.pending_start
        self.pending_start = start + take // ch
        self.pos_frames = self.pending_start
        return mb.audio_frame(out, self.format, ts.Timestamp(start, self.time_base))

    func read_all(max_frames=null):
        out := []
        left := self.frames - self.pos_frames if self.frames > 0 else null
        if max_frames != null and (left == null or max_frames < left):
            left = max_frames
        if left != null:
            self.limits.check("max_decoded_bytes", left * self.format.channels * 8)
        while left == null or left > 0:
            f := self.read_frame(65536 if left == null or left > 65536 else left)
            if f.eos:
                break
            for x in f.data:
                append(out, x)
            if left != null:
                left -= f.frames()
        return out

    func close():
        self.closed = true
        self.buf = []
        self.pending = []
