# ALEX STANDARD LIBRARY — web.browser.blob
#
# Blob : données binaires immuables avec type MIME — construites depuis des textes (encodés en UTF-8),
# des listes d'octets ou d'autres Blob ; taille, découpage (slice avec indices négatifs), lecture en texte /
# octets (promesses comme en JavaScript, ou directe avec bytes() / text_now()), conversion en URL data:.
#
#   use web.browser.blob as bl
#   b := bl.Blob(["Bonjour ", "été"], {"type": "text/plain"})
#   b.size, b.type                    # 13 text/plain   (« é » = 2 octets)
#   b.slice(0, 7).text_now()          # Bonjour
#   b.text(loop).wait()               # Bonjour été
#   b.to_data_url()                   # data:text/plain;base64,Qm9uam91ciDDqXTDqQ==
#   bl.from_data_url("data:,a%20b").text_now()   # a b
#
# Erreurs : TypeError (partie non prise en charge), EncodingError (URL data: invalide).

from core use len, type, to_int
from collections use append
use string as _s
use network.encoding as _enc
use web.browser.browser_errors as _err
use web.browser.timers as _tm

func _bytes_of(part, endings):
    if isinstance(part, Blob):
        return part.data
    t := type(part)
    if t == "str":
        p := part
        if endings == "native":
            p = _s.replace(_s.replace(p, "\r\n", "\n"), "\r", "\n")
        return _s.byte_unpack(p)
    if t == "list":
        for b in part:
            if type(b) != "int" or b < 0 or b > 255:
                _err.type_error("Blob", "octet invalide : " + str(b))
        return part
    _err.type_error("Blob", "partie de type " + t + " non prise en charge (str, liste d'octets, Blob)")

class Blob:
    # parts : liste de str / listes d'octets / Blob ; options : {"type": …, "endings": "transparent"|"native"}.
    func init(parts=null, options=null):
        o := options if options != null else {}
        self.type = _s.lower(o["type"]) if "type" in o else ""
        endings := o["endings"] if "endings" in o else "transparent"
        data := []
        for p in (parts if parts != null else []):
            for b in _bytes_of(p, endings):
                append(data, b)
        self.data = data
        self.size = len(data)

    func slice(start=0, end=null, content_type=""):
        n := self.size
        a := start if start >= 0 else n + start
        b := n if end == null else (end if end >= 0 else n + end)
        if a < 0:
            a = 0
        if b > n:
            b = n
        out := Blob(null, {"type": content_type})
        if b > a:
            out.data = self.data[a:b]
            out.size = b - a
        return out

    func bytes():
        return self.data

    func text_now():
        return _s.byte_pack(self.data)

    func text(loop=null):
        return _tm.resolved(loop if loop != null else _tm.default_loop(), self.text_now())

    func array_buffer(loop=null):
        return _tm.resolved(loop if loop != null else _tm.default_loop(), self.data)

    func to_data_url():
        t := self.type if self.type != "" else "application/octet-stream"
        return "data:" + t + ";base64," + _enc.base64_encode(self.data)

    func __str__():
        return "Blob(" + str(self.size) + " octets, " + (self.type if self.type != "" else "sans type") + ")"

func from_text(text, content_type="text/plain;charset=utf-8"):
    return Blob([text], {"type": content_type})

func from_bytes(data, content_type="application/octet-stream"):
    return Blob([data], {"type": content_type})

func _hexval(c):
    if c >= '0' and c <= '9':
        return _s.ord(c) - 48
    if c >= 'a' and c <= 'f':
        return _s.ord(c) - 87
    if c >= 'A' and c <= 'F':
        return _s.ord(c) - 55
    return -1

# Blob depuis une URL data: (« data:[type][;base64],données »).
func from_data_url(url):
    u := str(url)
    if not _s.starts_with(_s.lower(u), "data:"):
        _err.fail(_err.ENCODING, "from_data_url", "URL data: attendue")
    comma := _s.find(u, ",")
    if comma < 0:
        _err.fail(_err.ENCODING, "from_data_url", "« , » manquante dans l'URL data:")
    meta := u[5:comma]
    payload := u[comma + 1:len(u)]
    is_b64 := _s.ends_with(_s.lower(meta), ";base64")
    media := meta[0:len(meta) - 7] if is_b64 else meta
    if media == "":
        media = "text/plain;charset=US-ASCII"
    data := []
    if is_b64:
        try:
            data = _enc.base64_decode_bytes(_s.replace(payload, " ", ""))
        catch e:
            _err.fail(_err.ENCODING, "from_data_url", "base64 invalide")
    else:
        i := 0
        bytes := _s.byte_unpack(payload)
        while i < len(bytes):
            b := bytes[i]
            if b == 37 and i + 2 < len(bytes):
                h := _hexval(str(_s.byte_pack([bytes[i + 1]]))[0])
                l := _hexval(str(_s.byte_pack([bytes[i + 2]]))[0])
                if h >= 0 and l >= 0:
                    append(data, h * 16 + l)
                    i += 3
                    continue
            append(data, b)
            i += 1
    out := Blob(null, {"type": media})
    out.data = data
    out.size = len(data)
    return out
