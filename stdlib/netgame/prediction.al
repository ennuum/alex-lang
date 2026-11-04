# ALEX STANDARD LIBRARY — netgame.prediction
#
# PRÉDICTION CÔTÉ CLIENT et RÉCONCILIATION (serveur autoritaire) :
#   - le client applique ses entrées tout de suite à son propre état (pas d'attente du serveur), les numérote et
#     les envoie avec redondance (les dernières entrées non confirmées partent dans chaque paquet : une perte ne
#     coûte rien) ;
#   - le serveur rejoue les entrées dans l'ordre (InputBuffer) et renvoie, avec l'instantané, l'état autoritaire du
#     joueur et le numéro de la dernière entrée traitée ;
#   - le client repart de cet état, rejoue les entrées pas encore traitées et, s'il s'était trompé, LISSE la
#     correction (décalage visuel qui s'amortit) au lieu de téléporter le personnage.
# La fonction de simulation doit être la même des deux côtés : simulate(état, entrée, dt) -> nouvel état.
#
#   use netgame.prediction as pred
#   func bouger(s, e, dt):
#       return {"x": s["x"] + e["dx"] * 5.0 * dt, "y": s["y"] + e["dy"] * 5.0 * dt}
#   p := pred.Predictor(bouger, {"x": 0.0, "y": 0.0}, 1.0 / 60.0, ["x", "y"])
#   # chaque pas client
#   p.apply({"dx": 1, "dy": 0})
#   cli.send({"in": p.pending_inputs(), "ack": sc.ack_tick()})
#   etat_affiche := p.visual(dt_image)
#   # instantané reçu : extra = {"input": dernier numéro traité, "me": état du joueur}
#   p.reconcile(extra["me"], extra["input"])
#   # serveur : buf := pred.InputBuffer() par client ; buf.receive(m["in"]) ; e := buf.pop() ; buf.last
#
# Erreurs : ValueError (entrées mal formées).

from core use len, type
from collections use append, keys, remove
use math
use netgame.codec as nc

class Predictor:
    # smooth : champs numériques dont la correction est lissée ; snap : écart au-delà duquel on téléporte.
    func init(simulate, state, dt=0.016666666666666666, smooth=null, smooth_rate=12.0, snap=3.0, copy=null):
        self.simulate = simulate
        self.copy = copy if copy != null else nc.deep_copy
        self.state = self.copy(state)
        self.dt = dt
        self.seq = 0
        self.pending = []            # [[numéro, entrée]...] non confirmées
        self.smooth = smooth if smooth != null else []
        self.smooth_rate = smooth_rate
        self.snap = snap
        self.offset = {}
        for f in self.smooth:
            self.offset[f] = 0.0
        self.acked = 0
        self.corrections = 0
        self.last_error = 0.0

    # Applique une entrée localement ; rend son numéro.
    func apply(input):
        self.seq += 1
        self.state = self.simulate(self.copy(self.state), input, self.dt)
        append(self.pending, [self.seq, input])
        if len(self.pending) > 1024:
            self.pending = self.pending[len(self.pending) - 1024:len(self.pending)]
        return self.seq

    # [premier numéro, [entrées...]] : les `limit` dernières entrées non confirmées (redondance contre les pertes).
    func pending_inputs(limit=16):
        n := len(self.pending)
        if n == 0:
            return [self.seq + 1, []]
        s := n - limit if n > limit else 0
        return [self.pending[s][0], [p[1] for p in self.pending[s:n]]]

    # État autoritaire du serveur après traitement de l'entrée last_seq.
    func reconcile(server_state, last_seq):
        if last_seq < self.acked:
            return
        self.acked = last_seq
        keep := []
        for p in self.pending:
            if p[0] > last_seq:
                append(keep, p)
        self.pending = keep
        old := self.state
        s := self.copy(server_state)
        for p in self.pending:
            s = self.simulate(s, p[1], self.dt)
        err := 0.0
        for f in self.smooth:
            if f in old and f in s:
                d := old[f] - s[f]
                err += d * d
        err = math.sqrt(err)
        self.last_error = err
        if err > 1e-6:
            self.corrections += 1
            if err > self.snap:
                for f in self.smooth:
                    self.offset[f] = 0.0
            else:
                for f in self.smooth:
                    if f in old and f in s:
                        self.offset[f] = self.offset[f] + old[f] - s[f]
        self.state = s

    # État à afficher : état prédit + correction en cours d'amortissement.
    func visual(frame_dt=null):
        k := math.exp(-self.smooth_rate * (frame_dt if frame_dt != null else self.dt))
        v := self.copy(self.state)
        for f in self.smooth:
            self.offset[f] = self.offset[f] * k
            if f in v:
                v[f] = v[f] + self.offset[f]
        return v

# Tampon des entrées d'un client côté serveur : reçoit les paquets redondants, rend les entrées dans l'ordre.
class InputBuffer:
    func init(max_queue=120):
        self.last = 0                # dernière entrée traitée
        self.queue = {}
        self.last_input = null
        self.max_queue = max_queue
        self.missing = 0

    # pending : [premier numéro, [entrées...]] (Predictor.pending_inputs).
    func receive(pending):
        if type(pending) != "list" or len(pending) != 2 or type(pending[1]) != "list":
            raise("ValueError", "netgame.prediction : entrées mal formées")
        s := pending[0]
        for inp in pending[1]:
            if s > self.last and not (s in self.queue) and s <= self.last + self.max_queue:
                self.queue[s] = inp
            s += 1

    func available():
        return (self.last + 1) in self.queue

    # Entrée suivante dans l'ordre, ou null si elle n'est pas encore arrivée (repeat : rejouer la dernière connue,
    # sans avancer le numéro).
    func pop(repeat=false):
        n := self.last + 1
        if n in self.queue:
            inp := self.queue[n]
            remove(self.queue, n)
            self.last = n
            self.last_input = inp
            return inp
        self.missing += 1
        return self.last_input if repeat else null

    # Toutes les entrées disponibles dans l'ordre (rattrapage après un paquet arrivé en retard), au plus `limit`.
    func pop_all(limit=8):
        out := []
        while len(out) < limit and self.available():
            append(out, self.pop())
        return out
