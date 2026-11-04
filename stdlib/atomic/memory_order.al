# ALEX STANDARD LIBRARY — atomic.memory_order
#
# Ordres mémoire des opérations atomiques, comme std::memory_order (C++) : RELAXED, CONSUME, ACQUIRE,
# RELEASE, ACQ_REL, SEQ_CST. Les opérations natives d'ALEX sont TOUJOURS séquentiellement cohérentes
# (SEQ_CST) — le plus fort : tout ordre demandé est donc respecté. Ce module sert à DOCUMENTER l'intention
# dans le code, à valider qu'un ordre convient à une opération (comme le ferait un compilateur C++), et à
# raisonner sur la combinaison d'ordres.
#
#   use atomic.memory_order as mo
#   mo.check_load(mo.ACQUIRE)              # ok
#   mo.check_store(mo.ACQUIRE)             # MemoryOrderError : un store ne peut pas être « acquire »
#   print(mo.stronger(mo.ACQUIRE, mo.RELEASE))   # acq_rel
#   print(mo.is_at_least(mo.SEQ_CST, mo.ACQUIRE)) # true
#   mo.fence(mo.RELEASE)                   # barrière (effective : la VM est déjà seq_cst)
#   print(mo.effective(mo.RELAXED))        # seq_cst : ce qu'ALEX applique réellement
#
# Erreurs : MemoryOrderError (ordre inconnu ou interdit pour l'opération).

const ERROR := "MemoryOrderError"

const RELAXED := "relaxed"
const CONSUME := "consume"
const ACQUIRE := "acquire"
const RELEASE := "release"
const ACQ_REL := "acq_rel"
const SEQ_CST := "seq_cst"

const ALL := ["relaxed", "consume", "acquire", "release", "acq_rel", "seq_cst"]

_rank := {"relaxed": 0, "consume": 1, "acquire": 2, "release": 2, "acq_rel": 3, "seq_cst": 4}

_desc := {"relaxed": "atomicité seule, aucun ordre imposé aux autres accès",
          "consume": "ordre des accès DÉPENDANTS de la valeur lue (traité comme acquire)",
          "acquire": "aucun accès suivant ne remonte avant cette lecture",
          "release": "aucun accès précédent ne descend après cette écriture",
          "acq_rel": "acquire + release (lecture-modification-écriture)",
          "seq_cst": "ordre total unique de toutes les opérations seq_cst (le plus fort)"}

func is_valid(order):
    return order in _rank

func need(order, fn="memory_order"):
    if not is_valid(order):
        raise(ERROR, fn + " : ordre mémoire inconnu '" + str(order) + "' (relaxed, consume, acquire, release, acq_rel, seq_cst)")
    return order

func describe(order):
    need(order, "memory_order.describe")
    return _desc[order]

# Ordres permis pour une lecture : tous sauf release et acq_rel.
func check_load(order):
    need(order, "check_load")
    if order == RELEASE or order == ACQ_REL:
        raise(ERROR, "check_load : une lecture ne peut pas être « " + order + " »")
    return order

# Ordres permis pour une écriture : relaxed, release, seq_cst.
func check_store(order):
    need(order, "check_store")
    if order == ACQUIRE or order == CONSUME or order == ACQ_REL:
        raise(ERROR, "check_store : une écriture ne peut pas être « " + order + " »")
    return order

# Lecture-modification-écriture (exchange, fetch_add...) : tous permis.
func check_rmw(order):
    return need(order, "check_rmw")

# compare_exchange : l'ordre d'échec ne peut être ni release ni acq_rel, ni plus fort que celui de succès.
func check_compare_exchange(success, failure):
    need(success, "check_compare_exchange")
    check_load(failure)
    if _rank[failure] > _rank[success] and not (success == ACQ_REL and failure == ACQUIRE):
        raise(ERROR, "check_compare_exchange : ordre d'échec « " + failure + " » plus fort que celui de succès « " + success + " »")
    return [success, failure]

# Ordre d'échec par défaut d'un compare_exchange (comme C++ : release -> relaxed, acq_rel -> acquire).
func failure_order(success):
    need(success, "failure_order")
    if success == RELEASE:
        return RELAXED
    if success == ACQ_REL:
        return ACQUIRE
    return success

func is_at_least(order, minimum):
    need(order, "is_at_least")
    need(minimum, "is_at_least")
    if order == SEQ_CST:
        return true
    if minimum == ACQUIRE or minimum == CONSUME:
        return order == ACQUIRE or order == ACQ_REL or (minimum == CONSUME and order == CONSUME)
    if minimum == RELEASE:
        return order == RELEASE or order == ACQ_REL
    return _rank[order] >= _rank[minimum]

# Plus petit ordre au moins aussi fort que a et b.
func stronger(a, b):
    need(a, "stronger")
    need(b, "stronger")
    if a == b:
        return a
    if a == SEQ_CST or b == SEQ_CST:
        return SEQ_CST
    if (a == ACQUIRE and b == RELEASE) or (a == RELEASE and b == ACQUIRE):
        return ACQ_REL
    if _rank[a] >= _rank[b]:
        if a == CONSUME and b == RELEASE:
            return ACQ_REL
        return a
    if b == CONSUME and a == RELEASE:
        return ACQ_REL
    return b

# Ordre réellement appliqué par les opérations natives d'ALEX.
func effective(order):
    need(order, "effective")
    return SEQ_CST

_fences := [0]

# Barrière mémoire : sans effet supplémentaire (les opérations natives sont seq_cst), comptée pour le
# diagnostic.
func fence(order=SEQ_CST):
    need(order, "fence")
    if order == RELAXED:
        raise(ERROR, "fence : une barrière « relaxed » n'a pas de sens")
    _fences[0] += 1

func fence_count():
    return _fences[0]
