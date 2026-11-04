# ALEX STANDARD LIBRARY — multimedia.diagnostics.capabilities
#
# Ce que la bibliothèque multimédia peut RÉELLEMENT faire sur cette machine, détecté à l'exécution :
# lecture et capture audio (outils du système), caméra, conteneurs lus et écrits, codecs. Aucune capacité
# n'est supposée : chaque entrée indique ce qui manque et comment l'obtenir.
#
#   use multimedia.diagnostics.capabilities as dcaps
#   c := dcaps.detect()
#   print(c["audio_playback"], c["audio_capture"], c["camera"], c["containers"]["read"])
#   print(dcaps.report())                  # texte lisible
#   dcaps.require("audio_playback")        # DeviceError expliquée si absent

from core use len
from collections use append, keys
use string as _s
use audio.audio_errors as _aerr
use camera.camera_errors as _cerr
use multimedia.core.errors as merr
use multimedia.codec.capabilities as _ccaps
use multimedia.backends.codecs.ffmpeg as _ff
use multimedia.recording.screen_capture as _sc

const CONTAINERS_READ := ["wav", "flac", "ogg"]
const CONTAINERS_WRITE := ["wav", "flac", "ogg"]   # ogg : Ogg FLAC ; + tout conteneur de ffmpeg (backends.codecs.ffmpeg)
const PROBED := ["wav", "flac", "mp3", "png", "bmp", "pnm", "gif", "jpeg", "srt", "vtt", "m3u", "pls", "ogg", "mp4",
    "matroska", "webm", "avi", "aiff", "webp", "tiff", "mpegts", "midi"]

func detect():
    a := null
    try:
        a = _aerr.diagnose()
    catch e:
        a = {"can_play": false, "can_record": false, "player": null, "recorder": null, "advice": e.message}
    cam := null
    try:
        cam = _cerr.diagnose()
    catch e:
        cam = {"advice": e.message}
    cam_ok := "ok" in cam and cam["ok"]
    # Codecs de ffmpeg déclarés dans le registre avant d'en faire la liste (sinon « non disponibles » à tort).
    _ff.install()
    return {"audio_playback": a["can_play"], "audio_capture": a["can_record"], "audio_player": a["player"],
            "audio_recorder": a["recorder"], "audio_advice": a["advice"], "camera": cam_ok, "camera_details": cam,
            "containers": {"read": CONTAINERS_READ, "write": CONTAINERS_WRITE, "probe": PROBED},
            "images": {"decode": _ccaps.decodable("image"), "encode": _ccaps.encodable("image")},
            "codecs": {"decode": _ccaps.decodable(), "encode": _ccaps.encodable(), "missing": _ccaps.missing()},
            "system_codecs": _ff.available(), "screen_capture": _sc.available(),
            "video_playback": _ff.available(),
            "video_note": "lecture vidéo par l'adaptateur système ffmpeg" if _ff.available() else "lecture vidéo : installer ffmpeg (aucun décodeur vidéo en ALEX pur)"}

func require(name):
    c := detect()
    if not (name in c):
        merr.fail(merr.FORMAT, "capacité inconnue : " + str(name))
    if not c[name]:
        advice := ""
        if _s.starts_with(name, "audio") and c["audio_advice"] != null:
            advice = " : " + c["audio_advice"]
        merr.fail(merr.DEVICE, "capacité « " + name + " » absente sur cette machine" + advice)
    return true

func _yn(v):
    return "oui" if v else "non"

func report():
    c := detect()
    out := ["lecture audio : " + _yn(c["audio_playback"]) + (" (" + str(c["audio_player"]) + ")" if c["audio_player"] != null else ""),
            "capture audio : " + _yn(c["audio_capture"]) + (" (" + str(c["audio_recorder"]) + ")" if c["audio_recorder"] != null else ""),
            "caméra : " + _yn(c["camera"]),
            "capture d'écran : " + _yn(c["screen_capture"]),
            "codecs système (ffmpeg) : " + _yn(c["system_codecs"]),
            "conteneurs lus : " + _s.join(", ", c["containers"]["read"]) + " ; écrits : " + _s.join(", ", c["containers"]["write"]),
            "images décodées : " + _s.join(", ", c["images"]["decode"]) + " ; encodées : " + _s.join(", ", c["images"]["encode"]),
            "codecs non disponibles : " + _s.join(", ", c["codecs"]["missing"]),
            c["video_note"]]
    if c["audio_advice"] != null:
        append(out, "conseil audio : " + c["audio_advice"])
    return _s.join("\n", out)
