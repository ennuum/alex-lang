# Actions de l'application, sans fenêtre : état, enregistrement automatique, rechargement.
use os
use app.application as application
use testing

func _fichier():
    d := os.join(os.tmp_dir(), "{{nom}}_app_" + str(os.pid()))
    os.mkdir_all(d)
    f := os.join(d, "taches.json")
    if os.exists(f):
        os.remove(f)
    return f

func test_ajouter_et_recharger():
    f := _fichier()
    application.demarrer(f)
    application.saisir("tâche 1")
    application.ajouter()
    testing.assert_eq(application.etat["saisie"], "")
    application.saisir("tâche 2")
    application.ajouter()
    application.basculer(0)
    # nouvelle session : les tâches ont été enregistrées
    application.demarrer(f)
    testing.assert_eq(len(application.etat["liste"].elements), 2)
    testing.assert_eq(application.etat["liste"].restantes(), 1)
    os.remove(f)

func test_titre_vide_refuse():
    application.demarrer(null)
    application.saisir("   ")
    application.ajouter()
    testing.assert_eq(len(application.etat["liste"].elements), 0)
    testing.assert_true(application.etat["message"] != "")

func test_filtre_et_vider():
    application.demarrer(null)
    for t in ["a", "b"]:
        application.saisir(t)
        application.ajouter()
    application.basculer(1)
    application.filtrer("faites")
    testing.assert_eq(application.etat["liste"].visibles(application.etat["filtre"]), [1])
    application.vider_faites()
    testing.assert_eq(len(application.etat["liste"].elements), 1)
