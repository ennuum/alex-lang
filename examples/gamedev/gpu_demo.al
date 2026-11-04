# Démo : rendu par la carte graphique (gl, gl.render) + son en temps réel (audio.realtime).
#
#   ./alex run examples/gamedev/gpu_demo.al
#
# Flèches / ZQSD / WASD : déplacer la caméra ; souris (bouton gauche) : tourner ; Espace : son + rebond ;
# F : plein écran ; V : synchro verticale ; Tab : fil de fer ; Échap : quitter.

from collections use append
use math
use math3d as m3
use mesh
use gl
use gl.window as glw
use gl.render as gr
use audio
use audio.realtime as rt

w := glw.Window("ALEX — démo GPU", 1280, 720, {"vsync": true})
print("Carte graphique : " + w.info["renderer"] + " (OpenGL " + w.info["version"] + ")")
r := gr.Renderer(w)
r.set_ambient([0.22, 0.24, 0.3])
r.set_sun([-0.4, -1.0, -0.3], [0.9, 0.85, 0.8])
r.set_fog(15.0, 45.0, [0.07, 0.09, 0.13])
lampe := r.add_point_light([0.0, 2.0, 0.0], [1.0, 0.5, 0.2], 9.0)

sol := gr.GpuMesh(mesh.plane(60, 60))
cube := gr.GpuMesh(mesh.box(1, 1, 1))
boule := gr.GpuMesh(mesh.sphere(0.5, 32, 20))
tore := gr.GpuMesh(mesh.torus(0.8, 0.25, 32, 16))
m_sol := gr.Material([1.0, 1.0, 1.0, 1.0], gr.checker_texture(64, 8), 0.05)
m_sol.uv_rect = [0.0, 0.0, 30.0, 30.0]
couleurs := [[0.9, 0.3, 0.2, 1.0], [0.2, 0.7, 0.9, 1.0], [0.9, 0.8, 0.2, 1.0], [0.4, 0.9, 0.4, 1.0]]
mats := [gr.Material(c, null, 0.5, 48.0) for c in couleurs]
m_verre := gr.Material([0.6, 0.8, 1.0, 0.45], null, 0.9, 96.0)
m_lampe := gr.Material([1.0, 0.6, 0.3, 1.0], null, 0.0, 1.0, true)
hud := gr.SpriteBatch(r)

# son : bip synthétisé et boucle d'ambiance (aucun fichier nécessaire)
son := rt.AudioEngine()
bip := son.sound(audio.tone(660, 0.12).samples)
nappe := son.sound(audio.tone(110, 2.0).samples)
son.play(nappe, 0.15, 0.0, true, "music")

cam := [0.0, 2.5, 9.0]
yaw := 0.0
pitch := -0.15
saut := 0.0
vsaut := 0.0
fil := false
while w.is_open():
    for e in w.poll():
        if e["type"] == "key_down":
            k := e["key"]
            if k == "escape":
                w.close()
            elif k == "space" and saut <= 0.0:
                vsaut = 6.0
                son.play(bip, 0.6, 0.0)
            elif k == "f":
                w.set_fullscreen(not w.fullscreen)
            elif k == "v":
                w.set_vsync(not w.vsync)
            elif k == "tab":
                fil = not fil
                r.set_wireframe(fil)
        elif e["type"] == "mouse_move" and w.mouse_down("left"):
            yaw -= e["dx"] * 0.005
            pitch -= e["dy"] * 0.005
    if not w.is_open():
        break
    dt := w.dt if w.dt > 0.0 and w.dt < 0.1 else 1.0 / 60.0
    avant := [0.0 - math.sin(yaw), 0.0, 0.0 - math.cos(yaw)]
    droite := [math.cos(yaw), 0.0, 0.0 - math.sin(yaw)]
    v := 6.0 * dt
    if w.key_down("up") or w.key_down("w") or w.key_down("z"):
        cam = m3.vec3_add(cam, m3.vec3_scale(avant, v))
    if w.key_down("down") or w.key_down("s"):
        cam = m3.vec3_sub(cam, m3.vec3_scale(avant, v))
    if w.key_down("left") or w.key_down("a") or w.key_down("q"):
        cam = m3.vec3_sub(cam, m3.vec3_scale(droite, v))
    if w.key_down("right") or w.key_down("d"):
        cam = m3.vec3_add(cam, m3.vec3_scale(droite, v))
    vsaut -= 15.0 * dt
    saut += vsaut * dt
    if saut < 0.0:
        saut = 0.0
        vsaut = 0.0
    t := w.time()
    lampe["position"] = [math.cos(t) * 4.0, 1.5, math.sin(t) * 4.0]
    regard := [cam[0] + math.cos(pitch) * avant[0], cam[1] + math.sin(pitch), cam[2] + math.cos(pitch) * avant[2]]
    son.set_listener(cam, avant)
    son.update()

    r.begin_frame([0.07, 0.09, 0.13, 1.0])
    r.set_perspective(m3.radians(65), cam, regard, 0.1, 200.0)
    r.draw(sol, m3.mat4_translation(0.0, -0.5, 0.0), m_sol)
    i := 0
    while i < 36:
        x := (i % 6) * 2.5 - 6.25
        z := (i // 6) * 2.5 - 12.0
        m := m3.mat4_mul(m3.mat4_translation(x, math.sin(t * 2.0 + i) * 0.3, z), m3.mat4_rotation_y(t * 0.7 + i))
        r.draw(cube if i % 3 != 0 else tore, m, mats[i % 4])
        i += 1
    r.draw(boule, m3.mat4_translation(lampe["position"][0], lampe["position"][1], lampe["position"][2]), m_lampe)
    r.draw(boule, m3.mat4_mul(m3.mat4_translation(0.0, 0.5 + saut, 3.0), m3.mat4_scaling(2.0, 2.0, 2.0)), m_verre)

    hud.begin()
    hud.rect(10, 10, 260, 46, [0.0, 0.0, 0.0, 0.55])
    barre := w.fps / 60.0
    if barre > 1.0:
        barre = 1.0
    hud.rect(20, 20, 240 * barre, 10, [0.3, 0.9, 0.4, 1.0])
    hud.rect_outline(20, 20, 240, 10, [1.0, 1.0, 1.0, 0.8])
    hud.rect(20, 38, 240 * son.active_voices() / 8.0, 8, [0.9, 0.7, 0.2, 1.0])
    hud.circle(w.width - 40.0, 40.0, 18.0, [1.0, 0.6, 0.3, 0.9])
    hud.end()
    w.swap()
    if w.frame_count % 30 == 0:
        w.set_title("ALEX — démo GPU — " + str(math.round(w.fps)) + " img/s, " + str(r.stats["draws"]) + " objets")
son.close()
