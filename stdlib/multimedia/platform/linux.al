# ALEX STANDARD LIBRARY — multimedia.platform.linux
#
# Dorsaux multimédias sous Linux, détectés à l'exécution : son (PipeWire, PulseAudio, ALSA par aplay / pw-play /
# paplay / ffplay et arecord / pw-record / parecord / ffmpeg), caméra (Video4Linux par ffmpeg), écran (x11grab),
# codecs système (ffmpeg). Plateforme de développement : tous les tests de make test-multimedia y passent.
#
#   use multimedia.platform.linux as lx
#   print(lx.report())

use audio.audio_errors as _aerr
use camera.camera_errors as _cerr
use multimedia.backends.codecs.ffmpeg as _ff
use os as _os

# État déclaré par domaine (validé = couvert par les tests du dépôt sur cette plateforme).
const SUPPORT := {"audio_playback": "validé (sortie factice) ; matériel : non validé ici", "audio_capture": "validé (source factice)",
    "camera": "non validé (aucune caméra dans l'environnement de test)", "screen_capture": "validé sous Xvfb (x11grab)",
    "codecs_system": "validé (ffmpeg)", "pure_alex": "validé"}

func report():
    a := {}
    try:
        a = _aerr.diagnose()
    catch e:
        a = {"player": null, "recorder": null, "server": null, "advice": e.message}
    c := {}
    try:
        c = _cerr.diagnose()
    catch e:
        c = {"devices": [], "ok": false}
    return {"platform": "linux", "supported": true, "audio_player": a["player"], "audio_recorder": a["recorder"],
            "sound_server": a["server"] if "server" in a else null, "audio_advice": a["advice"],
            "cameras": c["devices"] if "devices" in c else [], "camera_ok": c["ok"] if "ok" in c else false,
            "display": _os.get_env("DISPLAY", null), "ffmpeg": _ff.available(), "support": SUPPORT}
