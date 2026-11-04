# ALEX - tests du gestionnaire de ressources (cache, arrière-plan, rechargement à chaud, chargeurs personnalisés).
# ./alex run tests/gamedev/test_assets.al
use os
use io
use time
use assets
use testing
from testing use assert_eq, assert_true
from collections use append

const DATA := "tests/gamedev/data"
const TMP := "/tmp/alex_test_assets"

func t_sync_cache():
    am := assets.AssetManager(DATA)
    a := am.get("niveau.tmj")
    assert_eq(a.kind, "tilemap")
    assert_eq(a.value.width, 6)
    b := am.get("niveau.tmj")
    assert_true(a == b)
    assert_eq(a.refs, 2)
    s := am.get("bip_22k.wav")
    assert_eq(s.value.frames, 5512)
    am.release("niveau.tmj")
    assert_eq(am.stats()["assets"], 2)
    am.release("niveau.tmj")
    assert_eq(am.stats()["assets"], 1)
    am.shutdown()

testing.test("synchrone, cache, références", t_sync_cache)

func t_async():
    am := assets.AssetManager(DATA)
    a := am.load_async("niveau.tmx")
    b := am.load_async("la440_stereo.ogg")
    c := am.load_async("absent.json")
    assert_eq(a.state, "loading")
    fin := []
    a.on_ready((x) => append(fin, x.path))
    k := 0
    while am.pending_count() > 0 and k < 4000:
        am.update()
        time.sleep(0.002)
        k += 1
    assert_eq(a.state, "ready")
    assert_eq(len(a.value.layers), 3)
    assert_eq(b.value.frames, 88200)
    assert_eq(c.state, "error")
    assert_eq(fin, ["niveau.tmx"])
    assert_true(am.progress() == 1.0)
    am.shutdown()

testing.test("arrière-plan, erreurs, progression", t_async)

func t_async_model():
    # le modèle glTF est analysé et construit dans un fil, puis recréé sur le fil principal
    am := assets.AssetManager(DATA)
    a := am.load_async("bras.glb")
    k := 0
    while am.pending_count() > 0 and k < 4000:
        am.update()
        time.sleep(0.002)
        k += 1
    assert_eq(a.state, "ready")
    m := a.value
    assert_eq(len(m.nodes), 4)
    assert_eq(m.skins[0]["joints"], [1, 2])
    assert_true(m.clip("plie").duration > 0.99)
    am.shutdown()

testing.test("modèle glTF construit en arrière-plan", t_async_model)

func t_reload_custom():
    if not os.exists(TMP):
        os.mkdir(TMP)
    io.write_file(TMP + "/reglages.json", "{\"vitesse\": 1}")
    am := assets.AssetManager(TMP)
    am.register("majuscules", (m, p, o) => io.read_file(p) + "!", null)
    io.write_file(TMP + "/mot.txt", "alex")
    m := am.get("mot.txt", "majuscules")
    assert_eq(m.value, "alex!")
    r := am.get("reglages.json")
    vus := []
    r.on_reload((x) => append(vus, x.value["vitesse"]))
    am.watch(true, 0.0)
    time.sleep(1.1)
    io.write_file(TMP + "/reglages.json", "{\"vitesse\": 2}")
    am.update()
    assert_eq(vus, [2])
    assert_eq(r.version, 1)
    assert_eq(am.check_reload(), [])
    am.shutdown()

testing.test("rechargement à chaud, chargeur personnalisé", t_reload_custom)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) assets en échec")
print("ASSETS: OK")
