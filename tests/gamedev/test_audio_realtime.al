# ALEX - tests de audio.realtime (dorsal « null » enregistré). ./alex run tests/gamedev/test_audio_realtime.al
use audio.realtime as rt
use testing
from testing use assert_eq, assert_true, assert_near
from collections use append

const DATA := "tests/gamedev/data/"

func t_load_wav():
    s := rt.load_wav(DATA + "bip_22k.wav")
    assert_eq(s.channels, 1)
    assert_eq(s.rate, 22050)
    assert_eq(s.frames, 5512)
    r := s.resampled(44100)
    assert_eq(r.rate, 44100)
    assert_true(r.frames >= 11023 and r.frames <= 11025)

testing.test("WAV PCM 16 bits et rééchantillonnage", t_load_wav)

func t_mix():
    eng := rt.AudioEngine(44100, 256, 0.02, "null", "default", true)
    assert_eq(eng.backend_name, "null")
    a := eng.sound([0.5 for i in 0..1000], 1)
    b := eng.sound([0.25 for i in 0..300], 1)
    va := eng.play(a, 1.0, -1.0)
    vb := eng.play(b, 1.0, 1.0, true)
    fin := []
    va.on_end = (v) => append(fin, 1)
    eng._mix(256)
    eng.out.write(eng.pcm, 256)
    rec := eng.recorded()
    assert_near(rec[0] / 32767.0, 0.5, 0.001)          # gauche : son a seul
    assert_near(rec[1] / 32767.0, 0.25, 0.001)         # droite : son b seul
    k := 0
    while k < 6:
        eng._mix(256)
        k += 1
    assert_eq(len(fin), 1)
    assert_eq(eng.active_voices(), 1)                  # b boucle encore
    vb.fade_out(0.001)
    eng._mix(256)
    assert_eq(eng.active_voices(), 0)
    eng.close()

testing.test("mixage, panoramique, fin de voix, boucle, fondu", t_mix)

func t_groups_spatial():
    eng := rt.AudioEngine(44100, 256, 0.02, "null")
    s := eng.sound([0.5 for i in 0..1000], 1)
    v := eng.play(s, 1.0, 0.0, false, "music")
    eng.set_group_volume("music", 0.5)
    g := eng._gains(v)
    assert_near(g[0], 0.5)
    v.set_position([5.0, 0.0, 0.0])                    # à droite de l'auditeur (regarde vers -Z)
    g = eng._gains(v)
    assert_true(g[1] > g[0])
    v.set_position([0.0, 0.0, -100.0])                 # au-delà de max_distance
    g = eng._gains(v)
    assert_near(g[0], 0.0)
    eng.close()

testing.test("groupes et son 3D", t_groups_spatial)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) audio.realtime en échec")
print("AUDIO_REALTIME: OK")
