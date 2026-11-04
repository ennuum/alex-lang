# ALEX STANDARD LIBRARY — smart_pointer.unique_ptr
#
# UniquePtr : propriété EXCLUSIVE d'une valeur (std::unique_ptr / Box de Rust). Un seul propriétaire ; la
# propriété se transfère par move() (l'ancien pointeur devient inutilisable) ; le suppresseur (deleter) est
# appelé à la destruction : reset(), drop(), ou fin de with_unique().
#
#   use smart_pointer.unique_ptr as up
#   p := up.make_unique(ouvrir("log.txt"), (f) => f.close())
#   p.get().write("…")
#   q := p.move()            # q possède le fichier
#   p.get()                  # OwnershipError : p a été déplacé
#   q.reset()                # ferme le fichier ; q est vide
#   up.with_unique(Connexion(), (c) => c.fermer(), (ptr) => ptr.get().envoyer("x"))
#   v := up.make_unique(5).release()     # rend la valeur SANS appeler le suppresseur
#
# Erreurs : NullPointerError (get sur vide), OwnershipError (après move/drop), DeleterError, TypeError.

from core use type
use smart_pointer.smart_pointer_errors as _e

class UniquePtr:
    func init(value=null, deleter=null):
        _e.need_deleter("UniquePtr", deleter)
        self._value = value
        self._has = type(value) != "null"
        self._deleter = deleter
        self._moved = false

    func _alive(fn):
        if self._moved:
            _e.moved("UniquePtr." + fn)

    func get():
        self._alive("get")
        if not self._has:
            _e.null_pointer("UniquePtr.get")
        return self._value

    # Valeur ou default (pointeur vide), sans erreur.
    func get_or(default=null):
        self._alive("get_or")
        if not self._has:
            return default
        return self._value

    func is_null():
        self._alive("is_null")
        return not self._has

    func has_value():
        return not self._moved and self._has

    func is_moved():
        return self._moved

    # Transfère la propriété vers un NOUVEAU UniquePtr ; celui-ci devient inutilisable.
    func move():
        self._alive("move")
        p := UniquePtr(null, self._deleter)
        p._value = self._value
        p._has = self._has
        self._value = null
        self._has = false
        self._moved = true
        return p

    # Abandonne la propriété : rend la valeur sans appeler le suppresseur ; le pointeur devient vide.
    func release():
        self._alive("release")
        v := self._value
        self._value = null
        self._has = false
        return v

    # Détruit la valeur actuelle (suppresseur) et prend new_value (null : reste vide).
    func reset(new_value=null):
        self._alive("reset")
        old := self._value
        had := self._has
        self._value = new_value
        self._has = type(new_value) != "null"
        if had and self._deleter != null:
            try:
                self._deleter(old)
            catch e:
                raise(_e.DELETER, "UniquePtr : suppresseur : " + e.type + " : " + e.message)

    # Détruit la valeur ; le pointeur devient inutilisable.
    func drop():
        if self._moved:
            return
        self.reset()
        self._moved = true

    func swap(other):
        self._alive("swap")
        other._alive("swap")
        v := self._value
        h := self._has
        d := self._deleter
        self._value = other._value
        self._has = other._has
        self._deleter = other._deleter
        other._value = v
        other._has = h
        other._deleter = d

    func deleter():
        return self._deleter

    # Transforme la valeur possédée en place : f(valeur) -> nouvelle valeur (sans suppresseur).
    func map_in_place(f):
        self._value = f(self.get())

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.drop()

    func __str__():
        if self._moved:
            return "UniquePtr(<déplacé>)"
        if not self._has:
            return "UniquePtr(null)"
        return "UniquePtr(" + str(self._value) + ")"

func make_unique(value, deleter=null):
    return UniquePtr(value, deleter)

# body(ptr) ; la valeur est détruite (suppresseur) à la sortie, même sur erreur — sauf si body l'a
# déplacée ou relâchée.
func with_unique(value, deleter, body):
    p := UniquePtr(value, deleter)
    try:
        return body(p)
    finally:
        p.drop()
