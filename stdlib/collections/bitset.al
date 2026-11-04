# ALEX STANDARD LIBRARY — collections.bitset
#
# BitSet : ensemble d'entiers positifs compact, un bit par valeur (mots de 32 bits). Opérations ensemblistes
# mot à mot, comptage de population, recherche du bit suivant. Croît à la demande, sauf si une taille fixe
# est donnée (fixed=true : un bit hors de 0..size-1 lève IndexError).
#
#   use collections.bitset as bs
#   b := bs.BitSet(16)
#   b.set(1)
#   b.set(3)
#   b.set_range(8, 12)                 # 8, 9, 10, 11
#   print(b.get(3), b.cardinality())   # true 6
#   print(b.next_set_bit(4))           # 8
#   c := bs.from_list([1, 2])
#   print(b.and_(c).to_list())         # [1]
#   print(bs.from_string("1011").to_list())   # [0, 2, 3]  (bit 0 à gauche)
#
# Erreurs : IndexError (bit négatif, hors taille fixe), TypeError.

from core use len, type
from collections use append
from collections.list use Collection
use collections.collection_errors as _e

const WORD := 32
const MASK := 0xffffffff

func _popcount(w):
    c := 0
    while w != 0:
        w = w & (w - 1)
        c += 1
    return c

class BitSet implements Collection:
    func init(size=64, fixed=false):
        _e.need_int("BitSet", size, "la taille")
        if size < 0:
            raise("ArgumentError", "BitSet : taille négative")
        self._fixed = fixed
        self._size = size
        nw := (size + WORD - 1) // WORD
        if nw < 1:
            nw = 1
        self._w = [0] * nw

    func _check(i, fn):
        _e.need_int("BitSet." + fn, i, "le bit")
        if i < 0:
            raise("IndexError", "BitSet." + fn + " : bit négatif " + str(i))
        if self._fixed and i >= self._size:
            raise("IndexError", "BitSet." + fn + " : bit " + str(i) + " hors de la taille fixe " + str(self._size))

    func _ensure(i):
        need := i // WORD + 1
        while len(self._w) < need:
            append(self._w, 0)
        if i + 1 > self._size:
            self._size = i + 1

    # Taille logique (nombre de bits adressables).
    func length():
        return self._size

    # Collection.size : nombre de bits à 1.
    func size():
        return self.cardinality()

    func is_empty():
        for w in self._w:
            if w != 0:
                return false
        return true

    func set(i, value=true):
        self._check(i, "set")
        if not value:
            self.clear_bit(i)
            return
        self._ensure(i)
        self._w[i // WORD] = self._w[i // WORD] | (1 << (i % WORD))

    func clear_bit(i):
        self._check(i, "clear_bit")
        if i // WORD < len(self._w):
            self._w[i // WORD] = self._w[i // WORD] & (MASK ^ (1 << (i % WORD)))

    func flip(i):
        self._check(i, "flip")
        self._ensure(i)
        self._w[i // WORD] = self._w[i // WORD] ^ (1 << (i % WORD))

    func get(i):
        self._check(i, "get")
        if i // WORD >= len(self._w):
            return false
        return ((self._w[i // WORD] >> (i % WORD)) & 1) == 1

    # Met à 1 les bits start..stop-1.
    func set_range(start, stop, value=true):
        i := start
        while i < stop:
            self.set(i, value)
            i += 1

    func clear_range(start, stop):
        self.set_range(start, stop, false)

    func cardinality():
        c := 0
        for w in self._w:
            c += _popcount(w)
        return c

    func contains(i):
        if type(i) != "int" or i < 0:
            return false
        return self.get(i)

    func next_set_bit(start=0):
        i := start
        limit := len(self._w) * WORD
        while i < limit:
            w := self._w[i // WORD] >> (i % WORD)
            if w == 0:
                i = (i // WORD + 1) * WORD
                continue
            while (w & 1) == 0:
                w = w >> 1
                i += 1
            return i
        return -1

    func next_clear_bit(start=0):
        i := start
        while self.get(i):
            i += 1
        return i

    func previous_set_bit(start):
        i := start
        while i >= 0:
            if self.get(i):
                return i
            i -= 1
        return -1

    func _combine(other, op):
        n := len(self._w)
        if len(other._w) > n:
            n = len(other._w)
        size := self._size
        if other._size > size:
            size = other._size
        out := BitSet(size, self._fixed and other._fixed)
        out._w = [0] * n
        i := 0
        while i < n:
            a := 0
            b := 0
            if i < len(self._w):
                a = self._w[i]
            if i < len(other._w):
                b = other._w[i]
            if op == "and":
                out._w[i] = a & b
            elif op == "or":
                out._w[i] = a | b
            elif op == "xor":
                out._w[i] = a ^ b
            else:
                out._w[i] = a & (MASK ^ b)
            i += 1
        return out

    func and_(other):
        return self._combine(other, "and")

    func or_(other):
        return self._combine(other, "or")

    func xor(other):
        return self._combine(other, "xor")

    func and_not(other):
        return self._combine(other, "andnot")

    func intersects(other):
        return not self.and_(other).is_empty()

    # Complément sur la taille logique.
    func invert():
        out := BitSet(self._size, self._fixed)
        i := 0
        while i < self._size:
            if not self.get(i):
                out.set(i)
            i += 1
        return out

    func clear():
        self._w = [0] * len(self._w)

    # Bits à 1, croissants.
    func to_list():
        out := []
        i := self.next_set_bit(0)
        while i >= 0:
            append(out, i)
            i = self.next_set_bit(i + 1)
        return out

    # Mots de 32 bits (bit 0 = poids faible du premier mot).
    func to_words():
        return self._w[:]

    # Chaîne de 0/1, bit 0 à gauche, sur la taille logique.
    func to_string():
        out := ""
        i := 0
        while i < self._size:
            if self.get(i):
                out += "1"
            else:
                out += "0"
            i += 1
        return out

    func copy():
        b := BitSet(self._size, self._fixed)
        b._w = self._w[:]
        return b

    func __eq__(other):
        if not isinstance(other, BitSet):
            return false
        return self.to_list() == other.to_list()

    func __len__():
        return self.cardinality()

    func __contains__(i):
        return self.contains(i)

    func __getitem__(i):
        if i >= self._size:
            raise("IndexError", "BitSet : bit " + str(i) + " hors de la taille")
        return self.get(i)

    func __and__(other):
        return self.and_(other)

    func __or__(other):
        return self.or_(other)

    func __xor__(other):
        return self.xor(other)

    func __str__():
        return "BitSet{" + str(self.to_list()) + "}"

func from_list(bits, size=null):
    n := size
    if n == null:
        n = 0
        for b in bits:
            if b + 1 > n:
                n = b + 1
    s := BitSet(n)
    for b in bits:
        s.set(b)
    return s

func from_string(text):
    s := BitSet(len(text))
    i := 0
    for ch in text:
        if ch == '1':
            s.set(i)
        elif ch != '0':
            raise("ValueError", "bitset.from_string : caractère '" + str(ch) + "' (0 ou 1 attendu)")
        i += 1
    return s

func from_int(value, size=64):
    s := BitSet(size)
    i := 0
    v := value
    while v != 0 and i < size:
        if (v & 1) == 1:
            s.set(i)
        v = v >> 1
        i += 1
    return s
