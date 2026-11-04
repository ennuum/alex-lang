use texte
use testing

func test_code():
    testing.assert_eq(texte.code('A'), 65)
    testing.assert_eq(texte.code('é'), 63)

func test_titre():
    testing.assert_eq(texte.titre("X"), "=== X ===")
