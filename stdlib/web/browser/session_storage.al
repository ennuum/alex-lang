# ALEX STANDARD LIBRARY — web.browser.session_storage
#
# Stockage de session (window.session_storage) : comme local_storage mais propre à un onglet et à une
# origine, jamais persisté, copié quand un onglet en ouvre un autre (window.open), effacé à la fermeture.
#
#   use web.browser.session_storage as ss
#   sess := ss.SessionStorageArea()               # un par onglet
#   st := sess.for_origin("https://exemple.org")
#   st.set_item("panier", "[1,2]")
#   copie := sess.clone()                         # nouvel onglet ouvert depuis celui-ci
#   copie.for_origin("https://exemple.org").get_item("panier")   # [1,2]
#   sess.close()                                  # tout est effacé
#
# Erreurs : QuotaExceededError (quota dépassé).

from core use len, type
from collections use keys
use web.browser.local_storage as _ls

func session_storage(origin, quota=5242880):
    return _ls.Storage(origin, quota, null, "session")

class SessionStorageArea:
    func init(quota=5242880):
        self.quota = quota
        self.stores = {}

    func for_origin(origin):
        if not (origin in self.stores):
            self.stores[origin] = session_storage(origin, self.quota)
        return self.stores[origin]

    # Copie pour un onglet ouvert depuis celui-ci (données dupliquées, puis indépendantes).
    func clone():
        c := SessionStorageArea(self.quota)
        for o in keys(self.stores):
            st := c.for_origin(o)
            src := self.stores[o]
            for k in src.order:
                st.items[k] = src.items[k]
                st.order = st.order + [k]
        return c

    func close():
        for o in keys(self.stores):
            self.stores[o].items = {}
            self.stores[o].order = []
        self.stores = {}
