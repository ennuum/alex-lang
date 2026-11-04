# Processus utilisateur : exécute en anneau 3 des exécutables produits par `alexc build --native` (ELF Linux
# x86-64), chargés depuis le disque FAT. Le noyau fournit les appels système Linux qu'utilise le runtime Alex
# (write, read, mmap, munmap, exit, open, close, stat, unlink, getpid, getcwd, chdir, mkdir, rmdir, uname...) :
# le même exécutable tourne sous Linux et sous Alex OS. Chemins relatifs au répertoire courant du processus.
#
# Plusieurs processus à la fois, isolés : chacun a son espace d'adressage (sa table PML4 ; le premier Gio du
# noyau y est partagé en mode superviseur, inaccessible à l'anneau 3) et sa tâche du noyau, ordonnancée comme
# les autres (préemption par la minuterie ; sur plusieurs cœurs, les processus tournent en parallèle). Mémoire
# au-delà de 1 Gio en pages de 4 Kio, allouées au premier accès (défaut de page).
use hw
use tasks
use fat
from collections use append, contains_key, remove, keys
from core use len
from string use split, join, starts_with

const PAGE := 4096
const ADDR_MASK := 4503599627366400 # bits 12..51 d'une entrée de table de pages
const MMAP_BASE := 137438953472     # 128 Gio : zones de mmap
const STACK_TOP := 274877906944     # 256 Gio : pile initiale (arguments)

class Region:
    start: int := 0
    end: int := 0
    func init(start: int, end: int):
        self.start = start
        self.end = end

class OpenFile:
    name: str := ""
    data: str := ""
    pos: int := 0
    writable: bool := false
    func init(name: str, data: str, writable: bool):
        self.name = name
        self.data = data
        self.writable = writable

class Process:
    pid: int := 0
    name: str := ""
    cwd: str := "" # répertoire courant (chemin normalisé, sans « / » initial ; "" : la racine)
    pml4: int := 0 # espace d'adressage (adresse physique de sa table de niveau 4)
    task: int := 0 # tâche du noyau qui l'exécute
    regions: list[Region] := []
    files: dict[int, OpenFile] := {}
    next_fd: int := 3
    mmap_next: int := MMAP_BASE
    pending: str := "" # entrée clavier non encore lue par le programme
    out: list[func(str)] := []
    read_line: list[func() -> str] := []
    entry: int := 0
    sp: int := 0
    code: int := -1
    done: bool := false
    cpus: dict[int, bool] := {} # cœurs sur lesquels il a fait des appels système

    func init(pid: int, name: str):
        self.pid = pid
        self.name = name
        self.regions = []
        self.files = {}
        self.cpus = {}

procs: dict[int, Process] := {} # par tâche du noyau
free_frames := 0 # pages physiques libérées (liste chaînée dans les pages elles-mêmes)
pid := 0 # dernier numéro de processus attribué
installed := false

# ---- pages physiques et tables de pages ----
func frame() -> int:
    if free_frames != 0:
        f := free_frames
        free_frames = hw.peek64(f)
        hw.zero(f, PAGE)
        return f
    return hw.alloc_pages(1)

func release(f: int):
    hw.poke64(f, free_frames)
    free_frames = f

# Nouvel espace d'adressage : PML4[0] -> PDPT propre dont l'entrée 0 est le premier Gio du noyau (pages de
# 2 Mio sans le bit utilisateur), PML4[1] = fenêtre des périphériques du noyau ; le reste est au processus.
func _new_space() -> int:
    kernel := hw.kernel_space()
    pml4 := frame()
    pdpt := frame()
    hw.poke64(pdpt, hw.peek64(hw.peek64(kernel) & ADDR_MASK))
    hw.poke64(pml4, pdpt | 7)
    hw.poke64(pml4 + 8, hw.peek64(kernel + 8))
    return pml4

func _pdpt(p: Process) -> int:
    return hw.peek64(p.pml4) & ADDR_MASK

func _table(table: int, i: int) -> int:
    e := hw.peek64(table + 8 * i)
    if (e & 1) == 0:
        t := frame()
        hw.poke64(table + 8 * i, t | 7) # présent, écriture, utilisateur
        return t
    return e & ADDR_MASK

func map(p: Process, v: int, phys: int):
    pd := _table(_pdpt(p), (v >> 30) & 511)
    pt := _table(pd, (v >> 21) & 511)
    hw.poke64(pt + 8 * ((v >> 12) & 511), phys | 7)

# Libère toutes les pages et tables du processus (au-delà du premier Gio), puis son espace d'adressage.
func _free_space(p: Process):
    pdpt := _pdpt(p)
    i := 1
    while i < 512:
        e := hw.peek64(pdpt + 8 * i)
        if (e & 1) != 0:
            pd := e & ADDR_MASK
            j := 0
            while j < 512:
                d := hw.peek64(pd + 8 * j)
                if (d & 1) != 0:
                    pt := d & ADDR_MASK
                    k := 0
                    while k < 512:
                        q := hw.peek64(pt + 8 * k)
                        if (q & 1) != 0:
                            release(q & ADDR_MASK)
                        k += 1
                    release(pt)
                j += 1
            release(pd)
        i += 1
    release(pdpt)
    release(p.pml4)
    p.pml4 = 0

func _unmap_range(p: Process, start: int, end: int):
    pdpt := _pdpt(p)
    v := start
    while v < end:
        e := hw.peek64(pdpt + 8 * ((v >> 30) & 511))
        if (e & 1) != 0:
            d := hw.peek64((e & ADDR_MASK) + 8 * ((v >> 21) & 511))
            if (d & 1) != 0:
                slot := (d & ADDR_MASK) + 8 * ((v >> 12) & 511)
                q := hw.peek64(slot)
                if (q & 1) != 0:
                    release(q & ADDR_MASK)
                    hw.poke64(slot, 0)
        v += PAGE
    hw.flush_tlb()

# Processus de la tâche courante (appels système, défauts de page).
func current() -> Process?:
    t := tasks.current()
    if contains_key(procs, t):
        return procs[t]
    return null

# ---- défauts de page : allocation à la demande, sinon arrêt du programme ----
func _page_fault(code: int):
    addr := hw.cr2()
    p := current()
    if p == null:
        raise("CPUError", "défaut de page du noyau (adresse " + str(addr) + ", code " + str(code) + ")")
    if (code & 1) == 0: # page absente d'une zone du programme (accès du programme ou du noyau pour lui)
        for r in p.regions:
            if addr >= r.start and addr < r.end:
                map(p, addr & ~4095, frame())
                return
    if (code & 4) == 0:
        raise("CPUError", "défaut de page du noyau (adresse " + str(addr) + ", code " + str(code) + ")")
    _out(p, f"Erreur de segmentation (adresse {addr})\n")
    hw.leave_user(139)

# Exceptions du processeur venues de l'anneau 3 : seul le programme fautif s'arrête (codes de Linux :
# 136 SIGFPE, 132 SIGILL, 139 SIGSEGV) ; venues du noyau, ce sont des erreurs du noyau.
func _user_fault(what: str, vector: int, code: int, exit_code: int):
    p := current()
    if not hw.from_user():
        raise("CPUError", f"exception {vector} du processeur dans le noyau (code {code})")
    if p == null:
        raise("CPUError", f"exception {vector} du processeur hors d'un processus (code {code})")
    _out(p, what + "\n")
    hw.leave_user(exit_code)

func _divide(code: int):
    _user_fault("Erreur de division", 0, code, 136)

func _invalid(code: int):
    _user_fault("Instruction invalide", 6, code, 132)

func _protection(code: int):
    _user_fault("Erreur de protection générale", 13, code, 139)

func _out(p: Process, s: str):
    h := p.out[0]
    h(s)

# ---- appels système (numéros Linux x86-64) ----
func _cstr(addr: int) -> str:
    n := 0
    while hw.peek8(addr + n) != 0:
        n += 1
    return hw.string_at(addr, n)

# Chemin normalisé (« a/b/c », sans « / » initial, « . » et « .. » résolus) de path, relatif à cwd.
func normalize(cwd: str, path: str) -> str:
    comps: list[str] := []
    if not starts_with(path, "/"):
        for c in split(cwd, "/"):
            if c != "":
                append(comps, c)
    for c in split(path, "/"):
        if c == "" or c == ".":
            continue
        if c == "..":
            if len(comps) > 0:
                comps = [comps[i] for i in 0..len(comps) - 1]
            continue
        append(comps, c)
    return join("/", comps)

# Répertoire parent d'un chemin normalisé.
func dirname(path: str) -> str:
    comps := split(path, "/")
    return join("/", [comps[i] for i in 0..len(comps) - 1])

func _path(p: Process, addr: int) -> str:
    return normalize(p.cwd, _cstr(addr))

func _read(p: Process, fd: int, buf: int, n: int) -> int:
    if fd == 0:
        if hw.byte_size(p.pending) == 0:
            h := p.read_line[0]
            p.pending = h() + "\n"
        size := hw.byte_size(p.pending)
        k := n
        if k > size:
            k = size
        hw.copy(buf, hw.byte_addr(p.pending), k)
        p.pending = hw.string_at(hw.byte_addr(p.pending) + k, size - k)
        return k
    if not contains_key(p.files, fd):
        return -9 # EBADF
    f := p.files[fd]
    size := hw.byte_size(f.data)
    k := size - f.pos
    if k > n:
        k = n
    if k < 0:
        k = 0
    hw.copy(buf, hw.byte_addr(f.data) + f.pos, k)
    f.pos += k
    return k

func _write(p: Process, fd: int, buf: int, n: int) -> int:
    s := hw.string_at(buf, n)
    if fd == 1 or fd == 2:
        _out(p, s)
        return n
    if not contains_key(p.files, fd) or not p.files[fd].writable:
        return -9
    f := p.files[fd]
    f.data = f.data + s
    return n

func _open(p: Process, addr: int, flags: int) -> int:
    name := _path(p, addr)
    writable := (flags & 3) != 0
    data := ""
    e := fat.find(name)
    if e == null:
        if (flags & 64) == 0:
            return -2 # ENOENT
        if not fat.is_dir(dirname(name)):
            return -2 # répertoire parent absent
    else:
        if e.is_dir:
            return -21 # EISDIR
        if (flags & 512) == 0:
            data = fat.read(name)
    fd := p.next_fd
    p.next_fd += 1
    p.files[fd] = OpenFile(name, data, writable)
    return fd

func _close(p: Process, fd: int) -> int:
    if not contains_key(p.files, fd):
        return -9
    f := p.files[fd]
    remove(p.files, fd)
    if f.writable:
        try:
            fat.write(f.name, f.data)
        catch e:
            return -28 # ENOSPC (disque ou répertoire racine plein)
    return 0

func _stat(p: Process, addr: int, buf: int) -> int:
    e := fat.find(_path(p, addr))
    if e == null:
        return -2
    hw.zero(buf, 144)
    if e.is_dir:
        hw.poke32(buf + 24, 16877) # répertoire, rwxr-xr-x
    else:
        hw.poke32(buf + 24, 33188) # fichier ordinaire, rw-r--r--
        hw.poke64(buf + 48, e.size)
    return 0

func _unlink(p: Process, addr: int) -> int:
    name := _path(p, addr)
    e := fat.find(name)
    if e == null:
        return -2
    if e.is_dir:
        return -21 # EISDIR
    fat.remove(name)
    return 0

func _mkdir(p: Process, addr: int) -> int:
    name := _path(p, addr)
    if name == "" or fat.find(name) != null:
        return -17 # EEXIST
    if not fat.is_dir(dirname(name)):
        return -2
    try:
        fat.mkdir(name)
    catch e:
        return -28
    return 0

func _rmdir(p: Process, addr: int) -> int:
    name := _path(p, addr)
    e := fat.find(name)
    if e == null:
        return -2
    if not e.is_dir:
        return -20 # ENOTDIR
    if name == "":
        return -16 # EBUSY : la racine
    if len(fat.list(name)) > 0:
        return -39 # ENOTEMPTY
    fat.rmdir(name)
    return 0

func _getcwd(p: Process, buf: int, size: int) -> int:
    s := "/" + p.cwd
    n := hw.byte_size(s)
    if n + 1 > size:
        return -34 # ERANGE
    _put_cstr(buf, s)
    return n + 1

func _chdir(p: Process, addr: int) -> int:
    name := _path(p, addr)
    e := fat.find(name)
    if e == null:
        return -2
    if not e.is_dir:
        return -20
    p.cwd = name
    return 0

func _put_cstr(addr: int, s: str):
    n := hw.store_string(s, addr)
    hw.poke8(addr + n, 0)

func _mmap(p: Process, size: int) -> int:
    start := p.mmap_next
    size = (size + 4095) & ~4095
    p.mmap_next += size + PAGE # page de garde entre deux zones
    append(p.regions, Region(start, start + size))
    return start

func _munmap(p: Process, addr: int, size: int) -> int:
    _unmap_range(p, addr, addr + ((size + 4095) & ~4095))
    kept: list[Region] := []
    for r in p.regions:
        if r.start != addr:
            append(kept, r)
    p.regions = kept
    return 0

func syscall(nr: int, a1: int, a2: int, a3: int, a4: int, a5: int) -> int:
    hw.enable() # interruptions autorisées pendant l'appel système (clavier, minuterie)
    p := current()
    if p == null:
        return -38
    p.cpus[hw.cpu_id()] = true
    if nr == 0:
        return _read(p, a1, a2, a3)
    if nr == 1:
        return _write(p, a1, a2, a3)
    if nr == 2:
        return _open(p, a1, a2)
    if nr == 3:
        return _close(p, a1)
    if nr == 4:
        return _stat(p, a1, a2)
    if nr == 9:
        if a5 != -1:
            return -19 # ENODEV : seulement des zones anonymes
        return _mmap(p, a2)
    if nr == 10:
        return 0 # mprotect : accepté (pas de pages de garde)
    if nr == 11:
        return _munmap(p, a1, a2)
    if nr == 24:
        tasks.yield_now() # sched_yield
        return 0
    if nr == 39:
        return p.pid
    if nr == 110:
        return 1
    if nr == 60 or nr == 231:
        hw.leave_user(a1 & 255)
    if nr == 63:
        hw.zero(a1, 390)
        _put_cstr(a1, "AlexOS")
        _put_cstr(a1 + 65, "alex")
        _put_cstr(a1 + 130, "0.7")
        _put_cstr(a1 + 195, "E7")
        _put_cstr(a1 + 260, "x86_64")
        return 0
    if nr == 79:
        return _getcwd(p, a1, a2)
    if nr == 80:
        return _chdir(p, a1)
    if nr == 83:
        return _mkdir(p, a1)
    if nr == 84:
        return _rmdir(p, a1)
    if nr == 87:
        return _unlink(p, a1)
    return -38 # ENOSYS

# ---- chargement et exécution ----
func _u16(q: int) -> int:
    return hw.peek16(q)

func _install():
    if not installed:
        hw.on_interrupt(14, _page_fault)
        hw.on_interrupt(0, _divide)
        hw.on_interrupt(6, _invalid)
        hw.on_interrupt(13, _protection)
        hw.on_syscall(syscall)
        installed = true

# Charge l'exécutable ELF image (nommé name) dans un nouvel espace d'adressage, avec sa pile initiale.
func _load(name: str, image: str, args: list[str]) -> Process:
    size := hw.byte_size(image)
    base := hw.byte_addr(image)
    if size < 64 or hw.peek32(base) != 1179403647: # \x7fELF
        raise("ProcessError", name + " : pas un exécutable ELF")
    if hw.peek8(base + 4) != 2 or _u16(base + 18) != 62:
        raise("ProcessError", name + " : ELF 64 bits x86-64 attendu")
    phoff := hw.peek64(base + 32)
    phnum := _u16(base + 56)
    pid += 1
    p := Process(pid, name)
    p.pml4 = _new_space()
    p.entry = hw.peek64(base + 24)
    i := 0
    while i < phnum:
        ph := base + phoff + 56 * i
        if hw.peek32(ph) == 1: # PT_LOAD
            off := hw.peek64(ph + 8)
            vaddr := hw.peek64(ph + 16)
            filesz := hw.peek64(ph + 32)
            memsz := hw.peek64(ph + 40)
            v := vaddr & ~4095
            while v < vaddr + filesz:
                f := frame()
                lo := v
                if lo < vaddr:
                    lo = vaddr
                hi := v + PAGE
                if hi > vaddr + filesz:
                    hi = vaddr + filesz
                hw.copy(f + (lo - v), base + off + (lo - vaddr), hi - lo)
                map(p, v, f)
                v += PAGE
            if memsz > filesz:
                append(p.regions, Region(v, (vaddr + memsz + 4095) & ~4095))
        i += 1
    # Pile initiale : argc, argv[], NULL, envp NULL, puis les chaînes (écrites dans la page physique).
    append(p.regions, Region(STACK_TOP - 1048576, STACK_TOP))
    top := frame()
    map(p, STACK_TOP - PAGE, top)
    all: list[str] := [name]
    for a in args:
        append(all, a)
    strp := PAGE
    ptrs: list[int] := []
    for s in all:
        strp -= hw.byte_size(s) + 1
        _put_cstr(top + strp, s)
        append(ptrs, STACK_TOP - PAGE + strp)
    sp := (strp - 8 * (len(all) + 3)) & ~15
    hw.poke64(top + sp, len(all))
    k := 0
    for q in ptrs:
        hw.poke64(top + sp + 8 + 8 * k, q)
        k += 1
    p.sp = STACK_TOP - PAGE + sp
    return p

# Corps de la tâche d'un processus : son espace d'adressage, l'anneau 3, puis la libération de tout.
func _run(p: Process):
    hw.set_space(p.pml4)
    code := hw.enter_user(p.entry, p.sp)
    for fd in [f for f in p.files]:
        _close(p, fd)
    hw.set_space(0)
    _free_space(p)
    p.code = code
    p.done = true
    remove(procs, p.task)

func _start(p: Process, out: func(str), read_line: func() -> str, cwd: str) -> Process:
    _install()
    p.cwd = normalize("", cwd)
    p.out = [out]
    p.read_line = [read_line]
    # Créée et enregistrée interruptions masquées : sinon la minuterie peut lancer la tâche (et le programme,
    # puis son premier défaut de page) avant que procs ne la connaisse. Les autres cœurs ne peuvent pas la
    # prendre avant : ce code détient le verrou global du noyau.
    f := hw.disable_saved()
    p.task = tasks.spawn(() => _run(p))
    procs[p.task] = p
    hw.restore(f)
    return p

# Lance le programme `name` du disque avec les arguments args, dans un nouveau processus ; il démarre au
# prochain passage de l'ordonnanceur. out reçoit ses sorties, read_line fournit son entrée ; cwd : son
# répertoire courant (racine par défaut).
func spawn(name: str, args: list[str], out: func(str), read_line: func() -> str, cwd: str = "") -> Process:
    return _start(_load(name, fat.read(name), args), out, read_line, cwd)

# Même chose pour un exécutable déjà en mémoire.
func spawn_image(name: str, image: str, args: list[str], out: func(str), read_line: func() -> str,
                cwd: str = "") -> Process:
    return _start(_load(name, image, args), out, read_line, cwd)

# Attend la fin du processus (en laissant la main aux autres tâches, puis en dormant jusqu'à la prochaine
# interruption, verrou global rendu) ; renvoie son code de sortie.
func wait(p: Process) -> int:
    while not p.done:
        tasks.yield_now()
        if not p.done and hw.cpus() > 1:
            hw.wait()
    return p.code

# Exécute le programme `name` du disque jusqu'à sa fin ; renvoie son code de sortie.
func run(name: str, args: list[str], out: func(str), read_line: func() -> str, cwd: str = "") -> int:
    return wait(spawn(name, args, out, read_line, cwd))

# Processus en cours.
func running() -> list[Process]:
    return [procs[t] for t in procs]
