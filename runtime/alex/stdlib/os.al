from collections use append
from core use len

func _cstr(s: str) -> int:
    p := __str_addr(s)
    n := __load64(p)
    c := __alloc_raw(n + 1)
    __copy(c, p + 8, n)
    __store8(c + n, 0)
    return c

func _from_c(c: int) -> str:
    n := 0
    while __load8(c + n) != 0:
        n += 1
    r := __rt_str_new(n)
    __copy(r + 8, c, n)
    return __as_str(r)

func _errno_text(e: int) -> str:
    if e == 1:
        return "Operation not permitted"
    if e == 3:
        return "No such process"
    if e == 10:
        return "No child processes"
    if e == 16:
        return "Device or resource busy"
    if e == 18:
        return "Invalid cross-device link"
    if e == 22:
        return "Invalid argument"
    if e == 30:
        return "Read-only file system"
    if e == 2:
        return "No such file or directory"
    if e == 13:
        return "Permission denied"
    if e == 17:
        return "File exists"
    if e == 20:
        return "Not a directory"
    if e == 21:
        return "Is a directory"
    if e == 28:
        return "No space left on device"
    if e == 39:
        return "Directory not empty"
    if e == 88:
        return "Socket operation on non-socket"
    if e == 97:
        return "Address family not supported by protocol"
    if e == 100:
        return "Network is down"
    if e == 104:
        return "Connection reset by peer"
    if e == 107:
        return "Transport endpoint is not connected"
    if e == 110:
        return "Connection timed out"
    if e == 111:
        return "Connection refused"
    if e == 113:
        return "No route to host"
    if e == 9:
        return "Bad file descriptor"
    if e == 11:
        return "Resource temporarily unavailable"
    if e == 12:
        return "Cannot allocate memory"
    if e == 14:
        return "Bad address"
    if e == 24:
        return "Too many open files"
    if e == 27:
        return "File too large"
    if e == 32:
        return "Broken pipe"
    if e == 38:
        return "Function not implemented"
    if e == 122:
        return "Disk quota exceeded"
    return "error " + str(e)

# stat : mode du fichier (st_mode), ou -1 s'il n'existe pas.
func _mode(path: str) -> int:
    st := __alloc_raw(144)
    if __syscall(4, _cstr(path), st) != 0:
        return -1
    return __load64(st + 24) & 4294967295

func name() -> str:
    return _uname(0) # "Linux" (ou "AlexOS" sous le noyau Alex, "Windows" sous Windows)

func platform() -> str:
    if __windows():
        return "windows"
    return "linux"

func arch() -> str:
    if __a64():
        return "aarch64"
    return "x86_64"

func argv() -> list[str]:
    sp := __argv_base()
    n := __load64(sp)
    out: list[str] := []
    i := 0
    while i < n:
        append(out, _from_c(__load64(sp + 8 + 8 * i)))
        i += 1
    return out

func argc() -> int:
    return __load64(__argv_base())

func args() -> list[str]:
    full := argv()
    out: list[str] := []
    i := 1
    while i < len(full):
        append(out, full[i])
        i += 1
    return out

func exit(code: int = 0):
    if code < 0 or code > 255:
        raise("ValueError", "exit : le code de sortie doit être compris entre 0 et 255 (obtenu " + str(code) + ")")
    __flush()
    __exit(code)

# Valeur de « nom=valeur » dans l'environnement initial, ou fallback.
func getenv(name_: str, fallback: str? = null) -> str?:
    sp := __argv_base()
    p := sp + 8 * (__load64(sp) + 2)
    key := __str_addr(name_)
    k := __load64(key)
    while __load64(p) != 0:
        c := __load64(p)
        j := 0
        if __windows(): # noms insensibles à la casse (ASCII), comme GetEnvironmentVariableW
            while j < k and _fold(__load8(c + j)) == _fold(__load8(key + 8 + j)):
                j += 1
        else:
            while j < k and __load8(c + j) == __load8(key + 8 + j):
                j += 1
        if j == k and __load8(c + k) == 61:
            return _from_c(c + k + 1)
        p += 8
    return fallback

func _fold(b: int) -> int:
    if b >= 65 and b <= 90:
        return b + 32
    return b

func hasenv(name_: str) -> bool:
    return getenv(name_) != null

func pid() -> int:
    return __syscall(39)

func parent_pid() -> int:
    return __syscall(110)

func cwd() -> str:
    buf := __alloc_raw(4096)
    if __syscall(79, buf, 4096) < 0:
        raise("IoError", "cwd() : getcwd a échoué")
    return _from_c(buf)

func chdir(path: str):
    r := __syscall(80, _cstr(path))
    if r < 0:
        raise("IoError", "chdir('" + path + "') : " + _errno_text(0 - r))

# Crée UN dossier ; son parent doit exister, lui-même ne doit pas exister (comme la VM).
func mkdir(path: str):
    r := __syscall(83, _cstr(path), 493)
    if r < 0:
        raise("IoError", "mkdir('" + path + "') : " + _errno_text(0 - r))

# Supprime un dossier vide (rmdir récursif de la VM : non pris en charge en natif).
func rmdir(path: str):
    r := __syscall(84, _cstr(path))
    if r < 0:
        msg := _errno_text(0 - r)
        if r == -20:
            msg = "n'est pas un dossier"
        raise("IoError", "rmdir('" + path + "') : " + msg)

# Supprime un fichier ; refuse les dossiers (voir rmdir).
func remove(path: str):
    r := __syscall(87, _cstr(path))
    if r < 0:
        msg := _errno_text(0 - r)
        if r == -21:
            msg = "est un dossier (utiliser rmdir)"
        raise("IoError", "remove('" + path + "') : " + msg)

func exists(path: str) -> bool:
    return _mode(path) >= 0

func isfile(path: str) -> bool:
    return (_mode(path) & 61440) == 32768

func isdir(path: str) -> bool:
    m := _mode(path)
    return m >= 0 and (m & 61440) == 16384

func _uname(field: int) -> str:
    buf := __alloc_raw(390)
    __syscall(63, buf)
    return _from_c(buf + 65 * field)

func hostname() -> str:
    return _uname(1)

func version() -> str:
    return _uname(2)
