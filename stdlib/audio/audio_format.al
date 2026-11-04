# ALEX STANDARD LIBRARY — audio.audio_format
#
# Formats audio PCM et conversions :
#   - AudioFormat : fréquence d'échantillonnage, nombre de canaux, format d'échantillon (« u8 », « s16le »,
#     « s24le », « s32le », « f32le »), taille d'une trame, débit, noms pour les outils (aplay, ffmpeg) ;
#   - encode / decode : échantillons flottants (-1.0..1.0, entrelacés) <-> octets (list[int]) ;
#   - convert_channels (mono <-> stéréo, réduction / extension), resample (interpolation linéaire),
#     frames <-> secondes.
#
#   use audio.audio_format as af
#   f := af.AudioFormat(48000, 2, "s16le")
#   octets := af.encode(echantillons, f)
#   retour := af.decode(octets, f)
#   mono := af.convert_channels(stereo, 2, 1)
#   x := af.resample(mono, 48000, 16000)
#
# Erreurs : ArgumentError (format inconnu, paramètres).

from core use len, type, to_int, to_float
from collections use append

const FORMATS := ["u8", "s16le", "s24le", "s32le", "f32le"]

func sample_size(sample_format):
    if sample_format == "u8":
        return 1
    if sample_format == "s16le":
        return 2
    if sample_format == "s24le":
        return 3
    if sample_format == "s32le" or sample_format == "f32le":
        return 4
    raise("ArgumentError", "audio : format d'échantillon inconnu '" + str(sample_format) + "' (u8, s16le, s24le, s32le, f32le)")

class AudioFormat:
    func init(rate=44100, channels=1, sample_format="s16le"):
        if rate < 1000 or rate > 768000:
            raise("ArgumentError", "AudioFormat : fréquence " + str(rate) + " hors de 1000..768000")
        if channels < 1 or channels > 32:
            raise("ArgumentError", "AudioFormat : 1 à 32 canaux")
        sample_size(sample_format)
        self.rate = rate
        self.channels = channels
        self.sample_format = sample_format

    func sample_bytes():
        return sample_size(self.sample_format)

    func frame_bytes():
        return self.sample_bytes() * self.channels

    func bytes_per_second():
        return self.frame_bytes() * self.rate

    func bits():
        return 8 * self.sample_bytes()

    func frames_for(seconds):
        return to_int(seconds * self.rate)

    func seconds_for(frames):
        return 1.0 * frames / self.rate

    # Nom pour « aplay -f » (S16_LE...) et pour « ffmpeg -f » (s16le...).
    func alsa_name():
        if self.sample_format == "u8":
            return "U8"
        if self.sample_format == "s16le":
            return "S16_LE"
        if self.sample_format == "s24le":
            return "S24_3LE"
        if self.sample_format == "s32le":
            return "S32_LE"
        return "FLOAT_LE"

    func ffmpeg_name():
        return self.sample_format

    func pulse_name():
        if self.sample_format == "s24le":
            return "s24le"
        if self.sample_format == "f32le":
            return "float32le"
        return self.sample_format

    func equals(other):
        return self.rate == other.rate and self.channels == other.channels and self.sample_format == other.sample_format

    func describe():
        ch := "mono"
        if self.channels == 2:
            ch = "stéréo"
        elif self.channels > 2:
            ch = str(self.channels) + " canaux"
        return str(self.rate) + " Hz, " + ch + ", " + self.sample_format

CD := AudioFormat(44100, 2, "s16le")
DVD := AudioFormat(48000, 2, "s16le")
VOICE := AudioFormat(16000, 1, "s16le")
TELEPHONE := AudioFormat(8000, 1, "u8")

func _clip(v):
    if v > 1.0:
        return 1.0
    if v < -1.0:
        return -1.0
    return v

# Flottant -> entier sur `scale` (2^(bits-1)) : arrondi au plus proche, écrêté à [-scale, scale - 1]. Inverse
# exact de decode (v / scale) : décoder puis réencoder dans le même format redonne les mêmes octets.
func _quantize(v, scale):
    n := to_int(v * scale + (0.5 if v >= 0 else -0.5))
    if n > scale - 1:
        return scale - 1
    if n < -scale:
        return -scale
    return n

# Échantillons flottants -> octets du format (petit-boutiste).
func encode(samples, fmt):
    out := []
    f := fmt.sample_format
    for x in samples:
        v := _clip(x)
        if f == "u8":
            append(out, _quantize(v, 128) + 128)
        elif f == "s16le":
            n := _quantize(v, 32768) & 0xFFFF
            append(out, n & 255)
            append(out, (n >> 8) & 255)
        elif f == "s24le":
            n := _quantize(v, 8388608) & 0xFFFFFF
            append(out, n & 255)
            append(out, (n >> 8) & 255)
            append(out, (n >> 16) & 255)
        elif f == "s32le":
            n := _quantize(v, 2147483648) & 0xFFFFFFFF
            append(out, n & 255)
            append(out, (n >> 8) & 255)
            append(out, (n >> 16) & 255)
            append(out, (n >> 24) & 255)
        else:
            n := _f32_bits(v)
            append(out, n & 255)
            append(out, (n >> 8) & 255)
            append(out, (n >> 16) & 255)
            append(out, (n >> 24) & 255)
    return out

# Octets -> échantillons flottants.
func decode(data, fmt):
    out := []
    f := fmt.sample_format
    size := sample_size(f)
    i := 0
    n := len(data) - len(data) % size
    while i < n:
        if f == "u8":
            append(out, (data[i] - 128) / 128.0)
        elif f == "s16le":
            v := data[i] | (data[i + 1] << 8)
            if v >= 32768:
                v -= 65536
            append(out, v / 32768.0)
        elif f == "s24le":
            v := data[i] | (data[i + 1] << 8) | (data[i + 2] << 16)
            if v >= 8388608:
                v -= 16777216
            append(out, v / 8388608.0)
        elif f == "s32le":
            v := data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24)
            if v >= 2147483648:
                v -= 4294967296
            append(out, v / 2147483648.0)
        else:
            append(out, _f32_value(data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24)))
        i += size
    return out

# Représentation IEEE 754 simple précision (entier 32 bits) d'un flottant de -1..1 (ou 0).
func _f32_bits(v):
    if v == 0.0:
        return 0
    sign := 0
    x := v
    if x < 0:
        sign = 1
        x = -x
    e := 0
    while x >= 2.0:
        x = x / 2.0
        e += 1
    while x < 1.0:
        x = x * 2.0
        e -= 1
    mant := to_int((x - 1.0) * 8388608.0 + 0.5)
    if mant >= 8388608:
        mant = 0
        e += 1
    return (sign << 31) | ((e + 127) << 23) | mant

func _f32_value(u):
    sign := (u >> 31) & 1
    e := (u >> 23) & 255
    mant := u & 8388607
    if e == 0:
        return 0.0
    x := 1.0 + mant / 8388608.0
    k := e - 127
    while k > 0:
        x = x * 2.0
        k -= 1
    while k < 0:
        x = x / 2.0
        k += 1
    if sign == 1:
        return -x
    return x

# Change le nombre de canaux d'échantillons entrelacés : moyenne pour réduire, copie pour étendre.
func convert_channels(samples, from_channels, to_channels):
    if from_channels == to_channels:
        return [x for x in samples]
    out := []
    frames := len(samples) // from_channels
    f := 0
    while f < frames:
        base := f * from_channels
        if to_channels < from_channels:
            if to_channels == 1:
                s := 0.0
                c := 0
                while c < from_channels:
                    s += samples[base + c]
                    c += 1
                append(out, s / from_channels)
            else:
                c := 0
                while c < to_channels:
                    append(out, samples[base + c])
                    c += 1
        else:
            c := 0
            while c < to_channels:
                if from_channels == 1:
                    append(out, samples[base])
                elif c < from_channels:
                    append(out, samples[base + c])
                else:
                    append(out, 0.0)
                c += 1
        f += 1
    return out

# Rééchantillonne (interpolation linéaire) des échantillons entrelacés de channels canaux.
func resample(samples, from_rate, to_rate, channels=1):
    if from_rate == to_rate:
        return [x for x in samples]
    frames := len(samples) // channels
    out_frames := to_int(1.0 * frames * to_rate / from_rate)
    out := []
    step := 1.0 * from_rate / to_rate
    i := 0
    while i < out_frames:
        pos := i * step
        k := to_int(pos)
        t := pos - k
        c := 0
        while c < channels:
            a := samples[k * channels + c]
            b := a
            if k + 1 < frames:
                b = samples[(k + 1) * channels + c]
            append(out, a + (b - a) * t)
            c += 1
        i += 1
    return out

func duration(samples, rate, channels=1):
    return 1.0 * (len(samples) // channels) / rate

# Format nommé : "cd", "dvd", "voice", "telephone" ou un AudioFormat.
func named(name):
    if type(name) != "str":
        return name
    if name == "cd":
        return CD
    if name == "dvd":
        return DVD
    if name == "voice":
        return VOICE
    if name == "telephone":
        return TELEPHONE
    raise("ArgumentError", "audio : format nommé inconnu '" + name + "' (cd, dvd, voice, telephone)")
