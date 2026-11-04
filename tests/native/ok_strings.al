# Chaînes : concaténation, str(), comparaison octet par octet, len et indexation en caractères, for, f-strings.
from core use len
s := "héllo"
t := s + ", " + "wörld"
print(t, len(t), len(""), s[1], s[0], t[len(t) - 1])
print("abc" == "abc", "abc" != "abd", "b" < "a", "é" > "z", "ab" < "abc", "" < "a")
print(str(42) + str(-7) + str(2.5) + str(true) + str(false))
n := 0
for c in "a€b":
    print(c)
    n += 1
print(n)
name := "Alex"
v := 3.5
print(f"bonjour {name}, v={v}, n={n}, ok={n == 3}, liste={[1, 2]}")
acc := ""
for i in 0..5:
    acc = acc + str(i)
print(acc)
func greet(who: str, excl: bool = false) -> str:
    if excl:
        return "Salut " + who + " !"
    return "Salut " + who
print(greet("monde"), greet("toi", true))
empty := ""
if empty:
    print("faux")
if s:
    print("non vide")
