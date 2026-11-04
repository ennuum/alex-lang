# ALEX STANDARD LIBRARY — multimedia.platform.platform
#
# Plateforme d'exécution et ce que la bibliothèque y sait faire RÉELLEMENT. Les modules propres à chaque système
# (multimedia.platform.linux, windows, android, alex_os) décrivent leurs dorsaux ; rien n'est annoncé sans
# chemin d'exécution réel (pas d'iOS : aucune chaîne de construction).
#
#   use multimedia.platform.platform as plat
#   print(plat.current())                 # "linux", "windows", "macos", "android", "alex_os", "inconnu"
#   print(plat.report())                  # dorsaux audio / vidéo / écran de la plateforme courante
#   print(plat.matrix())                  # matrice de compatibilité de toutes les plateformes

from core use len
from collections use keys
use os as _os
use string as _s
use multimedia.platform.linux as _linux
use multimedia.platform.windows as _windows
use multimedia.platform.android as _android
use multimedia.platform.alex_os as _alexos

func current():
    n := ""
    try:
        n = _s.lower(str(_os.platform()))
    catch e:
        n = ""
    if _os.exists("/system/build.prop") or _s.contains(n, "android"):
        return "android"
    if _s.contains(n, "linux"):
        return "linux"
    if _s.contains(n, "win"):
        return "windows"
    if _s.contains(n, "darwin") or _s.contains(n, "mac"):
        return "macos"
    if _s.contains(n, "alex") or _s.contains(n, "uefi") or _s.contains(n, "none"):
        return "alex_os"
    if _os.exists("/proc/version"):
        return "linux"
    return "inconnu"

func report():
    name := current()
    if name == "linux":
        return _linux.report()
    if name == "windows":
        return _windows.report()
    if name == "android":
        return _android.report()
    if name == "alex_os":
        return _alexos.report()
    return {"platform": name, "supported": false, "note": "plateforme sans dorsal multimédia déclaré"}

# Matrice de compatibilité (déclarée) : plateforme -> domaine -> état ("validé", "non validé", "non pris en charge").
func matrix():
    return {"linux": _linux.SUPPORT, "windows": _windows.SUPPORT, "android": _android.SUPPORT, "alex_os": _alexos.SUPPORT,
            "macos": {"audio_playback": "non validé", "audio_capture": "non validé", "camera": "non validé",
                      "screen_capture": "non validé", "codecs_system": "non validé", "pure_alex": "non validé"},
            "ios": {"note": "non pris en charge : aucune chaîne de construction iOS"}}
