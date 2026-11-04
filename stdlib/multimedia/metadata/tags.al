# ALEX STANDARD LIBRARY — multimedia.metadata.tags
#
# Étiquettes normalisées d'un média : title, artist, album, album_artist, date, genre, track, disc, comment,
# composer, copyright, encoder, language. Les noms propres aux formats (RIFF INFO « INAM », ID3 « TIT2 »,
# Vorbis « TITLE », PNG « Title »...) sont ramenés à ces clés ; les clés inconnues sont gardées telles quelles
# (en minuscules).
#
#   use multimedia.metadata.tags as tg
#   t := tg.Tags({"INAM": "Bonjour", "IART": "Moi"})
#   print(t.get("title"), t.get("artist"))        # Bonjour Moi
#   t.set("track", "3/12")
#   print(t.track_number(), t.track_total())       # 3 12
#   riff := t.to_format("riff")                    # {"INAM": "Bonjour", "IART": "Moi", "ITRK": "3/12"}
#
# Erreurs : FormatError (format de destination inconnu).

from core use len, type, to_int
from collections use append, keys
use string as _s
use multimedia.core.errors as merr

const STANDARD := ["title", "artist", "album", "album_artist", "date", "genre", "track", "disc", "comment",
    "composer", "copyright", "encoder", "language"]

# Noms propres aux formats -> clé normalisée.
const ALIASES := {"inam": "title", "iart": "artist", "iprd": "album", "icrd": "date", "ignr": "genre",
    "itrk": "track", "iprt": "track", "icmt": "comment", "icop": "copyright", "isft": "encoder", "ilng": "language",
    "imus": "composer",
    "tit2": "title", "tpe1": "artist", "talb": "album", "tpe2": "album_artist", "tyer": "date", "tdrc": "date",
    "tcon": "genre", "trck": "track", "tpos": "disc", "comm": "comment", "tcom": "composer", "tcop": "copyright",
    "tsse": "encoder", "tlan": "language",
    "albumartist": "album_artist", "album artist": "album_artist", "tracknumber": "track", "discnumber": "disc",
    "year": "date", "description": "comment", "author": "artist", "software": "encoder", "creation time": "date"}

const FORMATS := {
    "riff": {"title": "INAM", "artist": "IART", "album": "IPRD", "date": "ICRD", "genre": "IGNR", "track": "ITRK",
             "comment": "ICMT", "copyright": "ICOP", "encoder": "ISFT", "language": "ILNG", "composer": "IMUS"},
    "id3": {"title": "TIT2", "artist": "TPE1", "album": "TALB", "album_artist": "TPE2", "date": "TDRC",
            "genre": "TCON", "track": "TRCK", "disc": "TPOS", "composer": "TCOM", "copyright": "TCOP",
            "encoder": "TSSE", "language": "TLAN"},
    "vorbis": {"title": "TITLE", "artist": "ARTIST", "album": "ALBUM", "album_artist": "ALBUMARTIST",
               "date": "DATE", "genre": "GENRE", "track": "TRACKNUMBER", "disc": "DISCNUMBER",
               "comment": "COMMENT", "composer": "COMPOSER", "copyright": "COPYRIGHT", "encoder": "ENCODER",
               "language": "LANGUAGE"},
    "png": {"title": "Title", "artist": "Author", "comment": "Comment", "copyright": "Copyright",
            "date": "Creation Time", "encoder": "Software"}}

func normalize_key(k):
    low := _s.lower(_s.trim(str(k)))
    if low in ALIASES:
        return ALIASES[low]
    return low

func _clean(v):
    t := _s.trim(str(v))
    # zéros de fin (chaînes C des conteneurs)
    while len(t) > 0 and _s.ends_with(t, "\0"):
        t = _s.substring(t, 0, len(t) - 1)
    return t

class Tags:
    func init(values=null):
        self.values = {}
        if values != null:
            self.update(values)

    func set(key, value):
        if value == null:
            return self
        v := _clean(value)
        if len(v) == 0:
            return self
        self.values[normalize_key(key)] = v
        return self

    func get(key, default=null):
        k := normalize_key(key)
        if k in self.values:
            return self.values[k]
        return default

    func has(key):
        return normalize_key(key) in self.values

    func remove(key):
        k := normalize_key(key)
        out := {}
        for x in keys(self.values):
            if x != k:
                out[x] = self.values[x]
        self.values = out
        return self

    # Ajoute (et remplace) les valeurs d'un dict ou d'un autre Tags.
    func update(other):
        src := other.values if type(other) == "instance" else other
        for k in keys(src):
            self.set(k, src[k])
        return self

    # Ajoute seulement les clés absentes.
    func merge_missing(other):
        src := other.values if type(other) == "instance" else other
        for k in keys(src):
            if not self.has(k):
                self.set(k, src[k])
        return self

    func _number(key, part):
        v := self.get(key)
        if v == null:
            return null
        ps := _s.split(v, "/")
        if part >= len(ps):
            return null
        t := _s.trim(ps[part])
        if len(t) == 0:
            return null
        for c in _s.byte_unpack(t):
            if c < 48 or c > 57:
                return null
        return to_int(t)

    func track_number():
        return self._number("track", 0)

    func track_total():
        return self._number("track", 1)

    func disc_number():
        return self._number("disc", 0)

    # Année (4 chiffres en tête de la date), ou null.
    func year():
        d := self.get("date")
        if d == null or len(d) < 4:
            return null
        y := _s.substring(d, 0, 4)
        for c in _s.byte_unpack(y):
            if c < 48 or c > 57:
                return null
        return to_int(y)

    func names():
        return keys(self.values)

    func is_empty():
        return len(keys(self.values)) == 0

    # Dict aux noms du format (« riff », « id3 », « vorbis », « png ») ; les clés sans équivalent sont omises.
    func to_format(fmt):
        if not (fmt in FORMATS):
            merr.fail(merr.FORMAT, "format d'étiquettes inconnu : " + str(fmt))
        table := FORMATS[fmt]
        out := {}
        for k in keys(self.values):
            if k in table:
                out[table[k]] = self.values[k]
        return out

    func to_dict():
        out := {}
        for k in keys(self.values):
            out[k] = self.values[k]
        return out

    func describe():
        parts := []
        for k in STANDARD:
            if k in self.values:
                append(parts, k + "=" + self.values[k])
        for k in keys(self.values):
            if not (k in STANDARD):
                append(parts, k + "=" + self.values[k])
        return _s.join(", ", parts)

func of(values):
    return Tags(values)
