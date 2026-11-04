# ALEX STANDARD LIBRARY — testing.mock
#
# Doublures de test :
#   Mock(return_value, side_effect)   objet APPELABLE qui enregistre ses appels ; renvoie return_value, ou une
#                                     valeur de la liste side_effect à chaque appel, ou appelle side_effect(*args)
#                                     si c'est une fonction ; raises=(type, message) le fait lever
#   spy(fn)                           enveloppe fn : l'appelle vraiment, en enregistrant les appels
#   patch(obj, nom, valeur, body)     remplace un champ (ou une méthode, par un champ du même nom) le temps de
#                                     body(), puis restaure ; patch_method : idem pour une méthode
#   Stub(méthodes)                    faux objet : {nom: valeur ou fonction}
#
#   use testing.mock as mk
#   m := mk.Mock(42)
#   print(m(1, 2))                               # 42
#   m.assert_called_with([1, 2])
#   m.assert_called_times(1)
#   envoi := mk.Mock(null, null, ["IoError", "réseau coupé"])
#   mk.patch(client, "envoyer", envoi, () => service.notifier())   # client.envoyer(...) lève IoError
#   s := mk.Stub({"solde": 100, "debiter": (n) => n > 0})
#   print(s.call("solde"), s.call("debiter", 5))
#
# Un champ d'instance a priorité sur une méthode de même nom : patch remplace donc obj.nom(...) par le mock.
# Erreurs : MockError (vérification non satisfaite), AttributeError.

from core use len, type
from collections use append
use _native_reflect as _r
use testing.testing_errors as _e

func _show(v):
    if type(v) == "str":
        return "\"" + v + "\""
    return str(v)

class Mock:
    func init(return_value=null, side_effect=null, raises=null, name="mock"):
        self.return_value = return_value
        self.side_effect = side_effect
        self.raises = raises
        self.name = name
        self.calls = []
        self._k = 0

    func __call__(*args):
        append(self.calls, [*args])
        if self.raises != null:
            raise(self.raises[0], self.raises[1])
        se := self.side_effect
        if se != null:
            if type(se) == "function":
                return se(*args)
            if type(se) == "list":
                if self._k >= len(se):
                    raise(_e.MOCK, self.name + " : side_effect épuisé (" + str(len(se)) + " valeurs)")
                v := se[self._k]
                self._k += 1
                return v
        return self.return_value

    func call_count():
        return len(self.calls)

    func called():
        return len(self.calls) > 0

    func last_call():
        if len(self.calls) == 0:
            return null
        return self.calls[len(self.calls) - 1]

    func reset():
        self.calls = []
        self._k = 0

    func assert_called(msg=null):
        if len(self.calls) == 0:
            raise(_e.MOCK, self.name + " : jamais appelé" + _suffix(msg))

    func assert_not_called(msg=null):
        if len(self.calls) > 0:
            raise(_e.MOCK, self.name + " : appelé " + str(len(self.calls)) + " fois (aucun appel attendu)" + _suffix(msg))

    func assert_called_times(n, msg=null):
        if len(self.calls) != n:
            raise(_e.MOCK, self.name + " : " + str(len(self.calls)) + " appel(s), " + str(n) + " attendu(s)" + _suffix(msg))

    # Dernier appel avec exactement ces arguments (liste).
    func assert_called_with(args, msg=null):
        self.assert_called(msg)
        last := self.last_call()
        if not (last == args):
            raise(_e.MOCK, self.name + " : dernier appel " + _show(last) + ", attendu " + _show(args) + _suffix(msg))

    # Un appel au moins avec ces arguments.
    func assert_any_call(args, msg=null):
        for c in self.calls:
            if c == args:
                return
        raise(_e.MOCK, self.name + " : aucun appel avec " + _show(args) + " (appels : " + _show(self.calls) + ")" + _suffix(msg))

    func assert_calls(expected, msg=null):
        if not (self.calls == expected):
            raise(_e.MOCK, self.name + " : appels " + _show(self.calls) + ", attendus " + _show(expected) + _suffix(msg))

func _suffix(msg):
    if msg == null:
        return ""
    return " — " + str(msg)

class Spy extends Mock:
    func init(fn, name="spy"):
        super.init(null, fn, null, name)

func mock(return_value=null, side_effect=null):
    return Mock(return_value, side_effect)

# Enveloppe une vraie fonction en l'espionnant.
func spy(fn, name="spy"):
    if type(fn) != "function":
        raise("TypeError", "spy : fonction attendue")
    return Spy(fn, name)

# body() avec obj.nom remplacé par valeur ; restauration garantie (même sur erreur).
func patch(obj, name, value, body):
    had := _r.has_field(obj, name)
    old := null
    if had:
        old = _r.get_field(obj, name)
    _r.set_field(obj, name, value)
    try:
        return body()
    finally:
        if had:
            _r.set_field(obj, name, old)
        else:
            _r.remove_field(obj, name)

# Remplace une MÉTHODE de obj (par un champ appelable du même nom), le temps de body().
func patch_method(obj, name, replacement, body):
    if _r.method(obj, name) == null:
        raise("AttributeError", "patch_method : '" + _r.display_name(_r.type_name(obj)) + "' n'a pas de méthode '" + name + "'")
    return patch(obj, name, replacement, body)

class Stub:
    func init(members=null):
        self.members = members
        if self.members == null:
            self.members = {}
        self.log = []

    func set(name, value):
        self.members[name] = value
        return self

    # Appelle la méthode simulée name (une valeur est simplement rendue).
    func call(name, *args):
        if not (name in self.members):
            raise("AttributeError", "Stub : membre '" + name + "' non défini")
        append(self.log, [name, [*args]])
        v := self.members[name]
        if type(v) == "function":
            return v(*args)
        return v

    func calls_to(name):
        return [c[1] for c in self.log if c[0] == name]
