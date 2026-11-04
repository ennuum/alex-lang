# Tests : smart_pointer.* (unique_ptr, shared_ptr, weak_ptr, reference_count, ownership, façade).
from core use len, type
from collections use append
use check as t
use smart_pointer as smp
use smart_pointer.unique_ptr as up
use smart_pointer.shared_ptr as sp
use smart_pointer.weak_ptr as wp
use smart_pointer.reference_count as rc
use smart_pointer.ownership as own

log := []
class Res:
    func init(name):
        self.name = name
        self.open = true
    func close():
        self.open = false
        append(log, "close " + self.name)

func closer(r):
    r.close()

# unique
p := up.make_unique(Res("a"), closer)
t.eq(p.get().name, "a", "get")
q := p.move()
t.raises(() => p.get(), "OwnershipError", "après move")
t.check(p.is_moved(), "is_moved")
t.eq(q.get().name, "a", "propriété transférée")
q.reset(Res("b"))
t.eq(log, ["close a"], "reset appelle le suppresseur")
v := q.release()
t.eq(v.name, "b", "release rend la valeur")
t.check(q.is_null(), "vide après release")
t.eq(len(log), 1, "release sans suppresseur")
t.raises(() => q.get(), "NullPointerError", "get vide")
t.eq(q.get_or(7), 7, "get_or")
up.with_unique(Res("c"), closer, (ptr) => ptr.get().name)
t.eq(log[1], "close c", "with_unique")
func fail_body(ptr):
    raise("ValueError", "x")
t.raises(() => up.with_unique(Res("d"), closer, fail_body), "ValueError", "with_unique propage")
t.eq(log[2], "close d", "with_unique libère sur erreur")
x1 := up.make_unique(1)
x2 := up.make_unique(2)
x1.swap(x2)
t.eq([x1.get(), x2.get()], [2, 1], "swap")
func bad_del(r):
    raise("IoError", "disque")
bd := up.make_unique(1, bad_del)
t.raises(() => bd.reset(), "DeleterError", "suppresseur en échec")
t.raises(() => up.make_unique(1, 5), "TypeError", "suppresseur invalide")
with up.make_unique(Res("w"), closer) as wptr:
    t.eq(wptr.get().name, "w", "with")
t.eq(log[3], "close w", "__exit__")

# shared
a := sp.make_shared(Res("s"), closer)
b := a.clone()
t.eq(a.use_count(), 2, "use_count")
t.check(a.ptr_eq(b), "ptr_eq")
a.drop()
t.raises(() => a.get(), "OwnershipError", "après drop")
t.check(b.unique(), "unique")
t.eq(len(log), 4, "pas encore détruit")
b.drop()
t.eq(log[4], "close s", "dernier relâchement")
b.drop()
t.eq(len(log), 5, "drop idempotent")
t.check(not sp.make_shared(1).ptr_eq(sp.make_shared(1)), "valeurs distinctes")
e := sp.SharedPtr()
t.check(e.is_null(), "SharedPtr vide")
t.raises(() => e.get(), "NullPointerError", "get vide")
r1 := sp.make_shared(Res("r"), closer)
r1.reset(Res("r2"), closer)
t.eq(log[5], "close r", "reset partagé")
r1.drop()
t.raises(() => sp.make_shared(null), "ArgumentError", "make_shared(null)")
cnt := sp.make_shared(5)
inner_count := sp.with_shared(cnt, (pp) => pp.use_count())
t.eq(inner_count, 2, "with_shared")
t.eq(cnt.use_count(), 1, "with_shared relâche")

# weak
s := sp.make_shared(Res("n"), closer)
w := wp.WeakPtr(s)
t.check(not w.expired(), "pas expiré")
l := w.lock()
t.eq(s.use_count(), 2, "lock prend la propriété")
t.eq(w.use_count(), 2, "use_count weak")
l.drop()
s.drop()
t.check(w.expired(), "expiré")
t.eq(w.lock(), null, "lock expiré")
t.eq(w.peek(), null, "peek expiré")
t.raises(() => w.lock_or_raise(), "ExpiredError", "lock_or_raise")
s2 := sp.make_shared(3)
w2 := wp.downgrade(s2)
t.eq(s2.weak_count(), 1, "weak_count")
t.check(w2.points_to(s2), "points_to")

# reference_count
cb := rc.ControlBlock("v", null)
cb.acquire()
cb.acquire()
t.check(not cb.release(), "release non final")
t.check(cb.release(), "release final")
t.check(not cb.alive(), "détruit")
t.raises(() => cb.release(), "OwnershipError", "release sous zéro")
zero := [0]
c := rc.Counter(1, () => zero.clear())
c.retain()
t.check(not c.release(), "Counter release")
t.check(c.release(), "Counter zéro")
t.raises(() => c.retain(), "OwnershipError", "retain après zéro")

# ownership
tok := own.Owned("jeton", "jeton")
t.eq(tok.take(), "jeton", "take")
t.raises(() => tok.get(), "OwnershipError", "get après take")
t.check(not tok.is_owned(), "is_owned")
o2 := own.Owned([1])
func try_take(val):
    try:
        o2.take()
        return "pris"
    catch e2:
        return e2.type
t.eq(o2.borrow(try_take), "OwnershipError", "take pendant emprunt")
t.eq(o2.move().get(), [1], "move")
own.using(Res("u"), (r) => r.name)
t.eq(log[len(log) - 1], "close u", "using")
order := []
bag := own.DisposeBag()
bag.defer(() => append(order, 1))
bag.defer(() => append(order, 2))
bag.add(Res("bag"))
bag.dispose()
t.eq(order, [2, 1], "ordre inverse")
t.eq(log[len(log) - 1], "close bag", "ressource du sac")
bag2 := own.DisposeBag()
bag2.defer(() => raise("IoError", "x"))
bag2.defer(() => append(order, 3))
t.raises(() => bag2.dispose(), "DisposeError", "erreurs collectées")
t.eq(order[2], 3, "les autres libérations ont lieu")
func work(sc):
    sc.add(Res("s1"))
    sc.add(Res("s2"))
    return 42
t.eq(own.scope(work), 42, "scope")
t.eq(log[len(log) - 2:], ["close s2", "close s1"], "scope ordre")

# façade
uu := smp.make_unique(1)
ss := smp.make_shared(2)
ww := smp.make_weak(ss)
t.eq([smp.kind(uu), smp.kind(ss), smp.kind(ww), smp.kind(5)], ["unique", "shared", "weak", null], "kind")
t.eq(smp.deref(ww), 2, "deref weak")
smp.drop(ss)
t.check(ww.expired(), "drop façade")

t.summary("smart_pointer")
