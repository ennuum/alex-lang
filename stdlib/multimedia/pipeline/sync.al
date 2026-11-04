# ALEX STANDARD LIBRARY — multimedia.pipeline.sync
#
# Synchronisation audio / vidéo. L'horloge MAÎTRE est l'audio (MediaClock avancée par les trames réellement
# jouées) ; pour chaque image vidéo, AVSync décide :
#   « present »   afficher maintenant (écart dans la tolérance) ;
#   « wait »      trop tôt : attendre `delay` secondes ;
#   « drop »      trop tard : jeter l'image pour rattraper l'audio.
# Il mesure la dérive (moyenne, maximum) et propose une correction de fréquence audio bornée (± max_correction)
# pour résorber une dérive lente entre deux horloges matérielles.
#
#   use multimedia.pipeline.sync as sy
#   s := sy.AVSync(horloge_audio, 0.010, 0.080)    # tolérance 10 ms, image jetée au-delà de 80 ms de retard
#   d := s.decide(image.seconds())                  # ["present" | "wait" | "drop", délai]
#   ratio := sy.drift_correction(0.02, 10.0)        # ex. 1.002 : jouer l'audio 0,2 % plus vite
#   print(s.stats())                                # {"presented": ..., "dropped": ..., "mean_drift": ...}

from core use len
use multimedia.core.errors as merr

class AVSync:
    func init(master, tolerance=0.010, drop_after=0.080):
        if tolerance < 0 or drop_after <= tolerance:
            merr.fail(merr.FORMAT, "seuils de synchronisation invalides : " + str(tolerance) + " / " + str(drop_after))
        self.master = master
        self.tolerance = tolerance
        self.drop_after = drop_after
        self.presented = 0
        self.dropped = 0
        self.waited = 0
        self.max_drift = 0.0
        self.drift_sum = 0.0
        self.samples = 0

    # pts : instant de présentation de l'image (secondes, même échelle que l'horloge maître).
    func decide(pts):
        now := self.master.time()
        diff := pts - now
        a := diff if diff >= 0 else -diff
        self.drift_sum = self.drift_sum + a
        self.samples += 1
        if a > self.max_drift:
            self.max_drift = a
        if diff > self.tolerance:
            self.waited += 1
            return ["wait", diff]
        if -diff > self.drop_after:
            self.dropped += 1
            return ["drop", 0.0]
        self.presented += 1
        return ["present", 0.0]

    func mean_drift():
        if self.samples == 0:
            return 0.0
        return self.drift_sum / self.samples

    func stats():
        return {"presented": self.presented, "dropped": self.dropped, "waited": self.waited,
                "max_drift": self.max_drift, "mean_drift": self.mean_drift()}

    func reset():
        self.presented = 0
        self.dropped = 0
        self.waited = 0
        self.max_drift = 0.0
        self.drift_sum = 0.0
        self.samples = 0

# Ratio de lecture audio pour résorber `drift` secondes (positif : l'audio est en retard) en `horizon` secondes,
# borné à ± max_correction (0,5 % par défaut, inaudible).
func drift_correction(drift, horizon=10.0, max_correction=0.005):
    if horizon <= 0:
        merr.fail(merr.FORMAT, "horizon de correction invalide")
    r := drift / horizon
    if r > max_correction:
        r = max_correction
    if r < -max_correction:
        r = -max_correction
    return 1.0 + r

# Position audio d'après les trames réellement jouées (plus fiable qu'une horloge murale).
class SampleClock:
    func init(rate):
        if rate <= 0:
            merr.fail(merr.FORMAT, "fréquence invalide")
        self.rate = rate
        self.frames = 0
        self.offset = 0.0

    func advance(frames):
        self.frames += frames

    func seek(seconds):
        self.offset = seconds
        self.frames = 0

    func time():
        return self.offset + 1.0 * self.frames / self.rate
