# ALEX STANDARD LIBRARY — smart_pointer.ownership
#
# Discipline de propriété et libération déterministe des ressources (RAII), en ALEX :
#   Owned(v)            valeur à propriétaire unique : take() la déplace (l'original devient inutilisable),
#                       borrow(f) la prête le temps d'un appel ; une utilisation après take() lève
#                       OwnershipError — utile pour documenter et vérifier qu'une ressource n'est consommée
#                       qu'une fois (jeton, transaction, message).
#   Disposable          interface : dispose()
#   using(res, body)    body(res) puis res.dispose(), même sur erreur (comme `with` / using de C#)
#   DisposeBag          accumule des ressources / fonctions de nettoyage et les libère toutes, en ordre
#                       INVERSE de leur ajout (comme les destructeurs C++), même si l'une échoue
#   Scope               DisposeBag lié à un bloc : scope(body) libère à la sortie
#
#   use smart_pointer.ownership as own
#   jeton := own.Owned(nouveau_jeton())
#   envoyer(jeton.take())          # déplacé
#   jeton.get()                    # OwnershipError
#   own.scope((s) => travail(s.add(ouvrir("a")), s.add(ouvrir("b"))))   # b puis a fermés à la sortie
#   bag := own.DisposeBag()
#   bag.defer(() => print("nettoyage"))
#   bag.dispose()
#
# Erreurs : OwnershipError, DisposeError (une ou plusieurs libérations ont échoué ; les autres ont eu lieu).

from core use len, type
from collections use append, pop
use _native_reflect as _r
use smart_pointer.smart_pointer_errors as _e

interface Disposable:
    func dispose()

class Owned:
    func init(value, name="valeur"):
        self._value = value
        self._owned = true
        self.name = name
        self._borrows = 0

    func _need(fn):
        if not self._owned:
            raise(_e.OWNERSHIP, "Owned." + fn + " : " + self.name + " a déjà été déplacée")

    func get():
        self._need("get")
        return self._value

    # Déplace la valeur hors de ce propriétaire.
    func take():
        self._need("take")
        if self._borrows > 0:
            raise(_e.OWNERSHIP, "Owned.take : " + self.name + " est empruntée")
        self._owned = false
        v := self._value
        self._value = null
        return v

    # Transfère dans un nouveau Owned.
    func move():
        return Owned(self.take(), self.name)

    # f(valeur) pendant que la valeur est empruntée (take() interdit pendant l'emprunt).
    func borrow(f):
        self._need("borrow")
        self._borrows += 1
        try:
            return f(self._value)
        finally:
            self._borrows -= 1

    func replace(value):
        self._need("replace")
        old := self._value
        self._value = value
        return old

    func is_owned():
        return self._owned

    func __str__():
        if self._owned:
            return "Owned(" + str(self._value) + ")"
        return "Owned(<déplacée>)"

func _dispose_one(item):
    if type(item) == "function":
        item()
        return
    m := _r.method(item, "dispose")
    if type(m) == "null":
        m = _r.method(item, "close")
    if type(m) == "null":
        m = _r.method(item, "free")
    if type(m) == "null":
        raise("TypeError", "ownership : '" + _r.display_name(_r.type_name(item)) + "' n'a ni dispose(), ni close(), ni free()")
    m()

# body(resource) puis libération de resource (dispose / close / free), même sur erreur.
func using(resource, body):
    try:
        return body(resource)
    finally:
        _dispose_one(resource)

class DisposeBag implements Disposable:
    func init():
        self._items = []
        self.disposed = false
        self.errors = []

    # Ajoute une ressource (dispose/close/free) ; la rend pour chaîner.
    func add(resource):
        if self.disposed:
            raise(_e.OWNERSHIP, "DisposeBag.add : sac déjà libéré")
        append(self._items, resource)
        return resource

    # Ajoute une fonction de nettoyage.
    func defer(f):
        if type(f) != "function":
            raise("TypeError", "DisposeBag.defer : fonction attendue")
        self.add(f)

    func size():
        return len(self._items)

    # Libère tout, du dernier ajouté au premier ; collecte les erreurs puis lève DisposeError s'il y en a.
    func dispose():
        if self.disposed:
            return
        self.disposed = true
        while len(self._items) > 0:
            it := pop(self._items)
            try:
                _dispose_one(it)
            catch e:
                append(self.errors, e.type + " : " + e.message)
        if len(self.errors) > 0:
            raise("DisposeError", "DisposeBag : " + str(len(self.errors)) + " libération(s) en échec : " + self.errors[0])

class Scope extends DisposeBag:
    func init():
        super.init()

# body(scope) ; tout ce qui a été ajouté au scope est libéré à la sortie.
func scope(body):
    s := Scope()
    failure := null
    result := null
    try:
        result = body(s)
    catch e:
        failure = e
    try:
        s.dispose()
    catch e2:
        if failure == null:
            failure = e2
    if failure != null:
        raise(failure)
    return result

func owned(value, name="valeur"):
    return Owned(value, name)
