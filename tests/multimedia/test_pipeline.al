# multimedia.pipeline : nœuds, graphe (validation, ordre, cycles), planificateur (contre-pression, fan-out,
# fusion, fin de flux, annulation, blocage, arrêt propre), reprise sur erreur, horloges, synchronisation A/V.
from core use len
from collections use append
from multimedia.pipeline.node use Node
use audio.audio_format as af
use multimedia.core.buffer as mb
use multimedia.core.cancellation as mc
use multimedia.container.demux as dmx
use multimedia.container.mux as mux
use multimedia.pipeline.node as nd
use multimedia.pipeline.graph as pg
use multimedia.pipeline.scheduler as ps
use multimedia.pipeline.backpressure as bp
use multimedia.pipeline.recovery as rec
use multimedia.pipeline.clock as pc
use multimedia.pipeline.sync as sy
use multimedia.testing.fixtures as fx
use multimedia.testing.assertions as ta

t := ta.Checker("multimedia pipeline")

# ---------------------------------------------------------------- files bornées
q := bp.BoundedQueue(2)
t.check(q.push(1) and q.push(2) and not q.push(3) and q.size() == 2, "block : file pleine refuse")
t.check(q.push(nd.EOS) and q.size() == 3, "une fin de flux passe toujours")
t.check(q.pop() == 1 and q.pop() == 2 and nd.is_eos(q.pop()) and q.pop() == null, "ordre FIFO")
qo := bp.BoundedQueue(2, "drop_oldest")
qo.push(1)
qo.push(2)
qo.push(3)
t.check(qo.pop() == 2 and qo.dropped == 1, "drop_oldest")
qn := bp.BoundedQueue(1, "drop_newest")
qn.push(1)
t.check(not qn.push(2) and qn.pop() == 1 and qn.dropped == 1, "drop_newest")
t.raises("LimitError", () => _fill(bp.BoundedQueue(1, "error")), "politique error")
func _fill(qq):
    qq.push(1)
    qq.push(2)
big := bp.BoundedQueue(1000)
for i in 0..500:
    big.push(i)
for i in 0..400:
    big.pop()
t.check(big.size() == 100 and big.peek() == 400 and big.stats()["high_water"] == 500, "compactage interne")

# ---------------------------------------------------------------- chaîne simple
out := nd.collect("out")
r := ps.run_chain([nd.from_list("src", [1, 2, 3, 4, 5]), nd.map("x2", (x) => x * 2), nd.filter("pas6", (x) => x != 6), out], 2)
t.check(out.items == [2, 4, 8, 10] and r["finished"] and out.ended, "map / filter / collect")
t.check(r["nodes"]["x2"]["processed"] == 5 and r["nodes"]["pas6"]["produced"] == 4, "compteurs par nœud")
lots := nd.collect("lots")
ps.run_chain([nd.from_list("s", [1, 2, 3, 4, 5]), nd.batch("b", 2), lots])
t.check(lots.items == [[1, 2], [3, 4], [5]], "regroupement et vidage final")

# ---------------------------------------------------------------- contre-pression : la source ne déborde jamais
produced := [0]
func gen():
    produced[0] += 1
    if produced[0] > 1000:
        return nd.EOS
    return produced[0]
slow := nd.collect("lent")
g := pg.Graph()
g.add(nd.from_function("gen", gen))
g.add(nd.map("id", (x) => x))
g.add(slow)
g.connect("gen", "id", 4)
g.connect("id", "lent", 4)
s := ps.Scheduler(g, 3)
s.step()
t.check(produced[0] <= 3 + 1 and g.inputs("id")[0].queue.size() <= 4, "pas plus d'éléments que le budget et la file")
r2 := s.run()
t.check(len(slow.items) == 1000 and slow.items[999] == 1000, "tout arrive, dans l'ordre")
mx := 0
for e in g.edges:
    if e.queue.high_water > mx:
        mx = e.queue.high_water
t.check(mx <= 5, "files jamais au-delà de leur capacité (+ fin de flux) : " + str(mx))

# ---------------------------------------------------------------- fan-out et fusion
g2 := pg.Graph()
g2.add(nd.from_list("a", [1, 2, 3]))
g2.add(nd.from_list("b", [10, 20]))
g2.add(nd.map("fusion", (x) => x))
g2.add(nd.collect("c1"))
g2.add(nd.collect("c2"))
g2.connect("a", "fusion")
g2.connect("b", "fusion")
g2.connect("fusion", "c1")
g2.connect("fusion", "c2")
ps.Scheduler(g2).run()
c1 := g2.node("c1").items
t.check(len(c1) == 5 and c1 == g2.node("c2").items and (1 in c1) and (20 in c1), "fusion de deux sources, duplication vers deux puits")

# ---------------------------------------------------------------- validation
gv := pg.Graph()
gv.add(nd.map("m1", (x) => x))
gv.add(nd.map("m2", (x) => x))
gv.connect("m1", "m2")
gv.connect("m2", "m1")
t.raises("PipelineError", () => gv.validate(), "pas de source / cycle")
gc := pg.Graph()
gc.add(nd.from_list("s", [1]))
gc.add(nd.map("m1", (x) => x))
gc.add(nd.map("m2", (x) => x))
gc.connect("s", "m1")
gc.connect("m1", "m2")
gc.connect("m2", "m1")
t.raises("PipelineError", () => gc.order(), "cycle détecté")
gi := pg.Graph()
gi.add(nd.from_list("s", [1]))
gi.add(nd.collect("seul"))
t.raises("PipelineError", () => gi.validate(), "nœud sans entrée")
t.raises("PipelineError", () => gi.connect("seul", "s"), "une source n'a pas d'entrée")
t.raises("PipelineError", () => gi.add(nd.collect("seul")), "nom en double")
t.raises("PipelineError", () => gi.connect("s", "inconnu"), "nœud inconnu")

# ---------------------------------------------------------------- reprise sur erreur
func risky(x):
    if x == 0:
        raise("CorruptDataError", "bloc illisible")
    return 10 // x
gr := pg.Graph()
gr.add(nd.from_list("s", [1, 0, 2, 0, 5]))
gr.add(nd.map("div", risky))
gr.add(nd.collect("c"))
gr.chain(["s", "div", "c"])
journal := []
pol := rec.skip()
pol.on_error = (n, ty, m) => append(journal, n)
gr.set_recovery("div", pol)
rs := ps.Scheduler(gr).run()
t.check(gr.node("c").items == [10, 5, 2] and rs["nodes"]["div"]["skipped"] == 2 and len(journal) == 2, "skip : éléments fautifs jetés")
tries := [0]
func flaky(x):
    tries[0] += 1
    if tries[0] % 2 == 1:
        raise("DeviceError", "occupé")
    return x
gf := pg.Graph()
gf.add(nd.from_list("s", [7, 8]))
gf.add(nd.map("f", flaky))
gf.add(nd.collect("c"))
gf.chain(["s", "f", "c"])
gf.set_recovery("f", rec.retry(2, "fail"))
ps.Scheduler(gf).run()
t.check(gf.node("c").items == [7, 8] and gf.recovery["f"].retried == 2, "retry : réussite au 2e essai")
stopped := [0]
class Stoppable extends Node:
    func init(name):
        super.init(name)
    func process(x):
        if x == 3:
            raise("CorruptDataError", "fatal")
        return [x]
    func stop():
        stopped[0] += 1
gx := pg.Graph()
gx.add(nd.from_list("s", [1, 2, 3, 4]))
gx.add(Stoppable("st"))
gx.add(nd.collect("c"))
gx.chain(["s", "st", "c"])
t.raises("PipelineError", () => ps.Scheduler(gx).run(), "fail : PipelineError")
t.check(stopped[0] == 1, "arrêt propre même après une erreur")
glim := pg.Graph()
glim.add(nd.from_list("s", [1, 2, 3]))
glim.add(nd.collect("c", 2))
glim.chain(["s", "c"])
glim.set_recovery("c", rec.skip())
t.raises("LimitError", () => ps.Scheduler(glim).run(), "une limite n'est jamais contournée par skip")

# ---------------------------------------------------------------- annulation et blocage
src := mc.source()
count := [0]
func endless():
    count[0] += 1
    if count[0] == 50:
        src.cancel("assez")
    return count[0]
ga := pg.Graph()
ga.add(nd.from_function("inf", endless))
ga.add(nd.collect("c"))
ga.chain(["inf", "c"])
t.raises("CancelledError", () => ps.Scheduler(ga).run(src.token), "annulation d'un flux sans fin")
waiting := [0]
func later():
    waiting[0] += 1
    if waiting[0] < 5:
        return null
    if waiting[0] < 8:
        return waiting[0]
    return nd.EOS
gw := pg.Graph()
gw.add(nd.from_function("live", later))
gw.add(nd.collect("c"))
gw.chain(["live", "c"])
ps.Scheduler(gw, 64, 0.0).run()
t.check(gw.node("c").items == [5, 6, 7], "source en direct qui attend : pas de faux blocage")
gd := pg.Graph()
gd.add(nd.from_list("s", [1, 2, 3]))
gd.add(nd.map("m", (x) => x))
gd.add(nd.collect("c"))
gd.connect("s", "m", 1)
gd.connect("m", "c", 1)
sd := ps.Scheduler(gd)
r3 := sd.run(null, 1)
t.check(not r3["finished"] and r3["steps"] == 1, "exécution limitée en pas")
t.check(sd.run()["finished"], "reprise jusqu'à la fin")

# ---------------------------------------------------------------- pipeline audio réel : WAV -> gain -> WAV
pin := fx.temp_path("in.wav")
pout := fx.temp_path("out.wav")
fx.write_sine_wav(pin, 440, 0.2, 8000, 2)
d := dmx.open(pin)
w := mux.WavMuxer(pout, d.format)
ps.run_chain([nd.demux_source("lecture", d, 300), nd.audio_gain("gain", 0.5), nd.audio_output("écriture", w, true, "write_samples")], 3)
d2 := dmx.open(pout)
ref := dmx.open(pin).read_all()
got := d2.read_all()
t.check(d2.frames == 1600 and len(got) == len(ref), "toutes les trames écrites")
t.samples_near(got, [x * 0.5 for x in ref], 0.0002, "gain appliqué")
t.check(d.closed, "démultiplexeur fermé à l'arrêt")
fx.cleanup()

# ---------------------------------------------------------------- horloges et synchronisation
base := pc.ManualClock()
m := pc.MediaClock(base)
m.start()
base.advance(2.0)
t.check(m.time() == 2.0, "horloge média")
m.pause()
base.advance(5.0)
t.check(m.time() == 2.0, "pause")
m.set_rate(2.0)
m.resume()
base.advance(1.0)
t.check(m.time() == 4.0 and m.delay_until(6.0) == 1.0, "vitesse 2x, délai")
m.seek(30.0)
t.check(m.time() == 30.0, "recherche")
t.raises("FormatError", () => m.set_rate(0), "vitesse nulle refusée")
sc := sy.SampleClock(48000)
sc.advance(24000)
avs := sy.AVSync(sc, 0.010, 0.080)
t.check(avs.decide(0.5)[0] == "present" and avs.decide(0.6)[0] == "wait" and avs.decide(0.3)[0] == "drop", "décisions présenter / attendre / jeter")
t.near(avs.decide(0.52)[1], 0.02, 0.000001, "délai d'attente")
st := avs.stats()
t.check(st["presented"] == 1 and st["waited"] == 2 and st["dropped"] == 1 and st["max_drift"] >= 0.2, "statistiques de dérive")
t.check(sy.drift_correction(0.02, 10.0) == 1.002 and sy.drift_correction(10.0) == 1.005 and sy.drift_correction(-10.0) == 0.995, "correction de dérive bornée")
# 25 i/s contre l'audio pendant 10 min simulées : aucune image jetée si l'audio avance régulièrement
clk := sy.SampleClock(44100)
sync := sy.AVSync(clk)
for i in 0..15000:
    clk.advance(1764)
    sync.decide(1.0 * (i + 1) / 25)
t.check(sync.dropped == 0 and sync.max_drift < 0.000001, "longue lecture sans dérive")

t.summary()
