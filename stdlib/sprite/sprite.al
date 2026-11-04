# ALEX STANDARD LIBRARY — sprite
#
# Sprites 2D : atlas (grille régulière, TexturePacker / Aseprite JSON), animations image par image (boucle, une fois,
# aller-retour, durées par image, événements), lecteur d'animations et sprites positionnables (position, échelle,
# rotation, origine, retournements, couleur, profondeur). Indépendant du rendu : les images sont des
# gl.render.Texture (dessin par gl.render.SpriteBatch, GPU) ou des images ui (dessin par ui.canvas).
#
#   use gl.render as gr
#   use sprite
#   atlas := sprite.grid(gr.load_texture("heros.png", "nearest"), 32, 32)      # cases "0", "1", ...
#   atlas.add_animation("marche", sprite.Animation(atlas.frames_range(0, 5), 12))    # 12 images / s, en boucle
#   atlas.add_animation("saut", sprite.Animation(atlas.frames_range(6, 9), 10, "once"))
#   h := sprite.Sprite(atlas, [100, 200])
#   h.play("marche")
#   # à chaque image :
#   h.update(dt)
#   batch.begin() ; h.draw(batch) ; batch.end()             # gl.render.SpriteBatch
#   sprite.draw_canvas(canvas, h)                           # ou ui.canvas (gui)
#
#   a2 := sprite.load_atlas_json("heros.json", texture)      # TexturePacker (hash / array) ou Aseprite (+ tags)
#
# FRAME : zone d'une texture (x, y, w, h en pixels) + UV ; « offset » et « source_size » pour les atlas rognés
#   (trimmed) ; `duration` (s) facultative (Aseprite). Une Frame se passe telle quelle à SpriteBatch.draw (kind
#   « region »).
# ANIMATION : modes "loop", "once" (reste sur la dernière image), "pingpong" ; vitesse en images/s ou durées par
#   image ; `events` {indice: nom} déclenchés au passage.
#
# Erreurs : ValueError (données invalides), KeyError (image ou animation inconnue), IoError (fichier).

from core use len, type, to_int
from collections use append
use math
use json
use io
use path as _path
use ui.image as _uimg
use ui.canvas as _cv

# Taille [l, h] d'une texture GPU (gl.render.Texture) ou d'une image ui ({"handle"}).
func texture_size(tex):
    if type(tex) == "dict" and "handle" in tex:
        return _uimg.size(tex)
    return [tex.width, tex.height]

# ---------------------------------------------------------------------------------------------------------------------
# Images d'atlas
# ---------------------------------------------------------------------------------------------------------------------

class Frame:
    func init(texture, x, y, w, h, name="", tex_size=null):
        ts := tex_size if tex_size != null else texture_size(texture)
        self.kind = "region"
        self.name = name
        self.texture = texture
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.u0 = x * 1.0 / ts[0]
        self.v0 = y * 1.0 / ts[1]
        self.u1 = (x + w) * 1.0 / ts[0]
        self.v1 = (y + h) * 1.0 / ts[1]
        self.offset = [0, 0]              # position de la zone rognée dans l'image d'origine
        self.source_size = [w, h]
        self.duration = null              # secondes (atlas Aseprite)

# ---------------------------------------------------------------------------------------------------------------------
# Atlas
# ---------------------------------------------------------------------------------------------------------------------

class Atlas:
    func init(texture):
        self.texture = texture
        self.size = texture_size(texture)
        self.frames = {}
        self.order = []
        self.animations = {}

    # Ajoute une image nommée.
    func add(name, x, y, w, h):
        f := Frame(self.texture, x, y, w, h, name, self.size)
        if not (name in self.frames):
            append(self.order, name)
        self.frames[name] = f
        return f

    func frame(name):
        key := str(name)
        if not (key in self.frames):
            raise("KeyError", "sprite.Atlas : image inconnue '" + key + "'")
        return self.frames[key]

    # Images dans l'ordre d'ajout, de `first` à `last` inclus (indices).
    func frames_range(first, last):
        out := []
        k := first
        while k <= last and k < len(self.order):
            append(out, self.frames[self.order[k]])
            k += 1
        return out

    # Images dont le nom commence par `prefix`, triées par nom (« course_00 », « course_01 »...).
    func frames_prefixed(prefix):
        names := [n for n in self.order if len(n) >= len(prefix) and n[0:len(prefix)] == prefix]
        names = _sort_str(names)
        return [self.frames[n] for n in names]

    func add_animation(name, anim):
        self.animations[name] = anim
        return anim

    func animation(name):
        if not (name in self.animations):
            raise("KeyError", "sprite.Atlas : animation inconnue '" + str(name) + "'")
        return self.animations[name]

    # Remplit en grille : cases de fw x fh pixels, marge et espacement facultatifs ; noms "0", "1"... ligne par ligne.
    func fill_grid(fw, fh, margin=0, spacing=0, count=null):
        a := self
        cols := to_int((a.size[0] - 2 * margin + spacing) / (fw + spacing))
        rows := to_int((a.size[1] - 2 * margin + spacing) / (fh + spacing))
        if cols < 1 or rows < 1:
            raise("ValueError", "sprite.Atlas.grid : cases plus grandes que l'image")
        n := cols * rows
        if count != null and count < n:
            n = count
        k := 0
        while k < n:
            cx := k % cols
            cy := to_int(k / cols)
            a.add(str(k), margin + cx * (fw + spacing), margin + cy * (fh + spacing), fw, fh)
            k += 1
        return a

func _sort_str(items):
    out := []
    for it in items:
        k := len(out)
        append(out, it)
        while k > 0 and out[k - 1] > it:
            out[k] = out[k - 1]
            k -= 1
        out[k] = it
    return out

# Atlas en grille : cases de fw x fh pixels (noms "0", "1"... ligne par ligne).
func grid(texture, fw, fh, margin=0, spacing=0, count=null):
    return Atlas(texture).fill_grid(fw, fh, margin, spacing, count)

# Atlas JSON TexturePacker (« frames » en hash ou en tableau) ou Aseprite (durées par image et « frameTags »
# devenant des animations). `data` : chemin du .json ou dict déjà lu.
func load_atlas_json(data, texture):
    d := data
    if type(data) == "str":
        d = json.parse(io.read_file(data))
    a := Atlas(texture)
    fr := d["frames"]
    items := []
    if type(fr) == "list":
        for it in fr:
            append(items, [it["filename"] if "filename" in it else str(len(items)), it])
    else:
        for k in fr:
            append(items, [k, fr[k]])
    for it in items:
        e := it[1]
        r := e["frame"]
        if "rotated" in e and e["rotated"]:
            raise("ValueError", "sprite.load_atlas_json : images tournées (rotated) non prises en charge : '" + it[0] + "'")
        f := a.add(it[0], r["x"], r["y"], r["w"], r["h"])
        if "spriteSourceSize" in e:
            f.offset = [e["spriteSourceSize"]["x"], e["spriteSourceSize"]["y"]]
        if "sourceSize" in e:
            f.source_size = [e["sourceSize"]["w"], e["sourceSize"]["h"]]
        if "duration" in e:
            f.duration = e["duration"] / 1000.0
    meta := d["meta"] if "meta" in d else {}
    if "frameTags" in meta:
        for tag in meta["frameTags"]:
            frames := a.frames_range(tag["from"], tag["to"])
            dirn := tag["direction"] if "direction" in tag else "forward"
            mode := "pingpong" if dirn == "pingpong" else "loop"
            if dirn == "reverse":
                frames = [frames[len(frames) - 1 - k] for k in 0..len(frames)]
            durs := [f.duration if f.duration != null else 0.1 for f in frames]
            a.add_animation(tag["name"], Animation(frames, null, mode, durs))
    return a

# ---------------------------------------------------------------------------------------------------------------------
# Animations
# ---------------------------------------------------------------------------------------------------------------------

class Animation:
    # frames : list de Frame ; fps (images/s) ou durations (list de secondes) ; mode "loop" | "once" | "pingpong".
    func init(frames, fps=10, mode="loop", durations=null):
        if len(frames) == 0:
            raise("ValueError", "sprite.Animation : aucune image")
        if mode != "loop" and mode != "once" and mode != "pingpong":
            raise("ValueError", "sprite.Animation : mode inconnu '" + str(mode) + "'")
        self.frames = frames
        self.mode = mode
        if durations != null:
            if len(durations) != len(frames):
                raise("ValueError", "sprite.Animation : une durée par image attendue")
            self.durations = [d * 1.0 for d in durations]
        else:
            f := fps if fps != null and fps > 0 else 10
            self.durations = [1.0 / f for k in 0..len(frames)]
        self.events = {}

    # Événement `name` déclenché quand l'image `index` commence (pas, tir...).
    func on_frame(index, name):
        self.events[index] = name
        return self

    func total_duration():
        t := 0.0
        for d in self.durations:
            t += d
        return t

# Lecteur : image courante d'une animation selon le temps écoulé.
class AnimationPlayer:
    func init():
        self.animation = null
        self.name = null
        self.index = 0
        self.time = 0.0
        self.direction = 1
        self.speed = 1.0
        self.playing = false
        self.finished = false
        self.on_end = null              # fn(player) quand une animation « once » se termine
        self.on_event = null            # fn(player, nom_événement)

    func play(anim, name=null, restart=false):
        if anim == self.animation and not restart and not self.finished:
            self.playing = true
            return
        self.animation = anim
        self.name = name
        self.index = 0
        self.time = 0.0
        self.direction = 1
        self.playing = true
        self.finished = false
        self._fire(0)

    func stop():
        self.playing = false

    func _fire(i):
        if self.on_event != null and i in self.animation.events:
            self.on_event(self, self.animation.events[i])

    func update(dt):
        a := self.animation
        if a == null or not self.playing or self.finished:
            return
        self.time += dt * self.speed
        n := len(a.frames)
        guard := 0
        while self.time >= a.durations[self.index] and guard < 1000:
            self.time -= a.durations[self.index]
            guard += 1
            nxt := self.index + self.direction
            if nxt >= n or nxt < 0:
                if a.mode == "loop":
                    nxt = 0
                elif a.mode == "pingpong":
                    self.direction = 0 - self.direction
                    nxt = self.index + self.direction
                    if nxt < 0 or nxt >= n:
                        nxt = self.index
                else:
                    self.finished = true
                    self.playing = false
                    self.time = 0.0
                    if self.on_end != null:
                        self.on_end(self)
                    return
            self.index = nxt
            self._fire(nxt)

    func frame():
        if self.animation == null:
            return null
        return self.animation.frames[self.index]

# ---------------------------------------------------------------------------------------------------------------------
# Sprites
# ---------------------------------------------------------------------------------------------------------------------

class Sprite:
    # source : Atlas (animations nommées), Frame, ou texture entière.
    func init(source, position=null, frame=null):
        self.atlas = null
        self.frame = null
        if type(source) == "Atlas" or (type(source) != "dict" and _has_frames(source)):
            self.atlas = source
            if frame != null:
                self.frame = source.frame(frame)
            elif len(source.order) > 0:
                self.frame = source.frames[source.order[0]]
        elif _is_frame(source):
            self.frame = source
        else:
            ts := texture_size(source)
            self.frame = Frame(source, 0, 0, ts[0], ts[1], "", ts)
        self.position = position if position != null else [0.0, 0.0]
        self.scale = [1.0, 1.0]
        self.rotation = 0.0
        self.origin = [0.5, 0.5]          # fraction de l'image source (0, 0 = haut gauche)
        self.flip_x = false
        self.flip_y = false
        self.color = [1.0, 1.0, 1.0, 1.0]
        self.visible = true
        self.depth = 0.0
        self.player = AnimationPlayer()

    # Joue une animation de l'atlas (ou un objet Animation).
    func play(anim, restart=false):
        a := anim
        name := null
        if type(anim) == "str":
            if self.atlas == null:
                raise("KeyError", "Sprite.play : pas d'atlas pour l'animation '" + anim + "'")
            a = self.atlas.animation(anim)
            name = anim
        self.player.play(a, name, restart)
        self.frame = self.player.frame()

    func update(dt):
        self.player.update(dt)
        f := self.player.frame()
        if f != null:
            self.frame = f

    func set_frame(name):
        self.frame = self.atlas.frame(name)

    # Rectangle [x, y, l, h] occupé à l'écran (sans rotation) : collisions simples, sélection.
    func bounds():
        f := self.frame
        sw := f.source_size[0] * self.scale[0]
        sh := f.source_size[1] * self.scale[1]
        return [self.position[0] - sw * self.origin[0], self.position[1] - sh * self.origin[1], sw, sh]

    func contains(x, y):
        b := self.bounds()
        return x >= b[0] and y >= b[1] and x < b[0] + b[2] and y < b[1] + b[3]

    # Dessin dans un gl.render.SpriteBatch.
    func draw(batch):
        if not self.visible or self.frame == null:
            return
        f := self.frame
        sx := self.scale[0]
        sy := self.scale[1]
        sw := f.source_size[0] * sx
        sh := f.source_size[1] * sy
        ox := f.offset[0]
        if self.flip_x:
            ox = f.source_size[0] - f.offset[0] - f.w
        oy := f.offset[1]
        if self.flip_y:
            oy = f.source_size[1] - f.offset[1] - f.h
        x := self.position[0] - sw * self.origin[0] + ox * sx
        y := self.position[1] - sh * self.origin[1] + oy * sy
        w := f.w * sx
        h := f.h * sy
        org := null
        if self.rotation != 0.0:
            # pivot = origine du sprite, exprimée dans la zone rognée
            org = [(sw * self.origin[0] - ox * sx) / w, (sh * self.origin[1] - oy * sy) / h]
        batch.draw(f, x, y, w, h, self.color, self.rotation, org, self.flip_x, self.flip_y)

func _has_frames(x):
    try:
        return x.frames != null and x.order != null
    catch e:
        return false

func _is_frame(x):
    try:
        return x.kind == "region"
    catch e:
        return false

# Dessine des sprites triés par profondeur (croissante) dans un SpriteBatch.
func draw_all(sprites, batch):
    order := []
    for s in sprites:
        k := len(order)
        append(order, s)
        while k > 0 and order[k - 1].depth > s.depth:
            order[k] = order[k - 1]
            k -= 1
        order[k] = s
    for s in order:
        s.draw(batch)

# Dessin d'un sprite sur un canvas ui (gui) : la texture est une image ui. Rotation et retournements passent par la
# transformation du canvas.
func draw_canvas(canvas, s):
    if not s.visible or s.frame == null:
        return
    f := s.frame
    sx := s.scale[0]
    sy := s.scale[1]
    sw := f.source_size[0] * sx
    sh := f.source_size[1] * sy
    if s.rotation == 0.0 and not s.flip_x and not s.flip_y:
        x := s.position[0] - sw * s.origin[0] + f.offset[0] * sx
        y := s.position[1] - sh * s.origin[1] + f.offset[1] * sy
        _cv.image_region(canvas, f.texture, f.x, f.y, f.w, f.h, x, y, f.w * sx, f.h * sy, s.color[3])
        return
    c := math.cos(s.rotation)
    n := math.sin(s.rotation)
    fx := -1.0 if s.flip_x else 1.0
    fy := -1.0 if s.flip_y else 1.0
    px := s.position[0]
    py := s.position[1]
    _cv.transform(canvas, {"m11": c * fx, "m12": n * fx, "m21": 0.0 - n * fy, "m22": c * fy, "dx": px, "dy": py})
    _cv.image_region(canvas, f.texture, f.x, f.y, f.w, f.h, 0.0 - sw * s.origin[0] + f.offset[0] * sx, 0.0 - sh * s.origin[1] + f.offset[1] * sy, f.w * sx, f.h * sy, s.color[3])
    _cv.reset_transform(canvas)
