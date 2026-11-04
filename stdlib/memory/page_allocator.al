# ALEX STANDARD LIBRARY — memory.page_allocator
#
# Allocateur de PAGES sur une réservation d'espace d'adressage : on réserve d'un coup une grande plage
# inaccessible (PROT_NONE), puis on « engage » (commit) des suites de pages contiguës à la demande
# (lecture/écriture), et on les rend (decommit : pages vidées et de nouveau inaccessibles). Modèle des tas,
# piles et tampons à croissance contrôlée : tout accès hors des pages engagées est détecté.
#
#   use memory.page_allocator as pg
#   a := pg.PageAllocator(64)                 # 64 pages réservées
#   s := a.alloc_pages(3)                     # PageSpan de 3 pages contiguës (lecture/écriture)
#   s.view().write("u64", 1)
#   print(s.first_page, s.count, a.free_pages())   # 0 3 61
#   a.free_pages_of(s)                        # rendues : le contenu est effacé, l'accès refusé
#   print(a.largest_free_run())               # 64
#   a.destroy()
#
# Stratégie : premier ajustement (first fit) sur une table de bits ; les trous libérés se recombinent.
# Erreurs : MemoryError (plus de suite assez longue, accès à une page non engagée), ArgumentError.

from core use len, type
from collections use append
use _native_memory as _m
use memory.virtual_memory as _vm
use memory.memory_errors as _e

class PageSpan:
    func init(owner, first_page, count, token):
        self.owner = owner
        self.first_page = first_page
        self.count = count
        self.token = token

    func offset():
        return self.first_page * self.owner.page_size

    func size():
        return self.count * self.owner.page_size

    func valid():
        return self.owner._valid(self)

    # Vue (lecture/écriture) sur les pages de l'étendue.
    func view():
        if not self.valid():
            raise(_e.STALE_VIEW, "PageSpan.view : étendue déjà rendue")
        return self.owner.region.view(self.offset(), self.size())

    func address():
        return self.owner.region.address() + self.offset()

    func __str__():
        return "PageSpan(pages " + str(self.first_page) + ".." + str(self.first_page + self.count - 1) + ")"

class PageAllocator:
    func init(page_count, tag=null):
        if type(page_count) != "int" or page_count < 1:
            raise("ArgumentError", "PageAllocator : nombre de pages >= 1 attendu")
        self.page_size = _m.page_size()
        self.page_count = page_count
        self.region = _vm.reserve(page_count * self.page_size, tag)
        self._used = [false] * page_count
        self._spans = {}       # première page -> [nombre, jeton]
        self._next_token = 0
        self._committed = 0
        self._peak = 0

    func _valid(span):
        if not (span.first_page in self._spans):
            return false
        return self._spans[span.first_page][1] == span.token

    # n pages contiguës engagées (lecture/écriture, zéro).
    func alloc_pages(n):
        if type(n) != "int" or n < 1:
            raise("ArgumentError", "PageAllocator.alloc_pages : n >= 1 attendu")
        run := 0
        i := 0
        while i < self.page_count:
            if self._used[i]:
                run = 0
            else:
                run += 1
                if run == n:
                    first := i - n + 1
                    k := first
                    while k <= i:
                        self._used[k] = true
                        k += 1
                    self.region.protect(_vm.RW, first * self.page_size, n * self.page_size)
                    self._next_token += 1
                    self._spans[first] = [n, self._next_token]
                    self._committed += n
                    if self._committed > self._peak:
                        self._peak = self._committed
                    return PageSpan(self, first, n, self._next_token)
            i += 1
        _e.out_of_memory("PageAllocator.alloc_pages", n * self.page_size, self.largest_free_run() * self.page_size)

    # Rend les pages d'une étendue (effacées puis inaccessibles).
    func free_pages_of(span):
        if not isinstance(span, PageSpan) or not self._valid(span):
            _e.double_free("PageAllocator.free_pages_of")
        off := span.first_page * self.page_size
        n := span.count * self.page_size
        self.region.fill(0, off, n)
        self.region.protect(_vm.NONE, off, n)
        k := span.first_page
        while k < span.first_page + span.count:
            self._used[k] = false
            k += 1
        del self._spans[span.first_page]
        self._committed -= span.count

    func free_pages():
        return self.page_count - self._committed

    func committed_pages():
        return self._committed

    # Plus longue suite de pages libres.
    func largest_free_run():
        best := 0
        run := 0
        for u in self._used:
            if u:
                run = 0
            else:
                run += 1
                if run > best:
                    best = run
        return best

    # Carte des pages : "#" engagée, "." libre.
    func map_string():
        out := ""
        for u in self._used:
            if u:
                out += "#"
            else:
                out += "."
        return out

    func stats():
        return {"page_size": self.page_size, "pages": self.page_count, "committed": self._committed,
                "free": self.free_pages(), "peak": self._peak, "spans": len(self._spans),
                "largest_free_run": self.largest_free_run()}

    func destroy():
        self.region.unmap()
        self._spans = {}
        self._used = [true] * self.page_count
