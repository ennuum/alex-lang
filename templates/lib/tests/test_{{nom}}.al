use {{nom}}
use testing

func test_slug():
    testing.assert_eq({{nom}}.slug("Bonjour le Monde !"), "bonjour-le-monde")
    testing.assert_eq({{nom}}.slug("  A--B  "), "a-b")

func test_mots():
    testing.assert_eq({{nom}}.mots("un deux  trois"), 3)
    testing.assert_eq({{nom}}.mots(""), 0)
