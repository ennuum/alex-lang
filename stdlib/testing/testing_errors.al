# ALEX STANDARD LIBRARY — testing.testing_errors
#
# Erreurs du cadre de test :
#   AssertionError   assertion fausse : le test ÉCHOUE
#   SkipTest         levée par skip() dans un test : le test est IGNORÉ (avec sa raison)
#   MockError        vérification d'un mock non satisfaite (assert_called_with...)
#   PropertyError    propriété réfutée par un contre-exemple (testing.property_test)
#   TestSetupError   set_up / set_up_class en échec : les tests concernés sont en ERREUR
# Toute autre exception levée par un test le met en ERREUR (bogue du test ou du code testé).
#
#   use testing.testing_errors as te
#   te.skip("réseau indisponible")

const ASSERTION := "AssertionError"
const SKIP := "SkipTest"
const MOCK := "MockError"
const PROPERTY := "PropertyError"
const SETUP := "TestSetupError"

func fail(message):
    raise(ASSERTION, message)

func skip(reason="ignoré"):
    raise(SKIP, reason)

func is_failure(error_type):
    return error_type == ASSERTION or error_type == MOCK or error_type == PROPERTY

func is_skip(error_type):
    return error_type == SKIP
