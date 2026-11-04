# alex: native
# ALEX STANDARD LIBRARY — storage_driver.storage_queue
#
# File de requêtes d'un périphérique de blocs : les systèmes de fichiers et les applications déposent des
# lectures / écritures / vidages ; la file les ordonne (ascenseur : par LBA croissant à partir de la position
# courante de la tête, puis retour), FUSIONNE les requêtes contiguës de même sens dont les tampons se suivent,
# les exécute sur le BlockDevice et appelle la fonction de fin de chacune. Un vidage (flush) est une barrière :
# rien n'est réordonné par-dessus.
#
#   use storage_driver.storage_queue as sq
#   q := sq.StorageQueue(disque, 256)            # fusion jusqu'à 256 blocs
#   r := q.read(100, 8, tampon)
#   q.write(5000, 1, autre)
#   q.flush()
#   q.run()                                      # tout exécuter
#   print(r.done, q.stats())
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use hw
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice

const READ := 1
const WRITE := 2
const FLUSH := 3

func op_name(op: int) -> str:
    if op == READ:
        return "lecture"
    if op == WRITE:
        return "écriture"
    return "vidage"

class Request:
    id: int := 0
    op: int := 0
    lba: int := 0
    count: int := 0
    buf: int := 0
    done: bool := false
    ok: bool := false
    error: str := ""
    on_done: func(Request)?

    func init(op: int, lba: int, count: int, buf: int):
        self.id = 0
        self.op = op
        self.lba = lba
        self.count = count
        self.buf = buf
        self.done = false
        self.ok = false
        self.error = ""
        self.on_done = null

    func then(fn: func(Request)):
        self.on_done = fn

    func finish(ok: bool, error: str):
        self.done = true
        self.ok = ok
        self.error = error
        f := self.on_done
        if f != null:
            f(self)

    func describe() -> str:
        return op_name(self.op) + " " + str(self.lba) + "+" + str(self.count)

class StorageQueue:
    dev: BlockDevice
    pending: list[Request] := []
    max_merge: int := 256
    head: int := 0
    next_id: int := 1
    submitted: int := 0
    completed: int := 0
    failed: int := 0
    merged: int := 0
    operations: int := 0          # commandes réellement envoyées au périphérique
    seek_distance: int := 0

    func init(dev: BlockDevice, max_merge: int):
        self.dev = dev
        self.pending = []
        self.max_merge = max_merge
        self.head = 0
        self.next_id = 1
        self.submitted = 0
        self.completed = 0
        self.failed = 0
        self.merged = 0
        self.operations = 0
        self.seek_distance = 0

    func submit(r: Request) -> Request:
        r.id = self.next_id
        self.next_id += 1
        append(self.pending, r)
        self.submitted += 1
        return r

    func read(lba: int, count: int, buf: int) -> Request:
        return self.submit(Request(READ, lba, count, buf))

    func write(lba: int, count: int, buf: int) -> Request:
        return self.submit(Request(WRITE, lba, count, buf))

    func flush() -> Request:
        return self.submit(Request(FLUSH, 0, 0, 0))

    func size() -> int:
        return len(self.pending)

    # Lot suivant : requêtes jusqu'à la prochaine barrière, triées en ascenseur.
    func _batch() -> list[Request]:
        batch: list[Request] := []
        rest: list[Request] := []
        barrier := false
        for r in self.pending:
            if barrier:
                append(rest, r)
            elif r.op == FLUSH:
                if len(batch) == 0:
                    append(batch, r)
                else:
                    append(rest, r)
                barrier = true
            else:
                append(batch, r)
        self.pending = rest
        if len(batch) > 1:
            # tri par LBA (insertion), puis rotation : d'abord celles au-delà de la tête
            k := 1
            while k < len(batch):
                x := batch[k]
                j := k - 1
                while j >= 0 and batch[j].lba > x.lba:
                    batch[j + 1] = batch[j]
                    j -= 1
                batch[j + 1] = x
                k += 1
            up: list[Request] := []
            down: list[Request] := []
            for r in batch:
                if r.lba >= self.head:
                    append(up, r)
                else:
                    append(down, r)
            for r in down:
                append(up, r)
            batch = up
        return batch

    func _execute(group: list[Request]):
        first := group[0]
        total := 0
        for r in group:
            total += r.count
        self.operations += 1
        try:
            if first.op == FLUSH:
                self.dev.flush()
            else:
                d := first.lba - self.head
                if d < 0:
                    d = -d
                self.seek_distance += d
                if first.op == READ:
                    self.dev.read_blocks(first.lba, total, first.buf)
                else:
                    self.dev.write_blocks(first.lba, total, first.buf)
                self.head = first.lba + total
            for r in group:
                self.completed += 1
                r.finish(true, "")
        catch e:
            for r in group:
                self.failed += 1
                r.finish(false, e.type + " : " + e.message)

    # Exécute au plus max_ops commandes ; renvoie le nombre de requêtes terminées.
    func process(max_ops: int) -> int:
        before := self.completed + self.failed
        ops := 0
        while ops < max_ops and len(self.pending) > 0:
            batch := self._batch()
            i := 0
            while i < len(batch):
                group: list[Request] := [batch[i]]
                blocks := batch[i].count
                bs := self.dev.block_size()
                j := i + 1
                while j < len(batch) and batch[i].op != FLUSH:
                    prev := group[len(group) - 1]
                    nx := batch[j]
                    if nx.op != prev.op or nx.lba != prev.lba + prev.count or nx.buf != prev.buf + prev.count * bs:
                        break
                    if blocks + nx.count > self.max_merge:
                        break
                    append(group, nx)
                    blocks += nx.count
                    self.merged += 1
                    j += 1
                self._execute(group)
                ops += 1
                i = j
        return self.completed + self.failed - before

    func run() -> int:
        n := 0
        while len(self.pending) > 0:
            n += self.process(1000000)
        return n

    func stats() -> str:
        return str(self.completed) + " terminées, " + str(self.failed) + " en échec, " + str(self.merged) + " fusionnées, " + str(self.operations) + " commandes, déplacement " + str(self.seek_distance) + " blocs"
