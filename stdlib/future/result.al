# ALEX STANDARD LIBRARY — future.result
#
# Result : le résultat d'une opération qui peut échouer, comme une VALEUR (au lieu d'une exception) — Ok(valeur)
# ou Err(type, message). Pratique pour collecter les issues de plusieurs opérations, ou les transmettre.
#
#   use future.result as res
#   r := res.capture(() => int_of(texte))           # Ok(42) ou Err("ValueError", "...")
#   if r.is_ok():
#       print(r.value)
#   n := r.unwrap_or(0)
#   r2 := r.map((v) => v * 2).and_then(verifier)    # enchaîne ; une erreur traverse sans rien exécuter
#   valeurs := res.collect([r1, r2, r3])            # Ok([...]) ou la première Err
#   r3 := await res.from_future(tache)              # issue d'un futur, sans exception
#
# Erreurs : unwrap / expect sur une Err relancent l'erreur d'origine (type et message) ; TypeError.

from core use type
from collections use append

class Result:
    func init(ok, value=null, error_type=null, message=null):
        self.ok = ok
        self.value = value
        self.error_type = error_type
        self.message = message

    func is_ok():
        return self.ok

    func is_err():
        return not self.ok

    # Valeur, ou relance l'erreur.
    func unwrap():
        if not self.ok:
            raise(self.error_type, self.message)
        return self.value

    # Valeur, ou erreur avec un message de contexte.
    func expect(context):
        if not self.ok:
            raise(self.error_type, context + " : " + self.message)
        return self.value

    func unwrap_or(default):
        if self.ok:
            return self.value
        return default

    # Valeur, ou fn(type, message).
    func unwrap_or_else(fn):
        if self.ok:
            return self.value
        return fn(self.error_type, self.message)

    # Ok(fn(valeur)) ; une Err reste telle quelle. Une exception de fn devient une Err.
    func map(fn):
        if not self.ok:
            return self
        return capture(() => fn(self.value))

    # Err(type, fn(message)) ; un Ok reste tel quel.
    func map_err(fn):
        if self.ok:
            return self
        return err(self.error_type, fn(self.message))

    # fn(valeur) doit renvoyer un Result (enchaînement d'opérations faillibles).
    func and_then(fn):
        if not self.ok:
            return self
        r := fn(self.value)
        if not isinstance(r, Result):
            raise("TypeError", "Result.and_then : la fonction doit renvoyer un Result")
        return r

    # Pour une Err : fn(type, message) doit renvoyer un Result (rattrapage).
    func or_else(fn):
        if self.ok:
            return self
        return fn(self.error_type, self.message)

    func to_dict():
        if self.ok:
            return {"ok": true, "value": self.value}
        return {"ok": false, "type": self.error_type, "message": self.message}

    func to_string():
        if self.ok:
            return "Ok(" + str(self.value) + ")"
        return "Err(" + str(self.error_type) + ": " + str(self.message) + ")"

func ok(value=null):
    return Result(true, value)

func err(error_type, message=""):
    return Result(false, null, error_type, message)

# Exécute fn() ; Ok(résultat) ou Err(type, message) si une exception est levée.
func capture(fn):
    try:
        return ok(fn())
    catch e:
        return err(e.type, e.message)

# Result à partir d'un dict produit par to_dict (par exemple reçu d'un autre fil ou processus).
func from_dict(d):
    if d["ok"]:
        return ok(d["value"])
    return err(d["type"], d["message"])

# Ok([valeurs...]) si tous sont Ok, sinon la première Err.
func collect(results):
    out := []
    for r in results:
        if not r.ok:
            return r
        append(out, r.value)
    return ok(out)

# Sépare : ([valeurs des Ok], [Err...]).
func partition(results):
    oks := []
    errs := []
    for r in results:
        if r.ok:
            append(oks, r.value)
        else:
            append(errs, r)
    return (oks, errs)

# Attend le futur et renvoie son issue comme Result (jamais d'exception, annulation : Err("CancelledError")).
async func from_future(f):
    try:
        return ok(await f)
    catch e:
        return err(e.type, e.message)
