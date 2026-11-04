# ALEX UI V1.1 — Liaison état <-> widgets, répartition d'événements et boucle réactive
#
# Aucune fermeture en ALEX : chaque liaison est un observateur de premier niveau recevant son
# contexte (widget, propriété, transformation) via event["ctx"].
#   store -> widget : bind_text / bind_checked / bind_progress / bind_enabled / bind_visible /
#                     bind_prop (widgets modernes ui.widgets : dict + propriété)
#   widget -> store : link_input / link_checkbox (widgets natifs), link_widget (widgets modernes)
#   événements      : on / on_command / on_shortcut, puis handle_event() ou run()
# Les boucles de rétroaction sont évitées par la comparaison d'égalité de set() et en ne réécrivant
# un widget natif que si son contenu diffère (le curseur d'un champ de saisie ne saute pas).
from core use type, to_int, to_bool, clamp
use collections
use os as _os
use _native_ui as _native
use ui.state.store as _store
use ui.tween.core as _tcore
use ui.tween.animator as _tanim

const VERSION := "1.1.0"

func _check_handle(handle, fn):
    if type(handle) != "int":
        raise("TypeError", "ui.state." + fn + "() : handle de widget (int) attendu")

func _transform(ctx, value):
    if ctx["transform"] != null:
        return ctx["transform"](value)
    return value

# ---- store -> widget moderne (dict) ----
func _apply_prop(ev):
    c := ev["ctx"]
    c["target"][c["prop"]] = _transform(c, ev["value"])

func bind_prop(store, key, target, prop, transform=null):
    if type(target) != "dict":
        raise("TypeError", "ui.state.bind_prop() : le widget cible doit être un dict")
    return _store.watch(store, key, _apply_prop, {"target": target, "prop": prop, "transform": transform}, true)

# ---- store -> widgets natifs ----
func _apply_text(ev):
    c := ev["ctx"]
    v := _transform(c, ev["value"])
    text := ""
    if v != null:
        text = str(v)
    if _native.widget_get_text(c["handle"]) != text:
        _native.widget_set_text(c["handle"], text)

func bind_text(store, key, handle, transform=null):
    _check_handle(handle, "bind_text")
    return _store.watch(store, key, _apply_text, {"handle": handle, "transform": transform}, true)

func _apply_checked(ev):
    c := ev["ctx"]
    v := to_bool(_transform(c, ev["value"]))
    if _native.widget_get_checked(c["handle"]) != v:
        _native.widget_set_checked(c["handle"], v)

func bind_checked(store, key, handle, transform=null):
    _check_handle(handle, "bind_checked")
    return _store.watch(store, key, _apply_checked, {"handle": handle, "transform": transform}, true)

# La valeur de l'état est multipliée par `scale` puis bornée à 0..100 (0.75 avec scale=100 -> 75 %).
func _apply_progress(ev):
    c := ev["ctx"]
    v := _transform(c, ev["value"])
    if v == null:
        v = 0
    _native.progress_set(c["handle"], clamp(to_int(v * c["scale"]), 0, 100))

func bind_progress(store, key, handle, scale=1.0, transform=null):
    _check_handle(handle, "bind_progress")
    return _store.watch(store, key, _apply_progress, {"handle": handle, "scale": scale, "transform": transform}, true)

func _apply_enabled(ev):
    c := ev["ctx"]
    _native.widget_set_enabled(c["handle"], to_bool(_transform(c, ev["value"])))

func bind_enabled(store, key, handle, transform=null):
    _check_handle(handle, "bind_enabled")
    return _store.watch(store, key, _apply_enabled, {"handle": handle, "transform": transform}, true)

func _apply_visible(ev):
    c := ev["ctx"]
    _native.widget_set_visible(c["handle"], to_bool(_transform(c, ev["value"])))

func bind_visible(store, key, handle, transform=null):
    _check_handle(handle, "bind_visible")
    return _store.watch(store, key, _apply_visible, {"handle": handle, "transform": transform}, true)

# ---- widget natif -> store (liaison bidirectionnelle) ----
func link_input(store, key, handle):
    _check_handle(handle, "link_input")
    store["links"][handle] = {"key": key, "kind": "text"}
    return bind_text(store, key, handle)

func link_checkbox(store, key, handle):
    _check_handle(handle, "link_checkbox")
    store["links"][handle] = {"key": key, "kind": "checked"}
    return bind_checked(store, key, handle)

func unlink(store, handle):
    if collections.contains_key(store["links"], handle):
        collections.remove(store["links"], handle)
        return true
    return false

# ---- événements -> actions ----
# fn(call) avec call = {"store","widget","event","ctx"}
func on(store, handle, fn_value, ctx=null):
    _check_handle(handle, "on")
    store["handlers"]["w" + str(handle)] = {"fn": fn_value, "ctx": ctx}
    return handle

func on_command(store, command_id, fn_value, ctx=null):
    store["handlers"]["c" + str(command_id)] = {"fn": fn_value, "ctx": ctx}
    return command_id

func on_shortcut(store, shortcut_id, fn_value, ctx=null):
    store["handlers"]["s" + str(shortcut_id)] = {"fn": fn_value, "ctx": ctx}
    return shortcut_id

func _dispatch_handler(store, key, ev):
    if not collections.contains_key(store["handlers"], key):
        return false
    h := store["handlers"][key]
    h["fn"]({"store": store, "widget": ev["widget"], "event": ev, "ctx": h["ctx"]})
    return true

func _sync_checked(store):
    for handle in store["links"]:
        link := store["links"][handle]
        if link["kind"] == "checked":
            _store.set(store, link["key"], _native.widget_get_checked(handle))

# Répartit un événement natif (retourne true s'il a été traité par une liaison ou un handler).
func handle_event(store, ev):
    t := ev["type"]
    h := ev["widget"]
    if t == "change":
        if collections.contains_key(store["links"], h):
            link := store["links"][h]
            if link["kind"] == "text":
                _store.set(store, link["key"], _native.widget_get_text(h))
                return true
        return false
    if t == "check" or t == "radio":
        _sync_checked(store)
        return true
    if t == "button":
        return _dispatch_handler(store, "w" + str(h), ev)
    if t == "command":
        return _dispatch_handler(store, "c" + str(h), ev)
    if t == "shortcut":
        return _dispatch_handler(store, "s" + str(h), ev)
    return false

# ---- widgets modernes (canvas) : widget -> store ----
func _on_widget_click(w):
    link := w["state_link"]
    if link["kind"] == "checked":
        _store.set(link["store"], link["key"], w["value"])

func _on_widget_change(w, value):
    link := w["state_link"]
    _store.set(link["store"], link["key"], value)

func link_widget(store, key, w):
    if type(w) != "dict" or not collections.contains_key(w, "kind"):
        raise("TypeError", "ui.state.link_widget() : widget moderne (dict) attendu")
    if w["kind"] == "checkbox":
        w["state_link"] = {"store": store, "key": key, "kind": "checked"}
        w["on_click"] = _on_widget_click
    elif w["kind"] == "text_field":
        w["state_link"] = {"store": store, "key": key, "kind": "text"}
        w["on_change"] = _on_widget_change
    else:
        raise("ArgumentError", "ui.state.link_widget() : seuls checkbox et text_field sont liables (kind=" + str(w["kind"]) + ")")
    return bind_prop(store, key, w, "value")

# ---- animation de l'état (ui.tween) ----
# Anime une clé numérique/couleur/vecteur du store vers end_value ; un animateur est créé et attaché au store
# au premier appel (state.run l'avance). Relancer sur la même clé remplace l'animation en cours.
func animator(store):
    if not collections.contains_key(store, "animator"):
        _tanim.attach(_tanim.create(), store)
    return store["animator"]

func animate(store, key, end_value, duration, start_value=null, easing="ease_out", delay=0.0, repeat=0, yoyo=false):
    return _tanim.animate_state(animator(store), store, key, end_value, duration, start_value, easing, delay, repeat, yoyo)

func spring(store, key, end_value, start_value=null, stiffness=170.0, damping=26.0, mass=1.0, velocity=null):
    return _tanim.spring_state(animator(store), store, key, end_value, start_value, stiffness, damping, mass, velocity)

func play(store, node, tag=null, speed=1.0):
    return _tanim.play(animator(store), node, tag, speed)

# ---- crochets de la boucle ----
# on_tick(store, fn, ctx) : fn(store, ctx) est appelée à CHAQUE tour de boucle (gestes à durée, clignotement,
# animations...) ; retourner true demande un re-rendu.
func on_tick(store, fn_value, ctx=null):
    if not collections.contains_key(store, "ticks"):
        store["ticks"] = []
    collections.append(store["ticks"], {"fn": fn_value, "ctx": ctx})
    return null

# on_close_request(store, fn, ctx) : fn(store, ctx) -> true pour fermer. Active la fermeture avec confirmation :
# la croix de la fenêtre n'exécute plus rien d'elle-même (événement "close_request").
func on_close_request(store, fn_value, ctx=null):
    store["close_guard"] = {"fn": fn_value, "ctx": ctx}
    return null

# ---- boucle réactive ----
# render(store, ctx) est appelé une fois au départ puis à chaque fois que le store est « dirty »
# (valeur modifiée ou invalidate()). handler(ev, store, ctx) reçoit chaque événement après handle_event.
# La boucle s'arrête à l'événement "close" (ou à la fermeture acceptée par on_close_request).
func run(win, store, render=null, handler=null, ctx=null, idle=0.002):
    if collections.contains_key(store, "close_guard"):
        _native.window_set_confirm_close(win, true)
    if render != null:
        render(store, ctx)
    _store.clear_dirty(store)
    running := true
    while running:
        ev := _native.window_poll(win)
        if ev != null:
            if ev["type"] == "close":
                running = false
            elif ev["type"] == "close_request":
                allowed := true
                if collections.contains_key(store, "close_guard"):
                    g := store["close_guard"]
                    allowed = g["fn"](store, g["ctx"]) == true
                if allowed:
                    _native.window_close(win)
                    running = false
            else:
                handle_event(store, ev)
                if handler != null:
                    handler(ev, store, ctx)
        elif idle > 0:
            _os.sleep(idle)
        if running and collections.contains_key(store, "ticks"):
            for tk in store["ticks"]:
                if tk["fn"](store, tk["ctx"]) == true:
                    _store.invalidate(store)
        if running and collections.contains_key(store, "animator"):
            _tanim.update(store["animator"])
        if running and render != null and store["dirty"]:
            _store.clear_dirty(store)
            render(store, ctx)
    return null
