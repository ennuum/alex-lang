# ALEX STANDARD LIBRARY — multimedia.backends.codecs.ffmpeg
#
# Adaptateur SYSTÈME vers ffmpeg / ffprobe (outils installés sur la machine), pour les codecs et conteneurs que la
# bibliothèque ne décode pas en ALEX : MP3, AAC, Opus, Vorbis, ALAC, H.264, HEVC, VP8 / VP9, AV1, JPEG...
# dans MP4 / MOV, Matroska / WebM, AVI, MPEG-TS, AIFF, Ogg... Les données passent par des tubes (aucun fichier
# temporaire) ; les limites de sécurité sont vérifiées sur la description ffprobe AVANT tout décodage.
# Sans ffmpeg : available() est faux et chaque appel lève UnsupportedError avec la marche à suivre.
#
#   use multimedia.backends.codecs.ffmpeg as ff
#   if ff.available():
#       info := ff.probe("film.mp4")                    # MediaInfo (pistes, codecs, durées, étiquettes)
#       a := ff.AudioDecoder("film.mp4", 48000, 2)      # flux de flottants entrelacés
#       x := a.read(4096)
#       v := ff.VideoDecoder("film.mp4", 320, 180)      # images rgb (multimedia.image.Image), pts
#       img := v.read()
#       e := ff.AudioEncoder("sortie.opus", af.AudioFormat(48000, 2, "f32le"))
#       e.write(echantillons)
#       e.close()
#       ff.install()                                    # déclare ces codecs « système » dans le registre
#
# Erreurs : UnsupportedError (ffmpeg absent, codec inconnu de ffmpeg), DeviceError (échec du processus),
# LimitError, MediaError.

from core use len, type, to_int, to_float
from collections use append, keys
use os as _os
use json as _json
use string as _s
use process as _proc
use _native_net as _b
use hardware._sys as _sys
use audio.audio_format as _af
use multimedia.core.errors as merr
use multimedia.core.timestamp as ts
use multimedia.core.buffer as mb
use multimedia.core.stream as ms
use multimedia.core.format as mf
use multimedia.security.limits as lim
use multimedia.image.image as mi
use multimedia.metadata.tags as tg
use multimedia.codec.registry as _reg

const BASE := ["-hide_banner", "-nostdin", "-loglevel", "error"]

# Codecs déclarés « système » quand ffmpeg est présent (décodage ; encodage pour les plus courants).
const AUDIO_DECODE := ["mp3", "aac", "opus", "vorbis", "alac", "pcm_alaw", "pcm_mulaw", "adpcm_ima", "speex", "ac3", "wmav2"]
const VIDEO_DECODE := ["h264", "hevc", "vp8", "vp9", "av1", "mpeg2video", "mpeg4", "mjpeg", "theora"]
const IMAGE_DECODE := ["jpeg", "gif", "webp", "tiff"]
const AUDIO_ENCODE := {"mp3": "libmp3lame", "aac": "aac", "opus": "libopus", "vorbis": "libvorbis", "flac": "flac"}
const VIDEO_ENCODE := {"h264": "libx264", "vp9": "libvpx-vp9", "theora": "libtheora", "mpeg4": "mpeg4", "mjpeg": "mjpeg"}
const EXT_AUDIO := {".mp3": "libmp3lame", ".opus": "libopus", ".ogg": "libvorbis", ".oga": "flac", ".m4a": "aac",
    ".aac": "aac", ".flac": "flac", ".wav": "pcm_s16le", ".aiff": "pcm_s16be", ".mka": "libopus"}
const EXT_VIDEO := {".mp4": "libx264", ".mkv": "libx264", ".webm": "libvpx-vp9", ".ogv": "libtheora", ".avi": "mpeg4",
    ".mov": "libx264"}

_state := {"ffmpeg": null, "ffprobe": null, "checked": false, "encoders": null}

func _detect():
    if not _state["checked"]:
        _state["ffmpeg"] = _sys.find_tool(["ffmpeg"])
        _state["ffprobe"] = _sys.find_tool(["ffprobe"])
        _state["checked"] = true
    return _state

func available():
    d := _detect()
    return d["ffmpeg"] != null and d["ffprobe"] != null

# Pour les tests : force l'absence (ou la présence) de ffmpeg.
func set_tools(ffmpeg, ffprobe):
    _state["ffmpeg"] = ffmpeg
    _state["ffprobe"] = ffprobe
    _state["checked"] = true
    _state["encoders"] = null

func reset():
    _state["checked"] = false
    _state["encoders"] = null

func require():
    if not available():
        merr.unsupported("adaptateur ffmpeg", "ffmpeg / ffprobe introuvables : installer ffmpeg (paquet « ffmpeg ») pour ces formats")

func _ext(path):
    p := _s.lower(path)
    i := len(p) - 1
    while i >= 0:
        if p[i] == '.':
            return _s.substring(p, i, len(p))
        if p[i] == '/':
            break
        i -= 1
    return ""

# Encodeurs présents dans le ffmpeg installé (noms ffmpeg).
func encoders():
    require()
    if _state["encoders"] == null:
        r := _proc.run(_state["ffmpeg"], ["-hide_banner", "-encoders"])
        names := []
        for line in _s.split(r.stdout, "\n"):
            t := _s.trim(line)
            parts := _s.split(t, " ")
            if len(parts) >= 2 and len(parts[0]) == 6 and parts[0] != "------":
                append(names, parts[1])
        _state["encoders"] = names
    return _state["encoders"]

func has_encoder(name):
    return name in encoders()

# ------------------------------------------------------------------------------------------- sondage
func _num(x):
    if x == null:
        return null
    try:
        return to_float(str(x))
    catch e:
        return null

func _rate(text):
    if text == null:
        return [25, 1]
    ps := _s.split(str(text), "/")
    try:
        n := to_int(ps[0])
        d := to_int(ps[1]) if len(ps) > 1 else 1
        if n > 0 and d > 0:
            return [n, d]
    catch e:
        return [25, 1]
    return [25, 1]

const CONTAINERS := {"mov,mp4,m4a,3gp,3g2,mj2": "mp4", "matroska,webm": "matroska", "mp3": "mp3", "ogg": "ogg",
    "avi": "avi", "mpegts": "mpegts", "aiff": "aiff", "wav": "wav", "flac": "flac", "image2": "image",
    "png_pipe": "png", "jpeg_pipe": "jpeg", "gif": "gif", "webp_pipe": "webp", "aac": "aac"}

func probe(path, limits=null):
    require()
    l := lim.of(limits)
    if not _os.isfile(path):
        merr.fail(merr.MEDIA, "fichier introuvable : " + str(path))
    size := _os.size(path)
    l.check_file_size(size)
    r := _proc.run(_state["ffprobe"], ["-v", "error", "-show_streams", "-show_format", "-of", "json", path], null, 30.0)
    if r.code != 0:
        msg := _s.trim(r.stderr)
        merr.fail(merr.CORRUPT, "multimédia : ffprobe refuse « " + path + " » : " + (msg if len(msg) > 0 else "format non reconnu"))
    j := _json.parse(r.stdout)
    fmt := j["format"] if "format" in j else {}
    cname := fmt["format_name"] if "format_name" in fmt else "inconnu"
    info := ms.MediaInfo(path, CONTAINERS[cname] if cname in CONTAINERS else cname, size)
    if "duration" in fmt:
        info.duration = _num(fmt["duration"])
    if "tags" in fmt:
        info.tags = tg.Tags(fmt["tags"]).to_dict()
    streams := j["streams"] if "streams" in j else []
    l.check("max_streams", len(streams))
    for s in streams:
        kind := s["codec_type"] if "codec_type" in s else "data"
        if kind == "attachment":
            kind = "data"
        if not (kind in ["audio", "video", "subtitle", "data"]):
            kind = "data"
        codec := s["codec_name"] if "codec_name" in s else "inconnu"
        f := null
        base := ts.MILLIS
        if kind == "audio" and "sample_rate" in s and "channels" in s:
            rate := to_int(s["sample_rate"])
            ch := s["channels"]
            l.check_audio(rate, ch)
            try:
                f = _af.AudioFormat(rate, ch, "f32le")
                base = ts.for_rate(rate)
            catch e:
                info.warn("piste " + str(s["index"]) + " : " + e.message)
        elif kind == "video" and "width" in s and "height" in s and s["width"] > 0:
            l.check_dimensions(s["width"], s["height"])
            fr := _rate(s["avg_frame_rate"] if "avg_frame_rate" in s and s["avg_frame_rate"] != "0/0" else (s["r_frame_rate"] if "r_frame_rate" in s else null))
            f = mf.VideoFormat(s["width"], s["height"], "rgb24", fr[0], fr[1])
            if "disposition" in s and "attached_pic" in s["disposition"] and s["disposition"]["attached_pic"] == 1:
                kind = "image"
        st := ms.StreamInfo(s["index"], kind, codec, f, base)
        if "duration" in s:
            st.duration = _num(s["duration"])
        elif info.duration != null and kind != "image":
            st.duration = info.duration
        if "nb_frames" in s:
            try:
                st.frames = to_int(s["nb_frames"])
            catch e:
                st.frames = null
        if "bit_rate" in s:
            try:
                st.bit_rate = to_int(s["bit_rate"])
            catch e:
                st.bit_rate = null
        if "tags" in s:
            if "language" in s["tags"]:
                st.language = s["tags"]["language"]
            if "title" in s["tags"]:
                st.title = s["tags"]["title"]
        st.decodable = kind == "audio" or kind == "video" or kind == "image"
        info.add_stream(st)
    if info.duration != null:
        l.check("max_duration", info.duration)
    info.warn("décrit et décodé par l'adaptateur système ffmpeg")
    return info

# ------------------------------------------------------------------------------------------- décodage
class _Reader:
    func init(args):
        self.args = args
        self.proc = _proc.Command(_state["ffmpeg"]).args(args).stdin("null").stdout("pipe").stderr("pipe").spawn()
        self.pending = []
        self.ended = false
        self.closed = false

    # Jusqu'à n octets (moins à la fin).
    func take(n):
        while len(self.pending) < n and not self.ended:
            chunk := self.proc.read("stdout", 1048576 if n - len(self.pending) > 1048576 else n - len(self.pending), null)
            if chunk == null or chunk == "":
                self.ended = true
                break
            for c in _b.to_bytes(chunk):
                append(self.pending, c)
        k := n if n < len(self.pending) else len(self.pending)
        out := [self.pending[i] for i in 0..k]
        self.pending = [self.pending[i] for i in k..len(self.pending)]
        return out

    func finish():
        if self.closed:
            return 0
        self.closed = true
        code := 0
        if self.ended:
            code = self.proc.wait(10.0)
            err := ""
            try:
                err = self.proc.read_all("stderr")
            catch e:
                err = ""
            if code != null and code != 0:
                self.proc.close()
                merr.fail(merr.DEVICE, "multimédia : ffmpeg a échoué (code " + str(code) + ") : " + _s.trim(err))
        else:
            self.proc.stop(0.5)
        self.proc.close()
        return code

class AudioDecoder:
    func init(path, rate=null, channels=null, start=0.0, stream=null, limits=null):
        require()
        self.info = probe(path, limits)
        a := null
        for s in self.info.streams:
            if s.kind == "audio" and (stream == null or s.index == stream):
                a = s
                break
        if a == null:
            merr.fail(merr.MEDIA, "aucune piste audio dans « " + path + " »")
        self.stream_info = a
        self.format = _af.AudioFormat(rate if rate != null else a.format.rate, channels if channels != null else a.format.channels, "f32le")
        self.path = path
        self.start = start
        self.position = to_int(start * self.format.rate + 0.5)
        args := BASE + ([] if start <= 0 else ["-ss", str(start)]) + ["-i", path, "-map", "0:" + str(a.index), "-vn", "-sn",
                "-f", "f32le", "-acodec", "pcm_f32le", "-ar", str(self.format.rate), "-ac", str(self.format.channels), "pipe:1"]
        self.reader = _Reader(args)

    # Jusqu'à `frames` trames (flottants entrelacés) ; [] à la fin.
    func read(frames):
        b := self.reader.take(frames * self.format.frame_bytes())
        b = [b[k] for k in 0..len(b) - len(b) % self.format.frame_bytes()]
        out := _af.decode(b, self.format)
        self.position += len(out) // self.format.channels
        if len(out) == 0:
            self.reader.finish()
        return out

    func close():
        self.reader.finish()

class VideoDecoder:
    func init(path, width=null, height=null, fps=null, start=0.0, stream=null, limits=null):
        require()
        l := lim.of(limits)
        self.info = probe(path, l)
        v := null
        for s in self.info.streams:
            if (s.kind == "video" or s.kind == "image") and (stream == null or s.index == stream):
                v = s
                break
        if v == null:
            merr.fail(merr.MEDIA, "aucune piste vidéo dans « " + path + " »")
        self.stream_info = v
        w := width if width != null else v.format.width
        h := height if height != null else v.format.height
        l.check_dimensions(w, h)
        self.width = w
        self.height = h
        self.fps = fps if fps != null else v.format.fps()
        self.index = 0
        self.start = start
        vf := "scale=" + str(w) + ":" + str(h)
        if fps != null:
            vf = "fps=" + str(fps) + "," + vf
        args := BASE + ([] if start <= 0 else ["-ss", str(start)]) + ["-i", path, "-map", "0:" + str(v.index), "-an", "-sn",
                "-vf", vf, "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
        self.reader = _Reader(args)

    # Image suivante (Image rgb, meta["pts"] en secondes) ou null à la fin.
    func read():
        n := self.width * self.height * 3
        b := self.reader.take(n)
        if len(b) < n:
            self.reader.finish()
            return null
        img := mi.Image(self.width, self.height, "rgb", b)
        img.meta = {"pts": self.start + 1.0 * self.index / self.fps, "index": self.index}
        self.index += 1
        return img

    func close():
        self.reader.finish()

# Mire de test animée de ffmpeg (« testsrc », « smptebars », « mandelbrot »...) : mêmes images que VideoDecoder.
class PatternSource:
    func init(width=320, height=240, fps=15, pattern="testsrc", seconds=null):
        require()
        self.width = width
        self.height = height
        self.fps = fps
        self.index = 0
        self.start = 0.0
        src := pattern + "=size=" + str(width) + "x" + str(height) + ":rate=" + str(fps)
        args := BASE + ["-f", "lavfi", "-i", src] + ([] if seconds == null else ["-t", str(seconds)]) + ["-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
        self.reader = _Reader(args)

    func read():
        n := self.width * self.height * 3
        b := self.reader.take(n)
        if len(b) < n:
            self.reader.finish()
            return null
        img := mi.Image(self.width, self.height, "rgb", b)
        img.meta = {"pts": 1.0 * self.index / self.fps, "index": self.index}
        self.index += 1
        return img

    func close():
        self.reader.finish()

# ------------------------------------------------------------------------------------------- encodage
class _Writer:
    func init(args, path):
        self.path = path
        self.proc = _proc.Command(_state["ffmpeg"]).args(args).stdin("pipe").stdout("null").stderr("pipe").spawn()
        self.closed = false

    func write_bytes(data):
        if self.closed:
            merr.state("encodeur fermé : " + self.path)
        self.proc.write(_b.from_bytes(data))

    func close():
        if self.closed:
            return 0
        self.closed = true
        self.proc.close_stdin()
        code := self.proc.wait(60.0)
        err := ""
        try:
            err = self.proc.read_all("stderr")
        catch e:
            err = ""
        self.proc.close()
        if code != 0:
            merr.fail(merr.DEVICE, "multimédia : ffmpeg n'a pas pu écrire « " + self.path + " » (code " + str(code) + ") : " + _s.trim(err))
        return code

func _codec_for(path, table, codec):
    if codec != null:
        return codec
    e := _ext(path)
    if e in table:
        return table[e]
    merr.unsupported("encodage vers « " + path + " »", "extension inconnue : préciser le codec")

# Format d'échantillon de SORTIE demandé (codecs sans perte / PCM) : options ffmpeg.
func _sample_args(codec, out_sf):
    if out_sf == null:
        return []
    if codec == "flac":
        if out_sf == "s16le" or out_sf == "u8":
            return ["-sample_fmt", "s16"]
        if out_sf == "s24le":
            return ["-sample_fmt", "s32", "-bits_per_raw_sample", "24"]
        return ["-sample_fmt", "s32"]
    return []

class AudioEncoder:
    func init(path, fmt, codec=null, bitrate=null, tags=null, out_sample_format=null):
        require()
        self.format = _af.named(fmt)
        c := _codec_for(path, EXT_AUDIO, codec)
        if not has_encoder(c):
            merr.unsupported("encodeur ffmpeg « " + c + " »", "absent de ce ffmpeg")
        args := BASE + ["-y", "-f", "f32le", "-ar", str(self.format.rate)] + _sys.raw_channels_args(self.format.channels, _detect()["ffmpeg"]) + ["-i", "pipe:0", "-c:a", c]
        args = args + _sample_args(c, out_sample_format)
        if bitrate != null:
            args = args + ["-b:a", str(bitrate)]
        if tags != null:
            for k in keys(tags.values):
                args = args + ["-metadata", k + "=" + tags.values[k]]
        self.codec = c
        self.frames = 0
        self.writer = _Writer(args + [path], path)

    func write(samples):
        if len(samples) % self.format.channels != 0:
            merr.fail(merr.FORMAT, "trames incomplètes")
        self.writer.write_bytes(_af.encode(samples, _af.AudioFormat(self.format.rate, self.format.channels, "f32le")))
        self.frames += len(samples) // self.format.channels
        return len(samples)

    func write_samples(samples):
        return self.write(samples)

    func write_frame(f):
        if f.eos:
            return 0
        return self.write(f.data)

    func drain():
        return null

    func close():
        self.writer.close()
        return self.frames

class VideoEncoder:
    func init(path, width, height, fps=25, codec=null, audio_path=null, quality=null):
        require()
        c := _codec_for(path, EXT_VIDEO, codec)
        if not has_encoder(c):
            merr.unsupported("encodeur ffmpeg « " + c + " »", "absent de ce ffmpeg")
        self.width = width
        self.height = height
        self.fps = fps
        self.frames = 0
        args := BASE + ["-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", str(width) + "x" + str(height), "-r", str(fps), "-i", "pipe:0"]
        if audio_path != null:
            args = args + ["-i", audio_path, "-c:a", "aac" if _ext(path) == ".mp4" or _ext(path) == ".mov" else "libopus", "-shortest"]
        args = args + ["-c:v", c, "-pix_fmt", "yuv420p"]
        if quality != null and c == "libx264":
            args = args + ["-crf", str(quality), "-preset", "veryfast"]
        elif c == "libx264":
            args = args + ["-preset", "veryfast"]
        self.writer = _Writer(args + [path], path)

    func write(img):
        if img.width != self.width or img.height != self.height:
            merr.fail(merr.FORMAT, "image " + img.describe() + " au lieu de " + str(self.width) + "x" + str(self.height))
        px := img.pixels
        if img.mode != "rgb":
            out := []
            for i in 0..img.width * img.height:
                if img.mode == "gray":
                    v := img.pixels[i]
                    append(out, v)
                    append(out, v)
                    append(out, v)
                else:
                    for c in 0..3:
                        append(out, img.pixels[4 * i + c])
            px = out
        self.writer.write_bytes(px)
        self.frames += 1

    func close():
        self.writer.close()
        return self.frames

# ------------------------------------------------------------------------------------------- démultiplexeur
# Même interface que les démultiplexeurs natifs (audio décodé par ffmpeg) + read_video().
class FfmpegDemuxer:
    func init(path, limits=null, stream=null):
        require()
        self.path = path
        self.limits = lim.of(limits)
        self.info = probe(path, self.limits)
        self.audio = _first_stream(self.info, "audio", stream)
        self.closed = false
        self.format = null
        self.frames = 0
        self.tags = tg.Tags(self.info.tags)
        if self.audio != null:
            self.format = _af.AudioFormat(self.audio.format.rate, self.audio.format.channels, "f32le")
            dur := self.audio.duration if self.audio.duration != null else self.info.duration
            self.frames = to_int(dur * self.format.rate + 0.5) if dur != null else 0
        self.dec = null
        self.vdec = null
        self.pos_frames = 0
        self._eos = false
        self._vstart = 0.0

    func _alive():
        if self.closed:
            merr.state("démultiplexeur fermé : " + self.path)

    func _audio():
        if self.audio == null:
            merr.fail(merr.MEDIA, "aucune piste audio")
        if self.dec == null:
            self.dec = AudioDecoder(self.path, self.format.rate, self.format.channels, 1.0 * self.pos_frames / self.format.rate, self.audio.index, self.limits)
        return self.dec

    func duration():
        if self.audio != null and self.audio.duration != null:
            return self.audio.duration
        return self.info.duration

    func tell():
        if self.format == null:
            return 0.0
        return 1.0 * self.pos_frames / self.format.rate

    func at_end():
        return self._eos

    func read_frame(frames=4096):
        self._alive()
        d := self._audio()
        start := self.pos_frames
        x := d.read(frames)
        if len(x) == 0:
            self._eos = true
            return mb.end_frame("audio")
        self.pos_frames += len(x) // self.format.channels
        return mb.audio_frame(x, self.format, ts.Timestamp(start, ts.for_rate(self.format.rate)))

    func read_packet(frames=4096):
        f := self.read_frame(frames)
        if f.eos:
            return mb.end_of_stream(0)
        return mb.Packet(0, _af.encode(f.data, self.format), f.pts, f.frames(), true)

    func read_all(max_frames=null):
        out := []
        left := max_frames
        while left == null or left > 0:
            f := self.read_frame(65536 if left == null or left > 65536 else left)
            if f.eos:
                break
            for v in f.data:
                append(out, v)
            if left != null:
                left -= f.frames()
        return out

    func seek(seconds):
        self._alive()
        if self.dec != null:
            self.dec.close()
            self.dec = null
        t := seconds if seconds > 0 else 0.0
        dur := self.duration()
        if dur != null and t > dur:
            t = dur
        self.pos_frames = to_int(t * self.format.rate + 0.5) if self.format != null else 0
        self._eos = false
        if self.vdec != null:
            self.vdec.close()
            self.vdec = null
        self._vstart = t
        return self.tell()

    # Image vidéo suivante (Image rgb, meta["pts"]) ou null.
    func read_video(width=null, height=null):
        self._alive()
        if self.vdec == null:
            self.vdec = VideoDecoder(self.path, width, height, null, self._vstart, null, self.limits)
        return self.vdec.read()

    func close():
        if self.closed:
            return
        self.closed = true
        if self.dec != null:
            self.dec.close()
        if self.vdec != null:
            self.vdec.close()

func _first_stream(info, kind, stream):
    for s in info.streams:
        if s.kind == kind and (stream == null or s.index == stream):
            return s
    return null

func open(path, limits=null, stream=null):
    return FfmpegDemuxer(path, limits, stream)

# ------------------------------------------------------------------------------------------- registre
func _audio_encoder(name):
    return (path, fmt) => AudioEncoder(path, fmt, name)

func _video_encoder(name):
    return (path, w, h, fps) => VideoEncoder(path, w, h, fps, name)

func _decoder(kind):
    if kind == "audio":
        return (path) => FfmpegDemuxer(path)
    return (path) => VideoDecoder(path)

# Déclare les codecs « système » dans multimedia.codec.registry (ne remplace jamais un codec intégré).
func install():
    if not available():
        return 0
    n := 0
    for c in AUDIO_DECODE + VIDEO_DECODE + IMAGE_DECODE:
        f := _reg.find(c)
        if f != null and f["origin"] == "intégré":
            continue
        kind := "audio" if c in AUDIO_DECODE else ("video" if c in VIDEO_DECODE else "image")
        enc := null
        if c in AUDIO_ENCODE and has_encoder(AUDIO_ENCODE[c]):
            enc = _audio_encoder(AUDIO_ENCODE[c])
        if c in VIDEO_ENCODE and has_encoder(VIDEO_ENCODE[c]):
            enc = _video_encoder(VIDEO_ENCODE[c])
        lic := f["licence"] if f != null else null
        _reg.register(c, kind, _decoder(kind), enc, "système", "par ffmpeg (" + str(_state["ffmpeg"]) + ") : décodeur à partir d'un CHEMIN de fichier", lic)
        n += 1
    return n
