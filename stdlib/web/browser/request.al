# ALEX STANDARD LIBRARY — web.browser.request
#
# Request de l'API Fetch : URL, méthode, en-têtes (Headers à la JavaScript), corps (texte, octets, Blob,
# FormData, URLSearchParams, ou valeur JSON via l'option non standard « json »), mode, credentials, cache,
# redirect, referrer, signal d'annulation, keepalive ; lecture du corps une seule fois (text, json, blob,
# array_buffer, form_data — promesses) et clone().
#
#   use web.browser.request as rq
#   r := rq.Request("https://api.exemple.org/notes", {"method": "POST", "json": {"titre": "Été"}})
#   r.method, r.headers.get("content-type")      # POST application/json
#   r.json(loop).wait()                          # {"titre": "Été"}
#   h := rq.Headers({"Accept": "text/html"})
#   h.append("Accept", "application/json"); h.get("accept")   # text/html, application/json
#
# Erreurs : TypeError (méthode interdite, corps sur GET / HEAD, corps déjà lu, en-tête invalide).

from core use len, type
from collections use append, keys
use string as _s
use json as _json
use web.http.headers as _hh
use web.http.method as _method
use web.browser.browser_errors as _err
use web.browser.timers as _tm
use web.browser.blob as _blob
use web.browser.form_data as _fd
use web.browser.url_search_params as _usp

const FORBIDDEN_METHODS := ["CONNECT", "TRACE", "TRACK"]
const MODES := ["cors", "no-cors", "same-origin", "navigate"]
const CREDENTIALS := ["omit", "same-origin", "include"]
const CACHE_MODES := ["default", "no-store", "reload", "no-cache", "force-cache", "only-if-cached"]
const REDIRECTS := ["follow", "error", "manual"]

# Headers à la JavaScript (noms insensibles à la casse, get() combine les valeurs par « , »).
class Headers:
    func init(init_value=null):
        self.inner = _hh.Headers()
        self.guard = "none"          # "immutable" pour les réponses reçues
        if init_value == null:
            return
        if isinstance(init_value, Headers):
            for p in init_value.entries():
                self.inner.add(p[0], p[1])
        elif type(init_value) == "dict":
            for k in keys(init_value):
                self.append(k, init_value[k])
        elif type(init_value) == "list":
            for p in init_value:
                self.append(p[0], p[1])
        else:
            try:
                for p in init_value.items():
                    self.inner.add(p[0], p[1])
            catch e:
                _err.type_error("Headers", "dict, liste de paires ou Headers attendu")

    func _guard():
        if self.guard == "immutable":
            _err.type_error("Headers", "en-têtes non modifiables")

    func append(name, value):
        self._guard()
        try:
            self.inner.add(str(name), _s.trim(str(value)))
        catch e:
            _err.type_error("Headers.append", "en-tête invalide « " + str(name) + " »")

    func set(name, value):
        self._guard()
        try:
            self.inner.set(str(name), _s.trim(str(value)))
        catch e:
            _err.type_error("Headers.set", "en-tête invalide « " + str(name) + " »")

    func delete(name):
        self._guard()
        self.inner.remove(name)

    func get(name):
        vals := self.inner.get_all(name)
        if len(vals) == 0:
            return null
        return _s.join(", ", vals)

    func get_set_cookie():
        return self.inner.get_all("set-cookie")

    func has(name):
        return self.inner.has(name)

    # Paires (nom en minuscules, valeur combinée), triées par nom.
    func entries():
        names := []
        for n in self.inner.names():
            ln := _s.lower(n)
            if not (ln in names):
                append(names, ln)
        i := 1
        while i < len(names):
            cur := names[i]
            j := i - 1
            while j >= 0 and names[j] > cur:
                names[j + 1] = names[j]
                j -= 1
            names[j + 1] = cur
            i += 1
        out := []
        for n in names:
            if n == "set-cookie":
                for v in self.inner.get_all(n):
                    append(out, (n, v))
            else:
                append(out, (n, self.get(n)))
        return out

    func keys():
        out := []
        for p in self.entries():
            append(out, p[0])
        return out

    func for_each(fn):
        for p in self.entries():
            fn(p[1], p[0], self)

    func to_dict():
        out := {}
        for p in self.entries():
            out[p[0]] = p[1]
        return out

    func __contains__(name):
        return self.has(name)

# ---------------------------------------------------------------- corps

# (octets, type de contenu par défaut ou null) d'un corps d'initialisation.
func extract_body(body):
    if body == null:
        return (null, null)
    if type(body) == "str":
        return (_s.byte_unpack(body), "text/plain;charset=UTF-8")
    if type(body) == "list":
        return (body, null)
    if isinstance(body, _fd.FormData):
        m := body.to_multipart()
        return (_s.byte_unpack(m[0]), m[1])
    if isinstance(body, _usp.URLSearchParams):
        return (_s.byte_unpack(body.to_string()), "application/x-www-form-urlencoded;charset=UTF-8")
    if isinstance(body, _blob.Blob):
        return (body.data, body.type if body.type != "" else null)
    _err.type_error("extract_body", "corps de type " + type(body) + " non pris en charge")

class Body:
    func init_body(data, loop):
        self.body_bytes = data
        self.body_used = false
        self.loop = loop if loop != null else _tm.default_loop()

    func _consume():
        if self.body_used:
            _err.type_error("Body", "corps déjà lu")
        self.body_used = true
        return self.body_bytes if self.body_bytes != null else []

    # Texte du corps sans promesse (non standard, pratique en ALEX ; ne marque pas le corps comme lu).
    func body_text():
        return _s.byte_pack(self.body_bytes) if self.body_bytes != null else ""

    func _promise(fn):
        p := _tm.Promise(self.loop)
        try:
            p.resolve(fn())
        catch e:
            p.reject(_err.ErrorValue(str(e.type), str(e.message)))
        return p

    func text(loop=null):
        return self._promise(() => _s.byte_pack(self._consume()))

    func json(loop=null):
        return self._promise(() => _json.parse(_s.byte_pack(self._consume())))

    func array_buffer(loop=null):
        return self._promise(() => self._consume())

    func blob(loop=null):
        ct := self.headers.get("content-type")
        return self._promise(() => _blob.Blob([self._consume()], {"type": ct if ct != null else ""}))

    func form_data(loop=null):
        return self._promise(() => _form_from(self.headers.get("content-type"), self._consume()))

func _form_from(ctype, data):
    d := _fd.FormData()
    c := _s.lower(ctype if ctype != null else "")
    if _s.starts_with(c, "application/x-www-form-urlencoded"):
        for p in _usp.URLSearchParams(_s.byte_pack(data)).pairs:
            d.append(p[0], p[1])
        return d
    _err.type_error("form_data", "corps non analysable en FormData (type « " + c + " »)")

class Request extends Body:
    func init(input, init_value=null, loop=null):
        o := init_value if init_value != null else {}
        base := null
        if isinstance(input, Request):
            base = input
        self.url = base.url if base != null else str(input)
        m := _s.upper(o["method"] if "method" in o else (base.method if base != null else "GET"))
        if m in FORBIDDEN_METHODS:
            _err.type_error("Request", "méthode interdite « " + m + " »")
        self.method = _method.normalize(m) if m in ["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"] else m
        self.headers = Headers(o["headers"] if "headers" in o else (base.headers if base != null else null))
        self.mode = o["mode"] if "mode" in o else (base.mode if base != null else "cors")
        self.credentials = o["credentials"] if "credentials" in o else (base.credentials if base != null else "same-origin")
        self.cache = o["cache"] if "cache" in o else "default"
        self.redirect = o["redirect"] if "redirect" in o else "follow"
        self.referrer = o["referrer"] if "referrer" in o else "about:client"
        self.referrer_policy = o["referrer_policy"] if "referrer_policy" in o else ""
        self.integrity = o["integrity"] if "integrity" in o else ""
        self.keepalive = o["keepalive"] if "keepalive" in o else false
        self.signal = o["signal"] if "signal" in o else (base.signal if base != null else null)
        self.destination = ""
        for v in [(self.mode, MODES, "mode"), (self.credentials, CREDENTIALS, "credentials"), (self.cache, CACHE_MODES, "cache"), (self.redirect, REDIRECTS, "redirect")]:
            if not (v[0] in v[1]):
                _err.type_error("Request", "valeur de " + v[2] + " invalide « " + str(v[0]) + " »")
        body := o["body"] if "body" in o else null
        ctype := null
        data := null
        if "json" in o:
            data = _s.byte_unpack(_json.stringify(o["json"], null, false))
            ctype = "application/json"
        elif body != null:
            r := extract_body(body)
            data = r[0]
            ctype = r[1]
        elif base != null:
            data = base.body_bytes
        if data != null and (self.method == "GET" or self.method == "HEAD"):
            _err.type_error("Request", "une requête " + self.method + " ne peut pas avoir de corps")
        if ctype != null and not self.headers.has("content-type"):
            self.headers.set("Content-Type", ctype)
        self.init_body(data, loop if loop != null else (base.loop if base != null else null))

    func clone():
        if self.body_used:
            _err.type_error("Request.clone", "corps déjà lu")
        return Request(self, {}, self.loop)

    func __str__():
        return "Request(" + self.method + " " + self.url + ")"
