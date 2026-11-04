

# ---- Windows : argc / argv / envp ----------------------------------------------------------------
# Construit le bloc que le noyau Linux place sur la pile initiale : [argc][argv...][0][envp...][0], chaînes
# UTF-8 terminées par un zéro. Appelée par le point d'entrée avant tout le reste : le tas du ramasse-miettes
# n'existe pas encore (il lit lui-même l'environnement, ALEX_GC_STRESS), d'où la mémoire prise par __mmap.
func __rt_win_init() -> int:
    cl := __wincall("GetCommandLineW")
    n := __rt_w32(__wincall("WideCharToMultiByte", 65001, 0, cl, -1, 0, 0, 0, 0))
    src := __mmap(n + 2)
    if n > 0:
        __wincall("WideCharToMultiByte", 65001, 0, cl, -1, src, n, 0, 0)
    env := __wincall("GetEnvironmentStringsW")
    k := 0
    if env != 0:
        while __load16(env + 2 * k) != 0 or __load16(env + 2 * k + 2) != 0:
            k += 1
        k += 2
    m := 0
    if k > 0:
        m = __rt_w32(__wincall("WideCharToMultiByte", 65001, 0, env, k, 0, 0, 0, 0))
    ebuf := __mmap(m + 2)
    if m > 0:
        __wincall("WideCharToMultiByte", 65001, 0, env, k, ebuf, m, 0, 0)
    if env != 0:
        __wincall("FreeEnvironmentStringsW", env)
    ne := 0
    i := 0
    while i < m and __load8(ebuf + i) != 0:
        ne += 1
        while __load8(ebuf + i) != 0:
            i += 1
        i += 1
    out := __mmap(n + 2)
    block := __mmap(8 * (n + ne + 4))
    argc := __rt_win_split(src, out, block + 8)
    __store64(block, argc)
    __store64(block + 8 + 8 * argc, 0)
    p := block + 16 + 8 * argc
    i = 0
    while i < m and __load8(ebuf + i) != 0:
        __store64(p, ebuf + i)
        p += 8
        while __load8(ebuf + i) != 0:
            i += 1
        i += 1
    __store64(p, 0)
    return block

# Découpe la ligne de commande `s` (UTF-8) comme la CRT de Microsoft : argv[0] jusqu'au guillemet fermant ou
# au premier blanc, sans échappement ; ensuite, 2n barres obliques inverses + « " » -> n barres et bascule de
# la zone entre guillemets, 2n+1 barres + « " » -> n barres et un guillemet littéral, « "" » dans une zone
# entre guillemets -> un guillemet littéral. Arguments copiés dans `out`, leurs adresses rangées dans `ptrs`.
func __rt_win_split(s: int, out: int, ptrs: int) -> int:
    i := 0
    o := 0
    __store64(ptrs, out)
    argc := 1
    if __load8(s) == 34:
        i = 1
        while __load8(s + i) != 0 and __load8(s + i) != 34:
            __store8(out + o, __load8(s + i))
            o += 1
            i += 1
        if __load8(s + i) == 34:
            i += 1
    else:
        while __load8(s + i) != 0 and __load8(s + i) != 32 and __load8(s + i) != 9:
            __store8(out + o, __load8(s + i))
            o += 1
            i += 1
    __store8(out + o, 0)
    o += 1
    while true:
        while __load8(s + i) == 32 or __load8(s + i) == 9:
            i += 1
        if __load8(s + i) == 0:
            return argc
        __store64(ptrs + 8 * argc, out + o)
        argc += 1
        quoted := false
        while true:
            c := __load8(s + i)
            if c == 0:
                break
            if not quoted and (c == 32 or c == 9):
                break
            if c == 92:
                nb := 0
                while __load8(s + i) == 92:
                    nb += 1
                    i += 1
                if __load8(s + i) == 34:
                    j := 0
                    while j < nb // 2:
                        __store8(out + o, 92)
                        o += 1
                        j += 1
                    if nb % 2 == 1:
                        __store8(out + o, 34)
                        o += 1
                        i += 1
                else:
                    j := 0
                    while j < nb:
                        __store8(out + o, 92)
                        o += 1
                        j += 1
            elif c == 34:
                if quoted and __load8(s + i + 1) == 34:
                    __store8(out + o, 34)
                    o += 1
                    i += 2
                else:
                    quoted = not quoted
                    i += 1
            else:
                __store8(out + o, c)
                o += 1
                i += 1
        __store8(out + o, 0)
        o += 1
    return argc

# ---- Windows : émulation des appels système Linux utilisés par le runtime et la stdlib ---------------
func __rt_win_syscall(nr: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    if nr == 0:
        return __rt_win_read(a, b, c)
    if nr == 1:
        return __rt_win_write(a, b, c)
    if nr == 2:
        return __rt_win_open(a, b)
    if nr == 3:
        if __rt_ws_entry(a) != 0:
            return __rt_ws_close(a)
        return __rt_win_ok(__wincall("CloseHandle", __rt_win_handle(a)))
    if nr == 7:
        return __rt_ws_poll(a, b, c)
    if nr == 72:
        return __rt_ws_fcntl(a, b, c)
    if nr == 41:
        return __rt_ws_socket(a, b, c)
    if nr == 42:
        return __rt_ws_connect(a, b, c)
    if nr == 43:
        return __rt_ws_accept(a, b, c, 0)
    if nr == 288:
        return __rt_ws_accept(a, b, c, d)
    if nr == 44:
        return __rt_ws_sendto(a, b, c, d, e, f)
    if nr == 45:
        return __rt_ws_recvfrom(a, b, c, d, e, f)
    if nr == 48:
        return __rt_ws_ret(__wincall("ws2_32.dll!shutdown", a, b))
    if nr == 49:
        return __rt_ws_ret(__wincall("ws2_32.dll!bind", a, __rt_ws_in(b, c), c))
    if nr == 50:
        return __rt_ws_ret(__wincall("ws2_32.dll!listen", a, b))
    if nr == 51 or nr == 52:
        return __rt_ws_name(nr, a, b, c)
    if nr == 53:
        return __rt_ws_socketpair(b, d)
    if nr == 54:
        return __rt_ws_setopt(a, b, c, d, e)
    if nr == 55:
        return __rt_ws_getopt(a, b, c, d, e)
    if nr == 318:
        return __rt_win_random(a, b)
    if nr == 4 or nr == 6:
        return __rt_win_stat(a, b)
    if nr == 5:
        return __rt_win_fstat(a, b)
    if nr == 8:
        return __rt_win_lseek(a, b, c)
    if nr == 74:
        # fsync : données et métadonnées du fichier sur le support (FlushFileBuffers)
        if __rt_w32(__wincall("FlushFileBuffers", __rt_win_handle(a))) == 0:
            return 0 - __rt_win_errno()
        return 0
    if nr == 76:
        return __rt_win_truncate(a, b)
    if nr == 77:
        return __rt_win_ftruncate(__rt_win_handle(a), b)
    if nr == 10:
        return __rt_win_mprotect(a, b, c)
    if nr == 35:
        return __rt_win_sleep(a)
    if nr == 39:
        return __rt_w32(__wincall("GetCurrentProcessId"))
    if nr == 63:
        return __rt_win_uname(a)
    if nr == 79:
        return __rt_win_getcwd(a, b)
    if nr == 80:
        return __rt_win_ok(__wincall("SetCurrentDirectoryW", __rt_win_wide(a)))
    if nr == 83:
        r := __rt_win_ok(__wincall("CreateDirectoryW", __rt_win_wide(a), 0))
        if r == -20:
            return -22                  # ERROR_DIRECTORY (nom invalide) : EINVAL, comme _wmkdir de la CRT
        return r
    if nr == 84:
        return __rt_win_ok(__wincall("RemoveDirectoryW", __rt_win_wide(a)))
    if nr == 87:
        return __rt_win_unlink(a)
    if nr == 110:
        return __rt_win_getppid()
    if nr == 228:
        return __rt_win_clock(a, b)
    return -38 # ENOSYS

func __rt_w32(x: int) -> int:
    return x & 4294967295

# BOOL de Windows -> 0 ou -errno (GetLastError).
func __rt_win_ok(r: int) -> int:
    if __rt_w32(r) != 0:
        return 0
    return 0 - __rt_win_errno()

func __rt_win_errno() -> int:
    return __rt_win_errno_of(__rt_w32(__wincall("GetLastError")))

# Code d'erreur Win32 -> errno de Linux (même table que _dosmaperr de la CRT, sauf ERROR_DIRECTORY : ENOTDIR,
# comme rmdir sur un fichier sous Linux).
func __rt_win_errno_of(e: int) -> int:
    if e == 2 or e == 3 or e == 15 or e == 18 or e == 53:
        return 2   # ENOENT
    if e == 5 or e == 19 or e == 32 or e == 33 or e == 1224:
        return 13  # EACCES
    if e == 80 or e == 183:
        return 17  # EEXIST
    if e == 145:
        return 39  # ENOTEMPTY
    if e == 267:
        return 20  # ENOTDIR
    if e == 6:
        return 9   # EBADF
    if e == 8 or e == 14:
        return 12  # ENOMEM
    if e == 4:
        return 24  # EMFILE
    if e == 112 or e == 39:
        return 28  # ENOSPC
    if e == 109 or e == 232:
        return 32  # EPIPE
    if e == 16:
        return 16  # EBUSY (répertoire courant)
    if e == 17:
        return 18  # EXDEV
    if e == 206:
        return 36  # ENAMETOOLONG
    return 22      # EINVAL

# Chaîne C UTF-8 -> chaîne UTF-16 terminée par un zéro (tas), ou 0 si `c` est nul.
func __rt_win_wide(c: int) -> int:
    if c == 0:
        return 0
    n := __rt_w32(__wincall("MultiByteToWideChar", 65001, 0, c, -1, 0, 0))
    w := __alloc_raw(2 * n + 2)
    __store16(w, 0)
    if n > 0:
        __wincall("MultiByteToWideChar", 65001, 0, c, -1, w, n)
    return w

func __rt_win_handle(fd: int) -> int:
    if fd >= 0 and fd <= 2:
        return __wincall("GetStdHandle", -10 - fd)
    return fd

func __rt_win_console(h: int) -> bool:
    m := __alloc_raw(8)
    return __rt_w32(__wincall("GetConsoleMode", h, m)) != 0

# Mode texte de la CRT (la VM écrite en ALEX l'active, comme la VM C++ compilée sous Windows) : état du runtime
# [1600] actif, [1608] fin de fichier vue (Ctrl+Z), [1616] octet mis de côté + 1 (lecture d'un CR en fin de tampon).
# Lecture : CR LF -> LF, Ctrl+Z (0x1A) = fin de fichier ; écriture (sorties standard et d'erreur) : LF -> CR LF.
func __rt_win_text() -> bool:
    return __load64(__state() + 1600) != 0

func __rt_win_read(fd: int, buf: int, n: int) -> int:
    if fd == 0 and __rt_win_text():
        return __rt_win_read_text(buf, n)
    return __rt_win_read_raw(fd, buf, n)

func __rt_win_read_text(buf: int, n: int) -> int:
    st := __state()
    if __load64(st + 1608) != 0 or n <= 0:
        return 0
    k := 0
    if __load64(st + 1616) != 0:
        __store8(buf, __load64(st + 1616) - 1)
        __store64(st + 1616, 0)
        k = 1
        if n > 1:
            r := __rt_win_read_raw(0, buf + 1, n - 1)
            if r > 0:
                k += r
    else:
        k = __rt_win_read_raw(0, buf, n)
        if k <= 0:
            return k
    i := 0
    j := 0
    while i < k:
        c := __load8(buf + i)
        if c == 26:
            __store64(st + 1608, 1)
            return j
        if c == 13:
            if i + 1 < k:
                if __load8(buf + i + 1) == 10:
                    i += 1
                    continue
            else:
                t := __alloc_raw(8)
                if __rt_win_read_raw(0, t, 1) == 1:
                    if __load8(t) == 10:
                        __store8(buf + j, 10)
                        return j + 1
                    __store64(st + 1616, __load8(t) + 1)
        __store8(buf + j, c)
        j += 1
        i += 1
    if j == 0:
        return __rt_win_read_text(buf, n)
    return j

func __rt_win_read_raw(fd: int, buf: int, n: int) -> int:
    if __rt_ws_entry(fd) != 0:
        return __rt_ws_recvfrom(fd, buf, n, 0, 0, 0)
    h := __rt_win_handle(fd)
    if fd == 0 and __rt_win_console(h):
        return __rt_win_read_console(h, buf, n)
    if n > 1073741824:
        n = 1073741824
    got := __alloc_raw(8)
    __store64(got, 0)
    if __rt_w32(__wincall("ReadFile", h, buf, n, got, 0)) == 0:
        e := __rt_w32(__wincall("GetLastError"))
        if e == 109 or e == 38: # tube refermé, fin de fichier : comme read() == 0
            return 0
        return 0 - __rt_win_errno_of(e)
    return __rt_w32(__load64(got))

# Console : lecture en UTF-16 (ReadConsoleW), rendue en UTF-8 ; Ctrl+Z en début de ligne = fin de fichier.
func __rt_win_read_console(h: int, buf: int, n: int) -> int:
    chars := n // 3
    if chars > 8192:
        chars = 8192
    if chars < 1:
        return 0
    w := __alloc_raw(2 * chars + 2)
    got := __alloc_raw(8)
    __store64(got, 0)
    if __rt_w32(__wincall("ReadConsoleW", h, w, chars, got, 0)) == 0:
        return 0 - __rt_win_errno()
    k := __rt_w32(__load64(got))
    if k == 0 or __load16(w) == 26:
        return 0
    return __rt_w32(__wincall("WideCharToMultiByte", 65001, 0, w, k, buf, n, 0, 0))

func __rt_win_write(fd: int, p: int, n: int) -> int:
    if (fd == 1 or fd == 2) and __rt_win_text():
        m := 0
        i := 0
        while i < n:
            if __load8(p + i) == 10:
                m += 1
            i += 1
        if m > 0:
            q := __alloc_raw(n + m + 8)
            i = 0
            j := 0
            while i < n:
                c := __load8(p + i)
                if c == 10:
                    __store8(q + j, 13)
                    j += 1
                __store8(q + j, c)
                j += 1
                i += 1
            r := __rt_win_write_raw(fd, q, j)
            if r < 0:
                return r
            return n
    return __rt_win_write_raw(fd, p, n)

func __rt_win_write_raw(fd: int, p: int, n: int) -> int:
    if __rt_ws_entry(fd) != 0:
        return __rt_ws_sendto(fd, p, n, 0, 0, 0)
    h := __rt_win_handle(fd)
    if n > 1073741824:
        n = 1073741824
    if (fd == 1 or fd == 2) and n > 0 and __rt_win_console(h):
        r := __rt_win_write_console(h, p, n)
        if r != -1:
            return r
    got := __alloc_raw(8)
    __store64(got, 0)
    if __rt_w32(__wincall("WriteFile", h, p, n, got, 0)) == 0:
        return 0 - __rt_win_errno()
    return __rt_w32(__load64(got))

# Console : le texte UTF-8 est rendu en UTF-16 (WriteConsoleW), quelle que soit la page de code de la console
# (850, 1252... : WriteFile y afficherait « ├® » pour « é »). Le tampon de sortie ne coupe jamais une chaîne
# (il se vide avant une chaîne qui n'y tient pas, une chaîne plus grande part d'un seul bloc) : chaque écriture
# porte des caractères entiers. Paquets de 16 Ki unités UTF-16, sans couper une paire de substitution.
# -1 : conversion impossible (l'appelant écrit alors les octets tels quels).
func __rt_win_write_console(h: int, p: int, n: int) -> int:
    m := __rt_w32(__wincall("MultiByteToWideChar", 65001, 0, p, n, 0, 0))
    if m <= 0:
        return -1
    w := __alloc_raw(2 * m + 8)
    __wincall("MultiByteToWideChar", 65001, 0, p, n, w, m)
    got := __alloc_raw(8)
    i := 0
    while i < m:
        k := m - i
        if k > 16384:
            k = 16384
            hi := __load16(w + 2 * (i + k - 1))
            if hi >= 55296 and hi <= 56319:
                k -= 1
        __store64(got, 0)
        if __rt_w32(__wincall("WriteConsoleW", h, w + 2 * i, k, got, 0)) == 0:
            return 0 - __rt_win_errno()
        i += k
    return n

# open(chemin, drapeaux Linux) : O_WRONLY 1, O_RDWR 2, O_CREAT 0x40, O_EXCL 0x80, O_TRUNC 0x200, O_APPEND 0x400.
func __rt_win_open(path: int, flags: int) -> int:
    acc := flags & 3
    access := 2147483648                # GENERIC_READ
    if acc == 1:
        access = 1073741824             # GENERIC_WRITE
    elif acc == 2:
        access = 3221225472
    if (flags & 1024) != 0:
        access = 1048580                # SYNCHRONIZE | FILE_APPEND_DATA : chaque écriture va à la fin
        if acc == 2:
            access = access | 2147483648
    disp := 3                           # OPEN_EXISTING
    if (flags & 64) != 0:
        if (flags & 128) != 0:
            disp = 1                    # CREATE_NEW
        elif (flags & 512) != 0:
            disp = 2                    # CREATE_ALWAYS
        else:
            disp = 4                    # OPEN_ALWAYS
    elif (flags & 512) != 0:
        disp = 5                        # TRUNCATE_EXISTING
    # partage lecture | écriture | suppression ; FILE_ATTRIBUTE_NORMAL | FILE_FLAG_BACKUP_SEMANTICS (dossiers)
    h := __wincall("CreateFileW", __rt_win_wide(path), access, 7, 0, disp, 33554560, 0)
    if h == -1:
        return 0 - __rt_win_errno()
    return h

# stat : struct stat de Linux x86-64 (144 octets) : st_nlink 16, st_mode 24, st_size 48, st_blksize 56,
# st_atime 72, st_mtime 88, st_ctime 104.
func __rt_win_stat(path: int, st: int) -> int:
    data := __alloc_raw(40)
    if __rt_w32(__wincall("GetFileAttributesExW", __rt_win_wide(path), 0, data)) == 0:
        return 0 - __rt_win_errno()
    __zero(st, 144)
    at := __load32(data)
    mode := 33188                       # fichier 0644
    if (at & 16) != 0:
        mode = 16877                    # dossier 0755
    elif (at & 1) != 0:
        mode = 33060                    # fichier en lecture seule 0444
    __store64(st + 16, 1)
    __store32(st + 24, mode)
    __store64(st + 48, (__load32(data + 28) << 32) | __load32(data + 32))
    __store64(st + 56, 4096)
    __rt_win_stt(st + 72, __load64(data + 12))
    __rt_win_stt(st + 88, __load64(data + 20))
    __rt_win_stt(st + 104, __load64(data + 4))
    return 0

# fstat : GetFileInformationByHandle (st_dev = numéro de série du volume, st_ino = index du fichier).
func __rt_win_fstat(fd: int, st: int) -> int:
    bi := __alloc_raw(56)
    if __rt_w32(__wincall("GetFileInformationByHandle", __rt_win_handle(fd), bi)) == 0:
        return 0 - __rt_win_errno()
    __zero(st, 144)
    at := __load32(bi)
    mode := 33188
    if (at & 16) != 0:
        mode = 16877
    elif (at & 1) != 0:
        mode = 33060
    __store64(st, __load32(bi + 28))
    __store64(st + 8, (__load32(bi + 44) << 32) | __load32(bi + 48))
    __store64(st + 16, __load32(bi + 40))
    __store32(st + 24, mode)
    __store64(st + 48, (__load32(bi + 32) << 32) | __load32(bi + 36))
    __store64(st + 56, 4096)
    __rt_win_stt(st + 72, __load64(bi + 12))
    __rt_win_stt(st + 88, __load64(bi + 20))
    __rt_win_stt(st + 104, __load64(bi + 4))
    return 0

# lseek : SetFilePointerEx (SEEK_SET / CUR / END = FILE_BEGIN / CURRENT / END).
func __rt_win_lseek(fd: int, off: int, whence: int) -> int:
    np := __alloc_raw(8)
    __store64(np, 0)
    if __rt_w32(__wincall("SetFilePointerEx", __rt_win_handle(fd), off, np, whence)) == 0:
        return 0 - __rt_win_errno()
    return __load64(np)

# ftruncate : fin du fichier à `size` (SetEndOfFile), position courante conservée.
func __rt_win_ftruncate(h: int, size: int) -> int:
    cur := __alloc_raw(8)
    __store64(cur, 0)
    if __rt_w32(__wincall("SetFilePointerEx", h, 0, cur, 1)) == 0:
        return 0 - __rt_win_errno()
    if __rt_w32(__wincall("SetFilePointerEx", h, size, 0, 0)) == 0:
        return 0 - __rt_win_errno()
    ok := __rt_w32(__wincall("SetEndOfFile", h))
    e := 0
    if ok == 0:
        e = __rt_win_errno()
    __wincall("SetFilePointerEx", h, __load64(cur), 0, 0)
    if ok == 0:
        return 0 - e
    return 0

func __rt_win_truncate(path: int, size: int) -> int:
    h := __wincall("CreateFileW", __rt_win_wide(path), 1073741824, 7, 0, 3, 0, 0)
    if h == -1:
        return 0 - __rt_win_errno()
    r := __rt_win_ftruncate(h, size)
    __wincall("CloseHandle", h)
    return r

# ---- Windows : sockets (Winsock 2) derrière les appels système de Linux -----------------------------------------
# socket, connect, accept(4), sendto, recvfrom, shutdown, bind, listen, getsockname, getpeername, socketpair
# (paire TCP sur la boucle locale), setsockopt / getsockopt (niveaux et options traduits), poll (WSAPoll), fcntl
# (O_NONBLOCK : ioctlsocket), read / write / close d'un socket. AF_INET6 vaut 10 sous Linux, 23 sous Windows : les
# adresses sont traduites à l'entrée et à la sortie. Sockets ouverts : table hors du tas (état du runtime [1624],
# 4096 entrées [poignée][non bloquant]) ; [1632] Winsock initialisé ; [1640] entrées utilisées (plus haute + 1).

func __rt_ws_table() -> int:
    st := __state()
    if __load64(st + 1632) == 0:
        d := __mmap(1024)
        __wincall("ws2_32.dll!WSAStartup", 514, d)
        __store64(st + 1624, __mmap(16 * 4096))
        __store64(st + 1632, 1)
    return __load64(st + 1624)

# Entrée du socket h, ou 0 si h n'est pas un socket ouvert par le runtime.
func __rt_ws_entry(h: int) -> int:
    t := __load64(__state() + 1624)
    if t == 0 or h <= 2:
        return 0
    top := __load64(__state() + 1640)
    i := 0
    while i < top:
        if __load64(t + 16 * i) == h:
            return t + 16 * i
        i += 1
    return 0

func __rt_ws_add(h: int, nb: bool):
    t := __rt_ws_table()
    i := 0
    while i < 4096:
        if __load64(t + 16 * i) == 0:
            if i + 1 > __load64(__state() + 1640):
                __store64(__state() + 1640, i + 1)
            __store64(t + 16 * i, h)
            __store64(t + 16 * i + 8, 0)
            if nb:
                __store64(t + 16 * i + 8, 1)
            return
        i += 1

func __rt_ws_nonblock(h: int, on: bool):
    a := __alloc_raw(8)
    __store64(a, 0)
    if on:
        __store64(a, 1)
    __wincall("ws2_32.dll!ioctlsocket", h, 2147772030, a) # FIONBIO
    e := __rt_ws_entry(h)
    if e != 0:
        __store64(e + 8, 0)
        if on:
            __store64(e + 8, 1)

# Dernière erreur Winsock -> errno de Linux.
func __rt_ws_errno() -> int:
    e := __rt_w32(__wincall("ws2_32.dll!WSAGetLastError"))
    if e == 10035:
        return 11
    if e == 10036:
        return 115
    if e == 10037:
        return 114
    if e == 10004:
        return 4
    if e == 10009 or e == 10038:
        return 9
    if e == 10013:
        return 13
    if e == 10014:
        return 14
    if e == 10022:
        return 22
    if e == 10024:
        return 24
    if e >= 10039 and e <= 10058 and e != 10044 and e != 10046:
        if e == 10039:
            return 89
        if e == 10040:
            return 90
        if e == 10041:
            return 91
        if e == 10042:
            return 92
        if e == 10043:
            return 93
        if e == 10045:
            return 95
        return e - 10047 + 97          # 10047 EAFNOSUPPORT 97 ... 10058 ESHUTDOWN 108
    if e == 10060:
        return 110
    if e == 10061:
        return 111
    if e == 10064:
        return 112
    if e == 10065:
        return 113
    return 5

# Adresse d'entrée : copie avec la famille IPv6 traduite (10 -> 23).
func __rt_ws_in(addr: int, len: int) -> int:
    if addr == 0 or len < 2 or __load16(addr) != 10:
        return addr
    c := __alloc_raw(len + 8)
    __copy(c, addr, len)
    __store16(c, 23)
    return c

func __rt_ws_out(addr: int):
    if addr != 0 and __load16(addr) == 23:
        __store16(addr, 10)

func __rt_ws_ret(r: int) -> int:
    if __rt_w32(r) == 4294967295:
        return 0 - __rt_ws_errno()
    return __rt_w32(r)

func __rt_ws_socket(domain: int, type: int, proto: int) -> int:
    __rt_ws_table()
    af := domain
    if domain == 10:
        af = 23
    h := __wincall("ws2_32.dll!WSASocketW", af, type & 15, proto, 0, 0, 128) # WSA_FLAG_NO_HANDLE_INHERIT
    if h == -1:
        return 0 - __rt_ws_errno()
    __rt_ws_add(h, (type & 2048) != 0)
    if (type & 2048) != 0:
        __rt_ws_nonblock(h, true)
    return h

# Destination de boucle locale (127/8, ::1, ::ffff:127/104) ?
func __rt_ws_is_loop(addr: int, len: int) -> bool:
    if addr == 0 or len < 8:
        return false
    f := __load16(addr)
    if f == 2:
        return __load8(addr + 4) == 127
    if (f == 10 or f == 23) and len >= 24:
        i := 0
        while i < 10:
            if __load8(addr + 8 + i) != 0:
                return false
            i += 1
        if __load8(addr + 18) == 255 and __load8(addr + 19) == 255:
            return __load8(addr + 20) == 127
        if __load8(addr + 18) != 0 or __load8(addr + 19) != 0 or __load32(addr + 20) != 16777216:
            return false
        return true
    return false

func __rt_ws_connect(h: int, addr: int, len: int) -> int:
    if __rt_ws_is_loop(addr, len):
        # Boucle locale : Windows réémet le SYN après un RST pendant ~2 s ; sans réémission, le refus
        # (ECONNREFUSED) est immédiat, comme sous Linux (SIO_TCP_INITIAL_RTO, sans perte possible ici).
        p := __alloc_raw(16)
        __zero(p, 16)
        __store16(p, 65535)             # TCP_INITIAL_RTO_UNSPECIFIED_RTT
        __store8(p + 2, 254)            # TCP_INITIAL_RTO_NO_SYN_RETRANSMISSIONS
        __wincall("ws2_32.dll!WSAIoctl", h, 2550136849, p, 4, 0, 0, p + 8, 0, 0)
    if __rt_w32(__wincall("ws2_32.dll!connect", h, __rt_ws_in(addr, len), len)) != 0:
        e := __rt_ws_errno()
        if e == 11:
            return -115                 # connexion non bloquante en cours : EINPROGRESS
        return 0 - e
    return 0

func __rt_ws_accept(h: int, addr: int, lenp: int, flags: int) -> int:
    s := __wincall("ws2_32.dll!accept", h, addr, lenp)
    if s == -1:
        return 0 - __rt_ws_errno()
    __rt_ws_out(addr)
    __rt_ws_add(s, (flags & 2048) != 0)
    if (flags & 2048) != 0:
        __rt_ws_nonblock(s, true)
    return s

func __rt_ws_sendto(h: int, buf: int, len: int, flags: int, addr: int, alen: int) -> int:
    fl := flags & 3                     # MSG_OOB, MSG_PEEK (sans MSG_NOSIGNAL ni MSG_DONTWAIT)
    if len > 1073741824:
        len = 1073741824
    if addr != 0:
        return __rt_ws_ret(__wincall("ws2_32.dll!sendto", h, buf, len, fl, __rt_ws_in(addr, alen), alen))
    return __rt_ws_ret(__wincall("ws2_32.dll!send", h, buf, len, fl))

func __rt_ws_recvfrom(h: int, buf: int, len: int, flags: int, addr: int, lenp: int) -> int:
    fl := flags & 3
    if len > 1073741824:
        len = 1073741824
    if addr != 0:
        r := __rt_ws_ret(__wincall("ws2_32.dll!recvfrom", h, buf, len, fl, addr, lenp))
        __rt_ws_out(addr)
        return r
    return __rt_ws_ret(__wincall("ws2_32.dll!recv", h, buf, len, fl))

func __rt_ws_name(nr: int, h: int, addr: int, lenp: int) -> int:
    r := 0
    if nr == 51:
        r = __wincall("ws2_32.dll!getsockname", h, addr, lenp)
    else:
        r = __wincall("ws2_32.dll!getpeername", h, addr, lenp)
    if __rt_w32(r) != 0:
        return 0 - __rt_ws_errno()
    __rt_ws_out(addr)
    return 0

# Paire de sockets connectés (sv : deux entiers de 32 bits) : TCP sur 127.0.0.1, comme socketpair(AF_UNIX).
func __rt_ws_socketpair(type: int, sv: int) -> int:
    l := __rt_ws_socket(2, 1, 0)
    if l < 0:
        return l
    sa := __alloc_raw(16)
    __zero(sa, 16)
    __store16(sa, 2)
    __store32(sa + 4, 16777343)         # 127.0.0.1
    ln := __alloc_raw(8)
    __store64(ln, 16)
    r := 0
    if __rt_w32(__wincall("ws2_32.dll!bind", l, sa, 16)) != 0 or __rt_w32(__wincall("ws2_32.dll!listen", l, 1)) != 0 or __rt_w32(__wincall("ws2_32.dll!getsockname", l, sa, ln)) != 0:
        r = 0 - __rt_ws_errno()
        __rt_ws_close(l)
        return r
    c := __rt_ws_socket(2, 1, 0)
    if c < 0:
        __rt_ws_close(l)
        return c
    if __rt_w32(__wincall("ws2_32.dll!connect", c, sa, 16)) != 0:
        r = 0 - __rt_ws_errno()
        __rt_ws_close(l)
        __rt_ws_close(c)
        return r
    s := __rt_ws_accept(l, 0, 0, type & 2048)
    __rt_ws_close(l)
    if s < 0:
        __rt_ws_close(c)
        return s
    if (type & 2048) != 0:
        __rt_ws_nonblock(c, true)
    __store32(sv, c)
    __store32(sv + 4, s)
    return 0

# Niveaux et options de Linux -> Windows ; [niveau, option, taille], option -1 : sans effet (SO_REUSEPORT).
func __rt_ws_opt(level: int, opt: int, out: int):
    lv := level
    o := opt
    if level == 1:
        lv = 65535
        if opt == 2:
            o = 4
        elif opt == 6:
            o = 32
        elif opt == 9:
            o = 8
        elif opt == 8:
            o = 4098
        elif opt == 7:
            o = 4097
        elif opt == 4:
            o = 4103
        elif opt == 15:
            o = -1
    elif level == 0:
        if opt == 2:
            o = 4
        elif opt == 33:
            o = 10
        elif opt == 34:
            o = 11
        elif opt == 32:
            o = 9
        elif opt == 35:
            o = 12
        elif opt == 36:
            o = 13
    elif level == 41:
        if opt == 16:
            o = 4
        elif opt == 18:
            o = 10
        elif opt == 19:
            o = 11
        elif opt == 17:
            o = 9
        elif opt == 20:
            o = 12
        elif opt == 21:
            o = 13
        elif opt == 26:
            o = 27
    __store64(out, lv)
    __store64(out + 8, o)

func __rt_ws_setopt(h: int, level: int, opt: int, val: int, len: int) -> int:
    m := __alloc_raw(16)
    __rt_ws_opt(level, opt, m)
    if __load64(m + 8) < 0:
        return 0
    v := val
    n := len
    if len == 1:                        # options d'un octet sous Linux (IP_MULTICAST_TTL / LOOP) : DWORD sous Windows
        v = __alloc_raw(8)
        __store64(v, __load8(val))
        n = 4
    if __rt_w32(__wincall("ws2_32.dll!setsockopt", h, __load64(m), __load64(m + 8), v, n)) != 0:
        return 0 - __rt_ws_errno()
    return 0

func __rt_ws_getopt(h: int, level: int, opt: int, val: int, lenp: int) -> int:
    m := __alloc_raw(16)
    __rt_ws_opt(level, opt, m)
    if __load64(m + 8) < 0:
        __store32(val, 0)
        return 0
    if __rt_w32(__wincall("ws2_32.dll!getsockopt", h, __load64(m), __load64(m + 8), val, lenp)) != 0:
        return 0 - __rt_ws_errno()
    if level == 1 and opt == 4 and __load32(val) != 0:
        __wincall("ws2_32.dll!WSASetLastError", __load32(val))
        __store32(val, __rt_ws_errno())  # SO_ERROR : code Winsock -> errno
    return 0

func __rt_ws_close(h: int) -> int:
    e := __rt_ws_entry(h)
    if e != 0:
        __store64(e, 0)
    return __rt_ws_ret(__wincall("ws2_32.dll!closesocket", h))

# fcntl : F_GETFD / F_SETFD sans effet, F_GETFL (O_RDWR | O_NONBLOCK), F_SETFL (O_NONBLOCK) d'un socket.
func __rt_ws_fcntl(fd: int, cmd: int, arg: int) -> int:
    e := __rt_ws_entry(fd)
    if cmd == 3:
        if e != 0 and __load64(e + 8) != 0:
            return 2050
        return 2
    if cmd == 4:
        if e != 0:
            __rt_ws_nonblock(fd, (arg & 2048) != 0)
        return 0
    return 0

# poll : sockets par WSAPoll (événements traduits) ; un autre descripteur est toujours prêt.
func __rt_ws_poll(fds: int, n: int, ms: int) -> int:
    allsock := true
    i := 0
    while i < n:
        if __rt_ws_entry(__load32(fds + 8 * i)) == 0:
            allsock = false
        i += 1
    if not allsock:
        k := 0
        i = 0
        while i < n:
            __store16(fds + 8 * i + 6, __load16(fds + 8 * i + 4) & 5)
            if (__load16(fds + 8 * i + 4) & 5) != 0:
                k += 1
            i += 1
        return k
    w := __alloc_raw(16 * n + 16)
    i = 0
    while i < n:
        ev := __load16(fds + 8 * i + 4)
        we := 0
        if (ev & 1) != 0:
            we = we | 256               # POLLRDNORM
        if (ev & 2) != 0:
            we = we | 512               # POLLRDBAND
        if (ev & 4) != 0:
            we = we | 16                # POLLWRNORM
        __store64(w + 16 * i, __load32(fds + 8 * i))
        __store16(w + 16 * i + 8, we)
        __store16(w + 16 * i + 10, 0)
        i += 1
    r := __wincall("ws2_32.dll!WSAPoll", w, n, ms)
    if __rt_w32(r) == 4294967295:
        return 0 - __rt_ws_errno()
    i = 0
    while i < n:
        re := __load16(w + 16 * i + 10)
        le := 0
        if (re & 256) != 0:
            le = le | 1
        if (re & 512) != 0:
            le = le | 2
        if (re & 16) != 0:
            le = le | 4
        if (re & 1) != 0:
            le = le | 8
        if (re & 2) != 0:
            le = le | 17                # POLLHUP : la lecture voit aussi la fin du flux
        if (re & 4) != 0:
            le = le | 32
        __store16(fds + 8 * i + 6, le)
        i += 1
    return __rt_w32(r)

# getrandom : RtlGenRandom (advapi32!SystemFunction036).
func __rt_win_random(buf: int, n: int) -> int:
    if (__rt_w32(__wincall("advapi32.dll!SystemFunction036", buf, n)) & 255) == 0:
        return -5
    return n

# FILETIME (centaines de ns depuis 1601) -> secondes depuis 1970.
func __rt_win_unix(ft: int) -> int:
    return (ft - 116444736000000000) // 10000000

# FILETIME -> timespec (secondes, nanosecondes) de struct stat.
func __rt_win_stt(at: int, ft: int):
    t := ft - 116444736000000000
    __store64(at, t // 10000000)
    __store64(at + 8, (t % 10000000) * 100)

# unlink : refuse un dossier (EISDIR, comme Linux) ; un fichier en lecture seule est supprimé (sous Linux,
# seul le dossier parent compte).
func __rt_win_unlink(path: int) -> int:
    w := __rt_win_wide(path)
    at := __rt_w32(__wincall("GetFileAttributesW", w))
    if at != 4294967295:
        if (at & 16) != 0:
            return -21
        if (at & 1) != 0:
            __wincall("SetFileAttributesW", w, (at & 4294967294) | 128)
    return __rt_win_ok(__wincall("DeleteFileW", w))

func __rt_win_mprotect(a: int, n: int, prot: int) -> int:
    np := 1                             # PAGE_NOACCESS
    if (prot & 2) != 0:
        np = 4                          # PAGE_READWRITE
    elif (prot & 1) != 0:
        np = 2                          # PAGE_READONLY
    old := __alloc_raw(8)
    return __rt_win_ok(__wincall("VirtualProtect", a, n, np, old))

func __rt_win_sleep(ts: int) -> int:
    ms := __load64(ts) * 1000 + (__load64(ts + 8) + 999999) // 1000000
    __wincall("Sleep", ms)
    return 0

# clock_gettime : CLOCK_MONOTONIC (1, et 4, 7) par le compteur de performance, sinon l'heure système.
func __rt_win_clock(clk: int, ts: int) -> int:
    if clk == 1 or clk == 4 or clk == 7:
        q := __alloc_raw(16)
        __wincall("QueryPerformanceCounter", q)
        __wincall("QueryPerformanceFrequency", q + 8)
        cnt := __load64(q)
        fr := __load64(q + 8)
        __store64(ts, cnt // fr)
        __store64(ts + 8, (cnt % fr) * 1000000000 // fr)
        return 0
    ft := __alloc_raw(8)
    __wincall("GetSystemTimePreciseAsFileTime", ft)
    t := __load64(ft) - 116444736000000000
    __store64(ts, t // 10000000)
    __store64(ts + 8, (t % 10000000) * 100)
    return 0

func __rt_win_getcwd(buf: int, size: int) -> int:
    n := __rt_w32(__wincall("GetCurrentDirectoryW", 0, 0))
    if n == 0:
        return 0 - __rt_win_errno()
    w := __alloc_raw(2 * n + 2)
    k := __rt_w32(__wincall("GetCurrentDirectoryW", n, w))
    r := __rt_w32(__wincall("WideCharToMultiByte", 65001, 0, w, k + 1, buf, size, 0, 0))
    if r == 0:
        return -34 # ERANGE
    return r

# Copie `s` (64 octets au plus) dans un champ de 65 octets de struct utsname.
func __rt_win_put(dst: int, s: str):
    p := __str_addr(s)
    n := __load64(p)
    if n > 64:
        n = 64
    __copy(dst, p + 8, n)
    __store8(dst + n, 0)

# uname : sysname, nodename, release, version, machine (champs de 65 octets) ; comme os.name(),
# os.hostname() et os.version() de la VM sous Windows.
func __rt_win_uname(buf: int) -> int:
    __zero(buf, 390)
    __rt_win_put(buf, "Windows")
    w := __alloc_raw(520)
    sz := __alloc_raw(8)
    __store64(sz, 256)
    if __rt_w32(__wincall("GetComputerNameExW", 1, w, sz)) != 0: # ComputerNameDnsHostname
        __wincall("WideCharToMultiByte", 65001, 0, w, __rt_w32(__load64(sz)), buf + 65, 64, 0, 0)
    vi := __alloc_raw(288)              # RTL_OSVERSIONINFOW (276 octets)
    __zero(vi, 288)
    __store32(vi, 276)
    if __rt_w32(__wincall("ntdll.dll!RtlGetVersion", vi)) == 0:
        __rt_win_put(buf + 130, __int_to_str(__load32(vi + 4)) + "." + __int_to_str(__load32(vi + 8)) + "." + __int_to_str(__load32(vi + 12)))
    else:
        __rt_win_put(buf + 130, "unknown")
    __rt_win_put(buf + 260, "x86_64")
    return 0

# getppid : InheritedFromUniqueProcessId de PROCESS_BASIC_INFORMATION (48 octets, décalage 40).
func __rt_win_getppid() -> int:
    pbi := __alloc_raw(48)
    __zero(pbi, 48)
    if __rt_w32(__wincall("ntdll.dll!NtQueryInformationProcess", -1, 0, pbi, 48, 0)) != 0:
        return 0
    return __load64(pbi + 40)
