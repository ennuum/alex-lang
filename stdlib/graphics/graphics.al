# ALEX STANDARD LIBRARY — graphics
#
# Rendu 2D / 3D pour les applications, sur un pipeline LOGICIEL écrit en Alex (aucun pilote nécessaire) :
#
# | Module                    | Contenu                                                                   |
# |---------------------------|---------------------------------------------------------------------------|
# | graphics.context          | Context : création des objets, soumission, statistiques                   |
# | graphics.surface          | Surface : couleurs RGBA + profondeur, mélange, PPM, octets pour ui        |
# | graphics.buffer           | VertexLayout, VertexBuffer, IndexBuffer, UniformBuffer, cube, quad        |
# | graphics.texture          | Texture : échantillonnage (plus proche / bilinéaire), mipmaps, motifs     |
# | graphics.shader           | Shader (sommets + fragments en Alex), matrices 4x4, shaders fournis       |
# | graphics.pipeline         | Pipeline : découpage, élimination, rastérisation, profondeur, mélange     |
# | graphics.render_pass      | RenderPass : effacement, viewport, dessins                                |
# | graphics.command_buffer   | CommandBuffer : enregistrement puis exécution                             |
# | graphics.swapchain        | Swapchain : images multiples, présentation (fenêtre ui, fichiers, mémoire)|
#
#   use graphics
#   img := graphics.render_triangle(160, 120)         # Surface : triangle coloré
#   img.save_ppm("triangle.ppm")
#   img = graphics.render_cube(160, 120, 0.6)          # cube éclairé, tourné de 0,6 rad
#
# Les cartes d'un noyau Alex se pilotent avec gpu_driver ; le calcul parallèle est dans gpu.

use math
use graphics.context as gctx
use graphics.surface as gs
use graphics.buffer as gb
use graphics.shader as sh
use graphics.pipeline as gp
use graphics.render_pass as grp
use graphics.texture as gt

func context():
    return gctx.Context()

func surface(width, height):
    return gs.Surface(width, height)

func rgba(r, g, b, a=1.0):
    return gs.rgba(r, g, b, a)

# Triangle aux sommets rouge, vert, bleu sur fond sombre (exemple et test du pipeline).
func render_triangle(width, height):
    s := gs.Surface(width, height)
    vb := gb.VertexBuffer(gb.POSITION_COLOR, [0.0, 0.8, 0.0, 1.0, 0.0, 0.0, 1.0,
                                              -0.8, -0.8, 0.0, 0.0, 1.0, 0.0, 1.0,
                                              0.8, -0.8, 0.0, 0.0, 0.0, 1.0, 1.0])
    rp := grp.RenderPass(s)
    rp.clear_color = gs.rgba(0.05, 0.05, 0.1)
    rp.begin()
    rp.draw(gp.Pipeline(sh.vertex_color()), vb)
    rp.end()
    return s

# Cube texturé (damier) et éclairé, vu en perspective, tourné de angle radians.
func render_cube(width, height, angle):
    s := gs.Surface(width, height)
    model := sh.mul(sh.rotate_y(angle), sh.rotate_x(angle * 0.7))
    view := sh.look_at([0.0, 0.0, 2.5], [0.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    proj := sh.perspective(1.0, 1.0 * width / height, 0.1, 10.0)
    u := gb.UniformBuffer({"mvp": sh.chain([proj, view, model]), "model": model, "light_dir": [0.4, 0.6, 1.0],
                           "diffuse": [1.0, 0.8, 0.5, 1.0], "texture": gt.checkerboard(8, 8, 2, 0xFFFFFFFF, 0xFF606060)})
    rp := grp.RenderPass(s)
    rp.clear_color = gs.rgba(0.1, 0.1, 0.15)
    rp.begin()
    rp.draw(gp.Pipeline(sh.lit()), gb.cube(), null, u)
    rp.end()
    return s
