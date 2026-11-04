# ALEX UI V1.1 — Reactive store (état réactif)
#
# Un store est un dict de valeurs observables. Principes :
#   * set() ne notifie que si la valeur change réellement (comparaison structurelle `==`).
#   * Les valeurs CALCULÉES (computed) suivent automatiquement leurs dépendances : toute clé lue
#     par la fonction via get() est enregistrée ; les dépendances sont ré-évaluées à chaque calcul.
#   * Les notifications sont groupées : batch_begin()/batch_end() (ou transaction()) fusionnent
#     plusieurs set() en UNE passe ; une valeur remise à son état initial dans le lot n'émet rien ;
#     un calcul « diamant » (A -> B,C -> D) n'est notifié qu'une fois.
#   * Pas de fermetures en ALEX : un observateur est une fonction de premier niveau
#     fn(event) avec event = {"store","key","value","old","ctx"} ; l'état utile passe par `ctx`.
#   * Les erreurs d'observateurs ne corrompent pas le store : tous les observateurs s'exécutent,
#     puis la première erreur est relevée (strict=true) ou conservée dans errors() (strict=false).
#   * Protection contre les boucles de réactivité (MAX_ROUNDS passes) et les dépendances circulaires.
#
# Les valeurs du store doivent être des DONNÉES (nombres, str, bool, list, dict) : la comparaison
# structurelle de graphes cycliques (ex. widgets avec parent/enfants) n'est pas supportée.
# Les helpers sont déclarés avant leur usage (limite de l'analyseur : pas de référence en avant).
from core use type, len, is_function
use collections

const VERSION := "1.1.0"
const MAX_ROUNDS := 100

func _is_store(store):
    return type(store) == "dict" and collections.contains_key(store, "kind") and store["kind"] == "store"

func _check(store, fn):
    if not _is_store(store):
        raise("TypeError", "ui.state." + fn + "() : store invalide")

func _check_key(key, fn):
    if type(key) != "str" or key == "":
        raise("TypeError", "ui.state." + fn + "() : la clé doit être une str non vide")

func _check_fn(fn_value, fn):
    if not is_function(fn_value):
        raise("TypeError", "ui.state." + fn + "() : une fonction est attendue")

func create(initial=null, strict=true):
    store := {
        "kind": "store", "strict": strict,
        "values": {}, "computed": {}, "computed_order": [], "dependents": {},
        "watchers": {}, "any": [], "sub_index": {}, "next_id": 1,
        "version": 0, "dirty": false, "batch": 0,
        "pending": {}, "pending_order": [], "forced": {}, "affected": {},
        "tracking": null, "flushing": false, "errors": [],
        "links": {}, "handlers": {}
    }
    if initial != null:
        if type(initial) != "dict":
            raise("TypeError", "ui.state.create() : l'état initial doit être un dict")
        for key in initial:
            _check_key(key, "create")
            store["values"][key] = initial[key]
    return store

func has(store, key):
    _check(store, "has")
    return collections.contains_key(store["values"], key) or collections.contains_key(store["computed"], key)

func is_computed(store, key):
    _check(store, "is_computed")
    return collections.contains_key(store["computed"], key)

func _track(store, key):
    t := store["tracking"]
    if t != null:
        if not collections.contains(t, key):
            collections.append(t, key)

func _recompute(store, key):
    comp := store["computed"][key]
    if comp["evaluating"]:
        raise("RuntimeError", "ui.state : dépendance circulaire sur '" + key + "'")
    prev := store["tracking"]
    deps := []
    store["tracking"] = deps
    comp["evaluating"] = true
    value := null
    err := null
    try:
        value = comp["fn"](store)
    catch e:
        err = str(e)
    store["tracking"] = prev
    comp["evaluating"] = false
    if err != null:
        raise("RuntimeError", "ui.state : calcul de '" + key + "' échoué : " + err)
    for old in comp["deps"]:
        if collections.contains_key(store["dependents"], old):
            if collections.contains_key(store["dependents"][old], key):
                collections.remove(store["dependents"][old], key)
    for dep in deps:
        if not collections.contains_key(store["dependents"], dep):
            store["dependents"][dep] = {}
        store["dependents"][dep][key] = true
    comp["deps"] = deps
    comp["value"] = value
    comp["dirty"] = false
    return value

func get(store, key):
    _check(store, "get")
    if collections.contains_key(store["values"], key):
        _track(store, key)
        return store["values"][key]
    if collections.contains_key(store["computed"], key):
        _track(store, key)
        comp := store["computed"][key]
        if comp["dirty"]:
            _recompute(store, key)
        return comp["value"]
    raise("KeyError", "ui.state.get() : clé inconnue '" + str(key) + "'")

func get_or(store, key, fallback=null):
    if has(store, key):
        return get(store, key)
    return fallback

func _mark_dependents(store, key):
    deps := store["dependents"]
    if not collections.contains_key(deps, key):
        return null
    for ck in deps[key]:
        store["affected"][ck] = true
        comp := store["computed"][ck]
        if not comp["dirty"]:
            comp["dirty"] = true
            _mark_dependents(store, ck)
    return null

func _record(store, key, old):
    if not collections.contains_key(store["pending"], key):
        store["pending"][key] = old
        collections.append(store["pending_order"], key)
    _mark_dependents(store, key)

func _invoke(store, sub, ev):
    event := {"store": store, "key": ev["key"], "value": ev["value"], "old": ev["old"], "ctx": sub["ctx"]}
    try:
        sub["fn"](event)
    catch e:
        collections.append(store["errors"], str(e))
    return null

func _call_subs(store, subs, ev):
    snapshot := []
    for s in subs:
        collections.append(snapshot, s)
    for s in snapshot:
        if s["active"]:
            _invoke(store, s, ev)
    return null

func _raise_errors(store):
    if len(store["errors"]) > 0 and store["strict"]:
        msg := store["errors"][0]
        store["errors"] = []
        raise("RuntimeError", "ui.state : erreur dans un observateur : " + msg)
    return null

func _reset_pending(store):
    store["pending"] = {}
    store["pending_order"] = []
    store["forced"] = {}
    store["affected"] = {}

# Exécute les notifications en attente. Retourne true si au moins une valeur a changé.
func flush(store):
    _check(store, "flush")
    if store["flushing"] or store["batch"] > 0:
        return false
    store["flushing"] = true
    rounds := 0
    notified := false
    while len(store["pending_order"]) > 0 or len(store["affected"]) > 0:
        rounds += 1
        if rounds > MAX_ROUNDS:
            store["flushing"] = false
            _reset_pending(store)
            raise("RuntimeError", "ui.state : boucle de réactivité infinie (plus de " + str(MAX_ROUNDS) + " passes)")
        order := store["pending_order"]
        pend := store["pending"]
        forced := store["forced"]
        affected := store["affected"]
        _reset_pending(store)
        changed := []
        for key in order:
            cur := store["values"][key]
            if collections.contains_key(forced, key) or cur != pend[key]:
                collections.append(changed, {"key": key, "value": cur, "old": pend[key]})
        for ck in store["computed_order"]:
            if collections.contains_key(affected, ck):
                comp := store["computed"][ck]
                if comp["dirty"]:
                    err := null
                    try:
                        _recompute(store, ck)
                    catch e:
                        err = str(e)
                    if err != null:
                        collections.append(store["errors"], err)
                if not comp["dirty"] and comp["value"] != comp["notified"]:
                    collections.append(changed, {"key": ck, "value": comp["value"], "old": comp["notified"]})
                    comp["notified"] = comp["value"]
        if len(changed) > 0:
            store["version"] += 1
            store["dirty"] = true
            notified = true
        for ch in changed:
            if collections.contains_key(store["watchers"], ch["key"]):
                _call_subs(store, store["watchers"][ch["key"]], ch)
            _call_subs(store, store["any"], ch)
    store["flushing"] = false
    _raise_errors(store)
    return notified

func set(store, key, value):
    _check(store, "set")
    if collections.contains_key(store["computed"], key):
        raise("ArgumentError", "ui.state.set() : '" + str(key) + "' est une valeur calculée (lecture seule)")
    if not collections.contains_key(store["values"], key):
        raise("KeyError", "ui.state.set() : clé inconnue '" + str(key) + "' (utilisez define() pour la créer)")
    old := store["values"][key]
    if old == value:
        return false
    store["values"][key] = value
    _record(store, key, old)
    flush(store)
    return true

func define(store, key, value=null):
    _check(store, "define")
    _check_key(key, "define")
    if has(store, key):
        raise("ArgumentError", "ui.state.define() : '" + key + "' existe déjà")
    store["values"][key] = value
    return value

func update(store, key, fn_value):
    _check_fn(fn_value, "update")
    return set(store, key, fn_value(get(store, key)))

# Force la notification après une mutation EN PLACE d'une list/dict stockée.
func touch(store, key):
    _check(store, "touch")
    if not collections.contains_key(store["values"], key):
        raise("KeyError", "ui.state.touch() : clé inconnue '" + str(key) + "'")
    _record(store, key, store["values"][key])
    store["forced"][key] = true
    flush(store)
    return true

func batch_begin(store):
    _check(store, "batch_begin")
    store["batch"] += 1
    return store["batch"]

func batch_end(store):
    _check(store, "batch_end")
    if store["batch"] == 0:
        raise("RuntimeError", "ui.state.batch_end() : aucun lot ouvert")
    store["batch"] -= 1
    if store["batch"] == 0:
        return flush(store)
    return false

# Exécute fn(store, ctx) dans un lot ; les notifications sont émises à la fin, même en cas d'erreur.
func transaction(store, fn_value, ctx=null):
    _check_fn(fn_value, "transaction")
    batch_begin(store)
    err := null
    try:
        fn_value(store, ctx)
    catch e:
        err = str(e)
    batch_end(store)
    if err != null:
        raise("RuntimeError", "ui.state.transaction() : " + err)
    return null

func set_many(store, values):
    if type(values) != "dict":
        raise("TypeError", "ui.state.set_many() : un dict est attendu")
    batch_begin(store)
    err := null
    try:
        for key in values:
            set(store, key, values[key])
    catch e:
        err = str(e)
    batch_end(store)
    if err != null:
        raise("RuntimeError", "ui.state.set_many() : " + err)
    return null

# Valeur calculée : fn(store) -> valeur, dépendances détectées automatiquement via get().
func computed(store, key, fn_value):
    _check(store, "computed")
    _check_key(key, "computed")
    _check_fn(fn_value, "computed")
    if has(store, key):
        raise("ArgumentError", "ui.state.computed() : '" + key + "' existe déjà")
    store["computed"][key] = {"fn": fn_value, "deps": [], "value": null, "notified": null, "dirty": true, "evaluating": false}
    collections.append(store["computed_order"], key)
    err := null
    try:
        _recompute(store, key)
    catch e:
        err = str(e)
    if err != null:
        collections.remove(store["computed"], key)
        order := []
        for k in store["computed_order"]:
            if k != key:
                collections.append(order, k)
        store["computed_order"] = order
        raise("RuntimeError", err)
    comp := store["computed"][key]
    comp["notified"] = comp["value"]
    return comp["value"]

func _add_sub(store, key, fn_value, ctx):
    sub := {"id": store["next_id"], "fn": fn_value, "ctx": ctx, "active": true, "key": key}
    store["next_id"] += 1
    store["sub_index"][sub["id"]] = sub
    return sub

func watch(store, key, fn_value, ctx=null, immediate=false):
    _check(store, "watch")
    _check_fn(fn_value, "watch")
    if not has(store, key):
        raise("KeyError", "ui.state.watch() : clé inconnue '" + str(key) + "'")
    sub := _add_sub(store, key, fn_value, ctx)
    if not collections.contains_key(store["watchers"], key):
        store["watchers"][key] = []
    collections.append(store["watchers"][key], sub)
    if immediate:
        _invoke(store, sub, {"key": key, "value": get(store, key), "old": null})
        _raise_errors(store)
    return sub["id"]

func watch_all(store, fn_value, ctx=null):
    _check(store, "watch_all")
    _check_fn(fn_value, "watch_all")
    sub := _add_sub(store, null, fn_value, ctx)
    collections.append(store["any"], sub)
    return sub["id"]

func _without(subs, id):
    kept := []
    for s in subs:
        if s["id"] != id:
            collections.append(kept, s)
    return kept

func unwatch(store, id):
    _check(store, "unwatch")
    if not collections.contains_key(store["sub_index"], id):
        return false
    sub := store["sub_index"][id]
    sub["active"] = false
    collections.remove(store["sub_index"], id)
    if sub["key"] == null:
        store["any"] = _without(store["any"], id)
    else:
        store["watchers"][sub["key"]] = _without(store["watchers"][sub["key"]], id)
    return true

func version(store):
    _check(store, "version")
    return store["version"]

func is_dirty(store):
    _check(store, "is_dirty")
    return store["dirty"]

func clear_dirty(store):
    _check(store, "clear_dirty")
    store["dirty"] = false
    return null

# Demande un nouveau rendu sans changer de valeur (ex. redimensionnement).
func invalidate(store):
    _check(store, "invalidate")
    store["dirty"] = true
    return null

func errors(store):
    _check(store, "errors")
    out := []
    for e in store["errors"]:
        collections.append(out, e)
    return out

func clear_errors(store):
    _check(store, "clear_errors")
    store["errors"] = []
    return null

func snapshot(store):
    _check(store, "snapshot")
    snap := {}
    for key in store["values"]:
        snap[key] = store["values"][key]
    return snap

func restore(store, snap):
    _check(store, "restore")
    if type(snap) != "dict":
        raise("TypeError", "ui.state.restore() : un snapshot (dict) est attendu")
    set_many(store, snap)
    return null

func to_dict(store):
    _check(store, "to_dict")
    out := snapshot(store)
    for ck in store["computed_order"]:
        out[ck] = get(store, ck)
    return out
