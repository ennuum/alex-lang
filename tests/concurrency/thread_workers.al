# Fonctions exécutées dans des fils par tests/concurrency/test_thread.al.
from core use len
from collections use append
use concurrency.thread as thread
use time
use network.tcp as tcp

func square(n):
    return n * n

# Calcul long sans pause (vérifie le parallélisme) : renvoie la somme et les instants de début et de fin.
func busy(n):
    start := time.monotonic()
    s := 0
    i := 0
    while i < n:
        s = (s + i * i) % 1000003
        i += 1
    return [s, start, time.monotonic()]

func modify(items):
    append(items, "ajouté dans le fil")
    items[0] = "modifié"
    return items

func structures(d):
    return {"liste": [1, 2.5, "trois", null, true], "tuple": (d["a"], 'c'), "imbriqué": {"k": [[1], {"x": d}]}}

func fail(kind):
    raise(kind, "échec volontaire dans le fil")

func whoami():
    return [thread.is_main(), thread.current_id()]

# Renvoie chaque message reçu en majuscules, jusqu'à "stop".
func echo():
    n := 0
    while true:
        m := thread.receive(5.0)
        if m == "stop":
            return n
        thread.send("écho : " + m)
        n += 1

# Produit count valeurs dans le canal partagé ; renvoie leur somme.
func produce(chan_id, base, count):
    ch := thread.attach(chan_id)
    s := 0
    i := 0
    while i < count:
        ch.send(base + i)
        s += base + i
        i += 1
    return s

func sleepy(seconds):
    time.sleep(seconds)
    return "réveillé"

# Lance lui-même un fil (fils imbriqués).
func nested(n):
    t := thread.spawn(square, [n])
    return t.join() + 1

func returns_function():
    return square

# Serveur TCP dans un fil : envoie son port au parent, répond à un client puis s'arrête.
func tcp_echo_server():
    srv := tcp.listen("127.0.0.1", 0)
    thread.send(srv.port())
    c := srv.accept(10.0)
    line := c.read_line(10.0)
    c.write_line("le fil a reçu : " + line)
    c.close()
    srv.close()
    return line
