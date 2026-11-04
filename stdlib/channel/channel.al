# ALEX STANDARD LIBRARY — channel
# Canaux (rendez-vous ou tamponnés) entre tâches, en ALEX pur, par-dessus les futurs d'asyncio (docs/CHANNELS.md).
#
#   use channel
#   from channel use Channel
#   use asyncio
#
#   async func producteur(ch):
#       for i in [1, 2, 3]:
#           await ch.send(i)
#       ch.close()
#
#   async func main():
#       ch := Channel(2)                 # capacité 2 ; Channel() = canal sans tampon (rendez-vous)
#       producteur(ch)
#       print(await channel.drain(ch))   # [1, 2, 3]
#
# Principe : send() et recv() ne sont PAS des `async func` : ce sont des fonctions ordinaires qui renvoient un
# futur (une promesse). L'opération est donc enregistrée tout de suite, dans l'ordre des appels (FIFO, déterministe),
# et non au prochain tour de boucle. Une valeur n'est retirée du canal que si la promesse du correspondant a pu être
# complétée (resolve() renvoie true) : un attendant annulé, expiré (asyncio.timeout) ou déjà servi par un select()
# ne « vole » donc jamais de valeur.

from core use len, type
from collections use append
use asyncio

# --- structures internes ------------------------------------------------------------------------------------

# Opération en attente : `promise` est ce que l'appelant attend ; `tag` vaut -1 hors select(), sinon l'indice du
# cas dans le select ; `value` est la valeur à émettre (send).
class _Waiter:
    func init(promise, tag, value):
        self.promise = promise
        self.tag = tag
        self.value = value

# File FIFO à indice de tête (pop en O(1) amorti). Les files d'attente peuvent contenir des entrées mortes
# (promesse annulée, expirée, abandonnée) : elles sont ignorées au passage et balayées quand la file grossit.
class _Fifo:
    func init():
        self.items = []
        self.head = 0
        self.sweep_at = 16

    func size():
        return len(self.items) - self.head

    func push(x):
        append(self.items, x)

    func pop():
        x := self.items[self.head]
        self.items[self.head] = null
        self.head = self.head + 1
        if self.head >= 32 and self.head * 2 >= len(self.items):
            self._keep_from_head()
        return x

    func _keep_from_head():
        fresh := []
        i := self.head
        while i < len(self.items):
            append(fresh, self.items[i])
            i = i + 1
        self.items = fresh
        self.head = 0

    # Ajoute une opération en attente ; balaie d'abord les mortes si la file a doublé depuis le dernier balayage
    # (un select() en boucle sur un canal silencieux n'accumule ainsi rien).
    func add_waiter(w):
        if self.size() >= self.sweep_at:
            self._sweep()
            self.sweep_at = self.size() * 2
            if self.sweep_at < 16:
                self.sweep_at = 16
        append(self.items, w)

    func _sweep():
        fresh := []
        i := self.head
        while i < len(self.items):
            w := self.items[i]
            if _alive(w.promise):
                append(fresh, w)
            else:
                _drop(w.promise)
            i = i + 1
        self.items = fresh
        self.head = 0

func _alive(p):
    return not asyncio.done(p) and not asyncio.abandoned(p)

# Une entrée morte est annulée : réattendre sa promesse donne un CancelledError net plutôt qu'une attente sans fin.
func _drop(p):
    if not asyncio.done(p):
        asyncio.cancel(p)

# Termine l'opération `w` avec succès (`v` : valeur reçue ; null pour un envoi). false si elle est morte.
func _complete(w, v):
    if not _alive(w.promise):
        _drop(w.promise)
        return false
    if w.tag < 0:
        return asyncio.resolve(w.promise, v)
    return asyncio.resolve(w.promise, (w.tag, true, v))

# Termine `w` parce que le canal est fermé : ChannelClosedError, ou (indice, false, null) pour un select().
func _fail(w, message):
    if not _alive(w.promise):
        _drop(w.promise)
        return null
    if w.tag < 0:
        asyncio.reject(w.promise, "ChannelClosedError", message)
    else:
        asyncio.resolve(w.promise, (w.tag, false, null))

# --- le canal -----------------------------------------------------------------------------------------------

class Channel:
    func init(capacity=0):
        if type(capacity) != "int" or capacity < 0:
            raise("ArgumentError", "Channel : la capacité doit être un entier >= 0")
        self.cap = capacity
        self.buf = _Fifo()
        self.recvq = _Fifo()
        self.sendq = _Fifo()
        self.shut = false

    # Futur terminé quand `v` est accepté (placé dans le tampon ou remis à un récepteur). Avec un tampon plein, ou
    # sans tampon et sans récepteur, il reste en attente : c'est la contre-pression. Canal fermé : ChannelClosedError.
    func send(v):
        p := asyncio.future()
        if self.shut:
            asyncio.reject(p, "ChannelClosedError", "send sur un canal fermé")
            return p
        if self._offer(v):
            asyncio.resolve(p, null)
        else:
            self.sendq.add_waiter(_Waiter(p, -1, v))
        return p

    # Futur dont la valeur est la prochaine valeur du canal. Canal fermé ET vidé : ChannelClosedError.
    func recv():
        p := asyncio.future()
        r := self._take()
        if r[0]:
            asyncio.resolve(p, r[1])
        elif self.shut:
            asyncio.reject(p, "ChannelClosedError", "recv sur un canal fermé et vide")
        else:
            self.recvq.add_waiter(_Waiter(p, -1, null))
        return p

    # Non bloquant. true si la valeur a été acceptée tout de suite, false sinon. Canal fermé : ChannelClosedError.
    func try_send(v):
        if self.shut:
            raise("ChannelClosedError", "send sur un canal fermé")
        return self._offer(v)

    # Non bloquant. (true, valeur) ou (false, null) si rien n'est disponible. Fermé et vidé : ChannelClosedError.
    func try_recv():
        r := self._take()
        if r[0]:
            return r
        if self.shut:
            raise("ChannelClosedError", "recv sur un canal fermé et vide")
        return (false, null)

    # Ferme le canal. Les valeurs déjà tamponnées restent lisibles ; les récepteurs en attente et les émetteurs en
    # attente (leur valeur est abandonnée) échouent en ChannelClosedError. false si déjà fermé.
    func close():
        if self.shut:
            return false
        self.shut = true
        while self.recvq.size() > 0:
            _fail(self.recvq.pop(), "recv sur un canal fermé et vide")
        while self.sendq.size() > 0:
            _fail(self.sendq.pop(), "send sur un canal fermé")
        return true

    func closed():
        return self.shut

    # Nombre de valeurs dans le tampon.
    func size():
        return self.buf.size()

    func capacity():
        return self.cap

    # -- interne --

    # Remet `v` à un récepteur vivant. true si livré.
    func _hand_off(v):
        while self.recvq.size() > 0:
            if _complete(self.recvq.pop(), v):
                return true
        return false

    # Accepte la valeur d'un émetteur vivant : (true, valeur) ou (false, null).
    func _accept_sender():
        while self.sendq.size() > 0:
            w := self.sendq.pop()
            if _complete(w, null):
                return (true, w.value)
        return (false, null)

    # Place `v` maintenant si possible (récepteur en attente, sinon place dans le tampon).
    func _offer(v):
        if self._hand_off(v):
            return true
        if self.buf.size() < self.cap:
            self.buf.push(v)
            return true
        return false

    # Retire une valeur maintenant si possible : (true, valeur) ou (false, null). Libère une place du tampon au
    # profit du premier émetteur en attente, ce qui conserve l'ordre global.
    func _take():
        if self.buf.size() > 0:
            v := self.buf.pop()
            s := self._accept_sender()
            if s[0]:
                self.buf.push(s[1])
            return (true, v)
        return self._accept_sender()

# --- select -------------------------------------------------------------------------------------------------

func _ready_future(t):
    p := asyncio.future()
    asyncio.resolve(p, t)
    return p

# Attend le premier cas prêt. Un cas est un canal (réception) ou une paire [canal, valeur] (émission). Résultat :
# le tuple (indice, ok, valeur) ; `ok` vaut false si ce canal est fermé (comme `v, ok := <-ch` en Go), `valeur`
# est la valeur reçue (null pour une émission).
#   - si plusieurs cas sont prêts, le PREMIER de la liste gagne (déterministe) ;
#   - un seul cas est exécuté : les autres n'ont aucun effet (aucune valeur n'est retirée d'un canal perdant) ;
#   - select() est une fonction ordinaire renvoyant un futur : enregistrement immédiat, compatible avec
#     asyncio.timeout / race / cancel.
func select(cases):
    if type(cases) != "list" or len(cases) == 0:
        raise("ArgumentError", "select : une liste non vide de cas est attendue")
    n := len(cases)
    i := 0
    while i < n:
        c := cases[i]
        if not isinstance(c, Channel):
            if not ((type(c) == "list" or type(c) == "tuple") and len(c) == 2 and isinstance(c[0], Channel)):
                raise("ArgumentError", f"select : le cas {i} n'est ni un canal ni une paire [canal, valeur]")
        i = i + 1

    # 1. un cas est-il prêt tout de suite ?
    i = 0
    while i < n:
        c := cases[i]
        if isinstance(c, Channel):
            r := c._take()
            if r[0]:
                return _ready_future((i, true, r[1]))
            if c.shut:
                return _ready_future((i, false, null))
        else:
            if c[0].shut:
                return _ready_future((i, false, null))
            if c[0]._offer(c[1]):
                return _ready_future((i, true, null))
        i = i + 1

    # 2. sinon, une même promesse est inscrite dans chaque canal ; le premier qui la complète gagne, les autres
    #    entrées meurent (resolve() renvoie false) et ne retirent donc rien.
    p := asyncio.future()
    i = 0
    while i < n:
        c := cases[i]
        if isinstance(c, Channel):
            c.recvq.add_waiter(_Waiter(p, i, null))
        else:
            c[0].sendq.add_waiter(_Waiter(p, i, c[1]))
        i = i + 1
    return p

# --- aides --------------------------------------------------------------------------------------------------

# Appelle fn(valeur) pour chaque valeur reçue, jusqu'à la fermeture du canal. Si fn renvoie une tâche, elle est
# attendue avant la valeur suivante. Termine normalement à la fermeture ; toute autre exception se propage.
async func each(ch, fn):
    while true:
        v := null
        try:
            v = await ch.recv()
        catch e:
            if e.type == "ChannelClosedError":
                return null
            raise(e.type, e.message)
        r := fn(v)
        if asyncio.is_future(r):
            await r

# Liste de toutes les valeurs reçues jusqu'à la fermeture du canal.
async func drain(ch):
    out := []
    while true:
        v := null
        try:
            v = await ch.recv()
        catch e:
            if e.type == "ChannelClosedError":
                return out
            raise(e.type, e.message)
        append(out, v)
