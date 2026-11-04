# Petit harnais commun aux tests de tests/stdlib2 : compte les vérifications et affiche
# « <nom> : N OK, M échecs » (format attendu par tests/run_checked.sh).
from core use len, type
from collections use append

stats := [0, 0]
notes := []

func check(cond, label):
    if cond:
        stats[0] += 1
    else:
        stats[1] += 1
        append(notes, label)

func eq(a, b, label):
    if a == b:
        stats[0] += 1
    else:
        stats[1] += 1
        append(notes, label + " : obtenu " + str(a) + ", attendu " + str(b))

func raises(f, kind, label):
    try:
        f()
        stats[1] += 1
        append(notes, label + " (aucune erreur, " + kind + " attendue)")
    catch e:
        if e.type == kind:
            stats[0] += 1
        else:
            stats[1] += 1
            append(notes, label + " : " + e.type + " (" + e.message + "), " + kind + " attendue")

func summary(name):
    for n in notes:
        print("ÉCHEC " + n)
    print(name + " : " + str(stats[0]) + " OK, " + str(stats[1]) + " échecs")
    return stats[1]
