# multimedia.playback et metadata : lecteur (états, lecture complète, pause / reprise, recherche, volume sans clic,
# sourdine, panne de sortie, fermeture), listes M3U / PLS, recherche par texte, sous-titres SRT / WebVTT,
# chapitres, étiquettes ; faux périphériques.
from core use len
from collections use append
use io
use os
use audio.audio_format as af
use multimedia.core.cancellation as mc
use multimedia.container.demux as dmx
use multimedia.metadata.tags as tg
use multimedia.metadata.subtitles as subs
use multimedia.metadata.chapters as ch
use multimedia.playback.player as mp
use multimedia.playback.playlist as pl
use multimedia.playback.controls as ctl
use multimedia.playback.seek as sk
use multimedia.playback.subtitles as psub
use multimedia.testing.fake_device as fake
use multimedia.testing.fixtures as fx
use multimedia.testing.assertions as ta
use multimedia.security.limits as lim

t := ta.Checker("multimedia lecture")
f8 := af.AudioFormat(8000, 1, "s16le")

# ---------------------------------------------------------------- états
st := ctl.PlaybackState()
vus := []
st.on_change = (a, b) => append(vus, a + ">" + b)
t.raises("StateError", () => st.go("playing"), "lecture sans média refusée")
st.go("ready")
st.go("playing")
st.go("paused")
t.check(vus == ["idle>ready", "ready>playing", "playing>paused"], "transitions notifiées")
st.go("closed")
t.raises("StateError", () => st.go("ready"), "rien après closed")

# ---------------------------------------------------------------- volume
v := ctl.Volume(1.0)
t.check(v.apply([0.5, 0.5], 1) == [0.5, 0.5], "gain 1 : inchangé")
v.set(0.0)
ramp := v.apply([1.0, 1.0, 1.0, 1.0], 1)
t.check(ramp[0] == 0.75 and ramp[1] == 0.5 and ramp[3] == 0.0, "rampe sans clic : " + str(ramp))
t.check(v.apply([1.0], 1) == [0.0], "gain atteint")
v.set_db(-6.0206)
t.near(v.gain, 0.5, 0.001, "gain en dB")
v.mute()
v.apply([1.0, 1.0], 1)
t.check(v.apply([1.0], 1) == [0.0] and v.toggle_mute() == false, "sourdine")
t.raises("FormatError", () => v.set(5.0), "gain hors limites")
st2 := ctl.Volume(2.0)
t.check(st2.apply([0.8], 1) == [1.0], "écrêtage")

# ---------------------------------------------------------------- lecteur complet sur sortie factice
path := fx.temp_path("lecture.wav")
fx.write_sine_wav(path, 440, 1.0, 8000, 1, "s16le", tg.Tags({"title": "La 440"}))
out := fake.FakeAudioOutput(f8)
p := mp.Player(out, null, 1000)
events := []
p.on("state", (a, b) => append(events, b))
ends := []
p.on("end", (pl_) => append(ends, 1))
info := p.open(path)
t.check(info.tags["title"] == "La 440" and p.duration() == 1.0 and p.state() == "ready", "ouverture")
p.play()
p.run()
t.check(p.state() == "ended" and len(ends) == 1 and out.frames() == 8000 and out.drains == 1, "lecture jusqu'au bout")
t.check(p.position() == 1.0, "position exacte d'après les trames")
ref := dmx.open(path).read_all()
t.samples_near(out.samples, ref, 0.0, "échantillons transmis intacts")
t.check(events == ["ready", "playing", "ended"], "événements d'état : " + str(events))
# relecture depuis le début, pause pendant la lecture
out2 := fake.FakeAudioOutput(f8)
p2 := mp.Player(out2, null, 1000)
p2.open(path)
p2.on("position", (s) => p2.pause() if s >= 0.5 else null)
p2.play()
p2.run()
t.check(p2.state() == "paused" and p2.position() == 0.5 and out2.frames() == 4000, "pause demandée par un événement")
p2.resume()
p2.listeners = {}
p2.run()
t.check(p2.state() == "ended" and out2.frames() == 8000, "reprise jusqu'à la fin")
t.samples_near(out2.samples, ref, 0.0, "pause sans perte ni doublon")
# recherche
t.near(p2.seek(0.25), 0.25, 0.0, "recherche")
t.check(p2.state() == "paused", "recherche après la fin : en pause")
p2.play()
p2.run(null, 2)
t.near(p2.position(), 0.5, 0.0, "position après recherche et 2 blocs")
t.near(p2.seek_relative(-10.0), 0.0, 0.0, "recherche relative bornée")
t.near(p2.seek(99.0), 1.0, 0.0, "recherche bornée à la durée")
p2.stop()
t.check(p2.state() == "ready" and p2.position() == 0.0, "arrêt : retour au début")
# volume pendant la lecture
out3 := fake.FakeAudioOutput(f8)
p3 := mp.Player(out3, null, 4000)
p3.open(path)
p3.set_volume(0.5)
p3.play()
p3.run()
t.samples_near([out3.samples[k] for k in 4000..8000], [x * 0.5 for x in [ref[k] for k in 4000..8000]], 0.000001, "volume appliqué")
t.check(out3.samples[0] != 0.0 or ref[0] == 0.0, "rampe de départ")
# panne de la sortie
bad := fake.FakeAudioOutput(f8, 2)
p4 := mp.Player(bad, null, 1000)
errs := []
p4.on("error", (ty, m) => append(errs, ty))
p4.open(path)
p4.play()
t.raises("DeviceError", () => p4.run(), "panne de sortie signalée")
t.check(p4.state() == "paused" and errs == ["DeviceError"] and p4.position() == 0.25, "état cohérent après la panne")
# annulation
p5 := mp.Player(fake.FakeAudioOutput(f8), null, 100)
p5.open(path)
p5.play()
src := mc.source()
p5.on("position", (s) => src.cancel() if s >= 0.3 else null)
t.raises("CancelledError", () => p5.run(src.token), "annulation de la lecture")
p5.close()
t.check(p5.state() == "closed", "fermeture")
t.raises("StateError", () => p5.open(path), "lecteur fermé")
p6 := mp.Player(fake.FakeAudioOutput(f8))
t.raises("StateError", () => p6.play(), "lecture sans fichier")
t.raises("MediaError", () => p6.open(fx.temp_path("absent.wav")), "fichier absent")
# 100 ouvertures / fermetures : pas d'état résiduel
fermes := 0
for i in 0..100:
    q := mp.Player(fake.FakeAudioOutput(f8), null, 8000)
    q.open(path)
    q.play()
    q.pump(1)
    q.close()
    if q.state() == "closed" and q.demuxer == null:
        fermes += 1
t.check(fermes == 100, "100 ouvertures / fermetures sans ressource restante")

# ---------------------------------------------------------------- liste de lecture enchaînée
pa := fx.temp_path("a.wav")
pb := fx.temp_path("b.wav")
fx.write_sine_wav(pa, 300, 0.25)
fx.write_sine_wav(pb, 600, 0.5)
lst := pl.Playlist()
lst.add(pa, "A")
lst.add(pb, "B")
outp := fake.FakeAudioOutput(f8)
pp := mp.Player(outp, null, 1000)
tracks := []
pp.on("track", (e) => append(tracks, e.title))
pp.open_playlist(lst)
pp.play()
pp.run()
t.check(tracks == ["A", "B"] and outp.frames() == 6000 and pp.state() == "ended", "enchaînement des entrées")

# ---------------------------------------------------------------- listes M3U / PLS
m := pl.parse_m3u(fx.SAMPLE_M3U, "/musique")
t.check(m.size() == 3 and m.entries[0].path == os.join("/musique", "morceau1.wav") and m.entries[0].title == "Artiste - Titre" and m.entries[0].duration == 123.0, "M3U étendu")
t.check(m.entries[1].path == "http://exemple.org/flux.mp3" and m.entries[2].path == "/absolu/morceau3.wav" and m.entries[2].duration == null, "URL, chemin absolu, durée inconnue")
ps_ := pl.parse_pls(fx.SAMPLE_PLS)
t.check(ps_.size() == 2 and ps_.entries[0].title == "Premier" and ps_.entries[0].duration == 10.0 and ps_.entries[1].title == null, "PLS")
t.check(pl.parse_m3u(pl.format_m3u(m)).entries[0].title == "Artiste - Titre", "M3U aller-retour")
t.check(pl.parse_pls(pl.format_pls(ps_)).entries[0].duration == 10.0, "PLS aller-retour")
t.raises("CorruptDataError", () => pl.parse_pls("File1=a.wav"), "PLS sans section")
lp := pl.Playlist()
for n in ["a", "b", "c", "d"]:
    lp.add(n)
t.check(lp.next().path == "b" and lp.next().path == "c" and lp.next().path == "d" and lp.next() == null, "suivant sans répétition")
lp.set_repeat("all")
t.check(lp.next().path == "a" and lp.previous().path == "d", "répétition de toute la liste")
lp.set_repeat("one")
t.check(lp.next().path == "d" and lp.next(true).path == "a", "répétition d'une entrée")
lp.set_repeat("none")
lp.select(1)
lp.shuffle(42)
o1 := [x for x in lp.order]
lp.shuffle(42)
t.check(lp.order == o1 and lp.current().path == "b" and len(lp.order) == 4, "aléatoire reproductible, entrée courante en tête")
lp.unshuffle()
lp.remove(0)
t.check(lp.size() == 3 and lp.current().path == "b", "retrait")
lp.move(2, 0)
t.check(lp.entries[0].path == "d" and lp.current().path == "b", "déplacement")
t.raises("LimitError", () => pl.parse_m3u("a\nb\nc\n", null, fx_limits()), "limite d'entrées")
func fx_limits():
    return lim.Limits({"max_playlist_items": 2})

# ---------------------------------------------------------------- recherche par texte
t.check(sk.resolve("1:30", 0.0, 300.0) == 90.0 and sk.resolve("+15", 10.0, 300.0) == 25.0 and sk.resolve("-20", 10.0) == 0.0, "positions texte")
t.check(sk.resolve("50%", 0.0, 300.0) == 150.0 and sk.resolve("200%", 0.0, 300.0) == 300.0, "pourcentages")
t.check(sk.frame_aligned(0.123456, 1000) == 0.123 and sk.keyframe_before(5.5, [0.0, 2.0, 4.0, 6.0]) == 4.0, "alignement, image clé")
t.raises("FormatError", () => sk.resolve("50%", 0.0), "pourcentage sans durée")

# ---------------------------------------------------------------- sous-titres
s1 := subs.parse(fx.SAMPLE_SRT)
t.check(s1.format == "srt" and len(s1.cues) == 2 and s1.cues[0].start == 1.0 and s1.cues[0].end == 2.5 and s1.cues[1].text == "<i>deuxième</i> ligne\nsuite", "SRT")
t.check(s1.cues[1].plain_text() == "deuxième ligne\nsuite", "texte sans balises")
s2 := subs.parse(fx.SAMPLE_VTT)
t.check(s2.format == "vtt" and len(s2.cues) == 2 and s2.cues[0].ident == "intro" and s2.cues[0].settings == "align:start" and s2.cues[1].start == 60.0 and s2.cues[1].end == 61.25, "WebVTT (NOTE ignorée, réglages)")
back := subs.parse(subs.format_vtt(subs.parse(subs.format_srt(s1))))
t.check(len(back.cues) == 2 and back.cues[1].end == 4.0 and back.cues[0].text == "Bonjour", "SRT -> WebVTT -> SRT")
t.check(len(s1.at(1.5)) == 1 and len(s1.at(2.7)) == 0 and s1.next_after(2.7).start == 3.0, "sous-titre actif")
s1.shift(-2.0)
t.check(s1.cues[0].start == 0.0 and s1.cues[0].end == 0.5 and s1.cues[1].start == 1.0, "décalage borné à 0")
s1.scale(2.0)
t.check(s1.cues[1].end == 4.0, "changement d'échelle")
t.check(subs.parse("1\n00:00:02,000 --> 00:00:01,000\nx\n\n2\n00:00:00,500 --> 00:00:03,000\n\n").problems() == ["#1 : fin avant le début", "#2 : texte vide", "#2 : chevauche le précédent"], "contrôle des sous-titres")
t.raises("CorruptDataError", () => subs.parse("1\n00:00:0x,000 --> 00:00:01,000\nx\n"), "horodatage illisible")
t.raises("CorruptDataError", () => subs.parse_vtt("pas un vtt\n00:01.000 --> 00:02.000\n"), "WEBVTT absent")
t.raises("UnsupportedError", () => subs.parse("du texte"), "format non reconnu")
crlf := subs.parse("﻿1\r\n00:00:01,000 --> 00:00:02,000\r\nWindows\r\n\r\n")
t.check(len(crlf.cues) == 1 and crlf.cues[0].text == "Windows", "BOM et fins de ligne Windows")
aff := psub.SubtitleDisplay(subs.parse(fx.SAMPLE_SRT), 0.5)
c0 := aff.update(1.2)
c1 := aff.update(1.6)
c2 := aff.update(3.1)
t.check(c0["text"] == "" and c1["text"] == "Bonjour" and len(c1["shown"]) == 1 and len(c2["hidden"]) == 1 and c2["text"] == "", "affichage avec décalage")
pl2 := mp.Player(fake.FakeAudioOutput(f8), null, 800)
pl2.open(path)
pl2.attach_subtitles(subs.parse(fx.SAMPLE_SRT))
pl2.play()
pl2.run(null, 2)
t.check(pl2.subtitle_text() == "", "pas de sous-titre à 0,2 s")
pl2.seek(0.9)
pl2.pump(1)
t.check(pl2.subtitle_text() == "Bonjour", "sous-titre pendant la lecture")

# ---------------------------------------------------------------- chapitres
c := ch.parse("00:00 Intro\n01:30 - Couplet\n04:10 Fin", 300.0)
t.check(c.count() == 3 and c.at(95.0).title == "Couplet" and c.items[2].end == 300.0 and c.items[0].end == 90.0, "chapitres simples")
t.check(c.next_start(95.0) == 250.0 and c.previous_start(91.0) == 0.0 and c.previous_start(100.0) == 90.0, "navigation")
t.check(ch.format_simple(c) == "00:00 Intro\n01:30 Couplet\n04:10 Fin", "écriture simple")
og := ch.parse(ch.format_ogm(c), 300.0)
t.check(og.count() == 3 and og.items[1].title == "Couplet" and og.items[1].start == 90.0, "OGM aller-retour")
t.check("chapitre 1 : commence après la fin du média" in ch.parse("10:00 Après la fin", 60.0).problems(), "contrôle des chapitres")
t.raises("CorruptDataError", () => ch.parse("xx:00 Mauvais"), "chapitre illisible")

# ---------------------------------------------------------------- étiquettes
tags := tg.Tags({"INAM": "Titre", "TPE1": "Artiste", "TRACKNUMBER": "3/12", "year": "2026-05-01", "Perso": "x"})
t.check(tags.get("title") == "Titre" and tags.get("artist") == "Artiste" and tags.track_number() == 3 and tags.track_total() == 12, "normalisation")
t.check(tags.year() == 2026 and tags.get("perso") == "x", "année, clé libre")
t.check(tags.to_format("id3")["TIT2"] == "Titre" and tags.to_format("vorbis")["TRACKNUMBER"] == "3/12" and tags.to_format("riff")["INAM"] == "Titre", "conversion vers les formats")
tags.merge_missing({"title": "Autre", "genre": "Jazz"})
t.check(tags.get("title") == "Titre" and tags.get("genre") == "Jazz", "fusion sans écraser")
tags.set("comment", "   ")
t.check(not tags.has("comment"), "valeur vide ignorée")
tags.remove("genre")
t.check(not tags.has("genre") and len(tags.describe()) > 0, "retrait, description")
t.raises("FormatError", () => tags.to_format("xml"), "format inconnu")

# ---------------------------------------------------------------- faux périphériques
inp := fake.FakeAudioInput(af.AudioFormat(8000, 2, "f32le"), "sine", 440.0, 0.1)
blk := inp.read(300)
t.check(len(blk) == 600 and blk[0] == blk[1] and len(inp.read(1000)) == 1000, "entrée factice")
cam := fake.FakeCamera(16, 8, 25, "gradient", 3)
i0 := cam.read()
i1 := cam.read()
cam.read()
t.check(i0.width == 16 and i0.meta["timestamp"] == 0.0 and i1.meta["timestamp"] == 0.04 and cam.read() == null, "caméra factice")
t.check(not i0.equals(i1), "images différentes d'une image à l'autre")

fx.cleanup()
t.summary()
