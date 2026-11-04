# ALEX STANDARD LIBRARY — graphics.context
#
# Contexte de rendu : le point d'entrée qui crée les objets (surfaces, tampons, textures, pipelines,
# tampons de commandes, chaîne d'images) et exécute les soumissions, avec des statistiques par image.
# Le moteur est LOGICIEL (pipeline en Alex) : il fonctionne partout, sans pilote, en VM comme dans une
# application ; les mêmes objets serviront à un dorsal matériel.
#
#   use graphics.context as gctx
#   ctx := gctx.Context()
#   sc := ctx.swapchain(320, 240)
#   p := ctx.pipeline(sh.vertex_color())
#   cb := ctx.commands()
#   ...
#   ctx.submit(cb)
#   sc.present()

from core use len
use graphics.surface as gs
use graphics.buffer as gb
use graphics.texture as gt
use graphics.shader as sh
use graphics.pipeline as gp
use graphics.render_pass as grp
use graphics.command_buffer as gcb
use graphics.swapchain as gsc

class Context:
    func init(name="logiciel"):
        self.name = name
        self.frames = 0
        self.draws = 0
        self.fragments = 0

    func surface(width, height, depth=true):
        return gs.Surface(width, height, depth)

    func vertex_buffer(layout, data):
        return gb.VertexBuffer(layout, data)

    func index_buffer(indices):
        return gb.IndexBuffer(indices)

    func uniforms(values=null):
        return gb.UniformBuffer(values)

    func texture(width, height, pixels=null):
        return gt.Texture(width, height, pixels)

    func pipeline(shader, topology="triangles"):
        return gp.Pipeline(shader, topology)

    func render_pass(target, load="clear"):
        return grp.RenderPass(target, load)

    func commands(label="commandes"):
        return gcb.CommandBuffer(label)

    func swapchain(width, height, images=2, presenter=null):
        return gsc.Swapchain(width, height, images, presenter)

    func submit(cb):
        t := gcb.execute(cb)
        self.frames += 1
        self.draws += t["draws"]
        self.fragments += t["fragments"]
        return t

    func describe():
        return "contexte " + self.name + " : " + str(self.frames) + " soumissions, " + str(self.draws) + " dessins, " + str(self.fragments) + " fragments"
