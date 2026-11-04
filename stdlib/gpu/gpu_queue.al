# ALEX STANDARD LIBRARY — gpu.gpu_queue
#
# Files de commandes pour un gpu.gpu_device.GpuDevice : on enregistre une liste de commandes (CommandList)
# puis on la soumet ; la file l'exécute dans l'ordre et signale une barrière (gpu.gpu_fence.Fence).
#   - commandes : write (envoi), read (lecture, vers une liste ou un rappel), copy, fill, dispatch (opérations
#     nommées du ComputeDevice : saxpy, add, mul, scale, sum, dot, matmul, lut, histogram, convolve2d — ou un
#     noyau de l'utilisateur), barrier, signal / wait d'une Timeline, host (fonction du programme) ;
#   - modes : « immediate » (exécution à la soumission) ou « deferred » (exécution quand on attend une
#     barrière, flush() ou step() — permet d'enregistrer beaucoup de travail puis de le lancer) ;
#   - une commande qui échoue fait échouer la soumission (la barrière relance l'erreur), les suivantes
#     continuent ; lose() simule la perte du périphérique (DeviceLost ensuite) ;
#   - statistiques : soumissions, commandes, octets envoyés / lus, temps d'exécution.
#
#   use gpu.gpu_device as gd
#   use gpu.gpu_queue as gq
#   dev := gd.software()
#   x := dev.memory.upload([1.0, 2.0, 3.0])
#   y := dev.memory.upload([1.0, 1.0, 1.0])
#   out := dev.memory.zeros("float32", [3])
#   q := gq.GpuQueue(dev, "deferred")
#   cl := gq.CommandList("saxpy").dispatch("saxpy", [x, y], out, [2.0])
#   res := []
#   cl.read(out, res)
#   q.submit(cl).wait(5.0)
#   print(res)                     # [3.0, 5.0, 7.0]
#
# Erreurs : QueueError (file fermée, commande invalide, tampon libéré), DeviceLost, FenceTimeout, erreurs
# des commandes (MemoryError, ArgumentError...).

from core use len, type
from collections use append
use asyncio as _as
use gpu.gpu_fence as _gf
use gpu.gpu_memory as _gm

const OPS := ["saxpy", "add", "mul", "scale", "sum", "dot", "matmul", "lut", "histogram", "convolve2d"]

class CommandList:
    func init(name="commands"):
        self.name = name
        self.commands = []
        self.closed = false

    func _add(cmd):
        if self.closed:
            raise("QueueError", "CommandList « " + self.name + " » déjà soumise (créer une nouvelle liste ou reset())")
        append(self.commands, cmd)
        return self

    func write(buf, values):
        return self._add({"op": "write", "buf": buf, "values": values})

    # dest : liste à remplir, ou fonction appelée avec les données.
    func read(buf, dest):
        return self._add({"op": "read", "buf": buf, "dest": dest})

    func copy(src, dst):
        return self._add({"op": "copy", "src": src, "dst": dst})

    func fill(buf, value):
        return self._add({"op": "fill", "buf": buf, "value": value})

    # op : nom d'une opération (OPS) ou fonction kernel(données des entrées..., args...) -> liste ;
    # inputs : tampons d'entrée ; output : tampon de sortie (ou null pour sum/dot : résultat via read_scalar).
    func dispatch(op, inputs, output, args=null):
        if type(op) == "str" and not (op in OPS):
            raise("QueueError", "dispatch : opération inconnue « " + op + " » (" + str(OPS) + ")")
        return self._add({"op": "dispatch", "kernel": op, "inputs": inputs, "output": output, "args": args if args != null else []})

    func barrier():
        return self._add({"op": "barrier"})

    func signal(timeline, value):
        return self._add({"op": "signal", "timeline": timeline, "value": value})

    func wait(timeline, value):
        return self._add({"op": "wait", "timeline": timeline, "value": value})

    func host(fn):
        return self._add({"op": "host", "fn": fn})

    func count():
        return len(self.commands)

    func reset():
        self.commands = []
        self.closed = false
        return self

class _Submission:
    func init(cl, fence):
        self.commands = [c for c in cl.commands]
        self.name = cl.name
        self.fence = fence
        self.pos = 0
        self.error = null
        self.results = []

class GpuQueue:
    func init(device, mode="immediate", name="queue"):
        if mode != "immediate" and mode != "deferred":
            raise("ArgumentError", "GpuQueue : mode « immediate » ou « deferred »")
        self.device = device
        self.mode = mode
        self.name = name
        self.pending = []
        self.seq = 0
        self.closed = false
        self.lost = false
        self.submissions = 0
        self.executed = 0
        self.commands = 0
        self.bytes_up = 0
        self.bytes_down = 0
        self.busy_time = 0.0
        self.results = {}

    func _check_open():
        if self.lost:
            raise("DeviceLost", "file « " + self.name + " » : périphérique perdu")
        if self.closed:
            raise("QueueError", "file « " + self.name + " » fermée")

    func submit(cl):
        self._check_open()
        self.seq += 1
        fence := _gf.Fence(cl.name, self, self.seq)
        cl.closed = true
        append(self.pending, _Submission(cl, fence))
        self.submissions += 1
        if self.mode == "immediate":
            self.flush()
        return fence

    func idle():
        return len(self.pending) == 0

    func depth():
        return len(self.pending)

    # Exécute une soumission en attente ; false s'il n'y en a pas (ou si elle attend une Timeline).
    func step():
        if len(self.pending) == 0:
            return false
        if self.lost:
            for s in self.pending:
                s.fence.fail("DeviceLost", "périphérique perdu avant l'exécution de « " + s.name + " »")
            self.pending = []
            return true
        s := self.pending[0]
        t0 := _as.now()
        while s.pos < len(s.commands):
            c := s.commands[s.pos]
            if c["op"] == "wait" and not c["timeline"].reached(c["value"]):
                self.busy_time += _as.now() - t0
                return false
            try:
                self._run(c, s)
            catch e:
                if s.error == null:
                    s.error = [e.type, "« " + s.name + " », commande " + str(s.pos) + " (" + c["op"] + ") : " + e.message]
            s.pos += 1
            self.commands += 1
        self.busy_time += _as.now() - t0
        self.pending = [self.pending[i] for i in 1..len(self.pending)]
        self.executed += 1
        self.results[s.fence.seq] = s.results
        if s.error != null:
            s.fence.fail(s.error[0], s.error[1])
        else:
            s.fence.signal()
        return true

    func flush():
        while self.step():
            self.executed = self.executed
        return self.idle()

    # Attend la fin de tout le travail soumis.
    func wait_idle(timeout=null):
        start := _as.now()
        while not self.idle():
            if not self.step():
                if timeout != null and _as.now() - start >= timeout:
                    raise("FenceTimeout", "file « " + self.name + " » : travail en attente après " + str(timeout) + " s")
                if timeout == null:
                    raise("FenceTimeout", "file « " + self.name + " » bloquée sur une Timeline jamais signalée")
        return true

    # Résultats scalaires (sum, dot sans tampon de sortie) d'une soumission, par numéro de barrière.
    func results_of(fence):
        if fence.seq in self.results:
            return self.results[fence.seq]
        return null

    func _buf(b):
        if b.freed:
            raise("QueueError", "tampon " + str(b.id) + " libéré")
        return b

    func _run(c, s):
        op := c["op"]
        if op == "write":
            b := self._buf(c["buf"])
            b.write(c["values"])
            self.bytes_up += b.size_bytes()
        elif op == "read":
            b := self._buf(c["buf"])
            data := b.download()
            self.bytes_down += b.size_bytes()
            d := c["dest"]
            if type(d) == "list":
                for v in data:
                    append(d, v)
            else:
                d(data)
        elif op == "copy":
            src := self._buf(c["src"])
            dst := self._buf(c["dst"])
            if src.count() != dst.count():
                raise("ArgumentError", "copy : tailles différentes (" + str(src.count()) + " / " + str(dst.count()) + ")")
            dst.write(src.download())
        elif op == "fill":
            b := self._buf(c["buf"])
            b.write([c["value"] for i in 0..b.count()])
        elif op == "dispatch":
            self._dispatch(c, s)
        elif op == "signal":
            c["timeline"].signal(c["value"])
        elif op == "host":
            f := c["fn"]
            f()
        elif op == "barrier" or op == "wait":
            return
        else:
            raise("QueueError", "commande inconnue « " + str(op) + " »")

    func _dispatch(c, s):
        ins := [self._buf(b).download() for b in c["inputs"]]
        a := c["args"]
        k := c["kernel"]
        cd := self.device.compute
        r := null
        if type(k) != "str":
            params := [x for x in ins]
            for v in a:
                append(params, v)
            r = _apply(k, params)
        elif k == "saxpy":
            r = cd.saxpy(a[0], ins[0], ins[1])
        elif k == "add":
            r = cd.add(ins[0], ins[1])
        elif k == "mul":
            r = cd.mul(ins[0], ins[1])
        elif k == "scale":
            r = cd.scale(a[0], ins[0])
        elif k == "sum":
            r = cd.sum(ins[0])
        elif k == "dot":
            r = cd.dot(ins[0], ins[1])
        elif k == "matmul":
            r = cd.matmul(ins[0], ins[1], a[0], a[1], a[2])
        elif k == "lut":
            r = cd.map_lut(ins[0], a[0])
        elif k == "histogram":
            r = cd.histogram(ins[0], a[0])
        elif k == "convolve2d":
            r = cd.convolve2d(ins[0], a[0], a[1], a[2], a[3], a[4])
        out := c["output"]
        if out == null:
            append(s.results, r)
            return
        o := self._buf(out)
        if type(r) != "list":
            r = [r]
        if len(r) != o.count():
            raise("ArgumentError", "dispatch " + str(k) + " : " + str(len(r)) + " résultats pour un tampon de " + str(o.count()))
        o.write(r)

    # Simule la perte du périphérique : le travail en attente échoue en DeviceLost.
    func lose():
        self.lost = true
        self.step()

    func close():
        if not self.closed and not self.lost:
            self.flush()
        self.closed = true

    func stats():
        return {"submissions": self.submissions, "executed": self.executed, "commands": self.commands,
                "pending": len(self.pending), "bytes_up": self.bytes_up, "bytes_down": self.bytes_down,
                "busy_time": self.busy_time}

func _apply(fn, p):
    n := len(p)
    if n == 0:
        return fn()
    if n == 1:
        return fn(p[0])
    if n == 2:
        return fn(p[0], p[1])
    if n == 3:
        return fn(p[0], p[1], p[2])
    if n == 4:
        return fn(p[0], p[1], p[2], p[3])
    if n == 5:
        return fn(p[0], p[1], p[2], p[3], p[4])
    raise("ArgumentError", "dispatch : 5 paramètres au plus pour un noyau de l'utilisateur")

# Copie vers un nouveau tampon du même périphérique, en une soumission.
func clone(queue, buf):
    dst := queue.device.memory.allocate(buf.dtype, buf.shape)
    queue.submit(CommandList("clone").copy(buf, dst)).wait()
    return dst
