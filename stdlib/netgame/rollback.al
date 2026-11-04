# ALEX STANDARD LIBRARY — netgame.rollback
#
# Simulation à RETOUR ARRIÈRE (rollback, style GGPO) pour les jeux où chaque joueur simule tout le monde
# (combat, course, action à peu de joueurs) :
#   - chaque pair simule à chaque image avec ses entrées locales (après un petit délai d'entrée) et les entrées
#     distantes PRÉDITES (la dernière entrée connue du joueur est répétée) ;
#   - quand l'entrée réelle d'un joueur arrive et diffère de la prédiction, la session recharge l'état de cette image
#     et RESIMULE jusqu'à l'image courante, dans la même image d'affichage ;
#   - au-delà de max_rollback images d'avance sur les entrées confirmées, la session attend (advance rend false) ;
#   - should_wait() ralentit le pair en avance (synchronisation du temps), sommes de contrôle des images confirmées
#     échangées (desync détectée).
# La simulation doit être DÉTERMINISTE (mêmes entrées -> même état sur chaque machine) : entiers ou réels
# quantifiés, pas d'aléa non semé, pas de dépendance au temps réel.
#
#   use netgame.rollback as rb
#   func step(etat, entrees):                 # entrees[i] : entrée du joueur i (ou null)
#       ...
#       return etat
#   s := rb.RollbackSession(2, mon_numero, step, etat0, 2, 8)
#   lien := rb.RollbackNet(s, srv_ou_cli)     # netgame.Server (hôte) ou netgame.Client
#   # chaque image (60 Hz)
#   for e in srv_ou_cli.update(): lien.handle(e)
#   if not s.should_wait():
#       s.add_local_input(lire_manette())
#       s.advance()
#   lien.send() ; srv_ou_cli.flush()
#   dessiner(s.state)
#
# Plus de deux joueurs : l'hôte (Server) relaie les entrées de chacun vers les autres.
# Erreurs : ValueError (joueur ou image invalide).

from core use len, type
from collections use append, keys, remove
use math
use netgame.codec as nc

class RollbackSession:
    func init(players, local, step, state, input_delay=2, max_rollback=8, copy=null, default_input=null, checksum=null):
        if local < 0 or local >= players:
            raise("ValueError", "netgame.rollback : joueur local invalide")
        self.players = players
        self.local = local
        self.step = step
        self.copy = copy if copy != null else nc.deep_copy
        self.checksum_fn = checksum if checksum != null else nc.checksum
        self.delay = input_delay
        self.max_rollback = max_rollback
        self.default = default_input
        self.frame = 0
        self.state = self.copy(state)
        self.saved = {0: self.copy(state)}
        self.inputs = []
        self.confirmed = []
        p := 0
        while p < players:
            d := {}
            f := 0
            while f < input_delay:
                d[f] = default_input
                f += 1
            append(self.inputs, d)
            append(self.confirmed, input_delay - 1)
            p += 1
        self.used = {}
        self.rollback_to = -1
        self.local_next = input_delay
        self.checksums = {}
        self.cs_frame = -1
        self.remote_frame = [0 for k in 0..players]
        self.remote_ack = [-1 for k in 0..players]
        self.desync = null
        self.stats = {"rollbacks": 0, "resimulated": 0, "stalls": 0, "frames": 0, "max_depth": 0}

    # Entrée locale pour l'image frame + input_delay (une fois par image, avant advance).
    func add_local_input(inp):
        f := self.local_next
        if f > self.frame + self.delay:
            return false
        self._store(self.local, f, inp)
        self.local_next = f + 1
        return true

    func add_remote_input(player, frame, inp):
        if player < 0 or player >= self.players:
            raise("ValueError", "netgame.rollback : joueur " + str(player) + " invalide")
        if player == self.local:
            return
        self._store(player, frame, inp)

    func _store(p, f, inp):
        d := self.inputs[p]
        if f in d or f <= self.confirmed[p] - 512:
            return
        d[f] = inp
        while (self.confirmed[p] + 1) in d:
            self.confirmed[p] = self.confirmed[p] + 1
        if f < self.frame and f in self.used and self.used[f][p] != inp:
            if self.rollback_to < 0 or f < self.rollback_to:
                self.rollback_to = f

    # Dernière image dont toutes les entrées sont connues.
    func confirmed_frame():
        m := self.confirmed[0]
        for c in self.confirmed:
            if c < m:
                m = c
        return m

    func _input_for(p, f):
        d := self.inputs[p]
        if f in d:
            return d[f]
        c := self.confirmed[p]
        if c >= 0 and c in d:
            return d[c]
        return self.default

    func _sim(f):
        ins := [self._input_for(p, f) for p in 0..self.players]
        self.used[f] = ins
        self.state = self.step(self.state, ins)
        self.saved[f + 1] = self.copy(self.state)

    # Avance d'une image ; false si trop d'avance sur les entrées confirmées (attendre les autres).
    func advance():
        if self.frame - self.confirmed_frame() > self.max_rollback:
            self.stats["stalls"] = self.stats["stalls"] + 1
            return false
        if not (self.frame in self.inputs[self.local]):
            self._store(self.local, self.frame, self._input_for(self.local, self.frame))
        if self.rollback_to >= 0 and self.rollback_to < self.frame:
            f := self.rollback_to
            depth := self.frame - f
            self.state = self.copy(self.saved[f])
            while f < self.frame:
                self._sim(f)
                f += 1
            self.stats["rollbacks"] = self.stats["rollbacks"] + 1
            self.stats["resimulated"] = self.stats["resimulated"] + depth
            if depth > self.stats["max_depth"]:
                self.stats["max_depth"] = depth
        self.rollback_to = -1
        self._sim(self.frame)
        self.frame += 1
        self.stats["frames"] = self.stats["frames"] + 1
        self._confirm()
        return true

    func _confirm():
        cf := math.min(self.confirmed_frame(), self.frame - 1)
        while self.cs_frame < cf:
            self.cs_frame += 1
            self.checksums[self.cs_frame] = self.checksum_fn(self.saved[self.cs_frame + 1])
        keep := cf - 2
        for f in keys(self.saved):
            if f < keep:
                remove(self.saved, f)
        for f in keys(self.used):
            if f < keep:
                remove(self.used, f)
        for f in keys(self.checksums):
            if f < cf - 120:
                remove(self.checksums, f)
        p := 0
        while p < self.players:
            d := self.inputs[p]
            for f in keys(d):
                if f < keep - 64:
                    remove(d, f)
            p += 1

    func checksum_at(frame):
        return self.checksums[frame] if frame in self.checksums else null

    # Images d'avance sur le pair le plus lent (estimation) ; > 1 : should_wait() conseille une image d'attente.
    func frame_advantage(rtt=0.0, fps=60.0):
        worst := 0.0
        p := 0
        while p < self.players:
            if p != self.local:
                est := self.remote_frame[p] + rtt * 0.5 * fps
                adv := self.frame - est
                if adv > worst:
                    worst = adv
            p += 1
        return worst

    func should_wait(rtt=0.0, fps=60.0):
        return self.frame_advantage(rtt, fps) > 2.0

    # Message pour les pairs : entrées locales non confirmées par eux (redondantes), accusés, image, contrôle.
    func pack(limit=32):
        first := self.local_next
        p := 0
        while p < self.players:
            if p != self.local and self.remote_ack[p] + 1 < first:
                first = self.remote_ack[p] + 1
            p += 1
        if first < self.local_next - limit:
            first = self.local_next - limit
        if first < 0:
            first = 0
        d := self.inputs[self.local]
        ins := []
        f := first
        while f < self.local_next:
            append(ins, d[f] if f in d else self.default)
            f += 1
        cs := null
        if self.cs_frame >= 0:
            cs = [self.cs_frame, self.checksums[self.cs_frame]]
        return {"rb": self.local, "f": first, "i": ins, "a": self.confirmed, "n": self.frame, "c": cs}

    func unpack(msg):
        p := msg["rb"]
        if p == self.local or p < 0 or p >= self.players:
            return
        f := msg["f"]
        for inp in msg["i"]:
            self.add_remote_input(p, f, inp)
            f += 1
        a := msg["a"]
        if len(a) == self.players and a[self.local] > self.remote_ack[p]:
            self.remote_ack[p] = a[self.local]
        if msg["n"] > self.remote_frame[p]:
            self.remote_frame[p] = msg["n"]
        c := msg["c"]
        if c != null and c[0] in self.checksums and self.checksums[c[0]] != c[1] and self.desync == null:
            self.desync = {"frame": c[0], "player": p}

# Liaison réseau d'une session : endpoint = netgame.Server (hôte, relaie les entrées) ou netgame.Client.
class RollbackNet:
    func init(session, endpoint):
        self.session = session
        self.endpoint = endpoint
        self.is_server = type(endpoint.clients) == "dict" if _has_clients(endpoint) else false

    func send():
        m := self.session.pack()
        if self.is_server:
            self.endpoint.broadcast(m)
        else:
            self.endpoint.send(m)

    # Événement d'un update() ; rend true s'il s'agissait d'entrées de rollback.
    func handle(e):
        if e["type"] != "message" or type(e["data"]) != "dict" or not ("rb" in e["data"]):
            return false
        self.session.unpack(e["data"])
        if self.is_server:
            self.endpoint.broadcast(e["data"], false, e["client"])
        return true

    func rtt():
        if self.is_server:
            worst := 0.0
            for c in self.endpoint.client_ids():
                worst = math.max(worst, self.endpoint.rtt(c))
            return worst
        return self.endpoint.rtt()

    func should_wait(fps=60.0):
        return self.session.should_wait(self.rtt(), fps)

func _has_clients(ep):
    try:
        x := ep.clients
        return true
    catch e:
        return false
