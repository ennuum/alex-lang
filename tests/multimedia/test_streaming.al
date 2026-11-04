# multimedia.streaming et recording : format AMS1 (CRC, troncature), tampon de gigue (perte, désordre, doublons,
# retard, débordement, bouclage des numéros 32 bits), émission / réception en mémoire, UDP et TCP sur la boucle
# locale, reconnexion avec attente exponentielle ; enregistreur, export, transcodage.
from core use len, to_int
from collections use append
use io
use os
use audio.audio_format as af
use audio.audio_effects as afx
use network.tcp as tcp
use multimedia.streaming.network_stream as ns
use multimedia.streaming.buffering as jb
use multimedia.streaming.sink as snk
use multimedia.streaming.source as src
use multimedia.streaming.live as live
use multimedia.recording.recorder as rec
use multimedia.recording.export as ex
use multimedia.recording.microphone as mic
use multimedia.recording.screen_capture as sc
use multimedia.container.demux as dmx
use multimedia.codec.audio.flac as flac
use multimedia.backends.codecs.ffmpeg as ff
use multimedia.image.image as mi
use multimedia.testing.fake_device as fake
use multimedia.testing.fixtures as fx
use multimedia.testing.assertions as ta

t := ta.Checker("multimedia streaming et enregistrement")
f16 := af.AudioFormat(16000, 1, "s16le")

# ---------------------------------------------------------------- paquets AMS1
p := jb.StreamPacket(4294967295, [1, 2, 3], 123456789012, ns.KEY)
b := ns.encode(p)
q := ns.decode(b)
t.check(q.seq == 4294967295 and q.timestamp == 123456789012 and q.payload == [1, 2, 3] and q.flags == ns.KEY, "codage / décodage")
bad := [x for x in b]
bad[23] = bad[23] ^ 1
t.raises("CorruptDataError", () => ns.decode(bad), "CRC faux")
t.raises("CorruptDataError", () => ns.decode([b[k] for k in 0..20]), "paquet tronqué")
t.raises("CorruptDataError", () => ns.decode([0, 0, 0, 0] + [b[k] for k in 4..len(b)]), "magie absente")
two := ns.split_stream(b + ns.encode(p) + [65, 77])
t.check(len(two[0]) == 2 and two[1] == [65, 77], "découpage d'un flux TCP")
cfg := ns.parse_config(ns.config_packet(af.AudioFormat(48000, 2, "s16le"), 480))
t.check(cfg["format"].rate == 48000 and cfg["format"].channels == 2 and cfg["frames"] == 480, "paquet de configuration")

# ---------------------------------------------------------------- tampon de gigue
func pk(s):
    return jb.StreamPacket(s, [s], 0, 0)
j := jb.JitterBuffer(2, 16, "silence", [0])
for s in [10, 12, 11, 11, 14, 13]:
    j.push(pk(s))
order := []
while true:
    x := j.pop()
    if x == null:
        break
    append(order, x.seq)
t.check(order == [10, 11, 12, 13, 14], "remise en ordre : " + str(order))
st := j.stats()
t.check(st["duplicates"] == 1 and st["reordered"] == 2 and st["lost"] == 0, "doublon et désordre comptés : " + str(st))
j.push(pk(9))
t.check(j.stats()["late"] == 1, "paquet en retard jeté")
j2 := jb.JitterBuffer(0, 16, "repeat")
j2.push(pk(1))
j2.push(pk(3))
a := j2.pop()
b2 := j2.pop()
c := j2.pop()
t.check(a.seq == 1 and b2.concealed and b2.payload == [1] and c.seq == 3, "perte comblée par répétition")
j3 := jb.JitterBuffer(0, 8, "skip")
j3.push(pk(1))
j3.push(pk(100))
t.check(j3.stats()["overflow"] == 1 and j3.pop().seq == 100, "saut trop grand : remise à zéro")
j4 := jb.JitterBuffer(0, 8)
j4.push(pk(4294967294))
j4.push(pk(0))
j4.push(pk(4294967295))
t.check(j4.pop().seq == 4294967294 and j4.pop().seq == 4294967295 and j4.pop().seq == 0, "bouclage des numéros 32 bits")
t.check(jb.seq_diff(0, 4294967295) == 1 and jb.seq_diff(5, 10) == -5, "écart de séquence circulaire")

# ---------------------------------------------------------------- réseau simulé (mémoire)
sig := afx.sine(440, 1.0, 16000)
ms := snk.MemorySink(f16, 320)
ms.write(sig)
ms.close()
ref := af.decode(af.encode(sig, f16), f16)
got := src.PacketSource(ms.datagrams).read(100000)
t.check(got == ref, "transmission sans perte : identique (PCM 16 bits)")
dg := ms.datagrams
sim := [dg[k] for k in 0..len(dg) if k != 10]
tmp := sim[20]
sim[20] = sim[21]
sim[21] = tmp
sim = sim + [sim[30], [1, 2, 3]]
ps_ := src.PacketSource(sim, 4)
g2 := ps_.read(100000)
s2 := ps_.buffer.stats()
t.check(len(g2) == len(ref) and s2["lost"] == 1 and s2["concealed"] == 1 and s2["duplicates"] == 1 and s2["reordered"] == 1, "perte, désordre, doublon : " + str(s2))
t.check([g2[k] for k in 9 * 320..10 * 320] == [0.0 for k in 0..320] and [g2[k] for k in 0..9 * 320] == [ref[k] for k in 0..9 * 320], "trou comblé par du silence, le reste intact")
t.check(ps_.d.invalid == 1, "datagramme invalide ignoré")

# ---------------------------------------------------------------- UDP sur la boucle locale
rx := src.UdpAudioSource(0, 3)
tx := snk.UdpAudioSink("127.0.0.1", rx.port, f16, 320, 10)
tx.write(sig)
tx.close()
recv := []
while true:
    bl := rx.read(1000)
    if len(bl) == 0:
        break
    recv = recv + bl
rx.close()
t.check(recv == ref, "UDP : flux reçu identique (" + str(len(recv)) + " échantillons)")

# ---------------------------------------------------------------- TCP sur la boucle locale
srv := tcp.listen("127.0.0.1", 0)
txt := snk.TcpAudioSink("127.0.0.1", srv.port(), f16, 400)
txt.write(sig)
txt.close()
rt := src.accept_tcp(srv, 5.0)
rcv := []
while true:
    bl := rt.read(2000)
    if len(bl) == 0:
        break
    rcv = rcv + bl
rt.close()
srv.close()
t.check(rcv == ref, "TCP : flux reçu identique (" + str(len(rcv)) + ")")

# ---------------------------------------------------------------- reconnexion
attempts := [0]
waits := []
func flaky():
    attempts[0] += 1
    if attempts[0] < 3:
        raise("NetworkError", "refusé")
    return fake.FakeAudioOutput(f16)
ls := live.LiveSession(flaky, live.Backoff(0.5, 4.0, 5, 2.0, 0.0), (d) => append(waits, d))
ls.write([0.1, 0.2])
t.check(ls.state == "connecté" and ls.connections == 1 and ls.failures == 2 and waits == [0.5, 1.0], "reconnexion : attente 0,5 puis 1 s (" + str(waits) + ")")
func never():
    raise("TimeoutError", "pas de réponse")
sn := live.LiveSession(never, live.Backoff(0.1, 1.0, 4, 2.0, 0.0), (d) => append(waits, d))
t.raises("DeviceError", () => sn.write([0.0]), "abandon après 4 essais")
t.check(sn.state == "abandonné", "état abandonné")
t.check(live.Backoff(1.0, 8.0, 10, 2.0, 0.0).delay(6) == 8.0, "attente plafonnée")
drops := [0]
class Fragile:
    func init():
        self.n = 0
    func write(x):
        self.n += 1
        if self.n == 2:
            raise("NetworkError", "coupure")
        return len(x)
    func close():
        return null
s3 := live.LiveSession(() => Fragile(), live.Backoff(0.0, 0.0, 3, 1.0, 0.0), (d) => append(waits, d))
s3.write([1.0])
s3.write([1.0])
t.check(s3.drops == 1 and s3.connections == 2, "coupure en cours de flux : reconnexion transparente")

# ---------------------------------------------------------------- enregistrement
p1 := fx.temp_path("rec.wav")
inp := fake.FakeAudioInput(f16, "sine", 440.0, 1.0)
r := rec.Recorder(inp, f16, p1)
lv := []
r.on_level = (d) => append(lv, d)
stt := r.record(0.5)
d1 := dmx.open(p1)
t.check(stt["frames"] == 8000 and d1.frames == 8000 and stt["stopped_by"] == "durée" and len(lv) > 5, "enregistrement de 0,5 s")
t.samples_near(d1.read_all(), [ref[k] for k in 0..8000], 0.0001, "échantillons enregistrés")
loud := fake.FakeAudioInput(f16, "sine", 440.0, 0.3)
class Then:
    func init(a, b):
        self.a = a
        self.b = b
    func read(n):
        x := self.a.read(n)
        if len(x) == 0:
            return self.b.read(n)
        return x
    func close():
        return null
both := Then(loud, fake.FakeAudioInput(f16, "silence", 0.0, 5.0))
stu := rec.Recorder(both, f16, fx.temp_path("sil.wav")).record_until_silence(10.0, -40.0, 0.5)
t.check(stu["stopped_by"] == "silence" and stu["duration"] > 0.75 and stu["duration"] < 0.9, "arrêt sur silence (" + str(stu["duration"]) + " s)")
short := rec.Recorder(fake.FakeAudioInput(f16, "sine", 440.0, 0.1), f16, fx.temp_path("court.wav")).record(5.0)
t.check(short["stopped_by"] == "fin de la source" and short["frames"] == 1600, "fin de source")
if ff.available():
    pf := fx.temp_path("rec.flac")
    rec.Recorder(fake.FakeAudioInput(f16, "sine", 440.0, 0.5), f16, pf).record(0.5)
    fd := flac.decode(io.read_bytes(pf))
    t.check(fd["md5_checked"] and len(fd["channels"][0]) == 8000, "enregistrement FLAC (ffmpeg) relu par le décodeur ALEX, MD5 vérifié")
    pcm := fx.temp_path("ref.pcm")
    os.run("ffmpeg", ["-v", "error", "-y", "-i", pf, "-f", "s16le", pcm])
    rb := io.read_bytes(pcm)
    ffv := []
    for k in 0..len(rb) // 2:
        v := rb[2 * k] | (rb[2 * k + 1] << 8)
        append(ffv, v - 65536 if v >= 32768 else v)
    t.check(fd["channels"][0] == ffv, "FLAC décodé par ALEX identique au décodage ffmpeg")
    # transcodage FLAC (ALEX) -> WAV 8 kHz
    p2 := fx.temp_path("tr.wav")
    tr_ := ex.transcode(pf, p2, af.AudioFormat(8000, 1, "s16le"))
    t.check(dmx.open(p2).frames == 4000 and tr_["frames_in"] == 8000, "transcodage avec rééchantillonnage : 8000 -> 4000 trames")
paths := ex.export_frames([mi.gradient(4, 4), mi.gradient(4, 4)], os.tmp_dir() + "/alex_mm_frames_" + str(os.pid()))
t.check(len(paths) == 2 and os.exists(paths[1]), "export d'images")
for pth in paths:
    os.remove(pth)
t.check(mic.available() or mic.diagnose()["advice"] != null, "microphone : disponible ou raison donnée")
d := sc.diagnose()
t.check(d["ok"] or d["advice"] != null, "capture d'écran : disponible ou raison donnée (" + str(d["advice"]) + ")")

fx.cleanup()
t.summary()
