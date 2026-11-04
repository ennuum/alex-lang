# ALEX STANDARD LIBRARY — graphics.render_pass
#
# Passe de rendu : une cible (graphics.surface.Surface), ce qu'on fait de son contenu au début (effacer à une
# couleur / profondeur, ou conserver) et la zone de dessin (viewport, ciseaux) ; les dessins de la passe s'y
# accumulent ; à la fin, statistiques cumulées.
#
#   rp := RenderPass(surface)
#   rp.clear_color = gs.rgba(0.1, 0.1, 0.15)
#   rp.begin()
#   rp.draw(pipeline, vb, null, uniforms)
#   rp.end()
#   print(rp.totals)

from core use len
from collections use append, keys
use graphics.surface as gs

class RenderPass:
    func init(target, load="clear"):
        self.target = target
        self.load = load                     # "clear" ou "keep"
        self.clear_color = 0xFF000000
        self.clear_depth = 1.0
        self.viewport = null                 # [x, y, largeur, hauteur]
        self.active = false
        self.draws = 0
        self.totals = {}

    func begin():
        if self.active:
            raise("InvalidStateError", "RenderPass : passe déjà commencée")
        if self.load == "clear":
            self.target.clear(self.clear_color)
            self.target.clear_depth(self.clear_depth)
        self.active = true
        self.draws = 0
        self.totals = {"vertices": 0, "primitives": 0, "culled": 0, "clipped": 0, "fragments": 0, "rejected": 0, "depth_failed": 0}

    func draw(pipeline, vb, ib=null, uniforms=null):
        if not self.active:
            raise("InvalidStateError", "RenderPass : draw hors d'une passe (begin)")
        st := pipeline.draw(self.target, vb, ib, uniforms, self.viewport)
        for k in keys(st):
            self.totals[k] = self.totals[k] + st[k]
        self.draws += 1
        return st

    func end():
        if not self.active:
            raise("InvalidStateError", "RenderPass : passe non commencée")
        self.active = false
        return self.totals

    func describe():
        return "passe : " + str(self.draws) + " dessins, " + str(self.totals["fragments"]) + " fragments, " + str(self.totals["culled"]) + " faces éliminées"
