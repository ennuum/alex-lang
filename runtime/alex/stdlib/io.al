

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

func _io_error(fn: str, path: str, what: str):
    raise("IoError", fn + "('" + path + "') : " + what)

func read_file(path: str) -> str:
    fd := __syscall(2, _cstr(path), 0)
    if fd < 0:
        _io_error("read_file", path, "impossible d'ouvrir le fichier")
    sb := __rt_sb_new()
    buf := __alloc_raw(65536)
    while true:
        n := __syscall(0, fd, buf, 65536)
        if n < 0:
            __syscall(3, fd)
            _io_error("read_file", path, "erreur de lecture")
        if n == 0:
            __syscall(3, fd)
            return __rt_sb_str(sb)
        i := 0
        while i < n:
            __rt_sb_byte(sb, __load8(buf + i))
            i += 1
    return ""

func _write(fn: str, path: str, content: str, flags: int):
    fd := __syscall(2, _cstr(path), flags, 438)
    if fd < 0:
        if flags == 577:
            _io_error(fn, path, "impossible d'ouvrir le fichier en écriture")
        _io_error(fn, path, "impossible d'ouvrir le fichier")
    p := __str_addr(content) + 8
    n := __load64(p - 8)
    done := 0
    while done < n:
        w := __syscall(1, fd, p + done, n - done)
        if w <= 0:
            __syscall(3, fd)
            _io_error(fn, path, "erreur d'écriture")
        done += w
    __syscall(3, fd)

func write_file(path: str, content: str):
    _write("write_file", path, content, 577)

func append_file(path: str, content: str):
    _write("append_file", path, content, 1089)

func file_exists(path: str) -> bool:
    return (_mode(path) & 61440) == 32768

func delete_file(path: str):
    if not file_exists(path):
        _io_error("delete_file", path, "fichier introuvable")
    if __syscall(87, _cstr(path)) != 0:
        _io_error("delete_file", path, "suppression impossible")
