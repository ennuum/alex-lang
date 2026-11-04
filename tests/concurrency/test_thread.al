# Test de concurrency.thread : fils parallèles isolés (une VM par fil), copie des valeurs, erreurs, boîtes aux
# lettres, canaux partagés, parallélisme réel. Les fonctions des fils sont dans thread_workers.al, sauf
# local_double, définie ici : ce script protège donc son code de haut niveau par `if thread.is_main():`.

from core use len, type
from collections use append
use time
use concurrency.thread as thread
use network.tcp as tcp
use tests.concurrency.thread_workers as w

func local_double(x):
    return 2 * x

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

last_message := [""]
func error_of(f):
    try:
        f()
    catch e:
        last_message[0] = e.message
        return e.type
    return "aucune erreur"

func main():
    check(thread.supported(), "supported")
    check(thread.cpu_count() >= 1, "cpu_count")
    check(thread.is_main(), "is_main dans le programme principal")
    check_eq(thread.current_id(), 0, "current_id du programme principal")

    # Base : résultat, fonction du script principal (garde is_main), identité du fil.
    check_eq(thread.spawn(w.square, [12]).join(), 144, "résultat d'un fil")
    check_eq(thread.spawn(local_double, [21]).join(), 42, "fonction du script principal")
    who := thread.spawn(w.whoami).join()
    check_eq(who[0], false, "is_main dans un fil")
    check(who[1] > 0, "current_id dans un fil")

    # Copie : le fil modifie sa copie, pas l'original.
    original := ["a", "b"]
    copy := thread.spawn(w.modify, [original]).join()
    check_eq(original, ["a", "b"], "argument copié, original intact")
    check_eq(copy, ["modifié", "b", "ajouté dans le fil"], "résultat de la copie modifiée")
    r := thread.spawn(w.structures, [{"a": 7}]).join()
    check_eq(r["liste"], [1, 2.5, "trois", null, true], "list mixte")
    check_eq(r["tuple"], (7, 'c'), "tuple et char")
    check_eq(r["imbriqué"]["k"][1]["x"]["a"], 7, "structures imbriquées")

    # Erreurs.
    t := thread.spawn(w.fail, ["ValueError"], "défaillant")
    check_eq(error_of(() => t.join()), "ValueError", "erreur du fil relancée par join")
    check(last_message[0] == "échec volontaire dans le fil [fil " + str(t.id) + " : défaillant]", "message de l'erreur du fil")
    check(len(t.trace()) > 0, "trace de l'erreur du fil")
    check_eq(error_of(() => t.join()), "ValueError", "join répété : même erreur")
    check_eq(error_of(() => thread.spawn(w.square, [() => 1])), "TypeError", "argument non copiable")
    check_eq(error_of(() => thread.spawn((x) => x, [1])), "ArgumentError", "lambda refusée")
    check_eq(error_of(() => thread.spawn(w.returns_function).join()), "TypeError", "résultat non copiable")
    check_eq(error_of(() => thread.Thread(w.square, [1]).join()), "ThreadError", "join avant start")
    t2 := thread.Thread(w.square, [3]).start()
    check_eq(error_of(() => t2.start()), "ThreadError", "start répété")
    t2.join()

    # Délais.
    s := thread.spawn(w.sleepy, [0.5])
    check_eq(error_of(() => s.join(0.05)), "TimeoutError", "join : délai dépassé")
    check(s.is_alive(), "is_alive pendant le sommeil")
    check_eq(s.join(), "réveillé", "join après le délai")
    check(not s.is_alive(), "is_alive après la fin")

    # Boîte aux lettres : échanges avec un fil.
    e := thread.spawn(w.echo)
    e.send("un")
    e.send("deux")
    check_eq(e.receive(5.0), "écho : un", "boîte aux lettres : premier écho")
    check_eq(e.receive(5.0), "écho : deux", "boîte aux lettres : second écho")
    check_eq(error_of(() => e.receive(0.05)), "TimeoutError", "receive : délai dépassé")
    e.send("stop")
    check_eq(e.join(), 2, "fil d'écho terminé")
    check_eq(error_of(() => e.receive(1.0)), "ChannelClosedError", "receive après la fin du fil")

    # Canal partagé par trois producteurs.
    ch := thread.Channel()
    ps := []
    for k in 0..3:
        append(ps, thread.spawn(w.produce, [ch.id, 1000 * k, 50]))
    total := 0
    count := 0
    while count < 150:
        total += ch.receive(10.0)
        count += 1
    sums := 0
    for p in ps:
        sums += p.join()
    check_eq(total, sums, "canal partagé : toutes les valeurs reçues")
    check_eq(ch.try_receive(), (false, null), "canal vide")
    ch.close()
    check(ch.closed(), "canal fermé")
    check_eq(error_of(() => ch.send(1)), "ChannelClosedError", "send sur un canal fermé")
    bounded := thread.Channel(1)
    bounded.send("x")
    check_eq(error_of(() => bounded.send("y", 0.05)), "TimeoutError", "canal plein : délai")
    check_eq(bounded.receive(), "x", "canal borné")
    check_eq(error_of(() => thread.attach(999999)), "ArgumentError", "attach d'un canal inconnu")

    # Un serveur TCP dans un fil, le client dans le programme principal.
    srv := thread.spawn(w.tcp_echo_server)
    port := srv.receive(10.0)
    conn := tcp.connect("127.0.0.1", port, 5.0)
    conn.write_line("bonjour")
    check_eq(conn.read_line(10.0), "le fil a reçu : bonjour", "serveur TCP dans un fil")
    conn.close()
    check_eq(srv.join(), "bonjour", "fil serveur terminé")

    # Fils imbriqués, parallel_map.
    check_eq(thread.spawn(w.nested, [5]).join(), 26, "fil qui lance un fil")
    check_eq(thread.parallel_map(w.square, [1, 2, 3, 4, 5, 6], 3), [1, 4, 9, 16, 25, 36], "parallel_map dans l'ordre")

    # Parallélisme : deux calculs simultanés se chevauchent dans le temps.
    n := 3000000
    a := thread.spawn(w.busy, [n])
    b := thread.spawn(w.busy, [n])
    ra := a.join()
    rb := b.join()
    check_eq(ra[0], rb[0], "mêmes résultats")
    overlap := ra[1] < rb[2] and rb[1] < ra[2]
    check(overlap, "exécutions qui se chevauchent")
    if thread.cpu_count() >= 2:
        solo := w.busy(n)
        single := solo[2] - solo[1]
        both := (ra[2] - ra[1] + rb[2] - rb[1]) / 2
        print(f"parallélisme : un calcul seul {single} s, chacun des deux en parallèle {both} s")

    check_eq(thread.active_count(), 0, "plus aucun fil actif")

    print(f"thread : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for note in notes:
        print("  ÉCHEC " + note)
    if stats[1] > 0:
        raise("TestError", "test_thread : échecs")

if thread.is_main():
    main()
