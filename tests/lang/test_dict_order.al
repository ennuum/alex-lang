# Dictionnaires : itération dans l'ordre d'insertion (docs/RUNTIME.md, D3).
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/lang/test_dict_order.al
from collections use keys, values, remove, append
use core
use json

failures := []
func check(cond, label):
    if cond:
        print("ok   " + label)
    else:
        print("ÉCHEC " + label)
        append(failures, label)

d := {"zèbre": 1, "abeille": 2, "mouton": 3, "chat": 4}
check(keys(d) == ["zèbre", "abeille", "mouton", "chat"], "littéral : ordre d'écriture")
check(values(d) == [1, 2, 3, 4], "values() dans le même ordre")

order := []
for k in d:
    append(order, k)
check(order == ["zèbre", "abeille", "mouton", "chat"], "for k in d")

d["abeille"] = 20
check(keys(d) == ["zèbre", "abeille", "mouton", "chat"], "réaffectation : position conservée")
d["ane"] = 5
check(keys(d)[4] == "ane", "nouvelle clé ajoutée à la fin")

remove(d, "mouton")
check(keys(d) == ["zèbre", "abeille", "chat", "ane"], "suppression : ordre des autres conservé")
d["mouton"] = 3
check(keys(d)[4] == "mouton", "clé réinsérée : à la fin")

big := {}
i := 0
while i < 1000:
    big[i] = i * i
    i += 1
i = 0
while i < 1000:
    if i % 3 != 0:
        remove(big, i)
    i += 1
i = 1000
while i < 1100:
    big[i] = 0
    i += 1
ks := keys(big)
ok := core.len(ks) == 434 and ks[0] == 0 and ks[1] == 3 and ks[333] == 999 and ks[334] == 1000 and ks[433] == 1099
check(ok, "1000 insertions, 666 suppressions, 100 ajouts : ordre et taille")
check(big[999] == 998001 and big[3] == 9, "valeurs intactes après compactage")

squares := {x: x * x for x in [5, 1, 4]}
check(keys(squares) == [5, 1, 4], "compréhension de dict")
check(json.stringify({"b": 1, "a": 2}, null, false) == "{\"b\":1,\"a\":2}", "json.stringify(sort_keys=false) suit l'ordre d'insertion")
check(keys(json.parse("{\"z\": 1, \"a\": 2}")) == ["z", "a"], "json.parse conserve l'ordre du texte")
check({"a": 1, "b": 2} == {"b": 2, "a": 1}, "égalité indépendante de l'ordre")

if core.len(failures) > 0:
    raise("TestFailure", str(core.len(failures)) + " vérification(s) en échec")
print("test_dict_order : toutes les vérifications passent")
