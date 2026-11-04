# Paquet graphics : surfaces et mélange, tampons, textures (filtrage, mipmaps), matrices, pipeline
# (rastérisation, interpolation, profondeur, élimination, découpage proche, lignes, points, mélange),
# passes, tampons de commandes, chaîne d'images, cube éclairé.
from core use len
from collections use append
use os
use math
use graphics
use graphics.surface as gs
use graphics.buffer as gb
use graphics.texture as gt
use graphics.shader as sh
use graphics.pipeline as gp
use graphics.render_pass as grp
use graphics.command_buffer as gcb
use graphics.swapchain as gsc
use graphics.context as gctx

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

func near(a, b, eps):
    d := a - b
    if d < 0:
        d = -d
    return d <= eps

# couleurs et surface
check(gs.rgba(1.0, 0.0, 0.0) == 0xFFFF0000 and gs.unpack(0x80102030) == [16, 32, 48, 128], "couleurs")
check(gs.blend_over(0xFF0000FF, 0x80FF0000) == gs.pack(128, 0, 127, 255), "mélange alpha : " + str(gs.unpack(gs.blend_over(0xFF0000FF, 0x80FF0000))))
s := gs.Surface(16, 8)
s.clear(0xFF000000)
s.fill_rect(2, 2, 4, 3, 0xFFFFFFFF)
check(s.count(0xFFFFFFFF) == 12 and s.pixel(2, 2) == 0xFFFFFFFF and s.pixel(6, 2) == 0xFF000000, "rectangle")
c := s.copy()
check(c.diff(s) == 0, "copie")
c.set_pixel(0, 0, 0xFF010101)
check(c.diff(s) == 1 and c.diff(s, 2) == 0, "différences et tolérance")

# tampons
vb := gb.VertexBuffer(gb.POSITION_COLOR, [0.0, 0.5, 0.0, 1.0, 0.0, 0.0, 1.0, -0.5, -0.5, 0.0, 0.0, 1.0, 0.0, 1.0, 0.5, -0.5, 0.0, 0.0, 0.0, 1.0, 1.0])
check(vb.count() == 3 and vb.vertex(1)[1] == [0.0, 1.0, 0.0, 1.0] and vb.attribute(2, "position") == [0.5, -0.5, 0.0], "tampon de sommets")
erreur := ""
try:
    gb.VertexBuffer(gb.POSITION_COLOR, [1.0, 2.0])
catch e:
    erreur = e.type
check(erreur == "ArgumentError", "tampon incomplet")
check(gb.cube().count() == 36, "cube")

# textures
t := gt.checkerboard(4, 4, 2, 0xFFFFFFFF, 0xFF000000)
check(gs.to_floats(t.get(0, 0))[0] == 1.0 and t.sample(0.75, 0.25)[0] == 0.0 and t.sample(1.1, 0.1)[0] == 1.0, "damier, répétition")
t.filter = "linear"
check(near(t.sample(0.5, 0.25)[0], 0.5, 0.01), "bilinéaire au bord des cases")
check(t.build_mipmaps() == 3 and t.mips[2].width == 1 and near(gs.to_floats(t.mips[2].pixels[0])[0], 0.5, 0.01), "mipmaps")
g := gt.gradient(3, 1, 0xFF000000, 0xFFFFFFFF)
check(gs.unpack(g.get(1, 0))[0] == 127, "dégradé")

# matrices
m := sh.mul(sh.translate(1.0, 2.0, 3.0), sh.scale(2.0, 2.0, 2.0))
p := sh.transform(m, [1.0, 1.0, 1.0])
check(p == [3.0, 4.0, 5.0, 1.0], "translation · échelle")
r := sh.transform(sh.rotate_z(math.PI / 2.0), [1.0, 0.0, 0.0])
check(near(r[0], 0.0, 0.000001) and near(r[1], 1.0, 0.000001), "rotation")
la := sh.look_at([0.0, 0.0, 5.0], [0.0, 0.0, 0.0], [0.0, 1.0, 0.0])
check(near(sh.transform(la, [0.0, 0.0, 0.0])[2], -5.0, 0.000001), "caméra")
pr := sh.transform(sh.perspective(1.0, 1.0, 1.0, 10.0), [0.0, 0.0, -1.0])
check(near(pr[2] / pr[3], -1.0, 0.000001), "perspective : plan proche à -1")

# pipeline : triangle couleur par sommet
s2 := gs.Surface(32, 32)
rp := grp.RenderPass(s2)
rp.begin()
pipe := gp.Pipeline(sh.vertex_color())
st := rp.draw(pipe, vb)
rp.end()
centre := gs.unpack(s2.pixel(16, 16))
check(st["fragments"] > 100 and st["culled"] == 0, "triangle rastérisé : " + str(st))
check(centre[0] > 50 and centre[1] > 50 and centre[2] > 50, "interpolation des couleurs au centre : " + str(centre))
check(gs.unpack(s2.pixel(16, 9))[0] > gs.unpack(s2.pixel(16, 9))[1], "rouge vers le sommet du haut")
check(s2.pixel(1, 1) == 0xFF000000, "hors du triangle")
# face arrière (sens horaire) éliminée
vb_cw := gb.VertexBuffer(gb.POSITION_COLOR, [0.0, 0.5, 0.0, 1.0, 0.0, 0.0, 1.0, 0.5, -0.5, 0.0, 0.0, 0.0, 1.0, 1.0, -0.5, -0.5, 0.0, 0.0, 1.0, 0.0, 1.0])
rp.begin()
check(rp.draw(pipe, vb_cw)["culled"] == 1, "élimination de la face arrière")
pipe.cull = "none"
check(rp.draw(pipe, vb_cw)["fragments"] > 100, "sans élimination")
rp.end()
# profondeur : un carré rouge proche puis un bleu loin -> rouge visible
quad := func(z, rr, gg, bb) => gb.VertexBuffer(gb.POSITION_COLOR, [-0.5, -0.5, z, rr, gg, bb, 1.0, 0.5, -0.5, z, rr, gg, bb, 1.0, 0.5, 0.5, z, rr, gg, bb, 1.0, -0.5, -0.5, z, rr, gg, bb, 1.0, 0.5, 0.5, z, rr, gg, bb, 1.0, -0.5, 0.5, z, rr, gg, bb, 1.0])
s3 := gs.Surface(16, 16)
rp3 := grp.RenderPass(s3)
rp3.begin()
pd := gp.Pipeline(sh.vertex_color())
rp3.draw(pd, quad(-0.5, 1.0, 0.0, 0.0))
st3 := rp3.draw(pd, quad(0.5, 0.0, 0.0, 1.0))
rp3.end()
check(s3.pixel(8, 8) == 0xFFFF0000 and st3["depth_failed"] > 0, "test de profondeur")
# mélange alpha
s4 := gs.Surface(8, 8)
s4.clear(0xFF0000FF)
pa := gp.Pipeline(sh.solid())
pa.blend = "alpha"
pa.depth_test = false
u := gb.UniformBuffer({"color": [1.0, 0.0, 0.0, 0.5]})
pa.draw(s4, quad(0.0, 0.0, 0.0, 0.0), null, u, [0, 0, 8, 8])
check(gs.unpack(s4.pixel(4, 4))[0] > 120 and gs.unpack(s4.pixel(4, 4))[2] > 120, "mélange alpha du pipeline")
# découpage par le plan proche : triangle qui traverse la caméra
proj := sh.chain([sh.perspective(1.2, 1.0, 0.5, 20.0), sh.look_at([0.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0])])
vb_near := gb.VertexBuffer(gb.POSITION_COLOR, [-1.0, -0.5, -3.0, 1.0, 1.0, 1.0, 1.0, 1.0, -0.5, -3.0, 1.0, 1.0, 1.0, 1.0, 0.0, -0.5, 2.0, 1.0, 1.0, 1.0, 1.0])
s5 := gs.Surface(16, 16)
p5 := gp.Pipeline(sh.vertex_color())
p5.cull = "none"
st5 := p5.draw(s5, vb_near, null, gb.UniformBuffer({"mvp": proj}))
check(st5["fragments"] > 0 and st5["clipped"] == 0, "triangle découpé par le plan proche : " + str(st5))
# indices, lignes, points
s6 := gs.Surface(10, 10)
pl := gp.Pipeline(sh.solid(), "lines")
pl.depth_test = false
lines := gb.VertexBuffer(gb.POSITION, [-0.9, 0.0, 0.0, 0.9, 0.0, 0.0])
stl := pl.draw(s6, lines, gb.IndexBuffer([0, 1]), gb.UniformBuffer({"color": [0.0, 1.0, 0.0, 1.0]}))
check(stl["fragments"] >= 8 and s6.pixel(5, 5) == 0xFF00FF00, "ligne")
pp := gp.Pipeline(sh.solid(), "points")
pp.point_size = 3
stp := pp.draw(s6, gb.VertexBuffer(gb.POSITION, [0.0, 0.6, 0.0]), null, gb.UniformBuffer({"color": [1.0, 1.0, 0.0, 1.0]}))
check(stp["fragments"] == 9, "point de 3x3")
# texture plaquée
s7 := gs.Surface(8, 8)
pt := gp.Pipeline(sh.textured())
pt.cull = "none"
quv := gb.fullscreen_quad()
pt.draw(s7, quv, null, gb.UniformBuffer({"texture": gt.checkerboard(2, 2, 1, 0xFFFFFFFF, 0xFF000000)}))
check(s7.pixel(1, 1) == 0xFFFFFFFF and s7.pixel(6, 1) == 0xFF000000, "texture plaquée")

# tampon de commandes et contexte
ctx := gctx.Context()
cible := ctx.surface(24, 24)
cb := ctx.commands()
compte := [0]
func bump():
    compte[0] = compte[0] + 1
cb.begin_pass(cible, gs.rgba(0.0, 0.0, 0.0))
cb.bind_pipeline(gp.Pipeline(sh.vertex_color()))
cb.bind_vertices(vb)
cb.callback(bump)
cb.draw()
cb.set_viewport(0, 0, 12, 12)
cb.draw()
cb.end_pass()
cb.finish()
tot := ctx.submit(cb)
check(tot["draws"] == 2 and tot["passes"] == 1 and compte[0] == 1 and tot["fragments"] > 60, "tampon de commandes : " + str(tot))
ctx.submit(cb)
check(ctx.frames == 2 and compte[0] == 2, "rejouer")
erreur = ""
try:
    bad := gcb.CommandBuffer()
    bad.draw()
    gcb.execute(bad)
catch e3:
    erreur = e3.type
check(erreur == "InvalidStateError", "commande hors passe")

# chaîne d'images
prefixe := os.tmp_dir() + "/alex_gfx_" + str(os.pid())
sc := gsc.Swapchain(8, 8, 2, gsc.FilePresenter(prefixe))
a := sc.acquire()
a.clear(0xFFFF0000)
sc.present()
b := sc.acquire()
check(a != b, "deux images")
b.clear(0xFF00FF00)
sc.present()
check(len(sc.presenter.paths) == 2 and os.size(sc.presenter.paths[0]) == 11 + 192, "présentation en PPM")
for chemin in sc.presenter.paths:
    os.remove(chemin)
mem := gsc.Swapchain(4, 4, 3)
k := 0
while k < 5:
    mem.acquire().clear(0xFF000000 + k)
    mem.present()
    k += 1
check(mem.presenter.count == 5 and mem.presenter.last.pixel(0, 0) == 0xFF000004 and mem.fps() > 0, "présentation mémoire")

# scènes complètes
tri := graphics.render_triangle(40, 30)
check(tri.diff(graphics.render_triangle(40, 30)) == 0 and tri.count(gs.rgba(0.05, 0.05, 0.1)) < 1200, "triangle déterministe")
cube := graphics.render_cube(48, 48, 0.6)
fond := gs.rgba(0.1, 0.1, 0.15)
visibles := 48 * 48 - cube.count(fond)
check(visibles > 300 and visibles < 2000, "cube éclairé : " + str(visibles) + " points")
cube.save_ppm(prefixe + ".ppm")
check(os.size(prefixe + ".ppm") > 6900, "image du cube")
os.remove(prefixe + ".ppm")
print("graphics : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")
