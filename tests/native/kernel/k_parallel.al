# Noyau parallèle (docs Alex OS NOYAU_PARALLELE.md, P1) : sans verrou global, 8 tâches s'exécutent sur 4 cœurs EN
# MÊME TEMPS ; chacune alloue beaucoup (listes, chaînes, dictionnaires : plusieurs ramasse-miettes avec arrêt des
# autres cœurs), lève et rattrape des exceptions (chaîne des try propre à chaque cœur) et cède la main. Les
# résultats doivent être exactement ceux d'un calcul séquentiel.
use hw
use tasks
use examples.noyau.smp as smp
from core use len
from collections use append

const WORKERS := 8
const ROUNDS := 40

results: list[int] := [0, 0, 0, 0, 0, 0, 0, 0]
cores: list[int] := [0, 0, 0, 0, 0, 0, 0, 0]
done := 0
cell := hw.alloc_pages(1) # verrou tournant du compteur « done »

func work(k: int) -> int:
    total := 0
    r := 0
    while r < ROUNDS:
        l: list[int] := []
        i := 0
        while i < 2000:
            append(l, i * k + r)
            i += 1
        s := ""
        i = 0
        while i < 20:
            s = s + str(i + k)
            i += 1
        d: dict[int, str] := {}
        i = 0
        while i < 20:
            d[i] = s
            i += 1
        try:
            if r % 7 == k % 7:
                raise("ValueError", "tour " + str(r))
            total += l[1999] + len(d[19])
        catch e:
            total += 1
        r += 1
    return total

func job(k: int):
    seen := 0
    total := 0
    r := 0
    while r < 4:
        total += work(k)
        seen = seen | (1 << hw.cpu_id())
        tasks.yield_now()
        r += 1
    results[k] = total
    cores[k] = seen
    hw.spin_lock(cell)
    done += 1
    hw.spin_unlock(cell)

func starter(k: int) -> func():
    func go():
        job(k)
    return go

expected: list[int] := []
for k in 0..WORKERS:
    append(expected, 4 * work(k))

n := smp.start(1000)
print("cœurs en service :", n)
hw.smp_parallel(true)
print("mode parallèle :", hw.parallel())
gc_before := hw.gc_count()
for k in 0..WORKERS:
    tasks.spawn(starter(k))
while done < WORKERS:
    tasks.yield_now()
ok := true
mask := 0
for k in 0..WORKERS:
    if results[k] != expected[k]:
        ok = false
    mask = mask | cores[k]
used := 0
c := 0
while c < 16:
    if (mask & (1 << c)) != 0:
        used += 1
    c += 1
print("résultats corrects :", ok)
print("travail réparti sur plusieurs cœurs :", used >= 2)
print("ramasse-miettes pendant le travail parallèle :", hw.gc_count() > gc_before)
hw.exit(0)
