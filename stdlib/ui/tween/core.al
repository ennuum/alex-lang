# ALEX UI V1.2 — Nœuds d'animation : tween, ressort, séquence, parallèle, attente, appel
#
# Un nœud est un dict décrivant une animation ; evaluate(node, t, anim) l'applique au temps LOCAL t
# (secondes depuis son début). C'est une fonction du temps : seek, vitesse négative (lecture
# inversée) et tests déterministes en découlent. Les animations ne bloquent jamais : elles sont
# avancées par un animateur (ui.tween.animator), typiquement depuis la boucle d'événements.
#
# Cibles : state (clé d'un store ui.state) | dict (propriété d'un widget moderne/thème) |
#          native (widget natif : x, y, width, height, progress) | fn (rappel fn(event)).
# Pas de fermetures en ALEX : les rappels sont des fonctions de premier niveau fn(event) avec
# event = {"node","value","progress","ctx","animator"}.
from core use type, len, clamp, is_function
use collections
use math as _math
use _native_ui as _native
use ui.state.store as _state
use ui.animation.easing as _easing
use ui.tween.interp as _interp

const MAX_SPRING_SETTLE := 20.0
const _UID := {"n": 0}

func _uid():
    _UID["n"] += 1
    return _UID["n"]

# ---------------------------------------------------------------- validation
func _num(v, name, fn):
    if not _interp.is_number(v):
        raise("TypeError", "ui.tween." + fn + "() : " + name + " doit être un nombre")

func _check_common(duration, delay, repeat, yoyo, fn):
    _num(duration, "duration", fn)
    if duration <= 0:
        raise("ArgumentError", "ui.tween." + fn + "() : duration doit être > 0")
    _num(delay, "delay", fn)
    if delay < 0:
        raise("ArgumentError", "ui.tween." + fn + "() : delay doit être >= 0")
    if type(repeat) != "int" or repeat < -1:
        raise("ArgumentError", "ui.tween." + fn + "() : repeat doit être un int >= 0 (ou -1 = infini)")
    if type(yoyo) != "bool":
        raise("TypeError", "ui.tween." + fn + "() : yoyo doit être un bool")

func _check_value(v, fn, name):
    if _interp.kind(v) == null:
        raise("TypeError", "ui.tween." + fn + "() : " + name + " doit être un nombre, une couleur {r,g,b[,a]} ou une list de nombres")

# ---------------------------------------------------------------- cibles
func target_state(store, key):
    if not _state.has(store, key):
        raise("KeyError", "ui.tween : clé d'état inconnue '" + str(key) + "'")
    return {"t": "state", "store": store, "key": key}

func target_dict(obj, prop):
    if type(obj) != "dict":
        raise("TypeError", "ui.tween : la cible doit être un dict (widget moderne, thème...)")
    if type(prop) != "str":
        raise("TypeError", "ui.tween : la propriété doit être une str")
    return {"t": "dict", "obj": obj, "prop": prop}

func target_native(handle, prop):
    if type(handle) != "int":
        raise("TypeError", "ui.tween : handle de widget natif (int) attendu")
    if prop != "x" and prop != "y" and prop != "width" and prop != "height" and prop != "progress":
        raise("ArgumentError", "ui.tween : propriété native non supportée '" + str(prop) + "' (x, y, width, height, progress)")
    return {"t": "native", "handle": handle, "prop": prop}

func target_fn(fn_value, ctx):
    if not is_function(fn_value):
        raise("TypeError", "ui.tween : une fonction est attendue")
    return {"t": "fn", "fn": fn_value, "ctx": ctx}

func _geometry(anim, handle):
    g := anim["geometry"]
    if not collections.contains_key(g, handle):
        raise("RuntimeError", "ui.tween : géométrie du widget natif " + str(handle) + " inconnue — appelez track_native(animator, handle, x, y, width, height) d'abord")
    return g[handle]

func target_read(tg, anim):
    t := tg["t"]
    if t == "state":
        return _state.get(tg["store"], tg["key"])
    if t == "dict":
        if not collections.contains_key(tg["obj"], tg["prop"]):
            raise("KeyError", "ui.tween : propriété inconnue '" + tg["prop"] + "'")
        return tg["obj"][tg["prop"]]
    if t == "native":
        if tg["prop"] == "progress":
            if collections.contains_key(tg, "last"):
                return tg["last"]
            raise("RuntimeError", "ui.tween : valeur de départ (start_value) requise pour progress")
        return _geometry(anim, tg["handle"])[tg["prop"]]
    raise("RuntimeError", "ui.tween : valeur de départ (start_value) requise pour cette cible")

func target_write(tg, value, anim):
    t := tg["t"]
    if t == "state":
        _state.set(tg["store"], tg["key"], value)
        return null
    if t == "dict":
        tg["obj"][tg["prop"]] = value
        return null
    if t == "native":
        h := tg["handle"]
        p := tg["prop"]
        if p == "progress":
            tg["last"] = value
            _native.progress_set(h, clamp(_math.floor(value + 0.5), 0, 100))
            return null
        g := _geometry(anim, h)
        g[p] = _math.floor(value + 0.5)
        if p == "x" or p == "y":
            _native.widget_set_position(h, g["x"], g["y"])
        else:
            w := g["width"]
            hh := g["height"]
            if w < 1:
                w = 1
            if hh < 1:
                hh = 1
            _native.widget_set_size(h, w, hh)
        return null
    if t == "fn":
        tg["fn"]({"value": value, "ctx": tg["ctx"], "node": null, "progress": null, "animator": anim})
        return null
    return null

# Identifiant stable d'une cible (pour remplacer une animation concurrente). null = non identifiable.
func target_tag(tg):
    t := tg["t"]
    if t == "state":
        s := tg["store"]
        if not collections.contains_key(s, "tween_uid"):
            s["tween_uid"] = _uid()
        return "s" + str(s["tween_uid"]) + ":" + tg["key"]
    if t == "dict":
        o := tg["obj"]
        if not collections.contains_key(o, "tween_uid"):
            o["tween_uid"] = _uid()
        return "d" + str(o["tween_uid"]) + ":" + tg["prop"]
    if t == "native":
        return "n" + str(tg["handle"]) + ":" + tg["prop"]
    return null

# ---------------------------------------------------------------- constructeurs
func _base(kind):
    return {"kind": kind, "delay": 0.0, "started": false, "done": false,
            "on_start": null, "on_update": null, "on_complete": null, "ctx": null}

func tween(target, end_value, duration, start_value=null, easing="ease_out", delay=0.0, repeat=0, yoyo=false):
    _check_common(duration, delay, repeat, yoyo, "tween")
    _check_value(end_value, "tween", "end_value")
    if start_value != null:
        _check_value(start_value, "tween", "start_value")
        if _interp.kind(start_value) != _interp.kind(end_value):
            raise("TypeError", "ui.tween.tween() : start_value et end_value doivent être du même type")
    _easing.evaluate(easing, 0.5)
    n := _base("tween")
    n["target"] = target
    n["start"] = start_value
    n["cur_start"] = start_value
    n["end"] = end_value
    n["duration"] = duration + 0.0
    n["delay"] = delay + 0.0
    n["easing"] = easing
    n["repeat"] = repeat
    n["yoyo"] = yoyo
    return n

func _spring_check(stiffness, damping, mass, delay):
    _num(stiffness, "stiffness", "spring")
    _num(damping, "damping", "spring")
    _num(mass, "mass", "spring")
    if stiffness <= 0 or mass <= 0:
        raise("ArgumentError", "ui.tween.spring() : stiffness et mass doivent être > 0")
    if damping < 0:
        raise("ArgumentError", "ui.tween.spring() : damping doit être >= 0")
    _num(delay, "delay", "spring")
    if delay < 0:
        raise("ArgumentError", "ui.tween.spring() : delay doit être >= 0")

func _spring_settle(n):
    w0 := _math.sqrt(n["stiffness"] / n["mass"])
    zeta := n["damping"] / (2.0 * _math.sqrt(n["stiffness"] * n["mass"]))
    decay := 0.0
    if zeta < 0.999999:
        decay = zeta * w0
    elif zeta <= 1.000001:
        decay = w0
    else:
        decay = w0 * (zeta - _math.sqrt(zeta * zeta - 1.0))
    if decay < 0.0000001:
        return MAX_SPRING_SETTLE
    t := 9.0 / decay
    if t > MAX_SPRING_SETTLE:
        return MAX_SPRING_SETTLE
    return t

# Ressort amorti (solution analytique : seek et lecture inversée fonctionnent). Nombres uniquement.
# velocity=null : vitesse héritée de l'animation de ressort remplacée (continuité), sinon 0.
func spring(target, end_value, start_value=null, stiffness=170.0, damping=26.0, mass=1.0, velocity=null, delay=0.0):
    _spring_check(stiffness, damping, mass, delay)
    _num(end_value, "end_value", "spring")
    if start_value != null:
        _num(start_value, "start_value", "spring")
    if velocity != null:
        _num(velocity, "velocity", "spring")
    n := _base("spring")
    n["target"] = target
    n["start"] = start_value
    n["cur_start"] = start_value
    n["end"] = end_value
    n["stiffness"] = stiffness + 0.0
    n["damping"] = damping + 0.0
    n["mass"] = mass + 0.0
    n["velocity"] = velocity
    n["v0"] = 0.0
    if velocity != null:
        n["v0"] = velocity + 0.0
    n["delay"] = delay + 0.0
    n["settle"] = _spring_settle(n)
    return n

# Déplacement X(t) du ressort par rapport à la cible, et sa vitesse X'(t). x0 = départ - cible.
func spring_state_at(n, lt, x0):
    w0 := _math.sqrt(n["stiffness"] / n["mass"])
    zeta := n["damping"] / (2.0 * _math.sqrt(n["stiffness"] * n["mass"]))
    v0 := n["v0"]
    if zeta < 0.999999:
        a := zeta * w0
        wd := w0 * _math.sqrt(1.0 - zeta * zeta)
        b := (v0 + a * x0) / wd
        e := _math.exp(0.0 - a * lt)
        c := _math.cos(wd * lt)
        s := _math.sin(wd * lt)
        return [e * (x0 * c + b * s), e * ((b * wd - a * x0) * c - (a * b + x0 * wd) * s)]
    if zeta <= 1.000001:
        k := v0 + w0 * x0
        e := _math.exp(0.0 - w0 * lt)
        return [e * (x0 + k * lt), e * (k - w0 * (x0 + k * lt))]
    sq := _math.sqrt(zeta * zeta - 1.0)
    r1 := 0.0 - w0 * (zeta - sq)
    r2 := 0.0 - w0 * (zeta + sq)
    c2 := (v0 - r1 * x0) / (r2 - r1)
    c1 := x0 - c2
    e1 := _math.exp(r1 * lt)
    e2 := _math.exp(r2 * lt)
    return [c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2]

func wait(seconds):
    _num(seconds, "seconds", "wait")
    if seconds < 0:
        raise("ArgumentError", "ui.tween.wait() : seconds doit être >= 0")
    n := _base("wait")
    n["duration"] = seconds + 0.0
    return n

# Appelle fn(event) une fois, au moment où le nœud est atteint.
func call(fn_value, ctx=null):
    if not is_function(fn_value):
        raise("TypeError", "ui.tween.call() : une fonction est attendue")
    n := _base("call")
    n["fn"] = fn_value
    n["ctx"] = ctx
    return n

func _check_nodes(nodes, fn):
    if type(nodes) != "list":
        raise("TypeError", "ui.tween." + fn + "() : une list de nœuds est attendue")
    for c in nodes:
        if type(c) != "dict" or not collections.contains_key(c, "kind"):
            raise("TypeError", "ui.tween." + fn + "() : élément invalide (nœud d'animation attendu)")

func sequence(nodes, delay=0.0):
    _check_nodes(nodes, "sequence")
    n := _base("sequence")
    n["children"] = nodes
    n["delay"] = delay + 0.0
    return n

func parallel(nodes, delay=0.0):
    _check_nodes(nodes, "parallel")
    n := _base("parallel")
    n["children"] = nodes
    n["delay"] = delay + 0.0
    return n

# Décale chaque nœud de i * each secondes puis les lance en parallèle (liste, cascade...).
func stagger(nodes, each, delay=0.0):
    _check_nodes(nodes, "stagger")
    _num(each, "each", "stagger")
    i := 0
    while i < len(nodes):
        c := nodes[i]
        if c["kind"] == "call":
            nodes[i] = sequence([wait(i * each), c])
        else:
            c["delay"] = c["delay"] + i * each
        i += 1
    return parallel(nodes, delay)

func callbacks(node, on_start=null, on_update=null, on_complete=null, ctx=null):
    if on_start != null:
        node["on_start"] = on_start
    if on_update != null:
        node["on_update"] = on_update
    if on_complete != null:
        node["on_complete"] = on_complete
    if ctx != null:
        node["ctx"] = ctx
    return node

# ---------------------------------------------------------------- durée / remise à zéro
# Durée totale en secondes (délai inclus) ; -1 = infinie (repeat=-1).
func total_duration(node):
    k := node["kind"]
    if k == "tween":
        if node["repeat"] < 0:
            return -1.0
        return node["delay"] + node["duration"] * (node["repeat"] + 1)
    if k == "spring":
        return node["delay"] + node["settle"]
    if k == "wait":
        return node["delay"] + node["duration"]
    if k == "call":
        return node["delay"]
    if k == "sequence":
        total := node["delay"]
        for c in node["children"]:
            d := total_duration(c)
            if d < 0:
                return -1.0
            total += d
        return total
    if k == "parallel":
        best := 0.0
        for c in node["children"]:
            d := total_duration(c)
            if d < 0:
                return -1.0
            if d > best:
                best = d
        return node["delay"] + best
    return 0.0

func reset(node):
    node["started"] = false
    node["done"] = false
    if collections.contains_key(node, "start"):
        node["cur_start"] = node["start"]
    if collections.contains_key(node, "children"):
        for c in node["children"]:
            reset(c)
    return node

# ---------------------------------------------------------------- évaluation
func _fire(anim, node, field, value, progress):
    cb := node[field]
    if cb == null:
        return null
    err := null
    try:
        cb({"node": node, "value": value, "progress": progress, "ctx": node["ctx"], "animator": anim})
    catch e:
        err = str(e)
    if err != null:
        collections.append(anim["errors"], err)
    return null

func _begin(anim, node):
    if not node["started"]:
        node["started"] = true
        _fire(anim, node, "on_start", null, 0.0)

func _finish(anim, node, value):
    if not node["done"]:
        node["done"] = true
        _fire(anim, node, "on_complete", value, 1.0)

func _capture_start(anim, node):
    if node["cur_start"] == null:
        node["cur_start"] = _interp.copy_value(target_read(node["target"], anim))
        if node["kind"] == "tween" and _interp.kind(node["cur_start"]) != _interp.kind(node["end"]):
            raise("TypeError", "ui.tween : la valeur courante de la cible n'est pas du même type que end_value")
        if node["kind"] == "spring" and not _interp.is_number(node["cur_start"]):
            raise("TypeError", "ui.tween.spring() : la valeur courante de la cible doit être un nombre")

func _eval_tween(node, t, anim):
    lt := t - node["delay"]
    if lt < 0:
        node["done"] = false
        return null
    _begin(anim, node)
    _capture_start(anim, node)
    dur := node["duration"]
    rep := node["repeat"]
    active_total := dur * (rep + 1)
    finished := rep >= 0 and lt >= active_total
    cycle := 0
    within := 1.0
    if finished:
        cycle = rep
    else:
        cycle = _math.floor(lt / dur)
        within = lt / dur - cycle
    if node["yoyo"] and cycle % 2 == 1:
        within = 1.0 - within
    eased := _easing.evaluate(node["easing"], within)
    value := _interp.interpolate(node["cur_start"], node["end"], eased)
    target_write(node["target"], value, anim)
    prog := within
    if rep >= 0:
        prog = clamp(lt / active_total, 0.0, 1.0)
    _fire(anim, node, "on_update", value, prog)
    if finished:
        _finish(anim, node, value)
    else:
        node["done"] = false
    return null

func _eval_spring(node, t, anim):
    lt := t - node["delay"]
    if lt < 0:
        node["done"] = false
        return null
    _begin(anim, node)
    _capture_start(anim, node)
    finished := lt >= node["settle"]
    value := node["end"]
    if not finished:
        st := spring_state_at(node, lt, node["cur_start"] - node["end"])
        value = node["end"] + st[0]
    target_write(node["target"], value, anim)
    _fire(anim, node, "on_update", value, clamp(lt / node["settle"], 0.0, 1.0))
    if finished:
        _finish(anim, node, value)
    else:
        node["done"] = false
    return null

# Vitesse courante d'un ressort au temps local t (0 pour les autres nœuds ou avant le départ).
func velocity_at(node, t):
    if node["kind"] != "spring" or not node["started"] or node["cur_start"] == null:
        return 0.0
    lt := t - node["delay"]
    if lt < 0 or lt >= node["settle"]:
        return 0.0
    return spring_state_at(node, lt, node["cur_start"] - node["end"])[1]

func evaluate(node, t, anim):
    k := node["kind"]
    if k == "tween":
        return _eval_tween(node, t, anim)
    if k == "spring":
        return _eval_spring(node, t, anim)
    lt := t - node["delay"]
    if lt < 0:
        node["done"] = false
        return null
    if k == "wait":
        _begin(anim, node)
        if lt >= node["duration"]:
            _finish(anim, node, null)
        else:
            node["done"] = false
        return null
    if k == "call":
        if not node["done"]:
            node["done"] = true
            err := null
            try:
                node["fn"]({"node": node, "value": null, "progress": 1.0, "ctx": node["ctx"], "animator": anim})
            catch e:
                err = str(e)
            if err != null:
                collections.append(anim["errors"], err)
        return null
    _begin(anim, node)
    total := total_duration(node)
    if k == "sequence":
        offset := node["delay"]
        for c in node["children"]:
            d := total_duration(c)
            local := t - offset
            if d >= 0 and local >= d:
                # enfant terminé : appliqué UNE fois (sinon il écraserait les enfants suivants)
                if not c["done"]:
                    evaluate(c, d, anim)
            elif local >= 0:
                evaluate(c, local, anim)
            else:
                evaluate(c, -1.0, anim)
            if d < 0:
                break
            offset += d
    elif k == "parallel":
        for c in node["children"]:
            d := total_duration(c)
            if d >= 0 and lt >= d:
                if not c["done"]:
                    evaluate(c, d, anim)
            else:
                evaluate(c, lt, anim)
    prog := 1.0
    if total > 0:
        prog = clamp(t / total, 0.0, 1.0)
    _fire(anim, node, "on_update", null, prog)
    if total >= 0 and t >= total:
        _finish(anim, node, null)
    else:
        node["done"] = false
    return null
