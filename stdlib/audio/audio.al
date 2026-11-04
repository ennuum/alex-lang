# ALEX STANDARD LIBRARY — audio
#
# Son pour les applications :
#
# | Module               | Contenu                                                                     |
# |----------------------|-----------------------------------------------------------------------------|
# | audio.audio_format   | AudioFormat (fréquence, canaux, u8 / s16le / s24le / s32le / f32le),        |
# |                      | encode / decode, canaux, rééchantillonnage                                   |
# | audio.audio_stream   | AudioBuffer, PlayerStream (lecture en continu), WavWriter, CaptureStream... |
# | audio.audio_device   | périphériques ALSA, sortie / entrée par défaut                              |
# | audio.audio_mixer    | Mixer : pistes, volume, panoramique, solo, boucle, vumètres                 |
# | audio.audio_effects  | générateurs (sinus, carré, bruit, ADSR...), effets (écho, réverbération,    |
# |                      | filtres, compresseur...), mesures (rms, crête, hauteur)                     |
#
#   use audio
#   la := audio.tone(440, 0.5)                   # AudioBuffer
#   audio.save(la, "la.wav")
#   audio.play(la)                               # HardwareError sans lecteur
#   b := audio.load("voix.wav")
#   print(b.describe(), audio.pitch(b))
#
# Lecture : aplay, pw-play, paplay ou ffplay ; capture : arecord, pw-record, parecord ou ffmpeg.

from core use type
use audio.audio_format as af
use audio.audio_stream as ast
use audio.audio_device as ad
use audio.audio_mixer as am
use audio.audio_effects as fx

func format(rate=44100, channels=1, sample_format="s16le"):
    return af.AudioFormat(rate, channels, sample_format)

func buffer(samples, fmt=null):
    return ast.AudioBuffer(samples, fmt if fmt != null else af.AudioFormat(44100, 1, "s16le"))

func tone(frequency, seconds, rate=44100, volume=0.5):
    return ast.AudioBuffer(fx.sine(frequency, seconds, rate, volume), af.AudioFormat(rate, 1, "s16le"))

func silence(seconds, rate=44100):
    return ast.AudioBuffer(fx.silence(seconds, rate), af.AudioFormat(rate, 1, "s16le"))

func load(path):
    return ast.load_wav(path)

func save(buf, path):
    buf.save_wav(path)

# Joue un AudioBuffer (ou un fichier WAV) et attend la fin.
func play(source, device=null):
    buf := source
    if type_is_str(source):
        buf = ast.load_wav(source)
    out := ast.PlayerStream(buf.format, device)
    out.write(buf.samples)
    out.drain()

func type_is_str(x):
    return type(x) == "str"

func mixer(fmt=null):
    return am.Mixer(fmt)

func devices():
    return ad.devices()

func outputs():
    return ad.outputs()

func inputs():
    return ad.inputs()

func can_play():
    return ad.player_available()

func can_record():
    return ad.recorder_available()

# Hauteur fondamentale (Hz) d'un tampon (premier canal).
func pitch(buf):
    s := buf.samples
    if buf.format.channels > 1:
        s = buf.channel(0)
    return fx.estimate_pitch(s, buf.format.rate)

