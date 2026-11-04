# ALEX STANDARD LIBRARY — multimedia.pipeline.recovery
#
# Que faire quand un nœud échoue sur un élément :
#   « fail »   arrêter le pipeline (PipelineError qui cite le nœud et l'erreur d'origine) — défaut ;
#   « skip »   jeter l'élément fautif et continuer (fichiers partiellement corrompus, flux en direct) ;
#   « retry »  réessayer jusqu'à `retries` fois, puis appliquer `then` (« skip » ou « fail »).
# Toujours fatales, quelle que soit la politique : CancelledError et LimitError (on ne contourne pas une limite).
#
#   use multimedia.pipeline.recovery as rec
#   p := rec.Recovery("retry", 2, "skip")
#   p.on_error = (nom, erreur_type, message) => journal.append(nom + " : " + message)
#   g.set_recovery("decodeur", p)

from collections use append
use multimedia.core.errors as merr

const MODES := ["fail", "skip", "retry"]
const ALWAYS_FATAL := ["CancelledError", "LimitError"]

class Recovery:
    func init(mode="fail", retries=0, then="fail"):
        if not (mode in MODES):
            merr.fail(merr.FORMAT, "politique de reprise inconnue : " + str(mode))
        if then != "fail" and then != "skip":
            merr.fail(merr.FORMAT, "après les essais : « skip » ou « fail »")
        self.mode = mode
        self.retries = retries
        self.then = then
        self.on_error = null
        self.errors = []
        self.skipped = 0
        self.retried = 0

    # Applique fn(item) selon la politique ; renvoie [ok, résultat].
    func run(node_name, fn, item):
        attempts := 0
        while true:
            try:
                return [true, fn(item)]
            catch e:
                if e.type in ALWAYS_FATAL:
                    raise(e.type, e.message)
                append(self.errors, [node_name, e.type, e.message])
                if self.on_error != null:
                    self.on_error(node_name, e.type, e.message)
                mode := self.mode
                if mode == "retry":
                    if attempts < self.retries:
                        attempts += 1
                        self.retried += 1
                        continue
                    mode = self.then
                if mode == "skip":
                    self.skipped += 1
                    return [false, null]
                merr.fail(merr.PIPELINE, "nœud « " + node_name + " » : " + e.type + " : " + e.message)

func fail():
    return Recovery("fail")

func skip():
    return Recovery("skip")

func retry(n, then="skip"):
    return Recovery("retry", n, then)
