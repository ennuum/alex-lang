# Modules de jeu : math3d, mesh, scene, physics (+ physics2d, spatial), ecs, gameloop, ai

Sept modules ALEX purs (plus deux sous-modules de `physics`) pour construire des jeux 2D et 3D, à placer dans `stdlib/<module>/<module>.al`.
Ils se combinent avec `graphics`, `window`, `input` et `audio`, déjà présents dans la stdlib.

| Module | Rôle | Tests |
|---|---|---|
| `math3d` | vecteurs, quaternions, Mat3/Mat4, plans, AABB, frustum | `tests/gamedev/test_math3d.al` |
| `mesh` | maillages, primitives, import/export OBJ, import glTF/GLB | `tests/gamedev/test_mesh.al` |
| `scene` | graphe de scène, caméras, lumières, culling, picking, Camera2D | `tests/gamedev/test_scene.al` |
| `physics` | formes, collisions, corps rigides, raycasts, déclencheurs, détection continue, articulations | `tests/gamedev/test_physics.al` |
| `physics.physics2d` | physique 2D : cercle/boîte/polygone, SAT, solveur, articulations, CCD, raycasts | `tests/gamedev/test_physics2d.al` |
| `physics.spatial` | hachage spatial 3D (requêtes de boîte, sphère, rayon ; paires) et phase large | `tests/gamedev/test_spatial.al` |
| `ecs` | entités, composants, systèmes, hiérarchie, préfabriqués | `tests/gamedev/test_ecs.al` |
| `gameloop` | pas fixe, minuteries, planificateur, tweens | `tests/gamedev/test_gameloop.al` |
| `ai` | A* (grille et graphe), FSM, arbres de comportement, steering | `tests/gamedev/test_ai.al` |
| `gl`, `gl.window`, `gl.render` | rendu par la carte graphique (OpenGL 3.3), sprites 2D par lots — voir `docs/GPU_AUDIO.md` | `tests/gamedev/test_gl.al` |
| `audio.realtime`, `audio.vorbis` | son temps réel mixé en natif, Ogg Vorbis — voir `docs/GPU_AUDIO.md` | `tests/gamedev/test_audio_realtime.al`, `test_vorbis.al` |
| `sprite`, `tilemap`, `particles`, manettes XInput | atlas et animations, cartes Tiled, particules, vibration — voir `docs/OUTILS_2D.md` | `test_sprite_particles.al`, `test_tilemap.al`, `test_gl2d.al`, `test_canvas2d.al`, `test_gamepad_xinput.al` |
| `animation`, JPEG, DDS / KTX2, `assets` | squelettes, mélange, couches masquées / additives, IK, morphing ; JPEG complet ; cubemaps, ciel, ETC2 / ASTC, zstd ; gestionnaire de ressources — voir `docs/ANIMATION_RESSOURCES.md` | `test_animation.al`, `test_jpeg.al`, `test_assets.al`, `test_gl_assets.al` |
| `netgame` (+ `.codec`, `.snapshot`, `.prediction`, `.rollback`) | multijoueur sur UDP : connexion fiable / non fiable, instantanés delta interpolés, prédiction client, rollback — voir `docs/RESEAU_JEU.md` | `test_netgame.al`, démo `net_demo.al` |
| `ai` (navmesh 3D) | maillage de navigation, A* sur triangles, entonnoir, lissage, coûts, blocage | `tests/gamedev/test_navmesh.al` |

Lancer un test : `./alex run tests/gamedev/test_physics.al` (ou `make test-gamedev` pour toute la suite). Démo complète : `./alex run examples/gamedev/game3d_demo.al`.

## Conventions à connaître

- **Ordre des matrices.** `math3d` stocke les Mat4 **par colonne** (comme OpenGL/glTF) ; `graphics.shader` les attend
  **par ligne**. Pour passer une matrice à un shader : `math3d.mat4_transpose(m)`. Vérifié dans `tests/gamedev/test_math3d.al`.
- **Repère** : main droite, Y vers le haut, l'avant d'une caméra est -Z. Unités SI pour `physics`.
- **Les modules ne dessinent pas** (sauf l'exemple) : `scene` décide quoi dessiner (`render_list`), `graphics` dessine.
- **Notation méthode sur un dict** : dans le code de la stdlib, écrire `keys(d)` (après `from collections use keys`)
  et non `d.keys()`, qui échoue tant qu'aucun autre module n'a chargé `collections.hash_map`.

## Ce qui a été ajouté pour lever les limites

- **Détection continue** (`physics`) : un corps dynamique qui parcourt, en un sous-pas, plus que son rayon de cœur est
  balayé le long de sa trajectoire et arrêté au premier contact, au lieu de traverser un mur mince. Actif par défaut
  (`World.ccd`, `Body.continuous`). Même mécanisme dans `physics2d`.
- **Articulations** (`physics`, `physics2d`) : `ball_joint`, `hinge_joint` (limites, moteur), `distance_joint` (tige, corde),
  `spring_joint`, `fixed_joint`, `slider_joint` (3D) ; pivot, soudure, distance et ressort (2D). Contraintes de point et
  d'orientation résolues en bloc (matrice 3x3 ou 2x2 inversée), limites spéculatives (sans dépassement ni rebond), rupture
  (`break_force`), îlots d'endormissement, pas de collision entre corps reliés par défaut.
- **`physics.spatial`** : `SpatialHash` (insertion, mise à jour, requêtes `query_aabb`, `query_sphere`, `query_ray`, `pairs`).
  `physics` s'en sert comme phase large au-delà de 48 corps (`World.broadphase = "auto" | "sweep" | "hash"`).
- **`physics.physics2d`** : monde 2D complet (voir l'en-tête du fichier).
- **Navmesh 3D** (`ai.NavMesh`, `ai.navmesh_from_mesh`) : filtre de pente, `find_path` (A* sur triangles + entonnoir +
  lissage), `closest_point`, `height_at`, `raycast` / `line_of_sight`, `random_point`, `set_cost`, `block`, `block_region`.
- **Performances** : solveur d'impulsions réécrit en calcul scalaire (mêmes résultats, environ 4,5 fois plus rapide sur le
  solveur) ; la suite `test_physics.al` passe de 15 s à 5 s alors qu'elle contient désormais deux fois plus de tests.

## Limites connues

- Détection continue : les autres corps sont considérés immobiles pendant le sous-pas et la rotation n'est pas balayée ;
  pas de mailles triangulaires dynamiques (`raycast_mesh` sert aux requêtes) ; effet gyroscopique ignoré.
- Articulations : les angles de charnière sont mesurés dans ]-π, π] (des limites au-delà d'un demi-tour ne sont pas
  représentables) ; pas de glissière ni de capsule en 2D ; pas de polygones concaves en 2D (assembler des corps soudés).
- Navmesh : construit depuis un maillage fourni (pas de voxelisation automatique d'une scène) ; rayon d'agent approché en
  reculant les portes (pas d'érosion exacte) ; pas de liens hors maillage (sauts, échelles) ; le lissage ne raccourcit
  pas à travers une zone de coût > 1 ni quand `agent_radius > 0`.
- Performances : l'interpréteur reste le facteur limitant. Ordre de grandeur mesuré : 9 corps, 120 pas en 2,8 s
  (contre 7,1 s avant optimisation) ; 90 pas de `game3d_demo.al` en 0,9 s ; le rendu logiciel n'atteint toujours pas le
  temps réel. Pour de grands mondes, utiliser l'endormissement, `substeps = 1` et la phase large par hachage.
