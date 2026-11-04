# ALEX STANDARD LIBRARY — microphone.microphone_errors
#
# Erreurs du microphone et diagnostic de la capture : micro présent (entrées ALSA), outil de capture installé,
# serveur de son, droits sur /dev/snd, et vérification d'un enregistrement (silence complet : micro coupé ou
# mauvais périphérique ; saturation : gain trop fort).
#   MicrophoneError        erreur générale
#   MicrophoneUnavailable  aucun micro ou aucun outil de capture
#   CaptureError           capture interrompue, session dans un état incompatible
#
#   use microphone.microphone_errors as merr
#   print(merr.diagnose())                         # {"microphones": [...], "recorder": "arecord", "advice": ...}
#   merr.require_microphone()                      # MicrophoneUnavailable expliquée
#   print(merr.check_recording(tampon))            # {"ok": false, "problem": "silence complet", ...}
#
# Erreurs : celles ci-dessus.

from core use len, type
use audio.audio_errors as _aerr
use audio.audio_effects as _fx
use microphone.microphone_info as _mi

const MICROPHONE := "MicrophoneError"
const UNAVAILABLE := "MicrophoneUnavailable"
const CAPTURE := "CaptureError"

func diagnose():
    d := _aerr.diagnose()
    mics := []
    try:
        mics = [m.describe() for m in _mi.microphones()]
    catch e:
        mics = []
    advice := d["advice"]
    if advice == null and len(mics) == 0 and d["server"] == null:
        advice = "aucune entrée audio ALSA : brancher un micro, ou vérifier que le conteneur expose /dev/snd"
    return {"microphones": mics, "recorder": d["recorder"], "server": d["server"], "advice": advice,
            "ok": d["recorder"] != null and (len(mics) > 0 or d["server"] != null)}

func require_microphone():
    d := diagnose()
    if not d["ok"]:
        raise(UNAVAILABLE, "capture impossible : " + str(d["advice"]))
    return d

# Vérifie un enregistrement (audio_stream.AudioBuffer ou liste d'échantillons).
func check_recording(buf, silence_db=-70.0):
    s := buf
    if type(buf) != "list":
        s = buf.samples
    if len(s) == 0:
        return {"ok": false, "problem": "enregistrement vide", "rms_db": null, "peak": 0.0}
    q := _aerr.check_samples(s)
    rms := _fx.gain_to_db(_fx.rms(s))
    problem := null
    if q["silent"] or rms < silence_db:
        problem = "silence complet (micro coupé, mauvais périphérique ou gain nul)"
    elif q["clip_ratio"] > 0.01:
        problem = "saturation (" + str(q["clipped"]) + " échantillons écrêtés) : baisser le gain"
    return {"ok": problem == null, "problem": problem, "rms_db": rms, "peak": q["peak"]}

func is_microphone_error(t):
    return t == MICROPHONE or t == UNAVAILABLE or t == CAPTURE
