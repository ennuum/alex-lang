# ALEX STANDARD LIBRARY — multimedia.security.limits
#
# Limites de ressources appliquées à TOUT fichier multimédia externe (entrée non fiable) : taille du fichier,
# durée, dimensions, nombre de points, de pistes, de canaux, fréquence, nombre d'images, mémoire décodée,
# taille d'un bloc de conteneur et de texte de sous-titres. Les sondeurs, démultiplexeurs et décodeurs les
# vérifient AVANT d'allouer.
#
#   use multimedia.security.limits as lim
#   l := lim.defaults()                         # usage courant (fichier 2 Gio, 6 h, 16384 x 16384...)
#   s := lim.strict()                           # fichiers d'origine inconnue (64 Mio, 10 min, 4096 x 4096...)
#   l2 := l.with({"max_width": 1920, "max_height": 1080})
#   l.check_dimensions(w, h)                    # LimitError si dépassé, FormatError si absurde (<= 0)
#   l.check("max_streams", 12)
#
# Erreurs : LimitError, FormatError.

from core use len, type
from collections use keys
use multimedia.core.errors as merr

const DEFAULTS := {"max_file_bytes": 2147483648, "max_duration": 21600.0, "max_width": 16384, "max_height": 16384,
    "max_pixels": 134217728, "max_streams": 64, "max_channels": 32, "max_rate": 768000, "max_frames": 10000000,
    "max_decoded_bytes": 1073741824, "max_chunk_bytes": 1073741824, "max_text_bytes": 16777216,
    "max_playlist_items": 100000, "max_cues": 200000}

const STRICT := {"max_file_bytes": 67108864, "max_duration": 600.0, "max_width": 4096, "max_height": 4096,
    "max_pixels": 16777216, "max_streams": 8, "max_channels": 8, "max_rate": 192000, "max_frames": 100000,
    "max_decoded_bytes": 268435456, "max_chunk_bytes": 67108864, "max_text_bytes": 1048576,
    "max_playlist_items": 5000, "max_cues": 20000}

const LABELS := {"max_file_bytes": "taille du fichier (octets)", "max_duration": "durée (s)",
    "max_width": "largeur", "max_height": "hauteur", "max_pixels": "nombre de points",
    "max_streams": "nombre de pistes", "max_channels": "nombre de canaux", "max_rate": "fréquence (Hz)",
    "max_frames": "nombre d'images ou de trames", "max_decoded_bytes": "taille décodée (octets)",
    "max_chunk_bytes": "taille d'un bloc (octets)", "max_text_bytes": "taille du texte (octets)",
    "max_playlist_items": "entrées de liste de lecture", "max_cues": "nombre de sous-titres"}

class Limits:
    func init(values=null):
        self.values = {}
        for k in keys(DEFAULTS):
            self.values[k] = DEFAULTS[k]
        if values != null:
            for k in keys(values):
                if not (k in DEFAULTS):
                    merr.fail(merr.FORMAT, "limite inconnue : " + str(k))
                self.values[k] = values[k]

    func get(name):
        if not (name in self.values):
            merr.fail(merr.FORMAT, "limite inconnue : " + str(name))
        return self.values[name]

    func with(changes):
        v := {}
        for k in keys(self.values):
            v[k] = self.values[k]
        for k in keys(changes):
            if not (k in DEFAULTS):
                merr.fail(merr.FORMAT, "limite inconnue : " + str(k))
            v[k] = changes[k]
        return Limits(v)

    # LimitError si value > limite `name` (null : non vérifié).
    func check(name, value):
        if value == null:
            return value
        m := self.get(name)
        if value > m:
            merr.limit(LABELS[name], value, m)
        return value

    func check_dimensions(width, height):
        if type(width) != "int" or type(height) != "int" or width <= 0 or height <= 0:
            merr.fail(merr.FORMAT, "dimensions invalides : " + str(width) + "x" + str(height))
        self.check("max_width", width)
        self.check("max_height", height)
        self.check("max_pixels", width * height)

    func check_audio(rate, channels):
        if type(rate) != "int" or rate <= 0 or type(channels) != "int" or channels <= 0:
            merr.fail(merr.FORMAT, "format audio invalide : " + str(rate) + " Hz, " + str(channels) + " canaux")
        self.check("max_rate", rate)
        self.check("max_channels", channels)

    func check_file_size(n):
        return self.check("max_file_bytes", n)

    func describe():
        out := []
        for k in keys(self.values):
            out = out + [LABELS[k] + " ≤ " + str(self.values[k])]
        return out

func defaults():
    return Limits()

func strict():
    return Limits(STRICT)

func of(l):
    if l == null:
        return Limits()
    return l
