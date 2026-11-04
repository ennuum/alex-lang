# ALEX STANDARD LIBRARY — microphone
#
# Le microphone pour les applications :
#
# | Module                       | Contenu                                                              |
# |------------------------------|----------------------------------------------------------------------|
# | microphone.microphone_info   | micros présents (ALSA), défaut, recherche par nom                    |
# | microphone.audio_input       | AudioInput : lecture par blocs, gain, porte de bruit, niveaux, async |
# | microphone.capture           | Recorder : durée fixe, jusqu'au silence, vers WAV ; segments         |
#
#   use microphone
#   if microphone.available():
#       b := microphone.record(3.0)              # 3 s, 16 kHz mono (audio_stream.AudioBuffer)
#       b.save_wav("note.wav")
#       print(microphone.level(b))               # dBFS
#
# Capture par arecord, pw-record, parecord ou ffmpeg (HardwareError si aucun n'est installé).

use audio.audio_format as af
use audio.audio_effects as fx
use audio.audio_stream as ast
use microphone.microphone_info as mi
use microphone.audio_input as ai
use microphone.capture as cap

func microphones():
    return mi.microphones()

func default():
    return mi.default()

# Un micro est-il présent ET un outil de capture installé ?
func available():
    return mi.available() and ast.capture_command(af.VOICE) != null

func open(fmt=null, device=null):
    return ai.AudioInput(fmt, device)

func recorder(fmt=null, device=null):
    return cap.Recorder(fmt, device)

func record(seconds, fmt=null, device=null):
    r := cap.Recorder(fmt, device)
    try:
        return r.record(seconds)
    finally:
        r.close()

func record_to_wav(path, seconds, fmt=null, device=null):
    r := cap.Recorder(fmt, device)
    try:
        return r.record_to_wav(path, seconds)
    finally:
        r.close()

# Niveau efficace (dBFS) d'un AudioBuffer.
func level(buf):
    return fx.db(buf.samples)
