# print : entiers, booléens, chaînes (UTF-8), plusieurs arguments, ligne vide.
greeting := "Bonjour, monde"
print(greeting)
print("é à ü — ✓ 日本")
print()
print("a", 1, true, "b")
print("")
flag := false
flag = not flag
print(flag)
s: str := "annoté"
print(s)
func pick(b: bool) -> str:
    return "oui" if b else "non"
print(pick(true), pick(false))
i := 0
while i < 20000:
    print(i)
    i += 1
