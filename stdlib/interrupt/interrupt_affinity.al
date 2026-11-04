# alex: native
#
# ALEX STANDARD LIBRARY — interrupt.interrupt_affinity
#
# Affinité des interruptions : sur quels processeurs une interruption peut être livrée. CpuSet (ensemble de
# processeurs, notation « 0-3,6 » comme /proc/irq/*/smp_affinity_list, masque), table d'affinité par source
# (IRQ / GSI / vecteur MSI), RÉPARTITION des sources entre processeurs (tourniquet, ou équilibrage selon la
# charge mesurée), et application : APIC de destination d'une entrée d'IO-APIC ou d'un message MSI.
#
#   use interrupt.interrupt_affinity as ia
#   s := ia.parse("0-3,6")                      # CpuSet
#   print(s.format(), s.count(), s.first(), s.mask())     # 0-3,6 5 0 79
#   t := ia.AffinityTable(4)                    # 4 processeurs
#   t.set(14, ia.single(2))                     # IRQ 14 sur le processeur 2
#   t.spread([40, 41, 42, 43, 80, 81])          # tourniquet
#   t.balance({40: 900, 41: 10, 80: 500})       # selon les nombres d'interruptions observés
#   print(t.target(80), t.report())
#   ioapic.route(gsi, vecteur, t.target(gsi), false, false)   # destination = processeur choisi
#
# Les identifiants de processeur sont pris comme identifiants d'APIC (vrai sur QEMU et la plupart des
# machines ; sinon, fournir la correspondance avec set_apic_id).
# Module du sous-ensemble natif (noyau --freestanding ou VM).

from core use len
from collections use append, contains_key, keys
use interrupt.interrupt_vector as iv
use string as _s

class CpuSet:
    bits: int := 0

    func init(bits: int = 0):
        self.bits = bits

    func add(cpu: int) -> CpuSet:
        if cpu < 0 or cpu > 62:
            raise("InterruptError", "processeur " + str(cpu) + " hors de 0..62")
        self.bits = self.bits | (1 << cpu)
        return self

    func discard(cpu: int) -> CpuSet:
        self.bits = self.bits & ~(1 << cpu)
        return self

    func has(cpu: int) -> bool:
        return cpu >= 0 and cpu < 63 and ((self.bits >> cpu) & 1) != 0

    func count() -> int:
        n := 0
        b := self.bits
        while b != 0:
            n += b & 1
            b = b >> 1
        return n

    func is_empty() -> bool:
        return self.bits == 0

    func first() -> int:
        c := 0
        while c < 63:
            if self.has(c):
                return c
            c += 1
        return -1

    func cpus() -> list[int]:
        out: list[int] := []
        c := 0
        while c < 63:
            if self.has(c):
                append(out, c)
            c += 1
        return out

    func mask() -> int:
        return self.bits

    func union(o: CpuSet) -> CpuSet:
        return CpuSet(self.bits | o.bits)

    func intersection(o: CpuSet) -> CpuSet:
        return CpuSet(self.bits & o.bits)

    # « 0-3,6 »
    func format() -> str:
        out := ""
        c := 0
        while c < 63:
            if self.has(c):
                e := c
                while e + 1 < 63 and self.has(e + 1):
                    e += 1
                part := str(c)
                if e > c:
                    part = str(c) + "-" + str(e)
                if out == "":
                    out = part
                else:
                    out = out + "," + part
                c = e + 1
            else:
                c += 1
        return out

func single(cpu: int) -> CpuSet:
    return CpuSet(0).add(cpu)

func all_cpus(n: int) -> CpuSet:
    s := CpuSet(0)
    c := 0
    while c < n:
        s.add(c)
        c += 1
    return s

func _num(t: str) -> int:
    n := 0
    if len(t) == 0:
        raise("InterruptError", "liste de processeurs mal formée")
    for ch in t:
        if ch < '0' or ch > '9':
            raise("InterruptError", "liste de processeurs mal formée : « " + t + " »")
        n = n * 10 + (_s.ord(ch) - 48)
    return n

# « 0-3,6 » -> CpuSet.
func parse(text: str) -> CpuSet:
    s := CpuSet(0)
    part := ""
    for ch in text + ",":
        if ch == ',':
            if part != "":
                k := -1
                i := 0
                for c2 in part:
                    if c2 == '-':
                        k = i
                    i += 1
                if k < 0:
                    s.add(_num(part))
                else:
                    a := _num(_sub(part, 0, k))
                    b := _num(_sub(part, k + 1, len(part)))
                    while a <= b:
                        s.add(a)
                        a += 1
            part = ""
        elif ch != ' ':
            part = part + str(ch)
    return s

func _sub(t: str, a: int, b: int) -> str:
    out := ""
    i := 0
    for ch in t:
        if i >= a and i < b:
            out = out + str(ch)
        i += 1
    return out

class AffinityTable:
    cpus: int := 1
    table: dict[int, CpuSet] := {}
    apic_ids: dict[int, int] := {}
    next_cpu: int := 0

    func init(cpus: int):
        if cpus < 1:
            raise("InterruptError", "AffinityTable : au moins un processeur")
        self.cpus = cpus
        self.table = {}
        self.apic_ids = {}
        self.next_cpu = 0

    func set_apic_id(cpu: int, apic: int):
        self.apic_ids[cpu] = apic

    func apic_of(cpu: int) -> int:
        if contains_key(self.apic_ids, cpu):
            return self.apic_ids[cpu]
        return cpu

    func set(source: int, s: CpuSet):
        if s.is_empty():
            raise("InterruptError", "affinité vide pour la source " + str(source))
        if s.first() >= self.cpus:
            raise("InterruptError", "affinité hors des " + str(self.cpus) + " processeurs : " + s.format())
        self.table[source] = s

    func get(source: int) -> CpuSet:
        if contains_key(self.table, source):
            return self.table[source]
        return all_cpus(self.cpus)

    # Identifiant d'APIC de destination (premier processeur autorisé).
    func target(source: int) -> int:
        return self.apic_of(self.get(source).first())

    func msi_address(source: int) -> int:
        return iv.msi_address(self.target(source), false, false)

    # Tourniquet : chaque source sur le processeur suivant.
    func spread(sources: list[int]):
        for s in sources:
            self.table[s] = single(self.next_cpu % self.cpus)
            self.next_cpu += 1

    # Équilibrage glouton : sources triées par nombre décroissant, chacune sur le processeur le moins chargé.
    func balance(counts: dict[int, int]):
        srcs: list[int] := []
        for k in keys(counts):
            append(srcs, k)
        i := 1
        while i < len(srcs):
            v := srcs[i]
            j := i - 1
            while j >= 0 and counts[srcs[j]] < counts[v]:
                srcs[j + 1] = srcs[j]
                j -= 1
            srcs[j + 1] = v
            i += 1
        load: list[int] := []
        c := 0
        while c < self.cpus:
            append(load, 0)
            c += 1
        for s in srcs:
            best := 0
            c = 1
            while c < self.cpus:
                if load[c] < load[best]:
                    best = c
                c += 1
            load[best] = load[best] + counts[s]
            self.table[s] = single(best)

    func load_per_cpu(counts: dict[int, int]) -> list[int]:
        load: list[int] := []
        c := 0
        while c < self.cpus:
            append(load, 0)
            c += 1
        for s in keys(counts):
            cpu := self.get(s).first()
            if cpu >= 0 and cpu < self.cpus:
                load[cpu] = load[cpu] + counts[s]
        return load

    func report() -> str:
        out := "affinités (" + str(self.cpus) + " processeurs)"
        for s in keys(self.table):
            out = out + "\n  " + iv.describe(s) + " -> " + self.table[s].format()
        return out
