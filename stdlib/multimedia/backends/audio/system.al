# ALEX STANDARD LIBRARY — multimedia.backends.audio.system
#
# Dorsal audio du système : sorties et entrées par les outils de la machine (paquet audio : aplay, pw-play,
# paplay, ffplay / arecord, pw-record, parecord, ffmpeg). Fabriques pour le lecteur et l'enregistreur, avec
# diagnostic explicite quand rien n'est disponible.
#
#   use multimedia.backends.audio.system as asys
#   out := asys.open_output(af.CD)            # sortie en continu (write / drain / close)
#   p := mp.Player(null, null, 2048, asys.output_factory())
#   inp := asys.open_input(af.VOICE)          # entrée (read(trames))
#   print(asys.describe())

use audio.audio_format as _af
use audio.audio_stream as _ast
use audio.audio_errors as _aerr
use multimedia.core.errors as merr

func describe():
    try:
        return _aerr.diagnose()
    catch e:
        return {"can_play": false, "can_record": false, "advice": e.message}

func can_play():
    return describe()["can_play"]

func can_record():
    return describe()["can_record"]

func open_output(fmt=null, device=null):
    f := fmt if fmt != null else _af.CD
    if _ast.player_command(f, device) == null:
        merr.fail(merr.DEVICE, "aucune sortie audio : " + str(describe()["advice"]))
    try:
        return _ast.PlayerStream(f, device)
    catch e:
        merr.fail(merr.DEVICE, "sortie audio : " + e.message)

func open_input(fmt=null, device=null):
    f := fmt if fmt != null else _af.VOICE
    if _ast.capture_command(f, device) == null:
        merr.fail(merr.DEVICE, "aucune entrée audio : " + str(describe()["advice"]))
    try:
        return _ast.CaptureStream(f, device)
    catch e:
        merr.fail(merr.DEVICE, "entrée audio : " + e.message)

# Fabrique pour multimedia.playback.player.Player(output_factory=...).
func output_factory(device=null):
    return (fmt) => open_output(fmt, device)
