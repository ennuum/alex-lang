# ALEX STANDARD LIBRARY — web.client.client_response
#
# ClientResponse : la réponse reçue par le client. C'est une web.http.response.Response (statut, en-têtes, corps
# en octets) enrichie de ce qui concerne l'appel : URL finale, requête, historique des redirections, durée,
# connexion réutilisée, et de lectures pratiques (texte décodé selon le charset, JSON, liens « Link »).
#
#   r := client.get("https://api.exemple.org/notes")
#   r.status, r.ok()                   # 200 true
#   r.text()                           # corps décodé (UTF-8 par défaut, ISO-8859-1 / ASCII reconnus)
#   r.json()                           # valeur JSON (JSONError si invalide)
#   r.header("content-type")
#   r.url.href(), len(r.history)       # URL finale, redirections suivies
#   r.elapsed                          # secondes
#   r.links()                          # {"next": "https://…?page=2", ...} depuis l'en-tête Link
#   r.raise_for_status()               # HttpStatusError si 4xx / 5xx
#
# Erreurs : HttpStatusError, JSONError, ClientResponseError (charset non pris en charge en mode strict).

from core use len, type
from collections use append
use string as _s
use web.client.client_errors as _err
use web.http.response as _response
from web.http.response use Response
use web.http.header_value as _hv
use web.http.message_body as _mb
use web.url.url as _url

class ClientResponse extends Response:
    # Charset déclaré (en minuscules), ou null.
    func encoding():
        m := self.content_type()
        if m == null:
            return null
        return m.charset()

    # Corps décodé en texte : UTF-8 (défaut), ISO-8859-1 / windows-1252 / US-ASCII convertis ; octets UTF-8
    # invalides remplacés par U+FFFD.
    func text():
        cs := self.encoding()
        if cs == null or cs == "utf-8" or cs == "utf8" or cs == "us-ascii" or cs == "ascii":
            return _valid_utf8(self.body)
        if cs == "iso-8859-1" or cs == "latin1" or cs == "latin-1" or cs == "windows-1252" or cs == "cp1252":
            return _latin1(self.body)
        return _valid_utf8(self.body)

    # Corps JSON décodé (null si vide).
    func json():
        return _mb.parse_json(self.text())

    # Octets bruts du corps.
    func content():
        return self.body

    func size():
        return _s.byte_len(self.body)

    # En-tête Link (RFC 8288) : dict rel -> URL absolue.
    func links():
        out := {}
        v := self.headers.get("link", null, true)
        if v == null:
            return out
        for item in _hv.split_list(v):
            lt := _s.find(item, "<")
            gt := _s.find(item, ">")
            if lt < 0 or gt < lt:
                continue
            target := item[lt + 1:gt]
            pr := _hv.parse_parameters("x" + item[gt + 1:len(item)])
            rel := pr[1]["rel"] if "rel" in pr[1] else null
            if rel == null:
                continue
            absolute := target
            if self.url != null:
                try:
                    absolute = self.url.join(target).href()
                catch e:
                    absolute = target
            for r in _s.split(rel, " "):
                if r != "":
                    out[_s.lower(r)] = absolute
        return out

    func is_permanent_redirect():
        return self.status == 301 or self.status == 308

    # Résumé « 200 OK GET https://… (0.123 s) ».
    func summary():
        m := self.request.method if self.request != null else "?"
        u := self.url.redacted() if self.url != null else "?"
        t := ""
        if self.elapsed != null:
            t = " (" + str(self.elapsed) + " s)"
        return str(self.status) + " " + self.reason + " " + m + " " + u + t

    func __str__():
        return "<ClientResponse " + str(self.status) + " " + self.reason + ">"

func _valid_utf8(data):
    bytes := _s.byte_unpack(data)
    ok := true
    i := 0
    n := len(bytes)
    while i < n:
        b := bytes[i]
        if b < 128:
            i += 1
            continue
        k := 0
        if b >= 194 and b <= 223:
            k = 1
        elif b >= 224 and b <= 239:
            k = 2
        elif b >= 240 and b <= 244:
            k = 3
        else:
            ok = false
            break
        if i + k >= n:
            ok = false
            break
        j := 1
        while j <= k:
            if bytes[i + j] < 128 or bytes[i + j] > 191:
                ok = false
            j += 1
        if not ok:
            break
        i += k + 1
    if ok:
        return data
    out := []
    i = 0
    while i < n:
        b := bytes[i]
        if b < 128:
            append(out, b)
            i += 1
        else:
            # séquence vérifiée octet par octet, sinon U+FFFD
            k := 0
            if b >= 194 and b <= 223:
                k = 1
            elif b >= 224 and b <= 239:
                k = 2
            elif b >= 240 and b <= 244:
                k = 3
            good := k > 0 and i + k < n
            if good:
                j := 1
                while j <= k:
                    if bytes[i + j] < 128 or bytes[i + j] > 191:
                        good = false
                    j += 1
            if good:
                j := 0
                while j <= k:
                    append(out, bytes[i + j])
                    j += 1
                i += k + 1
            else:
                append(out, 239)
                append(out, 191)
                append(out, 189)
                i += 1
    return _s.byte_pack(out)

const _CP1252 := [8364, 129, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 352, 8249, 338, 141, 381, 143, 144, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, 353, 8250, 339, 157, 382, 376]

func _latin1(data):
    out := []
    for b in _s.byte_unpack(data):
        cp := b
        if b >= 128 and b <= 159:
            cp = _CP1252[b - 128]
        append(out, str(_s.chr(cp)))
    return _s.join("", out)

# ClientResponse depuis une web.http Response lue sur le réseau.
func from_response(resp, request=null, url=null, elapsed=null):
    r := ClientResponse(resp.status, resp.body, resp.headers, resp.reason, resp.version)
    r.trailers = resp.trailers
    r.request = request
    r.url = url
    r.elapsed = elapsed
    return r
