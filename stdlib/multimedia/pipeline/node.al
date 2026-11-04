# ALEX STANDARD LIBRARY — multimedia.pipeline.node
#
# Nœuds d'un graphe de traitement. Un nœud reçoit des éléments (Frame, Packet ou toute valeur) et en produit :
#   Node              base : process(item) -> liste d'éléments, finish() -> éléments vidés à la fin du flux,
#                     start() / stop() pour ouvrir et libérer ses ressources ;
#   SourceNode        produit les éléments : pull() -> élément, null (rien pour l'instant) ou EOS ;
#   SinkNode          consomme (process renvoie []).
# Nœuds prêts à l'emploi : from_list, from_function (générateur appelé jusqu'à EOS), demux_source (paquets ou
# trames d'un démultiplexeur), map, filter, batch (regroupe n éléments), audio_gain, collect (puits qui garde
# tout), callback (puits qui appelle une fonction), audio_output (puits vers un flux audio .write()).
#
#   use multimedia.pipeline.node as nd
#   src := nd.from_list("nombres", [1, 2, 3])
#   double := nd.map("double", (x) => x * 2)
#   puits := nd.collect("sortie")
#   # graphe : voir multimedia.pipeline.graph ; puits.items == [2, 4, 6] après exécution
#
# La fin de flux est un objet dont le champ `eos` est vrai (nd.EOS, ou les fins de flux de multimedia.core.buffer).

from core use len, type
from collections use append
use multimedia.core.errors as merr
use multimedia.core.buffer as mb

class EndOfStream:
    func init():
        self.eos = true

    func describe():
        return "fin de flux"

EOS := EndOfStream()

func is_eos(item):
    if item == null or type(item) != "instance":
        return false
    try:
        return item.eos == true
    catch e:
        return false

class Node:
    func init(name):
        self.name = name
        self.is_source = false
        self.processed = 0
        self.produced = 0
        self.started = false

    func start():
        self.started = true

    func stop():
        self.started = false

    func process(item):
        return [item]

    func finish():
        return []

    func describe():
        return self.name

class SourceNode extends Node:
    func init(name):
        super.init(name)
        self.is_source = true

    # Élément suivant, null si rien n'est prêt, ou une fin de flux.
    func pull():
        return EOS

class SinkNode extends Node:
    func init(name):
        super.init(name)

    func process(item):
        self.consume(item)
        return []

    func consume(item):
        return null

# ------------------------------------------------------------------------------------------- sources
class ListSource extends SourceNode:
    func init(name, items):
        super.init(name)
        self.items = items
        self.pos = 0

    func pull():
        if self.pos >= len(self.items):
            return EOS
        x := self.items[self.pos]
        self.pos += 1
        return x

class FunctionSource extends SourceNode:
    func init(name, fn):
        super.init(name)
        self.fn = fn

    func pull():
        return self.fn()

# Paquets (raw=true) ou trames décodées d'un démultiplexeur (multimedia.container.demux).
class DemuxSource extends SourceNode:
    func init(name, demuxer, frames=4096, raw=false, close_at_end=true):
        super.init(name)
        self.demuxer = demuxer
        self.frames = frames
        self.raw = raw
        self.close_at_end = close_at_end

    func pull():
        if self.raw:
            return self.demuxer.read_packet(self.frames)
        return self.demuxer.read_frame(self.frames)

    func stop():
        super.stop()
        if self.close_at_end:
            self.demuxer.close()

func from_list(name, items):
    return ListSource(name, items)

func from_function(name, fn):
    return FunctionSource(name, fn)

func demux_source(name, demuxer, frames=4096, raw=false):
    return DemuxSource(name, demuxer, frames, raw)

# ------------------------------------------------------------------------------------------- transformations
class MapNode extends Node:
    func init(name, fn):
        super.init(name)
        self.fn = fn

    func process(item):
        return [self.fn(item)]

class FilterNode extends Node:
    func init(name, pred):
        super.init(name)
        self.pred = pred

    func process(item):
        if self.pred(item):
            return [item]
        return []

class BatchNode extends Node:
    func init(name, size):
        super.init(name)
        if size <= 0:
            merr.fail(merr.FORMAT, "taille de lot invalide : " + str(size))
        self.size = size
        self.current = []

    func process(item):
        append(self.current, item)
        if len(self.current) >= self.size:
            out := self.current
            self.current = []
            return [out]
        return []

    func finish():
        if len(self.current) == 0:
            return []
        out := self.current
        self.current = []
        return [out]

# Gain sur des Frame audio (facteur linéaire, écrêté à -1..1).
class GainNode extends Node:
    func init(name, gain):
        super.init(name)
        self.gain = gain

    func process(f):
        g := self.gain
        out := []
        for x in f.data:
            v := x * g
            if v > 1.0:
                v = 1.0
            elif v < -1.0:
                v = -1.0
            append(out, v)
        nf := mb.Frame(f.kind, out, f.format, f.pts, f.duration)
        return [nf]

func map(name, fn):
    return MapNode(name, fn)

func filter(name, pred):
    return FilterNode(name, pred)

func batch(name, size):
    return BatchNode(name, size)

func audio_gain(name, gain):
    return GainNode(name, gain)

# ------------------------------------------------------------------------------------------- puits
class CollectSink extends SinkNode:
    func init(name, limit=null):
        super.init(name)
        self.items = []
        self.limit = limit
        self.ended = false

    func consume(item):
        if self.limit != null and len(self.items) >= self.limit:
            merr.fail(merr.LIMIT, "puits " + self.name + " : plus de " + str(self.limit) + " éléments")
        append(self.items, item)

    func finish():
        self.ended = true
        return []

class CallbackSink extends SinkNode:
    func init(name, fn):
        super.init(name)
        self.fn = fn

    func consume(item):
        self.fn(item)

# Écrit les Frame audio sur un flux de sortie : méthode write(échantillons) (audio.audio_stream.PlayerStream,
# MemorySink...) ou write_samples (multimedia.container.mux.WavMuxer) selon `method`.
class AudioOutputSink extends SinkNode:
    func init(name, stream, close_at_end=true, method="write"):
        super.init(name)
        if method != "write" and method != "write_samples":
            merr.fail(merr.FORMAT, "méthode d'écriture inconnue : " + str(method))
        self.stream = stream
        self.close_at_end = close_at_end
        self.method = method
        self.frames = 0

    func consume(f):
        if f.data != null and len(f.data) > 0:
            if self.method == "write_samples":
                self.stream.write_samples(f.data)
            else:
                self.stream.write(f.data)
            self.frames += f.frames()

    func finish():
        if self.close_at_end:
            self.stream.close()
        return []

func collect(name, limit=null):
    return CollectSink(name, limit)

func callback(name, fn):
    return CallbackSink(name, fn)

func audio_output(name, stream, close_at_end=true, method="write"):
    return AudioOutputSink(name, stream, close_at_end, method)
