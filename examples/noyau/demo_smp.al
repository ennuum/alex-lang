# Multiprocesseur (QEMU -smp 4) : démarrage des autres cœurs (ACPI, APIC), minuterie APIC propre à chaque
# cœur, mémoire partagée cohérente (opérations atomiques, verrou tournant).
#
# Le code Alex du noyau est sérialisé par le verrou global du noyau (un cœur à la fois : le ramasse-miettes et
# le runtime ne sont pas réentrants) ; le vrai parallélisme est celui des processus en anneau 3 (demo_multi).
# Ici, chaque cœur reste une unité d'exécution bien réelle : sa minuterie APIC l'interrompt indépendamment.
use hw
use tasks
use smp
from core use len

n := smp.start(1000) # 1000 interruptions de minuterie par seconde sur chaque cœur
print("cœurs en service :", n)
print("identifiants APIC distincts :", len(smp.apic_ids) == n)

# Attend, en rendant le verrou global (hw.wait), que la minuterie APIC de chaque cœur ait produit des tics :
# preuve que les n cœurs s'exécutent et s'interrompent indépendamment.
func all_ticked() -> bool:
    c := 0
    while c < n:
        if smp.ticks[c] == 0:
            return false
        c += 1
    return true

i := 0
while i < 1000 and not all_ticked():
    hw.wait()
    i += 1
print("chaque cœur reçoit les tics de sa minuterie APIC :", all_ticked())

# Mémoire partagée entre cœurs : compteur atomique et verrou tournant.
cell := hw.alloc_pages(1)
print(hw.cas(cell, 0, 5), hw.cas(cell, 0, 7), hw.peek64(cell)) # 0 (réussi), 5 (échec), 5
print(hw.atomic_add(cell, 3), hw.peek64(cell))                 # 5, 8
hw.spin_lock(cell + 8)
print("verrou tournant pris :", hw.peek64(cell + 8) == hw.cpu_id() + 1)
hw.spin_unlock(cell + 8)
hw.exit(0)
