

# ---- Mémoire : allocateur à classes de taille et ramasse-miettes mark-sweep conservatif ----------
#
# Tas : blocs de 32 Mio alignés sur 32 Mio, découpés en pages de 64 Kio ; la première page d'un bloc
# donne, pour chaque page, sa classe de taille (+1, 0 = libre). Une page ne contient que des cases d'une
# classe ; chaque case commence par un mot d'en-tête (bit 0 alloué, bit 1 marqué, bit 2 sans pointeurs,
# bit 3 grand objet, bits 8.. classe ou taille). Case libre : en-tête = lien vers la case libre suivante
# (adresse alignée, donc bit 0 nul). Objets de plus de 32 Kio : mmap dédié.
# Racines (conservatives) : registres préservés, variables globales, pile entière. Tout mot qui pointe
# dans une case allouée (début ou intérieur) la garde en vie ; les objets sont parcourus de même.
#
# État (__state(), mots) : 0..20 listes libres  24 table des blocs  25 nombre  26 capacité
#   27 prochaine page  28 fin du bloc courant  29 grands objets [début, taille]  30 nombre  31 capacité
#   32 octets alloués depuis le dernier GC  33 seuil  34 pile de marquage  35 sa taille  36 sa capacité
#   37 initialisé  38 adresse min du tas  39 adresse max  40..60 tailles des classes  61 nombre de GC
#   (sans OS) 100..103 tampon de input()  110 prochaine adresse physique libre  111 fin de la mémoire
#   120..124 tâches  126 ordonnanceur async  128..143 régions physiques rendues (2 Kio d'état en tout ;
#   auparavant 112..127, qui chevauchaient les tâches et l'ordonnanceur async)

func __rt_gc_init(st: int):
    __store64(st + 320, 16)
    __store64(st + 328, 24)
    __store64(st + 336, 32)
    __store64(st + 344, 48)
    __store64(st + 352, 64)
    __store64(st + 360, 96)
    __store64(st + 368, 128)
    __store64(st + 376, 192)
    __store64(st + 384, 256)
    __store64(st + 392, 384)
    __store64(st + 400, 512)
    __store64(st + 408, 768)
    __store64(st + 416, 1024)
    __store64(st + 424, 1536)
    __store64(st + 432, 2048)
    __store64(st + 440, 3072)
    __store64(st + 448, 4096)
    __store64(st + 456, 6144)
    __store64(st + 464, 8192)
    __store64(st + 472, 16384)
    __store64(st + 480, 32768)
    __store64(st + 296, 1)
    __store64(st + 304, 9223372036854775807)
    __store64(st + 312, 0)
    if __rt_env("ALEX_GC_STRESS=1"):
        __store64(st + 264, 4096)
    else:
        __store64(st + 264, 16777216)

func __rt_oom():
    st := __state()
    if __load64(st + 2032) != 0: # mémoire épuisée pendant le message d'erreur lui-même : sortie sans allouer
        __write_err("MemoryError: mémoire épuisée\n")
        __exit(1)
    __store64(st + 2032, 1)
    __fail("MemoryError: mémoire épuisée")

# Sans OS : régions de mémoire physique (état 110 = prochaine adresse libre, 111 = fin de la mémoire
# utilisable, 128.. = 8 régions rendues (adresse, taille)) ; 32 Mio et plus : alignées sur 32 Mio. Mises à zéro.
# Interruptions toujours masquées pendant la manipulation de la liste des zones libres : une interruption (ou la
# préemption qu'elle déclenche) au milieu d'une mise à jour laisserait une liste incohérente à la tâche suivante.
func __rt_kmap(n: int) -> int:
    f := __irq_save()
    if __load64(__state() + 2000) != 0:
        __rt_lock(__state() + 2008)
        r := __rt_kmap_impl(n)
        __rt_unlock(__state() + 2008)
        __irq_restore(f)
        return r
    r := __rt_kmap_impl(n)
    __irq_restore(f)
    return r

func __rt_kmap_impl(n: int) -> int:
    st := __state()
    size := (n + 4095) & ~4095
    prev := 0
    cur := __load64(st + 1024)
    while cur != 0:
        s := __load64(cur + 8)
        nx := __load64(cur)
        al := cur
        if size >= 33554432:
            al = (cur + 33554431) & ~33554431
        if al + size <= cur + s:
            if al == cur:
                __store64(st + 1032, __load64(st + 1032) - size)
                if s == size:
                    __rt_fl_link(st, prev, nx)
                else:
                    __store64(cur + size, nx)
                    __store64(cur + size + 8, s - size)
                    __rt_fl_link(st, prev, cur + size)
            else:
                __rt_fl_link(st, prev, nx)
                __store64(st + 1032, __load64(st + 1032) - s)
                __rt_kunmap_impl(cur, al - cur)
                if cur + s > al + size:
                    __rt_kunmap_impl(al + size, cur + s - al - size)
            __zero(al, size)
            return al
        prev = cur
        cur = nx
    next := __load64(st + 880)
    if size >= 33554432:
        next = (next + 33554431) & ~33554431
    if next + size > __load64(st + 888):
        return -12
    __store64(st + 880, next + size)
    __zero(next, size)
    return next

func __rt_fl_link(st: int, prev: int, x: int):
    if prev == 0:
        __store64(st + 1024, x)
    else:
        __store64(prev, x)

# Octets rendus et réutilisables (liste des zones libres ; compteur en état 129).
func __rt_kfree_total() -> int:
    return __load64(__state() + 1032)

# Libérations refusées (zone déjà libre ou hors de la mémoire distribuée).
func __rt_kfree_rejects() -> int:
    return __load64(__state() + 1040)

func __rt_kunmap(a: int, n: int):
    f := __irq_save()
    if __load64(__state() + 2000) != 0:
        __rt_lock(__state() + 2008)
        __rt_kunmap_impl(a, n)
        __rt_unlock(__state() + 2008)
        __irq_restore(f)
        return
    __rt_kunmap_impl(a, n)
    __irq_restore(f)

# Zone rendue : rangée dans la liste des zones libres, chaînée dans les zones elles-mêmes (adresse croissante ;
# premier mot = zone suivante, second = taille ; tête en état 128), fusionnée avec ses voisines, ou rendue à la fin
# de la mémoire distribuée si elle la touche. Plus aucune limite de cases : rien n'est perdu (l'ancienne table
# de 8 cases perdait les petites zones et épuisait la mémoire sous charge, fuzzing des appels système).
func __rt_kunmap_impl(a: int, n: int):
    st := __state()
    size := (n + 4095) & ~4095
    if size <= 0:
        return
    orig := size
    pp := 0
    prev := 0
    cur := __load64(st + 1024)
    while cur != 0 and cur < a:
        pp = prev
        prev = cur
        cur = __load64(cur)
    # Zone qui chevauche une zone déjà libre (double libération) : ignorée et comptée (état 130), sinon la liste
    # formerait une boucle.
    if (cur != 0 and cur < a + size) or (prev != 0 and prev + __load64(prev + 8) > a) or a + size > __load64(st + 880):
        __store64(st + 1040, __load64(st + 1040) + 1)
        return
    if cur != 0 and a + size == cur:
        size = size + __load64(cur + 8)
        cur = __load64(cur)
    if prev != 0 and prev + __load64(prev + 8) == a:
        a = prev
        size = size + __load64(prev + 8)
        prev = pp
    if a + size == __load64(st + 880):
        __store64(st + 880, a)
        __rt_fl_link(st, prev, cur)
        __store64(st + 1032, __load64(st + 1032) + orig - size)
        return
    __store64(st + 1032, __load64(st + 1032) + orig)
    __store64(a, cur)
    __store64(a + 8, size)
    __rt_fl_link(st, prev, a)

# Sans OS (multiboot) : page de garde sous la pile d'une tâche (Alex OS 0.7, tâche 7.5). La page la plus basse
# de la pile devient absente dans l'identité du noyau (premier Gio, partagé par tous les espaces) : un débordement
# de pile fait une faute au lieu d'écraser la mémoire voisine (le processeur, ne pouvant empiler le cadre de la
# faute, lève une double faute traitée sur sa pile IST dédiée). L'entrée de 2 Mio qui la couvre est d'abord
# découpée en 512 pages de 4 Kio (même correspondance, mêmes droits). present = 1 : la page redevient présente
# (pile rendue). Le TLB des autres cœurs est rechargé à chaque reprise de tâche (cr3).
func __rt_guard(a: int, present: int):
    if not __freestanding() or __uefi() or a >= 1073741824:
        return
    if __a64(): # AArch64 sans OS : tables de pages à blocs de 1 Gio (pas de page de garde)
        return
    f := __irq_save()
    par := __load64(__state() + 2000) != 0
    if par:
        __rt_lock(__state() + 2008)
    mask := 4503599627366400
    pml4 := __load64(__smp() + 16)
    pd := __load64(__load64(pml4) & mask) & mask
    slot := pd + 8 * ((a >> 21) & 511)
    e := __load64(slot)
    pt := 0
    if (e & 128) != 0:
        pt = __rt_kmap_impl(4096)
        base := e & 4503599625273344
        flags := e & 31
        if e < 0:
            flags = flags | (1 << 63)
        k := 0
        while k < 512:
            __store64(pt + 8 * k, (base + 4096 * k) | flags)
            k += 1
        __store64(slot, pt | (e & 31))
        __set_cr3(__cr3())
    else:
        pt = e & mask
    pte := pt + 8 * ((a >> 12) & 511)
    if present != 0:
        __store64(pte, __load64(pte) | 1)
    else:
        __store64(pte, __load64(pte) & ~1)
    __invlpg(a)
    if par:
        __rt_unlock(__state() + 2008)
    __irq_restore(f)

func __rt_map(n: int) -> int:
    a := __mmap(n)
    if a < 0:
        __rt_oom()
    return a

func __rt_heap_range(st: int, lo: int, hi: int):
    if lo < __load64(st + 304):
        __store64(st + 304, lo)
    if hi > __load64(st + 312):
        __store64(st + 312, hi)

# Ajoute une entrée de `width` mots à la table (adresse en st+8*t, nombre en t+1, capacité en t+2).
func __rt_table_push(st: int, t: int, a: int, b: int, width: int):
    tab := __load64(st + 8 * t)
    n := __load64(st + 8 * t + 8)
    cap := __load64(st + 8 * t + 16)
    if n == cap:
        cap = cap * 2 + 64
        bigger := __rt_map(8 * width * cap)
        if n > 0:
            __copy(bigger, tab, 8 * width * n)
            __munmap(tab, 8 * width * __load64(st + 8 * t + 16))
        tab = bigger
        __store64(st + 8 * t, tab)
        __store64(st + 8 * t + 16, cap)
    __store64(tab + 8 * width * n, a)
    if width > 1:
        __store64(tab + 8 * width * n + 8, b)
    __store64(st + 8 * t + 8, n + 1)

func __rt_new_chunk(st: int):
    size := 67108864
    if __freestanding(): # mémoire physique : régions de 32 Mio déjà alignées
        size = 33554432
    raw := __rt_map(size)
    base := (raw + 33554431) & ~33554431
    __store64(st + 216, base + 65536)
    __store64(st + 224, base + 33554432)
    __rt_table_push(st, 24, base, 0, 1)
    __rt_heap_range(st, base, base + 33554432)

func __rt_new_page(st: int, c: int):
    page := __load64(st + 216)
    if page == 0 or page >= __load64(st + 224):
        __rt_new_chunk(st)
        page = __load64(st + 216)
    __store64(st + 216, page + 65536)
    if __dyn(): # pages du tas en service (seuil du GC : le balayage les parcourt toutes)
        g := __load64(__globals_start())
        if g != 0:
            __store64(g + 448, __load64(g + 448) + 1)
    base := page & ~33554431
    __store8(base + ((page - base) >> 16), c + 1)
    size := __load64(st + 320 + 8 * c)
    head := __load64(st + 8 * c)
    i := 65536 // size - 1
    while i >= 0:
        slot := page + i * size
        __store64(slot, head)
        head = slot
        i -= 1
    __store64(st + 8 * c, head)

# Mode dynamique : gros blocs libérés par le GC gardés en réserve plutôt que rendus au système, rangés par palier
# de taille (x 1,25 ; état du mode dynamique : [416] têtes des listes par palier, [432] octets en réserve, 64 Mio
# au plus). Une réallocation de même ordre de taille (chaînes construites par concaténation...) évite mmap, munmap
# et les défauts de page de la mémoire neuve. Un bloc en réserve porte [suivant][taille][collection] ; ceux qui
# restent inutilisés pendant une collection entière sont rendus.
func __rt_large_bucket(size: int) -> int:
    b := 36864
    k := 0
    while b < size and k < 400:
        b = ((b + b // 4) + 4095) & ~4095
        k += 1
    return k

func __rt_large_take(st: int, total: int, need: int) -> int:
    g := __load64(__globals_start())
    if g == 0:
        return 0
    tab := __load64(g + 416)
    if tab == 0:
        return 0
    k := __rt_large_bucket(total)
    j := k
    while j < k + 4 and j < 500: # au plus ~2 x la taille demandée
        a := __load64(tab + 8 * j)
        if a != 0:
            __store64(tab + 8 * j, __load64(a))
            sz := __load64(a + 8)
            __store64(g + 432, __load64(g + 432) - sz)
            __store64(g + 440, sz)
            __zero(a, need) # partie utile seulement (au-delà : contenu périmé, jamais lu)
            return a
        j += 1
    return 0

func __rt_large_release(st: int, a: int, size: int):
    g := __load64(__globals_start())
    if g == 0 or size > 16777216 or __load64(g + 432) + size > 67108864:
        __munmap(a, size)
        return
    tab := __load64(g + 416)
    if tab == 0:
        tab = __mmap(4096)
        if tab < 0:
            __munmap(a, size)
            return
        __store64(g + 416, tab)
    k := __rt_large_bucket(size)
    if k >= 500:
        __munmap(a, size)
        return
    __store64(a, __load64(tab + 8 * k))
    __store64(a + 8, size)
    __store64(a + 16, __load64(st + 488)) # collection qui l'a libéré
    __store64(tab + 8 * k, a)
    __store64(g + 432, __load64(g + 432) + size)

# Après une collection : les blocs restés en réserve depuis la précédente (non réutilisés) sont rendus.
func __rt_large_trim(st: int):
    g := __load64(__globals_start())
    if g == 0:
        return
    tab := __load64(g + 416)
    if tab == 0:
        return
    old := __load64(st + 488) - 1
    k := 0
    while k < 500:
        prev := tab + 8 * k
        a := __load64(prev)
        while a != 0:
            nx := __load64(a)
            if __load64(a + 16) < old:
                __store64(prev, nx)
                __store64(g + 432, __load64(g + 432) - __load64(a + 8))
                __munmap(a, __load64(a + 8))
            else:
                prev = a
            a = nx
        k += 1

func __rt_alloc_large(st: int, n: int, raw0: int) -> int:
    raw := raw0 & 1
    total := (n + 8 + 4095) & ~4095
    a := 0
    if __dyn():
        # tailles par paliers (x 1,25) : un bloc rendu sert aux demandes voisines (chaînes qui grandissent)
        b := 36864
        while b < total:
            b = ((b + b // 4) + 4095) & ~4095
        total = b
        need := n + 8
        if raw0 == 3:
            need = 16 # en-tête seulement
        a = __rt_large_take(st, total, need)
        if a != 0:
            total = __load64(__load64(__globals_start()) + 440) # taille réelle du bloc repris
    if a == 0:
        a = __rt_map(total)
    __store64(a, 1 | (4 * raw) | 8 | (total << 8))
    __rt_table_push(st, 29, a, total, 2)
    __rt_heap_range(st, a, a + total)
    __store64(st + 256, __load64(st + 256) + total)
    if __dyn(): # gros objet : contrôle du GC dès la prochaine allocation si le seuil en octets est franchi
        if __load64(st + 256) > __load64(st + 264):
            ds := __load64(__globals_start())
            if ds != 0 and __load64(ds + 384) > 1:
                __store64(ds + 392, __load64(ds + 392) - __load64(ds + 384) + 1)
                __store64(ds + 384, 1)
    return a + 8

# ---- Noyau parallèle (sans OS, docs Alex OS NOYAU_PARALLELE.md) --------------------------------------------
# État : 224..239 (st + 1792) blocs des cœurs, 246 (1968) verrou de l'allocateur, 247 (1976) GC demandé (cœur
# demandeur + 1), 248 (1984) verrou des tâches, 249 (1992) verrou de la sortie (code généré), 250 (2000) mode
# parallèle (hw.smp_parallel : le verrou global du noyau n'est plus pris), 251 (2008) verrou des pages physiques.
# Hors du mode parallèle (par défaut), rien ne change : le verrou global sérialise le runtime.
func __rt_parallel() -> bool:
    if __freestanding():
        return __load64(__state() + 2000) != 0
    return false

func __rt_me() -> int:
    return __load64(__cpu_local() + 8) + 1

# Un autre cœur fait un GC : ce cœur range tous ses registres sur sa pile, publie son pointeur de pile et attend.
# Appelé par toute attente active (verrous), qui se fait interruptions masquées : sans cela, le cœur qui attend
# le verrou détenu par le GC ne recevrait jamais l'IPI d'arrêt (interblocage).
func __rt_gc_checkpoint():
    r := __load64(__state() + 1976)
    if r != 0 and r != __rt_me():
        __gc_park()

func __rt_lock(a: int):
    me := __rt_me()
    while __cas(a, 0, me) != 0:
        __rt_gc_checkpoint()
        __pause()

func __rt_unlock(a: int):
    __store64(a, 0)

# Prend le verrou s'il n'est pas déjà à ce cœur ; vrai s'il a été pris ici (à rendre).
func __rt_lock_once(a: int) -> bool:
    if __load64(a) == __rt_me():
        return false
    __rt_lock(a)
    return true

# Rend le verrou s'il est détenu par ce cœur (reprise d'une tâche commutée sous le verrou des tâches).
func __rt_unlock_mine(a: int):
    if __load64(a) == __rt_me():
        __store64(a, 0)

# Bloc du cœur qui exécute en ce moment la tâche i (autre que ce cœur), ou 0.
func __rt_running_on(st: int, i: int) -> int:
    me := __cpu_local()
    k := 0
    while k < 16:
        b := __load64(st + 1792 + 8 * k)
        if b != 0 and b != me and __load64(b + 72) != 0 and __load64(b + 16) == i:
            return b
        k += 1
    return 0

# Arrête les autres cœurs avant un GC (mode parallèle, plusieurs cœurs) : demande, IPI, attente de leur arrêt.
func __rt_stop_others(st: int) -> bool:
    if __load64(st + 2000) == 0 or __load64(__smp() + 8) <= 1:
        return false
    me := __cpu_local()
    __store64(st + 1976, __rt_me())
    __gc_ipi()
    k := 0
    while k < 16:
        b := __load64(st + 1792 + 8 * k)
        if b != 0 and b != me and __load64(b + 72) != 0:
            spins := 0
            while __load64(b + 208) == 0:
                __pause()
                spins += 1
                if spins == 1000000000:
                    __fail("RuntimeError: GC : le cœur " + __int_to_str(k) + " ne s'arrête pas")
        k += 1
    return true

# Nouvel objet de n octets, mis à zéro ; raw = 1 : sans pointeurs (jamais parcouru par le GC).
# Sans OS, l'allocation (et le GC) se fait interruptions masquées : un gestionnaire d'interruption peut
# lui-même allouer sans corrompre le tas.
func __rt_alloc(n: int, raw: int) -> int:
    if __freestanding():
        f := __irq_save()
        if __load64(__state() + 2000) != 0: # noyau parallèle : verrou de l'allocateur (et du GC)
            __rt_lock(__state() + 1968)
            q := __rt_alloc_impl(n, raw)
            __rt_unlock(__state() + 1968)
            __irq_restore(f)
            return q
        p := __rt_alloc_impl(n, raw)
        __irq_restore(f)
        return p
    return __rt_alloc_impl(n, raw)

# raw : 0 objet parcouru par le GC, 1 sans pointeurs ; 3 sans pointeurs et non mis à zéro (rempli aussitôt par
# l'appelant : chaînes construites par copie).
func __rt_alloc_impl(n: int, raw0: int) -> int:
    raw := raw0 & 1
    st := __state()
    if __load64(st + 296) == 0:
        __rt_gc_init(st)
    if __dyn():
        ds := __load64(__globals_start())
        if ds != 0:
            c := __load64(ds + 384) - 1
            __store64(ds + 384, c)
            if c <= 0:
                __dyn_gc_check(st)
    else:
        if __load64(st + 256) > __load64(st + 264):
            __rt_gc(st)
    total := n + 8
    if total > 32768:
        return __rt_alloc_large(st, n, raw0)
    c := 0
    while __load64(st + 320 + 8 * c) < total:
        c += 1
    slot := __load64(st + 8 * c)
    if slot == 0:
        __rt_new_page(st, c)
        slot = __load64(st + 8 * c)
    __store64(st + 8 * c, __load64(slot))
    size := __load64(st + 320 + 8 * c)
    if raw0 != 3:
        __zero(slot, size)
    __store64(slot, 1 | (4 * raw) | (c << 8))
    __store64(st + 256, __load64(st + 256) + size)
    return slot + 8

# Case allouée contenant l'adresse p (début ou intérieur de l'objet), ou 0.
func __rt_find(st: int, p: int) -> int:
    if p < __load64(st + 304) or p >= __load64(st + 312):
        return 0
    base := p & ~33554431
    chunks := __load64(st + 192)
    n := __load64(st + 200)
    i := 0
    while i < n:
        if __load64(chunks + 8 * i) == base:
            page := (p - base) >> 16
            if page == 0:
                return 0
            c1 := __load8(base + page)
            if c1 == 0:
                return 0
            size := __load64(st + 312 + 8 * c1)
            start := base + (page << 16)
            idx := (p - start) // size
            if idx >= 65536 // size:
                return 0
            slot := start + idx * size
            if (__load64(slot) & 1) == 0 or p < slot + 8:
                return 0
            return slot
        i += 1
    # gros objets : table triée par adresse au début de chaque collection (recherche dichotomique)
    large := __load64(st + 232)
    lo := 0
    hi := __load64(st + 240) - 1
    while lo <= hi:
        mid := (lo + hi) >> 1
        a := __load64(large + 16 * mid)
        if p < a + 8:
            hi = mid - 1
        elif p >= a + __load64(large + 16 * mid + 8):
            lo = mid + 1
        else:
            return a
    return 0

# Trie la table des gros objets par adresse (tri de Shell : elle l'est presque déjà d'une collection à l'autre).
func __rt_large_sort(st: int):
    t := __load64(st + 232)
    n := __load64(st + 240)
    gap := n >> 1
    while gap > 0:
        i := gap
        while i < n:
            a := __load64(t + 16 * i)
            z := __load64(t + 16 * i + 8)
            j := i
            while j >= gap and __load64(t + 16 * (j - gap)) > a:
                __store64(t + 16 * j, __load64(t + 16 * (j - gap)))
                __store64(t + 16 * j + 8, __load64(t + 16 * (j - gap) + 8))
                j -= gap
            __store64(t + 16 * j, a)
            __store64(t + 16 * j + 8, z)
            i += 1
        gap = gap >> 1

func __rt_slot_size(st: int, slot: int) -> int:
    h := __load64(slot)
    if (h & 8) != 0:
        return h >> 8
    return __load64(st + 320 + 8 * ((h >> 8) & 255))

func __rt_mark(st: int, p: int):
    slot := __rt_find(st, p)
    if slot == 0:
        return
    h := __load64(slot)
    if (h & 2) != 0:
        return
    __store64(slot, h | 2)
    if (h & 4) == 0:
        __rt_table_push(st, 34, slot, 0, 1)

func __rt_mark_range(st: int, a: int, b: int):
    while a < b:
        __rt_mark(st, __load64(a))
        a += 8

# Piles à parcourir : celle du programme, plus celle de chaque tâche vivante (depuis son pointeur de pile
# sauvegardé) et les objets fonction des tâches.
func __rt_mark_stacks(st: int):
    t := __load64(st + 960)
    if t == 0:
        __rt_mark_range(st, __sp(), __stack_top())
        return
    cur := __rt_cur()
    others := __load64(st + 1976) != 0 # autres cœurs arrêtés : leur tâche courante depuis leur pile publiée
    n := __load64(st + 976)
    i := 0
    while i < n:
        e := t + 128 * i
        s := __load64(e + 24)
        if s == 1 or s == 2 or s == 4 or s == 5:
            if i == cur:
                __rt_mark_range(st, __sp(), __load64(e + 16))
            else:
                b := 0
                if others:
                    b = __rt_running_on(st, i)
                if b != 0:
                    __rt_mark_range(st, __load64(b + 200), __load64(e + 16))
                else:
                    __rt_mark_range(st, __load64(e), __load64(e + 16))
            __rt_mark_range(st, e + 32, e + 40)
        i += 1

func __rt_gc(st: int):
    stopped := __rt_stop_others(st)
    __rt_gc_run(st)
    if stopped:
        __store64(st + 1976, 0)

func __rt_gc_run(st: int):
    __rt_large_sort(st)
    __store64(st + 280, 0)
    regs := __save_regs()
    __rt_mark_range(st, regs, regs + 32)
    __rt_mark_range(st, __globals_start(), __globals_end())
    __rt_mark_stacks(st)
    __rt_mark_range(st, st + 1008, st + 1016) # ordonnanceur async
    while __load64(st + 280) > 0:
        n := __load64(st + 280) - 1
        __store64(st + 280, n)
        slot := __load64(__load64(st + 272) + 8 * n)
        __rt_mark_range(st, slot + 8, slot + __rt_slot_size(st, slot))
    # Balayage : listes libres reconstruites, marques effacées.
    c := 0
    while c < 21:
        __store64(st + 8 * c, 0)
        c += 1
    live := 0
    liveObjs := 0
    freedObjs := 0
    chunks := __load64(st + 192)
    nc := __load64(st + 200)
    i := 0
    while i < nc:
        base := __load64(chunks + 8 * i)
        page := 1
        while page < 512:
            c1 := __load8(base + page)
            if c1 != 0:
                size := __load64(st + 312 + 8 * c1)
                start := base + (page << 16)
                k := 65536 // size - 1
                while k >= 0:
                    slot := start + k * size
                    h := __load64(slot)
                    if (h & 3) == 3:
                        __store64(slot, h & ~2)
                        live += size
                        liveObjs += 1
                    else:
                        if (h & 1) != 0:
                            freedObjs += 1
                        __store64(slot, __load64(st + 8 * (c1 - 1)))
                        __store64(st + 8 * (c1 - 1), slot)
                    k -= 1
            page += 1
        i += 1
    large := __load64(st + 232)
    j := 0
    while j < __load64(st + 240):
        a := __load64(large + 16 * j)
        size := __load64(large + 16 * j + 8)
        h := __load64(a)
        if (h & 2) != 0:
            __store64(a, h & ~2)
            live += size
            liveObjs += 1
            j += 1
        else:
            freedObjs += 1
            if __dyn():
                __rt_large_release(st, a, size)
            else:
                __munmap(a, size)
            last := __load64(st + 240) - 1
            __store64(large + 16 * j, __load64(large + 16 * last))
            __store64(large + 16 * j + 8, __load64(large + 16 * last + 8))
            __store64(st + 240, last)
    __store64(st + 256, 0)
    __store64(st + 488, __load64(st + 488) + 1)
    if __dyn():
        __rt_large_trim(st)
    if __dyn(): # mode dynamique : comptes d'objets (module gc, comme la VM) ; blocs du module memory dont la garde a été collectée
        __dyn_gc_swept(liveObjs, freedObjs)
        __mem_after_gc()
    if __load64(st + 2040) != 0: # hw.gc_stress (sans OS : mode --debug du noyau) : GC tous les 4 Kio alloués
        __store64(st + 264, 4096)
    elif not __rt_env("ALEX_GC_STRESS=1"):
        threshold := 2 * live
        if threshold < 16777216:
            threshold = 16777216
        __store64(st + 264, threshold)
func __rt_str_new(n: int) -> int:
    a := __alloc_raw(n + 8)
    __store64(a, n)
    return a

func __rt_concat(a: str, b: str) -> str:
    pa := __str_addr(a)
    pb := __str_addr(b)
    na := __load64(pa)
    nb := __load64(pb)
    if nb == 0:
        return a
    if na == 0:
        return b
    r := __rt_alloc(na + nb + 8, 3) # entièrement écrite ci-dessous : pas de mise à zéro
    __store64(r, na + nb)
    __copy(r + 8, pa + 8, na)
    __copy(r + 8 + na, pb + 8, nb)
    return __as_str(r)

func __rt_str_cmp(a: str, b: str) -> int:
    pa := __str_addr(a)
    pb := __str_addr(b)
    na := __load64(pa)
    nb := __load64(pb)
    n := na
    if nb < n:
        n = nb
    i := 0
    while i < n:
        x := __load8(pa + 8 + i)
        y := __load8(pb + 8 + i)
        if x != y:
            if x < y:
                return -1
            return 1
        i += 1
    if na < nb:
        return -1
    if na > nb:
        return 1
    return 0

func __rt_str_eq(a: str, b: str) -> bool:
    pa := __str_addr(a)
    pb := __str_addr(b)
    if pa == pb:
        return true
    n := __load64(pa)
    if n != __load64(pb):
        return false
    i := 0
    while i < n:
        if __load8(pa + 8 + i) != __load8(pb + 8 + i):
            return false
        i += 1
    return true

func __rt_str_len(s: str) -> int:
    p := __str_addr(s)
    n := __load64(p)
    count := 0
    i := 0
    while i < n:
        if (__load8(p + 8 + i) & 192) != 128:
            count += 1
        i += 1
    return count

func __rt_str_at(s: str, index: int) -> str:
    p := __str_addr(s)
    n := __load64(p)
    count := 0
    i := 0
    while i < n:
        if (__load8(p + 8 + i) & 192) != 128:
            if count == index:
                j := i + 1
                while j < n and (__load8(p + 8 + j) & 192) == 128:
                    j += 1
                r := __rt_str_new(j - i)
                __copy(r + 8, p + 8 + i, j - i)
                return __as_str(r)
            count += 1
        i += 1
    __fail("IndexError: index " + __int_to_str(index) + " hors limites (longueur " + __int_to_str(count) + ", §10)")
    return s

# Sans OS : prochain caractère reçu (-1 : plus rien à lire). x86-64 : port série COM1. AArch64 : UART PL011
# (adresse trouvée dans le device tree, état 243) ; UEFI AArch64 : ConIn->ReadKeyStroke (caractère UTF-16).
func __rt_fs_getc() -> int:
    if __a64():
        if __uefi():
            conin := __load64(__load64(__state() + 1928) + 48)
            key := __alloc_raw(8)
            while true:
                r := __mscall(__load64(conin + 8), conin, key)
                if r == 0:
                    ch := __load16(key + 2)
                    if ch != 0:
                        return ch
                elif r != -9223372036854775802: # EFI_NOT_READY : pas encore de touche ; autre erreur : fin
                    return -1
                __pause()
        else:
            u := __load64(__state() + 1944)
            while (__load32(u + 24) & 16) != 0: # FR.RXFE : file de réception vide
                __pause()
            return __load32(u) & 255
    else:
        while (__inb(1021) & 1) == 0:
            __pause()
        return __inb(1016)
    return -1

# input() : une ligne de l'entrée standard (tampon de 64 Kio hors du tas : état 100 = tampon, 101 = début,
# 102 = fin des données lues, 103 = fin de fichier atteinte).
func __rt_input() -> str:
    __flush()
    if __freestanding(): # sans OS : ligne lue sur le port série (fin : '\n' ou '\r')
        line := __rt_sb_new()
        while true:
            c := __rt_fs_getc()
            if c < 0 or c == 10 or c == 13:
                return __rt_sb_str(line)
            if c < 128:
                __rt_sb_byte(line, c)
            elif c < 2048:
                __rt_sb_byte(line, 192 | (c >> 6))
                __rt_sb_byte(line, 128 | (c & 63))
            else:
                __rt_sb_byte(line, 224 | (c >> 12))
                __rt_sb_byte(line, 128 | ((c >> 6) & 63))
                __rt_sb_byte(line, 128 | (c & 63))
    st := __state()
    buf := __load64(st + 800)
    if buf == 0:
        buf = __mmap(65536)
        __store64(st + 800, buf)
    sb := __rt_sb_new()
    while true:
        start := __load64(st + 808)
        end := __load64(st + 816)
        i := start
        while i < end and __load8(buf + i) != 10:
            i += 1
        j := start
        while j < i:
            __rt_sb_byte(sb, __load8(buf + j))
            j += 1
        if i < end:
            __store64(st + 808, i + 1)
            if __windows(): # fin de ligne CRLF (console, fichiers Windows) : comme la CRT en mode texte
                k := __load64(sb)
                if k > 0 and __load8(__load64(sb + 16) + k - 1) == 13:
                    __store64(sb, k - 1)
            return __rt_sb_str(sb)
        __store64(st + 808, 0)
        __store64(st + 816, 0)
        if __load64(st + 824) != 0:
            return __rt_sb_str(sb)
        n := __syscall(0, 0, buf, 65536)
        if n <= 0:
            __store64(st + 824, 1)
        else:
            __store64(st + 816, n)
    return ""

# index-ième caractère (point de code) d'une chaîne UTF-8.
func __rt_str_char_at(s: str, index: int) -> int:
    p := __str_addr(s)
    n := __load64(p)
    count := 0
    i := 0
    while i < n:
        b := __load8(p + 8 + i)
        if (b & 192) != 128:
            if count == index:
                if b < 128:
                    return b
                extra := 1
                cp := b & 31
                if b >= 240:
                    extra = 3
                    cp = b & 7
                elif b >= 224:
                    extra = 2
                    cp = b & 15
                j := 1
                while j <= extra and i + j < n:
                    cp = (cp << 6) | (__load8(p + 8 + i + j) & 63)
                    j += 1
                return cp
            count += 1
        i += 1
    __fail("IndexError: index " + __int_to_str(index) + " hors limites (longueur " + __int_to_str(count) + ", §10)")
    return 0

# Point de code -> chaîne UTF-8 d'un caractère.
func __rt_char_str(c: int) -> str:
    n := 4
    if c < 128:
        n = 1
    elif c < 2048:
        n = 2
    elif c < 65536:
        n = 3
    r := __rt_str_new(n)
    if n == 1:
        __store8(r + 8, c)
    elif n == 2:
        __store8(r + 8, 192 | (c >> 6))
        __store8(r + 9, 128 | (c & 63))
    elif n == 3:
        __store8(r + 8, 224 | (c >> 12))
        __store8(r + 9, 128 | ((c >> 6) & 63))
        __store8(r + 10, 128 | (c & 63))
    else:
        __store8(r + 8, 240 | (c >> 18))
        __store8(r + 9, 128 | ((c >> 12) & 63))
        __store8(r + 10, 128 | ((c >> 6) & 63))
        __store8(r + 11, 128 | (c & 63))
    return __as_str(r)

func __rt_index_error(i: int, n: int):
    __fail("IndexError: index " + __int_to_str(i) + " hors limites (taille " + __int_to_str(n) + ", §10)")

func __rt_sb_new() -> int:
    sb := __alloc(24)
    __store64(sb + 8, 64)
    __store64(sb + 16, __alloc_raw(64))
    return sb

func __rt_sb_reserve(sb: int, extra: int):
    n := __load64(sb)
    cap := __load64(sb + 8)
    if n + extra > cap:
        while n + extra > cap:
            cap = cap * 2
        data := __alloc_raw(cap)
        __copy(data, __load64(sb + 16), n)
        __store64(sb + 16, data)
        __store64(sb + 8, cap)

func __rt_sb_add(sb: int, s: str):
    p := __str_addr(s)
    m := __load64(p)
    __rt_sb_reserve(sb, m)
    n := __load64(sb)
    __copy(__load64(sb + 16) + n, p + 8, m)
    __store64(sb, n + m)

func __rt_sb_byte(sb: int, b: int):
    __rt_sb_reserve(sb, 1)
    n := __load64(sb)
    __store8(__load64(sb + 16) + n, b)
    __store64(sb, n + 1)

func __rt_sb_str(sb: int) -> str:
    n := __load64(sb)
    r := __rt_str_new(n)
    __copy(r + 8, __load64(sb + 16), n)
    return __as_str(r)

func __rt_list_new(n: int) -> int:
    cap := n
    if cap < 4:
        cap = 4
    l := __alloc(24)
    __store64(l, n)
    __store64(l + 8, cap)
    __store64(l + 16, __alloc(8 * cap))
    return l

func __rt_list_push(l: int, v: int):
    n := __load64(l)
    cap := __load64(l + 8)
    if n == cap:
        data := __alloc(16 * cap)
        __copy(data, __load64(l + 16), 8 * n)
        __store64(l + 16, data)
        __store64(l + 8, 2 * cap)
    __store64(__load64(l + 16) + 8 * n, v)
    __store64(l, n + 1)

# ---- Flottants ----------------------------------------------------------------------------------

# Comparaison non signée de deux mots de 64 bits.
func __rt_ule(a: int, b: int) -> bool:
    m := -9223372036854775807 - 1
    return (a ^ m) <= (b ^ m)

func __rt_floor(x: float) -> float:
    bits := __f2bits(x)
    e := ((bits >> 52) & 2047) - 1023
    if e >= 52:
        return x
    if e < 0:
        if x == 0.0:
            return x
        if bits >= 0:
            return 0.0
        return -1.0
    frac := (1 << (52 - e)) - 1
    if (bits & frac) == 0:
        return x
    if bits < 0:
        bits = bits + frac + 1
    return __bits2f(bits & ~frac)

# fmod exact (algorithme de musl) : reste de x / y du signe de x.
func __rt_fmod(x: float, y: float) -> float:
    ux := __f2bits(x)
    uy := __f2bits(y)
    ex := (ux >> 52) & 2047
    ey := (uy >> 52) & 2047
    sx := ux < 0
    if (uy << 1) == 0 or y != y or ex == 2047:
        return __bits2f(9221120237041090560)
    if __rt_ule(ux << 1, uy << 1):
        if (ux << 1) == (uy << 1):
            return 0.0 * x
        return x
    if ex == 0:
        i := ux << 12
        while i >= 0:
            ex -= 1
            i = i << 1
        ux = ux << (1 - ex)
    else:
        ux = (ux & 4503599627370495) | 4503599627370496
    if ey == 0:
        i := uy << 12
        while i >= 0:
            ey -= 1
            i = i << 1
        uy = uy << (1 - ey)
    else:
        uy = (uy & 4503599627370495) | 4503599627370496
    while ex > ey:
        i := ux - uy
        if i >= 0:
            if i == 0:
                return 0.0 * x
            ux = i
        ux = ux << 1
        ex -= 1
    i := ux - uy
    if i >= 0:
        if i == 0:
            return 0.0 * x
        ux = i
    while (ux >> 52) == 0:
        ux = ux << 1
        ex -= 1
    if ex > 0:
        ux = ux - 4503599627370496
        ux = ux | (ex << 52)
    else:
        ux = ux >> (1 - ex)
    if sx:
        ux = ux | (-9223372036854775807 - 1)
    return __bits2f(ux)

# Reste du signe du diviseur, comme la VM (floorModFloat).
func __rt_floor_mod(a: float, b: float) -> float:
    r := __rt_fmod(a, b)
    if r != 0.0 and (r < 0.0) != (b < 0.0):
        r = r + b
    return r

# Grand entier : limbs en base 10^9 (poids faible d'abord). Multiplie par m <= 1220703125 ; renvoie le nombre de limbs.
func __rt_big_mul(p: int, n: int, m: int) -> int:
    carry := 0
    i := 0
    while i < n:
        v := __load64(p + 8 * i) * m + carry
        __store64(p + 8 * i, v % 1000000000)
        carry = v // 1000000000
        i += 1
    while carry > 0:
        __store64(p + 8 * n, carry % 1000000000)
        carry = carry // 1000000000
        n += 1
    return n

# Chiffres décimaux (un octet 0..9 chacun, sans zéros de tête) ; renvoie leur nombre.
func __rt_big_digits(p: int, n: int, out: int) -> int:
    k := 0
    i := n - 1
    while i >= 0:
        v := __load64(p + 8 * i)
        j := 8
        while j >= 0:
            __store8(out + k + j, v % 10)
            v = v // 10
            j -= 1
        k += 9
        i -= 1
    first := 0
    while first < k - 1 and __load8(out + first) == 0:
        first += 1
    j := 0
    while j < k - first:
        __store8(out + j, __load8(out + first + j))
        j += 1
    return k - first

# Chiffres décimaux exacts de m * 2^e2 (m < 2^62) : res[0] = chiffres (octets 0..9, sans zéro de tête),
# res[1] = leur nombre, res[2] = exposant décimal du premier chiffre.
func __rt_exact_digits(m: int, e2: int, res: int):
    limbs := __alloc_raw(8 * 100)
    __store64(limbs, m % 1000000000)
    n := 1
    hi := m // 1000000000
    while hi > 0:
        __store64(limbs + 8 * n, hi % 1000000000)
        hi = hi // 1000000000
        n += 1
    k := 0
    if e2 >= 0:
        s := e2
        while s >= 30:
            n = __rt_big_mul(limbs, n, 1073741824)
            s -= 30
        if s > 0:
            n = __rt_big_mul(limbs, n, 1 << s)
    else:
        k = -e2
        s := k
        while s >= 13:
            n = __rt_big_mul(limbs, n, 1220703125)
            s -= 13
        p5 := 1
        while s > 0:
            p5 = p5 * 5
            s -= 1
        if p5 > 1:
            n = __rt_big_mul(limbs, n, p5)
    digits := __alloc_raw(9 * n + 16)
    nd := __rt_big_digits(limbs, n, digits)
    __store64(res, digits)
    __store64(res + 8, nd)
    __store64(res + 16, nd - 1 - k)

# Compare d1.d2...dn * 10^dx (chiffres a) à la valeur exacte (m * 2^e2) : -1, 0 ou 1.
func __rt_cmp_exact(a: int, na: int, xa: int, m: int, e2: int) -> int:
    res := __alloc_raw(24)
    __rt_exact_digits(m, e2, res)
    b := __load64(res)
    nb := __load64(res + 8)
    xb := __load64(res + 16)
    if xa != xb:
        if xa > xb:
            return 1
        return -1
    i := 0
    while i < na or i < nb:
        da := 0
        if i < na:
            da = __load8(a + i)
        db := 0
        if i < nb:
            db = __load8(b + i)
        if da != db:
            if da > db:
                return 1
            return -1
        i += 1
    return 0

func __rt_lower_ascii(c: int) -> int:
    if c >= 65 and c <= 90:
        return c + 32
    return c

# Vrai si la chaîne en p (longueur n) vaut exactement `word` (casse ignorée).
func __rt_word_is(p: int, n: int, word: str) -> bool:
    w := __str_addr(word)
    if __load64(w) != n:
        return false
    i := 0
    while i < n:
        if __rt_lower_ascii(__load8(p + i)) != __load8(w + 8 + i):
            return false
        i += 1
    return true

func __rt_conv_error(s: str, what: str):
    if __dyn(): # mode dynamique : TypeError rattrapable, comme la VM
        __dyn_err("TypeError", "to_" + what + "('" + s + "') : chaîne non convertible en " + what)
    __fail("TypeError: to_" + what + "('" + s + "') : chaîne non convertible en " + what)

func __rt_is_space(c: int) -> bool:
    return c == 32 or (c >= 9 and c <= 13)

# to_int(chaîne) comme std::stoll de la VM : espaces de tête, signe, chiffres décimaux, rien après.
func __rt_str_to_int(s: str) -> int:
    p := __str_addr(s) + 8
    n := __load64(p - 8)
    i := 0
    while i < n and __rt_is_space(__load8(p + i)):
        i += 1
    neg := false
    if i < n and (__load8(p + i) == 43 or __load8(p + i) == 45):
        neg = __load8(p + i) == 45
        i += 1
    start := i
    acc := 0
    while i < n and __load8(p + i) >= 48 and __load8(p + i) <= 57:
        d := __load8(p + i) - 48
        # accumulation en négatif : INT64_MIN reste représentable
        if acc < (-9223372036854775807 - 1 + d) // 10:
            __rt_conv_error(s, "int")
        acc = acc * 10 - d
        i += 1
    if i == start or i != n:
        __rt_conv_error(s, "int")
    if neg:
        return acc
    if acc == -9223372036854775807 - 1:
        __rt_conv_error(s, "int")
    return 0 - acc

# 10^e approché (e >= 0) par carrés successifs.
func __rt_pow10(e: int) -> float:
    r := 1.0
    b := 10.0
    while e > 0:
        if e % 2 == 1:
            r = r * b
        b = b * b
        e = e // 2
    return r

# to_float(chaîne) comme std::stod de la VM (décimal, inf, infinity, nan) : arrondi correct au plus proche
# (approximation puis correction exacte par comparaison en grand entier) ; dépassement, sous-dépassement
# (résultat nul ou sous-normal) et syntaxe invalide : TypeError.
func __rt_str_to_float(s: str) -> float:
    p := __str_addr(s) + 8
    n := __load64(p - 8)
    i := 0
    while i < n and __rt_is_space(__load8(p + i)):
        i += 1
    neg := false
    if i < n and (__load8(p + i) == 43 or __load8(p + i) == 45):
        neg = __load8(p + i) == 45
        i += 1
    if __rt_word_is(p + i, n - i, "inf") or __rt_word_is(p + i, n - i, "infinity"):
        if neg:
            return 0.0 - __bits2f(9218868437227405312)
        return __bits2f(9218868437227405312)
    if __rt_word_is(p + i, n - i, "nan"):
        return __bits2f(9221120237041090560)
    dig := __alloc_raw(n + 8)
    nd := 0
    dx := -1
    seen := false
    point := false
    while i < n:
        c := __load8(p + i)
        if c == 46 and not point:
            point = true
        elif c >= 48 and c <= 57:
            seen = true
            if nd == 0 and c == 48:
                if point:
                    dx -= 1
            else:
                __store8(dig + nd, c - 48)
                nd += 1
                if not point:
                    dx += 1
        else:
            break
        i += 1
    if not seen:
        __rt_conv_error(s, "float")
    if i < n and (__load8(p + i) == 101 or __load8(p + i) == 69):
        j := i + 1
        eneg := false
        if j < n and (__load8(p + j) == 43 or __load8(p + j) == 45):
            eneg = __load8(p + j) == 45
            j += 1
        if j < n and __load8(p + j) >= 48 and __load8(p + j) <= 57:
            ev := 0
            while j < n and __load8(p + j) >= 48 and __load8(p + j) <= 57:
                if ev < 100000:
                    ev = ev * 10 + __load8(p + j) - 48
                j += 1
            if eneg:
                ev = 0 - ev
            if nd > 0:
                dx += ev
            i = j
    if i != n:
        __rt_conv_error(s, "float")
    if nd == 0:
        if neg:
            return __bits2f(-9223372036854775807 - 1)
        return 0.0
    while nd > 1 and __load8(dig + nd - 1) == 0:
        nd -= 1
    if dx > 310:
        __rt_conv_error(s, "float")
    if dx < -330:
        __rt_conv_error(s, "float")
    # Approximation : 18 premiers chiffres significatifs.
    mm := 0
    k := 0
    while k < nd and k < 18:
        mm = mm * 10 + __load8(dig + k)
        k += 1
    e10 := dx - (k - 1)
    x := mm * 1.0
    if e10 >= 0:
        x = x * __rt_pow10(e10)
    elif e10 >= -300:
        x = x / __rt_pow10(0 - e10)
    else:
        x = (x / __rt_pow10(300)) / __rt_pow10(0 - e10 - 300)
    bits := __f2bits(x)
    if bits >= 9218868437227405312:
        bits = 9218868437227405311
    if bits <= 0:
        bits = 1
    # Correction : bits est le plus proche si la valeur est entre les demi-intervalles voisins.
    while true:
        e := (bits >> 52) & 2047
        m := bits & 4503599627370495
        e2 := -1074
        if e > 0:
            m = m | 4503599627370496
            e2 = e - 1075
        up := __rt_cmp_exact(dig, nd, dx, 2 * m + 1, e2 - 1)
        if up > 0 or (up == 0 and (m & 1) == 1):
            if bits == 9218868437227405311:
                __rt_conv_error(s, "float")
            bits += 1
            if up == 0:
                break
            continue
        lowm := 2 * m - 1
        le2 := e2 - 1
        if m == 4503599627370496 and e > 1:
            lowm = 4 * m - 1
            le2 = e2 - 2
        down := __rt_cmp_exact(dig, nd, dx, lowm, le2)
        if down < 0 or (down == 0 and (m & 1) == 1):
            if bits == 1:
                __rt_conv_error(s, "float")
            bits -= 1
            if down == 0:
                break
            continue
        break
    if ((bits >> 52) & 2047) == 0:
        __rt_conv_error(s, "float")
    if neg:
        bits = bits | (-9223372036854775807 - 1)
    return __bits2f(bits)

# Affichage d'un flottant identique à la VM : printf("%.15g"), suivi de ".0" sans '.' ni exposant.
# Conversion exacte : x = m * 2^e2 = (m * 5^-e2) * 10^e2, chiffres calculés en grand entier puis arrondis
# au plus proche (égalité : chiffre pair), comme glibc.
func __rt_float_to_str(x: float) -> str:
    bits := __f2bits(x)
    neg := bits < 0
    e := (bits >> 52) & 2047
    m := bits & 4503599627370495
    if e == 2047:
        if m != 0:
            return "nan"
        if neg:
            return "-inf"
        return "inf"
    if e == 0 and m == 0:
        if neg:
            return "-0.0"
        return "0.0"
    e2 := e - 1075
    if e == 0:
        e2 = -1074
    else:
        m = m | 4503599627370496
    res := __alloc_raw(24)
    __rt_exact_digits(m, e2, res)
    digits := __load64(res)
    nd := __load64(res + 8)
    x10 := __load64(res + 16)
    if nd > 15:
        up := false
        d := __load8(digits + 15)
        if d > 5:
            up = true
        elif d == 5:
            rest := false
            j := 16
            while j < nd:
                if __load8(digits + j) != 0:
                    rest = true
                    break
                j += 1
            if rest:
                up = true
            else:
                up = (__load8(digits + 14) % 2) == 1
        nd = 15
        if up:
            j := 14
            carry := true
            while carry and j >= 0:
                v := __load8(digits + j) + 1
                if v == 10:
                    __store8(digits + j, 0)
                    j -= 1
                else:
                    __store8(digits + j, v)
                    carry = false
            if carry:
                __store8(digits, 1)
                x10 += 1
    while nd > 1 and __load8(digits + nd - 1) == 0:
        nd -= 1
    sb := __rt_sb_new()
    if neg:
        __rt_sb_byte(sb, 45)
    if x10 < -4 or x10 >= 15:
        __rt_sb_byte(sb, 48 + __load8(digits))
        if nd > 1:
            __rt_sb_byte(sb, 46)
            i := 1
            while i < nd:
                __rt_sb_byte(sb, 48 + __load8(digits + i))
                i += 1
        __rt_sb_byte(sb, 101)
        ax := x10
        if x10 < 0:
            __rt_sb_byte(sb, 45)
            ax = -x10
        else:
            __rt_sb_byte(sb, 43)
        if ax < 10:
            __rt_sb_byte(sb, 48)
        __rt_sb_add(sb, __int_to_str(ax))
    elif x10 < 0:
        __rt_sb_byte(sb, 48)
        __rt_sb_byte(sb, 46)
        z := 0
        while z < -x10 - 1:
            __rt_sb_byte(sb, 48)
            z += 1
        i := 0
        while i < nd:
            __rt_sb_byte(sb, 48 + __load8(digits + i))
            i += 1
    else:
        i := 0
        while i <= x10:
            if i < nd:
                __rt_sb_byte(sb, 48 + __load8(digits + i))
            else:
                __rt_sb_byte(sb, 48)
            i += 1
        __rt_sb_byte(sb, 46)
        if nd > x10 + 1:
            while i < nd:
                __rt_sb_byte(sb, 48 + __load8(digits + i))
                i += 1
        else:
            __rt_sb_byte(sb, 48)
    return __rt_sb_str(sb)
# ---- Traces de pile (erreur d'exécution) ---------------------------------------------------------

func __rt_cstr_is(c: int, s: str) -> bool:
    p := __str_addr(s)
    n := __load64(p)
    i := 0
    while i < n:
        if __load8(c + i) != __load8(p + 8 + i):
            return false
        i += 1
    return __load8(c + n) == 0

# Vrai si la variable d'environnement exacte `entry` (« NOM=valeur ») est présente.
func __rt_env(entry: str) -> bool:
    sp := __argv_base()
    p := sp + 8 * (__load64(sp) + 2)
    while __load64(p) != 0:
        if __rt_cstr_is(__load64(p), entry):
            return true
        p += 8
    return false

# Table [nombre][entrées de `width` mots] triée : dernière entrée dont la clé (1er mot) est <= off, ou -1.
func __rt_bsearch(tab: int, width: int, off: int) -> int:
    lo := 0
    hi := __load64(tab) - 1
    found := -1
    while lo <= hi:
        mid := (lo + hi) // 2
        if __load64(tab + 8 + 8 * width * mid) <= off:
            found = mid
            lo = mid + 1
        else:
            hi = mid - 1
    return found

# Appelée par le runtime assembleur : addrs = [nombre][adresses de retour, la plus récente d'abord].
# Même format que la VM : appel le plus récent en dernier, fonctions du runtime omises.
func __rt_report(msg: str, addrs: int):
    if not __rt_env("ALEX_NO_TRACE=1"):
        info := __trace_info()
        funcs := info + __load64(info)
        lines := info + __load64(info + 8)
        code := __code_base()
        __write_err("Trace (appel le plus récent en dernier) :\n")
        i := __load64(addrs)
        while i >= 1:
            off := __load64(addrs + 8 * i) - code - 1
            f := __rt_bsearch(funcs, 4, off)
            if f >= 0:
                e := funcs + 8 + 32 * f
                if off < __load64(e + 8) and __load64(e + 24) != 0:
                    l := __rt_bsearch(lines, 2, off)
                    line := 0
                    if l >= 0:
                        line = __load64(lines + 8 + 16 * l + 8)
                    sb := __rt_sb_new()
                    __rt_sb_add(sb, "  ")
                    __rt_sb_add(sb, __as_str(info + __load64(e + 24)))
                    if line > 0:
                        __rt_sb_add(sb, ":")
                        __rt_sb_add(sb, __int_to_str(line))
                    __rt_sb_add(sb, ", dans ")
                    __rt_sb_add(sb, __as_str(info + __load64(e + 16)))
                    __rt_sb_add(sb, "\n")
                    __write_err(__rt_sb_str(sb))
            i -= 1
    __write_err(msg)
    __write_err("\n")
# ---- Dictionnaires : ordre d'insertion, adressage ouvert sur des numéros d'entrée ---------------
# dict = [nombre][entrées utilisées][capacité][clés][valeurs][hachages][index][masque]
# hachage < 0 : entrée supprimée ; index : case = numéro d'entrée + 1 (0 = vide), 2 x capacité cases.
# kind : 0 entier / booléen, 1 chaîne, 2 flottant.

func __rt_hash(key: int, kind: int) -> int:
    if __dyn(): # mode dynamique : clés quelconques (valeurs du runtime dynamique)
        if kind == 3:
            return __dyn_hash(key)
    if kind == 1:
        n := __load64(key)
        h := -3750763034362895579
        i := 0
        while i < n:
            h = (h ^ __load8(key + 8 + i)) * 1099511628211
            i += 1
        return h & 9223372036854775807
    if kind == 2 and key == -9223372036854775807 - 1:
        key = 0
    h := key * -7046029254386353131
    return (h ^ (h >> 29)) & 9223372036854775807

func __rt_key_eq(a: int, b: int, kind: int) -> bool:
    if a == b:
        return true
    if __dyn():
        if kind == 3:
            return __dyn_eq(a, b)
    if kind == 1:
        return __rt_str_eq(__as_str(a), __as_str(b))
    if kind == 2:
        return __bits2f(a) == __bits2f(b)
    return false

func __rt_dict_alloc(d: int, cap: int):
    __store64(d + 16, cap)
    __store64(d + 24, __alloc(8 * cap))
    __store64(d + 32, __alloc(8 * cap))
    __store64(d + 40, __alloc_raw(8 * cap))
    __store64(d + 48, __alloc_raw(16 * cap))
    __store64(d + 56, 2 * cap - 1)

func __rt_dict_new(n: int) -> int:
    d := __alloc(64)
    cap := 8
    while cap < n:
        cap = cap * 2
    __rt_dict_alloc(d, cap)
    return d

func __rt_dict_slot(d: int, h: int):
    idx := __load64(d + 48)
    mask := __load64(d + 56)
    i := h & mask
    while __load64(idx + 8 * i) != 0:
        i = (i + 1) & mask
    __store64(idx + 8 * i, __load64(d + 8) + 1)

# Numéro d'entrée de la clé, ou -1.
func __rt_dict_index(d: int, key: int, kind: int) -> int:
    h := __rt_hash(key, kind)
    idx := __load64(d + 48)
    mask := __load64(d + 56)
    keys := __load64(d + 24)
    hashes := __load64(d + 40)
    i := h & mask
    e := __load64(idx + 8 * i)
    while e != 0:
        e -= 1
        if __load64(hashes + 8 * e) == h:
            if __rt_key_eq(__load64(keys + 8 * e), key, kind):
                return e
        i = (i + 1) & mask
        e = __load64(idx + 8 * i)
    return -1

# Plein : recopie les entrées vivantes (compactage), capacité doublée si plus de la moitié est vivante.
func __rt_dict_grow(d: int):
    n := __load64(d)
    used := __load64(d + 8)
    cap := __load64(d + 16)
    keys := __load64(d + 24)
    vals := __load64(d + 32)
    hashes := __load64(d + 40)
    ncap := cap
    if n * 2 >= cap:
        ncap = cap * 2
    __rt_dict_alloc(d, ncap)
    __store64(d + 8, 0)
    e := 0
    while e < used:
        h := __load64(hashes + 8 * e)
        if h >= 0:
            j := __load64(d + 8)
            __store64(__load64(d + 24) + 8 * j, __load64(keys + 8 * e))
            __store64(__load64(d + 32) + 8 * j, __load64(vals + 8 * e))
            __store64(__load64(d + 40) + 8 * j, h)
            __rt_dict_slot(d, h)
            __store64(d + 8, j + 1)
        e += 1

func __rt_dict_set(d: int, key: int, val: int, kind: int):
    e := __rt_dict_index(d, key, kind)
    if e >= 0:
        __store64(__load64(d + 32) + 8 * e, val)
        return
    if __load64(d + 8) == __load64(d + 16):
        __rt_dict_grow(d)
    used := __load64(d + 8)
    h := __rt_hash(key, kind)
    __store64(__load64(d + 24) + 8 * used, key)
    __store64(__load64(d + 32) + 8 * used, val)
    __store64(__load64(d + 40) + 8 * used, h)
    __rt_dict_slot(d, h)
    __store64(d + 8, used + 1)
    __store64(d, __load64(d) + 1)

func __rt_dict_remove(d: int, key: int, kind: int):
    e := __rt_dict_index(d, key, kind)
    if e < 0:
        __fail("KeyError: DICT_REMOVE_KEY : clé absente du dictionnaire")
    __store64(__load64(d + 40) + 8 * e, -1)
    __store64(__load64(d + 24) + 8 * e, 0)
    __store64(__load64(d + 32) + 8 * e, 0)
    __store64(d, __load64(d) - 1)

# Liste des clés (champ 24) ou des valeurs (champ 32), dans l'ordre d'insertion.
func __rt_dict_list(d: int, field: int) -> int:
    l := __rt_list_new(0)
    used := __load64(d + 8)
    e := 0
    while e < used:
        if __load64(__load64(d + 40) + 8 * e) >= 0:
            __rt_list_push(l, __load64(__load64(d + field) + 8 * e))
        e += 1
    return l
# ---- Exceptions : objet [type][message][trace] ; chaîne de gestionnaires gérée par le code généré ----
# trace : [nombre][adresses de retour, la plus récente d'abord], relevée au premier lancement (comme la
# VM : une relance conserve la trace d'origine).

func __rt_exc_new(t: str, m: str) -> int:
    e := __alloc(32) # [type][message][trace][valeur du mode dynamique qui la porte, 0 si aucune]
    __store64(e, __str_addr(t))
    __store64(e + 8, __str_addr(m))
    return e

# Adresse `first`, puis les adresses de retour en remontant la chaîne des cadres depuis `fr`.
# Cadre suivant de la chaîne des pointeurs de cadre, ou 0 quand elle sort de la pile : un cadre appelant est plus
# haut sur la même pile (adresse croissante, alignée, à moins de 64 Mio). Sans cette garde, une exception levée par
# le noyau dans une interruption venue d'un programme (MemoryError pendant une faute de page) suivait le rbp du
# programme — un registre quelconque pour du code optimisé — et le déréférençait : faute du noyau.
func __rt_next_frame(f: int) -> int:
    g := __load64(f)
    if g <= f or (g & 7) != 0 or g - f > 67108864:
        return 0
    return g

func __rt_capture(first: int, fr: int) -> int:
    n := 1
    f := fr
    if (f & 7) != 0:
        f = 0
    while f != 0 and n < 100016:
        n += 1
        f = __rt_next_frame(f)
    buf := __alloc_raw(8 * (n + 1))
    __store64(buf, n)
    __store64(buf + 8, first)
    i := 2
    f = fr
    while i <= n:
        __store64(buf + 8 * i, __load64(f + 8))
        f = __rt_next_frame(f)
        i += 1
    return buf

func __rt_exc_str(e: int) -> str:
    return __as_str(__load64(e)) + ": " + __as_str(__load64(e + 8))

# Lève e vers le try le plus proche ; sans try actif : trace + « Type: message », code de sortie 1.
func __rt_throw(e: int):
    if __load64(e + 16) == 0:
        f := __frame()
        __store64(e + 16, __rt_capture(__load64(f + 8), __load64(f)))
    if __handler_top() == 0:
        __flush()
        __rt_report(__rt_exc_str(e), __load64(e + 16))
        __exit(1)
    __unwind(e)

# Exception du processeur sans gestionnaire (sans OS) : erreur avec trace, comme une erreur d'exécution.
func __rt_cpu_fault(vector: int, code: int):
    if __a64(): # AArch64 : vector = entrée de la table des vecteurs (0..15), code = ESR_EL1
        __fail("CPUError: " + __rt_a64_fault_name(vector, code))
    name := "exception " + __int_to_str(vector)
    if vector == 0:
        name = "division par zéro (#DE)"
    elif vector == 3:
        name = "point d'arrêt (#BP)"
    elif vector == 6:
        name = "instruction invalide (#UD)"
    elif vector == 8:
        name = "double faute (#DF)"
    elif vector == 13:
        name = "protection générale (#GP, code " + __int_to_str(code) + ")"
    elif vector == 14:
        name = "défaut de page (#PF, adresse " + __int_to_str(__cr2()) + ", code " + __int_to_str(code) + ")"
    elif vector >= 32:
        name = "interruption " + __int_to_str(vector) + " sans gestionnaire"
    __fail("CPUError: " + name)

# AArch64 sans OS / UEFI : nom d'une exception d'après l'entrée de la table des vecteurs et le syndrome (ESR).
func __rt_a64_fault_name(vector: int, esr: int) -> str:
    kind := vector & 3
    if kind == 1:
        return "interruption (IRQ) sans gestionnaire"
    if kind == 2:
        return "interruption rapide (FIQ) sans gestionnaire"
    if kind == 3:
        return "erreur système (SError, ESR " + __int_to_str(esr) + ")"
    ec := (esr >> 26) & 63
    if ec == 36 or ec == 37:
        return "défaut d'accès aux données (adresse " + __int_to_str(__cr2()) + ", ESR " + __int_to_str(esr) + ")"
    if ec == 32 or ec == 33:
        return "défaut d'instruction (adresse " + __int_to_str(__cr2()) + ")"
    if ec == 0:
        return "instruction invalide"
    if ec == 60:
        return "point d'arrêt (BRK #" + __int_to_str(esr & 65535) + ")"
    if ec == 34:
        return "adresse d'instruction mal alignée"
    if ec == 38:
        return "pile mal alignée (sp)"
    if ec == 7:
        return "FPU / SIMD désactivée"
    if ec == 21:
        return "appel système (svc) sans système d'exploitation"
    return "exception synchrone (EC " + __int_to_str(ec) + ", ESR " + __int_to_str(esr) + ")"

# ---- Tâches (fibres) : piles séparées, commutation coopérative ----------------------------------------------
# Table (état 120) d'entrées de 128 octets : [0] pointeur de pile sauvegardé, [8] base de la pile, [16] sommet,
# [24] état (0 libre, 1 prête, 2 en cours, 3 terminée, 4 réservée à async, 5 tâche inactive d'un cœur),
# [32] objet fonction, [40] gestionnaire try sauvegardé, [48] taille de la pile, [56] identifiant,
# [64] pile noyau sauvée par enter_user (0 : pas en anneau 3), [72] cr3 de son espace d'adressage (0 : noyau),
# [80] cœur d'une tâche inactive, [88] base FS de son programme en anneau 3 (TLS : arch_prctl), [96] zone de 4 Kio
# de l'état SSE / x87 de son programme (fxsave ; 0 : tâche du noyau). État 121 capacité, 122 entrées utilisées, 124 prochain identifiant.
# La tâche courante est propre à chaque cœur (bloc du cœur, + 16). L'entrée 0 est le programme principal.
# Case du gestionnaire try courant : par cœur sans OS (bloc du cœur + 192, chaque cœur a sa chaîne des try ;
# docs Alex OS NOYAU_PARALLELE.md, P1.1), dans le bss juste avant l'état du runtime sous Linux.
func __rt_handler_slot() -> int:
    if __freestanding():
        return __cpu_local() + 192
    return __state() - 8

func __rt_cur() -> int:
    return __load64(__cpu_local() + 16)

func __rt_set_cur(i: int):
    __store64(__cpu_local() + 16, i)

# Entrée de la tâche courante ; sans table des tâches, une zone du bloc du cœur en tient lieu.
func __rt_cur_entry() -> int:
    t := __load64(__state() + 960)
    if t == 0:
        return __cpu_local() + 96
    return t + 128 * __rt_cur()

func __rt_tasks_init(st: int):
    if __load64(st + 960) != 0:
        return
    cap := 4096
    t := __mmap(128 * cap)
    if t < 0:
        __rt_oom()
    __zero(t, 128)
    __store64(st + 960, t)
    __store64(st + 968, cap)
    __store64(st + 976, 1)
    __rt_set_cur(0)
    __store64(st + 992, 1)
    __store64(t + 16, __stack_top())
    __store64(t + 24, 2)

func __rt_spawn(f: int) -> int:
    st := __state()
    i := __rt_fiber_new(f, 1)
    return __load64(__load64(st + 960) + 128 * i + 56)

# Nouvelle fibre exécutant l'objet fonction f, à l'état `status` (1 prête pour tasks, 4 réservée à async,
# 5 tâche inactive d'un cœur) ; renvoie son indice dans la table.
func __rt_fiber_new(f: int, status: int) -> int:
    st := __state()
    fl := __irq_save()
    locked := false
    if __load64(st + 2000) != 0:
        locked = __rt_lock_once(st + 1984)
    __rt_tasks_init(st)
    t := __load64(st + 960)
    n := __load64(st + 976)
    i := 1
    while i < n and __load64(t + 128 * i + 24) != 0:
        i += 1
    if i == n:
        if n == __load64(st + 968):
            if locked:
                __rt_unlock(st + 1984)
            __irq_restore(fl)
            __fail("RuntimeError: trop de tâches (4096 au plus)")
        __store64(st + 976, n + 1)
    size := 262144
    if not __freestanding():
        size = 1048576
    base := __mmap(size)
    if base < 0:
        __rt_oom()
    if not __freestanding():
        __syscall(10, base, 4096, 0) # page de garde : un débordement de pile arrête le programme
    else:
        __rt_guard(base, 0)
    e := t + 128 * i
    __zero(e, 128)
    hi := base + size
    sp := hi - 72
    __store64(sp, 514)         # drapeaux (popfq) : IF = 1 (sans OS, la tâche est préemptible ; ignoré sous Linux)
    __zero(sp + 8, 48)         # r15 (profondeur), r14, r13, r12, rbx, rbp
    __store64(sp + 56, __fiber_entry())
    __store64(sp + 64, 0)
    __store64(e, sp)
    __store64(e + 8, base)
    __store64(e + 16, hi)
    __store64(e + 24, status)
    __store64(e + 32, f)
    __store64(e + 48, size)
    id := __load64(st + 992)
    __store64(st + 992, id + 1)
    __store64(e + 56, id)
    if locked:
        __rt_unlock(st + 1984)
    __irq_restore(fl)
    return i

# Libère la pile des tâches terminées (sauf la courante).
func __rt_tasks_reap(st: int):
    t := __load64(st + 960)
    n := __load64(st + 976)
    cur := __rt_cur()
    i := 1
    while i < n:
        e := t + 128 * i
        if __load64(e + 24) == 3 and i != cur:
            if __load64(e + 96) != 0:
                __munmap(__load64(e + 96), 4096)
            __rt_guard(__load64(e + 8), 1)
            __munmap(__load64(e + 8), __load64(e + 48))
            __zero(e, 128)
        i += 1

# Sans OS : espace d'adressage (cr3) et pile noyau (anneau 3) de la tâche e, sur le cœur courant.
func __rt_enter_space(e: int):
    if __a64(): # AArch64 : un seul espace d'adressage (identité), pas d'anneau 3
        return
    if __freestanding():
        c := __load64(e + 72)
        if c == 0:
            c = __load64(__smp() + 16)
        __set_cr3(c) # rechargé à chaque reprise : vide le TLB local (un processus peut migrer de cœur)
        __wrmsr(3221225728, __load64(e + 88)) # FS_BASE (0xC0000100) : TLS du programme de la tâche
        k := __load64(e + 64)
        if k != 0:
            __cpu_kstack(k)

# Plusieurs cœurs : si un autre cœur attend le verrou global du noyau, le lui laisse le temps qu'il le prenne.
func __rt_relax():
    if __freestanding():
        if __load64(__smp() + 8) > 1:
            __park(__rt_cur_entry(), 0)

# Commute de la tâche cur vers next (état de cur : `parked` s'il était en cours) ; revient à la reprise de cur.
func __rt_switch_task(t: int, cur: int, next: int, parked: int):
    ce := t + 128 * cur
    if __load64(ce + 24) == 2:
        __store64(ce + 24, parked)
    __store64(ce + 40, __load64(__rt_handler_slot())) # gestionnaire try de la tâche
    ne := t + 128 * next
    # État SSE / x87 des programmes en anneau 3 (le code du noyau n'utilise que xmm0 / xmm1, sauvés par les
    # points d'entrée) : rangé à la sortie d'une tâche qui en a un, rétabli à l'entrée de la suivante.
    if __freestanding() and __load64(ce + 96) != 0:
        __fxsave(__load64(ce + 96))
    if __load64(ne + 24) != 5:
        __store64(ne + 24, 2)
    __rt_set_cur(next)
    __store64(__rt_handler_slot(), __load64(ne + 40))
    __rt_enter_space(ne)
    if __freestanding() and __load64(ne + 96) != 0:
        __fxrstor(__load64(ne + 96))
    __switch(ce, __load64(ne))
    # De retour dans cette tâche (éventuellement sur un autre cœur). Noyau parallèle : le verrou des tâches, pris
    # par le cœur qui a commuté vers nous, est rendu ici (la tâche quittée est alors entièrement rangée).
    __rt_tasks_reap(__state())
    __rt_unlock_mine(__state() + 1984)

# Passe la main à la prochaine tâche prête (tourniquet) ; revient quand c'est de nouveau son tour. Sans tâche
# prête : la tâche courante continue ; si elle est terminée, la tâche inactive du cœur prend le relais.
func __rt_yield():
    __rt_yield_as(1)

# parked : état de la tâche quittée (1 prête ; 3 terminée : la tâche ne reprendra pas).
func __rt_yield_as(parked: int):
    st := __state()
    if __load64(st + 2000) != 0:
        # Point d'arrêt pour le GC : une boucle d'attente qui cède la main interruptions masquées (le programme de
        # démarrage tourne ainsi) ne recevrait jamais l'IPI d'arrêt.
        __rt_gc_checkpoint()
    t := __load64(st + 960)
    if t == 0:
        return
    fl := __irq_save()
    if __load64(st + 2000) != 0:
        __rt_lock_once(st + 1984)
    n := __load64(st + 976)
    cur := __rt_cur()
    next := cur
    k := 1
    while k <= n:
        j := (cur + k) % n
        if __load64(t + 128 * j + 24) == 1:
            next = j
            break
        k += 1
    if next == cur:
        s := __load64(t + 128 * cur + 24)
        if (s == 2 or s == 5) and parked != 3:
            __rt_unlock_mine(st + 1984)
            __irq_restore(fl)
            return
        idle := __load64(__cpu_local() + 56)
        if idle == 0:
            if not __freestanding():
                __fail("RuntimeError: plus aucune tâche prête")
            idle = __rt_make_idle()
        next = idle
    __rt_switch_task(t, cur, next, parked)
    __irq_restore(fl)

# Sans OS : tâche inactive du cœur courant, créée quand il n'a plus rien à exécuter (les autres tâches tournent
# sur d'autres cœurs) : attend une interruption verrou rendu, puis cède.
func __rt_idle(c: int):
    while true:
        __park(__rt_cur_entry(), 1)
        __rt_yield()

func __rt_make_idle() -> int:
    o := __alloc(16)
    __store64(o, __fnaddr("__rt_idle"))
    i := __rt_fiber_new(o, 5)
    __store64(__load64(__state() + 960) + 128 * i + 80, __load64(__cpu_local() + 8))
    __store64(__cpu_local() + 56, i)
    return i

# Point d'entrée d'une tâche (sur sa propre pile) : exécute la fonction, puis termine la tâche.
func __rt_fiber_main():
    st := __state()
    t := __load64(st + 960)
    __rt_unlock_mine(st + 1984) # première exécution après une commutation sous le verrou des tâches
    e := t + 128 * __rt_cur()
    __store64(__rt_handler_slot(), 0)
    f := __as_task(__load64(e + 32))
    f()
    __store64(e + 32, 0)
    if __rt_parallel():
        __rt_yield_as(3) # état « terminée » posé sous le verrou, au moment de quitter la pile
    else:
        __store64(e + 24, 3)
        __rt_yield()
    __fail("RuntimeError: tâche terminée reprise")

# Passe à la fibre d'indice next (ordonnanceur async) ; revient quand une autre fibre repasse la main ici.
func __rt_fiber_goto(next: int):
    st := __state()
    t := __load64(st + 960)
    cur := __rt_cur()
    if next == cur:
        return
    fl := __irq_save()
    if __load64(st + 2000) != 0:
        __rt_lock_once(st + 1984)
    __rt_switch_task(t, cur, next, 4)
    __irq_restore(fl)

# Nombre de tâches vivantes (programme principal compris).
func __rt_tasks_alive() -> int:
    st := __state()
    t := __load64(st + 960)
    if t == 0:
        return 1
    n := __load64(st + 976)
    alive := 0
    i := 0
    while i < n:
        s := __load64(t + 128 * i + 24)
        if s == 1 or s == 2:
            alive += 1
        i += 1
    return alive

func __rt_task_id() -> int:
    st := __state()
    t := __load64(st + 960)
    if t == 0:
        return 0
    return __load64(t + 128 * __rt_cur() + 56)

# ---- async / await : futurs et ordonnanceur, même sémantique que vm/Scheduler (docs/ASYNC.md) -------------
# Futur (objet du tas) : [0] état (0 en attente, 1 terminé, 2 échoué, 3 annulé), [8] valeur (mot), [16] exception,
# [24] attendants (liste), [32] futurs chaînés (liste), [40] 1 si tâche, [48] drapeaux (1 en file, 2 observé,
# 4 abandonné, 8 annulation demandée, 16 démarrée), [56] exception à lever à la reprise, [64] valeur à la reprise,
# [72] futur attendu, [80] nom, [88] fermeture, [96] fibre (-1 : pas encore créée).
# Ordonnanceur (état 126, racine du GC) : [0] tâche courante, [8] file des prêtes, [16] tête de file,
# [24] minuteurs triés, [32] numéro de minuteur, [40] tâches, [48] programme principal, [56] horloge (sans OS).
func __rt_vec_at(l: int, i: int) -> int:
    return __load64(__load64(l + 16) + 8 * i)

func __rt_vec_remove(l: int, v: int):
    n := __load64(l)
    d := __load64(l + 16)
    i := 0
    while i < n and __load64(d + 8 * i) != v:
        i += 1
    if i == n:
        return
    while i + 1 < n:
        __store64(d + 8 * i, __load64(d + 8 * i + 8))
        i += 1
    __store64(l, n - 1)

func __rt_flag(f: int, b: int) -> bool:
    return (__load64(f + 48) & b) != 0

func __rt_set_flag(f: int, b: int, on: bool):
    v := __load64(f + 48) | b
    if not on:
        v = v & ~b
    __store64(f + 48, v)

func __rt_future_new(name: str) -> int:
    f := __alloc(112) # [104] : valeur du mode dynamique qui le porte (0 si aucune)
    __store64(f + 80, __str_addr(name))
    __store64(f + 96, -1)
    return f

func __rt_sched() -> int:
    st := __state()
    s := __load64(st + 1008)
    if s != 0:
        return s
    s = __alloc(64)
    __store64(st + 1008, s)
    __store64(s + 8, __rt_list_new(0))
    __store64(s + 24, __rt_list_new(0))
    __store64(s + 40, __rt_list_new(0))
    main := __rt_future_new("")
    __store64(main + 40, 1)
    __store64(main + 48, 16)
    __store64(main + 96, 0)
    __store64(s + 48, main)
    __store64(s, main)
    __rt_tasks_init(st)
    return s

func __rt_now() -> float:
    if __freestanding(): # sans OS : horloge virtuelle, avancée jusqu'au prochain minuteur
        return __bits2f(__load64(__rt_sched() + 56))
    ts := __alloc_raw(16)
    __syscall(228, 1, ts) # clock_gettime(CLOCK_MONOTONIC)
    return __load64(ts) + __load64(ts + 8) / 1000000000.0

func __rt_make_ready(t: int):
    if __rt_flag(t, 1):
        return
    __rt_set_flag(t, 1, true)
    __rt_list_push(__load64(__rt_sched() + 8), t)

func __rt_add_waiter(awaited: int, waiter: int):
    __store64(waiter + 72, awaited)
    __rt_set_flag(awaited, 4, false)
    if __load64(awaited + 24) == 0:
        __store64(awaited + 24, __rt_list_new(0))
    __rt_list_push(__load64(awaited + 24), waiter)

func __rt_detach_waiter(waiter: int):
    a := __load64(waiter + 72)
    if a == 0:
        return
    ws := __load64(a + 24)
    if ws != 0:
        __rt_vec_remove(ws, waiter)
    if (ws == 0 or __load64(ws) == 0) and __load64(a) == 0:
        __rt_set_flag(a, 4, true)
    __store64(waiter + 72, 0)

func __rt_abandoned(f: int) -> bool:
    ws := __load64(f + 24)
    if __load64(f) != 0 or (ws != 0 and __load64(ws) != 0):
        return false
    if __rt_flag(f, 4):
        return true
    ch := __load64(f + 32)
    if ch == 0 or __load64(ch) == 0:
        return false
    i := 0
    while i < __load64(ch):
        c := __rt_vec_at(ch, i)
        if __load64(c) == 0 and not __rt_abandoned(c):
            return false
        i += 1
    return true

func __rt_complete(f: int, state: int, value: int, exc: int):
    __store64(f, state)
    __store64(f + 8, value)
    __store64(f + 16, exc)
    ws := __load64(f + 24)
    __store64(f + 24, 0)
    if ws != 0:
        i := 0
        while i < __load64(ws):
            w := __rt_vec_at(ws, i)
            __store64(w + 72, 0)
            if state == 1:
                __store64(w + 64, value)
            else:
                __store64(w + 56, exc)
            __rt_make_ready(w)
            i += 1
    ch := __load64(f + 32)
    __store64(f + 32, 0)
    if ch != 0:
        i := 0
        while i < __load64(ch):
            c := __rt_vec_at(ch, i)
            if __load64(c) == 0:
                if state == 1:
                    __rt_resolve(c, value)
                else:
                    __rt_reject(c, exc)
            i += 1

func __rt_resolve(f: int, v: int) -> bool:
    if __load64(f) != 0:
        return false
    __rt_complete(f, 1, v, 0)
    return true

func __rt_reject(f: int, exc: int) -> bool:
    if __load64(f) != 0:
        return false
    state := 2
    if __rt_cstr_eq(__load64(exc), "CancelledError"):
        state = 3
    __rt_complete(f, state, 0, exc)
    return true

func __rt_cstr_eq(a: int, b: str) -> bool:
    return __rt_str_eq(__as_str(a), b)

func __rt_cancel(f: int) -> bool:
    if __load64(f) != 0:
        return false
    exc := __rt_exc_new("CancelledError", "annulé")
    if __load64(f + 40) == 0:
        __rt_reject(f, exc)
        return true
    if f == __load64(__rt_sched()):
        __rt_set_flag(f, 8, true)
        return true
    __rt_detach_waiter(f)
    __store64(f + 56, exc)
    __rt_make_ready(f)
    return true

func __rt_timer_add(due: float, f: int, target: int):
    s := __rt_sched()
    tm := __alloc(32)
    __store64(tm, __f2bits(due))
    seq := __load64(s + 32)
    __store64(s + 32, seq + 1)
    __store64(tm + 8, seq)
    __store64(tm + 16, f)
    __store64(tm + 24, target)
    l := __load64(s + 24)
    __rt_list_push(l, tm)
    i := __load64(l) - 1 # insertion triée (échéance, puis ordre de création)
    d := __load64(l + 16)
    while i > 0 and __bits2f(__load64(__load64(d + 8 * i - 8))) > due:
        __store64(d + 8 * i, __load64(d + 8 * i - 8))
        i -= 1
    __store64(d + 8 * i, tm)

func __rt_sleep(seconds: float) -> int:
    if not (seconds >= 0.0):
        __fail("ArgumentError: 'sleep' : le délai doit être >= 0")
    f := __rt_future_new("sleep")
    __rt_timer_add(__rt_now() + seconds, f, 0)
    return f

func __rt_timeout(f: int, seconds: float) -> int:
    if not (seconds >= 0.0):
        __fail("ArgumentError: 'timeout' : le délai doit être >= 0")
    g := __rt_future_new("timeout")
    __rt_set_flag(f, 2, true)
    if __load64(f) == 0:
        if __load64(f + 32) == 0:
            __store64(f + 32, __rt_list_new(0))
        __rt_list_push(__load64(f + 32), g)
        __rt_timer_add(__rt_now() + seconds, g, f)
    elif __load64(f) == 1:
        __rt_resolve(g, __load64(f + 8))
    else:
        __rt_reject(g, __load64(f + 16))
    return g

func __rt_race(fs: int) -> int:
    if __load64(fs) == 0:
        __fail("ArgumentError: 'race' : la liste ne doit pas être vide")
    g := __rt_future_new("race")
    i := 0
    while i < __load64(fs):
        f := __rt_vec_at(fs, i)
        __rt_set_flag(f, 2, true)
        if __load64(f) == 1:
            __rt_resolve(g, __load64(f + 8))
        elif __load64(f) != 0:
            __rt_reject(g, __load64(f + 16))
        else:
            if __load64(f + 32) == 0:
                __store64(f + 32, __rt_list_new(0))
            __rt_list_push(__load64(f + 32), g)
        i += 1
    return g

func __rt_fire_timers(s: int):
    l := __load64(s + 24)
    if __load64(l) == 0:
        return
    now := __rt_now()
    while __load64(l) > 0 and __bits2f(__load64(__rt_vec_at(l, 0))) <= now:
        tm := __rt_vec_at(l, 0)
        __rt_vec_remove(l, tm)
        f := __load64(tm + 16)
        target := __load64(tm + 24)
        if target != 0:
            if __load64(f) == 0:
                __rt_reject(f, __rt_exc_new("TimeoutError", "délai dépassé"))
                __rt_cancel(target)
        else:
            __rt_resolve(f, 0)

func __rt_pop_ready(s: int) -> int:
    __rt_fire_timers(s)
    l := __load64(s + 8)
    head := __load64(s + 16)
    if head >= __load64(l):
        __store64(l, 0)
        __store64(s + 16, 0)
        return 0
    t := __rt_vec_at(l, head)
    __store64(s + 16, head + 1)
    __rt_set_flag(t, 1, false)
    return t

func __rt_wait_timers(s: int) -> bool:
    l := __load64(s + 24)
    if __load64(l) == 0:
        return false
    due := __bits2f(__load64(__rt_vec_at(l, 0)))
    if __freestanding():
        __store64(s + 56, __f2bits(due))
    else:
        d := due - __rt_now()
        if d > 0.0:
            ts := __alloc_raw(16)
            sec := __rt_trunc(d)
            __store64(ts, sec)
            __store64(ts + 8, __rt_trunc((d - sec) * 1000000000.0))
            __syscall(35, ts, 0) # nanosleep
    __rt_fire_timers(s)
    return true

func __rt_trunc(x: float) -> int:
    return __f2i(x)

# Exécute la tâche t (création de sa fibre au premier passage).
func __rt_install(t: int):
    s := __rt_sched()
    __store64(s, t)
    __rt_set_flag(t, 16, true)
    if __load64(t + 96) < 0:
        tramp := __alloc(24)
        __store64(tramp, __fnaddr("__rt_task_tramp"))
        __store64(tramp + 8, __load64(t + 80))
        __store64(tramp + 16, t)
        __store64(t + 96, __rt_fiber_new(tramp, 4))
    __rt_fiber_goto(__load64(t + 96))

# Passe à la prochaine tâche prête (minuteurs échus d'abord) ; sinon attend un minuteur ; sinon interblocage :
# le programme principal reçoit DeadlockError.
func __rt_switch_next():
    s := __rt_sched()
    while true:
        t := __rt_pop_ready(s)
        if t != 0:
            __rt_install(t)
            return
        if not __rt_wait_timers(s):
            main := __load64(s + 48)
            __rt_detach_waiter(main)
            __store64(main + 56, __rt_exc_new("DeadlockError", "toutes les tâches sont en attente : plus rien ne peut les réveiller"))
            __rt_install(main)
            return

# Nouvelle tâche : c est sa fermeture [code][nom][futur][arguments...] ; elle démarre au prochain tour.
func __rt_task_new(c: int) -> int:
    s := __rt_sched()
    t := __rt_future_new(__as_str(__load64(c + 8)))
    __store64(t + 40, 1)
    __store64(t + 88, c)
    __store64(c + 16, t)
    tasks := __load64(s + 40)
    if __load64(tasks) >= 64: # élague les tâches terminées (comme appendRoots de la VM)
        kept := __rt_list_new(0)
        i := 0
        while i < __load64(tasks):
            x := __rt_vec_at(tasks, i)
            if __load64(x) == 0 or (__load64(x) == 2 and not __rt_flag(x, 2)):
                __rt_list_push(kept, x)
            i += 1
        __store64(s + 40, kept)
        tasks = kept
    __rt_list_push(tasks, t)
    __rt_make_ready(t)
    return t

# Point d'entrée de la fibre d'une tâche : exécute sa fermeture ; une exception la fait échouer.
func __rt_task_tramp(c: int):
    t := __load64(c + 16)
    pending := __load64(t + 56)
    if pending != 0:
        __store64(t + 56, 0)
        __rt_task_died(t, pending)
    try:
        f := __as_task(__load64(t + 88))
        f()
    catch e:
        __rt_task_died(t, __addr(e))

func __rt_task_end(t: int, state: int, value: int, exc: int):
    s := __rt_sched()
    __store64(s, 0)
    st := __state()
    __store64(__load64(st + 960) + 128 * __rt_cur() + 24, 3) # fibre terminée
    __rt_complete(t, state, value, exc)
    __rt_switch_next()
    __fail("RuntimeError: tâche async terminée reprise")

func __rt_task_done(t: int, value: int):
    __rt_task_end(t, 1, value, 0)

func __rt_task_died(t: int, exc: int):
    state := 2
    if __rt_cstr_eq(__load64(exc), "CancelledError"):
        state = 3
    __rt_task_end(t, state, 0, exc)

# await f : valeur (mot) d'un futur terminé ; sinon suspend la tâche courante jusqu'à sa fin.
func __rt_await(f: int) -> int:
    s := __rt_sched()
    self := __load64(s)
    if __rt_flag(self, 8):
        __rt_set_flag(self, 8, false)
        __rt_throw(__rt_exc_new("CancelledError", "annulé"))
    if f == self:
        __rt_throw(__rt_exc_new("InvalidStateError", "une tâche ne peut pas s'attendre elle-même"))
    __rt_set_flag(f, 2, true)
    if __load64(f) == 1:
        return __load64(f + 8)
    if __load64(f) != 0:
        __rt_throw(__load64(f + 16))
    __rt_add_waiter(f, self)
    __store64(s, 0)
    __rt_switch_next()
    pending := __load64(self + 56)
    if pending != 0:
        __store64(self + 56, 0)
        __rt_throw(pending)
    return __load64(self + 64)

# gather : tâche qui attend chaque futur de la liste dans l'ordre et renvoie la liste des résultats.
func __rt_gather(fs: int) -> int:
    c := __alloc(32)
    __store64(c, __fnaddr("__rt_gather_body"))
    __store64(c + 8, __str_addr("gather"))
    __store64(c + 24, fs)
    return __rt_task_new(c)

func __rt_gather_body(c: int):
    fs := __load64(c + 24)
    out := __rt_list_new(0)
    i := 0
    while i < __load64(fs):
        __rt_list_push(out, __rt_await(__rt_vec_at(fs, i)))
        i += 1
    __rt_task_done(__load64(c + 16), out)

func __rt_future_str(f: int) -> str:
    sb := __rt_sb_new()
    if __load64(f + 40) != 0:
        __rt_sb_add(sb, "<task ")
    else:
        __rt_sb_add(sb, "<future ")
    name := __as_str(__load64(f + 80))
    if __load64(__str_addr(name)) > 0:
        __rt_sb_add(sb, name)
        __rt_sb_add(sb, " ")
    st := __load64(f)
    if st == 0:
        __rt_sb_add(sb, "pending>")
    elif st == 1:
        __rt_sb_add(sb, "done>")
    elif st == 2:
        __rt_sb_add(sb, "failed>")
    else:
        __rt_sb_add(sb, "cancelled>")
    return __rt_sb_str(sb)

func __rt_future_result(f: int) -> int:
    if __load64(f) != 1:
        __fail("ArgumentError: 'result' : le futur n'est pas terminé avec succès (utilisez await)")
    return __load64(f + 8)

# Fin du programme principal : avertit des tâches échouées que personne n'a attendues (comme la VM).
func __rt_async_end():
    st := __state()
    s := __load64(st + 1008)
    if s == 0:
        return
    __flush()
    tasks := __load64(s + 40)
    i := 0
    while i < __load64(tasks):
        t := __rt_vec_at(tasks, i)
        if __load64(t) == 2 and not __rt_flag(t, 2):
            e := __load64(t + 16)
            __write_err("Avertissement : la tâche '" + __as_str(__load64(t + 80)) + "' a échoué sans être attendue : " + __as_str(__load64(e)) + ": " + __as_str(__load64(e + 8)) + "\n")
        i += 1

# Erreur d'exécution « Type: message » survenue sous un try : devient une exception.
func __rt_raise_msg(msg: str):
    p := __str_addr(msg)
    n := __load64(p)
    i := 0
    while i + 1 < n:
        if __load8(p + 8 + i) == 58 and __load8(p + 9 + i) == 32:
            t := __rt_str_new(i)
            __copy(t + 8, p + 8, i)
            m := __rt_str_new(n - i - 2)
            __copy(m + 8, p + 10 + i, n - i - 2)
            e := __rt_with_site(__rt_exc_new(__as_str(t), __as_str(m)))
            __store64(__state() + 2032, 0) # exception construite : la garde de __rt_oom n'a plus lieu d'être
            __rt_throw(e)
        i += 1
    e2 := __rt_with_site(__rt_exc_new("Exception", msg))
    __store64(__state() + 2032, 0)
    __rt_throw(e2)

# Trace d'une erreur d'exécution : appelée depuis __rt_raise_msg, lui-même appelé par le runtime assembleur
# (arguments en registres) : l'adresse du site fautif est juste au-dessus de son adresse de retour.
func __rt_with_site(e: int) -> int:
    f := __load64(__frame())
    __store64(e + 16, __rt_capture(__load64(f + 16), __load64(f)))
    return e
