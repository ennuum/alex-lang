# ALEX STANDARD LIBRARY — multimedia.core.stream
#
# Description des fichiers et de leurs pistes (résultat du sondage, état d'un démultiplexeur) :
#   - StreamInfo : index, genre, codec, format (AudioFormat ou VideoFormat), base de temps, durée, nombre de
#                  trames / images, langue, titre, prise en charge (decodable) ;
#   - MediaInfo  : chemin, conteneur, taille, durée, pistes, étiquettes, avertissements.
#
#   use multimedia.core.stream as ms
#   info := probe.probe("voix.wav")
#   a := info.first("audio")
#   print(info.describe(), a.codec, a.format.describe(), info.duration)

from core use len, to_int
from collections use append
use multimedia.core.timestamp as ts
use multimedia.core.format as mf

class StreamInfo:
    func init(index, kind, codec, fmt=null, time_base=null):
        self.index = index
        self.kind = mf.check_kind(kind)
        self.codec = codec
        self.format = fmt
        self.time_base = time_base if time_base != null else ts.MILLIS
        self.duration = null
        self.frames = null
        self.bit_rate = null
        self.language = null
        self.title = null
        self.decodable = false

    func describe():
        d := "#" + str(self.index) + " " + self.kind + " " + str(self.codec)
        if self.format != null:
            if self.kind == "image":
                d = d + ", " + str(self.format.width) + "x" + str(self.format.height) + " " + self.format.pixel_format
            else:
                d = d + ", " + self.format.describe()
        if self.duration != null:
            d = d + ", " + ts.format_clock(self.duration)
        if not self.decodable:
            d = d + " (non décodable ici)"
        return d

class MediaInfo:
    func init(path, container, size=0):
        self.path = path
        self.container = container
        self.size = size
        self.duration = null
        self.streams = []
        self.tags = {}
        self.warnings = []
        self.mime = null

    func add_stream(s):
        append(self.streams, s)
        if s.duration != null and (self.duration == null or s.duration > self.duration):
            self.duration = s.duration
        return s

    func warn(message):
        append(self.warnings, message)

    func of_kind(kind):
        return [s for s in self.streams if s.kind == kind]

    func first(kind):
        for s in self.streams:
            if s.kind == kind:
                return s
        return null

    func has(kind):
        return self.first(kind) != null

    func decodable():
        if len(self.streams) == 0:
            return false
        for s in self.streams:
            if not s.decodable:
                return false
        return true

    func describe():
        d := str(self.container) + ", " + str(self.size) + " octets"
        if self.duration != null:
            d = d + ", " + ts.format_clock(self.duration)
        d = d + ", " + str(len(self.streams)) + " piste(s)"
        return d

    func to_dict():
        st := []
        for s in self.streams:
            f := null
            if s.format != null:
                f = s.format.describe()
            append(st, {"index": s.index, "kind": s.kind, "codec": s.codec, "format": f, "duration": s.duration,
                        "frames": s.frames, "decodable": s.decodable})
        return {"path": self.path, "container": self.container, "mime": self.mime, "size": self.size,
                "duration": self.duration, "streams": st, "tags": self.tags, "warnings": self.warnings}
