# alexc test attend les fonctions `async func test_*` (testing.run_async) ; testing.run refuse un test async avec
# un message clair au lieu de le compter réussi sans l'avoir exécuté.
use asyncio as aio
use testing
use os
from collections use append
from testing use assert_eq, assert_true

TRACE := []

async func test_async_attendu():
    await aio.sleep(0.01)
    append(TRACE, "async")
    assert_eq(len(TRACE), 1)

func test_sync_toujours_pris_en_charge():
    assert_eq(1 + 1, 2)

async func test_run_synchrone_refuse_un_test_async():
    async func dedans():
        await aio.sleep(0)
    # appel indirect : sinon `alexc test` croirait ce fichier autonome (détection par le texte de l'appel)
    lancer := testing.run_tests
    lancer_async := testing.run_tests_async
    rapport := os.getenv("ALEX_TEST_REPORT")
    os.setenv("ALEX_TEST_REPORT", "0")           # ces exécutions imbriquées ne sont pas des résultats du fichier
    n := lancer([["async dans run", dedans]], false)
    assert_eq(n, 1)
    assert_eq(testing.summary()["errors"], 1)
    m := await lancer_async([["async dans run_async", dedans]], false)
    os.setenv("ALEX_TEST_REPORT", rapport if rapport != null else "")
    assert_eq(m, 0)
