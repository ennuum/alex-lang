# ALEX STANDARD LIBRARY — web.client.request_builder
#
# RequestBuilder : construction pas à pas d'une requête, puis envoi (send) par le client auquel le constructeur
# est attaché. Chaque méthode renvoie le constructeur, ce qui permet d'enchaîner.
#
#   use web.client.http_client as hc
#   c := hc.HttpClient()
#   r := c.build("POST", "https://api.exemple.org/notes").header("X-Trace", "1").bearer("jeton").json({"titre": "Été"}).timeout(5).send()
#   r2 := c.build("GET", "https://exemple.org/recherche").param("q", "chat noir").param("page", 2).no_redirects().send()
#   req := c.build("PUT", url).form({"a": 1}).request()     # ClientRequest sans l'envoyer
#
# Erreurs : celles de web.client.client_request et du client à l'envoi.

from core use len, type
from collections use append, keys
use web.client.client_errors as _err
use web.client.client_request as _creq
use web.url.query_params as _qp

class RequestBuilder:
    # client : objet doté de send(ClientRequest) (HttpClient), ou null (request() seulement).
    func init(client, method, url):
        self.client = client
        self.method = method
        self.url = url
        self._headers = []
        self._params = _qp.QueryParams()
        self._body = null
        self._kind = null          # json, form, multipart, body, text
        self._multipart_files = null
        self._timeout = null
        self._follow = null
        self._auth = null

    func header(name, value):
        append(self._headers, (name, value))
        return self

    func headers(data):
        if type(data) == "dict":
            for k in keys(data):
                append(self._headers, (k, data[k]))
        else:
            for p in data:
                append(self._headers, (p[0], p[1]))
        return self

    func accept(media_type):
        return self.header("Accept", media_type)

    func param(name, value):
        if type(value) == "list" or type(value) == "tuple":
            for v in value:
                self._params.add(name, v)
        elif value != null:
            self._params.add(name, value)
        return self

    func params(data):
        self._params.update(data)
        return self

    func json(value):
        self._kind = "json"
        self._body = value
        return self

    func form(data):
        self._kind = "form"
        self._body = data
        return self

    func multipart(fields=null, files=null):
        self._kind = "multipart"
        self._body = fields
        self._multipart_files = files
        return self

    # Ajoute un fichier au corps multipart (contenu str d'octets ou liste d'octets).
    func file(field, filename, content, content_type=null):
        if self._kind != "multipart":
            self._kind = "multipart"
            if type(self._body) != "dict" and type(self._body) != "list":
                self._body = null
        if self._multipart_files == null:
            self._multipart_files = []
        append(self._multipart_files, (field, filename, content, content_type))
        return self

    func body(data, content_type=null):
        self._kind = "body"
        self._body = (data, content_type)
        return self

    func text(value, sub="plain"):
        self._kind = "text"
        self._body = (value, sub)
        return self

    func basic_auth(username, password):
        self._auth = ("basic", username, password)
        return self

    func bearer(token):
        self._auth = ("bearer", token, null)
        return self

    # Délai propre à la requête (nombre ou Timeout).
    func timeout(value):
        self._timeout = value
        return self

    func follow_redirects(on=true):
        self._follow = on
        return self

    func no_redirects():
        self._follow = false
        return self

    # ClientRequest construite (sans envoi). L'URL relative est résolue par le client à l'envoi (base_url).
    func request():
        u := self.url
        if self.client != null and type(u) == "str":
            u = self.client.resolve_url(u)
        r := _creq.ClientRequest(self.method, u, null, null, self._params if not self._params.is_empty() else null, self._timeout)
        for h in self._headers:
            r.headers.add(h[0], h[1])
        if self._kind == "json":
            r.set_json(self._body)
        elif self._kind == "form":
            r.set_form(self._body)
        elif self._kind == "multipart":
            r.set_multipart(self._body, self._multipart_files)
        elif self._kind == "body":
            r.set_body(self._body[0], self._body[1])
        elif self._kind == "text":
            r.set_text(self._body[0], self._body[1])
        if self._auth != null:
            if self._auth[0] == "basic":
                r.set_basic_auth(self._auth[1], self._auth[2])
            else:
                r.set_bearer(self._auth[1])
        r.follow_redirects = self._follow
        return r

    # Envoie la requête avec le client ; renvoie la ClientResponse.
    func send():
        if self.client == null:
            _err.client_error("RequestBuilder.send", "constructeur sans client : utiliser request()")
        return self.client.send(self.request())

func builder(method, url, client=null):
    return RequestBuilder(client, method, url)
