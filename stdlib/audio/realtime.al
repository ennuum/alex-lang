# ALEX STANDARD LIBRARY — audio.realtime
#
# Son de jeu en TEMPS RÉEL : sortie directe vers la carte son (waveOut / winmm sous Windows, ALSA sous Linux, par
# ffi, sans programme externe), mixage continu de voix en code natif (volume, panoramique, boucle, fondus, groupes
# « music » / « sfx »..., son 3D simple par rapport à un auditeur). La latence est de quelques dizaines de ms.
#
#   use audio.realtime as rt
#   eng := rt.AudioEngine()                          # 44100 Hz stéréo, périphérique par défaut
#   boum := eng.load("boum.wav")                     # Sound : décodé et rééchantillonné une fois
#   theme := eng.load("theme.ogg")                   # Ogg Vorbis (audio.vorbis)
#   eng.play(theme, 0.5, 0.0, true, "music")         # volume, panoramique, boucle, groupe
#   while jeu_actif:
#       if tir:
#           v := eng.play(boum, 0.8, -0.3)          # Voice : stop(), set_volume(), set_pan(), fade_to()...
#       eng.update()                                 # À CHAQUE IMAGE : remplit les tampons de la carte son
#   eng.close()
#
# Pompe : update() doit être appelée régulièrement (une fois par image suffit) ; la file de la carte contient
#   `latency` secondes d'avance (0,06 s par défaut), ce qui absorbe une image lente. Sans carte son (serveur, CI),
#   le dorsal « null » avance au rythme de l'horloge et rien n'est joué (eng.backend_name, eng.error).
# Sons : WAV PCM 8 / 16 / 24 / 32 bits et flottant (lecture rapide du PCM 16 bits), Ogg Vorbis, ou toute
#   audio.AudioBuffer / list de flottants. Stockage en entiers 16 bits à la fréquence du moteur.
# 3D : eng.set_listener(position, avant) ; voice.set_position([x, y, z]) atténue (distance) et panoramique (azimut).
#
# Erreurs : IoError (fichier), ValueError (format non pris en charge), HardwareError (dorsal demandé indisponible).

from core use len, type, to_int
from collections use append
use ffi
use math
use os as _os
use string as _s
use time as _time
use _native_ffi as _nf
use audio as _audio
use audio.vorbis as _vorbis

const DEFAULT_RATE := 44100

# ---------------------------------------------------------------------------------------------------------------------
# Lecture de fichiers en bloc (libc fopen / fread dans un ffi.Buffer)
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

# Contenu d'un fichier dans un ffi.Buffer (à libérer par l'appelant).
func read_file_buffer(path):
    c := _c()
    f := c["fopen"].call2(path, "rb")
    if f == null or f == 0:
        raise("IoError", "audio.realtime : impossible d'ouvrir '" + path + "'")
    c["fseek"].call3(f, 0, 2)
    n := c["ftell"].call1(f)
    c["fseek"].call3(f, 0, 0)
    if n <= 0:
        c["fclose"].call1(f)
        raise("IoError", "audio.realtime : fichier vide '" + path + "'")
    b := ffi.Buffer(n)
    got := c["fread"].call([b.address(), 1, n, f])
    c["fclose"].call1(f)
    if got != n:
        b.free()
        raise("IoError", "audio.realtime : lecture incomplète de '" + path + "'")
    return b

# ---------------------------------------------------------------------------------------------------------------------
# Sons
# ---------------------------------------------------------------------------------------------------------------------

# Son décodé en mémoire : entiers 16 bits entrelacés (1 ou 2 canaux) à `rate` Hz.
class Sound:
    func init(buffer, frames, channels, rate, name=""):
        self.buffer = buffer
        self.frames = frames
        self.channels = channels
        self.rate = rate
        self.name = name

    func duration():
        return self.frames * 1.0 / self.rate

    # Copie rééchantillonnée vers `rate` Hz (code natif, interpolation linéaire).
    func resampled(rate):
        if rate == self.rate:
            return self
        df := to_int(self.frames * 1.0 * rate / self.rate)
        if df < 1:
            df = 1
        dst := ffi.Buffer(df * self.channels * 2)
        _nf.audio_resample(dst._live(), self.buffer._live(), self.frames, self.channels, df)
        return Sound(dst, df, self.channels, rate, self.name)

    # Copie jouée plus aiguë / plus grave (facteur > 1 : plus aigu et plus court).
    func with_pitch(factor):
        if factor <= 0:
            raise("ValueError", "Sound.with_pitch : facteur > 0 attendu")
        df := to_int(self.frames / factor)
        if df < 1:
            df = 1
        dst := ffi.Buffer(df * self.channels * 2)
        _nf.audio_resample(dst._live(), self.buffer._live(), self.frames, self.channels, df)
        return Sound(dst, df, self.channels, self.rate, self.name)

    func free():
        if self.buffer != null:
            self.buffer.free()
            self.buffer = null

# Son depuis des échantillons flottants [-1, 1] entrelacés.
func sound_from_samples(samples, channels=1, rate=DEFAULT_RATE, name=""):
    if channels != 1 and channels != 2:
        raise("ValueError", "sound_from_samples : 1 ou 2 canaux")
    n := len(samples)
    frames := to_int(n / channels)
    if frames < 1:
        raise("ValueError", "sound_from_samples : aucun échantillon")
    b := ffi.Buffer(frames * channels * 2)
    b.write_array("pcm16", samples)
    return Sound(b, frames, channels, rate, name)

# Son depuis une audio.AudioBuffer (audio.load, audio.tone...).
func sound_from_audio_buffer(ab, name=""):
    ch := ab.format.channels
    samples := ab.samples
    if ch > 2:
        mono := []
        k := 0
        while k + ch <= len(samples):
            s := 0.0
            j := 0
            while j < ch:
                s += samples[k + j]
                j += 1
            append(mono, s / ch)
            k += ch
        samples = mono
        ch = 1
    if ab.format.sample_format != "f32le" and ab.format.sample_format != "f64le":
        samples = [_norm(x, ab.format.sample_format) for x in samples]
    return sound_from_samples(samples, ch, ab.format.rate, name)

func _norm(x, enc):
    if type(x) == "float":
        return x
    if enc == "u8":
        return (x - 128) / 128.0
    if enc == "s16le":
        return x / 32768.0
    if enc == "s24le":
        return x / 8388608.0
    if enc == "s32le":
        return x / 2147483648.0
    return x * 1.0

func _u16(b, o):
    return b.read("u16", o)

func _u32(b, o):
    return b.read("u32", o)

# WAV : chemin rapide pour le PCM 16 bits (copie directe des octets), sinon audio.load.
func load_wav(path):
    b := read_file_buffer(path)
    size := b.size()
    if size < 44 or b.read_bytes(0, 4) != "RIFF" or b.read_bytes(8, 4) != "WAVE":
        b.free()
        raise("ValueError", "audio.realtime : '" + path + "' n'est pas un fichier WAV")
    pos := 12
    fmt_tag := 0
    ch := 0
    rate := 0
    bits := 0
    data_off := -1
    data_len := 0
    while pos + 8 <= size:
        cid := b.read_bytes(pos, 4)
        clen := _u32(b, pos + 4)
        if cid == "fmt ":
            fmt_tag = _u16(b, pos + 8)
            ch = _u16(b, pos + 10)
            rate = _u32(b, pos + 12)
            bits = _u16(b, pos + 22)
            if fmt_tag == 0xFFFE and clen >= 26:
                fmt_tag = _u16(b, pos + 32)                   # WAVE_FORMAT_EXTENSIBLE : sous-format
        elif cid == "data":
            data_off = pos + 8
            data_len = clen
            if data_off + data_len > size:
                data_len = size - data_off
        pos += 8 + clen + (clen % 2)
    if data_off < 0 or ch == 0:
        b.free()
        raise("ValueError", "audio.realtime : WAV sans bloc fmt / data : '" + path + "'")
    if fmt_tag == 1 and bits == 16 and (ch == 1 or ch == 2):
        frames := to_int(data_len / (2 * ch))
        out := ffi.Buffer(frames * ch * 2 if frames > 0 else 2)
        out.copy_from(b, frames * ch * 2, 0, data_off)
        b.free()
        return Sound(out, frames, ch, rate, path)
    b.free()
    return sound_from_audio_buffer(_audio.load(path), path)

# Son depuis un fichier : .wav, .ogg (Vorbis).
func load_sound(path):
    low := _s.lower(path)
    if _s.ends_with(low, ".ogg") or _s.ends_with(low, ".oga"):
        d := _vorbis.load_pcm16(path)
        return Sound(d["buffer"], d["frames"], d["channels"], d["rate"], path)
    return load_wav(path)

# ---------------------------------------------------------------------------------------------------------------------
# Voix
# ---------------------------------------------------------------------------------------------------------------------

class Voice:
    func init(engine, sound, volume, pan, loop, group):
        self.engine = engine
        self.sound = sound
        self.volume = volume * 1.0
        self.pan = pan * 1.0
        self.loop = loop
        self.group = group
        self.position = 0                  # image courante dans le son
        self.playing = true
        self.paused = false
        self.on_end = null
        self.spatial = null                # [x, y, z] : son 3D
        self.min_distance = 1.0
        self.max_distance = 50.0
        self._fade = null                  # [volume cible, pas par image, arrêter à la fin]

    func stop():
        self.playing = false

    func pause():
        self.paused = true

    func resume():
        self.paused = false

    func set_volume(v):
        self.volume = v * 1.0

    func set_pan(p):
        self.pan = p * 1.0

    # Fondu vers `volume` en `seconds` ; stop_at_end : arrête la voix à la fin (fondu de sortie).
    func fade_to(volume, seconds, stop_at_end=false):
        frames := seconds * self.engine.rate
        if frames < 1:
            self.volume = volume * 1.0
            if stop_at_end:
                self.stop()
            return
        self._fade = [volume * 1.0, (volume - self.volume) / frames, stop_at_end]

    func fade_out(seconds):
        self.fade_to(0.0, seconds, true)

    # Position du son 3D (null : son 2D ordinaire).
    func set_position(p):
        self.spatial = p

    # Temps de lecture (s).
    func time():
        return self.position * 1.0 / self.sound.rate

    func seek(seconds):
        f := to_int(seconds * self.sound.rate)
        if f < 0:
            f = 0
        if f >= self.sound.frames:
            f = self.sound.frames - 1
        self.position = f

# ---------------------------------------------------------------------------------------------------------------------
# Dorsaux de sortie
# ---------------------------------------------------------------------------------------------------------------------

# Linux : ALSA en mode non bloquant.
class _AlsaOut:
    func init(rate, channels, period, latency, device):
        self.name = "alsa"
        lib := ffi.Library("libasound.so.2")
        self.lib = lib
        self.f = {"avail": lib.function("snd_pcm_avail_update", ["ptr"], "i64"),
                  "writei": lib.function("snd_pcm_writei", ["ptr", "ptr", "u64"], "i64"),
                  "recover": lib.function("snd_pcm_recover", ["ptr", "i32", "i32"], "i32"),
                  "close": lib.function("snd_pcm_close", ["ptr"], "i32"),
                  "strerror": lib.function("snd_strerror", ["i32"], "cstr")}
        hb := ffi.Buffer(8)
        r := lib.function("snd_pcm_open", ["ptr", "cstr", "i32", "i32"], "i32").call([hb.address(), device, 0, 1])
        if r < 0:
            hb.free()
            raise("HardwareError", "ALSA : ouverture de '" + device + "' impossible : " + self.f["strerror"].call1(r))
        self.pcm = hb.read("ptr")
        hb.free()
        sp := lib.function("snd_pcm_set_params", ["ptr", "i32", "i32", "u32", "u32", "i32", "u32"], "i32")
        r = sp.call([self.pcm, 2, 3, channels, rate, 1, to_int(latency * 1000000)])
        if r < 0:
            self.f["close"].call1(self.pcm)
            raise("HardwareError", "ALSA : configuration impossible : " + self.f["strerror"].call1(r))
        self.period = period

    # Nombre d'images qu'on peut écrire sans bloquer.
    func writable():
        a := self.f["avail"].call1(self.pcm)
        if a < 0:
            self.f["recover"].call3(self.pcm, a, 1)
            a = self.f["avail"].call1(self.pcm)
            if a < 0:
                return 0
        return a

    func write(buf, frames):
        r := self.f["writei"].call3(self.pcm, buf.address(), frames)
        if r < 0 and r != -11:
            self.f["recover"].call3(self.pcm, r, 1)

    func close():
        if self.pcm != null:
            self.f["close"].call1(self.pcm)
            self.pcm = null

# Windows : waveOut (winmm) avec une file de tampons, sondée sans rappel (WHDR_DONE).
class _WaveOut:
    func init(rate, channels, period, nbuf):
        self.name = "waveout"
        lib := ffi.Library("winmm")
        self.f = {"write": lib.function("waveOutWrite", ["ptr", "ptr", "u32"], "u32"),
                  "prepare": lib.function("waveOutPrepareHeader", ["ptr", "ptr", "u32"], "u32"),
                  "unprepare": lib.function("waveOutUnprepareHeader", ["ptr", "ptr", "u32"], "u32"),
                  "reset": lib.function("waveOutReset", ["ptr"], "u32"),
                  "close": lib.function("waveOutClose", ["ptr"], "u32")}
        wf := ffi.Buffer(20)
        wf.write("u16", 1, 0)
        wf.write("u16", channels, 2)
        wf.write("u32", rate, 4)
        wf.write("u32", rate * channels * 2, 8)
        wf.write("u16", channels * 2, 12)
        wf.write("u16", 16, 14)
        wf.write("u16", 0, 16)
        hb := ffi.Buffer(8)
        r := lib.function("waveOutOpen", ["ptr", "u32", "ptr", "ptr", "ptr", "u32"], "u32").call([hb.address(), 0xFFFFFFFF, wf.address(), 0, 0, 0])
        wf.free()
        if r != 0:
            hb.free()
            raise("HardwareError", "waveOut : ouverture impossible (code " + str(r) + ")")
        self.hwo = hb.read("ptr")
        hb.free()
        self.period = period
        self.bytes = period * channels * 2
        self.headers = []
        self.datas = []
        self.fresh = []
        k := 0
        while k < nbuf:
            d := ffi.Buffer(self.bytes)
            h := ffi.Buffer(48)
            h.write("ptr", d.address(), 0)
            h.write("u32", self.bytes, 8)
            self.f["prepare"].call3(self.hwo, h.address(), 48)
            append(self.headers, h)
            append(self.datas, d)
            append(self.fresh, true)
            k += 1

    func _free_index():
        k := 0
        while k < len(self.headers):
            if self.fresh[k] or (self.headers[k].read("u32", 24) & 1) == 1:
                return k
            k += 1
        return -1

    func writable():
        n := 0
        k := 0
        while k < len(self.headers):
            if self.fresh[k] or (self.headers[k].read("u32", 24) & 1) == 1:
                n += self.period
            k += 1
        return n

    func write(buf, frames):
        k := self._free_index()
        if k < 0:
            return
        self.datas[k].copy_from(buf, frames * 4)
        h := self.headers[k]
        h.write("u32", frames * 4, 8)
        h.write("u32", h.read("u32", 24) & 0xFFFFFFFE, 24)        # efface WHDR_DONE
        self.fresh[k] = false
        self.f["write"].call3(self.hwo, h.address(), 48)

    func close():
        if self.hwo != null:
            self.f["reset"].call1(self.hwo)
            for h in self.headers:
                self.f["unprepare"].call3(self.hwo, h.address(), 48)
                h.free()
            for d in self.datas:
                d.free()
            self.f["close"].call1(self.hwo)
            self.hwo = null

# Sans carte son : avance au rythme de l'horloge (ou d'un temps injecté) ; `record` garde le PCM produit (tests).
class _NullOut:
    func init(rate, period, latency, record=false):
        self.name = "null"
        self.rate = rate
        self.period = period
        self.queue = latency * rate
        self.queued = 0.0
        self.last = _time.monotonic()
        self.record = record
        self.recorded = []
        self.frames_written = 0

    func writable():
        now := _time.monotonic()
        self.queued -= (now - self.last) * self.rate
        self.last = now
        if self.queued < 0.0:
            self.queued = 0.0
        w := to_int(self.queue - self.queued)
        return w if w > 0 else 0

    func write(buf, frames):
        self.queued += frames
        self.frames_written += frames
        if self.record:
            for x in buf.read_array("i16", frames * 2):
                append(self.recorded, x)

    func close():
        return null

# ---------------------------------------------------------------------------------------------------------------------
# Moteur
# ---------------------------------------------------------------------------------------------------------------------

class AudioEngine:
    # backend : null (automatique), "alsa", "waveout" ou "null" ; device : nom ALSA ("default").
    func init(rate=DEFAULT_RATE, period=512, latency=0.06, backend=null, device="default", record=false):
        self.rate = rate
        self.channels = 2
        self.period = period
        self.latency = latency
        self.voices = []
        self.groups = {}
        self.master = 1.0
        self.error = null
        self.listener = [0.0, 0.0, 0.0]
        self.listener_forward = [0.0, 0.0, -1.0]
        self.listener_up = [0.0, 1.0, 0.0]
        self.acc = ffi.Buffer(period * 16)
        self.pcm = ffi.Buffer(period * 4)
        self.out = null
        want := backend
        plat := _os.platform()
        if want == null:
            want = "waveout" if plat == "windows" else "alsa"
        if want == "null":
            self.out = _NullOut(rate, period, latency, record)
        else:
            try:
                if want == "waveout":
                    nbuf := to_int(latency * rate / period) + 1
                    if nbuf < 3:
                        nbuf = 3
                    self.out = _WaveOut(rate, 2, period, nbuf)
                elif want == "alsa":
                    self.out = _AlsaOut(rate, 2, period, latency, device)
                else:
                    raise("ValueError", "audio.realtime : dorsal inconnu '" + str(want) + "'")
            catch e:
                if backend != null:
                    raise("HardwareError", e.message)
                self.error = e.message
                self.out = _NullOut(rate, period, latency, record)
        self.backend_name = self.out.name

    # Charge un son (WAV, Ogg Vorbis), rééchantillonné à la fréquence du moteur.
    func load(path):
        return load_sound(path).resampled(self.rate)

    # Son depuis des flottants (synthèse : audio.tone(...).samples, bruitages générés).
    func sound(samples, channels=1, rate=null):
        return sound_from_samples(samples, channels, rate if rate != null else self.rate).resampled(self.rate)

    # Joue un son ; rend la Voice. volume 0..1 (plus est possible), pan -1 (gauche) .. +1 (droite).
    func play(sound, volume=1.0, pan=0.0, loop=false, group="sfx"):
        s := sound
        if s.rate != self.rate:
            s = s.resampled(self.rate)
        v := Voice(self, s, volume, pan, loop, group)
        append(self.voices, v)
        return v

    # Son 3D à la position `p` (voir set_listener).
    func play_at(sound, p, volume=1.0, loop=false, group="sfx"):
        v := self.play(sound, volume, 0.0, loop, group)
        v.set_position(p)
        return v

    func set_group_volume(group, v):
        self.groups[group] = v * 1.0

    func group_volume(group):
        if group in self.groups:
            return self.groups[group]
        return 1.0

    func set_master_volume(v):
        self.master = v * 1.0

    func stop_all(group=null):
        for v in self.voices:
            if group == null or v.group == group:
                v.stop()

    func pause_all(group=null):
        for v in self.voices:
            if group == null or v.group == group:
                v.pause()

    func resume_all(group=null):
        for v in self.voices:
            if group == null or v.group == group:
                v.resume()

    func set_listener(position, forward=null, up=null):
        self.listener = position
        if forward != null:
            self.listener_forward = forward
        if up != null:
            self.listener_up = up

    func active_voices():
        return len([v for v in self.voices if v.playing])

    # Gains [gauche, droite] d'une voix pour ce bloc.
    func _gains(v):
        g := v.volume * self.group_volume(v.group)
        pan := v.pan
        if v.spatial != null:
            d := [v.spatial[0] - self.listener[0], v.spatial[1] - self.listener[1], v.spatial[2] - self.listener[2]]
            dist := math.sqrt((d[0] * d[0] + d[1] * d[1] + d[2] * d[2]) * 1.0)
            if dist > v.min_distance:
                if dist >= v.max_distance:
                    g = 0.0
                else:
                    g = g * v.min_distance / dist * (1.0 - (dist - v.min_distance) / (v.max_distance - v.min_distance))
            if dist > 0.0001:
                f := self.listener_forward
                u := self.listener_up
                right := [f[1] * u[2] - f[2] * u[1], f[2] * u[0] - f[0] * u[2], f[0] * u[1] - f[1] * u[0]]
                rl := math.sqrt((right[0] * right[0] + right[1] * right[1] + right[2] * right[2]) * 1.0)
                if rl > 0.0:
                    pan = (d[0] * right[0] + d[1] * right[1] + d[2] * right[2]) / (dist * rl)
        if pan < -1.0:
            pan = -1.0
        if pan > 1.0:
            pan = 1.0
        gl := g * (1.0 if pan <= 0.0 else 1.0 - pan)
        gr := g * (1.0 if pan >= 0.0 else 1.0 + pan)
        return [gl, gr]

    # Mixe un bloc de `frames` images dans self.pcm.
    func _mix(frames):
        acc := self.acc._live()
        for v in self.voices:
            if v.playing and not v.paused:
                gains := self._gains(v)
                s := v.sound
                done := 0
                while done < frames and v.playing:
                    left := s.frames - v.position
                    n := frames - done
                    if n > left:
                        n = left
                    if n > 0 and (gains[0] != 0.0 or gains[1] != 0.0):
                        _nf.audio_mix(acc, done, s.buffer._live(), v.position, n, s.channels, gains[0], gains[1])
                    v.position += n
                    done += n
                    if v.position >= s.frames:
                        if v.loop:
                            v.position = 0
                        else:
                            v.playing = false
                if v._fade != null:
                    fd := v._fade
                    v.volume += fd[1] * frames
                    if (fd[1] <= 0.0 and v.volume <= fd[0]) or (fd[1] >= 0.0 and v.volume >= fd[0]):
                        v.volume = fd[0]
                        v._fade = null
                        if fd[2]:
                            v.playing = false
        _nf.audio_out(self.pcm._live(), acc, frames, self.master)
        alive := []
        for v in self.voices:
            if v.playing:
                append(alive, v)
            elif v.on_end != null:
                cb := v.on_end
                v.on_end = null
                cb(v)
        self.voices = alive

    # À appeler à chaque image : remplit la file de la carte son. Rend le nombre d'images audio produites.
    func update():
        if self.out == null:
            return 0
        made := 0
        guard := 0
        while guard < 64:
            w := self.out.writable()
            if w < self.period:
                return made
            self._mix(self.period)
            self.out.write(self.pcm, self.period)
            made += self.period
            guard += 1
        return made

    # PCM enregistré par le dorsal « null » avec record=true (entiers 16 bits stéréo entrelacés).
    func recorded():
        if self.out.name == "null":
            return self.out.recorded
        return []

    func close():
        if self.out != null:
            self.out.close()
            self.out = null
        self.voices = []
