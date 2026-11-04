# ALEX STANDARD LIBRARY — hardware.audio
#
# Son : cartes et périphériques audio (Linux : ALSA, /proc/asound), fichiers WAV (lecture, écriture),
# génération de sons (tone, silence, mix) et lecture par le lecteur du système (aplay, paplay, pw-play,
# afplay sous macOS, ffplay).
#
# Les échantillons sont des float de -1.0 à 1.0, entrelacés si plusieurs canaux ([g0, d0, g1, d1, ...]).
#
# Exemple
#   use hardware.audio as audio
#   la := audio.tone(440, 0.5)                  # 0,5 s de la 440 Hz
#   audio.write_wav("la.wav", la, 44100)
#   audio.play("la.wav")                        # HardwareError si aucun lecteur ni sortie
#   w := audio.read_wav("la.wav")
#   print(w.rate, w.channels, w.duration())
#
# Erreurs : HardwareError (pas de lecteur, échec de lecture), ArgumentError (WAV invalide, paramètres).

from core use len, type, to_int, to_float
from collections use append, contains_key
use string as _s
use math as _m
use os as _os
use file as _file
use process as _proc
use hardware._sys as _sys
use hardware._windows as _win
use io.console as _console

# ---------------------------------------------------------------- inventaire (ALSA ; Windows : WMI, DirectShow)
# Cartes son : list de dict index, id, driver, name.
func cards():
    out := []
    if _win.is_windows():
        i := 0
        for n in _win.sound_cards():
            append(out, {"index": i, "id": n, "driver": "wdm", "name": n})
            i += 1
        return out
    text := _sys.read("/proc/asound/cards")
    if text == null:
        return out
    for line in _s.split(text, "\n"):
        k := _s.find(line, "[")
        e := _s.find(line, "]:")
        if k < 0 or e < k:
            continue
        idx := _sys.dec(_s.slice(line, 0, k))
        if idx == null:
            continue
        rest := _s.trim(_s.slice(line, e + 2))
        dash := _s.find(rest, " - ")
        driver := rest
        name := rest
        if dash >= 0:
            driver = _s.trim(_s.slice(rest, 0, dash))
            name = _s.trim(_s.slice(rest, dash + 3))
        append(out, {"index": idx, "id": _s.trim(_s.slice(line, k + 1, e)), "driver": driver, "name": name})
    return out

class AudioDevice:
    func init(card, device, name):
        self.card = card
        self.device = device
        self.name = name
        self.playback = false
        self.capture = false
        self.source = null            # Windows : identifiant DirectShow (card == -1)

    # Nom ALSA (« hw:0,3 ») à passer à play / microphone.record ; sous Windows, identifiant DirectShow
    # (« audio=@device_cm_... ») d'une entrée, ou null pour la sortie par défaut.
    func alsa_name():
        if self.card == -1:
            return self.source
        return "hw:" + str(self.card) + "," + str(self.device)

# Périphériques PCM (sorties et entrées) : list de AudioDevice. Windows : les entrées DirectShow (ffmpeg) et une
# sortie, celle par défaut du système (ffplay n'en choisit pas d'autre), s'il y a une carte son.
func devices():
    out := []
    if _win.is_windows():
        if len(_win.sound_cards()) > 0:
            o := AudioDevice(-1, 0, "sortie par défaut de Windows")
            o.playback = true
            append(out, o)
        k := 0
        for d in _win.dshow_audio():
            a := AudioDevice(-1, k, d["name"])
            a.capture = true
            a.source = _win.source(d)
            append(out, a)
            k += 1
        return out
    text := _sys.read("/proc/asound/pcm")
    if text == null:
        return out
    for line in _s.split(text, "\n"):
        parts := [_s.trim(x) for x in _s.split(line, ":")]
        if len(parts) < 2:
            continue
        ids := _s.split(parts[0], "-")
        if len(ids) != 2:
            continue
        card := _sys.dec(ids[0])
        dev := _sys.dec(ids[1])
        if card == null or dev == null:
            continue
        d := AudioDevice(card, dev, parts[1])
        for p in parts:
            if _s.starts_with(p, "playback"):
                d.playback = true
            if _s.starts_with(p, "capture"):
                d.capture = true
        append(out, d)
    return out

# Sorties (haut-parleurs, casque, HDMI...).
func outputs():
    return [d for d in devices() if d.playback]

# Entrées (microphones, entrée ligne).
func inputs():
    return [d for d in devices() if d.capture]

func available():
    return len(outputs()) > 0

# ---------------------------------------------------------------- sons
func _check_rate(rate):
    if type(rate) != "int" or rate < 1000 or rate > 384000:
        raise("ArgumentError", "audio : fréquence d'échantillonnage 1000..384000 attendue")

# Sinusoïde de frequency Hz pendant seconds secondes (volume 0..1), avec 5 ms de fondu aux extrémités.
func tone(frequency, seconds, rate=44100, volume=0.5):
    _check_rate(rate)
    if seconds < 0 or frequency <= 0:
        raise("ArgumentError", "audio.tone : durée >= 0 et fréquence > 0 attendues")
    n := to_int(seconds * rate)
    fade := to_int(0.005 * rate)
    out := []
    step := 2 * _m.PI * frequency / rate
    i := 0
    while i < n:
        g := volume
        if fade > 0 and i < fade:
            g = volume * i / fade
        elif fade > 0 and n - 1 - i < fade:
            g = volume * (n - 1 - i) / fade
        append(out, g * _m.sin(step * i))
        i += 1
    return out

func silence(seconds, rate=44100):
    _check_rate(rate)
    return [0.0 for i in 0..to_int(seconds * rate)]

# Somme de plusieurs pistes (list de list d'échantillons), bornée à -1..1 ; la plus longue fixe la durée.
func mix(tracks):
    n := 0
    for t in tracks:
        if len(t) > n:
            n = len(t)
    out := []
    i := 0
    while i < n:
        v := 0.0
        for t in tracks:
            if i < len(t):
                v += t[i]
        if v > 1:
            v = 1.0
        if v < -1:
            v = -1.0
        append(out, v)
        i += 1
    return out

# Niveau efficace (RMS, 0..1) d'échantillons.
func rms(samples):
    if len(samples) == 0:
        return 0.0
    total := 0.0
    for v in samples:
        total += v * v
    return _m.sqrt(total / len(samples))

# Niveau crête (0..1).
func peak(samples):
    p := 0.0
    for v in samples:
        a := v
        if a < 0:
            a = -a
        if a > p:
            p = a
    return p

# ---------------------------------------------------------------- WAV
class Wav:
    func init(samples, rate, channels, bits):
        self.samples = samples      # float -1..1, entrelacés
        self.rate = rate
        self.channels = channels
        self.bits = bits

    func frames():
        return len(self.samples) // self.channels

    func duration():
        return self.frames() / self.rate

    # Échantillons d'un canal (0 : gauche).
    func channel(index):
        return [self.samples[i] for i in index..len(self.samples) if (i - index) % self.channels == 0]

func _put(out, v, count):
    k := 0
    while k < count:
        append(out, v % 256)
        v = v // 256
        k += 1

func _text(out, t):
    for c in t:
        append(out, _s.ord(c))

# Octets d'un fichier WAV PCM (bits : 8, 16, 24 ou 32) à partir d'échantillons float.
func encode_wav(samples, rate=44100, channels=1, bits=16):
    _check_rate(rate)
    if type(channels) != "int" or channels < 1 or channels > 16:
        raise("ArgumentError", "audio : 1 à 16 canaux attendus")
    if bits != 8 and bits != 16 and bits != 24 and bits != 32:
        raise("ArgumentError", "audio : 8, 16, 24 ou 32 bits attendus")
    if len(samples) % channels != 0:
        raise("ArgumentError", "audio : le nombre d'échantillons doit être un multiple du nombre de canaux")
    width := bits // 8
    size := len(samples) * width
    out := []
    _text(out, "RIFF")
    _put(out, 36 + size, 4)
    _text(out, "WAVEfmt ")
    _put(out, 16, 4)
    _put(out, 1, 2)
    _put(out, channels, 2)
    _put(out, rate, 4)
    _put(out, rate * channels * width, 4)
    _put(out, channels * width, 2)
    _put(out, bits, 2)
    _text(out, "data")
    _put(out, size, 4)
    full := (1 << (bits - 1)) - 1
    for v in samples:
        x := v
        if x > 1:
            x = 1.0
        if x < -1:
            x = -1.0
        q := to_int(_m.round(x * full))
        if bits == 8:
            append(out, q + 128)
        else:
            if q < 0:
                q = q + (1 << bits)
            _put(out, q, width)
    return out

func write_wav(path, samples, rate=44100, channels=1, bits=16):
    _file.write_bytes(path, encode_wav(samples, rate, channels, bits))

func _get(b, at, count):
    v := 0
    k := count - 1
    while k >= 0:
        v = v * 256 + b[at + k]
        k -= 1
    return v

func _tag(b, at):
    return str(_s.chr(b[at])) + str(_s.chr(b[at + 1])) + str(_s.chr(b[at + 2])) + str(_s.chr(b[at + 3]))

# Décode les octets d'un WAV PCM (entiers 8/16/24/32 bits ou flottants 32 bits) : Wav.
func decode_wav(b):
    if type(b) != "list" or len(b) < 12 or _tag(b, 0) != "RIFF" or _tag(b, 8) != "WAVE":
        raise("ArgumentError", "audio : ce n'est pas un fichier WAV")
    fmt := null
    data_at := -1
    data_len := 0
    at := 12
    while at + 8 <= len(b):
        tag := _tag(b, at)
        size := _get(b, at + 4, 4)
        if tag == "fmt ":
            fmt = [_get(b, at + 8, 2), _get(b, at + 10, 2), _get(b, at + 12, 4), _get(b, at + 22, 2)]
            if fmt[0] == 65534 and size >= 26:
                fmt[0] = _get(b, at + 32, 2)            # WAVE_FORMAT_EXTENSIBLE : code réel dans le sous-format
        elif tag == "data":
            data_at = at + 8
            data_len = size
            if data_at + data_len > len(b):
                data_len = len(b) - data_at
            break
        at += 8 + size + size % 2
    if fmt == null or data_at < 0:
        raise("ArgumentError", "audio : WAV sans bloc fmt ou data")
    code := fmt[0]
    channels := fmt[1]
    rate := fmt[2]
    bits := fmt[3]
    if not ((code == 1 and (bits == 8 or bits == 16 or bits == 24 or bits == 32)) or (code == 3 and bits == 32)):
        raise("ArgumentError", "audio : format WAV non pris en charge (code " + str(code) + ", " + str(bits) + " bits)")
    width := bits // 8
    samples := []
    i := data_at
    end := data_at + data_len - (data_len % width)
    if code == 3:
        while i < end:
            append(samples, _f32(_get(b, i, 4)))
            i += 4
    elif bits == 8:
        while i < end:
            append(samples, (b[i] - 128) / 128.0)
            i += 1
    else:
        full := 1 << (bits - 1)
        while i < end:
            v := _get(b, i, width)
            if v >= full:
                v = v - 2 * full
            append(samples, v / full)
            i += width
    return Wav(samples, rate, channels, bits)

func _f32(u):
    sign := 1.0
    if u >= 2147483648:
        sign = -1.0
        u = u - 2147483648
    e := u >> 23
    m := u & 8388607
    if e == 0:
        return sign * m * _m.pow(2, -149)
    return sign * (1 + m / 8388608.0) * _m.pow(2, e - 127)

func read_wav(path):
    return decode_wav(_file.read_bytes(path))

# ---------------------------------------------------------------- lecture
_PLAYERS := ["pw-play", "paplay", "aplay", "afplay", "ffplay"]

# Lecteur disponible (« aplay »...), ou null.
func player():
    return _sys.find_tool(_PLAYERS)

func _player_args(tool, path, device):
    if tool == "aplay":
        if device != null:
            return ["-q", "-D", device, path]
        return ["-q", path]
    if tool == "ffplay":
        return ["-nodisp", "-autoexit", "-loglevel", "quiet", path]
    if tool == "paplay" and device != null:
        return ["--device=" + device, path]
    return [path]

# Joue un fichier WAV (chemin) ou des échantillons (list, à rate Hz) et attend la fin. device : nom ALSA
# (AudioDevice.alsa_name()) pour aplay, nom PulseAudio pour paplay.
func play(source, rate=44100, channels=1, device=null, timeout=null):
    tool := player()
    if tool == null:
        _sys.fail("audio.play", "aucun lecteur audio (pw-play, paplay, aplay, afplay ou ffplay)")
    path := source
    temp := null
    if type(source) == "list":
        temp = _os.tmp_dir() + "/alex_audio_" + str(_os.pid()) + ".wav"
        write_wav(temp, source, rate, channels)
        path = temp
    try:
        r := _proc.run(tool, _player_args(tool, path, device), null, timeout)
        if r.timed_out:
            _sys.fail("audio.play", "délai dépassé")
        if r.code != 0:
            _sys.fail("audio.play", tool + " a échoué (code " + str(r.code) + ") : " + _s.trim(r.stderr))
    finally:
        if temp != null and _os.exists(temp):
            _os.remove(temp)

# Bip : une note courte si un lecteur est disponible, sinon le caractère BEL du terminal.
func beep(frequency=880, seconds=0.15):
    played := false
    if player() != null:
        try:
            play(tone(frequency, seconds, 22050, 0.4), 22050)
            played = true
        catch e:
            played = false
    if not played:
        _console.bell()
        _console.flush()
