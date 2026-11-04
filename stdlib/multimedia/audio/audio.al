# ALEX STANDARD LIBRARY — multimedia.audio
#
# Espace audio de la bibliothèque multimédia. Les briques de base existent déjà dans le paquet `audio`
# (docs/MEDIA.md) et sont reprises ici sans duplication ; ce paquet ajoute rééchantillonnage de qualité,
# spatialisation et mesure de sonie.
#
# | Rôle (document d'architecture) | Module                                                         |
# |--------------------------------|----------------------------------------------------------------|
# | audio_format                   | audio.audio_format (AudioFormat, encode / decode)              |
# | sample_buffer                  | audio.audio_stream.AudioBuffer, multimedia.core.buffer         |
# | device                         | audio.audio_device, multimedia.backends.audio.system           |
# | capture                        | microphone, multimedia.recording.microphone                    |
# | playback                       | multimedia.playback.player                                     |
# | mixer                          | audio.audio_mixer                                              |
# | resampler                      | multimedia.audio.resampler (sinc polyphasé, en continu)        |
# | filters                        | audio.audio_effects, multimedia.effects.audio_effect           |
# | volume                         | multimedia.playback.controls.Volume (dB, rampe sans clic)      |
# | spatial                        | multimedia.audio.spatial (panoramique, largeur, 3D, ITD / ILD) |
# | meter                          | multimedia.audio.meter (crête vraie, RMS, EBU R128, LRA)       |
#
#   use multimedia.audio.audio as mau
#   y := mau.resample(x, 44100, 48000, 2)
#   print(mau.loudness(y, 48000, 2))

use audio.audio_format as _af
use audio.audio_mixer as _mix
use multimedia.audio.resampler as _rs
use multimedia.audio.meter as _mt
use multimedia.audio.spatial as _sp
use multimedia.playback.controls as _ctl

func format(rate=48000, channels=2, sample_format="f32le"):
    return _af.AudioFormat(rate, channels, sample_format)

func resample(samples, src, dst, channels=1, method="sinc", taps=32):
    return _rs.resample(samples, src, dst, channels, method, taps)

func loudness(samples, rate, channels=1):
    return _mt.loudness(samples, rate, channels)

func true_peak_db(samples, rate, channels=1):
    return _mt.db(_mt.true_peak(samples, rate, channels))

func pan(mono, position, law="constant_power"):
    return _sp.pan(mono, position, law)

func mixer(fmt=null):
    return _mix.Mixer(fmt)

func volume(gain=1.0):
    return _ctl.Volume(gain)
