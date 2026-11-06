# Fonctions de calcul pour tests/web/test_web_server_offload.al (exécutées dans des fils).
use time

# Calcul qui occupe un cœur environ `secondes`.
func lourd(secondes):
    t0 := time.monotonic()
    n := 0
    while time.monotonic() - t0 < secondes:
        n += 1
    return n

func carre(x):
    return x * x

func boum(message):
    raise("ValueError", message)
