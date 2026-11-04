# ALEX STANDARD LIBRARY — multimedia.security.validation
#
# Lecture BORNÉE des données binaires non fiables : chaque accès vérifie qu'il reste dans les octets disponibles
# et lève CorruptDataError (avec la position) au lieu de lire au-delà. Utilisée par les conteneurs et décodeurs.
#
#   use multimedia.security.validation as v
#   r := v.Reader(octets, "fichier.wav")
#   if r.tag(0) == "RIFF":
#       taille := r.u32le(4)
#   r.need(12, 8, "en-tête de bloc")          # CorruptDataError si [12, 20) dépasse les données
#   v.check_magic(octets, 0, [137, 80, 78, 71], "PNG")
#   v.check_chunk(position, taille, total, "bloc data")
#
# Erreurs : CorruptDataError, FormatError.

from core use len, type
use string as _s
use multimedia.core.errors as merr

class Reader:
    func init(data, name="données"):
        if type(data) != "list":
            merr.fail(merr.FORMAT, name + " : octets attendus (list[int])")
        self.data = data
        self.name = name
        self.size = len(data)

    func need(at, n, what="lecture"):
        if at < 0 or n < 0 or at + n > self.size:
            merr.corrupt(self.name, what + " hors des données (position " + str(at) + ", " + str(n) + " octets, taille " + str(self.size) + ")")

    func u8(at):
        self.need(at, 1)
        return self.data[at]

    func u16le(at):
        self.need(at, 2)
        return self.data[at] | (self.data[at + 1] << 8)

    func u16be(at):
        self.need(at, 2)
        return (self.data[at] << 8) | self.data[at + 1]

    func u32le(at):
        self.need(at, 4)
        return self.data[at] | (self.data[at + 1] << 8) | (self.data[at + 2] << 16) | (self.data[at + 3] << 24)

    func u32be(at):
        self.need(at, 4)
        return (self.data[at] << 24) | (self.data[at + 1] << 16) | (self.data[at + 2] << 8) | self.data[at + 3]

    func s32le(at):
        v := self.u32le(at)
        if v >= 2147483648:
            return v - 4294967296
        return v

    # 4 octets ASCII (« RIFF », « IHDR »...), "" s'ils ne sont pas imprimables.
    func tag(at, n=4):
        self.need(at, n, "étiquette")
        for k in at..at + n:
            c := self.data[k]
            if c < 32 or c > 126:
                return ""
        return _s.byte_pack([self.data[k] for k in at..at + n])

    func bytes(at, n):
        self.need(at, n)
        return [self.data[k] for k in at..at + n]

    func text(at, n):
        b := self.bytes(at, n)
        end := len(b)
        for k in 0..len(b):
            if b[k] == 0:
                end = k
                break
        return _s.byte_pack([b[k] for k in 0..end])

func check_magic(data, at, magic, what):
    if at + len(magic) > len(data):
        merr.corrupt(what, "signature tronquée")
    for k in 0..len(magic):
        if data[at + k] != magic[k]:
            merr.corrupt(what, "signature invalide")

# Bloc [at, at + size) d'un conteneur de `total` octets.
func check_chunk(at, size, total, what):
    if size < 0 or at < 0:
        merr.corrupt(what, "taille négative")
    if at + size > total:
        merr.corrupt(what, "déclare " + str(size) + " octets à la position " + str(at) + " mais le fichier n'en a que " + str(total) + " (fichier tronqué ?)")

func check_positive_int(value, what):
    if type(value) != "int" or value <= 0:
        merr.corrupt(what, "valeur invalide " + str(value))
    return value

func is_bytes(data):
    if type(data) != "list":
        return false
    for b in data:
        if type(b) != "int" or b < 0 or b > 255:
            return false
    return true
