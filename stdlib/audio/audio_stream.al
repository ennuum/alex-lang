# ALEX STANDARD LIBRARY — audio.audio_stream
#
# Tampons et flux audio :
#   - AudioBuffer : échantillons flottants (entrelacés) + format ; durée, canaux, extrait, conversion de format,
#     lecture / écriture WAV, octets PCM ;
#   - flux de SORTIE (write(échantillons), drain(), close()) :
#       PlayerStream    lecture en continu par le lecteur du système (aplay, pw-play, paplay, ffplay) qui
#                       reçoit le PCM brut sur son entrée standard ;
#       WavWriter       écriture progressive d'un fichier WAV (en-tête complété à la fermeture) ;
#       MemorySink      accumule en mémoire (tests, traitement) ;
#   - flux d'ENTRÉE (read(trames) -> échantillons, ou [] à la fin) :
#       CaptureStream   capture en continu par l'outil du système (arecord, pw-record, parecord, ffmpeg) ;
#       WavReader       lecture d'un fichier WAV par morceaux ;
#       MemorySource    échantillons en mémoire.
#
#   use audio.audio_stream as st
#   use audio.audio_format as af
#   out := st.open_output(af.CD)                 # PlayerStream (HardwareError sans lecteur)
#   out.write(echantillons)
#   out.close()
#   w := st.WavWriter("sortie.wav", af.VOICE)
#   w.write(voix)
#   w.close()

from core use len, type, to_int
from collections use append
use string as _s
use io as _io
use os as _os
use process
use hardware._sys as _sys
use hardware._windows as _win
use hardware.audio as _haudio
use audio.audio_format as af
use _native_net as _b

# ---------------------------------------------------------------- tampon
class AudioBuffer:
    func init(samples, fmt):
        self.samples = samples
        self.format = af.named(fmt)

    func frames():
        return len(self.samples) // self.format.channels

    func duration():
        return 1.0 * self.frames() / self.format.rate

    func channel(i):
        ch := self.format.channels
        return [self.samples[k] for k in i..len(self.samples) if (k - i) % ch == 0]

    # Extrait [début, fin) en secondes.
    func slice(start, stop=null):
        ch := self.format.channels
        a := to_int(start * self.format.rate) * ch
        b := len(self.samples)
        if stop != null:
            b = to_int(stop * self.format.rate) * ch
        if b > len(self.samples):
            b = len(self.samples)
        return AudioBuffer([self.samples[k] for k in a..b], self.format)

    func append_buffer(other):
        src := other.convert(self.format).samples
        for x in src:
            append(self.samples, x)
        return self

    # Même son dans un autre format (fréquence, canaux ; le format d'échantillon ne change que l'encodage).
    func convert(fmt):
        target := af.named(fmt)
        s := self.samples
        if target.channels != self.format.channels:
            s = af.convert_channels(s, self.format.channels, target.channels)
        if target.rate != self.format.rate:
            s = af.resample(s, self.format.rate, target.rate, target.channels)
        return AudioBuffer(s, target)

    func to_bytes():
        return af.encode(self.samples, self.format)

    func save_wav(path):
        bits := 16
        if self.format.sample_format == "u8":
            bits = 8
        _haudio.write_wav(path, self.samples, self.format.rate, self.format.channels, bits)

    func describe():
        return str(self.frames()) + " trames, " + str(to_int(self.duration() * 1000)) + " ms, " + self.format.describe()

func from_bytes(data, fmt):
    f := af.named(fmt)
    return AudioBuffer(af.decode(data, f), f)

func load_wav(path):
    w := _haudio.read_wav(path)
    fmt := "s16le"
    if w.bits == 8:
        fmt = "u8"
    return AudioBuffer(w.samples, af.AudioFormat(w.rate, w.channels, fmt))

# ---------------------------------------------------------------- sorties
class MemorySink:
    func init(fmt):
        self.format = af.named(fmt)
        self.samples = []
        self.closed = false
        self.frames_written = 0

    func write(samples):
        for x in samples:
            append(self.samples, x)
        self.frames_written += len(samples) // self.format.channels
        return len(samples)

    func drain():
        return null

    func close():
        self.closed = true

    func buffer():
        return AudioBuffer(self.samples, self.format)

class WavWriter:
    func init(path, fmt):
        self.path = path
        self.format = af.named(fmt)
        self.data_bytes = 0
        self.frames_written = 0
        self.closed = false
        _io.write_bytes(path, self._header(0))

    func _header(n):
        f := self.format
        out := []
        _text(out, "RIFF")
        _u32(out, 36 + n)
        _text(out, "WAVEfmt ")
        _u32(out, 16)
        tag := 1
        if f.sample_format == "f32le":
            tag = 3
        _u16(out, tag)
        _u16(out, f.channels)
        _u32(out, f.rate)
        _u32(out, f.bytes_per_second())
        _u16(out, f.frame_bytes())
        _u16(out, f.bits())
        _text(out, "data")
        _u32(out, n)
        return out

    func write(samples):
        if self.closed:
            raise("IoError", "WavWriter : fichier fermé")
        data := af.encode(samples, self.format)
        _io.write_bytes_at(self.path, data, null)
        self.data_bytes += len(data)
        self.frames_written += len(samples) // self.format.channels
        return len(samples)

    func drain():
        return null

    # Complète l'en-tête (tailles) et ferme.
    func close():
        if not self.closed:
            _io.write_bytes_at(self.path, self._header(self.data_bytes), 0)
            self.closed = true

func _text(out, t):
    for c in _b.to_bytes(t):
        append(out, c)

func _u16(out, v):
    append(out, v & 255)
    append(out, (v >> 8) & 255)

func _u32(out, v):
    append(out, v & 255)
    append(out, (v >> 8) & 255)
    append(out, (v >> 16) & 255)
    append(out, (v >> 24) & 255)

_PLAYERS := ["aplay", "pw-play", "paplay", "ffplay"]
_RECORDERS := ["arecord", "pw-record", "parecord", "ffmpeg"]

# Commande de lecture du PCM brut sur l'entrée standard : [programme, arguments], ou null sans lecteur.
func player_command(fmt, device=null, tool=null):
    f := af.named(fmt)
    t := tool if tool != null else _sys.find_tool(_PLAYERS)
    if t == null:
        return null
    r := str(f.rate)
    c := str(f.channels)
    if t == "aplay":
        a := ["-q", "-t", "raw", "-f", f.alsa_name(), "-r", r, "-c", c]
        if device != null:
            a = _cat(a, ["-D", device])
        return [t, _cat(a, ["-"])]
    if t == "pw-play":
        return [t, ["--rate", r, "--channels", c, "--format", _pw_format(f), "-"]]
    if t == "paplay":
        a := ["--raw", "--rate=" + r, "--channels=" + c, "--format=" + f.pulse_name()]
        if device != null:
            a = _cat(a, ["--device=" + device])
        return [t, a]
    return [t, ["-nodisp", "-autoexit", "-loglevel", "quiet", "-f", f.ffmpeg_name(), "-ar", r] + _sys.raw_channels_args(f.channels, t) + ["-i", "-"]]

func capture_command(fmt, device=null, tool=null):
    f := af.named(fmt)
    t := tool if tool != null else _sys.find_tool(_RECORDERS)
    if t == null:
        return null
    r := str(f.rate)
    c := str(f.channels)
    if t == "arecord":
        a := ["-q", "-t", "raw", "-f", f.alsa_name(), "-r", r, "-c", c]
        if device != null:
            a = _cat(a, ["-D", device])
        return [t, a]
    if t == "pw-record":
        return [t, ["--rate", r, "--channels", c, "--format", _pw_format(f), "-"]]
    if t == "parecord":
        a := ["--raw", "--rate=" + r, "--channels=" + c, "--format=" + f.pulse_name()]
        if device != null:
            a = _cat(a, ["--device=" + device])
        return [t, a]
    inp := null
    if _win.is_windows():
        inp = _win.input_args(device, "audio")      # DirectShow ; null : aucune entrée
        if inp == null:
            return null
    else:
        inp = ["-f", "alsa", "-i", device if device != null else "default"]
    return [t, ["-loglevel", "quiet"] + inp + ["-f", f.ffmpeg_name(), "-ar", r, "-ac", c, "-"]]

func _cat(a, b):
    out := [x for x in a]
    for x in b:
        append(out, x)
    return out

func _pw_format(f):
    if f.sample_format == "u8":
        return "u8"
    if f.sample_format == "s24le":
        return "s24"
    if f.sample_format == "s32le":
        return "s32"
    if f.sample_format == "f32le":
        return "f32"
    return "s16"

class PlayerStream:
    # command : [programme, arguments] (player_command par défaut).
    func init(fmt, device=null, command=null):
        self.format = af.named(fmt)
        cmd := command if command != null else player_command(self.format, device)
        if cmd == null:
            _sys.fail("audio", "aucun lecteur audio (aplay, pw-play, paplay ou ffplay)")
        self.command = cmd
        self.proc = process.Command(cmd[0]).args(cmd[1]).stdin("pipe").stdout("null").stderr("null").spawn()
        self.frames_written = 0
        self.closed = false

    func write(samples):
        if self.closed:
            raise("IoError", "PlayerStream : flux fermé")
        data := af.encode(samples, self.format)
        self.proc.write(_b.from_bytes(data))
        self.frames_written += len(samples) // self.format.channels
        return len(samples)

    # Ferme l'entrée du lecteur et attend qu'il ait tout joué.
    func drain():
        if not self.closed:
            self.proc.close_stdin()
            self.proc.wait()
            self.closed = true

    func close():
        self.drain()

    func stop():
        if not self.closed:
            self.proc.stop(0.5)
            self.closed = true

func open_output(fmt=null, device=null):
    return PlayerStream(fmt if fmt != null else af.CD, device)

# ---------------------------------------------------------------- entrées
class MemorySource:
    func init(samples, fmt):
        self.format = af.named(fmt)
        self.samples = samples
        self.pos = 0

    func read(frames):
        n := frames * self.format.channels
        end := self.pos + n
        if end > len(self.samples):
            end = len(self.samples)
        out := [self.samples[k] for k in self.pos..end]
        self.pos = end
        return out

    func close():
        return null

class WavReader:
    func init(path):
        b := load_wav(path)
        self.format = b.format
        self.source = MemorySource(b.samples, b.format)

    func read(frames):
        return self.source.read(frames)

    func close():
        return null

class CaptureStream:
    func init(fmt, device=null, command=null):
        self.format = af.named(fmt)
        cmd := command if command != null else capture_command(self.format, device)
        if cmd == null:
            _sys.fail("audio", "aucun outil de capture (arecord, pw-record, parecord ou ffmpeg)")
        self.command = cmd
        self.proc = process.Command(cmd[0]).args(cmd[1]).stdin("null").stdout("pipe").stderr("null").spawn()
        self.pending = []
        self.frames_read = 0
        self.closed = false
        self.ended = false

    # frames trames (moins à la fin du flux, [] quand il est fini) ; timeout en secondes (null : attendre).
    func read(frames, timeout=null):
        need := frames * self.format.frame_bytes()
        while len(self.pending) < need and not self.ended:
            chunk := self.proc.read("stdout", need - len(self.pending), timeout)
            if chunk == null:
                break
            if chunk == "":
                self.ended = true
                break
            for c in _b.to_bytes(chunk):
                append(self.pending, c)
        take := len(self.pending) - len(self.pending) % self.format.frame_bytes()
        if take > need:
            take = need
        data := [self.pending[k] for k in 0..take]
        self.pending = [self.pending[k] for k in take..len(self.pending)]
        out := af.decode(data, self.format)
        self.frames_read += len(out) // self.format.channels
        return out

    func close():
        if not self.closed:
            self.proc.stop(0.5)
            self.closed = true

func open_input(fmt=null, device=null):
    return CaptureStream(fmt if fmt != null else af.VOICE, device)
