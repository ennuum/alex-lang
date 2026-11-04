# ALEX STANDARD LIBRARY — multimedia.platform.windows
#
# Dorsaux multimédias sous Windows : son par ffplay (sortie par défaut), micro et caméra par ffmpeg DirectShow
# (hardware._windows), écran par gdigrab, codecs par ffmpeg. Validé sur Windows 11 x64 avec ffmpeg 9 (Gyan) : toute
# la suite tests/multimedia et tests/media, plus carte son, micro, caméra et écran réels (ALEX_MEDIA_REAL=1).
# Limite : le bac à sable (security.sandbox) n'y pose ni limite mémoire / processeur ni isolement réseau.
#
#   use multimedia.platform.windows as win
#   print(win.report())

use hardware._sys as _sys
use hardware._windows as _win
use multimedia.backends.codecs.ffmpeg as _ff

const SUPPORT := {"audio_playback": "validé (ffplay)", "audio_capture": "validé (ffmpeg dshow)",
    "camera": "validé (ffmpeg dshow)", "screen_capture": "validé (gdigrab)", "codecs_system": "validé (ffmpeg)",
    "pure_alex": "validé", "sandbox": "partiel : délai et environnement seulement"}

func report():
    return {"platform": "windows", "supported": true, "ffmpeg": _ff.available(),
            "ffplay": _sys.find_tool(["ffplay"]) != null, "support": SUPPORT,
            "cameras": [d["name"] for d in _win.dshow_video()], "microphones": [d["name"] for d in _win.dshow_audio()],
            "sound_cards": _win.sound_cards(),
            "note": "installer ffmpeg (ffmpeg.exe, ffprobe.exe, ffplay.exe dans le PATH ; winget install Gyan.FFmpeg)"}
