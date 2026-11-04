# ALEX STANDARD LIBRARY — multimedia.testing.fixtures
#
# Données de test générées (aucun fichier à versionner) :
#   - WAV valides (sinus, silence, stéréo) en octets ou sur disque ;
#   - WAV HOSTILES : tronqué, sans bloc fmt, taille de bloc énorme, zéro canal, fréquence nulle, format inconnu,
#     bloc data plus long que le fichier, en-tête seul ;
#   - PNG / BMP hostiles : CRC faux, IHDR absent, dimensions énormes, flux compressé tronqué, palette manquante ;
#   - sous-titres et listes de lecture d'exemple ;
#   - fichiers temporaires nettoyés par cleanup().
#
#   use multimedia.testing.fixtures as fx
#   p := fx.temp_path("essai.wav")
#   fx.write_sine_wav(p, 440, 0.5)
#   for cas in fx.hostile_wavs():           # [nom, octets, type d'erreur attendu]
#       ...
#   fx.cleanup()

from core use len, to_int
from collections use append
use io as _io
use os as _os
use string as _s
use audio.audio_format as _af
use audio.audio_effects as _efx
use multimedia.container.mux as _mux
use multimedia.image.image as _mi
use multimedia.image.encode as _enc
use office.compression as _z

_temps := []

func temp_path(name):
    p := _os.tmp_dir() + "/alex_mm_" + str(_os.pid()) + "_" + str(len(_temps)) + "_" + name
    append(_temps, p)
    return p

func cleanup():
    n := 0
    for p in _temps:
        if _os.exists(p):
            _os.remove(p)
            n += 1
    return n

func u32le(v):
    return [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]

func u16le(v):
    return [v & 255, (v >> 8) & 255]

func sine(frequency=440.0, seconds=0.1, rate=8000, channels=1, volume=0.5):
    mono := _efx.sine(frequency, seconds, rate, volume)
    if channels == 1:
        return mono
    out := []
    for x in mono:
        for c in 0..channels:
            append(out, x)
    return out

func write_sine_wav(path, frequency=440.0, seconds=0.1, rate=8000, channels=1, sample_format="s16le", tags=null):
    fmt := _af.AudioFormat(rate, channels, sample_format)
    return _mux.write_wav(path, sine(frequency, seconds, rate, channels), fmt, tags)

func wav_bytes(samples, fmt):
    data := _af.encode(samples, fmt)
    return _mux.wav_header(fmt, len(data)) + data

func _fmt_chunk(code, channels, rate, bits):
    align := channels * bits // 8
    return _s.byte_unpack("fmt ") + u32le(16) + u16le(code) + u16le(channels) + u32le(rate) + u32le(rate * align) + u16le(align) + u16le(bits)

# [nom, octets, type d'erreur attendu ou null si le fichier doit être accepté (avec avertissement)].
func hostile_wavs():
    good := wav_bytes(sine(440, 0.05, 8000), _af.AudioFormat(8000, 1, "s16le"))
    out := []
    append(out, ["vide", [], "CorruptDataError"])
    append(out, ["en-tête seul", [good[k] for k in 0..12], "CorruptDataError"])
    append(out, ["signature fausse", _s.byte_unpack("RIFX") + [good[k] for k in 4..len(good)], "CorruptDataError"])
    append(out, ["sans bloc fmt", _s.byte_unpack("RIFF") + u32le(12) + _s.byte_unpack("WAVEdata") + u32le(4) + [0, 0, 0, 0], "CorruptDataError"])
    append(out, ["sans bloc data", _s.byte_unpack("RIFF") + u32le(28) + _s.byte_unpack("WAVE") + _fmt_chunk(1, 1, 8000, 16), "CorruptDataError"])
    append(out, ["zéro canal", _s.byte_unpack("RIFF") + u32le(40) + _s.byte_unpack("WAVE") + _fmt_chunk(1, 0, 8000, 16) + _s.byte_unpack("data") + u32le(4) + [0, 0, 0, 0], "CorruptDataError"])
    append(out, ["fréquence nulle", _s.byte_unpack("RIFF") + u32le(40) + _s.byte_unpack("WAVE") + _fmt_chunk(1, 1, 0, 16) + _s.byte_unpack("data") + u32le(4) + [0, 0, 0, 0], "CorruptDataError"])
    append(out, ["12 bits", _s.byte_unpack("RIFF") + u32le(40) + _s.byte_unpack("WAVE") + _fmt_chunk(1, 1, 8000, 12) + _s.byte_unpack("data") + u32le(4) + [0, 0, 0, 0], "UnsupportedError"])
    append(out, ["ADPCM", _s.byte_unpack("RIFF") + u32le(40) + _s.byte_unpack("WAVE") + _fmt_chunk(17, 1, 8000, 4) + _s.byte_unpack("data") + u32le(4) + [0, 0, 0, 0], "UnsupportedError"])
    append(out, ["1000 canaux", _s.byte_unpack("RIFF") + u32le(40) + _s.byte_unpack("WAVE") + _fmt_chunk(1, 1000, 8000, 16) + _s.byte_unpack("data") + u32le(4) + [0, 0, 0, 0], "LimitError"])
    append(out, ["bloc fmt énorme", _s.byte_unpack("RIFF") + u32le(40) + _s.byte_unpack("WAVE") + _s.byte_unpack("fmt ") + u32le(0x7FFFFFF0) + [0 for i in 0..16], "CorruptDataError"])
    big := _s.byte_unpack("RIFF") + u32le(40) + _s.byte_unpack("WAVE") + _s.byte_unpack("junk") + u32le(0x7FFFFFF0) + [0, 0, 0, 0]
    append(out, ["bloc inconnu énorme", big, "CorruptDataError"])
    # acceptés avec avertissement : données tronquées, bloc data non aligné
    append(out, ["données tronquées", [good[k] for k in 0..len(good) - 100], null])
    nal := [x for x in good]
    nal[40] = (nal[40] + 1) & 255
    append(out, ["data non aligné", nal + [0], null])
    return out

func _png_chunk(t, data):
    use_crc := _z.crc32(_s.byte_unpack(t) + data)
    return [(len(data) >> 24) & 255, (len(data) >> 16) & 255, (len(data) >> 8) & 255, len(data) & 255] + _s.byte_unpack(t) + data + [(use_crc >> 24) & 255, (use_crc >> 16) & 255, (use_crc >> 8) & 255, use_crc & 255]

func _u32be(v):
    return [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]

# [nom, octets, type d'erreur attendu].
func hostile_images():
    img := _mi.gradient(8, 4, "rgb")
    good := _enc.encode_png(img)
    sig := [137, 80, 78, 71, 13, 10, 26, 10]
    out := []
    bad_crc := [x for x in good]
    bad_crc[29] = (bad_crc[29] + 1) & 255
    append(out, ["PNG CRC faux", bad_crc, "CorruptDataError"])
    append(out, ["PNG tronqué", [good[k] for k in 0..len(good) - 20], "CorruptDataError"])
    append(out, ["PNG sans IHDR", sig + _png_chunk("IEND", []), "CorruptDataError"])
    huge := sig + _png_chunk("IHDR", _u32be(100000) + _u32be(100000) + [8, 2, 0, 0, 0]) + _png_chunk("IDAT", _z.zlib_compress([0])) + _png_chunk("IEND", [])
    append(out, ["PNG 100000 x 100000", huge, "LimitError"])
    zero := sig + _png_chunk("IHDR", _u32be(0) + _u32be(5) + [8, 2, 0, 0, 0]) + _png_chunk("IDAT", _z.zlib_compress([0])) + _png_chunk("IEND", [])
    append(out, ["PNG largeur nulle", zero, "CorruptDataError"])
    short := sig + _png_chunk("IHDR", _u32be(8) + _u32be(4) + [8, 2, 0, 0, 0]) + _png_chunk("IDAT", _z.zlib_compress([0, 1, 2])) + _png_chunk("IEND", [])
    append(out, ["PNG données insuffisantes", short, "CorruptDataError"])
    nopal := sig + _png_chunk("IHDR", _u32be(2) + _u32be(2) + [8, 3, 0, 0, 0]) + _png_chunk("IDAT", _z.zlib_compress([0, 0, 0, 0, 0, 0])) + _png_chunk("IEND", [])
    append(out, ["PNG palette absente", nopal, "CorruptDataError"])
    badct := sig + _png_chunk("IHDR", _u32be(2) + _u32be(2) + [7, 2, 0, 0, 0]) + _png_chunk("IEND", [])
    append(out, ["PNG profondeur 7", badct, "CorruptDataError"])
    badfilter := sig + _png_chunk("IHDR", _u32be(1) + _u32be(1) + [8, 0, 0, 0, 0]) + _png_chunk("IDAT", _z.zlib_compress([9, 0])) + _png_chunk("IEND", [])
    append(out, ["PNG filtre 9", badfilter, "CorruptDataError"])
    bomb := sig + _png_chunk("IHDR", _u32be(4) + _u32be(4) + [8, 0, 0, 0, 0]) + _png_chunk("IDAT", _z.zlib_compress([0 for i in 0..100000])) + _png_chunk("IEND", [])
    append(out, ["PNG bombe de décompression", bomb, "CorruptDataError"])
    bmp := _enc.encode_bmp(img)
    append(out, ["BMP tronqué", [bmp[k] for k in 0..len(bmp) - 10], "CorruptDataError"])
    bmp_rle := [x for x in bmp]
    bmp_rle[30] = 1
    append(out, ["BMP RLE", bmp_rle, "UnsupportedError"])
    bmp_big := [x for x in bmp]
    bmp_big[18] = 0
    bmp_big[19] = 0
    bmp_big[20] = 1
    bmp_big[21] = 0
    append(out, ["BMP 65536 de large", bmp_big, "LimitError"])
    append(out, ["PPM tronqué", _s.byte_unpack("P6\n4 4\n255\n") + [1, 2, 3], "CorruptDataError"])
    append(out, ["PPM valeur max 0", _s.byte_unpack("P5\n1 1\n0\n") + [0], "CorruptDataError"])
    append(out, ["PGM texte, valeur trop grande", _s.byte_unpack("P2\n1 1\n10\n99\n"), "CorruptDataError"])
    return out

const SAMPLE_SRT := "1\n00:00:01,000 --> 00:00:02,500\nBonjour\n\n2\n00:00:03,000 --> 00:00:04,000\n<i>deuxième</i> ligne\nsuite\n\n"

const SAMPLE_VTT := "WEBVTT - essai\n\nNOTE commentaire\nignoré\n\nintro\n00:00.500 --> 00:02.000 align:start\nPremier\n\n00:01:00.000 --> 00:01:01.250\nSecond\n"

const SAMPLE_M3U := "#EXTM3U\n#EXTINF:123,Artiste - Titre\nmorceau1.wav\n# commentaire\nhttp://exemple.org/flux.mp3\n#EXTINF:-1,Sans durée\n/absolu/morceau3.wav\n"

const SAMPLE_PLS := "[playlist]\nFile1=a.wav\nTitle1=Premier\nLength1=10\nFile2=b.wav\nNumberOfEntries=2\nVersion=2\n"
