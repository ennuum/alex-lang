# ALEX STANDARD LIBRARY — web.dom.resize_observer
#
# ResizeObserver : notification des changements de taille d'éléments (boîte content-box, border-box ou
# device-pixel-content-box), à partir de la géométrie simulée (element.set_layout). La première observation
# d'un élément de taille non nulle produit une entrée, puis chaque changement de taille. Livraison : micro-tâche
# si un ordonnanceur est branché, sinon observer.flush().
#
#   use web.dom.resize_observer as ro
#   obs := ro.ResizeObserver((entries, o) => print(entries[0].content_rect.width))
#   panneau.set_layout(0, 0, 300, 200)
#   obs.observe(panneau)
#   obs.flush()                        # 300
#   panneau.set_layout(0, 0, 420, 200)
#   obs.flush()                        # 420
#   obs.take_records()                 # entrées en attente
#
# Erreurs : TypeError (boîte inconnue).

from core use len, type
from collections use append
use web.dom.element as _el

const BOXES := ["content-box", "border-box", "device-pixel-content-box"]

class ResizeObserverSize:
    func init(inline_size, block_size):
        self.inline_size = inline_size
        self.block_size = block_size

class ResizeObserverEntry:
    func init(target, width, height, dpr):
        self.target = target
        self.content_rect = _el.DOMRect(0, 0, width, height)
        self.content_box_size = [ResizeObserverSize(width, height)]
        self.border_box_size = [ResizeObserverSize(width, height)]
        self.device_pixel_content_box_size = [ResizeObserverSize(width * dpr, height * dpr)]

class ResizeObserver:
    func init(callback):
        self.callback = callback
        self.targets = []          # (élément, boîte, dernière taille)
        self.records = []
        self.documents = []

    func observe(target, options=null):
        box := options["box"] if options != null and "box" in options else "content-box"
        if not (box in BOXES):
            raise("TypeError", "ResizeObserver.observe : boîte inconnue « " + str(box) + " »")
        kept := []
        for t in self.targets:
            if t[0] != target:
                append(kept, t)
        append(kept, [target, box, (0, 0)])
        self.targets = kept
        doc := target.owner_document
        if doc != null and not (doc in self.documents):
            append(self.documents, doc)
            doc.register_layout_observer(self)
        self.check()

    func unobserve(target):
        kept := []
        for t in self.targets:
            if t[0] != target:
                append(kept, t)
        self.targets = kept

    func disconnect():
        for d in self.documents:
            d.unregister_layout_observer(self)
        self.documents = []
        self.targets = []

    func take_records():
        out := self.records
        self.records = []
        return out

    func check():
        doc := null
        for t in self.targets:
            el := t[0]
            w := el.offset_width()
            h := el.offset_height()
            if not (w == t[2][0] and h == t[2][1]):
                t[2] = (w, h)
                dpr := 1
                d := el.owner_document
                if d != null and d.default_view != null:
                    dpr = d.default_view.device_pixel_ratio
                append(self.records, ResizeObserverEntry(el, w, h, dpr))
                doc = d
        if len(self.records) > 0 and doc != null and doc.mutation_hub.scheduler != null:
            obs := self
            doc.mutation_hub.scheduler(() => obs.flush())

    func flush():
        recs := self.take_records()
        if len(recs) > 0:
            self.callback(recs, self)
