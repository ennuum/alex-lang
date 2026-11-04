# alex: native
# ALEX STANDARD LIBRARY — storage_driver.storage_request
#
# Requêtes d'E/S complètes pour les pilotes de blocs (complément de storage_queue) :
#   - IoRequest : opération, premier bloc, segments (listes dispersées : plusieurs tampons), priorité,
#     délai en « ticks », nombre de nouvelles tentatives, étiquette (tag) attribuée à l'envoi, état ;
#   - split : découpe selon le transfert maximal du contrôleur, sans couper un bloc ;
#   - TagSet : étiquettes de commandes en vol (NCQ SATA : 32, NVMe : taille de file) ;
#   - RequestTracker : envoi immédiat sur un BlockDevice (avec nouvelles tentatives sur DeviceIoError /
#     DeviceTimeout) ou mode asynchrone (start puis complete(tag) par l'interruption du contrôleur, tick()
#     pour les délais), ordre par priorité, statistiques.
#
#   use storage_driver.storage_request as sr
#   r := sr.IoRequest(sr.READ, 100, 0)
#   r.add_segment(tampon1, 8).add_segment(tampon2, 8)       # 16 blocs dans deux tampons
#   t := sr.RequestTracker(disque, 32)
#   t.execute(r)                                            # vrai si réussi
#   print(r.describe(), t.report())
#
# Erreurs : ArgumentError (requête vide, segments incohérents), DeviceBusy (plus d'étiquette libre).
# Compilable en natif (# alex: native).

from core use len
from collections use append
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice

const READ := 1
const WRITE := 2
const FLUSH := 3

const PENDING := 0
const INFLIGHT := 1
const DONE := 2
const FAILED := 3
const TIMED_OUT := 4

func status_name(s: int) -> str:
    if s == PENDING:
        return "en attente"
    if s == INFLIGHT:
        return "en cours"
    if s == DONE:
        return "terminée"
    if s == FAILED:
        return "échouée"
    return "délai dépassé"

class Segment:
    buf: int := 0
    blocks: int := 0

    func init(buf: int, blocks: int):
        self.buf = buf
        self.blocks = blocks

class IoRequest:
    op: int := 0
    lba: int := 0
    segments: list[Segment] := []
    priority: int := 0          # plus grand : plus urgent
    timeout: int := 0           # ticks (0 : aucun)
    retries: int := 2
    attempts: int := 0
    tag: int := -1
    status: int := 0
    error: str := ""
    started: int := 0

    func init(op: int, lba: int, priority: int):
        self.op = op
        self.lba = lba
        self.segments = []
        self.priority = priority
        self.timeout = 0
        self.retries = 2
        self.attempts = 0
        self.tag = -1
        self.status = PENDING
        self.error = ""
        self.started = 0

    func add_segment(buf: int, blocks: int) -> IoRequest:
        if blocks <= 0:
            raise("ArgumentError", "IoRequest : segment de " + str(blocks) + " blocs")
        append(self.segments, Segment(buf, blocks))
        return self

    func count() -> int:
        n := 0
        for s in self.segments:
            n += s.blocks
        return n

    func finished() -> bool:
        return self.status == DONE or self.status == FAILED or self.status == TIMED_OUT

    func ok() -> bool:
        return self.status == DONE

    # Requêtes d'au plus max_blocks blocs (un segment trop long est coupé ; bs : taille d'un bloc).
    func split(max_blocks: int, bs: int) -> list[IoRequest]:
        out: list[IoRequest] := []
        cur := IoRequest(self.op, self.lba, self.priority)
        cur.timeout = self.timeout
        cur.retries = self.retries
        room := max_blocks
        lba := self.lba
        for s in self.segments:
            buf := s.buf
            left := s.blocks
            while left > 0:
                if room == 0:
                    append(out, cur)
                    cur = IoRequest(self.op, lba, self.priority)
                    cur.timeout = self.timeout
                    cur.retries = self.retries
                    room = max_blocks
                take := left
                if take > room:
                    take = room
                cur.add_segment(buf, take)
                buf += take * bs
                left -= take
                room -= take
                lba += take
        if len(cur.segments) > 0 or self.op == FLUSH:
            append(out, cur)
        return out

    func describe() -> str:
        n := "lecture"
        if self.op == WRITE:
            n = "écriture"
        elif self.op == FLUSH:
            n = "vidage"
        t := n + " " + str(self.lba) + "+" + str(self.count()) + " (" + str(len(self.segments)) + " segment(s)) : " + status_name(self.status)
        if self.tag >= 0:
            t = t + " [tag " + str(self.tag) + "]"
        if self.error != "":
            t = t + " — " + self.error
        return t

class TagSet:
    used: list[bool] := []
    free_count: int := 0

    func init(n: int):
        self.used = [false for i in 0..n]
        self.free_count = n

    func size() -> int:
        return len(self.used)

    func allocate() -> int:
        i := 0
        while i < len(self.used):
            if not self.used[i]:
                self.used[i] = true
                self.free_count -= 1
                return i
            i += 1
        return -1

    func release(tag: int):
        if tag >= 0 and tag < len(self.used) and self.used[tag]:
            self.used[tag] = false
            self.free_count += 1

    func in_use() -> int:
        return len(self.used) - self.free_count

class RequestTracker:
    dev: BlockDevice
    tags: TagSet
    inflight: list[IoRequest] := []
    waiting: list[IoRequest] := []
    now: int := 0
    completed: int := 0
    failed: int := 0
    timeouts: int := 0
    retried: int := 0
    blocks_read: int := 0
    blocks_written: int := 0

    func init(dev: BlockDevice, depth: int):
        self.dev = dev
        self.tags = TagSet(depth)
        self.inflight = []
        self.waiting = []
        self.now = 0
        self.completed = 0
        self.failed = 0
        self.timeouts = 0
        self.retried = 0
        self.blocks_read = 0
        self.blocks_written = 0

    func _check(r: IoRequest):
        if r.op != FLUSH:
            if len(r.segments) == 0:
                raise("ArgumentError", "requête sans segment")
            bd.check_range(self.dev, r.lba, r.count())

    func _run(r: IoRequest) -> bool:
        if r.op == FLUSH:
            return self.dev.flush()
        lba := r.lba
        for s in r.segments:
            if r.op == READ:
                if not self.dev.read_blocks(lba, s.blocks, s.buf):
                    return false
                self.blocks_read += s.blocks
            else:
                if not self.dev.write_blocks(lba, s.blocks, s.buf):
                    return false
                self.blocks_written += s.blocks
            lba += s.blocks
        return true

    # Exécution immédiate avec nouvelles tentatives ; vrai si réussie.
    func execute(r: IoRequest) -> bool:
        self._check(r)
        r.status = INFLIGHT
        while true:
            r.attempts += 1
            ok := false
            try:
                ok = self._run(r)
                if not ok:
                    r.error = "le pilote a signalé un échec"
            catch e:
                ok = false
                r.error = e.type + " : " + e.message
                if e.type != "DeviceIoError" and e.type != "DeviceTimeout" and e.type != "MediaError":
                    r.attempts = r.retries + 1
            if ok:
                r.status = DONE
                r.error = ""
                self.completed += 1
                return true
            if r.attempts > r.retries:
                r.status = FAILED
                self.failed += 1
                return false
            self.retried += 1

    # Mode asynchrone : la requête reçoit une étiquette et attend complete(tag). Faute d'étiquette libre, elle
    # attend dans la file (triée par priorité). Renvoie l'étiquette ou -1.
    func start(r: IoRequest) -> int:
        self._check(r)
        t := self.tags.allocate()
        if t < 0:
            self._queue(r)
            return -1
        r.tag = t
        r.status = INFLIGHT
        r.started = self.now
        r.attempts += 1
        append(self.inflight, r)
        return t

    func _queue(r: IoRequest):
        keep: list[IoRequest] := []
        placed := false
        for w in self.waiting:
            if not placed and r.priority > w.priority:
                append(keep, r)
                placed = true
            append(keep, w)
        if not placed:
            append(keep, r)
        self.waiting = keep

    func _remove(tag: int) -> IoRequest?:
        found: IoRequest? := null
        keep: list[IoRequest] := []
        for r in self.inflight:
            if r.tag == tag and found == null:
                found = r
            else:
                append(keep, r)
        self.inflight = keep
        return found

    func _next():
        if len(self.waiting) > 0 and self.tags.free_count > 0:
            r := self.waiting[0]
            rest: list[IoRequest] := []
            i := 1
            while i < len(self.waiting):
                append(rest, self.waiting[i])
                i += 1
            self.waiting = rest
            self.start(r)

    # Fin signalée par le contrôleur pour l'étiquette tag.
    func complete(tag: int, ok: bool, error: str) -> IoRequest?:
        r := self._remove(tag)
        if r == null:
            return null
        self.tags.release(tag)
        if ok:
            r.status = DONE
            self.completed += 1
            if r.op == READ:
                self.blocks_read += r.count()
            elif r.op == WRITE:
                self.blocks_written += r.count()
        elif r.attempts <= r.retries:
            self.retried += 1
            r.error = error
            r.tag = -1
            self._queue(r)
        else:
            r.status = FAILED
            r.error = error
            self.failed += 1
        self._next()
        return r

    # Avance l'horloge ; les requêtes en vol depuis plus que leur délai échouent (TIMED_OUT). Renvoie le
    # nombre de requêtes expirées.
    func tick(n: int) -> int:
        self.now += n
        expired: list[IoRequest] := []
        for r in self.inflight:
            if r.timeout > 0 and self.now - r.started >= r.timeout:
                append(expired, r)
        for r in expired:
            self._remove(r.tag)
            self.tags.release(r.tag)
            r.status = TIMED_OUT
            r.error = "délai de " + str(r.timeout) + " ticks dépassé"
            self.timeouts += 1
        k := 0
        while k < len(expired):
            self._next()
            k += 1
        return len(expired)

    func pending() -> int:
        return len(self.inflight) + len(self.waiting)

    func report() -> str:
        return "terminées " + str(self.completed) + ", échouées " + str(self.failed) + ", délais " + str(self.timeouts) + ", nouvelles tentatives " + str(self.retried) + ", en vol " + str(len(self.inflight)) + ", en attente " + str(len(self.waiting)) + ", blocs lus " + str(self.blocks_read) + ", écrits " + str(self.blocks_written)
