# ALEX STANDARD LIBRARY — multimedia.recording.microphone
#
# Le microphone comme source d'enregistrement (au-dessus du paquet microphone) : disponibilité réelle, ouverture
# d'une entrée par blocs, enregistrement direct vers un fichier. Sans micro ou sans outil de capture :
# DeviceError expliquée (jamais de silence enregistré à la place).
#
#   use multimedia.recording.microphone as mic
#   if mic.available():
#       stats := mic.record_to("note.opus", 5.0)        # 5 s, 48 kHz mono par défaut
#   src := mic.open(af.VOICE)                            # objet read(trames) pour Recorder / pipelines
#   print(mic.diagnose())

use audio.audio_format as _af
use audio.audio_stream as _ast
use audio.audio_errors as _aerr
use microphone as _mic
use multimedia.core.errors as merr
use multimedia.recording.recorder as rec

func diagnose():
    try:
        return _aerr.diagnose()
    catch e:
        return {"can_record": false, "recorder": null, "advice": e.message}

func available():
    try:
        return _mic.available()
    catch e:
        return false

func open(fmt=null, device=null):
    f := fmt if fmt != null else _af.AudioFormat(48000, 1, "s16le")
    if _ast.capture_command(f, device) == null:
        merr.fail(merr.DEVICE, "aucun outil de capture audio : " + str(diagnose()["advice"]))
    try:
        return _ast.CaptureStream(f, device)
    catch e:
        merr.fail(merr.DEVICE, "microphone inaccessible : " + e.message)

func record_to(path, seconds, fmt=null, device=null, token=null):
    f := fmt if fmt != null else _af.AudioFormat(48000, 1, "s16le")
    r := rec.Recorder(open(f, device), f, path)
    return r.record(seconds, token)
