use modeles.taches as taches
use testing

func test_ajout():
    l := taches.Liste()
    testing.assert_true(l.ajouter("  écrire la doc "))
    testing.assert_false(l.ajouter("   "))
    testing.assert_eq(l.elements[0]["titre"], "écrire la doc")

func test_restantes_et_filtres():
    l := taches.Liste()
    l.ajouter("a")
    l.ajouter("b")
    l.ajouter("c")
    l.basculer(1)
    testing.assert_eq(l.restantes(), 2)
    testing.assert_eq(l.visibles("toutes"), [0, 1, 2])
    testing.assert_eq(l.visibles("a_faire"), [0, 2])
    testing.assert_eq(l.visibles("faites"), [1])

func test_supprimer_et_vider():
    l := taches.Liste()
    for t in ["a", "b", "c"]:
        l.ajouter(t)
    l.supprimer(0)
    testing.assert_eq(l.elements[0]["titre"], "b")
    l.basculer(0)
    testing.assert_eq(l.vider_faites(), 1)
    testing.assert_eq(len(l.elements), 1)

func test_donnees():
    l := taches.Liste()
    l.ajouter("x")
    l.basculer(0)
    r := taches.depuis_donnees(l.vers_donnees())
    testing.assert_eq(r.elements, [{"titre": "x", "faite": true}])
    # entrées invalides ignorées
    testing.assert_eq(len(taches.depuis_donnees([{"titre": ""}, 3, {"faite": true}]).elements), 0)
