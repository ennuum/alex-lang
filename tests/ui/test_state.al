# Tests de ui.state (V1.1 — état réactif) : logique pure, sans fenêtre.
from core use type, len
use collections
use ui.state as state

func check(cond, name):
    if not cond:
        raise("AssertionError", "ÉCHEC : " + name)
    print("ok  " + name)

# ---- observateurs de test (fonctions de premier niveau, état via ctx) ----
func rec(ev):
    collections.append(ev["ctx"], [ev["key"], ev["value"], ev["old"]])

func rec_count(ev):
    ev["ctx"]["n"] += 1

func boom(ev):
    raise("RuntimeError", "observateur en panne")

func inc_self(ev):
    state.set(ev["store"], "n", ev["value"] + 1)

func unwatch_self(ev):
    ev["ctx"]["n"] += 1
    state.unwatch(ev["store"], ev["ctx"]["id"])

func ping(ev):
    state.set(ev["store"], "b", ev["value"] + 1)

func pong(ev):
    state.set(ev["store"], "a", ev["value"] + 1)

# ---- valeurs de base ----
s := state.create({"a": 1, "b": 2, "name": "Alex"})
check(state.get(s, "a") == 1, "get")
check(state.has(s, "a") and not state.has(s, "zz"), "has")
check(state.get_or(s, "zz", 42) == 42, "get_or")
check(state.set(s, "a", 1) == false, "set identique -> pas de changement")
check(state.version(s) == 0 and not state.is_dirty(s), "aucune notification pour un no-op")
check(state.set(s, "a", 2) == true, "set valeur différente")
failed := false
try:
    state.get(s, "inconnue")
catch e:
    failed = true
check(failed, "get clé inconnue -> KeyError")
failed = false
try:
    state.set(s, "typo", 1)
catch e:
    failed = true
check(failed, "set clé inconnue -> erreur (protège des fautes de frappe)")
state.define(s, "extra", 7)
check(state.get(s, "extra") == 7, "define")
failed = false
try:
    state.define(s, "extra", 8)
catch e:
    failed = true
check(failed, "define doublon -> erreur")

# ---- watchers ----
log := []
id1 := state.watch(s, "a", rec, log)
state.set(s, "a", 10)
check(len(log) == 1 and log[0][0] == "a" and log[0][1] == 10 and log[0][2] == 2, "watch : key/value/old")
check(state.is_dirty(s) and state.version(s) == 2, "dirty + version après changement")
state.clear_dirty(s)
check(not state.is_dirty(s), "clear_dirty")
state.set(s, "b", 99)
check(len(log) == 1, "watch ne reçoit que sa clé")
check(state.unwatch(s, id1), "unwatch")
state.set(s, "a", 11)
check(len(log) == 1, "plus de notification après unwatch")
check(state.unwatch(s, id1) == false, "unwatch deux fois -> false")

log2 := []
state.watch(s, "a", rec, log2, true)
check(len(log2) == 1 and log2[0][1] == 11, "watch immediate")

all_log := []
state.watch_all(s, rec, all_log)
state.set(s, "name", "Zed")
state.set(s, "b", 1)
check(len(all_log) == 2 and all_log[0][0] == "name" and all_log[1][0] == "b", "watch_all")

# désabonnement pendant la notification
s2 := state.create({"n": 0})
c := {"n": 0, "id": 0}
c["id"] = state.watch(s2, "n", unwatch_self, c)
state.set(s2, "n", 1)
state.set(s2, "n", 2)
check(c["n"] == 1, "un observateur peut se désabonner pendant la notification")

# ---- lots (batch) ----
s3 := state.create({"x": 1, "y": 1})
bl := []
state.watch_all(s3, rec, bl)
state.batch_begin(s3)
state.set(s3, "x", 2)
state.set(s3, "y", 2)
check(len(bl) == 0, "batch : rien n'est émis avant batch_end")
check(state.get(s3, "x") == 2, "batch : lecture immédiate de la nouvelle valeur")
state.batch_end(s3)
check(len(bl) == 2, "batch : une notification par clé à la fin")
bl2 := []
s4 := state.create({"x": 1})
state.watch_all(s4, rec, bl2)
state.batch_begin(s4)
state.set(s4, "x", 5)
state.set(s4, "x", 1)
state.batch_end(s4)
check(len(bl2) == 0, "batch : valeur revenue à l'état initial -> aucune notification")
state.batch_begin(s4)
state.batch_begin(s4)
state.set(s4, "x", 3)
state.batch_end(s4)
check(len(bl2) == 0, "lots imbriqués : émission à la fermeture du lot externe")
state.batch_end(s4)
check(len(bl2) == 1, "lots imbriqués : émis une fois")
failed = false
try:
    state.batch_end(s4)
catch e:
    failed = true
check(failed, "batch_end sans batch_begin -> erreur")

func tx(store, ctx):
    state.set(store, "x", 100)
    state.set(store, "y", 200)
state.transaction(s3, tx)
check(state.get(s3, "x") == 100 and state.get(s3, "y") == 200, "transaction")

func tx_fail(store, ctx):
    state.set(store, "x", 1)
    raise("RuntimeError", "échec voulu")
failed = false
try:
    state.transaction(s3, tx_fail)
catch e:
    failed = true
check(failed and state.get(s3, "x") == 1, "transaction : erreur propagée, lot refermé, valeurs conservées")
state.set(s3, "x", 55)
check(state.get(s3, "x") == 55, "store utilisable après une transaction échouée")

state.set_many(s3, {"x": 7, "y": 8})
check(state.get(s3, "x") == 7 and state.get(s3, "y") == 8, "set_many")

# ---- valeurs calculées ----
func total(store):
    return state.get(store, "price") * state.get(store, "qty")
func label(store):
    return "Total=" + str(state.get(store, "total"))
func vat(store):
    return state.get(store, "total") * 0.2

s5 := state.create({"price": 10, "qty": 2})
check(state.computed(s5, "total", total) == 20, "computed : valeur initiale")
state.computed(s5, "label", label)
check(state.get(s5, "label") == "Total=20", "computed chaîné")
cl := []
state.watch(s5, "label", rec, cl)
state.watch(s5, "total", rec, cl)
state.set(s5, "qty", 3)
check(state.get(s5, "total") == 30 and state.get(s5, "label") == "Total=30", "computed recalculé")
check(len(cl) == 2 and cl[0][0] == "total" and cl[1][0] == "label", "computed : notifié dans l'ordre des dépendances")
check(cl[0][2] == 20 and cl[0][1] == 30, "computed : value/old")
failed = false
try:
    state.set(s5, "total", 1)
catch e:
    failed = true
check(failed, "computed en lecture seule")
check(state.is_computed(s5, "total") and not state.is_computed(s5, "qty"), "is_computed")

# diamant : A -> B, C -> D ; D n'est notifié qu'une fois par changement de A
func db(store):
    return state.get(store, "a") + 1
func dc(store):
    return state.get(store, "a") * 2
func dd(store):
    return state.get(store, "b") + state.get(store, "c")
s6 := state.create({"a": 1})
state.computed(s6, "b", db)
state.computed(s6, "c", dc)
state.computed(s6, "d", dd)
dl := {"n": 0}
state.watch(s6, "d", rec_count, dl)
state.set(s6, "a", 5)
check(state.get(s6, "d") == 16 and dl["n"] == 1, "diamant : D recalculé et notifié une seule fois")

# computed sans effet net : pas de notification
func parity(store):
    return state.get(store, "a") % 2
s7 := state.create({"a": 1})
state.computed(s7, "parity", parity)
pl := {"n": 0}
state.watch(s7, "parity", rec_count, pl)
state.set(s7, "a", 3)
check(pl["n"] == 0, "computed : valeur inchangée -> pas de notification")
state.set(s7, "a", 4)
check(pl["n"] == 1, "computed : valeur changée -> notification")

# dépendances dynamiques
func pick(store):
    if state.get(store, "use_a"):
        return state.get(store, "a")
    return state.get(store, "b")
s8 := state.create({"use_a": true, "a": 1, "b": 2})
state.computed(s8, "pick", pick)
dn := {"n": 0}
state.watch(s8, "pick", rec_count, dn)
state.set(s8, "b", 20)
check(dn["n"] == 0, "dépendance dynamique : 'b' non lu tant que use_a")
state.set(s8, "use_a", false)
check(state.get(s8, "pick") == 20 and dn["n"] == 1, "dépendance dynamique : bascule sur 'b'")
state.set(s8, "a", 99)
check(dn["n"] == 1, "dépendance dynamique : 'a' n'est plus une dépendance")

# lecture paresseuse dans un lot
s9 := state.create({"a": 1})
func plus1(store):
    return state.get(store, "a") + 1
state.computed(s9, "p", plus1)
state.batch_begin(s9)
state.set(s9, "a", 10)
check(state.get(s9, "p") == 11, "computed lu pendant un lot : valeur à jour")
state.batch_end(s9)

# erreurs
func selfref(store):
    return state.get(store, "self") + 1
failed = false
try:
    state.computed(s9, "self", selfref)
catch e:
    failed = true
check(failed and not state.has(s9, "self"), "dépendance circulaire détectée, computed non enregistré")
func bad(store):
    return 1 / 0
failed = false
try:
    state.computed(s9, "bad", bad)
catch e:
    failed = true
check(failed and not state.has(s9, "bad"), "computed qui lève : non enregistré")
check(state.get(s9, "a") == 10, "store intact après erreurs de computed")

# ---- erreurs d'observateurs ----
s10 := state.create({"a": 0})
okc := {"n": 0}
state.watch(s10, "a", boom)
state.watch(s10, "a", rec_count, okc)
failed = false
try:
    state.set(s10, "a", 1)
catch e:
    failed = true
check(failed, "strict : l'erreur d'un observateur est relevée")
check(okc["n"] == 1, "strict : les autres observateurs ont quand même été appelés")
check(state.get(s10, "a") == 1, "strict : la valeur est bien appliquée")
s11 := state.create({"a": 0}, false)
state.watch(s11, "a", boom)
state.set(s11, "a", 1)
check(len(state.errors(s11)) == 1, "non strict : erreur conservée dans errors()")
state.clear_errors(s11)
check(len(state.errors(s11)) == 0, "clear_errors")

# ---- boucle infinie ----
s12 := state.create({"n": 0})
state.watch(s12, "n", inc_self)
failed = false
try:
    state.set(s12, "n", 1)
catch e:
    failed = true
check(failed, "boucle de réactivité infinie interrompue")
s13 := state.create({"a": 0, "b": 0})
state.watch(s13, "a", ping)
state.watch(s13, "b", pong)
failed = false
try:
    state.set(s13, "a", 1)
catch e:
    failed = true
check(failed, "ping-pong entre deux clés interrompu")

# ---- touch / update / snapshot / restore / to_dict ----
func append_item(items):
    collections.append(items, "x")
    return items
func plus_one(v):
    return v + 1
s14 := state.create({"items": [], "n": 1})
tl := {"n": 0}
state.watch(s14, "items", rec_count, tl)
collections.append(state.get(s14, "items"), "a")
check(tl["n"] == 0, "mutation en place : pas de notification automatique")
state.touch(s14, "items")
check(tl["n"] == 1, "touch force la notification")
state.update(s14, "n", plus_one)
check(state.get(s14, "n") == 2, "update")
snap := state.snapshot(s14)
state.set(s14, "n", 50)
state.restore(s14, snap)
check(state.get(s14, "n") == 2, "snapshot / restore")
d := state.to_dict(s5)
check(d["total"] == 30 and d["qty"] == 3, "to_dict inclut les valeurs calculées")
failed = false
try:
    state.watch(s14, "inconnue", rec_count, {"n": 0})
catch e:
    failed = true
check(failed, "watch clé inconnue -> erreur")
failed = false
try:
    state.get("pas un store", "a")
catch e:
    failed = true
check(failed, "store invalide -> TypeError")
print("UI STATE: OK")
