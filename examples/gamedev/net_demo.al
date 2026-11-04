# Démo réseau multijoueur (netgame) : arène 2D, serveur autoritaire, instantanés delta interpolés, prédiction côté
# client avec réconciliation.
#
#   ./alex run examples/gamedev/net_demo.al                      # SOLO : serveur + vous + un robot dans ce
#                                                                 # processus, liaison simulée 100 ms / 5 % de pertes
#   ./alex run examples/gamedev/net_demo.al serveur 27015         # serveur seul (sans fenêtre)
#   ./alex run examples/gamedev/net_demo.al client 192.168.1.20 27015
#   options : latence=0.1 perte=0.05 (liaison simulée ajoutée côté client) ; images=N : quitter après N images
#
# Flèches / ZQSD : se déplacer. P : prédiction marche / arrêt (sans elle, on voit le retard). Échap : quitter.
# Votre carré est prédit (réaction immédiate) ; le contour blanc est la dernière position confirmée par le serveur ;
# les autres joueurs sont interpolés 100 ms dans le passé.

from collections use append, keys, remove
from core use len, to_int, to_float
use os
use math
use time
use gl.window as glw
use gl.render as gr
use netgame
use netgame.snapshot as snap
use netgame.prediction as pred

const W := 1280.0
const H := 720.0
const SPEED := 260.0
const SIM_DT := 0.016666666666666666
const SNAP_EVERY := 3            # 20 instantanés / s
const SIZE := 28.0
const COLORS := [[0.95, 0.35, 0.3, 1.0], [0.3, 0.75, 0.95, 1.0], [0.45, 0.9, 0.4, 1.0], [0.95, 0.8, 0.3, 1.0],
                 [0.8, 0.45, 0.95, 1.0], [0.95, 0.55, 0.75, 1.0]]

# Simulation partagée (identique sur le serveur et le client).
func move(s, e, dt):
    x := s["x"] + e["dx"] * SPEED * dt
    y := s["y"] + e["dy"] * SPEED * dt
    return {"x": math.max(SIZE, math.min(W - SIZE, x)), "y": math.max(SIZE, math.min(H - SIZE, y))}

SCHEMA := snap.Schema([["x", "float", 0.01], ["y", "float", 0.01], ["c", "uint"]])

class GameServer:
    func init(transport, clock):
        self.net = netgame.Server(transport, 16, netgame.PROTOCOL, 5.0, clock)
        self.clock = clock
        self.snaps = snap.SnapshotServer(SCHEMA)
        self.players = {}            # id -> {"s": état, "buf": InputBuffer, "c": couleur}
        self.tick = 0
        self.acc = 0.0
        self.last = clock.now()

    func step():
        now := self.clock.now()
        for e in self.net.update(now):
            id := e["client"]
            if e["type"] == "connect":
                self.players[id] = {"s": {"x": 200.0 + 150.0 * (id % 6), "y": H / 2.0}, "buf": pred.InputBuffer(),
                                    "c": (id - 1) % len(COLORS)}
                print("serveur : joueur " + str(id) + " connecté depuis " + str(e["address"]))
            elif e["type"] == "disconnect":
                if id in self.players:
                    remove(self.players, id)
                self.snaps.forget(id)
                print("serveur : joueur " + str(id) + " parti (" + e["reason"] + ")")
            elif e["type"] == "message" and id in self.players:
                m := e["data"]
                self.players[id]["buf"].receive(m["in"])
                self.snaps.ack(id, m["ack"])
        self.acc += math.min(0.25, now - self.last)
        self.last = now
        while self.acc >= SIM_DT:
            self.acc -= SIM_DT
            for id in keys(self.players):
                p := self.players[id]
                n := 1 if len(keys(p["buf"].queue)) < 4 else 2          # rattrapage si les entrées s'accumulent
                for inp in p["buf"].pop_all(n):
                    p["s"] = move(p["s"], inp, SIM_DT)
            self.tick += 1
            if self.tick % SNAP_EVERY == 0:
                world := {}
                for id in keys(self.players):
                    p := self.players[id]
                    world[id] = {"x": p["s"]["x"], "y": p["s"]["y"], "c": p["c"]}
                self.snaps.capture(self.tick // SNAP_EVERY, world)
                for id in keys(self.players):
                    p := self.players[id]
                    self.net.send(id, self.snaps.encode(id, {"input": p["buf"].last, "me": p["s"]}))
        self.net.flush(now)

class GameClient:
    func init(transport, clock, host, port):
        self.net = netgame.Client(transport, netgame.PROTOCOL, 5.0, clock)
        self.net.connect(host, port)
        self.clock = clock
        self.snaps = snap.SnapshotClient(SCHEMA, 60.0 / SNAP_EVERY, 0.1, 32, clock)
        self.pred = pred.Predictor(move, {"x": W / 2.0, "y": H / 2.0}, SIM_DT, ["x", "y"])
        self.server_me = null
        self.acc = 0.0
        self.last = clock.now()
        self.predict = true
        self.started = false

    func step(input):
        now := self.clock.now()
        for e in self.net.update(now):
            if e["type"] == "message":
                r := self.snaps.receive(e["data"], now)
                if r != null and r[1] != null and r[0] == self.snaps.ack_tick():
                    self.server_me = r[1]["me"]
                    if not self.started:
                        self.pred.state = r[1]["me"]
                        self.started = true
                    self.pred.reconcile(r[1]["me"], r[1]["input"])
            elif e["type"] == "disconnect":
                print("client : déconnecté (" + e["reason"] + ")")
        self.acc += math.min(0.25, now - self.last)
        self.last = now
        while self.acc >= SIM_DT and self.net.connected():
            self.acc -= SIM_DT
            self.pred.apply(input)
            self.net.send({"in": self.pred.pending_inputs(), "ack": self.snaps.ack_tick()})
        self.net.flush(now)

    # [moi (état affiché), autres {id: état}]
    func view(frame_dt):
        me := self.pred.visual(frame_dt) if self.predict else (self.server_me if self.server_me != null else self.pred.state)
        others := self.snaps.sample()
        if self.net.id in others:
            remove(others, self.net.id)
        return [me, others]

# ---------------------------------------------------------------------------------------------------------------------

args := os.args()
mode := args[0] if len(args) > 0 else "solo"
opts := {}
for a in args:
    i := 0
    while i < len(a) and a[i] != '=':
        i += 1
    if i < len(a):
        opts[a[0:i]] = a[i + 1:len(a)]
lat := to_float(opts["latence"]) if "latence" in opts else 0.1
loss := to_float(opts["perte"]) if "perte" in opts else 0.05

clock := netgame.Clock()

if mode == "serveur":
    port := to_int(args[1]) if len(args) > 1 else 27015
    gs := GameServer(netgame.UdpTransport("0.0.0.0", port), clock)
    print("serveur netgame sur le port UDP " + str(port) + " (Ctrl+C pour arrêter)")
    while true:
        gs.step()
        time.sleep(0.004)
else:
    server := null
    bot := null
    cl := null
    if mode == "client":
        host := args[1] if len(args) > 1 else "127.0.0.1"
        port := to_int(args[2]) if len(args) > 2 else 27015
        tr := netgame.UdpTransport("0.0.0.0", 0)
        if "latence" in opts or "perte" in opts:
            tr = netgame.LinkSim(tr, lat / 2.0, 0.01, loss, 0.0, 7, clock)
        cl = GameClient(tr, clock, host, port)
    else:
        hub := netgame.LoopbackHub()
        server = GameServer(netgame.LinkSim(hub.endpoint("serveur"), lat / 2.0, 0.015, loss, 0.0, 1, clock), clock)
        cl = GameClient(netgame.LinkSim(hub.endpoint("vous"), lat / 2.0, 0.015, loss, 0.0, 2, clock), clock, "serveur", 0)
        bot = GameClient(netgame.LinkSim(hub.endpoint("robot"), lat / 2.0, 0.015, loss, 0.0, 3, clock), clock, "serveur", 0)
    w := glw.Window("ALEX — réseau multijoueur", 1280, 720, {"vsync": true})
    r := gr.Renderer(w)
    batch := gr.SpriteBatch(r)
    bot_dir := [1, 0]
    max_frames := to_int(opts["images"]) if "images" in opts else -1       # essais automatiques
    while w.is_open() and (max_frames < 0 or w.frame_count < max_frames):
        for e in w.poll():
            if e["type"] == "key_down" and e["key"] == "escape":
                w.close()
            if e["type"] == "key_down" and e["key"] == "p":
                cl.predict = not cl.predict
        if not w.is_open():
            break
        dx := 0
        dy := 0
        if max_frames > 0:
            dx = 1 if (w.frame_count // 90) % 2 == 0 else -1               # pilote automatique
        if w.key_down("left") or w.key_down("q"):
            dx -= 1
        if w.key_down("right") or w.key_down("d"):
            dx += 1
        if w.key_down("up") or w.key_down("z"):
            dy -= 1
        if w.key_down("down") or w.key_down("s"):
            dy += 1
        if server != null:
            server.step()
        cl.step({"dx": dx, "dy": dy})
        if bot != null:
            if w.frame_count % 50 == 0:
                bot_dir = [[1, 0], [0, 1], [-1, 0], [0, -1], [1, 1], [-1, -1]][(w.frame_count // 50) % 6]
            bot.step({"dx": bot_dir[0], "dy": bot_dir[1]})
        v := cl.view(w.dt if w.dt > 0.0 else SIM_DT)
        r.begin_frame([0.07, 0.08, 0.11, 1.0])
        batch.begin()
        gx := 0.0
        while gx < W:
            batch.rect(gx, 0, 1, H, [0.12, 0.13, 0.17, 1.0])
            gx += 64.0
        gy := 0.0
        while gy < H:
            batch.rect(0, gy, W, 1, [0.12, 0.13, 0.17, 1.0])
            gy += 64.0
        for id in keys(v[1]):
            o := v[1][id]
            batch.rect(o["x"] - SIZE / 2.0, o["y"] - SIZE / 2.0, SIZE, SIZE, COLORS[o["c"] % len(COLORS)])
        me := v[0]
        col := COLORS[(cl.net.id - 1) % len(COLORS)] if cl.net.id > 0 else [1.0, 1.0, 1.0, 1.0]
        batch.rect(me["x"] - SIZE / 2.0, me["y"] - SIZE / 2.0, SIZE, SIZE, col)
        if cl.server_me != null:
            sm := cl.server_me
            batch.rect_outline(sm["x"] - SIZE / 2.0, sm["y"] - SIZE / 2.0, SIZE, SIZE, [1.0, 1.0, 1.0, 0.8], 2.0)
        batch.end()
        w.swap()
        if w.frame_count % 30 == 0:
            st := "connexion..." if not cl.net.connected() else ("joueur " + str(cl.net.id) + " — RTT " + str(to_int(cl.net.rtt() * 1000.0)) + " ms — pertes " + str(to_int(cl.net.conn.loss * 100.0)) + " % — corrections " + str(cl.pred.corrections) + " — prédiction " + ("oui" if cl.predict else "non"))
            w.set_title("ALEX — réseau multijoueur — " + st)
    if max_frames > 0:
        print("images " + str(w.frame_count) + ", connecté " + str(cl.net.connected()) + ", corrections " + str(cl.pred.corrections) + ", autres joueurs " + str(len(keys(cl.snaps.sample()))) + ", en attente " + str(len(cl.pred.pending)))
    cl.net.disconnect()
