# ALEX UI V1.1 — État réactif (`ui.state`)

```alex
use ui.state as state

store := state.create({"price": 10, "qty": 2})
state.computed(store, "total", total)        # total(store) -> state.get(store,"price") * state.get(store,"qty")
state.watch(store, "total", on_total)        # on_total(event) : event = {store,key,value,old,ctx}
state.set(store, "qty", 3)                   # -> total recalculé (dépendances auto), observateur appelé
```

## Principes
- **`set` ne notifie que si la valeur change** (égalité structurelle). Une clé inconnue lève une erreur
  (`define` crée une clé) : pas de faute de frappe silencieuse. Après une mutation EN PLACE d'une list/dict :
  `touch(store, key)`.
- **Calculés** (`computed`) : les dépendances sont détectées automatiquement (clés lues via `get`) et
  re-détectées à chaque calcul (dépendances dynamiques). Lecture seule, cycles détectés, notifiés **une seule
  fois** même pour un « diamant », et **pas du tout** si leur valeur finale ne change pas.
- **Lots** : `batch_begin/batch_end`, `transaction(store, fn, ctx)`, `set_many`. Une valeur remise à son état
  initial dans le lot n'émet rien. Les lots sont imbriquables.
- **Sûreté** : tous les observateurs s'exécutent même si l'un lève ; l'erreur est ensuite relevée
  (`strict=true`) ou gardée dans `errors()` (`strict=false`). Boucles de réactivité interrompues après
  100 passes. Un observateur peut se désabonner pendant la notification.
- **Fermetures** : ALEX a désormais des lambdas et des fonctions imbriquées capturantes (voir `docs/CLOSURES.md`).
  La bibliothèque UI n'en dépend pas : ses observateurs/handlers restent des fonctions de premier niveau et
  l'état utile passe par `ctx`.

## Liaisons widgets
| store → widget natif | widget → store | widgets modernes (canvas) |
|---|---|---|
| `bind_text`, `bind_checked`, `bind_progress(scale)`, `bind_enabled`, `bind_visible` | `link_input`, `link_checkbox` | `bind_prop(store,key,widget,"text")`, `link_widget` (checkbox, text_field) |

Événements : `on(store, handle, fn)`, `on_command`, `on_shortcut` avec `fn(call)`, `call = {store,widget,event,ctx}`.
`run(win, store, render, handler, ctx)` : boucle d'événements ; `render(store, ctx)` n'est rappelé que si l'état
est « dirty » (valeur modifiée ou `invalidate`). S'arrête sur `close`.

## Autres
`snapshot/restore`, `to_dict`, `version`, `is_dirty/clear_dirty`, `unwatch`, `watch_all`, `watch(..., immediate=true)`.

## Tests
`tests/ui/test_state.al` (logique pure) · `tests/ui/test_state_ui.al` (widgets, `ALEX_UI_BACKEND=headless`).
Exemples : `examples/ui_state_demo.al` (natif), `examples/ui_state_canvas.al` (canvas).
