# ALEX STANDARD LIBRARY — ipc
#
# Communication entre PROCESSUS de la même machine :
#
# | Besoin                                         | Outil                                   |
# |------------------------------------------------|-----------------------------------------|
# | partager des octets, des compteurs, un verrou  | ipc.shared_memory (SharedMemory, SharedCounter, SharedMutex) |
# | déposer / retirer des messages                 | ipc.message_queue (POSIX ou mémoire partagée)             |
# | limiter l'accès à une ressource                | ipc.semaphore (NamedSemaphore)                            |
# | un flux d'octets bidirectionnel                | ipc.local_socket (socket Unix : serveur, connexions)      |
# | échanger des valeurs, appeler des fonctions    | ipc.channel (JSON, question / réponse, multi-clients)     |
# | relier un parent et ses fils                   | pipe (tubes), process (flux des fils)                     |
#
#   use ipc
#   m := ipc.shared_memory("compteurs", 4096)
#   q := ipc.message_queue("travaux")
#   s := ipc.semaphore("gpu", 1)
#   c := ipc.connect("service")              # canal de valeurs (ipc.channel)
#   srv := ipc.serve("service")
#
# Les noms sont propres à la machine ; ils survivent aux processus jusqu'à unlink (mémoire, files, sémaphores)
# ou close du serveur (sockets). ipc.cleanup(nom) supprime tout ce qui porte ce nom.

use ipc.shared_memory as _shm
use ipc.message_queue as _mq
use ipc.semaphore as _sem
use ipc.local_socket as _ls
use ipc.channel as _ch
use _native_sync as _s

func supported():
    return _s.supported_ipc()

func shared_memory(name, size=0, mode="open_or_create"):
    return _shm.SharedMemory(name, size, mode)

func message_queue(name, max_messages=10, max_size=8192, backend=null):
    return _mq.open(name, max_messages, max_size, backend)

func semaphore(name, value=1):
    return _sem.NamedSemaphore(name, value, "open_or_create")

func listen(name):
    return _ls.listen(name)

func connect_socket(name, timeout=null):
    return _ls.connect(name, timeout)

# Canal de valeurs (ipc.channel.Channel).
func connect(name, timeout=null):
    return _ch.connect(name, timeout)

func serve(name):
    return _ch.serve_on(name)

# Supprime la mémoire partagée, les files et le sémaphore portant ce nom ; renvoie le nombre d'objets supprimés.
func cleanup(name):
    n := 0
    if _shm.unlink(name):
        n += 1
    if _mq.unlink(name):
        n += 1
    if _sem.unlink(name):
        n += 1
    return n
