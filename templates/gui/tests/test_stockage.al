use os
use io
use modeles.taches as taches
use services.stockage as stockage
use testing

func _fichier(nom):
    d := os.join(os.tmp_dir(), "{{nom}}_tests_" + str(os.pid()))
    os.mkdir_all(d)
    return os.join(d, nom)

func test_aller_retour():
    f := _fichier("taches.json")
    l := taches.Liste()
    l.ajouter("préparer la démo")
    l.basculer(0)
    stockage.enregistrer(l, f)
    testing.assert_eq(stockage.charger(f).vers_donnees(), [{"titre": "préparer la démo", "faite": true}])
    os.remove(f)

func test_fichier_absent():
    testing.assert_eq(len(stockage.charger(_fichier("absent.json")).elements), 0)

func test_fichier_abime_mis_de_cote():
    f := _fichier("abime.json")
    io.write_file(f, "{ ceci n'est pas du JSON")
    testing.assert_eq(len(stockage.charger(f).elements), 0)
    testing.assert_true(os.isfile(f + ".bak"))
    os.remove(f)
    os.remove(f + ".bak")
