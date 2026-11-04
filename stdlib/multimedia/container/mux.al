# ALEX STANDARD LIBRARY — multimedia.container.mux
#
# Multiplexage : écriture PROGRESSIVE d'un conteneur. WAV PCM (u8, s16le, s24le, s32le, f32le), en-tête
# provisoire complété à la fermeture, étiquettes LIST/INFO ajoutées après les données. Un fichier interrompu
# avant close() reste lisible (bloc data de taille provisoire, accepté par le démultiplexeur avec avertissement).
# FLAC (codec.audio.flac_encoder.FlacEncoder, même interface) et Ogg FLAC (container.ogg_mux) en ALEX pur.
#
#   use multimedia.container.mux as mux
#   w := mux.WavMuxer("sortie.wav", af.AudioFormat(48000, 2, "f32le"), tags)
#   w.write_samples(echantillons)          # flottants -1..1 entrelacés
#   w.write_frame(f)                       # Frame audio (convertie si son format diffère)
#   w.write_packet(p)                      # Packet d'octets PCM du même format
#   w.close()                              # renvoie le nombre de trames écrites
#   mux.open("x.mkv", fmt)                 # UnsupportedError : seul WAV est écrit
#
# Erreurs : UnsupportedError, FormatError, StateError (écriture après close).

from core use len
use io as _io
use string as _s
use audio.audio_format as _af
use multimedia.core.errors as merr
use multimedia.container.metadata as cmeta
use multimedia.metadata.tags as tg
use multimedia.codec.audio.flac_encoder as _flace
use multimedia.container.ogg_mux as _oggmux

func _u32le(v):
    return [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]

func _u16le(v):
    return [v & 255, (v >> 8) & 255]

func wav_header(fmt, data_bytes):
    code := 3 if fmt.sample_format == "f32le" else 1
    out := _s.byte_unpack("RIFF") + _u32le(36 + data_bytes) + _s.byte_unpack("WAVEfmt ") + _u32le(16)
    out = out + _u16le(code) + _u16le(fmt.channels) + _u32le(fmt.rate) + _u32le(fmt.bytes_per_second())
    out = out + _u16le(fmt.frame_bytes()) + _u16le(fmt.bits()) + _s.byte_unpack("data") + _u32le(data_bytes)
    return out

class WavMuxer:
    func init(path, fmt, tags=null):
        self.path = path
        self.format = _af.named(fmt)
        self.tags = tags if tags != null else tg.Tags()
        self.data_bytes = 0
        self.frames = 0
        self.closed = false
        _io.write_bytes(path, wav_header(self.format, 0))

    func _alive():
        if self.closed:
            merr.state("multiplexeur fermé : " + self.path)

    func write_bytes(data):
        self._alive()
        if len(data) % self.format.frame_bytes() != 0:
            merr.fail(merr.FORMAT, str(len(data)) + " octets : pas un nombre entier de trames de " + str(self.format.frame_bytes()) + " octets")
        if len(data) == 0:
            return 0
        _io.write_bytes_at(self.path, data, null)
        self.data_bytes += len(data)
        n := len(data) // self.format.frame_bytes()
        self.frames += n
        return n

    func write_samples(samples):
        if len(samples) % self.format.channels != 0:
            merr.fail(merr.FORMAT, str(len(samples)) + " échantillons : pas un nombre entier de trames")
        return self.write_bytes(_af.encode(samples, self.format))

    func write_packet(p):
        if p.eos:
            return 0
        return self.write_bytes(p.data)

    func write_frame(f):
        if f.eos:
            return 0
        s := f.data
        if not f.format.equals(self.format):
            if f.format.channels != self.format.channels:
                s = _af.convert_channels(s, f.format.channels, self.format.channels)
            if f.format.rate != self.format.rate:
                s = _af.resample(s, f.format.rate, self.format.rate, self.format.channels)
        return self.write_samples(s)

    func duration():
        return 1.0 * self.frames / self.format.rate

    func close():
        if self.closed:
            return self.frames
        if self.data_bytes % 2 == 1:
            _io.write_bytes_at(self.path, [0], null)
        info := cmeta.build_riff_info(self.tags)
        if len(info) > 0:
            _io.write_bytes_at(self.path, info, null)
        total := 44 + self.data_bytes + self.data_bytes % 2 + len(info)
        _io.write_bytes_at(self.path, _u32le(total - 8), 4)
        _io.write_bytes_at(self.path, _u32le(self.data_bytes), 40)
        self.closed = true
        return self.frames

func open(path, fmt, tags=null):
    p := _s.lower(path)
    if _s.ends_with(p, ".wav") or _s.ends_with(p, ".wave"):
        return WavMuxer(path, fmt, tags)
    if _s.ends_with(p, ".flac"):
        return _flace.FlacEncoder(path, fmt, tags)
    if _s.ends_with(p, ".oga"):
        return _oggmux.OggFlacMuxer(path, fmt, tags)
    merr.unsupported("multiplexage vers « " + path + " »", "conteneurs écrits : wav, flac, oga (Ogg FLAC) ; Vorbis / Opus par l'adaptateur ffmpeg")

# Écrit d'un coup un tampon d'échantillons dans un WAV.
func write_wav(path, samples, fmt, tags=null):
    w := WavMuxer(path, fmt, tags)
    w.write_samples(samples)
    return w.close()
