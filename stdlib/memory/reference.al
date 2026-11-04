# ALEX STANDARD LIBRARY — memory.reference
#
# Références SÛRES : partager et emprunter des valeurs sans jamais pouvoir produire un
# accès invalide (niveau « gestion automatique » du modèle hybride).
#
#   Ref(v)             boîte partagée mutable : get set replace swap update take
#                      compare_and_set
#   Rc(v, on_drop)     propriété PARTAGÉE à comptage explicite : clone() / drop() ;
#                      on_drop(v) est appelée UNE fois quand le dernier propriétaire relâche.
#   Weak               référence faible issue de Rc.downgrade() ; upgrade() rend un
#                      propriétaire, ou null si la valeur a été relâchée (pas de cycle bloquant).
#   RefCell(v)         emprunts vérifiés À L'EXÉCUTION : N lecteurs OU 1 écrivain ;
#                      violation => BorrowError. with_borrow()/with_borrow_mut() relâchent
#                      toujours, même sur exception.
#   HandleTable        handles GÉNÉRATIONNELS (index, génération) : un handle périmé est
#                      détecté (StaleHandleError) au lieu de viser la valeur d'un autre.
#
# Les valeurs ALEX sont déjà des références gérées par la VM ; ces types ajoutent la
# SÉMANTIQUE explicite (qui possède, qui emprunte, qui a relâché).
#
# Erreurs : BorrowError, StaleHandleError, OwnershipError (usage d'un propriétaire déjà
#           relâché), ArgumentError.

from core use len, type
from collections use append, pop

# ---------------------------------------------------------------------
# Ref : boîte mutable partagée
# ---------------------------------------------------------------------

class Ref:
    func init(value=null):
        self._v = value

    func get():
        return self._v

    # Remplace la valeur ; retourne l'ancienne.
    func replace(value):
        old := self._v
        self._v = value
        return old

    func set(value):
        self._v = value
        return value

    # Échange les contenus de deux Ref.
    func swap(other):
        tmp := self._v
        self._v = other._v
        other._v = tmp
        return null

    # v = fn(v) ; retourne la nouvelle valeur.
    func update(fn):
        self._v = fn(self._v)
        return self._v

    # Retire la valeur (laisse `replacement`) et la retourne.
    func take(replacement=null):
        return self.replace(replacement)

    # Si la valeur == expected, la remplace et retourne true ; sinon false.
    func compare_and_set(expected, value):
        if self._v == expected:
            self._v = value
            return true
        return false

# ---------------------------------------------------------------------
# Rc / Weak : propriété partagée à comptage explicite
# ---------------------------------------------------------------------

# Bloc de contrôle partagé par tous les propriétaires d'une même valeur.
class _Control:
    func init(value, on_drop):
        self.value = value
        self.on_drop = on_drop
        self.strong = 1
        self.weak = 0
        self.alive = true

class Rc:
    func init(value=null, on_drop=null, control=null):
        if control != null:
            self._c = control
        else:
            self._c = _Control(value, on_drop)
        self._held = true

    func _need():
        if not self._held:
            raise("OwnershipError", "memory.reference.Rc : ce propriétaire a déjà été relâché (drop)")
        return self._c

    func get():
        return self._need().value

    # Nouveau propriétaire de la même valeur (compte + 1).
    func clone():
        c := self._need()
        c.strong = c.strong + 1
        return Rc(null, null, c)

    # Nombre de propriétaires vivants.
    func count():
        return self._need().strong

    func weak_count():
        return self._need().weak

    # Relâche ce propriétaire. Le dernier déclenche on_drop(valeur) et détruit la valeur.
    # Idempotent par propriétaire : retourne true si CET appel a relâché, false sinon.
    func drop():
        if not self._held:
            return false
        self._held = false
        c := self._c
        c.strong = c.strong - 1
        if c.strong == 0:
            c.alive = false
            v := c.value
            c.value = null
            if c.on_drop != null:
                c.on_drop(v)
        return true

    func is_held():
        return self._held

    # Référence faible (ne retient pas la valeur).
    func downgrade():
        c := self._need()
        c.weak = c.weak + 1
        return Weak(c)

    # Les deux propriétaires partagent-ils la même valeur ?
    func ptr_eq(other):
        return self._need() == other._need()

    # Si c'est le SEUL propriétaire : relâche et rend la valeur ; sinon null.
    func try_unwrap():
        c := self._need()
        if c.strong != 1:
            return null
        v := c.value
        self._held = false
        c.strong = 0
        c.alive = false
        c.value = null
        return v

class Weak:
    func init(control):
        self._c = control

    # Un propriétaire (clone) si la valeur vit encore, sinon null.
    func upgrade():
        c := self._c
        if not c.alive:
            return null
        c.strong = c.strong + 1
        return Rc(null, null, c)

    func alive():
        return self._c.alive

    func strong_count():
        if not self._c.alive:
            return 0
        return self._c.strong

# ---------------------------------------------------------------------
# RefCell : emprunts vérifiés à l'exécution
# ---------------------------------------------------------------------

class Borrow:
    func init(cell, mutable):
        self._cell = cell
        self._mut = mutable
        self._open = true

    func _need():
        if not self._open:
            raise("BorrowError", "memory.reference : emprunt déjà relâché")
        return self._cell

    func get():
        return self._need()._v

    # Écriture : emprunts MUTABLES seulement.
    func set(value):
        c := self._need()
        if not self._mut:
            raise("BorrowError", "memory.reference : écriture via un emprunt partagé (utiliser borrow_mut)")
        c._v = value
        return value

    func release():
        if self._open:
            self._open = false
            if self._mut:
                self._cell._writer = false
            else:
                self._cell._readers = self._cell._readers - 1
        return null

class RefCell:
    func init(value=null):
        self._v = value
        self._readers = 0
        self._writer = false

    # Emprunt partagé ; BorrowError si un emprunt mutable est actif.
    func borrow():
        if self._writer:
            raise("BorrowError", "memory.reference.RefCell : déjà emprunté en écriture")
        self._readers = self._readers + 1
        return Borrow(self, false)

    # Emprunt exclusif ; BorrowError si un autre emprunt (partagé ou mutable) est actif.
    func borrow_mut():
        if self._writer:
            raise("BorrowError", "memory.reference.RefCell : déjà emprunté en écriture")
        if self._readers > 0:
            raise("BorrowError", f"memory.reference.RefCell : {self._readers} emprunt(s) partagé(s) actif(s)")
        self._writer = true
        return Borrow(self, true)

    func is_borrowed():
        return self._writer or self._readers > 0

    func is_borrowed_mut():
        return self._writer

    # body(valeur) avec emprunt partagé, relâché quoi qu'il arrive.
    func with_borrow(body):
        b := self.borrow()
        failure := null
        result := null
        try:
            result = body(b.get())
        catch e:
            failure = e
        b.release()
        if failure != null:
            raise(failure.type, failure.message)
        return result

    # body(valeur) -> nouvelle valeur ; emprunt exclusif relâché quoi qu'il arrive.
    # Retourne la nouvelle valeur.
    func with_borrow_mut(body):
        b := self.borrow_mut()
        failure := null
        try:
            b.set(body(b.get()))
        catch e:
            failure = e
        result := b.get()
        b.release()
        if failure != null:
            raise(failure.type, failure.message)
        return result

# ---------------------------------------------------------------------
# HandleTable : handles générationnels
# ---------------------------------------------------------------------

class Handle:
    func init(index, generation):
        self.index = index
        self.generation = generation

    func eq(other):
        return self.index == other.index and self.generation == other.generation

class HandleTable:
    func init():
        self._values = []
        self._gens = []
        self._used = []
        self._free = []
        self._count = 0

    # Range la valeur ; retourne un Handle. Les emplacements libérés sont réutilisés avec
    # une génération incrémentée : les anciens handles de cet emplacement restent périmés.
    func insert(value):
        i := 0
        if len(self._free) > 0:
            i = pop(self._free)
            self._values[i] = value
            self._used[i] = true
        else:
            i = len(self._values)
            append(self._values, value)
            append(self._gens, 0)
            append(self._used, true)
        self._count = self._count + 1
        return Handle(i, self._gens[i])

    func _slot(handle, op):
        i := handle.index
        if i < 0 or i >= len(self._values) or not self._used[i] or self._gens[i] != handle.generation:
            raise("StaleHandleError", f"memory.reference.HandleTable.{op}() : handle périmé ou invalide (index {i}, génération {handle.generation})")
        return i

    func contains(handle):
        i := handle.index
        return i >= 0 and i < len(self._values) and self._used[i] and self._gens[i] == handle.generation

    func get(handle):
        return self._values[self._slot(handle, "get")]

    func set(handle, value):
        self._values[self._slot(handle, "set")] = value
        return value

    # Retire et retourne la valeur ; le handle (et ses copies) devient périmé.
    func remove(handle):
        i := self._slot(handle, "remove")
        v := self._values[i]
        self._values[i] = null
        self._used[i] = false
        self._gens[i] = self._gens[i] + 1
        append(self._free, i)
        self._count = self._count - 1
        return v

    func count():
        return self._count

# --- constructeurs pratiques ---------------------------------------------

func ref(value=null):
    return Ref(value)

func rc(value=null, on_drop=null):
    return Rc(value, on_drop)

func cell(value=null):
    return RefCell(value)

func table():
    return HandleTable()
