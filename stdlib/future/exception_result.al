# ALEX STANDARD LIBRARY — future.exception_result
#
# ExceptionResult : l'issue d'une opération avec, en cas d'échec, l'EXCEPTION COMPLÈTE (type, message, trace
# de pile, cause) — là où future.result.Result ne garde que type et message. Pour journaliser une erreur
# survenue ailleurs (autre tâche, autre fil), la relancer plus tard SANS perdre sa trace, ou l'envelopper
# dans une erreur de plus haut niveau en gardant la cause.
#
#   use future.exception_result as er
#   r := er.capture(charger, "config.toml")
#   if r.failed():
#       print(r.error_type, r.message)
#       print(r.trace_text())                   # trace de pile d'origine
#       r.rethrow()                             # relance l'exception d'origine (trace conservée)
#   v := r.value_or({})
#   w := r.wrap("ConfigError", "configuration illisible")   # nouvelle erreur, cause = l'originale
#   res := r.to_result()                        # future.result.Result
#   r2 := await er.capture_future(tache)        # issue d'un futur, sans exception
#
# Erreurs : InvalidStateError (value() sur un échec n'est pas une erreur : value() relance l'exception).

from core use len, type
from collections use append
use asyncio
use future.result as _res
use future.future_errors as _e

class ExceptionResult:
    func init(ok, value=null, exception=null, cause=null):
        self.ok = ok
        self.value_ = value
        self.exception = exception
        self.cause = cause
        self.error_type = null
        self.message = null
        if exception != null:
            self.error_type = exception.type
            self.message = exception.message

    func succeeded():
        return self.ok

    func failed():
        return not self.ok

    # Valeur, ou relance l'exception d'origine.
    func value():
        if not self.ok:
            raise(self.exception)
        return self.value_

    func value_or(default):
        if self.ok:
            return self.value_
        return default

    func rethrow():
        if not self.ok:
            raise(self.exception)

    # Trace de pile de l'exception (liste de lignes ; [] si inconnue).
    func trace():
        if self.ok or self.exception == null:
            return []
        try:
            t := self.exception.trace
            if type(t) == "list":
                return t
            if type(t) == "str":
                return [t]
        catch e:
            pass
        return []

    func trace_text():
        out := ""
        for l in self.trace():
            out += str(l) + "\n"
        return out

    # Nouvel échec de type error_type dont la cause est cette exception.
    func wrap(error_type, message):
        if self.ok:
            return self
        try:
            raise(error_type, message + " (cause : " + self.error_type + " : " + self.message + ")")
        catch e:
            return ExceptionResult(false, null, e, self)

    # Chaîne des causes, de la plus récente à l'originale.
    func causes():
        out := []
        c := self
        while c != null:
            if c.failed():
                append(out, [c.error_type, c.message])
            c = c.cause
        return out

    func root_cause():
        c := self
        while c.cause != null:
            c = c.cause
        return c

    func map(f):
        if not self.ok:
            return self
        return capture(f, self.value_)

    func to_result():
        if self.ok:
            return _res.ok(self.value_)
        return _res.err(self.error_type, self.message)

    func to_dict():
        return {"ok": self.ok, "value": self.value_, "error_type": self.error_type, "message": self.message,
                "trace": self.trace()}

    func __str__():
        if self.ok:
            return "ExceptionResult(ok, " + str(self.value_) + ")"
        return "ExceptionResult(" + self.error_type + " : " + self.message + ")"

func success(value=null):
    return ExceptionResult(true, value)

func from_exception(e, cause=null):
    return ExceptionResult(false, null, e, cause)

# Exécute fn(*args) et capture son issue.
func capture(fn, *args):
    try:
        return ExceptionResult(true, fn(*args))
    catch e:
        return ExceptionResult(false, null, e)

# Issue d'un futur ou d'une tâche (sans relancer).
async func capture_future(f):
    try:
        return ExceptionResult(true, await f)
    catch e:
        return ExceptionResult(false, null, e)

# Liste d'issues -> succès([valeurs]) ou le premier échec.
func collect(results):
    out := []
    for r in results:
        if r.failed():
            return r
        append(out, r.value_)
    return success(out)

# Exécute toutes les fonctions ; renvoie la liste des issues (aucune exception ne s'échappe).
func capture_all(fns):
    return [capture(f) for f in fns]
