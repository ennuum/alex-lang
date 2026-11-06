# ALEX - non-régression : un fil (thread.spawn) qui se termine ne doit pas fermer les réserves (ThreadPool) de son
# parent. Avant la correction, __th_join_all fermait dans chaque fil les canaux de TOUTES les réserves : les tâches
# soumises ensuite n'étaient jamais exécutées.
#   ./alex run tests/test_thread_pool_after_spawn.al
use time
use concurrency.thread as thread
use thread.thread_pool as tp

func carre(x):
    return x * x

func court(x):
    time.sleep(0.05)
    return x

if thread.is_main():
    pool := tp.ThreadPool(2)
    a := pool.submit(carre, [3])
    if a.result(5.0) != 9:
        raise("AssertionError", "première tâche")
    t := thread.spawn(court, [1])
    t.join(5.0)                        # le fil a fini (et exécuté sa routine de fin)
    time.sleep(0.1)
    fs := [pool.submit(carre, [i]) for i in [4, 5, 6]]
    out := [f.result(5.0) for f in fs]  # TimeoutError avant la correction
    if out != [16, 25, 36]:
        raise("AssertionError", "résultats : " + str(out))
    pool.shutdown()
    print("réserve de fils après thread.spawn : OK")
