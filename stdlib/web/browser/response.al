# ALEX STANDARD LIBRARY — web.browser.response
#
# Response de l'API Fetch : statut, texte du statut, ok, en-têtes, type (basic, cors, error, opaque,
# opaqueredirect), URL finale, redirected, corps lu une fois (text, json, blob, array_buffer, form_data —
# promesses), clone() ; constructeurs Response.error(), Response.redirect(), Response.json() ; conversion
# depuis une réponse web.http / web.client.
#
#   use web.browser.response as rs
#   r := rs.Response("{\"ok\": true}", {"status": 201, "headers": {"Content-Type": "application/json"}})
#   r.ok, r.status, r.status_text                 # true 201 Created
#   r.json(loop).wait()["ok"]                     # true
#   rs.json_response({"a": 1}).headers.get("content-type")   # application/json
#   rs.redirect("/ailleurs", 302).headers.get("location")
#   rs.error().type                               # error
#
# Erreurs : RangeError (statut hors de 200..599), TypeError (corps pour un statut sans corps, corps déjà lu).

from core use len, type
from collections use append
use string as _s
use json as _json
use web.http.status_code as _status
use web.browser.browser_errors as _err
use web.browser.timers as _tm
use web.browser.request as _rq
from web.browser.request use Body

const NULL_BODY_STATUSES := [101, 103, 204, 205, 304]
const REDIRECT_STATUSES := [301, 302, 303, 307, 308]

class Response extends Body:
    func init(body=null, init_value=null, loop=null):
        o := init_value if init_value != null else {}
        st := o["status"] if "status" in o else 200
        if st < 200 or st > 599:
            if not (o["_allow_any"] if "_allow_any" in o else false):
                raise("RangeError", "Response : statut hors de 200..599 : " + str(st))
        self.status = st
        self.status_text = o["status_text"] if "status_text" in o else (_status.reason(st) if st >= 100 else "")
        self.headers = _rq.Headers(o["headers"] if "headers" in o else null)
        self.type = o["type"] if "type" in o else "default"
        self.url = o["url"] if "url" in o else ""
        self.redirected = o["redirected"] if "redirected" in o else false
        self.ok = st >= 200 and st <= 299
        data := null
        if body != null:
            if st in NULL_BODY_STATUSES:
                _err.type_error("Response", "le statut " + str(st) + " n'a pas de corps")
            r := _rq.extract_body(body)
            data = r[0]
            if r[1] != null and not self.headers.has("content-type"):
                self.headers.set("Content-Type", r[1])
        self.init_body(data, loop)

    func clone():
        if self.body_used:
            _err.type_error("Response.clone", "corps déjà lu")
        c := Response(null, {"status": self.status, "status_text": self.status_text, "headers": self.headers, "type": self.type, "url": self.url, "redirected": self.redirected, "_allow_any": true}, self.loop)
        c.body_bytes = self.body_bytes
        return c

    func __str__():
        return "Response(" + str(self.status) + " " + self.url + ")"

# Réponse d'erreur réseau (type « error », statut 0).
func error(loop=null):
    r := Response(null, {"status": 0, "status_text": "", "type": "error", "_allow_any": true}, loop)
    r.ok = false
    r.headers.guard = "immutable"
    return r

func redirect(url, status=302, loop=null):
    if not (status in REDIRECT_STATUSES):
        raise("RangeError", "Response.redirect : statut de redirection attendu")
    return Response(null, {"status": status, "headers": {"Location": str(url)}}, loop)

func json_response(value, init_value=null, loop=null):
    o := {}
    if init_value != null:
        for k in init_value:
            o[k] = init_value[k]
    r := Response(_json.stringify(value, null, false), o, loop)
    r.headers.set("Content-Type", "application/json")
    return r

# Response depuis une réponse web.http (Response / ClientResponse) ; url : URL finale.
func from_http(resp, url="", redirected=false, loop=null, response_type="basic"):
    h := []
    for p in resp.headers.items():
        append(h, (p[0], p[1]))
    st := resp.status
    r := Response(null, {"status": st if st >= 200 else 200, "status_text": resp.reason if st >= 200 else "", "headers": h, "type": response_type, "url": url, "redirected": redirected, "_allow_any": true}, loop)
    r.status = st
    r.ok = st >= 200 and st <= 299
    b := resp.body
    if b != null and b != "":
        r.body_bytes = _s.byte_unpack(b) if type(b) == "str" else b
    r.headers.guard = "immutable"
    return r

func opaque(loop=null, url=""):
    r := Response(null, {"status": 0, "status_text": "", "type": "opaque", "url": "", "_allow_any": true}, loop)
    r.ok = false
    return r
