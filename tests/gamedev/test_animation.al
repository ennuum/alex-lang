# ALEX - tests du module animation (glTF : squelette, clips, mélange, morphing). ./alex run tests/gamedev/test_animation.al
use animation
use math
use testing
from testing use assert_eq, assert_true, assert_near
from collections use append

const DATA := "tests/gamedev/data/"

func near3(a, b):
    k := 0
    while k < 3:
        assert_near(a[k], b[k], 0.0001)
        k += 1

func t_load():
    for f in ["bras.gltf", "bras.glb"]:
        m := animation.load_gltf(DATA + f)
        assert_eq(len(m.nodes), 4)
        assert_eq(m.node_index("os1"), 2)
        assert_eq(m.nodes[2]["parent"], 1)
        assert_eq(len(m.skins), 1)
        assert_eq(m.skins[0]["joints"], [1, 2])
        assert_eq(len(m.meshes[1][0]["targets"]), 1)
        assert_near(m.clip("plie").duration, 1.0)
        assert_eq(m.materials[0]["color"], [1.0, 0.0, 0.0, 1.0])

testing.test("chargement .gltf / .glb", t_load)

func t_skinning():
    m := animation.load_gltf(DATA + "bras.gltf")
    prim := m.meshes[0][0]
    a := animation.Animator(m)
    near3(animation.skinned_position(prim, 8, a), [-0.2, 2.0, -0.2])
    a.play("plie")
    a.update(0.25)
    near3(a.node_position("os0"), [0.0, 0.0, 0.0])          # STEP : translation encore nulle
    a.update(0.749999)
    near3(a.node_position("os0"), [1.0, 0.0, 0.0])
    near3(animation.skinned_position(prim, 8, a), [0.0, 0.8, -0.2])   # os1 tourné de 90° autour de z
    near3(animation.skinned_position(prim, 0, a), [0.8, 0.0, -0.2])   # anneau du bas : os0 seul

testing.test("skinning, STEP, LINEAR / slerp", t_skinning)

func t_blend():
    m := animation.load_gltf(DATA + "bras.gltf")
    prim := m.meshes[0][0]
    a := animation.Animator(m)
    a.blend([["plie", 1.0], ["morph", 1.0]])                 # canaux disjoints : chacun à plein poids
    a.update(0.999999)
    near3(animation.skinned_position(prim, 8, a), [0.0, 0.8, -0.2])
    assert_near(a.morph_weights(3)[0], 1.0, 0.0001)
    a.blend([["plie", 0.5]])                                  # demi-poids : 45° et demi-translation
    a.update(0.0)
    c := math.cos(math.PI / 4)
    near3(animation.skinned_position(prim, 8, a), [0.5 - 0.2 * c - c, 1.0 - 0.2 * c + c, -0.2])
    a.play("plie", 0.0)
    a.play("morph", 0.5)
    a.update(0.25)
    w := {}
    for t in a.tracks:
        w[t.clip.name] = t.weight
    assert_near(w["plie"], 0.5, 0.0001)
    assert_near(w["morph"], 0.5, 0.0001)
    a.update(0.5)
    assert_eq(a.current(), "morph")
    assert_eq(len(a.tracks), 1)

testing.test("mélange par canal, fondu enchaîné", t_blend)

func t_once_cubic():
    m := animation.load_gltf(DATA + "bras.gltf")
    a := animation.Animator(m)
    fin := []
    a.on_end = (an, name) => append(fin, name)
    a.play("plie", 0.0, false)
    a.update(2.0)
    assert_eq(fin, ["plie"])
    # CUBICSPLINE : tangentes nulles -> courbe en S, valeur médiane au milieu
    c := animation.Clip("s")
    c.add_channel(2, "translation", [0.0, 1.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                                                  0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0], "CUBICSPLINE", 3)
    assert_near(animation.sample_channel(c.channels[0], 0.5)[0], 1.0, 0.0001)
    assert_near(animation.sample_channel(c.channels[0], 0.25)[0], 2.0 * (3 * 0.0625 - 2 * 0.015625), 0.0001)
    q := animation.slerp([0.0, 0.0, 0.0, 1.0], [0.0, 0.0, 1.0, 0.0], 0.5)
    assert_near(q[2], math.sqrt(0.5), 0.0001)

testing.test("fin de clip, CUBICSPLINE, slerp", t_once_cubic)

# Chaîne d'os alignés sur y (longueur 1), sans maillage : IK, look_at.
func chain(n):
    m := animation.Model()
    k := 0
    while k < n:
        append(m.nodes, {"name": "j" + str(k), "parent": k - 1, "children": [k + 1] if k + 1 < n else [],
                         "t": [0.0, 1.0 if k > 0 else 0.0, 0.0], "r": [0.0, 0.0, 0.0, 1.0], "s": [1.0, 1.0, 1.0],
                         "mesh": -1, "skin": -1, "weights": null})
        k += 1
    m._compute_order()
    return m

func t_mask_additive():
    m := animation.load_gltf(DATA + "bras.gltf")
    s := math.sqrt(0.5)
    # masque par os : seul os1 (rotation) est animé, la translation d'os0 est ignorée
    a := animation.Animator(m)
    a.play("plie")
    a.tracks[0].mask = animation.bone_mask(m, ["os1"])
    a.update(0.999999)
    near3(a.local_trs(1)[0], [0.0, 0.0, 0.0])
    near3(a.node_position("os1"), [0.0, 1.0, 0.0])
    q := a.local_trs(2)[1]
    assert_near(q[2], s, 0.0001)
    assert_near(q[3], s, 0.0001)
    # couche additive : différence avec l'instant 0 ajoutée à la pose de repos
    b := animation.Animator(m)
    b.set_layer("recul", "plie", 1.0, null, true)
    b.update(0.999999)
    near3(b.local_trs(1)[0], [1.0, 0.0, 0.0])
    assert_near(b.local_trs(2)[1][2], s, 0.0001)
    # demi-poids : demi-translation, 45°
    c := animation.Animator(m)
    c.set_layer("recul", "plie", 0.5, null, true)
    c.update(0.999999)
    near3(c.local_trs(1)[0], [0.5, 0.0, 0.0])
    assert_near(c.local_trs(2)[1][2], math.sin(math.PI / 8), 0.0001)
    # couche masquée remplaçante, fondu d'entrée puis de sortie
    d := animation.Animator(m)
    d.play("morph")
    tr := d.set_layer("bras", "plie", 1.0, animation.bone_mask(m, ["os0"], 1.0, false), false, 0.5)
    d.update(0.25)
    assert_near(tr.weight, 0.5, 0.0001)
    d.update(0.5)
    assert_near(tr.weight, 1.0, 0.0001)
    near3(d.local_trs(1)[0], [1.0, 0.0, 0.0])
    assert_near(d.local_trs(2)[1][2], 0.0, 0.0001)          # os1 hors du masque (sans les enfants)
    d.clear_layer("bras", 0.2)
    d.update(0.3)
    assert_eq(len(d.layers), 0)

testing.test("masques par os, couches additives, fondus de couche", t_mask_additive)

func t_ik():
    m := chain(3)
    a := animation.Animator(m)
    a.update(0.0)
    a.ik_two_bone("j0", "j1", "j2", [1.2, 1.0, 0.0], [1.0, 2.0, 0.0])
    near3(a.node_position("j2"), [1.2, 1.0, 0.0])
    assert_near(m3len(a.node_position("j1")), 1.0, 0.0001)   # longueurs conservées
    # cible hors d'atteinte : bras tendu vers elle
    a.ik_two_bone("j0", "j1", "j2", [0.0, 0.0, 5.0])
    p := a.node_position("j2")
    assert_true(p[2] > 1.99 and math.abs(p[0]) < 0.01)
    # CCD sur une chaîne de 5 os
    c := animation.Animator(chain(5))
    c.update(0.0)
    rest := c.ik_ccd(["j0", "j1", "j2", "j3", "j4"], [1.5, 2.0, 1.0], 20, 0.001)
    assert_true(rest < 0.01)
    # look_at : l'axe local y de j0 vise +x
    l := animation.Animator(chain(2))
    l.update(0.0)
    l.look_at("j0", [5.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    near3(l.node_position("j1"), [1.0, 0.0, 0.0])

testing.test("cinématique inverse : deux os, CCD, look_at", t_ik)

func m3len(v):
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])

func t_dict():
    m := animation.load_gltf(DATA + "bras.gltf")
    m2 := animation.model_from_dict(animation.model_to_dict(m))
    assert_eq(len(m2.nodes), len(m.nodes))
    assert_near(m2.clip("plie").duration, 1.0)
    a := animation.Animator(m2)
    a.play("plie")
    a.update(0.999999)
    near3(animation.skinned_position(m2.meshes[0][0], 8, a), [0.0, 0.8, -0.2])
    assert_eq(len(m2.meshes[1][0]["targets"]), 1)

testing.test("modèle en dictionnaire (transfert entre fils)", t_dict)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) animation en échec")
print("ANIMATION: OK")
