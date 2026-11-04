# ALEX STANDARD LIBRARY — memory.aligned_memory
#
# Alignement : arithmétique d'adresses et tampons alignés (SIMD, DMA, lignes de cache, pages).
#
#   use memory.aligned_memory as am
#   print(am.align_up(13, 8), am.align_down(13, 8), am.padding(13, 8))   # 16 8 3
#   b := am.AlignedBuffer(4096, am.PAGE)          # adresse multiple de 4096
#   print(am.is_aligned(b.address(), 4096))       # true
#   v := am.aligned_slice(buffer_quelconque, 64)  # sous-vue qui commence sur une ligne de cache
#   print(am.next_power_of_two(1000))             # 1024
#
# Constantes : CACHE_LINE (64), PAGE (taille de page système), SIMD (32, AVX), MAX_ALIGN (65536, limite native).
# Erreurs : AlignmentError (alignement non puissance de 2), ArgumentError, TypeError.

from core use type
use _native_memory as _m
from memory.buffer use Buffer
use memory.memory_errors as _e

const CACHE_LINE := 64
const SIMD := 32
const MAX_ALIGN := 65536
PAGE := _m.page_size()

func is_power_of_two(n):
    return _e.is_power_of_two(n)

func next_power_of_two(n):
    if type(n) != "int":
        raise("TypeError", "next_power_of_two : int attendu")
    p := 1
    while p < n:
        p = p * 2
    return p

func align_up(value, align):
    _e.need_align("align_up", align)
    return (value + align - 1) & (-align)

func align_down(value, align):
    _e.need_align("align_down", align)
    return value & (-align)

func is_aligned(value, align):
    _e.need_align("is_aligned", align)
    return (value & (align - 1)) == 0

# Octets à ajouter à value pour atteindre l'alignement.
func padding(value, align):
    return align_up(value, align) - value

# Plus grand alignement (puissance de 2) dont value est multiple (value > 0).
func alignment_of(value):
    if value == 0:
        return MAX_ALIGN
    return value & (-value)

# Alignement naturel d'un type natif (u32 -> 4...).
func natural_alignment(type_name):
    return _m.type_size(type_name)

# Taille arrondie au multiple de l'alignement (taille d'un élément de tableau aligné).
func stride(size, align):
    return align_up(size, align)

class AlignedBuffer extends Buffer:
    func init(size, align=CACHE_LINE, zero=true, tag=null):
        _e.need_size("AlignedBuffer", size)
        _e.need_align("AlignedBuffer", align)
        if align > MAX_ALIGN:
            raise(_e.ALIGNMENT, "AlignedBuffer : alignement " + str(align) + " > " + str(MAX_ALIGN))
        super.init(size, zero, align, tag)
        self.alignment = align

    # Sous-vue de `count` éléments de `elem_size` octets, chacun aligné sur `align` (stride).
    func element_view(index, elem_size, align=null):
        a := align
        if a == null:
            a = self.alignment
        st := stride(elem_size, a)
        return self.view(index * st, elem_size)

# Sous-vue de `source` (Buffer ou MemoryView) qui commence à la première adresse alignée.
func aligned_slice(source, align, length=null):
    _e.need_align("aligned_slice", align)
    base := source.address()
    pad := padding(base, align)
    if pad >= source.size():
        raise("ArgumentError", "aligned_slice : aucune adresse alignée sur " + str(align) + " dans la source")
    n := length
    if n == null:
        n = source.size() - pad
    return source.view(pad, n)

# Tampon aligné ; raccourci.
func buffer(size, align=CACHE_LINE, zero=true):
    return AlignedBuffer(size, align, zero)
