use routes
use testing
use string

func test_bonjour():
    r := routes.repondre("GET", "/api/bonjour", {"nom": "Alex"})
    testing.assert_eq(r[0], 200)
    testing.assert_eq(r[1]["message"], "Bonjour, Alex !")

func test_introuvable():
    testing.assert_eq(routes.repondre("GET", "/nulle-part", {})[0], 404)

func test_reponse_json():
    rep := routes.traiter("GET", "/api/bonjour", {"nom": "Alex"})
    testing.assert_eq(rep.status, 200)
    testing.assert_eq(rep.headers["Content-Type"], "application/json")

func test_reponse_texte_404():
    rep := routes.traiter("GET", "/nulle-part", {})
    testing.assert_eq(rep.status, 404)
    testing.assert_true(string.starts_with(rep.headers["Content-Type"], "text/plain"))
    testing.assert_eq(rep.body, "introuvable : /nulle-part\n")
