# ALEX STANDARD LIBRARY — web.browser.url_api
#
# URL (API WHATWG des navigateurs) sur le moteur web.url : analyse avec base, composantes lisibles ET
# modifiables (protocol, username, password, host, hostname, port, pathname, search, hash), origin,
# search_params vivant (URLSearchParams lié), sérialisation ; URL.can_parse / URL.parse ; URL d'objets.
#
#   use web.browser.url_api as ua
#   u := ua.URL("/recherche?q=chat#res", "https://exemple.org/a/b")
#   u.href()                          # https://exemple.org/recherche?q=chat#res
#   u.hostname(), u.pathname(), u.search(), u.hash(), u.origin()
#   u.search_params.append("page", 2)
#   u.search()                        # ?q=chat&page=2
#   u.set_pathname("/autre"); u.set_hash("")
#   ua.can_parse("pas une url")       # false
#   ua.parse("x", "https://a.b/")     # URL, ou null si invalide
#
# Erreurs : TypeError (URL invalide, comme new URL() en JavaScript).

from core use len, type, to_int
use string as _s
use web.url.url as _url
use web.url.scheme as _scheme
use web.url.form_url_encoding as _form
use web.browser.browser_errors as _err
use web.browser.url_search_params as _usp
use web.browser.object_url as _ou

class URL:
    func init(url, base=null):
        u := null
        try:
            b := base
            if isinstance(base, URL):
                b = base.inner
            u = _url.parse(str(url), b) if b != null else _url.parse(str(url))
        catch e:
            _err.type_error("URL", "URL invalide « " + str(url) + " »" + (" (base « " + str(base) + " »)" if base != null else ""))
        self.inner = u
        self.search_params = _usp.URLSearchParams(u.query if u.query != null else "")
        self.search_params.owner = self

    func _set(u):
        self.inner = u
        owner_params := _usp.URLSearchParams(u.query if u.query != null else "")
        self.search_params.pairs = owner_params.pairs

    func _search_params_changed():
        q := self.search_params.to_string()
        t := self.inner.copy()
        t.query = q if q != "" else null
        self.inner = t

    func href():
        return self.inner.href()

    func set_href(value):
        self._set(URL(value).inner)

    func to_string():
        return self.href()

    func to_json():
        return self.href()

    func __str__():
        return self.href()

    func origin():
        if self.inner.scheme == "blob":
            try:
                return URL(self.inner.path).origin()
            catch e:
                return "null"
        return self.inner.origin()

    func protocol():
        return self.inner.scheme + ":"

    func set_protocol(value):
        v := _s.lower(_s.replace(str(value), ":", ""))
        if _scheme.is_special(self.inner.scheme) != _scheme.is_special(v):
            return
        try:
            self._set(self.inner.with_scheme(v))
        catch e:
            pass

    func username():
        return self.inner.username if self.inner.username != null else ""

    func set_username(value):
        self._set(self.inner.with_userinfo(str(value), self.inner.password))

    func password():
        return self.inner.password if self.inner.password != null else ""

    func set_password(value):
        u := self.inner.username if self.inner.username != "" else ""
        self._set(self.inner.with_userinfo(u if u != "" else "", str(value)))

    func host():
        h := self.inner.host_port()
        return h if h != null else ""

    func set_host(value):
        try:
            self._set(self.inner.with_host(str(value)))
        catch e:
            pass

    func hostname():
        h := self.inner.host
        return h if h != null else ""

    func set_hostname(value):
        try:
            p := self.inner.port
            t := self.inner.with_host(str(value))
            if p != null:
                t = t.with_port(p)
            self._set(t)
        catch e:
            pass

    func port():
        return str(self.inner.port) if self.inner.port != null else ""

    func set_port(value):
        v := str(value)
        try:
            self._set(self.inner.with_port(v if v != "" else null))
        catch e:
            pass

    func pathname():
        return self.inner.path

    func set_pathname(value):
        self._set(self.inner.with_path(str(value)))

    func search():
        q := self.inner.query
        if q == null or q == "":
            return ""
        return "?" + q

    func set_search(value):
        v := str(value)
        if _s.starts_with(v, "?"):
            v = v[1:len(v)]
        self._set(self.inner.with_query(v if v != "" else null))

    func hash():
        f := self.inner.fragment
        if f == null or f == "":
            return ""
        return "#" + f

    func set_hash(value):
        v := str(value)
        if _s.starts_with(v, "#"):
            v = v[1:len(v)]
        if v == "":
            self._set(self.inner.without_fragment())
        else:
            self._set(self.inner.with_fragment(v))

    func url():
        return self.inner

func can_parse(url, base=null):
    try:
        URL(url, base)
        return true
    catch e:
        return false

# URL, ou null si invalide (URL.parse).
func parse(url, base=null):
    try:
        return URL(url, base)
    catch e:
        return null

func create_object_url(blob, origin="null"):
    return _ou.create_object_url(blob, origin)

func revoke_object_url(url):
    _ou.revoke_object_url(url)
