# ALEX STANDARD LIBRARY — web.browser.object_url
#
# URL d'objets (« blob: ») : URL.createObjectURL / revokeObjectURL. Chaque URL désigne un Blob (ou File)
# tant qu'elle n'est pas révoquée ; fetch() et les éléments de la page peuvent la résoudre.
#
#   use web.browser.object_url as ou
#   reg := ou.ObjectUrlRegistry("https://exemple.org")
#   u := reg.create(blob)             # blob:https://exemple.org/3f6c…
#   reg.resolve(u) == blob            # true
#   reg.revoke(u)
#   reg.resolve(u)                    # null
#   ou.is_blob_url(u)                 # true
#
# Erreurs : TypeError (objet qui n'est pas un Blob).

from core use len, type
from collections use append, keys
use string as _s
use random as _random
use web.browser.browser_errors as _err
use web.browser.blob as _blob

func _hex(n, width):
    digits := "0123456789abcdef"
    out := []
    v := n
    i := 0
    while i < width:
        append(out, str(digits[v % 16]))
        v = v // 16
        i += 1
    r := []
    j := len(out) - 1
    while j >= 0:
        append(r, out[j])
        j -= 1
    return _s.join("", r)

# Identifiant aléatoire de forme UUID v4.
func uuid4():
    a := _hex(_random.getrandbits(32), 8)
    b := _hex(_random.getrandbits(16), 4)
    c := "4" + _hex(_random.getrandbits(12), 3)
    d := _hex(8 + _random.getrandbits(2), 1) + _hex(_random.getrandbits(12), 3)
    e := _hex(_random.getrandbits(48), 12)
    return a + "-" + b + "-" + c + "-" + d + "-" + e

func is_blob_url(url):
    return type(url) == "str" and _s.starts_with(url, "blob:")

class ObjectUrlRegistry:
    func init(origin="null"):
        self.origin = origin
        self.entries = {}

    func create(blob):
        if not isinstance(blob, _blob.Blob):
            _err.type_error("create_object_url", "Blob ou File attendu")
        u := "blob:" + self.origin + "/" + uuid4()
        self.entries[u] = blob
        return u

    func revoke(url):
        if url in self.entries:
            out := {}
            for k in keys(self.entries):
                if k != url:
                    out[k] = self.entries[k]
            self.entries = out

    # Blob désigné (le fragment « #… » est ignoré), ou null.
    func resolve(url):
        u := str(url)
        h := _s.find(u, "#")
        if h >= 0:
            u = u[0:h]
        if u in self.entries:
            return self.entries[u]
        return null

    func size():
        return len(self.entries)

_registries := {}

# Registre partagé d'une origine.
func registry_for(origin):
    if not (origin in _registries):
        _registries[origin] = ObjectUrlRegistry(origin)
    return _registries[origin]

func create_object_url(blob, origin="null"):
    return registry_for(origin).create(blob)

func revoke_object_url(url):
    for k in keys(_registries):
        _registries[k].revoke(url)

func resolve(url):
    for k in keys(_registries):
        b := _registries[k].resolve(url)
        if b != null:
            return b
    return null
