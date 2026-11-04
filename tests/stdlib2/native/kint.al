use interrupt.interrupt_vector as iv
use interrupt.interrupt_affinity as ia
use interrupt.interrupt_errors as ierr
a := iv.VectorAllocator(80, 223)
print(a.allocate("x"))
print(a.allocate_block(4, "y"))
print(iv.describe(46))
print(ierr.describe_exception(14, 6))
s := ia.parse("0-3,6")
print(s.format())
t := ia.AffinityTable(4)
t.spread([40, 41])
c: dict[int, int] := {40: 9, 41: 3}
t.balance(c)
print(t.report())
