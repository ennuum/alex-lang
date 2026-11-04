# multimedia : fichiers HOSTILES (tronqués, en-têtes incohérents, tailles déclarées énormes, dimensions excessives,
# bombes de décompression, formats non pris en charge). Chaque cas doit lever l'erreur attendue — jamais une
# erreur interne (IndexError, TypeError...) ni une allocation non bornée — ou être accepté avec un avertissement.
# Plus un test de robustesse : 300 mutations aléatoires reproductibles d'un WAV et d'un PNG valides.
from core use len
use io
use audio.audio_format as af
use multimedia.container.demux as dmx
use multimedia.container.probe as probe
use multimedia.image.decode as dec
use multimedia.image.image as mi
use multimedia.image.encode as enc
use multimedia.metadata.subtitles as subs
use multimedia.playback.playlist as pl
use multimedia.core.errors as merr
use multimedia.security.limits as lim
use multimedia.testing.fixtures as fx
use multimedia.testing.assertions as ta

t := ta.Checker("multimedia fichiers hostiles")
func _empty():
    p := fx.temp_path("vide.bin")
    io.write_bytes(p, [])
    return p

for cas in fx.hostile_wavs():
    p := fx.temp_path("hostile.wav")
    io.write_bytes(p, cas[1])
    got := null
    warnings := 0
    try:
        d := dmx.WavDemuxer(p)
        d.read_all()
        warnings = len(d.info.warnings)
        d.close()
    catch e:
        got = e.type
    if cas[2] == null:
        t.check(got == null and warnings > 0, "WAV " + cas[0] + " : accepté avec avertissement (" + str(got) + ")")
    else:
        t.check(got == cas[2], "WAV " + cas[0] + " : " + str(got) + " au lieu de " + cas[2])
    # le sondage réagit pareil (jamais d'erreur interne)
    pr := null
    try:
        probe.probe(p)
    catch e:
        pr = e.type
    t.check(pr == null or merr.is_media_error(pr), "sondage WAV " + cas[0] + " : " + str(pr))

t.raises("UnsupportedError", () => dmx.open(_empty(), null, "native_only"), "open() d'un fichier vide : format non reconnu")
for cas in fx.hostile_images():
    got := null
    try:
        dec.decode(cas[1])
    catch e:
        got = e.type
    t.check(got == cas[2], "image " + cas[0] + " : " + str(got) + " au lieu de " + cas[2])

# limites strictes appliquées avant le décodage
grand := enc.encode_png(mi.new(300, 20, "gray", [7]))
t.raises("LimitError", () => dec.decode(grand, lim.Limits({"max_width": 256})), "largeur au-delà de la limite")
t.raises("LimitError", () => dec.decode(grand, lim.Limits({"max_file_bytes": 10})), "taille au-delà de la limite")
t.raises("LimitError", () => subs.parse(fx.SAMPLE_SRT, lim.Limits({"max_cues": 1})), "nombre de sous-titres limité")
t.raises("LimitError", () => subs.parse(fx.SAMPLE_SRT, lim.Limits({"max_text_bytes": 10})), "texte de sous-titres limité")
t.raises("LimitError", () => pl.parse_m3u("a\nb\nc\n", null, lim.Limits({"max_playlist_items": 2})), "liste limitée")

# ---------------------------------------------------------------- mutations reproductibles
state := [12345]
func rnd(n):
    state[0] = (state[0] * 1103515245 + 12345) & 0x7FFFFFFF
    return state[0] % n

func mutate(b, k):
    out := [x for x in b]
    kind := k % 4
    if kind == 0:
        for i in 0..1 + rnd(4):
            p := rnd(len(out))
            out[p] = rnd(256)
    elif kind == 1:
        out = [out[i] for i in 0..rnd(len(out))]
    elif kind == 2:
        p := rnd(len(out))
        out = [out[i] for i in 0..p] + [255, 255, 255, 127] + [out[i] for i in p..len(out)]
    else:
        p := 4 + rnd(40)
        if p + 4 <= len(out):
            out[p] = 255
            out[p + 1] = 255
            out[p + 2] = 255
            out[p + 3] = 127
    return out

png := enc.encode_png(mi.gradient(9, 5, "rgba"))
internal := []
for k in 0..150:
    b := mutate(png, k)
    try:
        dec.decode(b)
    catch e:
        if not merr.is_media_error(e.type):
            internal = internal + [e.type + " : " + e.message]
t.check(len(internal) == 0, "PNG mutés : seulement des erreurs multimédias " + str(internal))
wavb := fx.wav_bytes(fx.sine(440, 0.02, 8000), af.AudioFormat(8000, 1, "s16le"))
internal2 := []
for k in 0..150:
    b := mutate(wavb, k)
    p := fx.temp_path("m.wav")
    io.write_bytes(p, b)
    try:
        d := dmx.open(p)
        d.read_all()
        d.close()
    catch e:
        if not merr.is_media_error(e.type):
            internal2 = internal2 + [e.type + " : " + e.message]
t.check(len(internal2) == 0, "WAV mutés : seulement des erreurs multimédias " + str(internal2))

t.check(fx.cleanup() > 0, "fichiers temporaires nettoyés")
t.summary()
