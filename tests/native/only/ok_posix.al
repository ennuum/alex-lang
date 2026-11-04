# Module natif posix : fork, pipe, dup2, waitpid, execv, kill, signaux ignorés, listdir (getdents64).
use posix
use os
from core use len

# fork + tube : l'enfant écrit, le parent lit jusqu'à la fin de fichier puis récupère le code.
t := posix.pipe()
pid := posix.fork()
if pid == 0:
    posix.close(t[0])
    posix.write(t[1], "message de l'enfant")
    posix.exit(7)
posix.close(t[1])
print("lu : " + posix.read_all(t[0]))
posix.close(t[0])
print("waitpid -> enfant : " + str(posix.waitpid(pid) == pid) + ", code " + str(posix.status()))

# dup2 : la sortie standard de l'enfant va dans le tube.
t = posix.pipe()
pid = posix.fork()
if pid == 0:
    posix.dup2(t[1], 1)
    posix.close(t[0])
    posix.close(t[1])
    print("via dup2")
    posix.exit(0)
posix.close(t[1])
print("capturé : " + posix.read_all(t[0]))
posix.waitpid(pid)

# execv d'un programme absent : erreur rattrapée dans l'enfant.
pid = posix.fork()
if pid == 0:
    try:
        posix.execv("/inexistant/programme", ["programme"])
    catch e:
        posix.exit(42)
posix.waitpid(pid)
print("execv absent -> code " + str(posix.status()))

# Signal : l'enfant boucle, le parent le tue.
pid = posix.fork()
if pid == 0:
    while true:
        x := 1
posix.kill(pid, posix.SIGKILL)
posix.waitpid(pid)
print("SIGKILL -> code " + str(posix.status()))

# Signal ignoré (hérité par fork) puis SIGTERM toujours fatal après default_signal.
posix.ignore_signal(posix.SIGINT)
pid = posix.fork()
if pid == 0:
    posix.kill(posix.getpid(), posix.SIGINT)
    posix.default_signal(posix.SIGINT)
    posix.exit(3)
posix.waitpid(pid)
print("SIGINT ignoré -> code " + str(posix.status()))
posix.default_signal(posix.SIGINT)

# WNOHANG sans enfant terminé, puis attente.
pid = posix.fork()
if pid == 0:
    i := 0
    while i < 2000000:
        i += 1
    posix.exit(1)
print("nohang : " + str(posix.waitpid(pid, true)))
posix.waitpid(pid)
print("puis code " + str(posix.status()))

# listdir (getdents64)
d := "/tmp/alex_posix_test_" + str(posix.getpid())
os.mkdir(d)
os.mkdir(d + "/sous")
posix.close(posix.open(d + "/a.txt", "w"))
noms := posix.listdir(d)
print("entrées : " + str(len(noms)))
os.remove(d + "/a.txt")
os.rmdir(d + "/sous")
os.rmdir(d)
