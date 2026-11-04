# ALEX UI V1.2 — Animation / Tweening avancé (`ui.tween`)

Moteur **non bloquant** (l'ancien `ui.animation` bloquant reste inchangé) : des *nœuds* d'animation sont
avancés par un *animateur*, normalement depuis `ui.state.run`.

```alex
use ui.state as state
use ui.tween as tw

state.animate(store, "x", 100.0, 0.5, null, "cubic_out")            # tween d'une clé d'état
state.spring(store, "x", 0.0, null, 170.0, 12.0)                     # ressort amorti (rebond)
node := tw.sequence([tw.tween(tw.target_state(store, "a"), 1.0, 0.3),
                     tw.wait(0.2),
                     tw.tween(tw.target_state(store, "a"), 0.0, 0.3)])
state.play(store, node)
state.run(win, store, render)       # avance l'animateur et ne redessine que si quelque chose a changé
```

## Nœuds
| | |
|---|---|
| `tween(cible, fin, durée, début=null, easing, delay, repeat, yoyo)` | nombre, couleur `{r,g,b[,a]}` ou list de nombres ; `début=null` = valeur courante de la cible ; `repeat=-1` = infini |
| `spring(cible, fin, début, stiffness, damping, mass, velocity, delay)` | ressort **analytique** (sous/critique/sur-amorti) ; se fige exactement sur la cible |
| `sequence`, `parallel`, `stagger(nœuds, each)`, `wait`, `call(fn, ctx)` | composition imbriquable |
| `callbacks(nœud, on_start, on_update, on_complete, ctx)` | `fn(event)`, `event = {node, value, progress, ctx, animator}` |

**Cibles** : `target_state(store,clé)`, `target_dict(widget_moderne_ou_thème, propriété)`,
`target_native(handle, "x"|"y"|"width"|"height"|"progress")` (+ `track_native` : les widgets natifs n'ont pas de
getter de géométrie), `target_fn(fn, ctx)`.

## Easing
Noms existants + `elastic_*`, `circ_*`, `back_in_out` ; paramétrés : `bezier(x1,y1,x2,y2)` (= CSS
`cubic-bezier`), `steps(n, jump)` (= CSS `steps`) ; ou toute fonction `f(t)`. `ease(spec, t)` pour évaluer.

## Pilotage (`animator`)
`play(anim, nœud, tag, speed)` → id · `tick(anim, dt)` (déterministe, tests) · `update(anim)` (horloge réelle,
limitée à `fps`) · `pause/resume/cancel/finish/seek/set_speed/reverse` · `set_time_scale` · `state/is_active/
active_count` · `attach(anim, store)` · `clear`.

- **Remplacement** : rejouer sur la même cible (même tag) annule l'animation précédente ; un ressort remplaçant un
  ressort **hérite de sa vitesse** (interruption fluide, sans à-coup).
- **Valeurs exactes** : l'état final est exactement `fin` ; un enfant de séquence terminé n'écrase pas les suivants.
- **Erreurs** : une erreur de rappel ne casse pas l'animateur ; elle est relevée (strict) ou gardée dans `errors()`.
- Les animations d'un widget **laid-out** (x, y) sont écrasées par `layout.perform` : animez plutôt `opacity`,
  `value`, la couleur du thème, ou des tailles/flex puis re-layout.

## Tests / exemples
`tests/ui/test_tween.al` (déterministe + horloge réelle) · `examples/ui_tween_demo.al` (natif) ·
`examples/ui_tween_canvas.al` (canvas).
