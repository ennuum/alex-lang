# alex: intrinsics
# noyau — interface du noyau d'Alex OS pour les programmes ALEX (cible --alexos) : appel système brut, mémoire
# (mmap, munmap, mprotect, memfd), informations (RAM, cœurs), processus et signaux élémentaires. Les numéros et les
# conventions sont ceux de l'ABI d'Alex OS (docs/APPELS_SYSTEME.md d'Alex OS) : résultat négatif = -code d'erreur.

# Appel système brut (numéro, jusqu'à 5 arguments).
func appel(nr: int, a1: int = 0, a2: int = 0, a3: int = 0, a4: int = 0, a5: int = 0) -> int:
    return __syscall(nr, a1, a2, a3, a4, a5)

const PROT_LECTURE := 1
const PROT_ECRITURE := 2
const PARTAGE := 1
const PRIVE := 2
const ANONYME := 32

# Zone de mémoire de taille octets (adresse, ou -code d'erreur) ; anonyme par défaut (fd ignoré).
func mmap(taille: int, prot: int = 3, drapeaux: int = 34, fd: int = 0) -> int:
    f := fd
    if (drapeaux & ANONYME) != 0:
        f = -1
    return __syscall(9, 0, taille, prot, drapeaux, f, 0)   # décalage 0 (6e argument)

func munmap(adresse: int, taille: int) -> int:
    return __syscall(11, adresse, taille)

func mprotect(adresse: int, taille: int, prot: int) -> int:
    return __syscall(10, adresse, taille, prot)

func lire64(adresse: int) -> int:
    return __load64(adresse)

func ecrire64(adresse: int, valeur: int):
    __store64(adresse, valeur)

func _cstr(s: str) -> int:
    p := __str_addr(s)
    n := __load64(p)
    c := __alloc_raw(n + 1)
    __copy(c, p + 8, n)
    __store8(c + n, 0)
    return c

# Objet de mémoire partagée anonyme (descripteur, ou -code d'erreur).
func memfd(nom: str, drapeaux: int = 0) -> int:
    return __syscall(319, _cstr(nom), drapeaux)

func ftruncate(fd: int, taille: int) -> int:
    return __syscall(77, fd, taille)

# RAM totale annoncée par le noyau (octets).
func ram_totale() -> int:
    b := __alloc_raw(112)
    if __syscall(99, b) != 0:
        return 0
    return __load64(b + 32) * (__load32(b + 104) & 4294967295)

func fork() -> int:
    __flush()
    return __syscall(57)

# Attend l'enfant pid ; renvoie son code de sortie (128 + signal s'il a été tué).
func attendre(pid: int) -> int:
    st := __alloc_raw(8)
    __store64(st, 0)
    __syscall(61, pid, st, 0, 0)
    s := __load32(st) & 65535
    if (s & 127) != 0:
        return 128 + (s & 127)
    return (s >> 8) & 255

func sortir(code: int):
    __flush()
    __syscall(231, code)

func lire8(adresse: int) -> int:
    return __load8(adresse)

func ecrire8(adresse: int, valeur: int):
    __store8(adresse, valeur)

func lire32(adresse: int) -> int:
    return __load32(adresse) & 4294967295

func ecrire32(adresse: int, valeur: int):
    __store32(adresse, valeur)

# Tampon de n octets mis à zéro, hors du tas du programme (pour les appels qui écrivent en mémoire).
func tampon(n: int) -> int:
    return mmap((n + 4095) // 4096 * 4096)

# Lit au plus n octets du descripteur fd dans le tampon (nombre d'octets, ou -code d'erreur).
func lire(fd: int, tampon: int, n: int) -> int:
    return __syscall(0, fd, tampon, n)

# Durée écoulée depuis le démarrage, en millisecondes (horloge monotone).
func millisecondes() -> int:
    ts := __alloc_raw(16)
    __syscall(228, 1, ts)
    return __load64(ts) * 1000 + __load64(ts + 8) // 1000000
