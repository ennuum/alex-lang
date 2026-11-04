# ALEX STANDARD LIBRARY — web.http.version
#
# Versions du protocole HTTP (RFC 9110 §2.5, RFC 9112 §2.3) : « HTTP/1.0 », « HTTP/1.1 » (texte), « HTTP/2 » et
# « HTTP/3 » (binaires, cités pour information). Ce paquet parle HTTP/1.x ; les autres sont reconnues pour
# produire une réponse 505 correcte.
#
#   use web.http.version as v
#   x := v.parse("HTTP/1.1")       # x.major == 1, x.minor == 1
#   x.supports_keep_alive_by_default()   # true (1.0 : seulement avec « Connection: keep-alive »)
#   v.is_supported("HTTP/2.0")     # false
#   str(v.HTTP_1_1)                # HTTP/1.1
#
# Erreurs : HttpVersionError.

from core use len, type
use string as _s
use web.http.http_errors as _err

class Version:
    func init(major=1, minor=1):
        self.major = major
        self.minor = minor

    func text():
        if self.major >= 2 and self.minor == 0:
            return "HTTP/" + str(self.major)
        return "HTTP/" + str(self.major) + "." + str(self.minor)

    func __str__():
        return self.text()

    func __eq__(other):
        if type(other) == "str":
            return self.text() == other
        return isinstance(other, Version) and other.major == self.major and other.minor == self.minor

    func __lt__(other):
        return self.major < other.major or (self.major == other.major and self.minor < other.minor)

    func __le__(other):
        return self == other or self < other

    func __gt__(other):
        return not (self <= other)

    func __ge__(other):
        return not (self < other)

    func is_http11():
        return self.major == 1 and self.minor >= 1

    func is_http10():
        return self.major == 1 and self.minor == 0

    # HTTP/1.1 garde la connexion ouverte par défaut ; HTTP/1.0 la ferme.
    func supports_keep_alive_by_default():
        return self.is_http11()

    # Codage « chunked » utilisable (HTTP/1.1).
    func supports_chunked():
        return self.is_http11()

    func copy():
        return Version(self.major, self.minor)

const HTTP_1_0_TEXT := "HTTP/1.0"
const HTTP_1_1_TEXT := "HTTP/1.1"

HTTP_1_0 := Version(1, 0)
HTTP_1_1 := Version(1, 1)

func _digit(c):
    if c >= '0' and c <= '9':
        return _s.ord(c) - 48
    return -1

# Analyse « HTTP/x.y » (forme stricte RFC 9112 : un chiffre de chaque côté) ; « HTTP/2 » et « HTTP/3 » acceptés.
func parse(text):
    fn := "version.parse"
    if type(text) != "str" or not _s.starts_with(text, "HTTP/"):
        _err.version_error(fn, "version HTTP invalide '" + str(text) + "'", 400)
    rest := text[5:len(text)]
    if len(rest) == 1 and _digit(rest[0]) >= 2:
        return Version(_digit(rest[0]), 0)
    if len(rest) != 3 or rest[1] != '.' or _digit(rest[0]) < 0 or _digit(rest[2]) < 0:
        _err.version_error(fn, "version HTTP invalide '" + text + "'", 400)
    return Version(_digit(rest[0]), _digit(rest[2]))

func try_parse(text):
    try:
        return parse(text)
    catch e:
        return null

# Versions prises en charge par ce paquet : HTTP/1.0 et HTTP/1.1 (et 1.x supérieures, traitées comme 1.1).
func is_supported(text):
    v := try_parse(text)
    return v != null and v.major == 1

# Version validée et prise en charge ; HttpVersionError (505) sinon.
func require_supported(text):
    v := parse(text)
    if v.major != 1:
        _err.version_error("version.require_supported", "version non prise en charge '" + text + "'")
    return v

# Version de réponse pour une requête : la plus haute commune (HTTP/1.1 au plus).
func response_version_for(request_version):
    v := request_version
    if type(v) == "str":
        v = parse(v)
    if v.major == 1 and v.minor == 0:
        return Version(1, 0)
    return Version(1, 1)
