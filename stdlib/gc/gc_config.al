# ALEX STANDARD LIBRARY — gc.gc_config
#
# Réglages du ramasse-miettes sous forme d'objet : lire la configuration courante, en appliquer une autre,
# l'appliquer le temps d'un appel puis restaurer la précédente, et préréglages nommés.
#
#   use gc.gc_config as gcc
#   print(gcc.current())                              # GcConfig(enabled=true, threshold=..., stress=0)
#   gcc.preset("throughput").apply()                  # moins de collectes (seuil élevé)
#   gcc.with_config(gcc.GcConfig(false), calcul)      # GC automatique coupé pendant calcul(), puis restauré
#   gcc.with_config(gcc.preset("debug"), test)        # collecte toutes les 64 instructions (traque des racines)
#
# Préréglages : "default" (seuil 1024), "throughput" (seuil 65536), "low_latency" (seuil 256 : collectes
# fréquentes et courtes), "memory" (seuil 128), "debug" (stress 64), "off" (déclenchement automatique coupé).
# Le seuil est un NOMBRE D'OBJETS vivants ; la VM le double après chaque collecte.
#
# Erreurs : GcConfigError, TypeError.

from core use type
use _native_gc as _g
use gc.gc_errors as _e

# Valeurs connues uniquement de ce module (la VM n'expose pas l'intervalle de stress).
_stress := [0]

class GcConfig:
    func init(enabled=true, threshold=null, stress=0):
        if type(enabled) != "bool":
            raise("TypeError", "GcConfig : enabled doit être un bool")
        if threshold != null:
            _e.need_int("GcConfig", threshold, "le seuil", 1)
        _e.need_int("GcConfig", stress, "l'intervalle de stress", 0)
        self.enabled = enabled
        self.threshold = threshold
        self.stress = stress

    # Applique ; renvoie la configuration précédente.
    func apply():
        before := current()
        _g.enable(self.enabled)
        if self.threshold != null:
            _g.set_threshold(self.threshold)
        _g.set_stress(self.stress)
        _stress[0] = self.stress
        return before

    func with_threshold(n):
        return GcConfig(self.enabled, n, self.stress)

    func with_enabled(flag):
        return GcConfig(flag, self.threshold, self.stress)

    func with_stress(n):
        return GcConfig(self.enabled, self.threshold, n)

    func to_dict():
        return {"enabled": self.enabled, "threshold": self.threshold, "stress": self.stress}

    func __eq__(other):
        return isinstance(other, GcConfig) and other.enabled == self.enabled and other.threshold == self.threshold and other.stress == self.stress

    func __str__():
        return "GcConfig(enabled=" + str(self.enabled) + ", threshold=" + str(self.threshold) + ", stress=" + str(self.stress) + ")"

func current():
    s := _g.stats()
    return GcConfig(s["enabled"], s["threshold"], _stress[0])

func preset(name):
    if name == "default":
        return GcConfig(true, 1024, 0)
    if name == "throughput":
        return GcConfig(true, 65536, 0)
    if name == "low_latency":
        return GcConfig(true, 256, 0)
    if name == "memory":
        return GcConfig(true, 128, 0)
    if name == "debug":
        return GcConfig(true, null, 64)
    if name == "off":
        return GcConfig(false, null, 0)
    _e.config("gc_config.preset", "préréglage inconnu '" + str(name) + "' (default, throughput, low_latency, memory, debug, off)")

func presets():
    return ["default", "throughput", "low_latency", "memory", "debug", "off"]

# body() sous la configuration cfg ; la précédente est restaurée à la sortie, même sur erreur.
func with_config(cfg, body):
    before := cfg.apply()
    try:
        return body()
    finally:
        before.apply()

# Désactive le déclenchement automatique pendant body() (sections critiques en latence).
func without_gc(body):
    return with_config(current().with_enabled(false), body)
