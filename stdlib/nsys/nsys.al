# alex: native
# NOVA (édition bureau) — appels système, version Linux : enveloppe du module posix, plus le lancement de
# processus avec tube (spawn) et les services propres à la plateforme. La version Windows (nsys_windows.al) a la
# même interface ; construire.sh installe l'une ou l'autre sous le nom « nsys ».
use posix
use os
from core use len
from collections use append

func platform() -> str:
    return "linux"

func uptime_ms() -> int:
    return posix.uptime_ms()

func time() -> int:
    return posix.time()

func sleep_ms(ms: int):
    posix.sleep_ms(ms)

func open(path: str, mode: str = "r") -> int:
    return posix.open(path, mode)

func read(fd: int, n: int = 4096) -> str:
    return posix.read(fd, n)

func read_all(fd: int) -> str:
    return posix.read_all(fd)

func write(fd: int, s: str) -> int:
    return posix.write(fd, s)

func close(fd: int):
    posix.close(fd)

func exists(path: str) -> bool:
    return posix.exists(path)

func mkdir(path: str):
    posix.mkdir(path)

func rmdir(path: str):
    posix.rmdir(path)

func unlink(path: str):
    posix.unlink(path)

func rename(old: str, new: str):
    posix.rename(old, new)

func listdir(path: str) -> list[str]:
    return posix.listdir(path)

func getpid() -> int:
    return posix.getpid()

func environ() -> list[str]:
    return posix.environ()

func exit(code: int = 0):
    posix.exit(code)

func set_nonblock(fd: int):
    posix.set_nonblock(fd)

func read_nb(fd: int, n: int = 4096) -> str:
    return posix.read_nb(fd, n)

# Chemin de l'exécutable courant.
func exe_path() -> str:
    return posix.readlink("/proc/self/exe")

# Lance path (argv[0] compris) : mode 0 sans tube, 1 sortie standard lue par l'appelant, 2 entrée standard écrite
# par l'appelant. env : environnement de l'enfant (vide : celui du processus). Rend [processus, descripteur].
func spawn(path: str, argv: list[str], mode: int, env: list[str]) -> list[int]:
    pp := [-1, -1]
    if mode != 0:
        pp = posix.pipe()
    pid := posix.fork()
    if pid == 0:
        if mode == 1:
            posix.dup2(pp[1], 1)
        elif mode == 2:
            posix.dup2(pp[0], 0)
        k := 3
        while k < 64:
            try:
                posix.close(k)
            catch e0:
                pass
            k += 1
        try:
            if len(env) > 0:
                posix.execve(path, argv, env)
            else:
                posix.execv(path, argv)
        catch e1:
            pass
        posix.exit(127)
    if mode == 1:
        posix.close(pp[1])
        return [pid, pp[0]]
    if mode == 2:
        posix.close(pp[0])
        return [pid, pp[1]]
    return [pid, -1]

# Vrai si le processus est terminé (nohang : sans attendre).
func waited(pid: int, nohang: bool) -> bool:
    return posix.waitpid(pid, nohang) == pid

func terminate(pid: int):
    posix.kill(pid, 9)

# Presse-papiers : sous Linux, les outils du système (xclip, xsel, wl-clipboard) sont lancés par l'appelant.
func clipboard_native() -> bool:
    return false

func clipboard_set(t: str) -> bool:
    return false

func clipboard_get() -> str:
    return ""

# Son : sous Linux, le lecteur du système (paplay, aplay…) est lancé par l'appelant.
func sound_native() -> bool:
    return false

func play_sound(path: str) -> bool:
    return false

func stop_sound():
    pass

# Sons par le système (MCI sous Windows) : absent sous Linux.
func sound_open(id: int, path: str) -> int:
    return -1

func sound_play(id: int, from_ms: int) -> bool:
    return false

func sound_pause(id: int):
    pass

func sound_close(id: int):
    pass

func sound_playing(id: int) -> bool:
    return false

func sound_position(id: int) -> int:
    return -1

func sound_volume(id: int, v: int):
    pass

# Facteur d'échelle de l'affichage en % (100 : 96 ppp).
func display_scale() -> int:
    return 100

# Dossiers de l'utilisateur.
func home_dir() -> str:
    h := os.getenv("HOME", "")
    if h != null:
        t: str := h
        if t != "":
            return t
    return "/tmp"

func known_downloads() -> str:
    return ""

func temp_dir() -> str:
    return "/tmp"

# Ouvre une adresse ou un fichier avec l'application du système (xdg-open).
func open_external(target: str) -> bool:
    for p in ["/usr/bin/xdg-open", "/bin/xdg-open"]:
        if posix.exists(p):
            spawn(p, [p, target], 0, [])
            return true
    return false

# --- HTTP par le système (WinHTTP sous Windows) : absent sous Linux (transport navtls).
class HttpReq:
    handle: int := 0
    status: int := 0
    headers: str := ""
    ecat: str := ""
    emsg: str := ""
    tls: str := ""
    subject: str := ""
    issuer: str := ""
    proto: str := ""

func http_native() -> bool:
    return false

func http_open(host: str, port: int, secure: bool, method: str, path: str, headers: list[str], body: str, agent: str, ignore_cert: bool, http2: bool, tls13: bool) -> HttpReq:
    r := HttpReq()
    r.ecat = "connexion"
    r.emsg = "HTTP du système indisponible"
    return r

func http_read(r: HttpReq, n: int) -> str:
    return ""

func http_close(r: HttpReq):
    pass
