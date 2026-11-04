from collections use contains_key

# ---- Interruptions : vecteur -> gestionnaire Alex (reçoit le code d'erreur du processeur, 0 sinon) ----
_handlers: dict[int, func(int)] := {}

func on_interrupt(vector: int, handler: func(int)):
    _handlers[vector] = handler

# Appelé par l'assembleur pour chaque interruption (interruptions masquées pendant le gestionnaire).
func _dispatch(vector: int, code: int):
    if vector == 253: # noyau parallèle : un autre cœur fait un GC, ce cœur s'arrête (docs NATIVE.md)
        __apic_eoi()
        __gc_park()
        return
    if contains_key(_handlers, vector):
        h := _handlers[vector]
        h(code)
        return
    if vector >= 32 and vector < 48: # ligne du PIC sans gestionnaire : acquittée, ignorée
        eoi(vector - 32)
        return
    __rt_cpu_fault(vector, code)

# PIC 8259 : lignes 0..7 -> vecteurs 32..39, 8..15 -> 40..47 ; toutes masquées.
func pic_init():
    outb(32, 17)
    outb(160, 17)
    outb(33, 32)
    outb(161, 40)
    outb(33, 4)
    outb(161, 2)
    outb(33, 1)
    outb(161, 1)
    outb(33, 255)
    outb(161, 255)

# Contrôleur d'interruptions choisi par le noyau (Alex OS 0.10) : 8259 (défaut) ou IOAPIC. Avec l'IOAPIC, le
# noyau fournit le masquage par ligne (set_irq_controller) et la fin d'interruption passe par l'APIC local.
_irq_ctl: list[func(int, bool)] := []
_apic_eoi_mode := false

func set_irq_controller(f: func(int, bool)):
    _irq_ctl = [f]
    _apic_eoi_mode = true # le contrôleur choisi est l'IOAPIC (toujours avec l'APIC local)

func apic_mode() -> bool:
    return _apic_eoi_mode

# Fin d'interruption de l'APIC local (MSI, IOAPIC, minuterie APIC).
func apic_eoi():
    __apic_eoi()

func irq_enable(irq: int):
    if _apic_eoi_mode:
        f := _irq_ctl[0]
        f(irq, true)
        return
    if irq < 8:
        outb(33, inb(33) & ~(1 << irq))
    else:
        outb(161, inb(161) & ~(1 << (irq - 8)))
        outb(33, inb(33) & ~4)

func irq_disable(irq: int):
    if _apic_eoi_mode:
        f := _irq_ctl[0]
        f(irq, false)
        return
    if irq < 8:
        outb(33, inb(33) | (1 << irq))
    else:
        outb(161, inb(161) | (1 << (irq - 8)))

# Fin d'interruption pour la ligne irq (à appeler dans son gestionnaire).
func eoi(irq: int):
    if _apic_eoi_mode:
        __apic_eoi()
        return
    if irq >= 8:
        outb(160, 32)
    outb(32, 32)

# Minuterie PIT, canal 0 (ligne 0, vecteur 32) : hz interruptions par seconde.
func timer_start(hz: int):
    d := 1193182 // hz
    outb(67, 54)
    outb(64, d & 255)
    outb(64, (d >> 8) & 255)

# Démasque les interruptions et attend la prochaine (sti ; hlt). Le verrou global du noyau est rendu pendant
# l'attente : les autres cœurs peuvent exécuter le noyau.
func wait():
    __park(__rt_cur_entry(), 1)
    __sti()

# Masque les interruptions et renvoie l'état précédent, à rendre à restore (sections critiques imbriquables).
func disable_saved() -> int:
    return __irq_save()

func restore(state: int):
    __irq_restore(state)

func enable():
    __sti()

func disable():
    __cli()

# ---- Mémoire physique : pages de 4 Kio prises dans la zone du tas, mises à zéro ----
func alloc_pages(n: int) -> int:
    a := __mmap(4096 * n)
    if a < 0:
        raise("MemoryError", "alloc_pages(" + str(n) + ") : mémoire physique épuisée")
    return a

func free_pages(addr: int, n: int):
    __munmap(addr, 4096 * n)

# ---- Mode utilisateur (anneau 3) ----
# Gestionnaire des appels système des programmes utilisateur : (numéro, a1..a5) -> résultat (convention Linux).
_syscalls: dict[int, func(int, int, int, int, int, int) -> int] := {}

func on_syscall(handler: func(int, int, int, int, int, int) -> int):
    _syscalls[0] = handler

func _syscall(nr: int, a1: int, a2: int, a3: int, a4: int, a5: int) -> int:
    if contains_key(_syscalls, 0):
        h := _syscalls[0]
        return h(nr, a1, a2, a3, a4, a5)
    return -38

# Lance du code en anneau 3 (rip, rsp) dans l'espace d'adressage de la tâche courante ; renvoie le code passé
# à leave_user. Chaque tâche peut avoir son programme en anneau 3 ; pendant qu'il s'exécute, son cœur ne détient
# pas le verrou global du noyau (les programmes de plusieurs cœurs tournent en parallèle).
func enter_user(rip: int, rsp: int) -> int:
    e := __rt_cur_entry()
    if __load64(e + 64) != 0:
        raise("ProcessError", "enter_user : la tâche exécute déjà un programme en anneau 3")
    _user_fpu(e)
    return __enter_user(rip, rsp, e)

# Zone d'état SSE / x87 du programme de la tâche (sauvée à chaque commutation) : créée au premier passage en
# anneau 3, état initial standard (FCW 0x37F, MXCSR 0x1F80 : exceptions masquées) chargé à chaque lancement.
func _user_fpu(e: int):
    a := __load64(e + 96)
    if a == 0:
        a = __mmap(4096)
        if a < 0:
            raise("MemoryError", "état SSE du programme : mémoire épuisée")
        __zero(a, 4096)
        __store64(e + 96, a)
    __zero(a, 512)
    __store64(a, 895)
    __store64(a + 24, 8064 | (65535 << 32))
    __fxrstor(a)

# Base du segment FS du programme de la tâche courante (TLS des programmes : arch_prctl ARCH_SET_FS) : chargée
# aussitôt, puis à chaque reprise de la tâche.
func set_user_fs(base: int):
    __store64(__rt_cur_entry() + 88, base)
    __wrmsr(3221225728, base)

func user_fs() -> int:
    return __load64(__rt_cur_entry() + 88)

# Sixième argument (r9) de l'appel système en cours (mmap : décalage dans le fichier).
func syscall_arg6() -> int:
    k := __load64(__rt_cur_entry() + 64)
    if k == 0:
        return 0
    return __load64(k - 72)

# Pointeur d'instruction et pile du programme interrompu par une exception ou une interruption venue de
# l'anneau 3 (cadre matériel en haut de la pile noyau de la tâche) ; 0 si la tâche n'exécute pas de programme.
func user_trap_rip() -> int:
    k := __load64(__rt_cur_entry() + 64)
    if k == 0:
        return 0
    return __load64(k - 40)

func user_trap_rsp() -> int:
    k := __load64(__rt_cur_entry() + 64)
    if k == 0:
        return 0
    return __load64(k - 16)

# Modifie le pointeur d'instruction et la pile du programme au retour de l'appel système en cours (signaux).
func set_user_return(rip: int, rsp: int):
    k := __load64(__rt_cur_entry() + 64)
    if k == 0:
        raise("ProcessError", "set_user_return : la tâche n'exécute pas de programme en anneau 3")
    __store64(k - 16, rip)
    __store64(k - 8, rsp)

# Termine le programme utilisateur de la tâche courante (depuis un appel système ou une interruption) :
# son enter_user renvoie code.
func leave_user(code: int):
    e := __rt_cur_entry()
    k := __load64(e + 64)
    if k == 0:
        raise("ProcessError", "leave_user : la tâche n'exécute pas de programme en anneau 3")
    __store64(e + 64, 0)
    __leave_user(code, k)

# Copie dans buf (18 mots : rip, rsp, rflags, rax, rbx, rcx, rdx, rsi, rdi, rbp, r8..r15) les registres du
# programme de la tâche courante tels qu'à son appel système en cours ; rax vaut 0 (résultat vu par un enfant
# de fork), rcx et r11 valent rip et rflags comme après sysret. Seulement pendant un appel système.
func user_frame(buf: int):
    k := __load64(__rt_cur_entry() + 64)
    if k == 0:
        raise("ProcessError", "user_frame : la tâche n'exécute pas de programme en anneau 3")
    __store64(buf, __load64(k - 16))
    __store64(buf + 8, __load64(k - 8))
    __store64(buf + 16, __load64(k - 24))
    __store64(buf + 24, 0)
    __store64(buf + 32, __load64(k - 96))
    __store64(buf + 40, __load64(k - 16))
    __store64(buf + 48, __load64(k - 48))
    __store64(buf + 56, __load64(k - 40))
    __store64(buf + 64, __load64(k - 32))
    __store64(buf + 72, __load64(k - 80))
    __store64(buf + 80, __load64(k - 64))
    __store64(buf + 88, __load64(k - 72))
    __store64(buf + 96, __load64(k - 56))
    __store64(buf + 104, __load64(k - 24))
    __store64(buf + 112, __load64(k - 104))
    __store64(buf + 120, __load64(k - 112))
    __store64(buf + 128, __load64(k - 120))
    __store64(buf + 136, __load64(k - 88))

# Comme enter_user, mais reprend le programme avec tous ses registres (cadre de user_frame) : l'enfant d'un
# fork repart juste après l'instruction syscall. Renvoie le code passé à leave_user.
func enter_user_frame(frame: int) -> int:
    e := __rt_cur_entry()
    if __load64(e + 64) != 0:
        raise("ProcessError", "enter_user_frame : la tâche exécute déjà un programme en anneau 3")
    _user_fpu(e)
    return __enter_user_frame(frame, e)

# Après un MemoryError rattrapé exprès (noyau : un appel système échoue avec ENOMEM au lieu de tout arrêter) :
# le runtime oublie qu'un manque de mémoire est « en cours de signalement » ; sinon le manque suivant, même
# récupérable, arrêterait le programme sans exception (garde contre l'épuisement pendant le message d'erreur).
func oom_recovered():
    __store64(__state() + 2032, 0)

# Signaux (Alex OS) : base des cadres de registres du programme de la tâche courante, c'est-à-dire le sommet de sa
# pile noyau ; appel système : rsp en base - 8, rip en - 16, rflags en - 24, rdi - 32, rsi - 40, rdx - 48, r10 - 56,
# r8 - 64, r9 - 72, rbp - 80, r15 - 88, rbx - 96, r12 - 104, r13 - 112, r14 - 120, xmm0 - 152, xmm1 - 136 ;
# interruption venue de l'anneau 3 : rsp - 16, rflags - 24, rip - 40, rax - 64, rcx - 72, rdx - 80, rsi - 88,
# rdi - 96, r8 - 104, r9 - 112, r10 - 120, r11 - 128, r15 - 144, xmm0 - 184, xmm1 - 168. 0 sans programme.
func user_frame_base() -> int:
    return __load64(__rt_cur_entry() + 64)

# État SSE / x87 du programme (fxsave, 512 octets, adresse alignée sur 16) pendant un appel système ou une
# interruption venue de l'anneau 3 ; xmm0 et xmm1, sauvés par l'entrée du noyau, sont à recopier par l'appelant
# depuis leurs emplacements (voir user_frame_base).
func fpu_save(addr: int):
    __fxsave(addr)

# Comme enter_user_frame, mais l'état SSE / x87 du programme est rechargé depuis fpu (512 octets alignés sur 16,
# MXCSR assaini) au lieu de l'état initial : retour d'un gestionnaire de signal (rt_sigreturn).
func enter_user_frame_fpu(frame: int, fpu: int) -> int:
    e := __rt_cur_entry()
    if __load64(e + 64) != 0:
        raise("ProcessError", "enter_user_frame_fpu : la tâche exécute déjà un programme en anneau 3")
    _user_fpu(e)
    a := __load64(e + 96)
    i := 0
    while i < 512:
        __store64(a + i, __load64(fpu + i))
        i += 8
    m := __load64(a + 24)
    __store64(a + 24, (m & -4294967296) | (m & 65471))   # MXCSR : bits réservés effacés (sinon #GP)
    __fxrstor(a)
    return __enter_user_frame(frame, e)

# ---- Espaces d'adressage ----
# Table de niveau 4 (PML4) du noyau : premier Gio en identité, fenêtre des périphériques.
func kernel_space() -> int:
    return __load64(__smp() + 16)

# Fait de pml4 (adresse physique, 0 : celui du noyau) l'espace d'adressage de la tâche courante : chargé
# aussitôt, puis à chaque reprise de la tâche (sur n'importe quel cœur).
func set_space(pml4: int):
    __store64(__rt_cur_entry() + 72, pml4)
    if pml4 == 0:
        pml4 = kernel_space()
    if __cr3() != pml4:
        __set_cr3(pml4)

# ---- Périphériques au-delà du premier Gio (APIC, PCI) : fenêtre sans cache, adresse physique < 4 Gio ----
func mmio(phys: int) -> int:
    return 549755813888 + phys

func rdmsr(msr: int) -> int:
    return __rdmsr(msr)

func wrmsr(msr: int, value: int):
    __wrmsr(msr, value)

# ---- Opérations atomiques (mémoire partagée entre cœurs) ----
# Si le mot en addr vaut expected, y écrit new ; renvoie l'ancienne valeur (égale à expected : réussi).
func cas(addr: int, expected: int, new: int) -> int:
    return __cas(addr, expected, new)

# Ajoute v au mot en addr ; renvoie l'ancienne valeur.
func atomic_add(addr: int, v: int) -> int:
    return __xadd(addr, v)

# Verrou tournant sur le mot en addr (0 libre) : à réserver aux données partagées hors du noyau Alex (le code
# du noyau est déjà sérialisé par le verrou global) ; spin_lock attend en rendant le verrou global.
func spin_lock(addr: int):
    me := cpu_id() + 1
    while __cas(addr, 0, me) != 0:
        __rt_gc_checkpoint()
        __rt_relax()
        __pause()

# Attente active polie : laisse le verrou global à un cœur qui l'attend, point d'arrêt pour le GC.
func relax():
    __rt_gc_checkpoint()
    __rt_relax()
    __pause()

# TLB shootdown (vecteur 251, servi sans code Alex) : adresse du compteur d'accusés ; registre EOI de l'APIC local
# (adresse virtuelle, 0 : x2APIC) que le gestionnaire écrit.
func shootdown_counter() -> int:
    return __state() + 1760

func set_shootdown_eoi(addr: int):
    __store64(__state() + 1768, addr)

func spin_unlock(addr: int):
    __store64(addr, 0)

# ---- Multiprocesseur ----
# Numéro du cœur courant (0 : celui du démarrage) et nombre de cœurs en service.
func cpu_id() -> int:
    return __load64(__cpu_local() + 8)

func cpus() -> int:
    return __load64(__smp() + 8)

# Vrai si l'interruption ou l'exception en cours de traitement a interrompu l'anneau 3 (programme utilisateur).
func from_user() -> bool:
    return __load64(__cpu_local() + 184) != 0

# Bloc du cœur courant (192 octets ; identifiant APIC en 48, réservé au noyau).
func cpu_block() -> int:
    return __cpu_local()

# Prépare le démarrage du cœur numéro index (1..15) : bloc, pile de démarrage et tâche inactive exécutant
# idle (sur ce cœur seulement), et page de démarrage en 0x8000 ; renvoie le bloc. Il reste à envoyer au cœur
# INIT puis deux SIPI de vecteur 8 (APIC) et à attendre cpu_online(bloc).
func smp_prepare(index: int, idle: func()) -> int:
    if index < 1 or index >= 16:
        raise("ValueError", "smp_prepare : numéro de cœur hors de 1..15")
    b := alloc_pages(1)
    __store64(b, b)
    __store64(b + 8, index)
    __store64(__state() + 1792 + 8 * index, b) # registre des blocs (GC du noyau parallèle)
    __store64(b + 40, __load64(__smp() + 24) + 112 * index)
    __store64(b + 80, 40 + 16 * index)
    __store64(b + 88, alloc_pages(4) + 16384)
    i := __rt_fiber_new(__addr(idle), 5)
    e := __load64(__state() + 960) + 128 * i
    __store64(e + 80, index)
    __store64(b + 16, i)
    __store64(b + 56, i)
    __store64(b + 64, __load64(e))
    page := 32768
    tr := __ap_trampoline()
    __copy(page, tr + 8, __load64(tr))
    __store64(page + 304, kernel_space())
    __store64(page + 312, __ap_entry())
    __store64(page + 320, b)
    return b

# Noyau parallèle (docs Alex OS NOYAU_PARALLELE.md) : vrai = le verrou global du noyau n'est plus pris, le code
# ALEX s'exécute sur plusieurs cœurs à la fois. Le runtime se protège alors lui-même (verrous de l'allocateur,
# des tâches, de la sortie ; GC avec arrêt des autres cœurs par IPI, vecteur 253). Les données du programme
# partagées entre cœurs doivent être protégées par le programme (spin_lock...).
func smp_parallel(on: bool):
    if on:
        __store64(__state() + 2000, 1)
        __store64(__state() + 2016, 1)
    else:
        __store64(__state() + 2016, 0)
        __store64(__state() + 2000, 0)

# Noyau parallèle par étapes (Alex OS, P2) : le runtime se protège (verrous, GC par IPI) mais le verrou global
# du noyau existe toujours ; l'entrée des appels système ne le prend plus : le noyau le prend lui-même
# (bkl_take) sauf sur les chemins qu'il a rendus sûrs entre cœurs.
func runtime_locks(on: bool):
    if on:
        __store64(__state() + 2000, 1)
    else:
        __store64(__state() + 2000, 0)

# Verrou global du noyau pour ce cœur : le prendre (attente active, point d'arrêt pour le GC), le rendre, savoir
# s'il est détenu. Sans effet sous Linux.
# Interruption « libérée » (vecteurs 0..63) : en mode runtime_locks, son entrée ne prend plus le verrou global ;
# le gestionnaire doit être sûr entre cœurs et prendre le verrou (bkl_take) avant tout chemin qui ne l'est pas.
func interrupt_free(vector: int, on: bool):
    if vector < 0 or vector >= 64:
        raise("ValueError", "interrupt_free : vecteur hors de 0..63")
    a := __state() + 2024
    if on:
        __store64(a, __load64(a) | (1 << vector))
    else:
        __store64(a, __load64(a) & ~(1 << vector))

func bkl_take():
    __bkl_take()

func bkl_drop():
    __bkl_drop()

func bkl_held() -> bool:
    return __bkl_held()

func parallel() -> bool:
    return __load64(__state() + 2000) != 0

# Point d'arrêt pour le GC (noyau parallèle) : à appeler dans toute attente active faite interruptions masquées
# (scrutation d'un périphérique...), sinon un GC demandé par un autre cœur attendrait la fin de la boucle.
func safepoint():
    __rt_gc_checkpoint()

# Mode « stress » du ramasse-miettes (mode --debug du noyau) : un GC tous les 4 Kio alloués, pour faire
# apparaître tôt une référence non suivie par le GC. Faux : seuil normal (à partir du GC suivant).
func gc_stress(on: bool):
    if on:
        __store64(__state() + 2040, 1)
        __store64(__state() + 264, 4096)
    else:
        __store64(__state() + 2040, 0)
        __store64(__state() + 264, 16777216)

# Nombre de ramasse-miettes effectués depuis le démarrage.
func gc_count() -> int:
    return __load64(__state() + 488)

func cpu_online(block: int) -> bool:
    return __load64(block + 72) != 0

# Recharge cr3 : vide le TLB après une modification des tables de pages.
func flush_tlb():
    asm("0f 20 d8 0f 22 d8")

# Écrit s sur le port série sans saut de ligne (après la sortie tamponnée de print).
func console_write(s: str):
    __flush()
    __write_err(s)

# ---- SMAP (Alex OS 0.7, tâche 7.5) ----
# Une fois CR4.SMAP activé par le noyau (set_smap), le processeur interdit au noyau tout accès aux pages
# utilisateur, sauf drapeau AC posé (stac). Les accès explicites de ce module (peek, poke, copy, zero, string_at,
# store_string) sont les SEULS chemins voulus vers la mémoire d'un programme (équivalents de copy_from_user /
# copy_to_user, précédés de la validation de l'adresse par le noyau) : ils ouvrent une fenêtre stac / clac
# quand la plage touche la zone utilisateur [1 Gio, 512 Gio). Tout autre accès du noyau à une page utilisateur
# (pointeur corrompu, objet Alex mal placé) déclenche une faute de page.
_smap := false

func set_smap(on: bool):
    _smap = on

func smap() -> bool:
    return _smap

func _user(addr: int, n: int) -> bool:
    return addr < 549755813888 and addr + n > 1073741824

# ---- Tampons en mémoire physique (pilotes) ----
func copy(dst: int, src: int, n: int):
    if _smap and (_user(dst, n) or _user(src, n)):
        asm("0f 01 cb")
        __copy(dst, src, n)
        asm("0f 01 ca")
        return
    __copy(dst, src, n)

func zero(addr: int, n: int):
    if _smap and _user(addr, n):
        asm("0f 01 cb")
        __zero(addr, n)
        asm("0f 01 ca")
        return
    __zero(addr, n)

# Chaîne formée des n octets en addr (UTF-8 supposé).
func string_at(addr: int, n: int) -> str:
    r := __rt_str_new(n)
    copy(r + 8, addr, n)
    return __as_str(r)

# Copie les octets UTF-8 de s en addr ; renvoie leur nombre.
func store_string(s: str, addr: int) -> int:
    p := __str_addr(s)
    n := __load64(p)
    copy(addr, p + 8, n)
    return n

# Adresse des octets de s (valide tant que s est vivante).
func byte_addr(s: str) -> int:
    return __str_addr(s) + 8

# Taille de s en octets (UTF-8).
func byte_size(s: str) -> int:
    return __load64(__str_addr(s))

func cr2() -> int:
    return __cr2()

func cr3() -> int:
    return __cr3()

func invlpg(addr: int):
    __invlpg(addr)

# Image du noyau (multiboot) : [image_start(), image_end()) contient l'en-tête, le code et les données en lecture
# seule (chaînes) ; rien n'y est écrit après le démarrage. Le bss (variables, état du runtime) commence à
# image_end(). W^X du noyau (Alex OS 0.7).
func image_start() -> int:
    return 1048576

func image_end() -> int:
    return __state() - 64

# Début des données en lecture seule de l'image (chaînes...) : [image_start(), image_rodata()) est le code.
func image_rodata() -> int:
    return __load64(1048608)

# Rend la page (4 Kio) de l'identité du noyau contenant addr absente (present faux) ou de nouveau présente :
# pages de garde (piles des tâches, page 0). Premier Gio seulement ; sans effet sous UEFI.
func guard_page(addr: int, present: bool):
    p := 0
    if present:
        p = 1
    __rt_guard(addr, p)

func outb(port: int, value: int):
    __outb(port, value)

func outw(port: int, value: int):
    __outw(port, value)

func outl(port: int, value: int):
    __outl(port, value)

func inb(port: int) -> int:
    return __inb(port)

func inw(port: int) -> int:
    return __inw(port)

func inl(port: int) -> int:
    return __inl(port)

func peek8(addr: int) -> int:
    if _smap and _user(addr, 8):
        asm("0f 01 cb")
        v := __load8(addr)
        asm("0f 01 ca")
        return v
    return __load8(addr)

func peek16(addr: int) -> int:
    if _smap and _user(addr, 8):
        asm("0f 01 cb")
        v := __load16(addr)
        asm("0f 01 ca")
        return v
    return __load16(addr)

func peek32(addr: int) -> int:
    if _smap and _user(addr, 8):
        asm("0f 01 cb")
        v := __load32(addr)
        asm("0f 01 ca")
        return v
    return __load32(addr)

func peek64(addr: int) -> int:
    if _smap and _user(addr, 8):
        asm("0f 01 cb")
        v := __load64(addr)
        asm("0f 01 ca")
        return v
    return __load64(addr)

func poke8(addr: int, value: int):
    if _smap and _user(addr, 8):
        asm("0f 01 cb")
        __store8(addr, value)
        asm("0f 01 ca")
        return
    __store8(addr, value)

func poke16(addr: int, value: int):
    if _smap and _user(addr, 8):
        asm("0f 01 cb")
        __store16(addr, value)
        asm("0f 01 ca")
        return
    __store16(addr, value)

func poke32(addr: int, value: int):
    if _smap and _user(addr, 8):
        asm("0f 01 cb")
        __store32(addr, value)
        asm("0f 01 ca")
        return
    __store32(addr, value)

func poke64(addr: int, value: int):
    if _smap and _user(addr, 8):
        asm("0f 01 cb")
        __store64(addr, value)
        asm("0f 01 ca")
        return
    __store64(addr, value)

func hlt():
    __hlt()

func cli():
    __cli()

func sti():
    __sti()

func pause():
    __pause()

# Fin de la mémoire physique utilisable (octets).
func memory_end() -> int:
    return __load64(__state() + 888)

# Mémoire physique jamais encore distribuée par l'allocateur du runtime (octets) : au-delà du point d'allocation
# courant (les zones rendues et réutilisables n'y sont pas comptées : estimation prudente).
func memory_left() -> int:
    return __load64(__state() + 888) - __load64(__state() + 880)

# Mémoire rendue à l'allocateur du runtime et réutilisable (liste des zones libres), en octets.
func memory_reusable() -> int:
    return __rt_kfree_total()

# Libérations de zones refusées par l'allocateur (double libération, zone hors de la mémoire distribuée).
func memory_bad_frees() -> int:
    return __rt_kfree_rejects()

# UEFI (alexc build --native --uefi) : appelle un service du micrologiciel (pointeur de fonction lu dans une table
# UEFI) avec la convention d'appel Microsoft x64 ; renvoie le EFI_STATUS (ou la valeur) laissé dans rax.
func efi_call(fn: int, a1: int = 0, a2: int = 0, a3: int = 0, a4: int = 0, a5: int = 0, a6: int = 0, a7: int = 0, a8: int = 0, a9: int = 0, a10: int = 0, a11: int = 0, a12: int = 0) -> int:
    return __mscall(fn, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)

# UEFI : vrai si le programme est une application UEFI.
func uefi() -> bool:
    return __uefi()

# UEFI : poignée de l'image (EFI_HANDLE) et adresse de la table système (EFI_SYSTEM_TABLE) reçues à l'entrée.
func efi_image() -> int:
    return __load64(__state() + 1920)

func efi_system_table() -> int:
    return __load64(__state() + 1928)

# Sans OS (image multiboot) : adresse physique de la structure d'information Multiboot reçue du chargeur
# (GRUB, AlexBoot, qemu -kernel), 0 si aucune.
func multiboot_info() -> int:
    return __load64(__state() + 1960)

# Termine : sous QEMU avec `-device isa-debug-exit,iobase=0xf4,iosize=0x04`, code de sortie 2 * code + 1 ;
# sinon le processeur s'arrête.
func exit(code: int):
    __flush()
    __exit(code)

# asm("fa f4") : octets machine insérés tels quels à l'endroit de l'appel (développé en ligne). Le code peut
# utiliser rax, rcx, rdx, rsi, rdi, r8 à r11 et doit préserver les autres registres et la pile.
func asm(code: str):
    return

# asm_value("0f 31 48 c1 e2 20 48 09 d0") : comme asm, puis renvoie la valeur laissée dans rax.
func asm_value(code: str) -> int:
    return 0
