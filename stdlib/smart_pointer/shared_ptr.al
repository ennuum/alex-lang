# ALEX STANDARD LIBRARY — smart_pointer.shared_ptr
#
# SharedPtr : propriété PARTAGÉE à comptage de références (std::shared_ptr / Rc de Rust). Chaque copie
# (clone) est un propriétaire ; le suppresseur est appelé quand le DERNIER propriétaire relâche (drop ou
# reset). WeakPtr (smart_pointer.weak_ptr) observe sans posséder, pour casser les cycles.
#
#   use smart_pointer.shared_ptr as sp
#   a := sp.make_shared(Cache(), (c) => c.vider())
#   b := a.clone()
#   print(a.use_count())        # 2
#   a.drop()                    # b reste propriétaire
#   print(b.get().taille(), b.unique())   # … true
#   b.drop()                    # dernier : suppresseur appelé
#   print(sp.make_shared(1).ptr_eq(sp.make_shared(1)))   # false : deux valeurs distinctes
#
# Comme ALEX gère déjà la mémoire, SharedPtr sert à rendre EXPLICITE et DÉTERMINISTE la fin de vie d'une
# ressource partagée (fichier, connexion, tampon natif), au moment exact du dernier relâchement.
# Erreurs : NullPointerError, OwnershipError (après drop), DeleterError, TypeError.

from core use type
use smart_pointer.reference_count as _rc
use smart_pointer.smart_pointer_errors as _e

class SharedPtr:
    # Préférer make_shared(). control : bloc existant (usage interne : clone, WeakPtr.lock).
    func init(value=null, deleter=null, control=null):
        self._dropped = false
        if control != null:
            self._cb = control
            control.acquire()
        elif type(value) == "null":
            self._cb = null
        else:
            self._cb = _rc.ControlBlock(value, deleter)
            self._cb.acquire()

    func _alive(fn):
        if self._dropped:
            _e.moved("SharedPtr." + fn)

    func get():
        self._alive("get")
        if self._cb == null:
            _e.null_pointer("SharedPtr.get")
        return self._cb.value

    func get_or(default=null):
        self._alive("get_or")
        if self._cb == null:
            return default
        return self._cb.value

    func is_null():
        self._alive("is_null")
        return self._cb == null

    # Nouveau propriétaire de la même valeur.
    func clone():
        self._alive("clone")
        if self._cb == null:
            return SharedPtr()
        return SharedPtr(null, null, self._cb)

    # Nombre de propriétaires (0 pour un pointeur vide).
    func use_count():
        if self._dropped or self._cb == null:
            return 0
        return self._cb.strong

    func weak_count():
        if self._cb == null:
            return 0
        return self._cb.weak

    func unique():
        return self.use_count() == 1

    # Relâche cette propriété puis devient propriétaire de new_value (ou vide).
    func reset(new_value=null, deleter=null):
        self._alive("reset")
        old := self._cb
        self._cb = null
        if type(new_value) != "null":
            self._cb = _rc.ControlBlock(new_value, deleter)
            self._cb.acquire()
        if old != null:
            old.release()

    # Relâche ; le pointeur devient inutilisable. Idempotent.
    func drop():
        if self._dropped:
            return
        self._dropped = true
        cb := self._cb
        self._cb = null
        if cb != null:
            cb.release()

    func is_dropped():
        return self._dropped

    # Même valeur partagée (même bloc de contrôle) ?
    func ptr_eq(other):
        if self._cb == null or other._cb == null:
            return self._cb == null and other._cb == null
        return self._cb.id == other._cb.id

    # Ordre stable entre blocs de contrôle (clé de tri / de dict).
    func owner_id():
        if self._cb == null:
            return 0
        return self._cb.id

    func _control():
        return self._cb

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.drop()

    func __str__():
        if self._dropped:
            return "SharedPtr(<relâché>)"
        if self._cb == null:
            return "SharedPtr(null)"
        return "SharedPtr(" + str(self._cb.value) + ", " + str(self._cb.strong) + " propriétaire(s))"

func make_shared(value, deleter=null):
    if type(value) == "null":
        raise("ArgumentError", "make_shared : valeur null (utiliser SharedPtr() pour un pointeur vide)")
    return SharedPtr(value, deleter)

# body(ptr) avec un nouveau propriétaire ; relâché à la sortie, même sur erreur.
func with_shared(ptr, body):
    p := ptr.clone()
    try:
        return body(p)
    finally:
        p.drop()
