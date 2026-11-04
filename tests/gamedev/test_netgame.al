# ALEX - réseau multijoueur (netgame) : connexion fiable sur UDP, instantanés delta + interpolation, prédiction
# côté client + réconciliation, rollback. Liaisons simulées (latence, gigue, pertes, doublons) sur une horloge
# manuelle : résultats reproductibles. Plus un échange réel sur UDP local. ./alex run tests/gamedev/test_netgame.al
use math
use time
use netgame
use netgame.codec as nc
use netgame.snapshot as snap
use netgame.prediction as pred
use netgame.rollback as rb
use testing
from testing use assert_eq, assert_true, assert_near
from collections use append, keys
from core use to_int

const DT := 0.016666666666666666

# Serveur et client reliés par deux liaisons simulées.
func pair(clk, lat, jit, loss, dup, seed=1, max_clients=4):
    hub := netgame.LoopbackHub()
    s := netgame.Server(netgame.LinkSim(hub.endpoint("srv"), lat, jit, loss, dup, seed, clk), max_clients, netgame.PROTOCOL, 2.0, clk)
    c := netgame.Client(netgame.LinkSim(hub.endpoint("cli"), lat, jit, loss, dup, seed + 7, clk), netgame.PROTOCOL, 2.0, clk)
    c.connect("srv", 0)
    return [s, c, hub]

func t_codec():
    w := nc.Writer()
    w.uint(300)
    w.sint(-5)
    w.fixed(3.14159, 0.01)
    w.f64(-2.5e-3)
    w.text("héllo")
    v := {"a": [1, -2, 3.5, null, true, "x"], "b": {"c": false}}
    w.value(v)
    r := nc.Reader(w.data())
    assert_eq([r.uint(), r.sint(), r.fixed(0.01), r.f64(), r.text(), r.value()], [300, -5, 3.14, -0.0025, "héllo", v])
    assert_true(r.at_end())
    assert_eq(nc.checksum(nc.deep_copy(v)), nc.checksum(v))
    bad := false
    try:
        nc.Reader([6, 200]).value()
    catch e:
        bad = true
    assert_true(bad)

testing.test("codec : entiers variables, réels quantifiés, valeurs étiquetées", t_codec)

func t_reliable():
    clk := netgame.ManualClock()
    p := pair(clk, 0.05, 0.03, 0.3, 0.05)
    s := p[0]
    c := p[1]
    got := []
    unrel := 0
    big := [k % 251 for k in 0..5000]
    sent := 0
    k := 0
    while k < 900:
        for e in s.update():
            if e["type"] == "message":
                if e["reliable"]:
                    append(got, e["data"])
                else:
                    unrel += 1
        c.update()
        if c.connected() and sent < 60 and k % 2 == 0:
            c.send(sent, true)
            c.send({"pos": k}, false)
            if sent == 30:
                c.send(big, true)
            sent += 1
        s.flush()
        c.flush()
        clk.advance(DT)
        k += 1
    # 60 messages fiables + le gros, dans l'ordre malgré 30 % de pertes, gigue et doublons
    assert_eq(len(got), 61)
    exp := [i for i in 0..31] + [big] + [i for i in 31..60]
    assert_eq(got, exp)
    assert_true(unrel > 20 and unrel < 60)             # non fiable : une partie perdue, jamais en double
    assert_true(c.rtt() > 0.09 and c.rtt() < 0.25)    # 2 x 50 ms + gigue
    assert_true(c.conn.stats["resent"] > 0)

testing.test("fiable ordonné + non fiable + fragmentation sous 30 % de pertes", t_reliable)

func t_unreliable_fragments():
    clk := netgame.ManualClock()
    p := pair(clk, 0.02, 0.0, 0.0, 0.0)
    s := p[0]
    c := p[1]
    got := []
    k := 0
    while k < 200:
        for e in s.update():
            if e["type"] == "message":
                append(got, e["data"])
        c.update()
        if c.connected() and k % 20 == 0:
            c.send("z" * 3000, false)
        s.flush()
        c.flush()
        clk.advance(DT)
        k += 1
    assert_true(len(got) >= 8)
    assert_eq(len(got[0]), 3000)

testing.test("message non fiable fragmenté (3 morceaux)", t_unreliable_fragments)

func t_handshake():
    clk := netgame.ManualClock()
    hub := netgame.LoopbackHub()
    s := netgame.Server(hub.endpoint("srv"), 1, netgame.PROTOCOL, 1.0, clk)
    a := netgame.Client(hub.endpoint("a"), netgame.PROTOCOL, 1.0, clk)
    b := netgame.Client(hub.endpoint("b"), netgame.PROTOCOL, 1.0, clk)
    x := netgame.Client(hub.endpoint("x"), 0x1234, 1.0, clk)       # autre protocole : ignoré
    a.connect("srv", 0)
    ev := []
    k := 0
    while k < 30:
        for e in s.update():
            append(ev, e["type"])
        a.update()
        s.flush()
        a.flush()
        clk.advance(DT)
        k += 1
    assert_eq([ev, a.connected(), a.id], [["connect"], true, 1])
    b.connect("srv", 0)
    x.connect("srv", 0)
    reasons := []
    k = 0
    while k < 90:
        s.update()
        a.update()
        for e in b.update():
            append(reasons, e["reason"])
        for e in x.update():
            append(reasons, "x:" + e["reason"])
        s.flush()
        a.flush()
        clk.advance(DT)
        k += 1
    assert_eq(reasons, ["full", "x:timeout"])          # serveur plein ; protocole inconnu sans réponse
    assert_true(s.rejected > 0)
    # déconnexion propre, puis expiration
    a.disconnect()
    ev = []
    for e in s.update():
        append(ev, e["type"] + ":" + e["reason"])
    assert_eq(ev, ["disconnect:client"])
    b.connect("srv", 0)
    k = 0
    while k < 30:
        s.update()
        b.update()
        clk.advance(DT)
        k += 1
    assert_true(b.connected())
    ev = []
    k = 0
    while k < 90:                                       # le client se tait : expiration après 1 s
        for e in s.update():
            append(ev, e["type"] + ":" + e["reason"])
        clk.advance(DT)
        k += 1
    assert_eq(ev, ["disconnect:timeout"])

testing.test("poignée de main, serveur plein, protocole inconnu, déconnexion, expiration", t_handshake)

func world_at(tick):
    w := {}
    i := 1
    while i <= 6:
        if not (i == 4 and tick >= 40) and not (i == 6 and tick < 20):
            w[i] = {"x": math.cos(tick * 0.1 + i) * 10.0, "y": tick * 0.05 * i, "angle": tick * 0.2 + i,
                    "hp": 100 - (tick // 10) if i == 2 else 100, "nom": "j" + str(i), "vivant": true}
        i += 1
    return w

func t_snapshot():
    schema := snap.Schema([["x", "float", 0.01], ["y", "float", 0.01], ["angle", "angle"], ["hp", "uint"],
                           ["nom", "str"], ["vivant", "bool"]])
    clk := netgame.ManualClock()
    p := pair(clk, 0.04, 0.03, 0.2, 0.0, 3)
    s := p[0]
    c := p[1]
    ss := snap.SnapshotServer(schema)
    sc := snap.SnapshotClient(schema, 20.0, 0.1, 32, clk)
    tick := 0
    k := 0
    decoded := 0
    while k < 240:
        for e in s.update():
            if e["type"] == "message":
                ss.ack(e["client"], e["data"]["ack"])
        for e in c.update():
            if e["type"] == "message":
                if sc.receive(e["data"]) != null:
                    decoded += 1
        if k % 3 == 0:                                 # 20 Hz
            ss.capture(tick, world_at(tick))
            for id in s.client_ids():
                s.send(id, ss.encode(id, {"t": tick}))
            tick += 1
        if c.connected():
            c.send({"ack": sc.ack_tick()})
        s.flush()
        c.flush()
        clk.advance(DT)
        k += 1
    assert_true(decoded > 40)
    # le dernier instantané reconstruit = état quantifié du serveur à ce tick
    lt := sc.ack_tick()
    exp := {}
    w := world_at(lt)
    for id in keys(w):
        exp[id] = schema.dequantize(schema.quantize(w[id]))
    got := sc.latest()
    assert_eq(keys(got), keys(exp))
    assert_true(not (4 in got) and 6 in got)            # entité retirée, entité apparue
    for id in keys(exp):
        assert_eq(got[id]["hp"], exp[id]["hp"])
        assert_near(got[id]["x"], exp[id]["x"], 1e-9)
        assert_near(got[id]["angle"], exp[id]["angle"], 1e-9)
    assert_eq(sc.extra["t"], lt)
    # différentiel bien plus petit que complet
    st := ss.stats
    assert_true(st["delta_bytes"] / math.max(1, st["sent"] - 2) < 0.6 * (st["full_bytes"] / 2.0))
    # interpolation : temps de rendu = temps serveur - 100 ms
    rt := sc.render_tick()
    assert_true(rt < lt and rt > lt - 4.0)
    v := sc.sample()
    a := -1
    b := -1
    for t in sc.ticks:                                  # instantanés reçus qui encadrent le temps de rendu
        if t <= rt:
            a = t
        elif b < 0:
            b = t
    f := (rt - a) / (b - a)
    xa := schema.dequantize(schema.quantize(world_at(a)[1]))["x"]
    xb := schema.dequantize(schema.quantize(world_at(b)[1]))["x"]
    assert_near(v[1]["x"], xa + (xb - xa) * f, 1e-9)
    assert_near(v[1]["y"], (a + (b - a) * f) * 0.05, 0.011)

testing.test("instantanés delta sous pertes, apparition / retrait, interpolation", t_snapshot)

func t_angle_lerp():
    schema := snap.Schema([["a", "angle"]])
    q1 := schema.quantize({"a": 3.0})
    q2 := schema.quantize({"a": -3.0})                 # 3.0 -> -3.0 : passer par pi, pas par 0
    m := schema.lerp(q1, q2, 0.5)["a"]
    assert_true(math.abs(math.abs(m) - math.PI) < 0.01)

testing.test("angles : interpolation par le plus court chemin", t_angle_lerp)

# Jeu de test : déplacement à vitesse fixe ; le serveur borne x <= limite (mur inconnu du client).
func move(s, e, dt):
    return {"x": s["x"] + e["dx"] * 4.0 * dt, "y": s["y"] + e["dy"] * 4.0 * dt}

func run_prediction(wall, loss):
    clk := netgame.ManualClock()
    p := pair(clk, 0.06, 0.02, loss, 0.0, 5)
    s := p[0]
    c := p[1]
    ib := pred.InputBuffer()
    auth := {"x": 0.0, "y": 0.0}
    pr := pred.Predictor(move, {"x": 0.0, "y": 0.0}, DT, ["x", "y"])
    k := 0
    while k < 480:
        for e in s.update():
            if e["type"] == "message":
                ib.receive(e["data"]["in"])
        for e in c.update():
            if e["type"] == "message":
                pr.reconcile(e["data"]["me"], e["data"]["input"])
        # serveur : une entrée par pas, rattrapage si plusieurs sont arrivées ensemble
        for inp in ib.pop_all(3):
            auth = move(auth, inp, DT)
            if auth["x"] > wall:
                auth["x"] = wall
        if k % 3 == 0:
            for id in s.client_ids():
                s.send(id, {"me": auth, "input": ib.last})
        if c.connected():
            if k < 360:
                pr.apply({"dx": 1 if (k // 60) % 2 == 0 else 0, "dy": 1 if k % 120 < 30 else 0})
            c.send({"in": pr.pending_inputs()})
        s.flush()
        c.flush()
        clk.advance(DT)
        k += 1
    return [pr, auth, ib]

func t_prediction():
    # simulation identique des deux côtés : aucune correction, et état final identique au serveur
    r := run_prediction(1000.0, 0.1)
    pr := r[0]
    assert_eq(r[2].last, pr.seq)                        # toutes les entrées traitées malgré 10 % de pertes
    assert_near(pr.state["x"], r[1]["x"], 1e-9)
    assert_near(pr.state["y"], r[1]["y"], 1e-9)
    assert_eq(pr.corrections, 0)
    assert_eq(len(pr.pending), 0)
    # le serveur bloque x à 1,5 (mur) : le client se corrige, sans téléportation visible
    r2 := run_prediction(1.5, 0.1)
    p2 := r2[0]
    assert_true(p2.corrections > 0)
    assert_near(p2.state["x"], 1.5, 1e-9)
    assert_near(p2.state["y"], r2[1]["y"], 1e-9)
    v := p2.visual(1.0)
    assert_near(v["x"], 1.5, 1e-3)                      # correction lissée amortie

testing.test("prédiction client + réconciliation (sans erreur ; avec mur côté serveur)", t_prediction)

func t_input_buffer():
    b := pred.InputBuffer()
    b.receive([3, ["c", "d"]])
    assert_eq(b.pop(), null)                           # 1 et 2 manquent encore
    b.receive([1, ["a", "b", "c"]])                    # redondance
    assert_eq(b.pop_all(), ["a", "b", "c", "d"])
    assert_eq([b.last, b.pop(true)], [4, "d"])

testing.test("tampon d'entrées serveur (désordre, redondance)", t_input_buffer)

# ---- rollback ----

# Simulation déterministe en entiers : chaque joueur se déplace, rebondit, marque en touchant le centre.
func rb_step(s, ins):
    i := 0
    while i < len(ins):
        e := ins[i] if ins[i] != null else 0
        pl := s["p"][i]
        pl[0] = pl[0] + (e % 3 - 1) * 7
        pl[1] = pl[1] + ((e // 3) % 3 - 1) * 5
        if pl[0] < 0 or pl[0] > 1000:
            pl[0] = math.max(0, math.min(1000, pl[0]))
        if math.abs(pl[0] - 500) < 30 and math.abs(pl[1]) < 30:
            pl[2] = pl[2] + 1
        i += 1
    s["t"] = s["t"] + 1
    return s

func script_input(player, frame):
    return ((frame // 7) * 31 + player * 17 + (frame // 23) * 5) % 9

func rb_initial(n):
    return {"t": 0, "p": [[100 + 200 * i, 0, 0] for i in 0..n]}

func reference(n, frames):
    s := rb_initial(n)
    f := 0
    while f < frames:
        ins := []
        p := 0
        while p < n:
            append(ins, 0 if f < 2 else script_input(p, f - 2))
            p += 1
        s = rb_step(s, ins)
        f += 1
    return s

func run_rollback(n, lat, jit, loss, frames):
    clk := netgame.ManualClock()
    hub := netgame.LoopbackHub()
    host := netgame.Server(netgame.LinkSim(hub.endpoint("h"), lat, jit, loss, 0.0, 11, clk), 8, netgame.PROTOCOL, 3.0, clk)
    eps := [host]
    k := 1
    while k < n:
        c := netgame.Client(netgame.LinkSim(hub.endpoint("c" + str(k)), lat, jit, loss, 0.0, 11 + k, clk), netgame.PROTOCOL, 3.0, clk)
        c.connect("h", 0)
        append(eps, c)
        k += 1
    # connexion
    k = 0
    while k < 120:
        for ep in eps:
            ep.update()
            ep.flush()
        clk.advance(DT)
        k += 1
    sess := []
    links := []
    k = 0
    while k < n:
        se := rb.RollbackSession(n, k, rb_step, rb_initial(n), 2, 12)
        append(sess, se)
        append(links, rb.RollbackNet(se, eps[k]))
        k += 1
    waits := 0
    t := 0
    while t < frames * 3 and sess[0].confirmed_frame() < frames + 2:
        k = 0
        while k < n:
            for e in eps[k].update():
                links[k].handle(e)
            se := sess[k]
            if not links[k].should_wait():
                if se.local_next - 2 < frames:
                    se.add_local_input(script_input(k, se.local_next - 2))
                else:
                    se.add_local_input(0)
                se.advance()
            else:
                waits += 1
            links[k].send()
            eps[k].flush()
            k += 1
        clk.advance(DT)
        t += 1
    return [sess, waits]

func t_rollback_two():
    r := run_rollback(2, 0.05, 0.02, 0.1, 240)
    sess := r[0]
    ref := reference(2, 200)
    for se in sess:
        assert_true(se.confirmed_frame() >= 200)
        assert_eq(se.checksum_at(199), nc.checksum(ref))   # état confirmé = simulation de référence
        assert_eq(se.desync, null)
    assert_true(sess[0].stats["rollbacks"] > 0 or sess[1].stats["rollbacks"] > 0)
    assert_true(sess[0].stats["max_depth"] <= 12)

testing.test("rollback à 2 joueurs : 50 ms, gigue, 10 % de pertes -> états identiques", t_rollback_two)

func t_rollback_three():
    r := run_rollback(3, 0.04, 0.01, 0.05, 150)
    ref := reference(3, 120)
    for se in r[0]:
        assert_eq(se.checksum_at(119), nc.checksum(ref))
        assert_eq(se.desync, null)

testing.test("rollback à 3 joueurs relayés par l'hôte", t_rollback_three)

func t_rollback_local():
    # mauvaise prédiction corrigée immédiatement, attente au-delà de max_rollback, désynchronisation détectée
    s := rb.RollbackSession(2, 0, rb_step, rb_initial(2), 0, 4)
    f := 0
    while f < 4:
        s.add_local_input(1)
        assert_true(s.advance())
        f += 1
    s.add_local_input(1)
    assert_eq(s.advance(), false)                      # 5e image sans entrée distante : attente
    s.add_remote_input(1, 0, 4)
    s.add_remote_input(1, 1, 4)
    assert_true(s.advance())
    assert_eq(s.stats["rollbacks"], 1)                 # la prédiction (null) différait : resimulation
    m := s.pack()
    m["c"] = [0, 12345]
    s2 := rb.RollbackSession(2, 1, rb_step, rb_initial(2), 0, 4)
    s2.add_local_input(4)
    s2.add_remote_input(0, 0, 1)
    s2.advance()
    s2.unpack(m)
    assert_eq(s2.desync["frame"], 0)

testing.test("rollback : resimulation, attente, désynchronisation détectée", t_rollback_local)

func t_udp_real():
    srv := netgame.Server(netgame.UdpTransport("127.0.0.1", 0), 4)
    port := srv.transport.port()
    cli := netgame.Client(netgame.UdpTransport("127.0.0.1", 0))
    cli.connect("127.0.0.1", port)
    echo := null
    k := 0
    while k < 400 and echo == null:
        for e in srv.update():
            if e["type"] == "message":
                srv.send(e["client"], {"echo": e["data"]}, true)
        for e in cli.update():
            if e["type"] == "message":
                echo = e["data"]
        if cli.connected() and k % 10 == 0:
            cli.send([1, "deux", 3.0], true)
        srv.flush()
        cli.flush()
        time.sleep(0.005)
        k += 1
    assert_eq(echo, {"echo": [1, "deux", 3.0]})
    cli.close()
    srv.shutdown()

testing.test("UDP réel sur la boucle locale", t_udp_real)

func t_hostile():
    # paquets aléatoires, tronqués ou altérés : rejetés sans exception, la connexion continue
    clk := netgame.ManualClock()
    hub := netgame.LoopbackHub()
    s := netgame.Server(hub.endpoint("srv"), 4, netgame.PROTOCOL, 2.0, clk)
    c := netgame.Client(hub.endpoint("cli"), netgame.PROTOCOL, 2.0, clk)
    evil := hub.endpoint("cli")                       # même adresse que le client (usurpation)
    c.connect("srv", 0)
    rng := netgame.Rng(99)
    got := 0
    k := 0
    while k < 300:
        for e in s.update():
            if e["type"] == "message":
                got += 1
        c.update()
        if c.connected():
            c.send(k, true)
        n := to_int(rng.next() * 40)
        junk := [to_int(rng.next() * 256) for i in 0..n]
        if k % 3 == 0 and n > 3:
            junk[0] = 0x41
            junk[1] = 0x4E
            junk[2] = to_int(rng.next() * 8)
        evil.send(["srv", 0], junk)
        s.flush()
        c.flush()
        clk.advance(DT)
        k += 1
    assert_true(c.connected())
    assert_true(got > 250)
    assert_true(s.rejected > 0)

testing.test("paquets hostiles : rejetés, la connexion tient", t_hostile)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) netgame en échec")
print("NETGAME: OK")
