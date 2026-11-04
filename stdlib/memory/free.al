# ALEX STANDARD LIBRARY — memory.free
#
# Libération de mémoire, et détection des erreurs classiques :
#
#   double free        MemoryError   (adresse brute ou bloc déjà libéré)
#   pointeur intérieur MemoryError   (on ne libère que le DÉBUT d'un bloc)
#   pointeur inconnu   MemoryError   (jamais alloué par raw())
#   genre incompatible ArgumentError (raw libéré par block_id, page par free, ...)
#   débordement        MemoryError   (canari écrasé, constaté à la libération)
#
# La mémoire libérée est remplie de 0xDD (<= 1 Mio) pour rendre les lectures après
# libération évidentes.
#
#   free.address(addr)      libère un bloc brut                  (unsafe)
#   free.block(id)          libère un bloc géré par identifiant
#   free.release(x)         int -> adresse brute ; objet -> x.free() (Buffer, Pointer, ...)
#   free.release_all(items) libère chacun, MÊME si l'un échoue ; relève la 1re erreur
#   FreeList / defer        pile de nettoyage en ordre inverse (LIFO), façon `defer`
#   free.scope(body)        exécute body(freelist) puis libère tout ce qui y a été enregistré
#
# Il n'y a pas de `finally` en ALEX : scope() et FreeList.run() sont le moyen sûr de
# garantir la libération même en cas d'exception.

from core use len, type
from collections use append, pop

use _native_memory as _m
use memory.unsafe as _u

# Libère le bloc brut débutant à `address`.
func address(address):
    _u.require("memory.free.address")
    if type(address) != "int":
        raise("TypeError", "memory.free.address() : adresse int attendue (obtenu '" + type(address) + "')")
    _m.raw_free(address)
    _u.note_free(address)
    return null

# Libère un bloc géré (par identifiant). Ses vues et Buffer deviennent invalides.
func block(block_id):
    if type(block_id) != "int":
        raise("TypeError", "memory.free.block() : identifiant int attendu (obtenu '" + type(block_id) + "')")
    _m.free(block_id)
    return null

# int : adresse brute (unsafe) ; sinon l'objet doit avoir une méthode free().
func release(target):
    if type(target) == "int":
        return address(target)
    return target.free()

# Libère tous les éléments ; continue après une erreur et relève la première à la fin.
func release_all(items):
    first := null
    for it in items:
        try:
            release(it)
        catch e:
            if first == null:
                first = e
    if first != null:
        raise(first.type, first.message)
    return null

# Pile de nettoyage LIFO. push(x) enregistre un objet à libérer (ou une fonction
# sans argument via defer(fn)) ; run() exécute/libère tout dans l'ordre inverse.
class FreeList:
    func init():
        self._items = []
        self._fns = []

    func push(target):
        append(self._items, target)
        append(self._fns, null)
        return target

    func defer(fn):
        append(self._items, null)
        append(self._fns, fn)
        return fn

    func count():
        return len(self._items)

    # Libère tout en ordre inverse ; relève la première erreur après avoir tout tenté.
    func run():
        first := null
        while len(self._items) > 0:
            item := pop(self._items)
            fn := pop(self._fns)
            try:
                if fn != null:
                    fn()
                else:
                    release(item)
            catch e:
                if first == null:
                    first = e
        if first != null:
            raise(first.type, first.message)
        return null

func freelist():
    return FreeList()

# body(freelist) puis libération garantie, y compris si body lève ; retourne body().
func scope(body):
    fl := FreeList()
    failure := null
    result := null
    try:
        result = body(fl)
    catch e:
        failure = e
    cleanup_error := null
    try:
        fl.run()
    catch e2:
        cleanup_error = e2
    if failure != null:
        raise(failure.type, failure.message)
    if cleanup_error != null:
        raise(cleanup_error.type, cleanup_error.message)
    return result

# Blocs bruts / mappés / externes encore vivants (hors blocs gérés, libérés par leurs
# Buffer) : liste de {id, kind, address, size, align, readonly, tag}. Vide = pas de fuite.
func leaks():
    out := []
    for b in _m.live(null):
        if b["kind"] != "managed":
            append(out, b)
    return out

# Texte lisible du rapport de fuites ("aucune fuite" si vide).
func leak_report():
    ls := leaks()
    if len(ls) == 0:
        return "aucune fuite"
    lines := [f"{len(ls)} région(s) non libérée(s) :"]
    for b in ls:
        label := b["tag"]
        if label == null:
            label = "-"
        ident := b["id"]
        kind := b["kind"]
        size := b["size"]
        addr := b["address"]
        append(lines, f"  #{ident} {kind} {size} octets @ {addr} [{label}]")
    out := ""
    first := true
    for l in lines:
        if first:
            out = l
            first = false
        else:
            out = out + "\n" + l
    return out
