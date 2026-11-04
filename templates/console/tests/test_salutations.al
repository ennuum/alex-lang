use salutations
use testing

func test_bonjour():
    testing.assert_eq(salutations.bonjour("Alex"), "Bonjour, Alex !")

func test_resume():
    r := salutations.resume([3, 1, 4, 1, 5])
    testing.assert_eq(r["total"], 14)
    testing.assert_eq(r["min"], 1)
    testing.assert_eq(r["max"], 5)
