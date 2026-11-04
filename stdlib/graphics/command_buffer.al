# ALEX STANDARD LIBRARY — graphics.command_buffer
#
# Tampon de commandes de rendu (comme Vulkan / Metal) : on ENREGISTRE la suite des opérations d'une image,
# puis on la SOUMET d'un coup (graphics.context.Context.submit) ; le même tampon peut être rejoué. Commandes :
# begin_pass / end_pass, bind_pipeline, bind_vertices, bind_indices, set_uniform, set_viewport, draw,
# copy_surface (blit d'une surface dans une autre), callback (code Alex arbitraire, ex. mise à jour d'un
# uniform animé).
#
#   cb := CommandBuffer()
#   cb.begin_pass(cible, gs.rgba(0, 0, 0))
#   cb.bind_pipeline(p)
#   cb.bind_vertices(vb)
#   cb.set_uniform("mvp", mvp)
#   cb.draw()
#   cb.end_pass()
#   ctx.submit(cb)

from core use len
from collections use append, keys
use graphics.render_pass as rpm
use graphics.buffer as gb

class CommandBuffer:
    func init(label="commandes"):
        self.label = label
        self.commands = []
        self.recording = true

    func _add(op, args):
        if not self.recording:
            raise("InvalidStateError", "CommandBuffer : enregistrement terminé (reset() pour recommencer)")
        append(self.commands, [op, args])
        return self

    func begin_pass(target, clear_color=0xFF000000, load="clear"):
        return self._add("begin_pass", [target, clear_color, load])

    func end_pass():
        return self._add("end_pass", [])

    func bind_pipeline(p):
        return self._add("pipeline", [p])

    func bind_vertices(vb):
        return self._add("vertices", [vb])

    func bind_indices(ib):
        return self._add("indices", [ib])

    func set_uniform(name, value):
        return self._add("uniform", [name, value])

    func set_viewport(x, y, w, h):
        return self._add("viewport", [[x, y, w, h]])

    func draw():
        return self._add("draw", [])

    func copy_surface(src, dst, x, y, blend=true):
        return self._add("copy", [src, dst, x, y, blend])

    # fn() exécutée à cet endroit lors de la soumission.
    func callback(fn):
        return self._add("callback", [fn])

    func finish():
        self.recording = false
        return self

    func reset():
        self.commands = []
        self.recording = true

    func count():
        return len(self.commands)

# Exécute les commandes ; renvoie le total des statistiques des passes.
func execute(cb):
    totals := {"draws": 0, "fragments": 0, "passes": 0}
    rp := null
    pipeline := null
    vb := null
    ib := null
    uniforms := gb.UniformBuffer()
    viewport := null
    for c in cb.commands:
        op := c[0]
        a := c[1]
        if op == "begin_pass":
            rp = rpm.RenderPass(a[0], a[2])
            rp.clear_color = a[1]
            rp.viewport = viewport
            rp.begin()
            totals["passes"] = totals["passes"] + 1
        elif op == "end_pass":
            if rp == null:
                raise("InvalidStateError", "CommandBuffer : end_pass sans begin_pass")
            st := rp.end()
            totals["fragments"] = totals["fragments"] + st["fragments"]
            rp = null
        elif op == "pipeline":
            pipeline = a[0]
        elif op == "vertices":
            vb = a[0]
            ib = null
        elif op == "indices":
            ib = a[0]
        elif op == "uniform":
            uniforms.set(a[0], a[1])
        elif op == "viewport":
            viewport = a[0]
            if rp != null:
                rp.viewport = viewport
        elif op == "draw":
            if rp == null or pipeline == null or vb == null:
                raise("InvalidStateError", "CommandBuffer : draw sans passe, pipeline ou sommets")
            rp.draw(pipeline, vb, ib, uniforms)
            totals["draws"] = totals["draws"] + 1
        elif op == "copy":
            a[1].draw_surface(a[0], a[2], a[3], a[4])
        elif op == "callback":
            f := a[0]
            f()
    if rp != null:
        raise("InvalidStateError", "CommandBuffer : passe non terminée (end_pass)")
    return totals
