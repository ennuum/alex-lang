# ALEX STANDARD LIBRARY — audio.audio_errors
#
# Erreurs du son et DIAGNOSTIC de la chaîne audio de la machine : cartes ALSA présentes, outils de lecture et
# de capture installés (aplay, pw-play, paplay, ffplay / arecord, pw-record, parecord, ffmpeg), serveur de son
# (PipeWire, PulseAudio), droits sur /dev/snd ; et contrôle de la qualité d'échantillons (valeurs non finies,
# écrêtage, silence numérique).
#   AudioError          erreur générale
#   AudioDeviceError    pas de lecteur / d'enregistreur, carte absente ou occupée
#   AudioFormatError    format PCM, fréquence ou nombre de canaux invalides
#   AudioBufferError    tampon plein, vide, ou données mal alignées sur les trames
#
#   use audio.audio_errors as aerr
#   d := aerr.diagnose()
#   print(d["can_play"], d["player"], d["cards"], d["advice"])
#   q := aerr.check_samples(echantillons)        # {"clipped": 12, "non_finite": 0, "silent": false, ...}
#   aerr.require_player()                         # AudioDeviceError expliquée s'il n'y a aucun lecteur
#
# Erreurs : celles ci-dessus.

from core use len, type
from collections use append
use string as _s
use os as _os
use io as _io
use hardware._sys as _sys
use hardware._windows as _win

const AUDIO := "AudioError"
const DEVICE := "AudioDeviceError"
const FORMAT := "AudioFormatError"
const BUFFER := "AudioBufferError"

const PLAYERS := ["aplay", "pw-play", "paplay", "ffplay"]
const RECORDERS := ["arecord", "pw-record", "parecord", "ffmpeg"]

func _cards():
    out := []
    if _win.is_windows():
        return _win.sound_cards()
    txt := null
    try:
        txt = _io.read_file(_sys.p("/proc/asound/cards"))
    catch e:
        return out
    for line in _s.split(txt, "\n"):
        t := _s.trim(line)
        if len(t) > 0 and t[0] >= '0' and t[0] <= '9' and _s.contains(t, "]:"):
            append(out, _s.trim(_s.split(t, "]:")[1]))
    return out

func _server():
    rt := _os.get_env("XDG_RUNTIME_DIR", null)
    if rt != null:
        if _os.exists(rt + "/pipewire-0"):
            return "pipewire"
        if _os.exists(rt + "/pulse/native"):
            return "pulseaudio"
    return null

func diagnose():
    player := _sys.find_tool(PLAYERS)
    recorder := _sys.find_tool(RECORDERS)
    cards := _cards()
    snd := _os.isdir("/dev/snd")
    advice := null
    if _win.is_windows():
        if player == null and recorder == null:
            advice = "aucun outil audio : installer ffmpeg (ffplay.exe, ffmpeg.exe dans le PATH)"
        elif len(cards) == 0:
            advice = "aucune carte son Windows (Win32_SoundDevice)"
        elif recorder != null and len(_win.dshow_audio()) == 0:
            advice = "aucune entrée audio DirectShow (microphone désactivé ou refusé dans Confidentialité)"
        return {"player": player, "recorder": recorder, "can_play": player != null and len(cards) > 0,
                "can_record": recorder != null and len(_win.dshow_audio()) > 0, "cards": cards, "server": "windows",
                "dev_snd": false, "advice": advice}
    if player == null and recorder == null:
        advice = "aucun outil audio : installer alsa-utils (aplay / arecord), pipewire ou ffmpeg"
    elif len(cards) == 0 and _server() == null:
        advice = "aucune carte son ALSA ni serveur de son : machine sans audio (serveur, conteneur)"
    elif not snd and _server() == null:
        advice = "/dev/snd absent : le conteneur n'expose pas le son"
    return {"player": player, "recorder": recorder, "can_play": player != null, "can_record": recorder != null,
            "cards": cards, "server": _server(), "dev_snd": snd, "advice": advice}

func require_player():
    d := diagnose()
    if d["player"] == null:
        raise(DEVICE, "aucun lecteur audio (" + _s.join(", ", PLAYERS) + ") : " + str(d["advice"]))
    return d["player"]

func require_recorder():
    d := diagnose()
    if d["recorder"] == null:
        raise(DEVICE, "aucun outil de capture (" + _s.join(", ", RECORDERS) + ") : " + str(d["advice"]))
    return d["recorder"]

func check_format(rate, channels, sample_format=null):
    if type(rate) != "int" or rate < 1000 or rate > 768000:
        raise(FORMAT, "fréquence d'échantillonnage invalide : " + str(rate))
    if type(channels) != "int" or channels < 1 or channels > 32:
        raise(FORMAT, "nombre de canaux invalide : " + str(channels))
    if sample_format != null and not (sample_format in ["u8", "s16le", "s24le", "s32le", "f32le"]):
        raise(FORMAT, "format d'échantillon inconnu : " + str(sample_format))

func check_frames(samples, channels):
    if len(samples) % channels != 0:
        raise(BUFFER, str(len(samples)) + " échantillons : pas un nombre entier de trames de " + str(channels) + " canaux")

# Qualité d'échantillons flottants (-1..1).
func check_samples(samples, clip_level=0.999):
    clipped := 0
    nonfinite := 0
    peak := 0.0
    for x in samples:
        if x != x or x > 1e30 or x < -1e30:
            nonfinite += 1
            continue
        a := x
        if a < 0:
            a = -a
        if a > peak:
            peak = a
        if a >= clip_level:
            clipped += 1
    n := len(samples)
    ratio := 0.0
    if n > 0:
        ratio = clipped / n
    return {"samples": n, "clipped": clipped, "clip_ratio": ratio, "non_finite": nonfinite, "peak": peak,
            "silent": peak == 0.0}

func is_audio_error(t):
    return t == AUDIO or t == DEVICE or t == FORMAT or t == BUFFER
