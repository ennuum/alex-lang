# Outils 2D et manettes : sprite, tilemap, particles, input.gamepad (XInput, vibration)

| Module | Rôle | Tests |
|---|---|---|
| `sprite` | atlas (grille, TexturePacker / Aseprite JSON), animations image par image, lecteur, sprites | `tests/gamedev/test_sprite_particles.al` |
| `tilemap` | cartes à tuiles, import Tiled `.tmj` / `.tmx` (+ `.tsj` / `.tsx`), collisions, rendu GPU par blocs | `tests/gamedev/test_tilemap.al` |
| `particles` | émetteurs, rafales, formes, gravité, courbes de taille / couleur, mélange additif, préréglages | `tests/gamedev/test_sprite_particles.al` |
| `gl.render` (ajouts) | `SpriteBatch.set_blend`, `SpriteBatch.draw_tile` (retournements), `QuadBuffer` (quads statiques) | `tests/gamedev/test_gl2d.al` |
| `ui.canvas` / `ui.image` (ajouts) | `canvas.image_region` (partie d'image), `image.crop`, `image.create`, `image.size` | `tests/gamedev/test_canvas2d.al` |
| `input.gamepad` (ajouts) | `XInputReader` (Windows), vibration XInput et evdev, `open_first` multiplateforme | `tests/gamedev/test_gamepad_xinput.al` |

Démo : `./alex run examples/gamedev/platformer_demo.al` (niveau, héros animé, pièces, poussière et étincelles,
caméra, son, manette). Rendu GPU vérifié sous Xvfb : `make test-gl` ; canvas : `ALEX_UI_BACKEND=headless`.

## sprite

```alex
use gl.render as gr
use sprite
atlas := sprite.grid(gr.load_texture("heros.png", "nearest", "clamp", false), 32, 32)
atlas.add_animation("course", sprite.Animation(atlas.frames_range(0, 5), 12))           # boucle, 12 img/s
atlas.add_animation("saut", sprite.Animation(atlas.frames_range(6, 9), 10, "once").on_frame(2, "envol"))
h := sprite.Sprite(atlas, [100, 200])
h.origin = [0.5, 1.0]                       # pieds
h.play("course")
h.player.on_event = (p, nom) => print(nom)  # événements d'images
# chaque image : h.update(dt) ; h.draw(batch)      (ou sprite.draw_canvas(canvas, h) avec une image ui)
```

- `sprite.load_atlas_json(chemin_ou_dict, texture)` : formats TexturePacker (« hash » et « array ») et Aseprite ; les
  `frameTags` d'Aseprite deviennent des animations (durées par image, sens avant / arrière / aller-retour). Les
  images rognées (trimmed) gardent leur décalage (`offset`, `source_size`). Les images tournées sont refusées.
- `Frame` se passe directement à `SpriteBatch.draw` ; `Sprite` gère échelle, rotation autour de l'origine,
  retournements, couleur, `bounds()`, `contains()` ; `sprite.draw_all(liste, batch)` trie par `depth`.

## tilemap

```alex
use tilemap
carte := tilemap.load("niveau1.tmx")                    # ou .tmj
rendu := tilemap.MapRenderer(carte)                     # textures des jeux de tuiles chargées (nearest)
sol := carte.layer("sol")
res := carte.move(sol, [x, y, 12, 30], vx * dt, vy * dt)   # {"rect", "hit_x", "hit_y", "on_ground", "on_ceiling"}
for o in carte.objects("ennemi"):
    creer(o["x"], o["y"], o["properties"])
# chaque image, batch commencé avec la caméra (scene.Camera2D) :
rendu.update(dt)
rendu.draw(batch, [gauche, haut, largeur, hauteur])     # seuls les blocs visibles sont dessinés
```

- Import : CSV, base64, base64 + zlib, base64 + gzip, tuiles XML `<tile gid>`, cartes infinies (blocs réunis en
  une couche), jeux de tuiles intégrés ou externes, couches de tuiles / d'objets / d'images, groupes (décalages et
  opacités cumulés), parallaxe, teinte, propriétés typées (int, float, bool, string, color, file, object), tuiles
  animées, objets rectangle / point / ellipse / polygone / polyligne / tuile / texte. Compression zstd : refusée.
- Rendu GPU : la carte est découpée en blocs de 32 x 32 tuiles ; chaque bloc est un `gl.render.QuadBuffer` envoyé
  une fois à la carte graphique (un appel de dessin par bloc et par jeu de tuiles) et reconstruit seulement quand une
  de ses tuiles change (`layer.set`). Les tuiles animées sont dessinées à chaque image.
- Orientations dessinées : orthogonale et isométrique. Décalée et hexagonale : données lues, dessin refusé.
- Collisions : `solid_rects` (rectangles fusionnés, à donner à `physics.physics2d` en corps statiques),
  `overlaps`, `move` (sous-pas d'une demi-tuile au plus : pas de traversée), filtre `solid(gid, propriétés)`.
- `tilemap.draw_canvas(canvas, carte, vue)` dessine sur un canvas ui (images ui, découpes en cache).

## particles

```alex
use particles
fx := particles.ParticleSystem()
fx.add(particles.Emitter(particles.preset("fire"), [400, 300]))
fx.add(particles.Emitter({"burst": 60, "duration": 0.0, "speed": [50, 200], "gravity": [0, 400],
                          "colors": [[0.0, [1.0, 1.0, 0.5, 1.0]], [1.0, [1.0, 0.2, 0.0, 0.0]]], "blend": "add"}, [x, y]))
# chaque image : fx.update(dt) ; fx.draw(batch)   (ou fx.draw_canvas(canvas))
```

Préréglages : `fire`, `smoke`, `explosion`, `sparks`, `rain`, `snow`, `dust`, `magic` (dicts modifiables). Les
émetteurs à rafale unique sont retirés du système quand leurs particules sont mortes. Quelques milliers de
particules à 60 images/s (mise à jour en ALEX) : préférer moins de particules plus grandes.

## Manettes

```alex
use input.gamepad as gp
m := gp.open_first()                  # XInputReader sous Windows, GamepadReader (evdev) sous Linux
# chaque image :
m.poll()
x := m.pad.left_stick()[0]
if m.pad.is_down("a"):
    sauter()
m.pad.rumble(0.8, 0.3, 0.2)           # fort, faible, durée (s)
```

- Windows : XInput (`xinput1_4.dll`, sinon `xinput1_3` / `xinput9_1_0`), manettes 0 à 3, branchement à chaud
  (`connected`). Les noms de boutons et d'axes sont ceux de Linux (`south`/`a`, `east`/`b`, `tl`/`lb`, `tl2`/`lt`,
  `dpad_*`, `start`, `select`), sticks dans la convention evdev (Y vers le bas positif). Vibration : `XInputSetState`,
  arrêt automatique après la durée (vérifié à chaque `poll`).
- Linux : vibration par le retour de force evdev (ioctl `EVIOCSFF`, effet `FF_RUMBLE`, puis événement `EV_FF`) sur le
  périphérique ouvert en écriture.
- `XInputReader` et `GamepadReader` ont `read(timeout)` (événements `InputEvent`) : utilisables par
  `input.input_manager` (`m.add_device(lecteur)` : la manette y est reconnue comme `gamepad`).

## Limites connues

- La lecture XInput a été testée avec une API simulée ; la vibration evdev n'a pas pu être essayée (pas de manette
  ici) : codes et structures du noyau Linux x86-64.
- Pas de manettes DirectInput / GameInput sous Windows (manettes non XInput : à brancher via Steam Input ou un
  pilote XInput).
- Canvas ui : `image_region` copie la zone une fois puis la garde en cache dans l'image ; le canvas reste dessiné par
  le processeur, donc plus lent que `gl.render` pour de grandes cartes.
