# ALEX STANDARD LIBRARY — concurrency.thread
#
# Fils d'exécution PARALLÈLES et isolés : chaque fil exécute une fonction dans sa propre VM (son tas, son
# ramasse-miettes, son ordonnanceur async) sur un fil du système. Ils tournent vraiment en même temps, sur
# plusieurs cœurs. Ils ne partagent aucun objet : arguments, résultat et messages sont COPIÉS.
#
#   use concurrency.thread as thread
#
#   func carre_lent(n):          # fonction de PREMIER NIVEAU d'un module
#       ...
#       return n * n
#
#   if thread.is_main():         # voir « Programme principal » ci-dessous
#       t := thread.spawn(carre_lent, [12])
#       print(t.join())          # 144
#
# Ce qui peut passer d'un fil à l'autre : null, bool, int, float, char, byte, str, et les list, tuple, dict qui
# n'en contiennent pas d'autres (copie profonde). Une fonction, un objet de classe, un futur, un socket... ne
# le peuvent pas (TypeError) : passer des dicts, et un canal par son identifiant (Channel.id, puis attach).
#
# Programme principal : le fil importe le module de la fonction, dont le code de haut niveau s'exécute donc
# (comme à un import). Si la fonction est définie dans le script principal, protéger son code de haut niveau :
# `if thread.is_main():` (même principe que `if __name__ == "__main__":` en Python), ou placer les fonctions
# des fils dans un module à part.
#
# Communication
#   - Thread.send / Thread.receive (côté parent) et thread.send / thread.receive (côté fil) : boîte aux lettres
#     du fil (FIFO, sans limite).
#   - Channel(capacité) : canal partagé par plusieurs fils (FIFO ; capacité 0 : sans limite). Voyage par son
#     identifiant entier : Channel(4).id, puis thread.attach(id) dans le fil.
# Les appels qui attendent (join, receive, send sur un canal plein) bloquent le fil appelant, son ordonnanceur
# async compris ; ils acceptent un délai (null : sans limite).
#
# Fin du programme : comme en Python, le programme principal attend la fin de tous ses fils ; un fil qui échoue
# sans que personne ne l'attende est signalé sur stderr.
#
# Erreurs
#   TimeoutError        délai dépassé (join, receive, send).
#   ChannelClosedError  canal fermé (receive après le dernier message, send).
#   TypeError           valeur non copiable ; ArgumentError : fonction qui n'est pas de premier niveau.
#   ThreadError         start répété, join avant start, garde is_main oubliée, plus de 256 fils en cours.
#   join relance l'erreur du fil avec son type et son message (« ... [fil 3] »).
#
# Limites : chaque fil a ses propres sockets, processus fils et bibliothèques FFI (un handle ne passe pas d'un
# fil à l'autre) ; l'interface graphique (ui) reste au programme principal ; os.chdir et os.setenv agissent sur
# tout le processus.

from core use len, type
from collections use append
use _native_thread as _t

func supported():
    return _t.supported()

# Nombre de cœurs de la machine.
func cpu_count():
    return _t.cpu_count()

# Identifiant du fil courant (0 : programme principal).
func current_id():
    return _t.current_id()

func is_main():
    return _t.is_main()

# Fils lancés et pas encore terminés.
func active_count():
    return _t.active_count()

func _check_timeout(fn, t):
    if t != null and type(t) != "int" and type(t) != "float":
        raise("TypeError", "thread." + fn + " : délai nombre ou null attendu")

func _send(chan, value, timeout, what):
    _check_timeout("send", timeout)
    r := _t.send(chan, value, timeout)
    if r == 0:
        raise("TimeoutError", what + " : délai dépassé (canal plein)")
    if r == 2:
        raise("ChannelClosedError", what + " : canal fermé")

func _recv(chan, timeout, what):
    _check_timeout("receive", timeout)
    r := _t.recv(chan, timeout)
    if r[0] == 1:
        return r[1]
    if r[0] == 0:
        raise("TimeoutError", what + " : délai dépassé (aucun message)")
    raise("ChannelClosedError", what + " : canal fermé")

class Thread:
    # target : fonction de premier niveau ; args : list de valeurs copiables ; name : nom (traces, messages).
    func init(target, args=null, name=null):
        if args == null:
            args = []
        if type(args) != "list" and type(args) != "tuple":
            raise("TypeError", "Thread : les arguments doivent être une list (obtenu '" + type(args) + "')")
        self.target = target
        self.args = args
        self.name = name
        self.id = null
        self._finished = false
        self._result = null

    func start():
        if self.id != null:
            raise("ThreadError", "Thread.start : fil déjà démarré")
        id := _t.spawn(self.target, self.args, self.name)
        if id == -1:
            raise("ThreadError", "thread.spawn appelé par le code de haut niveau d'un module importé dans un fil : protéger le programme principal par `if thread.is_main():` (sinon chaque fil le relance)")
        if id == -2:
            raise("ThreadError", "thread.spawn : trop de fils en cours (256 au plus)")
        self.id = id
        self.name = _t.name(self.id)
        return self

    func _started(fn):
        if self.id == null:
            raise("ThreadError", "Thread." + fn + " : fil pas encore démarré (start)")

    # Attend la fin du fil ; renvoie la valeur rendue par sa fonction, ou relance son erreur.
    func join(timeout=null):
        self._started("join")
        _check_timeout("join", timeout)
        if not self._finished:
            r := _t.join(self.id, timeout)
            if r == null:
                raise("TimeoutError", "Thread.join : le fil " + self.name + " n'a pas fini dans le délai")
            self._finished = true
            if r[0]:
                self._result = [true, r[1]]
            else:
                self._result = [false, r[1], r[2], r[3]]
        if self._result[0]:
            return self._result[1]
        raise(self._result[1], self._result[2] + " [fil " + str(self.id) + " : " + self.name + "]")

    # Erreur du fil (après join ou s'il est fini) : trace de pile du fil, "" si aucune.
    func trace():
        if self._result == null or self._result[0]:
            return ""
        return self._result[3]

    func is_alive():
        if self.id == null:
            return false
        return _t.is_alive(self.id)

    # Boîte aux lettres : message vers le fil, et message venant du fil.
    func send(value, timeout=null):
        self._started("send")
        _send(_t.mailbox(self.id)[0], value, timeout, "Thread.send")

    func receive(timeout=null):
        self._started("receive")
        return _recv(_t.mailbox(self.id)[1], timeout, "Thread.receive")

# Crée et démarre un fil.
func spawn(target, args=null, name=null):
    return Thread(target, args, name).start()

# Applique f (fonction de premier niveau) à chaque élément, avec au plus workers fils à la fois (par défaut le
# nombre de cœurs) ; résultats dans l'ordre des éléments.
func parallel_map(f, items, workers=null):
    if workers == null:
        workers = cpu_count()
    if workers < 1:
        raise("ArgumentError", "parallel_map : au moins un fil")
    results := []
    running := []
    i := 0
    while i < len(items):
        if len(running) >= workers:
            first := running[0]
            results[first[0]] = first[1].join()
            running = [running[k] for k in 1..len(running)]
        append(results, null)
        append(running, [i, spawn(f, [items[i]], "parallel_map")])
        i += 1
    for r in running:
        results[r[0]] = r[1].join()
    return results

# ---- côté fil : boîte aux lettres du fil courant ----
func send(value, timeout=null):
    _send(_t.mailbox(0)[1], value, timeout, "thread.send")

func receive(timeout=null):
    return _recv(_t.mailbox(0)[0], timeout, "thread.receive")

# ---- canaux entre fils ----
class Channel:
    # Nouveau canal (capacity 0 : sans limite) ; id : canal existant (voir attach).
    func init(capacity=0, id=null):
        if id == null:
            self.id = _t.channel(capacity)
        else:
            self.id = id

    func send(value, timeout=null):
        _send(self.id, value, timeout, "Channel.send")

    func receive(timeout=null):
        return _recv(self.id, timeout, "Channel.receive")

    # Comme receive sans attendre : (true, valeur) ou (false, null).
    func try_receive():
        r := _t.recv(self.id, 0)
        if r[0] == 1:
            return (true, r[1])
        return (false, null)

    # Ferme le canal : les envois échouent, les réceptions vident ce qui reste puis échouent.
    func close():
        _t.close(self.id)

    func closed():
        return _t.closed(self.id)

    func size():
        return _t.size(self.id)

# Canal désigné par son identifiant (reçu dans les arguments d'un fil ou dans un message).
func attach(id):
    if type(id) != "int":
        raise("TypeError", "thread.attach : identifiant de canal int attendu")
    _t.size(id) # vérifie qu'il existe
    return Channel(0, id)
