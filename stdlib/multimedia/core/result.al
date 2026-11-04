# ALEX STANDARD LIBRARY — multimedia.core.result
#
# Résultat explicite (succès ou erreur) pour les opérations où l'échec est attendu et doit être traité sans
# exception : sondage d'un lot de fichiers, décodage tolérant, capacités optionnelles.
#
#   use multimedia.core.result as res
#   r := res.attempt(() => probe.probe("film.mkv"))
#   if r.ok:
#       print(r.value.describe())
#   else:
#       print(r.error_type, r.error_message)          # UnsupportedError ...
#   v := r.unwrap_or(null)
#   r.unwrap()                                        # relève l'erreur d'origine si r est un échec

from collections use append

class Result:
    func init(ok, value=null, error_type=null, error_message=null):
        self.ok = ok
        self.value = value
        self.error_type = error_type
        self.error_message = error_message

    func unwrap():
        if not self.ok:
            raise(self.error_type, self.error_message)
        return self.value

    func unwrap_or(default):
        if self.ok:
            return self.value
        return default

    func map(fn):
        if not self.ok:
            return self
        return attempt(() => fn(self.value))

    func describe():
        if self.ok:
            return "ok : " + str(self.value)
        return "erreur " + str(self.error_type) + " : " + str(self.error_message)

func ok(value=null):
    return Result(true, value)

func err(error_type, message):
    return Result(false, null, error_type, message)

# Exécute fn() et capture toute erreur dans un Result.
func attempt(fn):
    try:
        return Result(true, fn())
    catch e:
        return Result(false, null, e.type, e.message)

# Applique fn à chaque élément ; renvoie [succès, échecs] (listes de Result).
func partition(items, fn):
    good := []
    bad := []
    for it in items:
        r := attempt(() => fn(it))
        if r.ok:
            append(good, r)
        else:
            append(bad, r)
    return [good, bad]
