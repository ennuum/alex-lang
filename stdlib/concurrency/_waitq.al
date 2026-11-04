# Détail d'implémentation de stdlib/concurrency : file FIFO de promesses en attente (asyncio.future), dont on
# saute celles qu'il ne faut plus réveiller (déjà terminées, ou abandonnées : la tâche qui attendait a été
# annulée). Même règle que les canaux (stdlib/channel).
from core use len
from collections use append
use asyncio

func alive(p):
    return not asyncio.done(p) and not asyncio.abandoned(p)

func drop(p):
    if not asyncio.done(p):
        asyncio.cancel(p)

# Futur déjà terminé avec v.
func ready(v):
    p := asyncio.future()
    asyncio.resolve(p, v)
    return p

class WaitQueue:
    func init():
        self.items = []
        self.head = 0

    # Nouvelle promesse en attente, renvoyée.
    func add():
        p := asyncio.future()
        append(self.items, p)
        return p

    # Prochaine promesse vivante (les autres sont écartées), ou null.
    func pop_alive():
        while self.head < len(self.items):
            p := self.items[self.head]
            self.items[self.head] = null
            self.head = self.head + 1
            if self.head >= 32 and self.head * 2 >= len(self.items):
                self._compact()
            if alive(p):
                return p
            drop(p)
        return null

    func _compact():
        fresh := []
        i := self.head
        while i < len(self.items):
            append(fresh, self.items[i])
            i = i + 1
        self.items = fresh
        self.head = 0

    # Nombre de promesses encore vivantes.
    func count():
        n := 0
        i := self.head
        while i < len(self.items):
            if alive(self.items[i]):
                n = n + 1
            i = i + 1
        return n

    # Réveille toutes les promesses vivantes avec v ; renvoie leur nombre.
    func resolve_all(v):
        n := 0
        p := self.pop_alive()
        while p != null:
            asyncio.resolve(p, v)
            n = n + 1
            p = self.pop_alive()
        return n
