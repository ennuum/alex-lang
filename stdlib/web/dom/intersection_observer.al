# ALEX STANDARD LIBRARY — web.dom.intersection_observer
#
# IntersectionObserver : visibilité d'éléments par rapport à la fenêtre (ou à un élément racine), avec marge
# de racine (« 10px 20% ») et seuils. Sans moteur de rendu, les positions viennent de la géométrie simulée
# (element.set_layout, fenêtre de web.dom.window) ; chaque changement de géométrie relance le calcul. Les
# entrées sont livrées comme pour MutationObserver : micro-tâche si un ordonnanceur est branché, sinon
# observer.flush().
#
#   use web.dom.intersection_observer as io
#   obs := io.IntersectionObserver((entries, o) => print(entries[0].is_intersecting), {"threshold": [0, 0.5, 1]})
#   obs.observe(image)                 # première entrée toujours produite
#   image.set_layout(0, 2000, 300, 200)   # hors de la fenêtre 1280×720
#   obs.flush()                        # false
#   window.scroll_to(0, 1600)          # recalcul : intersection
#   obs.take_records()[0].intersection_ratio    # 1.0
#
# Erreurs : SyntaxError (marge invalide), RangeError (seuil hors de [0, 1]).

from core use len, type, to_float
from collections use append
use string as _s
use web.dom.dom_errors as _err
use web.dom.event as _ev
use web.dom.element as _el

class IntersectionObserverEntry:
    func init(target, time, root_bounds, bounding_client_rect, intersection_rect, ratio, is_intersecting):
        self.target = target
        self.time = time
        self.root_bounds = root_bounds
        self.bounding_client_rect = bounding_client_rect
        self.intersection_rect = intersection_rect
        self.intersection_ratio = ratio
        self.is_intersecting = is_intersecting

func _margins(text):
    parts := []
    for p in _s.split(_s.trim(str(text)), " "):
        if p != "":
            append(parts, p)
    if len(parts) == 0 or len(parts) > 4:
        _err.syntax("IntersectionObserver", "marge de racine invalide « " + str(text) + " »")
    for p in parts:
        if not (_s.ends_with(p, "px") or _s.ends_with(p, "%")) and p != "0":
            _err.syntax("IntersectionObserver", "marge en px ou % attendue : « " + p + " »")
    while len(parts) < 4:
        if len(parts) == 1:
            parts = [parts[0], parts[0], parts[0], parts[0]]
        elif len(parts) == 2:
            parts = [parts[0], parts[1], parts[0], parts[1]]
        elif len(parts) == 3:
            parts = [parts[0], parts[1], parts[2], parts[1]]
    return parts

func _margin_px(m, size):
    if m == "0":
        return 0.0
    if _s.ends_with(m, "%"):
        return to_float(m[0:len(m) - 1]) * size / 100.0
    return to_float(m[0:len(m) - 2])

class IntersectionObserver:
    # options : root (élément ou null = fenêtre), root_margin, threshold (nombre ou liste).
    func init(callback, options=null):
        o := options if options != null else {}
        self.callback = callback
        self.root = o["root"] if "root" in o else null
        self.root_margin = o["root_margin"] if "root_margin" in o else (o["rootMargin"] if "rootMargin" in o else "0px")
        self.margins = _margins(self.root_margin)
        th := o["threshold"] if "threshold" in o else 0
        self.thresholds = th if type(th) == "list" else [th]
        for t in self.thresholds:
            if t < 0 or t > 1:
                raise("RangeError", "IntersectionObserver : seuil hors de [0, 1] : " + str(t))
        self.thresholds = _sorted(self.thresholds)
        self.targets = []
        self.previous = {}          # indice de cible -> (indice de seuil, intersecte)
        self.records = []
        self.documents = []

    func _root_rect(target):
        r := null
        if self.root != null:
            r = self.root.get_bounding_client_rect()
        else:
            doc := target.owner_document
            w := 1280
            h := 720
            if doc != null and doc.default_view != null:
                w = doc.default_view.inner_width
                h = doc.default_view.inner_height
            r = _el.DOMRect(0, 0, w, h)
        top := _margin_px(self.margins[0], r.height)
        right := _margin_px(self.margins[1], r.width)
        bottom := _margin_px(self.margins[2], r.height)
        left := _margin_px(self.margins[3], r.width)
        return _el.DOMRect(r.left - left, r.top - top, r.width + left + right, r.height + top + bottom)

    func observe(target):
        for t in self.targets:
            if t == target:
                return
        append(self.targets, target)
        doc := target.owner_document
        if doc != null and not (doc in self.documents):
            append(self.documents, doc)
            doc.register_layout_observer(self)
        self._check_one(target, len(self.targets) - 1, true)
        self._schedule(doc)

    func unobserve(target):
        kept := []
        for t in self.targets:
            if t != target:
                append(kept, t)
        self.targets = kept
        self.previous = {}

    func disconnect():
        for d in self.documents:
            d.unregister_layout_observer(self)
        self.documents = []
        self.targets = []
        self.previous = {}

    func take_records():
        out := self.records
        self.records = []
        return out

    func _threshold_index(ratio, intersecting):
        i := 0
        for t in self.thresholds:
            if ratio >= t and (intersecting or t > 0):
                i += 1
            elif ratio < t:
                break
        return i

    func _check_one(target, idx, force):
        rect := target.get_bounding_client_rect()
        root := self._root_rect(target)
        inter := rect.intersection(root)
        connected := target.is_connected()
        area := rect.width * rect.height
        overlap := rect.left <= root.right and rect.right >= root.left and rect.top <= root.bottom and rect.bottom >= root.top
        intersecting := connected and overlap and (inter.width > 0 or inter.height > 0 or area == 0)
        ratio := 0.0
        if intersecting:
            ratio = (inter.width * inter.height) / area if area > 0 else 1.0
        ti := self._threshold_index(ratio, intersecting)
        key := str(idx)
        prev := self.previous[key] if key in self.previous else null
        if force or prev == null or prev[0] != ti or prev[1] != intersecting:
            self.previous[key] = (ti, intersecting)
            append(self.records, IntersectionObserverEntry(target, _ev.now(), root, rect, inter if intersecting else _el.DOMRect(), ratio, intersecting))

    # Recalcule toutes les cibles (appelé par le document après un changement de géométrie).
    func check():
        i := 0
        for t in self.targets:
            self._check_one(t, i, false)
            i += 1
        if len(self.targets) > 0:
            self._schedule(self.targets[0].owner_document)

    func _schedule(doc):
        if len(self.records) == 0:
            return
        if doc != null and doc.mutation_hub.scheduler != null:
            obs := self
            doc.mutation_hub.scheduler(() => obs.flush())

    func flush():
        recs := self.take_records()
        if len(recs) > 0:
            self.callback(recs, self)

func _sorted(xs):
    out := []
    for x in xs:
        append(out, x)
    i := 1
    while i < len(out):
        cur := out[i]
        j := i - 1
        while j >= 0 and out[j] > cur:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = cur
        i += 1
    return out
