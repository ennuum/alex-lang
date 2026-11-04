# Animation 3D et ressources : animation, gl.render.ModelRenderer, JPEG, DDS / KTX2, assets

| Module | Rôle | Tests |
|---|---|---|
| `animation` | modèles glTF complets, squelettes, clips, échantillonnage, mélange par canal, fondus, couches masquées et additives, cinématique inverse, morphing | `tests/gamedev/test_animation.al` |
| `gl.render` (ajouts) | `ModelRenderer` : skinning et morphing (128 cibles) dans le shader ; `load_cubemap`, `Skybox` | `tests/gamedev/test_gl_assets.al` |
| `mesh` (ajouts) | accesseurs glTF « sparse », `load_gltf_document`, `gltf_accessor` | `tests/gamedev/test_mesh.al` |
| `multimedia.image.jpeg` | JPEG séquentiel, progressif, arithmétique, sans perte, 12 bits, CMYK / YCCK, orientation Exif | `tests/gamedev/test_jpeg.al` |
| `gl.textures` | DDS et KTX2 : 2D, cubemaps, tableaux, volumes ; BC1..BC7, ETC2 / EAC, ASTC ; zlib et zstd | `tests/gamedev/test_gl_assets.al` |
| `office.compression` (ajout) | décompression Zstandard native | `tests/office/test_zstd.al` |
| `assets` | cache, références, chargement en arrière-plan (fils, modèles compris), rechargement à chaud, chargeurs personnalisés | `tests/gamedev/test_assets.al` |

Démo : `./alex run examples/gamedev/animation_demo.al` (tentacule à 8 os construit dans le code, deux clips
mélangés avec Espace, bras glTF animé, sol texturé par un JPEG chargé en arrière-plan et surveillé).
Tests GPU : `make test-gl` (Xvfb + Mesa).

## Animation squelettique

```alex
use animation
use gl.render as gr
use math3d as m3

modele := animation.load_gltf("perso.glb")
anim := animation.Animator(modele)
rendu := gr.ModelRenderer(r, modele)             # r : gl.render.Renderer ; textures glTF chargées (PNG, JPEG...)
anim.play("idle")
anim.on_end = (a, clip) => print("fin de " + clip)

# chaque image
anim.play("run", 0.2)                            # fondu enchaîné de 0,2 s (sans effet si déjà en cours)
anim.blend([["walk", 1.0 - k], ["run", k], ["sourire", 1.0]])   # mélange piloté (corps + visage)
anim.update(dt)
rendu.draw(anim, m3.mat4_translation(x, 0, z))
main := anim.node_position("hand_r")             # attacher une arme, une caméra...
```

- Import glTF 2.0 (.gltf avec .bin ou données intégrées, .glb) : hiérarchie, TRS ou matrices, maillages
  (positions, normales, UV, indices), `JOINTS_0` / `WEIGHTS_0`, skins (os, matrices de liaison inverses), cibles de
  morphing (positions, normales, accesseurs « sparse »), poids par défaut, clips (translation, rotation, échelle,
  poids ; interpolations STEP, LINEAR avec slerp, CUBICSPLINE), matériaux (couleur de base, texture, émissif, double
  face, transparence), images (fichiers ou intégrées au .glb).
- Mélange : chaque canal ne mélange que les pistes qui l'animent ; poids ramenés à 1 au-delà, complétés par la pose
  de repos en dessous ; rotations par nlerp avec alignement des signes. `sync_phase()` cale les cycles (marche /
  course). `play(nom, fondu, boucle, vitesse)`, `stop(fondu)`, `speed` global.
- Calcul en code natif : échantillonnage des canaux (clé mémorisée, slerp, Hermite), mélange pondéré par canal
  (`anim_sample`, `anim_resolve`, `anim_additive`), puis matrices monde et matrices d'os (`anim_skin`). Mesuré :
  60 os, 0,2 ms par image avec une piste, 0,8 ms avec deux pistes mélangées.
- GPU : les matrices d'os sont envoyées dans une texture RGBA32F (aucune limite pratique du nombre d'os) ; le shader
  fait le skinning à 4 influences. Les écarts de morphing (positions et normales) sont dans une seconde texture
  flottante lue par `gl_VertexID` : jusqu'à 128 cibles actives par primitive.
- `animation.skinned_position(primitive, sommet, animateur)` : position d'un sommet déformé (vérifications,
  sélection).

### Couches, masques, animations additives

```alex
haut := animation.bone_mask(modele, ["spine_02"])          # l'os et ses descendants (poids 0..1 par os)
anim.play("courir")                                          # pistes de base : tout le corps
anim.set_layer("tir", "viser", 1.0, haut, false, 0.2)        # le haut du corps vise, fondu de 0,2 s
anim.set_layer("souffle", "respirer", 0.6, null, true)       # additive : écart avec l'instant ref_time ajouté
anim.clear_layer("tir", 0.3)                                 # sortie en fondu, couche supprimée ensuite
```

- `set_layer(nom, clip, poids, masque, additive, fondu, boucle, vitesse, ref_time)` : les couches s'appliquent dans
  l'ordre, au-dessus des pistes de base. Une couche remplaçante mélange vers son clip selon `poids x masque` ; une
  couche additive ajoute la différence avec la pose de référence (translation : écart pondéré ; rotation :
  `conj(ref) x q`, interpolée depuis l'identité ; échelle : rapport).
- Un masque est un `ffi.Buffer` (un poids par nœud) : `bone_mask(modele, os, poids, avec_enfants)` ; il s'applique
  aussi à une piste de base (`anim.tracks[i].mask`).

### Cinématique inverse et orientation (après `update`)

```alex
anim.update(dt)
anim.ik_two_bone("upperarm_r", "lowerarm_r", "hand_r", poignee, coude_vers)   # bras, jambes ; pole = plan de pliage
reste := anim.ik_ccd(["tail_0", "tail_1", "tail_2", "tail_3"], cible, 10)     # chaînes longues
anim.look_at("head", camera, [0.0, 0.0, 1.0], 0.7)                            # tête, yeux, tourelle (poids)
```

- `ik_two_bone` est analytique (longueurs conservées ; cible hors d'atteinte : membre tendu vers elle). `ik_ccd`
  rend la distance restante. Les trois acceptent un poids 0..1. Aides : `local_trs(i)`, `set_local_rotation(i, q)`,
  `world_rotation(i)`, `world_matrix(i)`.

## Images et textures

### JPEG

- `multimedia.image.decode` et `gl.render.load_texture("x.jpg")` décodent : séquentiel de base et étendu,
  progressif, codage de Huffman ou **arithmétique** (SOF9 / SOF10, conditionnement DAC), précision **12 bits**
  (ramenée à 8), **sans perte** (SOF3, prédicteurs 1 à 7, transformation ponctuelle, 2 à 16 bits), intervalles de
  reprise, gris, YCbCr, RGB, **CMYK et YCCK** (marqueur Adobe), tout sous-échantillonnage.
- Tout le calcul est natif : 1024 x 768 en 0,3 s (progressif Huffman), 0,29 s (arithmétique), 0,21 s (sans perte).
  Écart avec libjpeg-turbo : 0,32 / 255 en moyenne ; sans perte : identique au pixel près.
- **Orientation Exif** : `jpeg.decode_rgba(octets, null, true)` (ou `jpeg.decode(..., true)`) tourne / retourne
  l'image (8 orientations, natif) ; les textures (`load_texture`, `texture_from_bytes`, `assets`) l'appliquent
  toujours. `r["info"]` décrit le fichier (`process`, `coding`, `precision`, `colorspace`, `exif_orientation`) ;
  `jpeg.orient_rgba(tampon, l, h, o)` sert pour d'autres sources.
- Refusés : JPEG hiérarchique (SOF5..7, SOF13..15) et sans perte arithmétique (SOF11), absents en pratique.

### DDS / KTX2

- `gl.render.load_texture("x.dds" | "x.ktx2")` : blocs envoyés tels quels à la carte avec les mipmaps du fichier.
  - Formes : 2D, **cubemaps** (`glTexImage2D` par face), **tableaux 2D**, **tableaux de cubemaps** (OpenGL 4.0+),
    **volumes** 3D. L'objet rendu a `shape` (`"2d"`, `"cube"`, `"2d_array"`, `"cube_array"`, `"3d"`), `layers`,
    `faces`, `depth`, `target` et `read_rgba(niveau, face)` (relecture décompressée par le pilote).
  - Formats : BC1..BC5 (unorm et snorm), **BC6H** (HDR), BC7 ; **ETC2 / EAC** (RGB8, RGB8A1, RGBA8, R11, RG11, sRGB) ;
    **ASTC** LDR de 4x4 à 12x12 (sRGB compris) ; RGBA8 / BGRA8, RGBA16F, RGBA32F.
  - KTX2 sans supercompression, zlib ou **zstd** (décodeur natif d'`office.compression` : environ 80 Mo/s).
  - Si le pilote n'a pas S3TC, BC1..BC3 sont décodés par le processeur (image par image, toutes formes). ETC2 / EAC
    demandent OpenGL 4.3 ou `GL_ARB_ES3_compatibility`, ASTC `GL_KHR_texture_compression_astc_ldr` : sinon erreur
    claire.
- `gl.textures.info(chemin)` décrit un fichier sans le charger ; `gl.render.texture_from_bytes(octets)` sert aux
  textures intégrées (PNG, JPEG, DDS, KTX2...).
- **Basis Universal** (KTX2 BasisLZ / ETC1S / UASTC) est refusé avec une explication : c'est un format intermédiaire
  qui doit être transcodé par le transcodeur de Binomial (non inclus). Convertir les fichiers à l'avance en BC7, ASTC
  ou ETC2 (`toktx`, `basisu`).

### Ciel

```alex
ciel := gr.Skybox(r, gr.load_cubemap("ciel.ktx2"))          # ou 6 images : +X, -X, +Y, -Y, +Z, -Z
ciel = gr.Skybox(r, gr.load_cubemap(["px.jpg", "nx.jpg", "py.jpg", "ny.jpg", "pz.jpg", "nz.jpg"]))
# chaque image, après les objets opaques
ciel.draw()
```

La cubemap est dessinée à la profondeur maximale, sans la translation de la caméra ; filtrage sans coutures
(`GL_TEXTURE_CUBE_MAP_SEAMLESS`). `gl.textures.cubemap_from_rgba(faces)` crée une cubemap depuis des pixels.

## Gestionnaire de ressources

```alex
use assets
am := assets.AssetManager("data")
am.audio = moteur_audio              # sons rééchantillonnés à la fréquence du moteur
am.renderer = r                      # modèles : asset.extra = gl.render.ModelRenderer
fond := am.load_async("decor/fond.jpg")
musique := am.load_async("musique/theme.ogg")
heros := am.load_async("perso.glb")  # analysé et construit dans un fil
carte := am.get("niveaux/1.tmx")     # synchrone
am.watch(true)                       # rechargement à chaud
while jeu:
    am.update()                      # 4 ms au plus par image pour finaliser
    if fond.ready(): ...
```

- Types d'après l'extension : texture, sound, model, mesh, tilemap, atlas (option `texture`), json, text, bytes ;
  `register(type, chargeur, libération)` pour les vôtres.
- Arrière-plan : décodage PNG / BMP / PNM / JPEG, lecture DDS / KTX2, décodage WAV / Ogg Vorbis, analyse JSON et
  cartes Tiled, **modèles glTF et OBJ complets** dans une réserve de fils (`workers`, 2 par défaut). Les objets ne
  passent pas d'un fil à l'autre : le fil rend une description en valeurs simples (`animation.model_to_dict`), que
  `update(budget)` recrée sur le fil principal (`model_from_dict`) avant l'envoi à la carte graphique.
- Plus besoin de `if thread.is_main():` dans le programme principal : les fils de la réserve n'exécutent que les
  fonctions de chargement d'`assets`. Sous Linux un fil est une copie du processus ; sous Windows (fils = processus)
  seuls les modules importés sont initialisés, pas le code de haut niveau du programme. La garde reste nécessaire
  pour `thread.spawn` / `ThreadPool` appliqués à une fonction écrite dans le programme principal lui-même.
- `progress()` (écran de chargement), `pending_count()`, `release(chemin)` (compteur de références), `stats()`,
  `reload(chemin)`, `check_reload()`, `asset.on_ready(fn)`, `asset.on_reload(fn)`, `asset.version`,
  `asset.wait()`. Un échec en arrière-plan donne `asset.state == "error"` et `asset.error`, sans exception.

## Fichiers de test

`tests/gamedev/data/mkjpeg_ref.py` (JPEG arithmétiques, sans perte, 12 bits, CMYK, YCCK, Exif, produits par
libjpeg-turbo 3 et décodés par elle pour les références), `tests/gamedev/data/mktex_ref.py` (DDS / KTX2 : cubemaps,
tableaux, volumes, ETC2, EAC, ASTC, zstd, Basis), `tests/office/data/zstd/mkzstd_ref.py` (flux libzstd).
Ces outils Python servent seulement à régénérer les données.

## Limites connues

- Pas de « root motion » automatique ni de compression des clips ; l'IK ne gère pas de contraintes d'angle
  (articulations) : la limiter avec le poids ou corriger la rotation ensuite.
- JPEG hiérarchique et sans perte arithmétique refusés ; 12 bits et sans perte au-delà de 8 bits ramenés à 8 bits.
- ASTC HDR, Basis Universal, PVRTC refusés ; pas de décodage logiciel d'ETC2 / ASTC (le pilote doit les gérer).
- zstd : pas de dictionnaires.
