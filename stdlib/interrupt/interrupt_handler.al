# alex: native
# ALEX STANDARD LIBRARY — interrupt.interrupt_handler
#
# Gestionnaires d'interruption :
#   - InterruptHandler (interface) : handle(irq) -> bool, vrai si LE périphérique du gestionnaire a levé
#     l'interruption (lignes partagées : PCI INTx, IO-APIC en niveau) ;
#   - FunctionHandler : une fonction Alex comme gestionnaire ;
#   - HandlerChain : les gestionnaires d'une même ligne, appelés à tour de rôle, avec compteurs (traitées,
#     non revendiquées) ;
#   - Deferred : travail différé (« moitié basse ») : le gestionnaire note la ligne dans un anneau sans allouer,
#     une tâche ou la boucle principale traite ensuite (drain), interruptions de nouveau permises.
#
#   use interrupt.interrupt_handler as ih
#   h := ih.FunctionHandler("clavier", (irq) => clavier.lire_octet())
#   chain := ih.HandlerChain(1, 33)
#   chain.add(h)
#   chain.dispatch(1)
#
# Un gestionnaire s'exécute interruptions masquées : il doit être court (lire un registre, acquitter le
# périphérique, noter le travail) ; le reste se fait hors interruption (Deferred).
#
# Compilable en natif (# alex: native).

from collections use append
from core use len

interface InterruptHandler:
    func handle(irq: int) -> bool
    func name() -> str

class FunctionHandler implements InterruptHandler:
    label: str := ""
    fn: func(int) -> bool

    func init(label: str, fn: func(int) -> bool):
        self.label = label
        self.fn = fn

    func handle(irq: int) -> bool:
        f := self.fn
        return f(irq)

    func name() -> str:
        return self.label

# Gestionnaire qui revendique toujours l'interruption (ligne non partagée).
class SimpleHandler implements InterruptHandler:
    label: str := ""
    fn: func(int)

    func init(label: str, fn: func(int)):
        self.label = label
        self.fn = fn

    func handle(irq: int) -> bool:
        f := self.fn
        f(irq)
        return true

    func name() -> str:
        return self.label

class HandlerChain:
    irq: int := 0
    vector: int := 0
    handlers: list[InterruptHandler] := []
    count: int := 0          # interruptions reçues sur la ligne
    handled: int := 0        # revendiquées par au moins un gestionnaire
    unhandled: int := 0      # personne ne les a revendiquées
    spurious: int := 0       # parasites (PIC)
    shared: bool := true     # appeler tous les gestionnaires (ligne partagée) ou s'arrêter au premier qui revendique

    func init(irq: int, vector: int):
        self.irq = irq
        self.vector = vector
        self.handlers = []
        self.count = 0
        self.handled = 0
        self.unhandled = 0
        self.spurious = 0
        self.shared = true

    func add(h: InterruptHandler):
        append(self.handlers, h)

    # Retire le gestionnaire de ce nom ; renvoie vrai s'il y était.
    func remove(label: str) -> bool:
        keep: list[InterruptHandler] := []
        found := false
        for h in self.handlers:
            if h.name() == label:
                found = true
            else:
                append(keep, h)
        self.handlers = keep
        return found

    func size() -> int:
        return len(self.handlers)

    func names() -> list[str]:
        out: list[str] := []
        for h in self.handlers:
            append(out, h.name())
        return out

    func dispatch(irq: int) -> bool:
        self.count += 1
        any := false
        for h in self.handlers:
            if h.handle(irq):
                any = true
                if not self.shared:
                    break
        if any:
            self.handled += 1
        else:
            self.unhandled += 1
        return any

    func describe() -> str:
        t := "IRQ " + str(self.irq) + " (vecteur " + str(self.vector) + ") : " + str(self.count) + " reçues, " + str(self.unhandled) + " non revendiquées"
        if self.spurious > 0:
            t = t + ", " + str(self.spurious) + " parasites"
        return t

# Anneau de travail différé : post(n) depuis le gestionnaire (aucune allocation), drain(fn) ailleurs.
class Deferred:
    ring: list[int] := []
    head: int := 0
    tail: int := 0
    capacity: int := 0
    dropped: int := 0
    posted: int := 0

    func init(capacity: int):
        self.ring = [0 for i in 0..capacity]
        self.capacity = capacity
        self.head = 0
        self.tail = 0
        self.dropped = 0
        self.posted = 0

    func pending() -> int:
        return self.tail - self.head

    # Note n ; faux (et compté dans dropped) si l'anneau est plein.
    func post(n: int) -> bool:
        if self.tail - self.head >= self.capacity:
            self.dropped += 1
            return false
        self.ring[self.tail % self.capacity] = n
        self.tail += 1
        self.posted += 1
        return true

    # Retire la plus ancienne valeur (-1 si vide). À appeler interruptions masquées si post peut survenir.
    func take() -> int:
        if self.head == self.tail:
            return -1
        v := self.ring[self.head % self.capacity]
        self.head += 1
        return v

    # Traite tout ce qui est en attente ; renvoie le nombre de valeurs traitées.
    func drain(fn: func(int)) -> int:
        n := 0
        while self.head != self.tail:
            v := self.ring[self.head % self.capacity]
            self.head += 1
            fn(v)
            n += 1
        return n
