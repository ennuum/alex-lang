# Rendu GPU et son en temps réel : gl, gl.window, gl.render, audio.realtime, audio.vorbis

Ces modules donnent aux jeux ALEX un rendu **par la carte graphique** (OpenGL 3.3 core) et un **son à faible latence**
mixé en continu. Ils remplacent, pour les jeux, le pipeline logiciel de `graphics` (environ 4 s par image pour un cube en
640 x 360) et la lecture par programme externe d'`audio` (`aplay`, `ffplay`).

| Module | Rôle | Tests |
|---|---|---|
| `gl` | fonctions OpenGL (noms C), constantes, chargement des adresses, aides (shaders, tampons) | `tests/gamedev/test_gl.al` |
| `gl.window` | fenêtre native + contexte OpenGL (Win32/WGL, X11/GLX), clavier, souris, VSync, plein écran | `tests/gamedev/test_gl.al` |
| `gl.render` | maillages GPU, textures, matériaux, éclairage, brouillard, scène, cibles de rendu, sprites 2D par lots | `tests/gamedev/test_gl.al` |
| `audio.realtime` | sortie directe (waveOut / ALSA), mixage natif, voix, groupes, fondus, son 3D | `tests/gamedev/test_audio_realtime.al` |
| `audio.vorbis` | décodage Ogg Vorbis (libvorbisfile ou décodeur ALEX) | `tests/gamedev/test_vorbis.al` |
| `ffi` (étendu) | Windows x64, arguments sur la pile, flottants, pointeurs de fonctions, tableaux en bloc | `tests/gamedev/test_ffi_ext.al`, `tests/ffi/test_ffi.al` |

Démo : `./alex run examples/gamedev/gpu_demo.al` (ZQSD/WASD, souris, Espace, F, V, Tab, Échap).

## Exemple minimal

```alex
use gl.window as glw
use gl.render as gr
use audio.realtime as rt
use mesh
use math3d as m3

w := glw.Window("Jeu", 1280, 720)
r := gr.Renderer(w)
cube := gr.GpuMesh(mesh.box(1, 1, 1))
rouge := gr.Material([0.9, 0.2, 0.2, 1.0])
hud := gr.SpriteBatch(r)
son := rt.AudioEngine()
saut := son.load("saut.wav")

while w.is_open():
    for e in w.poll():
        if e["type"] == "key_down" and e["key"] == "space":
            son.play(saut, 0.8)
    son.update()                                    # une fois par image
    r.begin_frame([0.1, 0.1, 0.15, 1.0])
    r.set_perspective(m3.radians(60), [0, 2, 5], [0, 0, 0])
    r.draw(cube, m3.mat4_rotation_y(w.time()), rouge)
    hud.begin()
    hud.rect(10, 10, 200, 16, [0.2, 0.9, 0.3, 1.0])
    hud.end()
    w.swap()
son.close()
```

## gl.render en bref

- `Renderer(window)` : `begin_frame(couleur)`, `set_perspective(fov, œil, cible)`, `set_camera(scene.Camera)`,
  `set_view_projection(vue, proj, œil)`, `draw(GpuMesh, Mat4, Material)`, `draw_scene(scene.Scene)` (opaques puis
  transparents triés), `set_ambient`, `set_sun`, `add_point_light` (8 au plus), `set_fog`, `set_wireframe`, `stats`.
- `GpuMesh(mesh.Mesh)` ; `Texture(l, h, octets, canaux)`, `load_texture("x.png")`, `texture_from_image(img)`,
  `solid_texture`, `checker_texture` ; `Material(couleur, texture, spéculaire, brillance, unlit, émissif)` avec
  `uv_rect` (répétition, atlas), `double_sided`, transparence automatique si alpha < 1.
- `SpriteBatch(renderer)` : `begin()` (pixels, origine en haut à gauche, ou une `scene.Camera2D`), `draw(texture ou
  Region, x, y, l, h, couleur, rotation, origine, flip_x, flip_y)`, `rect`, `rect_outline`, `line`, `circle`, `end()`.
  `Region` / `grid_regions` découpent une feuille de sprites. Un appel de dessin par changement de texture.
- `RenderTarget(l, h)` : `begin(couleur)` / `end(window)`, puis `.texture` utilisable partout.
- Shaders personnels : `gr.Shader(source_sommets, source_fragments)` (GLSL 330) et toutes les fonctions `gl.gl*`.

## audio.realtime en bref

- `AudioEngine(rate=44100, period=512, latency=0.06, backend=null)` : dorsal `waveout` (Windows), `alsa` (Linux), sinon
  `null` (silencieux, au rythme de l'horloge ; `engine.error` dit pourquoi).
- `load("x.wav" | "x.ogg")`, `sound(flottants, canaux)` → `Sound` ; `play(son, volume, pan, boucle, groupe)` →
  `Voice` (`stop`, `pause`, `resume`, `set_volume`, `set_pan`, `fade_to`, `fade_out`, `seek`, `set_position`, `on_end`).
- `set_group_volume("music", 0.4)`, `set_master_volume`, `stop_all`, `pause_all`, `set_listener(position, avant)`.
- **`update()` à chaque image.** La carte son garde `latency` secondes d'avance, ce qui absorbe une image lente.
- Le mixage, le rééchantillonnage et la conversion 16 bits sont en code natif dans la VM (`audio_mix`, `audio_out`,
  `audio_resample`) : quelques appels par bloc, quel que soit le nombre d'échantillons.

## audio.vorbis

`load_pcm16(chemin)` utilise **libvorbisfile** si elle est présente (Linux : `libvorbisfile.so.3` ; Windows : placer
`vorbisfile.dll` ou `libvorbisfile-3.dll` à côté du programme), sinon le **décodeur ALEX** (Vorbis I complet : livres de
codes, floor 1, résidus 0/1/2, couplage, fenêtres). Le décodeur ALEX donne les mêmes échantillons que ffmpeg à ±1 près ;
l'IMDCT, la courbe de floor, la fenêtre et le recouvrement sont en code natif, le décodage de Huffman en ALEX. Compter
de 0,3 à 0,9 seconde de calcul par seconde de son selon le débit : préférer le WAV pour les bruitages, décoder les
musiques au chargement. `ALEX_VORBIS=alex` force le décodeur ALEX.

## Modifications du runtime et du compilateur

- **ffi** (`runtime/vm/vm.al`, `stdlib/ffi/ffi.al`) : Windows x64 (LoadLibraryA / GetProcAddress, appel par
  `__mscall`) ; System V : arguments au-delà de 6 entiers / 8 flottants passés sur la pile (16 au plus) ;
  `function_at`, `Library.address`, `peek` / `poke` / `peek_bytes`, `Buffer.write_array` / `read_array` natifs (dont le
  type `pcm16`), `Buffer.copy_from`. Nouvelles natives : `bind_addr`, `symbol_address`, `buf_write_array`,
  `buf_read_array`, `buf_copy`, `ptr_read`, `ptr_write`, `ptr_read_bytes`, `audio_*`.
- **Appel Windows** (`src/native/codegen_x64.al`, `lower.al`) : `__mscall` copie aussi les 4 premiers arguments dans
  xmm0..xmm3 (convention x64 pour les flottants) ; nouveau `__mscall_f` qui rend xmm0.
- **Sortie du processus** (`codegen_x64.al`) : `exit_group` au lieu de `exit` sous Linux x86-64 ; un programme qui avait
  ouvert un contexte OpenGL ne se terminait plus (fils du pilote encore vivants).
- `src/native/dyn_registry.al` (registre des natives) a été complété à la main avec les nouvelles fonctions de
  `_native_ffi` (ordre alphabétique conservé) ; vérifier avec `make nt-dyn-registry` avant de le régénérer.

## Limites connues

- **Windows** : le code WGL, waveOut et le passage des flottants est écrit selon la convention x64 mais n'a pas pu être
  exécuté pendant le développement (tests faits sous Linux, Xvfb + Mesa). Windows ARM64 : ffi refusé.
- Pendant le déplacement / redimensionnement d'une fenêtre Windows à la souris, la boucle du jeu est suspendue
  (boucle modale de Windows).
- Plein écran Windows = fenêtre sans bord à la taille de l'écran (pas de changement de mode vidéo).
- Pas encore : ombres, rendu instancié de haut niveau, texte dans `gl.render`, manettes XInput, MSAA sous Windows.
- Les objets dessinés coûtent environ 0,25 ms chacun côté ALEX (calcul des matrices, uniformes) : quelques centaines
  par image à 60 images/s. Regrouper les décors statiques dans un seul `GpuMesh`.
