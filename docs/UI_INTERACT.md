# ALEX UI V1.3 — Gestes et interactions

```alex
use ui.interact as interact
ctl := interact.create(root, theme, win, canvas)
state.on_tick(store, interact.tick, ctl)
state.on_close_request(store, guard)                     # fermeture avec confirmation
state.run(win, store, interact.render, interact.handler, ctl)
```

## Événements natifs (Windows et Linux)
| événement | champs |
|---|---|
| `pointer_move` / `pointer_down` / `pointer_up` | `x`, `y`, `mods`, `button` (1 gauche, 2 droit, 3 milieu) |
| `wheel` | `x`, `y`, `dx`, `dy` (`dy` > 0 = vers le haut, en crans), `mods` |
| `pointer_leave` | `mods` (le pointeur quitte la fenêtre) |
| `key_down` | `key` (code VK), `mods` (1 Alt, 2 Ctrl, 4 Maj, 8 Win), `text` (Linux) |
| `text_input` | `data` (Windows : texte saisi, IME/AZERTY) |
| `resize` | `x`, `y` (rafales fusionnées) · `close_request` (voir ci-dessous) · `close` |

- **Capture de la souris** : pendant un appui, les `pointer_move` / `pointer_up` continuent d'arriver même hors de la
  fenêtre (X11 : prise implicite ; Windows : `SetCapture`).
- **Fermeture avec confirmation** : `ui.set_confirm_close(win, true)` ; la croix émet `close_request` au lieu de
  fermer ; l'application décide (`ui.close(win)`). Avec `state.on_close_request(store, fn)`, `state.run` gère tout.
- **Curseurs** : `ui.set_cursor(win, "text"|"pointer"|"grab"|"grabbing"|"resize_h"|…)` ; **mesure** : `ui.measure_text`.
- Codes de touches de ponctuation = `VK_OEM_*` (jamais l'ASCII : `(` ne se confond plus avec la flèche bas).

## Gestes (`ui.gesture`, pur et testable avec une horloge fournie)
`press`, `release`, `click` (count 1/2/3), `double_click`, `triple_click`, `context` (clic droit), `middle_click`,
`long_press` (0,5 s, supprime le clic), `drag_start/move/end/cancel` (seuil 4 px), `hover`, `hover_end`, `wheel`.

## Contrôleur (`ui.interact`) — widgets modernes
- **Survol / appui animés** (`hover_t`, `press_t` via `ui.tween`), **curseur adapté** à chaque zone.
- **Focus clavier** : Tab / Maj+Tab (ordre de l'arbre, `tab_index`), flèches (navigation spatiale), anneau visible
  seulement au clavier, Entrée/Espace, Échap (`on_escape`), piège de focus (`set_trap`).
- **Callbacks** (widget) : `on_click(w)`, `on_press`, `on_release`, `on_double_click`, `on_context`, `on_long_press`,
  `on_hover`, `on_hover_end`, `on_wheel` (→ true consomme), `on_key`, `on_escape`, `on_drag_start/drag/drag_end`,
  `on_drag_enter/over/leave`, `on_drop`, `on_scroll`. Les événements « fn(w, ev) » portent la position et les modificateurs.
- **Glisser-déposer entre composants** : `draggable`, `drag_data`, `drag_type` ; cibles `droppable`, `drop_accept`
  (liste de types ou `fn(cible, session)`). Fantôme, surbrillance verte / rouge, refus avec **retour animé**, Échap
  annule, défilement automatique près des bords. `widget.move(enfant, parent, index)` pour déplacer.
- **Défilement** (`ui.scroll`) : `scroll_view` (imbriquables), molette (Maj = horizontal), barres cliquables et
  glissables, clavier (PgHaut/PgBas/Début/Fin/flèches), `to_view`, `smooth`, **`link(a, b, axe, mode)`** pour une
  synchronisation dans les deux sens (ratio ou décalage, sans boucle).
- **Texte** : `text_field` et `text_area` (`ui.widgets.text_input`) — curseur et sélection mesurés sur les glyphes,
  sélection à la souris, double-clic = mot, triple-clic = ligne, Maj+flèches, Ctrl+←/→, Ctrl+A/C/X/V/Z/Y, lecture seule,
  défilement horizontal/vertical ; `gutter` (numéros de ligne synchronisés). Logique pure : `ui.edit`, `ui.text`.

## Limites connues
Pas de glisser-déposer de fichiers depuis le bureau sous Linux (XDND) ; pas d'IME riche ; texte sans retour à la
ligne automatique ; pas de sélection multiple de widgets. **Win32** : les nouveautés natives (souris droite/milieu,
molette, capture, `pointer_leave`, `close_request`, curseurs, `text_input`, mesure DirectWrite) sont écrites mais
n'ont pas pu être compilées ni exécutées ici : à vérifier sous Windows.

## Tests
`make test-ui-portable` (gestes, édition, interactions, défilement, glisser-déposer, rendu) · `make test-ui-x11`
(vrais événements X). Exemple : `examples/ui_gestures_demo.al`.
