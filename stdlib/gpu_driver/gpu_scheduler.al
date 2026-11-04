# alex: native
# ALEX STANDARD LIBRARY — gpu_driver.gpu_scheduler
#
# Ordonnanceur du moteur 2D : plusieurs clients (contextes : bureau, application, console) soumettent des
# tampons de commandes (gpu_command.CommandBuffer) ; l'ordonnanceur les exécute sur le moteur (GpuEngine)
# chacun sur sa surface :
#   - priorités (temps réel > normal > fond) et tourniquet à priorité égale ;
#   - tranches de temps exprimées en COMMANDES : un tampon long est préempté entre deux commandes et repris
#     plus tard (personne n'accapare l'écran) ;
#   - barrières numérotées par contexte : fence(contexte) = dernière valeur atteinte, wait jusqu'à une valeur ;
#   - détection de blocage : un contexte qui dépasse hang_slices tranches sur la même soumission est déclaré
#     fautif, sa file est vidée (GpuHang journalisé) et les autres continuent ;
#   - statistiques par contexte (soumissions, commandes, tranches, préemptions).
#
#   use gpu_driver.gpu_scheduler as gs
#   sch := gs.GpuScheduler(64)                       # 64 commandes par tranche
#   bureau := sch.context("bureau", gs.PRIO_HIGH, ecran)
#   v := sch.submit(bureau, tampon)                  # numéro de barrière de cette soumission
#   sch.run(1000)                                    # au plus 1000 tranches
#   print(sch.fence(bureau) >= v, sch.report())
#
# Erreurs : GpuDriverError (contexte inconnu). Compilable en natif.

from core use len
from collections use append
use gpu_driver.gpu_command as gc
from gpu_driver.gpu_command use CommandBuffer, Surface2D, GpuEngine

const PRIO_LOW := 0
const PRIO_NORMAL := 1
const PRIO_HIGH := 2

class _Job:
    words: list[int] := []
    pos: int := 0
    fence: int := 0
    slices: int := 0

    func init(words: list[int], fence: int):
        self.words = words
        self.pos = 0
        self.fence = fence
        self.slices = 0

class GpuContext:
    name: str := ""
    priority: int := 1
    surface: Surface2D
    jobs: list[_Job] := []
    next_fence: int := 0
    done_fence: int := 0
    submissions: int := 0
    commands: int := 0
    slices: int := 0
    preemptions: int := 0
    guilty: bool := false
    hangs: int := 0

    func init(name: str, priority: int, surface: Surface2D):
        self.name = name
        self.priority = priority
        self.surface = surface
        self.jobs = []
        self.next_fence = 0
        self.done_fence = 0
        self.submissions = 0
        self.commands = 0
        self.slices = 0
        self.preemptions = 0
        self.guilty = false
        self.hangs = 0

    func idle() -> bool:
        return len(self.jobs) == 0

    func describe() -> str:
        t := self.name + " (prio " + str(self.priority) + ") : soumissions " + str(self.submissions) + ", commandes " + str(self.commands) + ", tranches " + str(self.slices) + ", préemptions " + str(self.preemptions) + ", barrière " + str(self.done_fence) + "/" + str(self.next_fence)
        if self.hangs > 0:
            t = t + ", blocages " + str(self.hangs)
        return t

class GpuScheduler:
    engine: GpuEngine
    slice: int := 64
    hang_slices: int := 1000
    contexts: list[GpuContext] := []
    turn: int := 0
    log: list[str] := []

    func init(slice: int):
        self.engine = GpuEngine()
        self.slice = slice if slice > 0 else 64
        self.hang_slices = 1000
        self.contexts = []
        self.turn = 0
        self.log = []

    func context(name: str, priority: int, surface: Surface2D) -> GpuContext:
        c := GpuContext(name, priority, surface)
        append(self.contexts, c)
        return c

    # Copie le tampon (le client peut le réutiliser) ; renvoie la valeur de barrière de la soumission.
    func submit(c: GpuContext, cb: CommandBuffer) -> int:
        c.next_fence += 1
        c.submissions += 1
        words: list[int] := []
        for w in cb.words:
            append(words, w)
        append(c.jobs, _Job(words, c.next_fence))
        if c.guilty:
            c.guilty = false
        return c.next_fence

    func fence(c: GpuContext) -> int:
        return c.done_fence

    func pending() -> int:
        n := 0
        for c in self.contexts:
            n += len(c.jobs)
        return n

    # Contexte suivant : plus haute priorité ayant du travail, tourniquet entre égaux.
    func _pick() -> GpuContext?:
        best := -1
        for c in self.contexts:
            if not c.idle() and c.priority > best:
                best = c.priority
        if best < 0:
            return null
        n := len(self.contexts)
        k := 0
        while k < n:
            i := (self.turn + k) % n
            c := self.contexts[i]
            if not c.idle() and c.priority == best:
                self.turn = (i + 1) % n
                return c
            k += 1
        return null

    # Exécute au plus slice commandes du travail en tête de c.
    func _run_slice(c: GpuContext):
        j := c.jobs[0]
        part := CommandBuffer()
        k := 0
        while k < self.slice and j.pos < len(j.words):
            nargs := j.words[j.pos + 1]
            i := 0
            while i < nargs + 2:
                append(part.words, j.words[j.pos + i])
                i += 1
            part.count += 1
            j.pos += nargs + 2
            k += 1
        self.engine.execute(part, c.surface)
        c.commands += k
        c.slices += 1
        j.slices += 1
        if j.pos >= len(j.words):
            c.done_fence = j.fence
            rest: list[_Job] := []
            i2 := 1
            while i2 < len(c.jobs):
                append(rest, c.jobs[i2])
                i2 += 1
            c.jobs = rest
        else:
            c.preemptions += 1
            if j.slices >= self.hang_slices:
                c.hangs += 1
                c.guilty = true
                last := c.jobs[len(c.jobs) - 1]
                c.done_fence = last.fence
                c.jobs = []
                append(self.log, "GpuHang : contexte « " + c.name + " » réinitialisé après " + str(j.slices) + " tranches")

    # Exécute jusqu'à max_slices tranches ; renvoie le nombre de tranches exécutées.
    func run(max_slices: int) -> int:
        n := 0
        while n < max_slices:
            c := self._pick()
            if c == null:
                break
            cc := c
            if cc != null:
                self._run_slice(cc)
            n += 1
        return n

    # Fait tourner jusqu'à ce que la barrière de c atteigne value (vrai) ou que tout soit fini (faux).
    func wait(c: GpuContext, value: int) -> bool:
        while c.done_fence < value:
            if self.run(1) == 0:
                return c.done_fence >= value
        return true

    func report() -> str:
        t := "moteur : " + str(self.engine.commands) + " commandes, " + str(self.engine.pixels) + " points"
        for c in self.contexts:
            t = t + "\n  " + c.describe()
        for l in self.log:
            t = t + "\n  " + l
        return t
