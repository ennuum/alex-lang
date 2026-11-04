# multimedia.streaming.rtp : paquets RTP (RFC 3550 : CSRC, extension, bourrage, marqueur), paquets invalides
# rejetés, G.711 loi µ / loi A (valeurs de référence, 256 codes), L16 / L24, SDP, réseau simulé (perte, désordre,
# doublon, bouclage du numéro de séquence 16 bits, source et type étrangers), boucle locale UDP ALEX -> ALEX ; et,
# si ffmpeg est installé, interopérabilité dans les deux sens (ffmpeg -> ALEX en L16 et PCMU, ALEX -> ffmpeg par SDP).
from core use len, to_int
from collections use append
use io
use os
use math
use process
use audio.audio_format as af
use multimedia.streaming.rtp as rtp
use multimedia.backends.codecs.ffmpeg as ff
use multimedia.container.demux as dmx
use multimedia.container.mux as mux
use multimedia.testing.assertions as ta
use multimedia.testing.fixtures as fx

t := ta.Checker("multimedia RTP")

# ---------------------------------------------------------------- paquets
p := rtp.RtpPacket(96, 65535, 4294967295, 0xDEADBEEF, [1, 2, 3, 4, 5], true, [11, 22], [0xBEDE, [9, 8, 7, 6]])
b := rtp.encode(p)
t.check(len(b) == 12 + 8 + 4 + 4 + 5 and b[0] == 0x92 and b[1] == 0xE0, "en-tête : version 2, extension, 2 CSRC, marqueur")
q := rtp.decode(b)
t.check(q.pt == 96 and q.seq == 65535 and q.timestamp == 4294967295 and q.ssrc == 0xDEADBEEF and q.marker and q.csrc == [11, 22] and q.extension == [0xBEDE, [9, 8, 7, 6]] and q.payload == [1, 2, 3, 4, 5], "aller-retour du paquet")
bourre := rtp.encode(rtp.RtpPacket(0, 1, 2, 3, [7, 7, 7]))
bourre[0] = bourre[0] | 32
bourre = bourre + [0, 0, 3]
t.check(rtp.decode(bourre).payload == [7, 7, 7], "bourrage retiré")
t.raises("CorruptDataError", () => rtp.decode([0x80, 0, 0]), "paquet trop court")
t.raises("CorruptDataError", () => rtp.decode([0x40] + [0 for i in 0..11]), "version 1 refusée")
mauvais := rtp.encode(rtp.RtpPacket(0, 1, 2, 3, [1]))
mauvais[0] = mauvais[0] | 32
mauvais[len(mauvais) - 1] = 200
t.raises("CorruptDataError", () => rtp.decode(mauvais), "bourrage impossible refusé")
t.raises("CorruptDataError", () => rtp.decode([0x8F] + [0 for i in 0..15]), "CSRC tronqués refusés")

# ---------------------------------------------------------------- G.711, L16, L24
t.check(rtp.mulaw_encode(0) == 0xFF and rtp.mulaw_decode(0xFF) == 0 and rtp.mulaw_decode(0x00) == -32124 and rtp.mulaw_decode(0x80) == 32124, "loi µ : valeurs de référence")
t.check(rtp.alaw_encode(0) == 0xD5 and rtp.alaw_decode(0xD5) == 8 and rtp.alaw_decode(0x55) == -8 and rtp.alaw_decode(0xAA) == 32256, "loi A : valeurs de référence")
t.check(len([c for c in 0..256 if c != 0x7F and rtp.mulaw_encode(rtp.mulaw_decode(c)) != c]) == 0, "loi µ : 255 codes relus à l'identique (zéro négatif à part)")
t.check(len([c for c in 0..256 if rtp.alaw_encode(rtp.alaw_decode(c)) != c]) == 0, "loi A : 256 codes relus à l'identique")
vals := [k / 32768.0 for k in [-32768, -1, 0, 1, 12345, 32767]]
t.check(rtp.unpack(rtp.pack(vals, "L16"), "L16") == vals and rtp.pack([0.5], "L16") == [0x40, 0], "L16 grand-boutiste, exact")
v24 := [k / 8388608.0 for k in [-8388608, -1, 0, 7, 8388607]]
t.check(rtp.unpack(rtp.pack(v24, "L24"), "L24") == v24, "L24 exact")
t.raises("UnsupportedError", () => rtp.pack([0.0], "OPUS"), "codec inconnu")
t.check(rtp.payload_type("PCMU", 8000, 1) == 0 and rtp.payload_type("L16", 44100, 2) == 10 and rtp.payload_type("L16", 48000, 2) == 96, "types de charge utile statiques / dynamique")

# ---------------------------------------------------------------- SDP
s := rtp.build_sdp("127.0.0.1", 5004, "L16", 48000, 2, 97)
d := rtp.parse_sdp(s)
t.check(d["port"] == 5004 and d["pt"] == 97 and d["codec"] == "L16" and d["rate"] == 48000 and d["channels"] == 2 and d["host"] == "127.0.0.1", "SDP : écrit puis relu")
t.check(rtp.parse_sdp("v=0\r\nc=IN IP4 10.0.0.1\r\nm=audio 6000 RTP/AVP 0\r\n")["codec"] == "PCMU", "SDP : type statique sans rtpmap")
t.raises("CorruptDataError", () => rtp.parse_sdp("v=0\nm=audio 6000 RTP/AVP 98\n"), "SDP : type dynamique sans rtpmap")

# ---------------------------------------------------------------- réseau simulé
f48 := af.AudioFormat(48000, 2, "s16le")
ref := []
for i in 0..4800:
    append(ref, to_int(16000 * math.sin(i * 0.05)) / 32768.0)
    append(ref, to_int(8000 * math.sin(i * 0.07)) / 32768.0)
pk := rtp.RtpPacketizer(f48, "L16", null, rtp.MAX_PAYLOAD, 240, 4242)
pk.seq = 65530                                    # bouclage du numéro de séquence en cours de flux
dg := pk.packets(ref, true)
t.check(len(dg) == 20 and rtp.decode(dg[0]).marker and not rtp.decode(dg[1]).marker and rtp.decode(dg[19]).seq == 13, "20 paquets, marqueur sur le premier, séquence 65530 -> 13")
t.check(rtp.decode(dg[1]).timestamp - rtp.decode(dg[0]).timestamp == 240 or rtp.decode(dg[1]).timestamp + 4294967296 - rtp.decode(dg[0]).timestamp == 240, "horodatage en échantillons")
etranger := rtp.encode(rtp.RtpPacket(96, 5, 0, 999, [0, 0, 0, 0]))
autre_type := rtp.encode(rtp.RtpPacket(0, 5, 0, 4242, [0]))
sim := [dg[0], dg[1], dg[3], dg[2], dg[4], dg[4], etranger, autre_type, [1, 2, 3]] + [dg[k] for k in 5..20 if k != 9]
src := rtp.RtpPacketSource(sim, f48, "L16", null, 4)
got := src.read(100000)
st := src.buffer.stats()
t.check(len(got) == len(ref) and st["lost"] == 1 and st["duplicates"] == 1 and st["reordered"] == 1, "perte, désordre, doublon : " + str(st))
t.check(got[0:9 * 480] == ref[0:9 * 480] and got[9 * 480:10 * 480] == [0.0 for k in 0..480] and got[10 * 480:] == ref[10 * 480:], "trou comblé par du silence, le reste intact (malgré le bouclage)")
t.check(src.d.invalid == 1 and src.d.foreign == 2, "invalide, source et type étrangers ignorés")

# ---------------------------------------------------------------- boucle locale UDP ALEX -> ALEX
rx := rtp.RtpAudioSource(0, f48, "L16")
tx := rtp.RtpAudioSink("127.0.0.1", rx.port, f48)
tx.write(ref)
tx.close()
recv := []
while true:
    bl := rx.read(1000)
    if len(bl) == 0:
        break
    recv = recv + bl
rx.close()
# 20 ms = 960 trames, mais 1200 octets de charge utile au plus : 300 trames stéréo L16 par paquet
t.check(recv == ref and tx.packets_sent() == 16, "UDP L16 48 kHz stéréo : identique, 16 paquets de 300 trames")
voix := [to_int(20000 * math.sin(i * 0.2)) / 32768.0 for i in 0..1600]
rxu := rtp.RtpAudioSource(0, null, "PCMU")
txu := rtp.RtpAudioSink("127.0.0.1", rxu.port, af.AudioFormat(8000, 1, "s16le"), "PCMU")
txu.write(voix)
txu.close()
ru := rxu.read(5000)
rxu.close()
pire := 0.0
for i in 0..len(voix):
    e := ru[i] - voix[i] if i < len(ru) else 1.0
    pire = e if e > pire else (-e if -e > pire else pire)
t.check(len(ru) == 1600 and rxu.format.rate == 8000 and pire < 0.032, "UDP PCMU 8 kHz : erreur de quantification G.711 " + str(pire))
t.raises("FormatError", () => rtp.RtpAudioSink("127.0.0.1", 9, f48, "PCMU"), "PCMU hors 8 kHz refusé")

# ---------------------------------------------------------------- interopérabilité ffmpeg
if ff.available():
    # ffmpeg -> ALEX : L16 44100 stéréo (type statique 10) depuis un WAV, au bit près
    w := fx.temp_path("rtp_src.wav")
    f44 := af.AudioFormat(44100, 2, "s16le")
    sig := []
    for i in 0..22050:
        append(sig, to_int(12000 * math.sin(2.0 * math.PI * 440.0 * i / 44100)) / 32768.0)
        append(sig, to_int(9000 * math.sin(2.0 * math.PI * 660.0 * i / 44100)) / 32768.0)
    mux.write_wav(w, sig, f44)
    rf := rtp.RtpAudioSource(0, null, null, null, 3, 64, "127.0.0.1", 3.0, 15.0)
    fp := process.Command("ffmpeg").args(["-hide_banner", "-loglevel", "error", "-re", "-i", w, "-acodec", "pcm_s16be", "-f", "rtp", "rtp://127.0.0.1:" + str(rf.port)]).stdin("null").stdout("null").stderr("pipe").spawn()
    rec := []
    while true:
        bl := rf.read(4410)
        if len(bl) == 0:
            break
        rec = rec + bl
    fp.wait(10.0)
    rf.close()
    t.check(rf.format.rate == 44100 and rf.format.channels == 2 and rec == sig, "ffmpeg -> ALEX (L16, type 10) : " + str(len(rec)) + " échantillons identiques")
    # ffmpeg -> ALEX : G.711 loi µ (type 0)
    rm := rtp.RtpAudioSource(0, null, null, null, 3, 64, "127.0.0.1", 3.0, 15.0)
    fm := process.Command("ffmpeg").args(["-hide_banner", "-loglevel", "error", "-re", "-i", w, "-ar", "8000", "-ac", "1", "-acodec", "pcm_mulaw", "-f", "rtp", "rtp://127.0.0.1:" + str(rm.port)]).stdin("null").stdout("null").stderr("pipe").spawn()
    mu := []
    while true:
        bl := rm.read(800)
        if len(bl) == 0:
            break
        mu = mu + bl
    fm.wait(10.0)
    rm.close()
    energie := 0.0
    for x in mu:
        energie += x * x
    t.check(rm.d.codec == "PCMU" and len(mu) >= 3900 and len(mu) <= 4100 and energie / len(mu) > 0.01, "ffmpeg -> ALEX (PCMU, type 0) : " + str(len(mu)) + " échantillons")
    # ALEX -> ffmpeg : description SDP, flux L16 48 kHz stéréo (type dynamique 96), relu au bit près
    port := 0
    tmp := rtp.RtpAudioSource(0)
    port = tmp.port
    tmp.close()
    tx2 := rtp.RtpAudioSink("127.0.0.1", port, f48)
    sdpf := fx.temp_path("flux.sdp")
    io.write_file(sdpf, tx2.sdp())
    raw := fx.temp_path("rtp_out.pcm")
    fr := process.Command("ffmpeg").args(["-hide_banner", "-loglevel", "error", "-protocol_whitelist", "file,udp,rtp", "-i", sdpf, "-t", "0.1", "-f", "s16le", "-y", raw]).stdin("null").stdout("null").stderr("pipe").spawn()
    os.sleep(2.0)                                   # ffmpeg ouvre le port avant le premier paquet
    for k in 0..10:
        tx2.write(ref)
        os.sleep(0.05)
    tx2.close()
    code := fr.wait(15.0)
    if code == null:
        fr.stop(1.0)
    rb := io.read_bytes(raw) if os.exists(raw) else []
    n := len(rb) // 2
    lu := []
    for i in 0..n:
        v := rb[2 * i] | (rb[2 * i + 1] << 8)
        append(lu, (v - 65536 if v >= 32768 else v) / 32768.0)
    t.check(code == 0 and n == 9600 and lu == ref[0:9600], "ALEX -> ffmpeg (SDP, L16 type 96) : " + str(n) + " échantillons identiques")
else:
    print("(ffmpeg absent : interopérabilité non testée)")
fx.cleanup()
t.summary()
