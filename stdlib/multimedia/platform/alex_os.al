# ALEX STANDARD LIBRARY — multimedia.platform.alex_os
#
# ALEX OS (noyau du dépôt, examples/noyau) : pas d'outils système (ffmpeg, lecteurs) ; le code multimédia en ALEX
# pur fonctionne s'il est compilé dans l'image ; l'affichage passe par pixmap / gui et le son par les pilotes
# matériels (stdlib/hardware, stdlib/driver) quand ils sont présents. Lecture et capture : non branchées ici.
#
#   use multimedia.platform.alex_os as aos
#   print(aos.report())

use multimedia.core.errors as merr

const SUPPORT := {"audio_playback": "non pris en charge (pilote son à brancher)", "audio_capture": "non pris en charge",
    "camera": "non pris en charge", "screen_capture": "possible par pixmap (tampon de trame), non branché",
    "codecs_system": "non pris en charge (pas de ffmpeg)", "pure_alex": "non validé (portable, non exécuté)"}

func report():
    return {"platform": "alex_os", "supported": false, "support": SUPPORT,
            "note": "utiliser les décodeurs ALEX purs (WAV, FLAC, Ogg FLAC, PNG, BMP, PNM) et pixmap pour l'affichage"}

func require_backend(name):
    merr.unsupported("dorsal ALEX OS « " + str(name) + " »", "non branché")
