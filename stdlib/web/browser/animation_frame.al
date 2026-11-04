# ALEX STANDARD LIBRARY — web.browser.animation_frame
#
# requestAnimationFrame : les rappels enregistrés avant une image sont appelés ensemble avec l'horodatage de
# l'image (millisecondes) ; ceux enregistrés pendant l'image attendent la suivante. La boucle d'événements
# (web.browser.timers) produit une image toutes les 16,67 ms quand des rappels attendent, ou à la demande.
# Aides : animer une valeur sur une durée avec une fonction d'accélération CSS, mesurer les images.
#
#   use web.browser.animation_frame as af
#   id := loop.request_animation_frame((t) => dessiner(t))
#   loop.cancel_animation_frame(id)
#   anim := af.animate(loop, 300, (p) => boite.style.set("opacity", str(p)), "ease-out")   # 0 -> 1 en 300 ms
#   loop.advance(400)
#   anim.finished                    # true
#
# Erreurs : BrowserError (durée négative).

from core use len, type
from collections use append
use web.browser.browser_errors as _err
use web.css.transitions as _tr
use web.css.keyframes as _kf

class FrameScheduler:
    func init():
        self.callbacks = []        # (id, fn)
        self.next_id = 1
        self.frame_count = 0
        self.last_time = null
        self.running = false

    func request(fn):
        id := self.next_id
        self.next_id += 1
        append(self.callbacks, (id, fn))
        return id

    func cancel(id):
        kept := []
        for c in self.callbacks:
            if c[0] != id:
                append(kept, c)
        self.callbacks = kept

    func has_pending():
        return len(self.callbacks) > 0

    # Exécute une image : run(fn) exécute chaque rappel (gestion des erreurs par la boucle).
    func run_frame(timestamp, run):
        batch := self.callbacks
        self.callbacks = []
        self.frame_count += 1
        self.last_time = timestamp
        self.running = true
        for c in batch:
            run(c[1], timestamp)
        self.running = false
        return len(batch)

# Animation d'une progression 0..1 sur duration ms (on_progress(p) à chaque image ; p accélérée par easing).
class Animation:
    func init(loop, duration, on_progress, easing="linear", on_done=null):
        if duration < 0:
            _err.browser_error("animate", "durée négative")
        self.loop = loop
        self.duration = duration
        self.on_progress = on_progress
        self.easing = _tr.easing(easing)
        self.on_done = on_done
        self.start = null
        self.finished = false
        self.cancelled = false
        self.frames = 0
        self.id = loop.request_animation_frame((t) => self._frame(t))

    func _frame(t):
        if self.cancelled:
            return
        if self.start == null:
            self.start = t
        self.frames += 1
        elapsed := t - self.start
        p := 1.0 if self.duration == 0 else elapsed / self.duration
        if p >= 1.0:
            self.on_progress(self.easing.at(1.0))
            self.finished = true
            if self.on_done != null:
                self.on_done()
            return
        self.on_progress(self.easing.at(p))
        self.id = self.loop.request_animation_frame((t2) => self._frame(t2))

    func cancel():
        self.cancelled = true
        self.loop.cancel_animation_frame(self.id)

func animate(loop, duration, on_progress, easing="linear", on_done=null):
    return Animation(loop, duration, on_progress, easing, on_done)

# Interpole une propriété CSS d'un élément (style en ligne) entre deux valeurs.
func animate_style(loop, element, prop, start, end, duration, easing="ease"):
    return Animation(loop, duration, (p) => element.style.set_property(prop, _kf.interpolate(start, end, p)), easing)
