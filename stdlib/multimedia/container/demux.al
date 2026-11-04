# ALEX STANDARD LIBRARY — multimedia.container.demux
#
# Démultiplexage : ouvre un conteneur, décrit ses pistes et en lit les paquets dans l'ordre, avec recherche
# temporelle. Conteneurs pris en charge : FLAC (multimedia.container.flac_demux), Ogg (multimedia.container.ogg)
# et WAV / RIFF (PCM 8, 16, 24, 32 bits entiers, 32 bits flottants,
# WAVE_FORMAT_EXTENSIBLE, étiquettes LIST/INFO). Le fichier est lu PAR MORCEAUX (jamais chargé en entier) ; un
# fichier tronqué est accepté avec un avertissement (durée réelle recalculée).
#
#   use multimedia.container.demux as dmx
#   d := dmx.open("voix.wav")                    # WavDemuxer (UnsupportedError pour un autre conteneur)
#   print(d.info.describe(), d.format.describe(), d.duration())
#   while true:
#       f := d.read_frame(4096)                  # Frame audio décodée (échantillons flottants), ou fin de flux
#       if f.eos:
#           break
#       traiter(f.data)
#   d.seek(12.5)                                 # position au plus proche, alignée sur une trame
#   p := d.read_packet(1024)                     # Packet : octets PCM bruts, pts en 1/fréquence
#   d.close()
#
# Erreurs : CorruptDataError, UnsupportedError, LimitError, StateError (lecture après close).

from core use len, to_int
from collections use append
use io as _io
use os as _os
use audio.audio_format as _af
use multimedia.core.errors as merr
use multimedia.core.timestamp as ts
use multimedia.core.buffer as mb
use multimedia.core.stream as ms
use multimedia.security.limits as lim
use multimedia.security.validation as val
use multimedia.container.metadata as cmeta
use multimedia.metadata.tags as tg
use multimedia.container.flac_demux as _fdx
use multimedia.container.ogg as _ogg
use multimedia.backends.codecs.ffmpeg as _ff

func _read(path, at, n):
    if n <= 0:
        return []
    return _io.read_bytes(path, at, n)

# Codec PCM d'après le code de format WAV et le nombre de bits.
func pcm_codec(code, bits):
    if code == 1:
        if bits == 8:
            return "pcm_u8"
        if bits == 16:
            return "pcm_s16le"
        if bits == 24:
            return "pcm_s24le"
        if bits == 32:
            return "pcm_s32le"
    if code == 3 and bits == 32:
        return "pcm_f32le"
    return null

const WAV_CODES := {2: "adpcm_ms", 6: "pcm_alaw", 7: "pcm_mulaw", 17: "adpcm_ima", 85: "mp3", 255: "aac", 8193: "dts"}

class WavDemuxer:
    func init(path, limits=null):
        self.limits = lim.of(limits)
        self.path = path
        self.closed = false
        if not _os.isfile(path):
            merr.fail(merr.MEDIA, "fichier introuvable : " + str(path))
        self.size = _os.size(path)
        self.limits.check_file_size(self.size)
        self.info = ms.MediaInfo(path, "wav", self.size)
        self.info.mime = "audio/wav"
        self.tags = tg.Tags()
        self._parse()
        self.pos_frames = 0

    func _parse():
        head := _read(self.path, 0, 12)
        r := val.Reader(head, "WAV")
        if len(head) < 12 or r.tag(0) != "RIFF" or r.tag(8) != "WAVE":
            if len(head) >= 4 and r.tag(0) == "RF64":
                merr.unsupported("WAV RF64 (fichiers de plus de 4 Gio)")
            merr.corrupt("WAV", "en-tête RIFF/WAVE absent")
        riff_size := r.u32le(4)
        if riff_size + 8 > self.size:
            self.info.warn("taille RIFF déclarée " + str(riff_size + 8) + " > taille du fichier " + str(self.size))
        at := 12
        fmt := null
        self.data_at = -1
        self.data_bytes = 0
        nchunks := 0
        while at + 8 <= self.size:
            h := _read(self.path, at, 8)
            hr := val.Reader(h, "WAV")
            cid := hr.tag(0)
            csize := hr.u32le(4)
            nchunks += 1
            if nchunks > 10000:
                merr.corrupt("WAV", "trop de blocs")
            if cid == "":
                merr.corrupt("WAV", "identifiant de bloc illisible à la position " + str(at))
            if cid == "fmt ":
                if csize < 16 or csize > 4096:
                    merr.corrupt("WAV", "bloc fmt de " + str(csize) + " octets")
                val.check_chunk(at + 8, csize, self.size, "bloc fmt")
                fb := _read(self.path, at + 8, csize)
                fr := val.Reader(fb, "WAV fmt")
                code := fr.u16le(0)
                channels := fr.u16le(2)
                rate := fr.u32le(4)
                align := fr.u16le(12)
                bits := fr.u16le(14)
                if code == 65534 and csize >= 40:
                    code = fr.u16le(24)
                fmt = [code, channels, rate, align, bits]
            elif cid == "data":
                self.data_at = at + 8
                self.data_bytes = csize
                if csize == 0xFFFFFFFF or at + 8 + csize > self.size:
                    if csize != 0xFFFFFFFF:
                        self.info.warn("bloc data tronqué : " + str(csize) + " octets déclarés, " + str(self.size - at - 8) + " présents")
                    self.data_bytes = self.size - at - 8
            elif cid == "LIST":
                if csize <= self.limits.get("max_chunk_bytes") and at + 8 + csize <= self.size and csize <= 1048576:
                    self.tags.update(cmeta.read_riff_info(_read(self.path, at + 8, csize)))
            if cid == "data" and self.data_bytes != csize:
                break
            if cid != "data":
                if at + 8 + csize > self.size:
                    if self.data_at >= 0:
                        self.info.warn("bloc « " + cid + " » tronqué en fin de fichier (ignoré)")
                        break
                    merr.corrupt("WAV", "bloc « " + cid + " » de " + str(csize) + " octets au-delà de la fin du fichier")
                self.limits.check("max_chunk_bytes", csize)
            at += 8 + csize + csize % 2
        if fmt == null:
            merr.corrupt("WAV", "bloc fmt absent")
        if self.data_at < 0:
            merr.corrupt("WAV", "bloc data absent")
        code := fmt[0]
        channels := fmt[1]
        rate := fmt[2]
        bits := fmt[4]
        codec := pcm_codec(code, bits)
        if codec == null:
            name := WAV_CODES[code] if code in WAV_CODES else ("code " + str(code))
            merr.unsupported("WAV " + name + " (" + str(bits) + " bits)", "seul le PCM non compressé est décodé")
        if channels == 0 or rate == 0:
            merr.corrupt("WAV", "fréquence ou nombre de canaux nul")
        self.limits.check_audio(rate, channels)
        sf := {"pcm_u8": "u8", "pcm_s16le": "s16le", "pcm_s24le": "s24le", "pcm_s32le": "s32le", "pcm_f32le": "f32le"}[codec]
        self.format = _af.AudioFormat(rate, channels, sf)
        self.frame_bytes = self.format.frame_bytes()
        if fmt[3] != self.frame_bytes:
            self.info.warn("alignement de bloc " + str(fmt[3]) + " au lieu de " + str(self.frame_bytes) + " (corrigé)")
        if self.data_bytes % self.frame_bytes != 0:
            self.info.warn("bloc data non aligné sur les trames : " + str(self.data_bytes % self.frame_bytes) + " octets ignorés")
        self.frames = self.data_bytes // self.frame_bytes
        self.limits.check("max_frames", self.frames)
        self.limits.check("max_duration", 1.0 * self.frames / rate)
        self.time_base = ts.for_rate(rate)
        st := ms.StreamInfo(0, "audio", codec, self.format, self.time_base)
        st.duration = 1.0 * self.frames / rate
        st.frames = self.frames
        st.bit_rate = self.format.bytes_per_second() * 8
        st.decodable = true
        self.info.add_stream(st)
        self.info.tags = self.tags.to_dict()

    func _alive():
        if self.closed:
            merr.state("démultiplexeur fermé : " + self.path)

    func duration():
        return 1.0 * self.frames / self.format.rate

    func streams():
        return self.info.streams

    func tell():
        return 1.0 * self.pos_frames / self.format.rate

    func tell_frames():
        return self.pos_frames

    func at_end():
        return self.pos_frames >= self.frames

    # Position au plus proche (en trames) ; renvoie l'instant réellement atteint.
    func seek(seconds):
        self._alive()
        f := to_int(seconds * self.format.rate + 0.5)
        return self.seek_frames(f)

    func seek_frames(f):
        self._alive()
        if f < 0:
            f = 0
        if f > self.frames:
            f = self.frames
        self.pos_frames = f
        return self.tell()

    # Paquet brut (octets PCM) d'au plus `frames` trames ; paquet eos à la fin.
    func read_packet(frames=4096):
        self._alive()
        if frames <= 0:
            merr.fail(merr.FORMAT, "nombre de trames invalide : " + str(frames))
        n := frames
        if self.pos_frames + n > self.frames:
            n = self.frames - self.pos_frames
        if n <= 0:
            return mb.end_of_stream(0)
        data := _read(self.path, self.data_at + self.pos_frames * self.frame_bytes, n * self.frame_bytes)
        if len(data) != n * self.frame_bytes:
            merr.corrupt("WAV", "lecture incomplète à la trame " + str(self.pos_frames))
        p := mb.Packet(0, data, ts.Timestamp(self.pos_frames, self.time_base), n, true)
        self.pos_frames += n
        return p

    # Frame audio décodée (flottants -1..1 entrelacés).
    func read_frame(frames=4096):
        p := self.read_packet(frames)
        if p.eos:
            return mb.end_frame("audio")
        return mb.audio_frame(_af.decode(p.data, self.format), self.format, p.pts)

    # Lit tout ce qui reste (ou au plus max_frames) en un seul tableau d'échantillons.
    func read_all(max_frames=null):
        out := []
        left := self.frames - self.pos_frames
        if max_frames != null and max_frames < left:
            left = max_frames
        self.limits.check("max_decoded_bytes", left * self.format.channels * 8)
        while left > 0:
            f := self.read_frame(65536 if left > 65536 else left)
            if f.eos:
                break
            for x in f.data:
                append(out, x)
            left -= f.frames()
        return out

    func close():
        self.closed = true

func _head(path, n):
    size := _os.size(path)
    return _io.read_bytes(path, 0, n if n < size else size)

# Ouvre un démultiplexeur adapté au fichier : natif en ALEX (WAV, FLAC, Ogg FLAC) ; sinon, si ffmpeg est installé,
# l'adaptateur système (multimedia.backends.codecs.ffmpeg : MP3, AAC, Opus, Vorbis, MP4, Matroska...) ;
# sinon UnsupportedError explicite. prefer : "native" (défaut), "system" (toujours ffmpeg), "native_only".
func open(path, limits=null, prefer="native"):
    if not _os.isfile(path):
        merr.fail(merr.MEDIA, "fichier introuvable : " + str(path))
    if prefer == "system":
        _ff.require()
        return _ff.FfmpegDemuxer(path, limits)
    h := _head(path, 16)
    if len(h) >= 12 and h[0] == 82 and h[1] == 73 and h[2] == 70 and h[3] == 70 and h[8] == 87 and h[9] == 65 and h[10] == 86 and h[11] == 69:
        try:
            return WavDemuxer(path, limits)
        catch e:
            if e.type == "UnsupportedError" and prefer != "native_only" and _ff.available():
                return _ff.FfmpegDemuxer(path, limits)
            raise(e.type, e.message)
    if len(h) >= 4 and h[0] == 102 and h[1] == 76 and h[2] == 97 and h[3] == 67:
        return _fdx.FlacDemuxer(path, limits)
    if len(h) >= 4 and h[0] == 79 and h[1] == 103 and h[2] == 103 and h[3] == 83:
        d := _ogg.OggDemuxer(path, limits)
        if d.selected.codec != "flac" and d.selected.kind == "audio" and prefer != "native_only" and _ff.available():
            d.close()
            return _ff.FfmpegDemuxer(path, limits)
        return d
    if prefer != "native_only" and _ff.available():
        return _ff.FfmpegDemuxer(path, limits)
    merr.unsupported("démultiplexage " + _probe_name(h), "conteneurs natifs : wav, flac, ogg ; installer ffmpeg pour les autres")

func _probe_name(h):
    if len(h) >= 4 and h[0] == 79 and h[1] == 103 and h[2] == 103 and h[3] == 83:
        return "ogg"
    if len(h) >= 4 and h[0] == 102 and h[1] == 76 and h[2] == 97 and h[3] == 67:
        return "flac"
    if len(h) >= 3 and h[0] == 73 and h[1] == 68 and h[2] == 51:
        return "mp3"
    if len(h) >= 8 and h[4] == 102 and h[5] == 116 and h[6] == 121 and h[7] == 112:
        return "mp4"
    if len(h) >= 4 and h[0] == 26 and h[1] == 69 and h[2] == 223 and h[3] == 163:
        return "matroska"
    if len(h) >= 12 and h[0] == 82 and h[8] == 65 and h[9] == 86 and h[10] == 73:
        return "avi"
    return "de ce fichier"
