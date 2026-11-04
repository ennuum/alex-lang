# Démo 2D : carte à tuiles (tilemap), sprite animé (sprite), particules (particles), manette (input.gamepad),
# caméra qui suit le joueur, son (audio.realtime). Aucun fichier externe : textures et niveau générés.
#
#   ./alex run examples/gamedev/platformer_demo.al
#
# Flèches / A D : courir ; Espace / Haut / bouton A : sauter ; Échap : quitter. Une manette (XInput sous Windows,
# evdev sous Linux) est utilisée si elle est branchée ; elle vibre à l'atterrissage.

from collections use append
use math
use gl
use gl.window as glw
use gl.render as gr
use scene
use sprite
use tilemap
use particles
use audio
use audio.realtime as rt
use input.gamepad as gp

const T := 16          # taille d'une tuile (px)
const ZOOM := 3.0

w := glw.Window("ALEX — plates-formes 2D", 1280, 720, {"vsync": true})
r := gr.Renderer(w)
batch := gr.SpriteBatch(r)

# ---- textures générées : 4 tuiles (terre, herbe, brique, pièce) et 4 images du héros ----
func pixel_art(wd, ht, fn):
    px := []
    y := 0
    while y < ht:
        x := 0
        while x < wd:
            c := fn(x, y)
            px = px + c
            x += 1
        y += 1
    return gr.Texture(wd, ht, px, 4, "nearest", "clamp", false)

func tile_px(x, y):
    t := x // T
    lx := x % T
    noise := ((lx * 7 + y * 13) % 5) * 6
    if t == 0:
        return [110 + noise, 72 + noise, 40, 255]
    if t == 1:
        if y < 4:
            return [70, 170 + noise, 60, 255]
        return [110 + noise, 72 + noise, 40, 255]
    if t == 2:
        if y % 8 == 0 or (lx + (8 if (y // 8) % 2 == 1 else 0)) % 16 == 0:
            return [90, 50, 40, 255]
        return [170 + noise, 80, 60, 255]
    d := (lx - 7.5) * (lx - 7.5) + (y - 7.5) * (y - 7.5)
    if d < 25:
        return [255, 210, 60, 255]
    return [0, 0, 0, 0]

tiles_tex := pixel_art(4 * T, T, tile_px)

func hero_px(x, y):
    f := x // 12
    lx := x % 12
    if y < 5 and lx >= 3 and lx <= 8:
        return [250, 210, 170, 255]
    if y >= 5 and y < 12 and lx >= 2 and lx <= 9:
        return [60, 110, 230, 255]
    if y >= 12:
        leg := 1 if f % 2 == 0 else -1
        if (lx >= 3 + leg and lx <= 4 + leg) or (lx >= 7 - leg and lx <= 8 - leg):
            return [50, 50, 70, 255]
    return [0, 0, 0, 0]

hero_atlas := sprite.grid(pixel_art(48, 16, hero_px), 12, 16)
hero_atlas.add_animation("repos", sprite.Animation(hero_atlas.frames_range(0, 0), 1))
hero_atlas.add_animation("course", sprite.Animation(hero_atlas.frames_range(0, 3), 10))
hero_atlas.add_animation("saut", sprite.Animation(hero_atlas.frames_range(1, 1), 1, "once"))

# ---- niveau généré ----
carte := tilemap.TileMap(160, 30, T, T)
ts := tilemap.Tileset({"name": "demo", "tilewidth": T, "tileheight": T, "tilecount": 4, "columns": 4}, 1, "")
ts.texture = tiles_tex
carte.add_tileset(ts)
sol := carte.add_tile_layer("sol")
pieces := carte.add_tile_layer("pieces")
x := 0
haut := 24
while x < 160:
    if x % 23 == 0 and x > 10:
        haut = 20 + (x * 7) % 6
    if not (x % 37 > 33):
        y := haut
        sol.set(x, y, 2)
        y += 1
        while y < 30:
            sol.set(x, y, 1)
            y += 1
    if x % 11 == 5 and x + 4 < 160:
        k := 0
        while k < 4:
            sol.set(x + k, haut - 5, 3)
            k += 1
        pieces.set(x + 1, haut - 7, 4)
        pieces.set(x + 2, haut - 7, 4)
    x += 1
rendu := tilemap.MapRenderer(carte)

# ---- joueur, effets, caméra, son, manette ----
hero := sprite.Sprite(hero_atlas, [40.0, 100.0])
hero.origin = [0.5, 1.0]
hero.play("repos")
pos := [40.0, 100.0]
vel := [0.0, 0.0]
au_sol := false
score := 0
fx := particles.ParticleSystem()
cam := scene.Camera2D(w.width / ZOOM, w.height / ZOOM)
son := rt.AudioEngine()
s_saut := son.sound(audio.tone(520, 0.08).samples)
s_piece := son.sound(audio.tone(1040, 0.1).samples)
manette := null
try:
    manette = gp.open_first()
    print("Manette : " + manette.pad.name)
catch e:
    manette = null

while w.is_open():
    for e in w.poll():
        if e["type"] == "key_down" and e["key"] == "escape":
            w.close()
    if not w.is_open():
        break
    dt := w.dt if w.dt > 0.0 and w.dt < 0.05 else 1.0 / 60.0
    gauche := w.key_down("left") or w.key_down("a") or w.key_down("q")
    droite := w.key_down("right") or w.key_down("d")
    saut := w.key_down("space") or w.key_down("up") or w.key_down("w") or w.key_down("z")
    if manette != null:
        manette.poll()
        st := manette.pad.left_stick()
        gauche = gauche or st[0] < -0.3 or manette.pad.is_down("dpad_left")
        droite = droite or st[0] > 0.3 or manette.pad.is_down("dpad_right")
        saut = saut or manette.pad.is_down("a")
    cible := 0.0
    if gauche:
        cible = -110.0
        hero.flip_x = true
    if droite:
        cible = 110.0
        hero.flip_x = false
    vel[0] += (cible - vel[0]) * math.min(1.0, dt * 12.0)
    if saut and au_sol:
        vel[1] = -300.0
        son.play(s_saut, 0.5)
        fx.add(particles.Emitter(particles.preset("dust"), [pos[0], pos[1]]))
    vel[1] += 900.0 * dt
    res := carte.move(sol, [pos[0] - 5.0, pos[1] - 15.0, 10.0, 15.0], vel[0] * dt, vel[1] * dt)
    rect := res["rect"]
    pos = [rect[0] + 5.0, rect[1] + 15.0]
    if res["hit_y"]:
        if vel[1] > 250.0:
            fx.add(particles.Emitter(particles.preset("dust"), [pos[0], pos[1]]))
            if manette != null:
                try:
                    manette.pad.rumble(0.6, 0.3, 0.15)
                catch e:
                    pass
        vel[1] = 0.0
    if res["hit_x"]:
        vel[0] = 0.0
    au_sol = res["on_ground"]
    if pos[1] > 30 * T + 50:
        pos = [40.0, 100.0]
        vel = [0.0, 0.0]
    t := carte.world_to_tile(pos[0], pos[1] - 8.0)
    if pieces.gid(t[0], t[1]) == 4:
        pieces.set(t[0], t[1], 0)
        score += 1
        son.play(s_piece, 0.4)
        e := particles.Emitter(particles.preset("sparks"), [t[0] * T + 8.0, t[1] * T + 8.0])
        e.config["gravity"] = [0, 300]
        fx.add(e)
    hero.position = pos
    if not au_sol:
        hero.play("saut")
    elif math.abs(vel[0]) > 20.0:
        hero.play("course")
    else:
        hero.play("repos")
    hero.update(dt)
    fx.update(dt)
    rendu.update(dt)
    son.update()

    cam.viewport = [w.width / ZOOM, w.height / ZOOM]
    cam.position = [pos[0], math.min(pos[1] - 20.0, 30 * T - cam.viewport[1] * 0.5)]
    r.begin_frame([0.45, 0.7, 0.95, 1.0])
    batch.begin(cam)
    vue := [cam.position[0] - cam.viewport[0] * 0.5, cam.position[1] - cam.viewport[1] * 0.5, cam.viewport[0], cam.viewport[1]]
    rendu.draw(batch, vue)
    hero.draw(batch)
    fx.draw(batch)
    batch.end()
    batch.begin()
    i := 0
    while i < score and i < 40:
        batch.circle(20.0 + i * 18.0, 20.0, 7.0, [1.0, 0.82, 0.25, 1.0])
        i += 1
    batch.end()
    w.swap()
    if w.frame_count % 30 == 0:
        w.set_title("ALEX — plates-formes 2D — " + str(math.round(w.fps)) + " img/s — pièces : " + str(score))
son.close()
if manette != null:
    manette.close()
