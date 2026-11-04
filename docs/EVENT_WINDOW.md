# Événements, fenêtres, clavier, souris : `event`, `window`, `keyboard`, `mouse`

Le socle des applications interactives : une boucle d'événements d'application (minuteries, descripteurs,
signaux, sources), des émetteurs / répartiteurs, des fenêtres natives (X11, Win32, ou sans écran pour les
tests) avec position, états (normal, agrandi, plein écran, réduit), styles, focus, et le clavier / la souris
de ces fenêtres (touches, dispositions, appuis ET relâchements, pointeur, curseurs).

```
use event.event_loop as el
use window

loop := el.EventLoop()
w := window.Window("Démo", 640, 480)
w.on("key", (e) => print("touche", e.combo()))     # keyboard.key_event.KeyEvent
w.show()
loop.add_source(() => w.dispatch_events())
loop.every(1.0, rafraichir)
await loop.run()
```

Dorsals de fenêtres : X11 (EWMH : états, déplacement, focus, relâchement des touches avec filtrage de
l'auto-répétition), Win32, et `ALEX_UI_BACKEND=headless` (sans écran, pour les tests : les états sont
émulés). Natifs ajoutés à `ui` : `window_set_position`, `window_info`, `window_set_state`,
`window_set_hints`, `window_focus`, `window_list`, `inject_key_up`, `canvas_put_pixels`.

Tests : `make test-event-window` (sans écran, 92 vérifications) et `make test-window-x11` (Xvfb réel,
pilote d'événements `tests/ui/x11_driver.cpp`).

## Paquet `event`

### `event`

```text
Le système d'événements : un Event (type, données, horodatage, source, propagation) et les modules qui les
font circuler.

| Module               | Rôle                                                                             |
|----------------------|----------------------------------------------------------------------------------|
| event                | Event : la valeur qui circule (ici)                                              |
| event.event_emitter  | EventEmitter : on / once / off / emit (comme Node.js), écouteurs async, wait_for  |
| event.event_dispatcher | EventTarget (capture / cible / bouillonnement, comme le DOM), Dispatcher (bus)  |
| event.event_queue    | EventQueue (priorités, fusion), ThreadEventQueue (entre fils)                    |
| event.timer          | Timer, Interval, debounce, throttle                                              |
| event.watcher        | FileWatcher (fichiers et dossiers : inotify ou scrutation), ValueWatcher         |
| event.event_loop     | EventLoop : file d'événements + minuteurs + descripteurs + signaux, en une boucle |

  use event
  e := event.Event("click", {"x": 10, "y": 20})
  print(e.type, e.data["x"], e.timestamp)
  e.stop_propagation()

Un événement est une valeur ordinaire : n'importe quel objet peut le transporter. Pour le faire passer d'un
fil à l'autre, to_dict() / from_dict() (seules des valeurs copiables traversent).
```

API publique :

- class `Event(event_type, data=null, source=null)` : `stop_propagation()`, `stop_immediate_propagation()`, `prevent_default()`, `get(key, fallback=null)`, `to_dict()`, `to_string()`
- `create(event_type, data=null, source=null)`
- `is_event(x)`
- `from_dict(d)`
- `coerce(x, data=null)`

### `event.event_dispatcher`

```text
Distribution d'événements (event.Event) :
  - EventTarget : des nœuds en arbre (interface, documents, scènes) ; un événement envoyé à un nœud traverse
    la phase de CAPTURE (de la racine vers la cible), la CIBLE, puis le BOUILLONNEMENT (de la cible vers la
    racine), comme dans le DOM. stop_propagation / prevent_default sont respectés.
  - Dispatcher : un bus central par type d'événement, avec priorités, filtres et types hiérarchiques
    (« fenetre.clavier.appui » atteint aussi les abonnés de « fenetre.clavier » et « fenetre »).

  use event
  use event.event_dispatcher as ed
  racine := ed.EventTarget("fenêtre")
  bouton := ed.EventTarget("ok", racine)
  racine.add_listener("click", (e) => print("capture", e.target.name), true)
  bouton.add_listener("click", (e) => print("bouton"))
  racine.add_listener("click", (e) => print("bouillonnement"))
  bouton.dispatch(event.Event("click", {"x": 3}))         # capture, bouton, bouillonnement

  bus := ed.Dispatcher()
  bus.subscribe("commande.creee", traiter, 10, (e) => e.get("montant") > 100)
  bus.publish("commande.creee", {"montant": 250})

Erreurs : TypeError ; une exception d'un écouteur traverse dispatch / publish (Dispatcher.on_error pour la
capturer et continuer).
```

API publique :

- class `EventTarget(name="", parent=null)` : `append_child(child)`, `remove_child(child)`, `path()`, `add_listener(event_type, fn, capture=false, priority=0, once=false)`, `remove_listener(event_type, fn)`, `listener_count(event_type)`, `dispatch(e, data=null)`, `find(name)`
- class `Dispatcher()` : `subscribe(event_type, handler, priority=0, filter=null)`, `on_error(handler)`, `subscriber_count(event_type)`, `publish(e, data=null)`
- `target(name="", parent=null)`
- `dispatcher()`

### `event.event_emitter`

```text
EventEmitter : des écouteurs nommés par type d'événement, appelés quand on émet ce type (comme Node.js).

  use event.event_emitter as ee
  bus := ee.EventEmitter()
  off := bus.on("message", (texte) => print("reçu", texte))
  bus.once("pret", () => print("prêt !"))
  bus.on("*", (type, args) => journal(type))        # joker : tous les types (type, liste des arguments)
  bus.emit("message", "bonjour")                     # renvoie le nombre d'écouteurs appelés
  off()                                              # retire l'écouteur
  v := await bus.wait_for("reponse", 2.0)            # futur du prochain événement « reponse » (premier argument)
  await bus.emit_async("sauvegarde", doc)            # attend aussi les écouteurs async

Un écouteur reçoit autant d'arguments qu'il en déclare (les autres sont ignorés, les manquants valent null).
Ordre : priorité décroissante (on(type, fn, priorité)), puis ordre d'inscription. Une exception levée par un
écouteur est remise aux écouteurs de "error" (fn(type, message, type_d_evenement)) s'il y en a, sinon relancée
par emit (comme Node.js).

Erreurs : TypeError (écouteur non fonction), ArgumentError (trop d'arguments), TimeoutError (wait_for).
```

API publique :

- class `EventEmitter(max_listeners=100)` : `on(event_type, fn, priority=0)`, `once(event_type, fn, priority=0)`, `off(event_type, fn)`, `remove_all(event_type=null)`, `listener_count(event_type)`, `event_types()`, `emit(event_type, a=null, b=null, c=null, d=null)`, `emit_args(event_type, args)`, `emit_async(event_type, a=null, b=null, c=null, d=null)`, `wait_for(event_type, timeout=null)`
- `emitter(max_listeners=100)`

### `event.event_loop`

```text
Boucle d'événements d'APPLICATION : une seule boucle qui réunit
  - une file d'événements (post / on : gestionnaires par type, avec priorités),
  - des appels différés et périodiques (call_soon, call_later, every),
  - des descripteurs à surveiller (add_reader : tube, socket, terminal, inotify...),
  - des signaux du système (add_signal_handler),
  - des sources sondées à chaque tour (add_source : par exemple ui.window.poll ou un FileWatcher),
au-dessus des tâches async (asyncio) : les tâches et les gestionnaires async avancent en même temps.

  use event.event_loop as el
  loop := el.EventLoop()
  loop.on("commande", (e) => executer(e.data))
  loop.add_reader(tube.reader.fd, () => lire_et_poster(loop))
  loop.add_signal_handler("TERM", () => loop.stop())
  loop.every(1.0, rafraichir_statistiques)
  loop.post("commande", "démarrer")
  await loop.run()                         # jusqu'à loop.stop() (ou run(secondes))

Un gestionnaire reçoit l'événement (event.Event) ; s'il renvoie un futur (async), la boucle ne l'attend pas
(il s'exécute en tâche) sauf avec on(type, fn, priorité, true) (sérialisé). Une exception d'un gestionnaire est
passée à on_error(fn) ; sans on_error, elle arrête la boucle et run() la relance.

Erreurs : celles des gestionnaires ; ArgumentError ; ThreadError (signaux hors du programme principal).
```

API publique :

- class `EventLoop(tick=0.01)` : `on(event_type, handler, priority=0, serialize=false)`, `off(event_type, handler)`, `on_error(fn)`, `post(e, data=null, priority=0)`, `post_unique(e, data=null, priority=0)`, `call_soon(fn)`, `call_later(delay, fn)`, `every(interval, fn)`, `cancel(id)`, `add_reader(fd, fn)`, `remove_reader(fd)`, `add_writer(fd, fn)`, `remove_writer(fd)`, `add_source(fn)`, `add_signal_handler(sig, fn)`, `remove_signal_handler(sig)`, `stop()`, `running()`, `dispatch_pending(limit=1000)`, `run(duration=null)`, `run_until(f)`
- `default()`

### `event.event_queue`

```text
Files d'événements :
  - EventQueue : dans un fil, entre tâches async — priorités (la plus haute sort d'abord, FIFO à priorité
    égale), fusion (post_unique remplace un événement du même type encore en attente : redimensionnement,
    rafraîchissement), retrait sans attendre (poll), attente async (get), capacité bornée.
  - ThreadEventQueue : entre FILS (thread) ; les événements y passent sous forme copiable (to_dict).

  use event.event_queue as eq
  q := eq.EventQueue()
  q.post(event.Event("clavier", "a"))
  q.post("rafraichir", null, 10)                 # type + données + priorité
  q.post_unique("redimensionner", {"l": 800})     # remplace un « redimensionner » en attente
  e := q.poll()                                   # null si vide
  e := await q.get(1.0)                           # attend au plus 1 s (null après le délai)
  for e in q.drain(): ...

Erreurs : QueueFull (capacité atteinte), TypeError.
```

API publique :

- class `EventQueue(capacity=0)` : `size()`, `empty()`, `post(e, data=null, priority=0)`, `post_unique(e, data=null, priority=0)`, `poll()`, `peek()`, `get(timeout=null)`, `drain()`, `remove_type(event_type)`, `clear()`
- `queue(capacity=0)`
- class `ThreadEventQueue(capacity=0, id=null)` : `post(e, data=null, timeout=null)`, `get(timeout=null)`, `poll()`, `size()`, `close()`, `closed()`
- `attach(id)`

### `event.timer`

```text
Minuteries sur la boucle async : déclencher une fonction après un délai (Timer), périodiquement (Interval), et
deux outils pour les événements en rafale : debounce (n'agir qu'après un calme) et throttle (au plus une fois
par période).

  use event.timer as timer
  t := timer.Timer(2.0, () => print("2 s plus tard"))
  t.start()
  t.cancel()                                    # avant l'échéance : rien ne se passe
  i := timer.Interval(0.5, () => print("tic"), 3).start()   # 3 fois
  await i.wait()                                 # futur de fin
  sauvegarder_bientot := timer.debounce(sauvegarder, 0.3)   # appelée 10 fois de suite : 1 seule sauvegarde
  rafraichir_ecran := timer.throttle(redessiner, 1.0 / 60)

Les fonctions peuvent être async (leur futur est attendu avant le tic suivant). Il faut que la boucle async
tourne (await, ou event.event_loop) pour que les minuteries se déclenchent.

Erreurs : ArgumentError (délai négatif), TypeError ; une exception de la fonction est gardée dans last_error et
remise à on_error si défini (sinon le minuteur s'arrête et wait() la relance).
```

API publique :

- class `Timer(delay, fn, args=null)` : `start()`, `cancel()`, `stop()`, `restart(delay=null)`, `active()`, `wait()`
- class `Interval(interval, fn, count=null, args=null, first_delay=null)`
- `after(delay, fn, args=null)`
- `every(interval, fn, count=null, args=null)`
- `debounce(fn, wait)`
- `throttle(fn, period)`
- `sleep(delay, value=null)`

### `event.watcher`

```text
Surveiller des fichiers et des dossiers : création, modification, suppression, renommage. Sous Linux, le noyau
prévient (inotify : immédiat, sans coût) ; ailleurs, ou sur demande, l'arborescence est comparée régulièrement
(scrutation : dates de modification et tailles).

  use event.watcher as watcher
  w := watcher.FileWatcher(["config", "data/entrees"], true)       # récursif
  for e in w.poll(1.0):                                             # attend au plus 1 s
      print(e["kind"], e["path"])        # created | modified | deleted | moved_from | moved_to
  w.on((e) => recharger(e["path"]))
  await w.run(60)                                                   # 60 s de surveillance avec rappels
  w.close()

  v := watcher.ValueWatcher(() => lire_temperature(), 1.0, (ancienne, nouvelle) => alerte(nouvelle))
  v.start()

Les événements d'une même seconde peuvent être regroupés ou dédoublonnés selon le système ; un éditeur qui
enregistre « en remplaçant » produit souvent deleted + created (ou moved_to). backend : "inotify" ou "poll".

Erreurs : IoError (chemin absent, limite d'inotify), ArgumentError.
```

API publique :

- class `FileWatcher(paths, recursive=false, backend=null, interval=0.5)` : `poll(timeout=0)`, `on(handler)`, `dispatch()`, `run(duration=null)`, `close()`
- `watch(paths, recursive=false)`
- class `ValueWatcher(fn, interval, on_change)` : `check()`, `start()`, `stop()`

## Paquet `window`

### `window`

```text
Fenêtres d'application : création, titre, taille, POSITION, ÉTAT (normale, réduite, agrandie, plein écran),
style (redimensionnable, décorée, toujours devant, opacité, tailles min / max), focus, curseur, événements
(clavier et souris typés, gestes), pixels bruts (rendu logiciel, graphics), capture d'écran.

  use window
  w := window.Window("Mon appli", 800, 600, {"min_size": (400, 300)})
  w.on("key", (e) => print("touche", e.combo()))          # keyboard.key_event.KeyEvent
  w.on("click", (g) => print("clic", g.x, g.y))           # geste (mouse.pointer)
  w.on("close", () => print("fermée"))
  w.show()
  w.center()
  w.maximize()
  while w.is_open():
      w.dispatch_events()                                 # ou : w.run() / await w.run_async()

Événements (on) : les types bruts de la fenêtre (key_down, key_up, pointer_down, pointer_up, pointer_move,
pointer_leave, wheel, resize, move, state, focus_in, focus_out, close, close_request, drop, shortcut...) reçoivent
le dict d'origine ; « key » reçoit un KeyEvent, « mouse » un MouseEvent, et les gestes « click », « double_click »,
« drag_start », « drag », « drag_end » un MouseEvent produit par mouse.pointer. « * » reçoit tous les dicts.
Les fenêtres partagent l'écran et la file du système : window.window_manager en gère plusieurs.

Backends : X11 (Linux), Win32, et « headless » (ALEX_UI_BACKEND=headless : fenêtres virtuelles, pour les tests
et les serveurs ; les déplacements, états et focus y sont immédiats et produisent leurs événements).

Erreurs : IoError (pas d'affichage, fenêtre fermée), ArgumentError (dimensions, état, réglages invalides),
TypeError.
```

API publique :

- `available()`
- `backend()`
- class `Window(title="Alex", width=800, height=600, options=null)` : `show()`, `hide()`, `close()`, `is_open()`, `visible()`, `confirm_close(enabled=true)`, `title()`, `set_title(t)`, `size()`, `set_size(width, height)`, `resize(width, height)`, `position()`, `move(x, y)`, `center()`, `state()`, `set_state(state)`, `minimize()`, `maximize()`, `fullscreen()`, `restore()`, `toggle_fullscreen()`, `snapshot()`, `set_hints(resizable, decorated, topmost, opacity, min_size, max_size)`, `set_resizable(v)`, `set_decorated(v)`, `set_topmost(v)`, `set_opacity(v)`, `set_min_size(width, height)`, `set_max_size(width, height)`, `focus()`, `focused()`, `set_cursor(name)`, `cursor()`, `info()`, `dpi()`, `draw_pixels(x, y, width, height, rgba)`, `screenshot(path)`, `on(event_type, fn)`, `once(event_type, fn)`, `off(event_type, fn)`, `poll()`, `poll_all(limit=1000)`, `idle()`, `dispatch_events()`, `run(frame=null, fps=60)`, `run_async(frame=null, fps=60)`, `wait_for(event_type, timeout=null)`, `inject_key(name, mods=0)`, `inject_key_up(name, mods=0)`, `inject_press(name, mods=0)`, `inject_text(text)`, `inject_mouse(kind, x, y, button=1, mods=0)`, `inject_wheel(x, y, dx, dy, mods=0)`, `inject_close()`
- `create(title="Alex", width=800, height=600, options=null)`
- `handles()`

### `window.display`

```text
Les écrans physiques branchés (moniteurs) : nom de sortie, fabricant et modèle (EDID), résolution et modes,
taille physique, densité ; et l'écran logique du système de fenêtres (window.screen).

  use window.display as display
  for d in display.displays():
      print(d.name, d.model, d.resolution, d.dpi, d.primary)
  p := display.primary()                          # Display, ou null s'il n'y a pas d'information
  print(display.summary())

Les informations viennent de hardware.screen (/sys/class/drm, EDID, xrandr) : elles peuvent manquer dans une
machine virtuelle ou un conteneur — displays() renvoie alors un écran unique déduit du système de fenêtres.
```

API publique :

- class `Display(name, manufacturer, model, resolution, modes, width_mm, height_mm, primary, dpi, connected=true)` : `diagonal_inches()`, `describe()`
- `displays()`
- `primary()`
- `count()`
- `summary()`

### `window.screen`

```text
L'écran vu par le système de fenêtres : taille, zone de travail (hors barres et docks), densité (DPI) et facteur
d'échelle ; placement d'une fenêtre (centrer, coin, demi-écran).

  use window.screen as screen
  s := screen.current()
  print(s.width, s.height, s.work_width, s.work_height, s.dpi, s.scale)
  screen.center(fenetre)
  screen.place(fenetre, "right_half")            # moitié droite de la zone de travail
  print(s.dp_to_px(16))                          # 16 points « indépendants » en pixels

Erreurs : IoError (pas d'affichage : utiliser ALEX_UI_BACKEND=headless pour un écran virtuel 1920x1080).
```

API publique :

- class `Screen(width, height, work_width, work_height, dpi)` : `size()`, `work_area()`, `dp_to_px(dp)`, `px_to_dp(px)`, `contains(x, y)`, `to_dict()`
- `current(win=null)`
- `center(win)`
- `place(win, where, margin=0)`

### `window.window_manager`

```text
Gestion de PLUSIEURS fenêtres : création, recherche, fenêtre active, boucle d'événements commune (synchrone ou
async) qui s'arrête quand la dernière fenêtre se ferme, disposition automatique (cascade, mosaïque), et
sauvegarde / restauration des positions.

  use window.window_manager as wm
  m := wm.WindowManager()
  a := m.create("Éditeur", 800, 600)
  b := m.create("Aperçu", 400, 600)
  m.tile()                                  # côte à côte dans la zone de travail
  m.on_close(a, () => m.close_all())        # fermer l'éditeur ferme tout
  await m.run_async()                       # jusqu'à la fermeture de toutes les fenêtres

  m.save_layout("~/.config/appli/fenetres.json")
  m.restore_layout("~/.config/appli/fenetres.json")   # par titre de fenêtre

Erreurs : ArgumentError (fenêtre inconnue), IoError.
```

API publique :

- class `WindowManager()` : `create(title="Alex", width=800, height=600, options=null)`, `add(win)`, `remove(win)`, `windows()`, `count()`, `active()`, `get(handle)`, `find(title)`, `focused()`, `on_close(win, fn)`, `close_all()`, `minimize_all()`, `restore_all()`, `dispatch_events()`, `run(frame=null, fps=60)`, `run_async(frame=null, fps=60)`, `cascade(x=40, y=40, step=32)`, `tile(columns=null)`, `save_layout(path)`, `restore_layout(path)`
- `default()`

### `window.window_state`

```text
États d'une fenêtre et instantané de sa géométrie (WindowState), avec sauvegarde / restauration (pour rouvrir
une application là où l'utilisateur l'avait laissée, en restant visible sur l'écran actuel).

  use window.window_state as ws
  s := fenetre.snapshot()                       # WindowState
  ws.save(s, "~/.config/mon-appli/fenetre.json")
  s2 := ws.load("~/.config/mon-appli/fenetre.json")
  if s2 != null:
      s2.clamp_to(1920, 1080).apply(fenetre)

Erreurs : ArgumentError (état inconnu), IoError (fichier).
```

API publique :

- `all_states()`
- `is_valid(state)`
- `check(state)`
- `describe(state)`
- class `WindowState(x=0, y=0, width=800, height=600, state="normal")` : `to_dict()`, `clamp_to(screen_w, screen_h, margin=32)`, `apply(win)`, `to_string()`
- `from_dict(d)`
- `save(state, path)`
- `load(path)`

### `window.window_style`

```text
Styles de fenêtre : un ensemble de réglages appliqués d'un coup (redimensionnable, décorée, toujours devant,
opacité, tailles minimale et maximale), avec des préréglages usuels.

  use window.window_style as wst
  wst.DIALOG.apply(fenetre)                     # taille fixe, décorée
  s := wst.WindowStyle()                        # style par défaut
  s.topmost = true
  s.opacity = 0.9
  s.min_size = (320, 200)
  s.apply(fenetre)

Préréglages : DEFAULT, DIALOG, TOOL (petite, toujours devant), BORDERLESS (sans bordure), OVERLAY (sans
bordure, toujours devant, semi-transparente), KIOSK (plein écran sans bordure, fixe).

Erreurs : ArgumentError (opacité hors de 0..1, tailles incohérentes).
```

API publique :

- class `WindowStyle(resizable=true, decorated=true, topmost=false, opacity=1.0, min_size=null, max_size=null, fullscreen=false)` : `validate()`, `copy()`, `apply(win)`, `to_dict()`
- `of(win)`
- `preset(name)`

## Paquet `keyboard`

### `keyboard`

```text
Le clavier : état des touches (lesquelles sont enfoncées, modificateurs), raccourcis, saisie de texte, quelle que
soit la source des événements — une fenêtre (window), le clavier brut du noyau (evdev, hardware.keyboard) ou le
terminal.

  use keyboard
  kb := keyboard.Keyboard()
  kb.shortcuts.add("ctrl+s", sauvegarder)
  kb.shortcuts.add("ctrl+q", () => fenetre.close())
  for ev in fenetre.poll_all():
      kb.feed_window_event(ev)                 # met à jour l'état, déclenche les raccourcis
  if kb.is_pressed("left") and kb.shift():
      selectionner()

  r := keyboard.open_raw()                     # clavier physique (droits sur /dev/input)
  e := r.read(1.0)                             # keyboard.key_event.KeyEvent (ou null)
  print(keyboard.layout().type_text(evenements))

Modules : keyboard.key (noms et codes), keyboard.key_event (KeyEvent, raccourcis), keyboard.keyboard_layout
(dispositions AZERTY, QWERTY, QWERTZ...), hardware.keyboard (périphériques).

Erreurs : HardwareError (clavier brut absent ou droits), ArgumentError (raccourci mal formé), TypeError.
```

API publique :

- class `Shortcuts()` : `add(shortcut, fn)`, `remove(shortcut)`, `has(shortcut)`, `list()`, `handle(e)`
- class `Keyboard(layout_code=null)` : `feed(e)`, `feed_window_event(ev)`, `is_pressed(name)`, `pressed()`, `mods()`, `ctrl()`, `shift()`, `alt()`, `meta()`, `held_for(name, now=null)`, `take_text()`, `reset()`
- class `RawKeyboard(device=null, layout_code=null)` : `read(timeout=null)`, `close()`
- `open_raw(device=null, layout_code=null)`
- `devices()`
- `available()`
- `layout(code=null)`
- `read_terminal_key(timeout=null)`

### `keyboard.key`

```text
Les touches : noms uniformes (« a », « 1 », « enter », « left », « f5 », « left_ctrl »...), codes virtuels des
fenêtres (ceux de window / ui, façon Win32 : A = 65, F1 = 112, flèche gauche = 37) et codes du noyau Linux
(evdev, ceux de hardware.keyboard : A = 30). Modificateurs en masque de bits.

  use keyboard.key as key
  print(key.name(65), key.code("f5"), key.from_evdev(30))      # a 116 a
  print(key.mods_names(key.CTRL | key.SHIFT))                  # [ctrl, shift]
  print(key.is_modifier("left_shift"), key.is_printable("a"))

Les noms suivent hardware.keyboard (evdev) : un même nom désigne la même touche quelle que soit la source.
```

API publique :

- `name(vk)`
- `normalize(n)`
- `code(n)`
- `from_evdev(evcode)`
- `to_evdev(n)`
- `is_modifier(n)`
- `modifier_bit(n)`
- `is_printable(n)`
- `is_function_key(n)`
- `is_navigation(n)`
- `mods_names(mods)`
- `mods_from_names(names)`
- `all_names()`

### `keyboard.key_event`

```text
KeyEvent : un appui, un relâchement ou une répétition de touche, quelle que soit sa source — fenêtre (window,
ui), clavier brut du noyau (hardware.keyboard / evdev), ou terminal (io.console.read_key) — avec le même nom de
touche (keyboard.key), les modificateurs et le texte produit.

  use keyboard.key_event as ke
  e := ke.from_window_event(ev)              # ev : dict de window.poll()
  if e != null and e.matches("ctrl+s"):
      sauvegarder()
  r := ke.parse_shortcut("Ctrl+Shift+F5")    # ["f5", CTRL | SHIFT]
  print(e.describe())                         # « ctrl+shift+f5 (appui) »

Erreurs : ArgumentError (raccourci mal formé), TypeError.
```

API publique :

- class `KeyEvent(key, action="press", mods=0, text="", code=null, source="program", time=null)` : `pressed()`, `is_repeat()`, `ctrl()`, `shift()`, `alt()`, `meta()`, `matches(shortcut)`, `combo()`, `describe()`, `to_dict()`
- `parse_shortcut(text)`
- `format_shortcut(key, mods)`
- `from_window_event(ev)`
- `from_evdev(e, mods=0)`
- `from_terminal(name)`

### `keyboard.keyboard_layout`

```text
Dispositions de clavier : quel caractère produit une touche PHYSIQUE (nom keyboard.key, position QWERTY du
noyau) selon la disposition (azerty, qwerty, qwertz...) et les modificateurs (Maj, AltGr). Sert à traduire
les événements bruts (evdev), qui ne donnent que la position, en texte.

  use keyboard.keyboard_layout as kl
  fr := kl.get("fr")                      # AZERTY français
  print(fr.char("q"), fr.char("1", true), fr.char("2", false, true))   # a 1 ~
  print(kl.detect())                      # disposition du système (XKB, localectl, LANG), ex. « fr »
  print(kl.available())                   # [us, fr, de, be, ch, es, it, uk, dvorak]

Les tables couvrent les touches de caractères (lettres, chiffres, ponctuation) ; les touches mortes (^, ¨)
donnent le caractère lui-même (pas de composition).

Erreurs : ArgumentError (disposition inconnue).
```

API publique :

- class `KeyboardLayout(code)` : `char(key, shift=false, altgr=false, caps_lock=false)`, `key_for(c)`, `type_text(events)`
- `get(code)`
- `available()`
- `detect()`

## Paquet `mouse`

### `mouse`

```text
La souris : événements d'une fenêtre ou de la souris physique (evdev), suivi du pointeur et gestes (clic,
double clic, glisser), forme du curseur.

  use mouse
  p := mouse.pointer()
  for ev in fenetre.poll_all():
      for g in p.feed(mouse.from_window_event(ev)):
          if g.kind == "double_click":
              ouvrir(g.x, g.y)
  mouse.set_cursor(fenetre, "pointer")
  brut := mouse.open_raw()                  # souris physique : déplacements relatifs (droits sur /dev/input)
  e := brut.read(1.0)

Modules : mouse.mouse_event (MouseEvent), mouse.pointer (Pointer : gestes, régions), mouse.cursor (formes),
hardware.mouse (périphériques).

Erreurs : HardwareError (souris brute absente ou droits), ArgumentError (curseur inconnu).
```

API publique :

- `pointer(drag_threshold=4, double_click_time=0.4)`
- `from_window_event(ev)`
- `set_cursor(window, name)`
- `get_cursor(window)`
- `cursors()`
- `devices()`
- `available()`
- class `RawMouse(device=null)` : `read(timeout=null)`, `close()`
- `open_raw(device=null)`

### `mouse.cursor`

```text
Forme du curseur de la souris au-dessus d'une fenêtre : flèche, texte, main, sablier, déplacement...

  use mouse.cursor as cursor
  cursor.set(fenetre, cursor.WAIT)
  cursor.with_cursor(fenetre, cursor.WAIT, calcul_long)     # rétablit le curseur précédent ensuite
  print(cursor.get(fenetre), cursor.names())

fenetre : un window.Window (ou tout objet ayant .handle), ou un handle de fenêtre ui.

Erreurs : ArgumentError (nom inconnu), IoError (fenêtre fermée, pas d'affichage).
```

API publique :

- `names()`
- `is_valid(name)`
- `set(window, name)`
- `get(window)`
- `reset(window)`
- `with_cursor(window, name, fn)`
- `for_edge(edge)`

### `mouse.mouse_event`

```text
MouseEvent : mouvement, appui, relâchement, molette, sortie de la fenêtre, clic, double clic, glisser — d'une
fenêtre (window / ui) ou de la souris brute du noyau (evdev, hardware.mouse : déplacements relatifs).

  use mouse.mouse_event as me
  e := me.from_window_event(ev)          # ev : dict de window.poll()
  if e != null and e.kind == "down" and e.button == "left":
      commencer(e.x, e.y)

kind : move | down | up | wheel | leave | click | double_click | drag_start | drag | drag_end | relative
button : "left", "right", "middle" (ou null) ; buttons : ensemble des boutons enfoncés (pointer.Pointer).
```

API publique :

- `button_name(n)`
- class `MouseEvent(kind, x=0, y=0, button=null, mods=0, dx=0.0, dy=0.0, source="program", time=null)` : `is_press()`, `is_release()`, `position()`, `describe()`, `to_dict()`
- `from_window_event(ev)`
- `from_evdev(e)`

### `mouse.pointer`

```text
Pointer : suit le pointeur à partir des événements bruts (mouse_event.MouseEvent) et en déduit des gestes de
haut niveau — clic, double clic, glisser (début / déplacement / fin, avec seuil), vitesse — ainsi que la zone
survolée parmi des régions nommées.

  use mouse.pointer as pt
  p := pt.Pointer()
  p.add_region("bouton_ok", 10, 10, 80, 30)
  for ev in fenetre.poll_all():
      for g in p.feed(mouse_event.from_window_event(ev)):     # gestes produits par cet événement
          if g.kind == "click" and p.region_at(g.x, g.y) == "bouton_ok":
              valider()
          if g.kind == "drag":
              deplacer(g.dx, g.dy)
  print(p.x, p.y, p.is_down("left"), p.speed())

Réglages : drag_threshold (pixels, 4), double_click_time (secondes, 0,4), double_click_distance (pixels, 4).
```

API publique :

- class `Pointer(drag_threshold=4, double_click_time=0.4, double_click_distance=4)` : `is_down(button="left")`, `buttons()`, `dragging()`, `speed()`, `add_region(name, x, y, w, h)`, `remove_region(name)`, `region_at(x, y)`, `hovered()`, `feed(e)`

