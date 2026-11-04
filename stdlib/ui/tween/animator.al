# ALEX UI V1.2 — Animateur : exécute des nœuds d'animation sans jamais bloquer
#
# L'animateur avance ses animations (« handles ») par tick(animator, dt) — dt déterministe, pour les
# tests — ou update(animator), qui lit l'horloge monotone et limite à `fps` images/s.
# attach(animator, store) l'intègre à ui.state.run : l'animateur est avancé à chaque tour de boucle
# et le store est marqué « dirty » quand une animation a écrit quelque chose (re-rendu).
# Concurrence : jouer une animation avec le même tag qu'une animation en cours REMPLACE celle-ci
# (le tag par défaut identifie la cible : clé d'état, propriété de widget, propriété native).
# Un ressort remplaçant un ressort hérite de sa vitesse : l'interruption reste fluide.
from core use type, len, clamp, is_function
use collections
use os as _os
use ui.state.store as _state
use ui.tween.core as _core

const DEFAULT_FPS := 60
const MAX_DT := 0.1
const MAX_HISTORY := 256

func create(fps=60, strict=true):
    if type(fps) != "int" or fps < 1:
        raise("ArgumentError", "ui.tween.create() : fps doit être un int >= 1")
    return {"kind": "animator", "handles": [], "index": {}, "next_id": 1, "scale": 1.0, "fps": fps,
            "last": null, "errors": [], "strict": strict, "geometry": {}, "store": null, "dirty": false}

func _check(anim, fn):
    if type(anim) != "dict" or not collections.contains_key(anim, "kind") or anim["kind"] != "animator":
        raise("TypeError", "ui.tween." + fn + "() : animateur invalide")

# Intègre l'animateur à un store : state.run l'avance et redessine quand il écrit.
func attach(anim, store):
    _check(anim, "attach")
    anim["store"] = store
    store["animator"] = anim
    return anim

# Enregistre la géométrie d'un widget natif (les natifs n'ont pas de getter de position/taille).
func track_native(anim, handle, x, y, width, height):
    _check(anim, "track_native")
    anim["geometry"][handle] = {"x": x, "y": y, "width": width, "height": height}
    return handle

func _handle(anim, id, fn):
    _check(anim, fn)
    if not collections.contains_key(anim["index"], id):
        raise("KeyError", "ui.tween." + fn + "() : animation inconnue (" + str(id) + ")")
    return anim["index"][id]

func _remove_active(anim, h):
    kept := []
    for x in anim["handles"]:
        if x["id"] != h["id"]:
            collections.append(kept, x)
    anim["handles"] = kept

func _prune(anim):
    if len(anim["index"]) <= MAX_HISTORY:
        return null
    ids := []
    for id in anim["index"]:
        if anim["index"][id]["state"] == "finished" or anim["index"][id]["state"] == "cancelled":
            collections.append(ids, id)
    collections.sort(ids)
    drop := len(anim["index"]) - MAX_HISTORY
    i := 0
    while i < drop and i < len(ids):
        collections.remove(anim["index"], ids[i])
        i += 1
    return null

func _end(anim, h, state_name):
    h["state"] = state_name
    _remove_active(anim, h)
    _prune(anim)

func _auto_tag(node):
    if collections.contains_key(node, "target"):
        return _core.target_tag(node["target"])
    return null

# Applique l'état courant d'un handle ; le termine si le temps est écoulé (ou revenu à 0).
func _apply(anim, h):
    err := null
    try:
        t := h["t"]
        if h["total"] >= 0 and t >= h["total"]:
            _core.evaluate(h["node"], h["total"], anim)
            _end(anim, h, "finished")
        elif t <= 0 and h["speed"] < 0:
            _core.evaluate(h["node"], 0.0, anim)
            _end(anim, h, "finished")
        else:
            _core.evaluate(h["node"], t, anim)
        anim["dirty"] = true
    catch e:
        err = str(e)
    if err != null:
        collections.append(anim["errors"], err)
        if h["state"] == "running":
            _end(anim, h, "cancelled")
    return null

func _raise_errors(anim):
    if len(anim["errors"]) > 0 and anim["strict"]:
        msg := anim["errors"][0]
        anim["errors"] = []
        raise("RuntimeError", "ui.tween : erreur d'animation : " + msg)
    return null

# Lance une animation ; retourne son identifiant. tag=null : tag de la cible (voir en-tête).
func play(anim, node, tag=null, speed=1.0):
    _check(anim, "play")
    if type(node) != "dict" or not collections.contains_key(node, "kind"):
        raise("TypeError", "ui.tween.play() : nœud d'animation invalide")
    if not (type(speed) == "int" or type(speed) == "float") or speed == 0:
        raise("ArgumentError", "ui.tween.play() : speed doit être un nombre non nul")
    _core.reset(node)
    if tag == null:
        tag = _auto_tag(node)
    if tag != null:
        for old in anim["handles"]:
            if old["tag"] == tag:
                if node["kind"] == "spring" and node["velocity"] == null and old["node"]["kind"] == "spring":
                    node["v0"] = _core.velocity_at(old["node"], old["t"])
                _end(anim, old, "cancelled")
    total := _core.total_duration(node)
    h := {"id": anim["next_id"], "node": node, "t": 0.0, "speed": speed + 0.0, "paused": false,
          "state": "running", "tag": tag, "total": total}
    anim["next_id"] += 1
    collections.append(anim["handles"], h)
    anim["index"][h["id"]] = h
    _apply(anim, h)
    _raise_errors(anim)
    return h["id"]

# Avance toutes les animations de dt secondes (temps « animateur », avant vitesse/échelle).
func tick(anim, dt):
    _check(anim, "tick")
    if not (type(dt) == "int" or type(dt) == "float") or dt < 0:
        raise("ArgumentError", "ui.tween.tick() : dt doit être un nombre >= 0")
    snapshot := []
    for h in anim["handles"]:
        collections.append(snapshot, h)
    for h in snapshot:
        if h["state"] == "running" and not h["paused"]:
            h["t"] = h["t"] + dt * h["speed"] * anim["scale"]
            if h["t"] < 0:
                h["t"] = 0.0
            _apply(anim, h)
    if anim["dirty"]:
        anim["dirty"] = false
        if anim["store"] != null:
            _state.invalidate(anim["store"])
    _raise_errors(anim)
    return len(anim["handles"])

# Avance selon l'horloge monotone (limitée à `fps` images/s, dt plafonné à MAX_DT).
# Retourne true si une image a été calculée.
func update(anim):
    _check(anim, "update")
    if len(anim["handles"]) == 0:
        anim["last"] = null
        return false
    now := _os.monotonic_time()
    if anim["last"] == null:
        anim["last"] = now
        return false
    dt := now - anim["last"]
    if dt < 1.0 / anim["fps"]:
        return false
    anim["last"] = now
    if dt > MAX_DT:
        dt = MAX_DT
    tick(anim, dt)
    return true

func pause(anim, id):
    _handle(anim, id, "pause")["paused"] = true
    return id

func resume(anim, id):
    _handle(anim, id, "resume")["paused"] = false
    return id

func cancel(anim, id):
    h := _handle(anim, id, "cancel")
    if h["state"] != "running":
        return false
    _end(anim, h, "cancelled")
    return true

# Saute à la fin : applique la valeur finale et déclenche on_complete.
func finish(anim, id):
    h := _handle(anim, id, "finish")
    if h["state"] != "running":
        return false
    if h["total"] < 0:
        raise("RuntimeError", "ui.tween.finish() : animation infinie (repeat=-1)")
    h["t"] = h["total"] + 0.0
    _apply(anim, h)
    return true

# Place l'animation au temps t (secondes locales) et l'applique.
func seek(anim, id, t):
    h := _handle(anim, id, "seek")
    if h["state"] != "running":
        raise("RuntimeError", "ui.tween.seek() : animation terminée ou annulée")
    h["t"] = clamp(t, 0.0, 1000000.0) + 0.0
    _apply(anim, h)
    return t

func set_speed(anim, id, speed):
    if not (type(speed) == "int" or type(speed) == "float") or speed == 0:
        raise("ArgumentError", "ui.tween.set_speed() : speed doit être un nombre non nul")
    _handle(anim, id, "set_speed")["speed"] = speed + 0.0
    return speed

func reverse(anim, id):
    h := _handle(anim, id, "reverse")
    h["speed"] = 0.0 - h["speed"]
    return h["speed"]

# Échelle de temps globale (ralenti/accéléré, 0 = gel de toutes les animations).
func set_time_scale(anim, scale):
    _check(anim, "set_time_scale")
    if not (type(scale) == "int" or type(scale) == "float") or scale < 0:
        raise("ArgumentError", "ui.tween.set_time_scale() : scale doit être un nombre >= 0")
    anim["scale"] = scale + 0.0
    return scale

func state(anim, id):
    return _handle(anim, id, "state")["state"]

func is_active(anim, id=null):
    _check(anim, "is_active")
    if id == null:
        return len(anim["handles"]) > 0
    if not collections.contains_key(anim["index"], id):
        return false
    return anim["index"][id]["state"] == "running"

func active_count(anim):
    _check(anim, "active_count")
    return len(anim["handles"])

func clear(anim):
    _check(anim, "clear")
    for h in anim["handles"]:
        h["state"] = "cancelled"
    anim["handles"] = []
    anim["last"] = null
    return null

func errors(anim):
    _check(anim, "errors")
    out := []
    for e in anim["errors"]:
        collections.append(out, e)
    return out

func clear_errors(anim):
    _check(anim, "clear_errors")
    anim["errors"] = []
    return null

# ---- raccourcis : construire + lancer ----
func animate_state(anim, store, key, end_value, duration, start_value=null, easing="ease_out", delay=0.0, repeat=0, yoyo=false):
    return play(anim, _core.tween(_core.target_state(store, key), end_value, duration, start_value, easing, delay, repeat, yoyo))

func animate_prop(anim, obj, prop, end_value, duration, start_value=null, easing="ease_out", delay=0.0, repeat=0, yoyo=false):
    return play(anim, _core.tween(_core.target_dict(obj, prop), end_value, duration, start_value, easing, delay, repeat, yoyo))

func animate_native(anim, handle, prop, end_value, duration, start_value=null, easing="ease_out", delay=0.0, repeat=0, yoyo=false):
    return play(anim, _core.tween(_core.target_native(handle, prop), end_value, duration, start_value, easing, delay, repeat, yoyo))

func spring_state(anim, store, key, end_value, start_value=null, stiffness=170.0, damping=26.0, mass=1.0, velocity=null):
    return play(anim, _core.spring(_core.target_state(store, key), end_value, start_value, stiffness, damping, mass, velocity))

func spring_prop(anim, obj, prop, end_value, start_value=null, stiffness=170.0, damping=26.0, mass=1.0, velocity=null):
    return play(anim, _core.spring(_core.target_dict(obj, prop), end_value, start_value, stiffness, damping, mass, velocity))

func spring_native(anim, handle, prop, end_value, start_value=null, stiffness=170.0, damping=26.0, mass=1.0, velocity=null):
    return play(anim, _core.spring(_core.target_native(handle, prop), end_value, start_value, stiffness, damping, mass, velocity))
