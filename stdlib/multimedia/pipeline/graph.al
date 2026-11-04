# ALEX STANDARD LIBRARY — multimedia.pipeline.graph
#
# Graphe de traitement : nœuds nommés reliés par des files bornées (multimedia.pipeline.backpressure). Une sortie
# reliée à plusieurs nœuds est DUPLIQUÉE vers chacun ; un nœud à plusieurs entrées reçoit leurs éléments à mesure
# (fusion) et ne finit qu'après la fin de flux de toutes ses entrées.
#
#   use multimedia.pipeline.graph as pg
#   use multimedia.pipeline.node as nd
#   g := pg.Graph()
#   g.add(nd.demux_source("fichier", dmx.open("voix.wav")))
#   g.add(nd.audio_gain("gain", 0.5))
#   g.add(nd.collect("sortie"))
#   g.connect("fichier", "gain", 4)              # file de 4 éléments, politique « block »
#   g.connect("gain", "sortie", 4, "drop_oldest")
#   g.chain(["a", "b", "c"])                     # raccourci : relie dans l'ordre
#   g.validate()                                  # PipelineError : cycle, nœud isolé, source avec entrée...
#   print(g.order())                              # noms dans l'ordre topologique
#
# Exécution : multimedia.pipeline.scheduler. Erreurs : PipelineError.

from core use len
from collections use append, keys
use multimedia.core.errors as merr
use multimedia.pipeline.backpressure as bp
use multimedia.pipeline.recovery as rec

class Edge:
    func init(src, dst, queue):
        self.src = src
        self.dst = dst
        self.queue = queue

class Graph:
    func init():
        self.nodes = {}
        self.names = []
        self.edges = []
        self.recovery = {}

    func add(node):
        if node.name in self.nodes:
            merr.fail(merr.PIPELINE, "nœud « " + node.name + " » déjà présent")
        self.nodes[node.name] = node
        append(self.names, node.name)
        self.recovery[node.name] = rec.fail()
        return node

    func node(name):
        if not (name in self.nodes):
            merr.fail(merr.PIPELINE, "nœud « " + str(name) + " » inconnu")
        return self.nodes[name]

    func connect(src, dst, capacity=16, policy="block"):
        self.node(src)
        d := self.node(dst)
        if d.is_source:
            merr.fail(merr.PIPELINE, "« " + dst + " » est une source : elle n'a pas d'entrée")
        for e in self.edges:
            if e.src == src and e.dst == dst:
                merr.fail(merr.PIPELINE, "liaison « " + src + " » -> « " + dst + " » en double")
        e := Edge(src, dst, bp.BoundedQueue(capacity, policy))
        append(self.edges, e)
        return e

    func chain(names, capacity=16, policy="block"):
        for i in 0..len(names) - 1:
            self.connect(names[i], names[i + 1], capacity, policy)
        return self

    func set_recovery(name, policy):
        self.node(name)
        self.recovery[name] = policy

    func inputs(name):
        return [e for e in self.edges if e.dst == name]

    func outputs(name):
        return [e for e in self.edges if e.src == name]

    func sources():
        return [n for n in self.names if self.nodes[n].is_source]

    # Ordre topologique (Kahn) ; PipelineError s'il y a un cycle.
    func order():
        indeg := {}
        for n in self.names:
            indeg[n] = 0
        for e in self.edges:
            indeg[e.dst] = indeg[e.dst] + 1
        ready := [n for n in self.names if indeg[n] == 0]
        out := []
        while len(ready) > 0:
            n := ready[0]
            ready = [ready[k] for k in 1..len(ready)]
            append(out, n)
            for e in self.outputs(n):
                indeg[e.dst] = indeg[e.dst] - 1
                if indeg[e.dst] == 0:
                    append(ready, e.dst)
        if len(out) != len(self.names):
            left := [n for n in self.names if not (n in out)]
            merr.fail(merr.PIPELINE, "cycle dans le graphe entre : " + str(left))
        return out

    func validate():
        if len(self.names) == 0:
            merr.fail(merr.PIPELINE, "graphe vide")
        if len(self.sources()) == 0:
            merr.fail(merr.PIPELINE, "aucune source")
        self.order()
        for n in self.names:
            nd := self.nodes[n]
            ins := self.inputs(n)
            outs := self.outputs(n)
            if not nd.is_source and len(ins) == 0:
                merr.fail(merr.PIPELINE, "nœud « " + n + " » sans entrée")
            if nd.is_source and len(outs) == 0:
                merr.fail(merr.PIPELINE, "source « " + n + " » reliée à rien")
        return true

    func queues():
        out := {}
        for e in self.edges:
            out[e.src + " -> " + e.dst] = e.queue.stats()
        return out

    func describe():
        out := []
        for e in self.edges:
            append(out, e.src + " -> " + e.dst + " [" + str(e.queue.capacity) + ", " + e.queue.policy + "]")
        return out
