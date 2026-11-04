# ALEX STANDARD LIBRARY — gc
#
# Observer et piloter le ramasse-miettes (mark-and-sweep, voir docs/RUNTIME.md §4). La VM collecte
# automatiquement entre deux instructions quand le nombre d'objets vivants atteint un seuil (doublé après
# chaque collecte) ; ce module sert à mesurer, forcer ou régler.
#
#   use gc
#   gc.collect()              # a lieu avant l'instruction suivante
#   print(gc.stats())         # {"live", "peak", "allocated", "freed", "collections", "threshold", "enabled"}
#
# Le déclenchement est basé sur le NOMBRE d'objets, pas sur leur taille en octets : un petit nombre de très gros
# objets peut retarder une collecte (appeler gc.collect() après en avoir libéré).
# La mémoire native (module memory) n'est pas gérée par ce ramasse-miettes.

use _native_gc as _g

func stats():
    return _g.stats()

# Demande une collecte immédiate (effective avant l'instruction suivante), même si le GC est désactivé.
func collect():
    return _g.collect()

# Active/désactive le déclenchement automatique ; retourne l'état précédent.
func enable(flag=true):
    return _g.enable(flag)

func disable():
    return _g.enable(false)

func is_enabled():
    return _g.stats()["enabled"]

# Seuil d'objets vivants déclenchant une collecte ; retourne l'ancien.
func set_threshold(n):
    return _g.set_threshold(n)

# Diagnostic : collecte toutes les n instructions (0 = off).
func set_stress(n):
    return _g.set_stress(n)
