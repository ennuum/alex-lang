# Annotations vérifiées et entiers dimensionnés (débordement borné à l'exécution).
func mix(a: u8, b: u8) -> u8:
    return a + b

func neg(v: i16) -> i16:
    return -v

x: u8 := 200
y: u8 := 50
print(mix(x, y))
print(neg(1234))
z: i32 := 1000
z = z * 1000
print(z)
lst: list[int] := [1, 2, 3]
name: str? := null
if name == null:
    name = "anonyme"
print(name, lst)
try:
    print(mix(x, 100))
catch TypeError as e:
    print("débordement détecté")
total: u32 := 0
for i in 0..10:
    total += i
print(total)
