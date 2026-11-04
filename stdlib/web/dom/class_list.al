# ALEX STANDARD LIBRARY — web.dom.class_list
#
# DOMTokenList : liste de jetons d'un attribut (element.class_list pour « class », rel_list pour « rel »…) —
# ajout, retrait, bascule (avec forçage), remplacement, test, sans doublons et en gardant l'ordre ; chaque
# modification réécrit l'attribut (et notifie donc les MutationObserver).
#
#   cl := element.class_list
#   cl.add(["carte", "active"])        # plusieurs jetons
#   cl.toggle("ouvert")                # true (ajouté)
#   cl.toggle("ouvert", true)          # true (forcé, reste présent)
#   cl.contains("active")              # true
#   cl.replace("active", "inactive")   # true
#   cl.value()                         # carte inactive ouvert
#   len(cl), cl.item(0), cl[1]
#
# Erreurs : SyntaxError (jeton vide), InvalidCharacterError (jeton contenant un espace).

from core use len, type
from collections use append
use string as _s
use web.dom.dom_errors as _err

func _is_ws(c):
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or _s.ord(c) == 12

# Jetons d'une valeur (séparés par des blancs, doublons retirés).
func tokens(value):
    out := []
    if value == null:
        return out
    cur := []
    for c in str(value) + " ":
        if _is_ws(c):
            if len(cur) > 0:
                t := _s.join("", cur)
                if not (t in out):
                    append(out, t)
                cur = []
        else:
            append(cur, str(c))
    return out

func _check(token, fn):
    if token == "":
        _err.syntax(fn, "jeton vide")
    for c in token:
        if _is_ws(c):
            _err.invalid_character(fn, "jeton contenant un blanc « " + token + " »")

class DOMTokenList:
    # supported : jetons permis (rel, sandbox…) pour supports(), ou null.
    func init(element, attribute="class", supported=null):
        self.element = element
        self.attribute = attribute
        self.supported = supported

    func _get():
        return tokens(self.element.get_attribute(self.attribute))

    func _set(items):
        self.element.set_attribute(self.attribute, _s.join(" ", items))

    func value():
        v := self.element.get_attribute(self.attribute)
        return v if v != null else ""

    func set_value(v):
        self.element.set_attribute(self.attribute, str(v))

    func length():
        return len(self._get())

    func __len__():
        return self.length()

    func item(i):
        l := self._get()
        if i < 0 or i >= len(l):
            return null
        return l[i]

    func __getitem__(i):
        return self._get()[i]

    func contains(token):
        return token in self._get()

    func __contains__(token):
        return self.contains(token)

    func add(items):
        lst := items if type(items) == "list" else [items]
        cur := self._get()
        for t in lst:
            _check(t, "DOMTokenList.add")
            if not (t in cur):
                append(cur, t)
        self._set(cur)
        return self

    func remove(items):
        lst := items if type(items) == "list" else [items]
        for t in lst:
            _check(t, "DOMTokenList.remove")
        if self.element.get_attribute(self.attribute) == null:
            return self
        kept := []
        for t in self._get():
            if not (t in lst):
                append(kept, t)
        self._set(kept)
        return self

    # Bascule ; force : true (ajout) / false (retrait) / null. Renvoie la présence finale.
    func toggle(token, force=null):
        _check(token, "DOMTokenList.toggle")
        present := self.contains(token)
        if present and force != true:
            self.remove(token)
            return false
        if not present and force != false:
            self.add(token)
            return true
        return present

    func replace(old, new_token):
        _check(old, "DOMTokenList.replace")
        _check(new_token, "DOMTokenList.replace")
        cur := self._get()
        if not (old in cur):
            return false
        out := []
        for t in cur:
            if t == old:
                if not (new_token in out):
                    append(out, new_token)
            elif t != new_token or not (new_token in out):
                if not (t in out):
                    append(out, t)
        self._set(out)
        return true

    func supports(token):
        if self.supported == null:
            _err.fail("TypeError", "DOMTokenList.supports", "l'attribut « " + self.attribute + " » n'a pas de jetons définis")
        return _s.lower(token) in self.supported

    func to_list():
        return self._get()

    func __str__():
        return self.value()
