# ALEX STANDARD LIBRARY — multimedia.pipeline.scheduler
#
# Exécution COOPÉRATIVE d'un graphe (un seul fil, déterministe) : à chaque pas, les nœuds avancent dans l'ordre
# topologique tant que leurs sorties acceptent des éléments (contre-pression) ; une source n'est sollicitée que si
# toutes ses files de sortie ont de la place. Fins de flux propagées, annulation vérifiée à chaque pas, arrêt
# propre (stop() de chaque nœud, même en cas d'erreur), détection des blocages.
#
#   use multimedia.pipeline.scheduler as ps
#   s := ps.Scheduler(g)
#   r := s.run()                       # jusqu'à la fin de tous les flux ; dict de statistiques
#   r2 := s.run(jeton, 1000)           # avec annulation et au plus 1000 pas
#   (une source qui renvoie null « rien pour l'instant » fait attendre run() par courtes pauses, sans blocage)
#   s.step()                           # un seul pas (intégration dans une boucle d'événements) ; vrai s'il a avancé
#   print(r["steps"], r["nodes"]["gain"]["processed"], r["queues"])
#
# Erreurs : PipelineError (graphe invalide, blocage, échec d'un nœud en politique « fail »), CancelledError.

from core use len
from collections use append, keys
use multimedia.core.errors as merr
use multimedia.core.cancellation as mc
use multimedia.pipeline.node as nd
use multimedia.pipeline.graph as _pg
use time as _t

class Scheduler:
    func init(graph, budget=64, idle_sleep=0.002):
        graph.validate()
        self.idle_sleep = idle_sleep
        self.graph = graph
        self.order = graph.order()
        self.budget = budget
        self.outbox = {}
        self.done = {}
        self.eos_seen = {}
        self.steps = 0
        self.source_waiting = false
        self.started = false
        self.stopped = false
        for n in self.order:
            self.outbox[n] = []
            self.done[n] = false
            self.eos_seen[n] = 0

    func _start():
        if self.started:
            return
        self.started = true
        for n in self.order:
            self.graph.nodes[n].start()

    # Arrêt propre : stop() de chaque nœud une seule fois.
    func stop():
        if self.stopped:
            return
        self.stopped = true
        first_error := null
        for n in self.order:
            try:
                self.graph.nodes[n].stop()
            catch e:
                if first_error == null:
                    first_error = e
        if first_error != null:
            raise(first_error.type, first_error.message)

    func finished():
        for n in self.order:
            if not self.done[n] or len(self.outbox[n]) > 0:
                return false
        return true

    # Tente de vider la boîte de sortie d'un nœud dans ses files ; vrai si elle est vide.
    func _flush(name):
        box := self.outbox[name]
        outs := self.graph.outputs(name)
        k := 0
        while k < len(box):
            item := box[k]
            ok := true
            for e in outs:
                if not e.queue.can_accept() and not nd.is_eos(item):
                    ok = false
            if not ok:
                break
            for e in outs:
                e.queue.push(item)
            k += 1
        if k > 0:
            self.outbox[name] = [box[j] for j in k..len(box)]
        return len(self.outbox[name]) == 0

    func _emit(name, items):
        node := self.graph.nodes[name]
        for x in items:
            append(self.outbox[name], x)
            if not nd.is_eos(x):
                node.produced += 1

    func _advance_source(name, node):
        moved := false
        n := 0
        while n < self.budget and not self.done[name]:
            if not self._flush(name):
                break
            item := null
            r := self.graph.recovery[name].run(name, (x) => node.pull(), null)
            if not r[0]:
                n += 1
                moved = true
                continue
            item = r[1]
            if item == null:
                self.source_waiting = true
                break
            moved = true
            n += 1
            if nd.is_eos(item):
                self.done[name] = true
                self._emit(name, node.finish() + [nd.EOS])
            else:
                self._emit(name, [item])
        self._flush(name)
        return moved

    func _advance(name, node):
        moved := false
        ins := self.graph.inputs(name)
        n := 0
        while n < self.budget and not self.done[name]:
            if not self._flush(name):
                break
            got := false
            for e in ins:
                if self.done[name]:
                    break
                item := e.queue.pop()
                if item == null:
                    continue
                got = true
                n += 1
                if nd.is_eos(item):
                    self.eos_seen[name] = self.eos_seen[name] + 1
                    if self.eos_seen[name] >= len(ins):
                        self.done[name] = true
                        self._emit(name, node.finish() + [nd.EOS])
                    continue
                r := self.graph.recovery[name].run(name, (x) => node.process(x), item)
                node.processed += 1
                if r[0] and r[1] != null:
                    self._emit(name, r[1])
                if not self._flush(name):
                    break
            if not got:
                break
            moved = true
        self._flush(name)
        return moved

    # Un pas : chaque nœud avance d'au plus `budget` éléments. Vrai si quelque chose a bougé.
    func step(token=null):
        mc.check(token)
        self._start()
        self.steps += 1
        self.source_waiting = false
        moved := false
        for name in self.order:
            node := self.graph.nodes[name]
            before := len(self.outbox[name])
            m := false
            if node.is_source:
                m = self._advance_source(name, node)
            else:
                m = self._advance(name, node)
            if m or len(self.outbox[name]) != before:
                moved = true
        return moved

    func run(token=null, max_steps=null):
        try:
            idle := 0
            while not self.finished():
                if max_steps != null and self.steps >= max_steps:
                    break
                if self.step(token):
                    idle = 0
                else:
                    idle += 1
                    if self.source_waiting:
                        # une source attend des données (flux en direct) : pas un blocage
                        idle = 0
                        _t.sleep(self.idle_sleep)
                    elif idle >= 3:
                        waiting := [n for n in self.order if not self.done[n]]
                        merr.fail(merr.PIPELINE, "blocage : aucun nœud ne peut avancer (en attente : " + str(waiting) + ")")
        catch e:
            try:
                self.stop()
            catch e2:
                pass
            raise(e.type, e.message)
        if self.finished():
            self.stop()
        return self.stats()

    func stats():
        ns := {}
        for n in self.order:
            node := self.graph.nodes[n]
            r := self.graph.recovery[n]
            ns[n] = {"processed": node.processed, "produced": node.produced, "done": self.done[n],
                     "skipped": r.skipped, "retried": r.retried, "errors": len(r.errors)}
        return {"steps": self.steps, "finished": self.finished(), "nodes": ns, "queues": self.graph.queues()}

# Construit et exécute un graphe linéaire : run_chain([source, n1, n2, puits]).
func run_chain(nodes, capacity=16, token=null):
    g := _pg.Graph()
    for n in nodes:
        g.add(n)
    g.chain([n.name for n in nodes], capacity)
    return Scheduler(g).run(token)
