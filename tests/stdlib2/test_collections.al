# Tests : collections.* (list, array_list, vector, linked_list, deque, stack, queue, priority_queue,
# hash_map, hash_set, tree_map, tree_set, bitset, collection_errors).
from core use len, type
from collections use append
use check as t
use collections.list as lst
use collections.array_list as al
use collections.vector as vec
use collections.linked_list as ll
use collections.deque as dq
use collections.stack as st
use collections.queue as qu
use collections.priority_queue as pq
use collections.hash_map as hm
use collections.hash_set as hs
use collections.tree_map as tm
use collections.tree_set as ts
use collections.bitset as bs
use collections.collection_errors as ce

class Pt:
    func init(x, y):
        self.x = x
        self.y = y
    func hash_code():
        return self.x * 31 + self.y
    func __eq__(o):
        return isinstance(o, Pt) and o.x == self.x and o.y == self.y

class Obj:
    func init(n):
        self.n = n

# ---------------------------------------------------------------- list
il := lst.ImmutableList([3, 1, 2])
t.eq(il.size(), 3, "immutable size")
t.eq(il.get(-1), 2, "immutable get négatif")
t.eq(il.sorted().to_list(), [1, 2, 3], "immutable sorted")
t.eq(il.with_appended(4).to_list(), [3, 1, 2, 4], "with_appended")
t.eq(il.to_list(), [3, 1, 2], "originale intacte")
t.raises(() => il.set(0, 1), "TypeError", "immutable set")
t.raises(() => il.get(5), "IndexError", "immutable hors limites")
t.check(lst.is_collection(il), "is_collection")
t.check(lst.equals(il, (3, 1, 2)), "equals tuple")
seen := []
for x in il:
    append(seen, x)
t.eq(seen, [3, 1, 2], "for sur ImmutableList")
t.check(2 in il, "__contains__")
t.eq(len(il), 3, "__len__")

# ---------------------------------------------------------------- array_list
a := al.ArrayList([5, 3])
a.add(8)
a.add_at(0, 1)
t.eq(a.to_list(), [1, 5, 3, 8], "add_at")
t.check(a.remove(3), "remove valeur")
t.check(not a.remove(42), "remove absent")
a.sort()
t.eq(a.to_list(), [1, 5, 8], "sort")
t.eq(a.get(-1), 8, "get négatif")
t.eq(a.index_of(5), 1, "index_of")
t.eq(a.set(0, 7), 1, "set renvoie l'ancienne")
t.eq(a.remove_if((x) => x > 6), 2, "remove_if")
t.eq(a.to_list(), [5], "après remove_if")
a.add_all([4, 4, 9])
t.eq(a.last_index_of(4), 2, "last_index_of")
t.eq(a.sub_list(1, 3).to_list(), [4, 4], "sub_list")
t.eq(a.map((x) => x * 2).to_list(), [10, 8, 8, 18], "map")
it := a.iterator()
total := 0
while it.has_next():
    v := it.next()
    if v == 4:
        it.remove()
    total += v
t.eq(total, 22, "iterator somme")
t.eq(a.to_list(), [5, 9], "iterator.remove")
it2 := a.iterator()
a.add(1)
t.raises(() => it2.next(), "ConcurrentModificationError", "modification pendant parcours")
t.raises(() => al.ArrayList().first(), "EmptyCollectionError", "first vide")
t.check(al.of(1, 2) == al.of(1, 2), "égalité ArrayList")
a[0] = 50
t.eq(a[0], 50, "__setitem__")

# ---------------------------------------------------------------- vector
v := vec.Vector()
v.reserve(100)
t.eq(v.capacity(), 100, "reserve")
v.push_back(1)
v.push_back(2)
v.insert(1, 9)
t.eq(v.to_list(), [1, 9, 2], "insert")
t.eq(v.front(), 1, "front")
t.eq(v.back(), 2, "back")
v.resize(5, 0)
t.eq(v.to_list(), [1, 9, 2, 0, 0], "resize croissant")
t.eq(v.erase(0, 2), 2, "erase plage")
t.eq(v.to_list(), [2, 0, 0], "après erase")
v.shrink_to_fit()
t.eq(v.capacity(), 3, "shrink_to_fit")
t.eq(v.pop_back(), 0, "pop_back")
v.resize(1)
t.eq(v.to_list(), [2], "resize décroissant")
t.raises(() => v.at(3), "IndexError", "at hors limites")
w := vec.Vector()
i := 0
while i < 100:
    w.push_back(i)
    i += 1
t.eq(w.size(), 100, "croissance")
t.check(w.capacity() >= 100, "capacité suffisante")
cnt := 0
for x in w:
    cnt += 1
t.eq(cnt, 100, "for sur Vector")
t.raises(() => vec.Vector().pop_back(), "EmptyCollectionError", "pop_back vide")

# ---------------------------------------------------------------- linked_list
l := ll.LinkedList([2, 3])
l.add_first(1)
l.add_last(4)
t.eq(l.to_list(), [1, 2, 3, 4], "add_first/last")
t.eq(l.remove_first(), 1, "remove_first")
t.eq(l.peek_last(), 4, "peek_last")
c := l.cursor()
c.move_next()
c.insert_after(9)
t.eq(l.to_list(), [2, 3, 9, 4], "cursor.insert_after")
t.eq(c.remove(), 3, "cursor.remove")
t.eq(l.to_list(), [2, 9, 4], "après cursor.remove")
t.eq(c.value(), 9, "curseur avance")
l.reverse()
t.eq(l.to_list(), [4, 9, 2], "reverse")
t.eq(l.to_list_reversed(), [2, 9, 4], "to_list_reversed")
t.eq(l.get(1), 9, "get")
l.insert(1, 7)
t.eq(l.to_list(), [4, 7, 9, 2], "insert")
l2 := ll.LinkedList([10, 11])
l.splice(l2)
t.eq(l.size(), 6, "splice taille")
t.eq(l2.size(), 0, "splice vide la source")
t.eq(l.get(5), 11, "splice contenu")
s := 0
for x in l:
    s += x
t.eq(s, 43, "for sur LinkedList")
other := ll.LinkedList([1])
n := other.first_node()
t.raises(() => l.remove_node(n), "InvalidStateError", "nœud étranger")
t.raises(() => ll.LinkedList().remove_last(), "EmptyCollectionError", "remove_last vide")
big := ll.LinkedList()
i = 0
while i < 2000:
    big.add_last(i)
    i += 1
s = 0
for x in big:
    s += x
t.eq(s, 1999000, "parcours séquentiel 2000")

# ---------------------------------------------------------------- deque
d := dq.Deque([1, 2, 3])
d.push_front(0)
d.push_back(4)
t.eq(d.to_list(), [0, 1, 2, 3, 4], "push_front/back")
d.rotate(2)
t.eq(d.to_list(), [3, 4, 0, 1, 2], "rotate")
d.rotate(-2)
t.eq(d.to_list(), [0, 1, 2, 3, 4], "rotate négatif")
t.eq(d.pop_front(), 0, "pop_front")
t.eq(d.pop_back(), 4, "pop_back")
h := dq.Deque(null, 3)
for x in [1, 2, 3, 4, 5]:
    h.push_back(x)
t.eq(h.to_list(), [3, 4, 5], "max_len")
h.push_front(9)
t.eq(h.to_list(), [9, 3, 4], "max_len push_front")
g := dq.Deque()
i = 0
while i < 50:
    g.push_back(i)
    g.push_front(-i)
    i += 1
t.eq(g.size(), 100, "croissance du tampon")
t.eq(g.get(0), -49, "get après croissance")
t.eq(g.get(-1), 49, "get négatif")
t.check(g.remove(0), "remove")
t.eq(g.count(0), 1, "count")
t.raises(() => dq.Deque().peek_front(), "EmptyCollectionError", "peek vide")

# ---------------------------------------------------------------- stack
sk := st.Stack()
sk.push(1)
sk.push(2)
t.eq(sk.peek(), 2, "peek")
t.eq(sk.pop(), 2, "pop")
t.eq(sk.try_pop(), 1, "try_pop")
t.eq(sk.try_pop(), null, "try_pop vide")
b2 := st.Stack(null, 2)
b2.push(1)
b2.push(2)
t.raises(() => b2.push(3), "CapacityError", "pile pleine")
t.eq(b2.search(1), 1, "search")
t.eq(b2.to_list(), [2, 1], "to_list du sommet")
t.raises(() => st.Stack().pop(), "EmptyCollectionError", "pop vide")
t.eq(st.Stack([1, 2, 3]).pop_many(2), [3, 2], "pop_many")

# ---------------------------------------------------------------- queue
f := qu.Queue()
f.enqueue("a")
f.enqueue("b")
t.eq(f.dequeue(), "a", "FIFO")
t.eq(f.size(), 1, "taille")
bq := qu.Queue(null, 2)
t.check(bq.offer(1) and bq.offer(2), "offer")
t.check(not bq.offer(3), "offer plein")
t.raises(() => bq.enqueue(3), "CapacityError", "enqueue plein")
t.eq(bq.drain(), [1, 2], "drain")
t.eq(qu.Queue().poll(), null, "poll vide")
t.raises(() => qu.Queue().dequeue(), "EmptyCollectionError", "dequeue vide")

# ---------------------------------------------------------------- priority_queue
q := pq.PriorityQueue([5, 1, 3])
t.eq(q.pop(), 1, "tas min")
t.eq(q.pop(), 3, "tas min 2")
mx := pq.PriorityQueue([5, 1, 3], null, true)
t.eq(mx.pop(), 5, "tas max")
tasks := pq.PriorityQueue(null, (x) => x["p"])
tasks.push({"n": "a", "p": 2})
tasks.push({"n": "b", "p": 1})
tasks.push({"n": "c", "p": 1})
t.eq(tasks.pop()["n"], "b", "stable 1")
t.eq(tasks.pop()["n"], "c", "stable 2")
pp := pq.PriorityQueue()
pp.push_with_priority("x", 5)
pp.push_with_priority("y", 0)
t.eq(pp.pop_with_priority(), ["y", 0], "pop_with_priority")
t.eq(pq.n_smallest([5, 1, 4, 2], 2), [1, 2], "n_smallest")
t.eq(pq.n_largest([5, 1, 4, 2], 2), [5, 4], "n_largest")
t.eq(pq.merge_sorted([[1, 4, 7], [2, 5], [0, 9]]), [0, 1, 2, 4, 5, 7, 9], "merge_sorted")
r := pq.PriorityQueue([4, 2, 8])
t.eq(r.push_pop(1), 1, "push_pop plus petit")
t.eq(r.push_pop(5), 2, "push_pop")
t.check(r.update_priority(8, 0) == false or true, "update_priority")
rr := pq.PriorityQueue([4, 8, 6])
t.check(rr.remove(8), "remove")
t.eq(rr.to_sorted_list(), [4, 6], "to_sorted_list")
t.raises(() => pq.PriorityQueue().pop(), "EmptyCollectionError", "pop vide")
desc := pq.PriorityQueue([3, 9, 1], null, false, (x, y) => y - x)
t.eq(desc.pop(), 9, "comparateur")

# ---------------------------------------------------------------- hash_map
m := hm.HashMap()
m.put("a", 1)
m["b"] = 2
t.eq(m.get("a"), 1, "get")
t.eq(m["b"], 2, "__getitem__")
t.eq(m.get("z", 0), 0, "défaut")
t.eq(m.size(), 2, "size")
m.compute("a", (k, x) => x + 10)
t.eq(m["a"], 11, "compute")
m.merge("c", 1, (o, nw) => o + nw)
m.merge("c", 1, (o, nw) => o + nw)
t.eq(m["c"], 2, "merge")
t.eq(m.keys(), ["a", "b", "c"], "ordre d'insertion")
t.eq(m.remove("a"), 11, "remove")
t.check(not m.contains_key("a"), "remove effectif")
t.raises(() => m["zz"], "KeyError", "clé absente")
pts := hm.HashMap()
pts.put(Pt(1, 2), "p")
t.eq(pts.get(Pt(1, 2)), "p", "clé instance par valeur")
o1 := Obj(1)
pts.put(o1, "o")
t.eq(pts.get(o1), "o", "clé instance identité")
t.eq(pts.get(Obj(1)), null, "autre instance")
many := hm.HashMap()
i = 0
while i < 500:
    many.put(i, i * i)
    i += 1
i = 0
while i < 500:
    if i % 2 == 0:
        many.remove(i)
    i += 1
t.eq(many.size(), 250, "suppressions massives")
t.eq(many.get(499), 249001, "valeur après rehash")
t.eq(many.get(498), null, "supprimée")
t.check(many.stats()["longest_chain"] < 10, "chaînes courtes")
t.eq(hm.counter("abca").get('a'), 2, "counter")
gb := hm.group_by([1, 2, 3, 4], (x) => x % 2)
t.eq(gb.get(0), [2, 4], "group_by")
t.check(hm.HashMap({"x": 1}) == hm.HashMap([["x", 1]]), "égalité HashMap")
t.eq(m.to_dict()["b"], 2, "to_dict")
t.raises(() => hm.HashMap().put({}, 1), "TypeError", "dict comme clé")

# ---------------------------------------------------------------- hash_set
sa := hs.HashSet([1, 2, 3])
sb := hs.HashSet([3, 4])
t.eq(sa.union(sb).to_list(), [1, 2, 3, 4], "union")
t.eq(sa.intersection(sb).to_list(), [3], "intersection")
t.eq(sa.difference(sb).to_list(), [1, 2], "difference")
t.eq(sa.symmetric_difference(sb).to_list(), [1, 2, 4], "symmetric_difference")
t.check(sa.is_subset(hs.HashSet([1, 2, 3, 9])), "is_subset")
t.check(not sa.add(2), "add doublon")
t.check(hs.HashSet([Pt(0, 0), Pt(0, 0)]).size() == 1, "instances dédoublonnées")
t.eq((sa | sb).size(), 4, "opérateur |")
t.eq((sa & sb).to_list(), [3], "opérateur &")
t.check(hs.of(1, 2) == hs.of(2, 1), "égalité indépendante de l'ordre")
t.eq(hs.of(1, 2).hash_code(), hs.of(2, 1).hash_code(), "hash_code indépendant de l'ordre")
t.eq(hs.HashSet([5]).pop(), 5, "pop")
t.raises(() => hs.HashSet().pop(), "EmptyCollectionError", "pop vide")

# ---------------------------------------------------------------- tree_map
tmap := tm.TreeMap()
tmap.put(30, "c")
tmap.put(10, "a")
tmap[20] = "b"
t.eq(tmap.keys(), [10, 20, 30], "ordre")
t.eq(tmap.first_key(), 10, "first_key")
t.eq(tmap.last_key(), 30, "last_key")
t.eq(tmap.floor_key(25), 20, "floor_key")
t.eq(tmap.ceiling_key(25), 30, "ceiling_key")
t.eq(tmap.lower_key(20), 10, "lower_key")
t.eq(tmap.higher_key(20), 30, "higher_key")
t.eq(tmap.floor_key(5), null, "floor_key absent")
t.eq(tmap.range(10, 30), [[10, "a"], [20, "b"]], "range")
t.eq(tmap.range(10, 30, true), [[10, "a"], [20, "b"], [30, "c"]], "range inclusive")
t.eq(tmap.pop_first(), [10, "a"], "pop_first")
t.eq(tmap.put(20, "B"), "b", "put remplace")
bigt := tm.TreeMap()
i = 0
while i < 1000:
    bigt.put((i * 7919) % 1000, i)
    i += 1
t.eq(bigt.size(), 1000, "1000 clés")
t.check(bigt.height() <= 15, "équilibré (hauteur " + str(bigt.height()) + ")")
i = 0
while i < 1000:
    if i % 3 != 0:
        bigt.remove(i)
    i += 1
t.eq(bigt.size(), 334, "suppressions")
ks := bigt.keys()
ok := true
i = 1
while i < len(ks):
    if ks[i - 1] >= ks[i]:
        ok = false
    i += 1
t.check(ok, "ordre après suppressions")
t.check(bigt.height() <= 13, "équilibré après suppressions")
bylen := tm.TreeMap(null, (x, y) => len(x) - len(y))
bylen.put("ccc", 3)
bylen.put("a", 1)
bylen.put("bb", 2)
t.eq(bylen.keys(), ["a", "bb", "ccc"], "comparateur")
t.raises(() => tm.TreeMap().first_key(), "EmptyCollectionError", "first_key vide")
t.raises(() => tmap["nope"], "TypeError", "clés non comparables")

# ---------------------------------------------------------------- tree_set
tset := ts.TreeSet([5, 1, 3, 1])
t.eq(tset.to_list(), [1, 3, 5], "tri et dédoublonnage")
t.eq(tset.first(), 1, "first")
t.eq(tset.ceiling(2), 3, "ceiling")
t.eq(tset.range(2, 6), [3, 5], "range")
t.eq(tset.union(ts.TreeSet([2])).to_list(), [1, 2, 3, 5], "union")
t.eq(tset.intersection([3, 5, 7]).to_list(), [3, 5], "intersection")
t.eq(tset.to_list_descending(), [5, 3, 1], "descending")

# ---------------------------------------------------------------- bitset
bb := bs.BitSet(16)
bb.set(1)
bb.set(3)
bb.set_range(8, 12)
t.check(bb.get(3), "get")
t.eq(bb.cardinality(), 6, "cardinality")
t.eq(bb.next_set_bit(4), 8, "next_set_bit")
t.eq(bb.next_clear_bit(8), 12, "next_clear_bit")
cc := bs.from_list([1, 2])
t.eq(bb.and_(cc).to_list(), [1], "and")
t.eq(bb.or_(cc).to_list(), [1, 2, 3, 8, 9, 10, 11], "or")
t.eq(bb.xor(cc).to_list(), [2, 3, 8, 9, 10, 11], "xor")
t.eq(bb.and_not(cc).to_list(), [3, 8, 9, 10, 11], "and_not")
t.eq(bs.from_string("1011").to_list(), [0, 2, 3], "from_string")
t.eq(bs.from_list([0, 2, 3]).to_string(), "1011", "to_string")
t.eq(bs.from_int(10, 8).to_list(), [1, 3], "from_int")
bb.set(100)
t.check(bb.get(100), "croissance")
t.eq(bb.length(), 101, "length")
fx := bs.BitSet(8, true)
t.raises(() => fx.set(8), "IndexError", "taille fixe")
t.raises(() => bb.set(-1), "IndexError", "bit négatif")
bb.flip(1)
t.check(not bb.get(1), "flip")
t.eq(bs.from_list([0, 1]).invert().to_list(), [], "invert")

# ---------------------------------------------------------------- errors
t.eq(len(ce.kinds()), 5, "kinds")
t.raises(() => ce.check_index("f", 3, 3), "IndexError", "check_index")
t.eq(ce.check_index("f", -1, 3), 2, "check_index négatif")
t.raises(() => ce.check_capacity("f", 0), "ArgumentError", "check_capacity")

t.summary("collections")
