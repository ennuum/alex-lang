# Fonctions d'octets du module string : même résultat en VM et en natif (données binaires, UTF-8 non interprété).
from string use byte_len, byte_at, byte_slice, byte_find, byte_char, byte_pack, byte_unpack, byte_join, find
from core use len

s := "héllo"
print(str(len(s)) + " points de code, " + str(byte_len(s)) + " octets")
print(str(byte_at(s, 1)) + " " + str(byte_at(s, 2)))
print(byte_slice(s, 0, 1) + "|" + byte_slice(s, 3, 99) + "|" + byte_slice(s, 4, 2) + "|")
print(str(byte_find(s, "l")) + " " + str(byte_find(s, "l", 4)) + " " + str(byte_find(s, "z")) + " " + str(find(s, "l")))
b := byte_pack([0, 1, 127, 128, 255, 256, -1])
print(str(byte_len(b)) + " octets : " + str(byte_unpack(b)))
z := byte_char(0) + byte_char(200) + byte_char(65)
print(str(byte_len(z)) + " " + str(byte_at(z, 0)) + " " + str(byte_at(z, 1)) + " " + byte_slice(z, 2, 3))
parts: list[str] := ["ab", "", byte_char(10), "cd"]
j := byte_join(parts)
print(str(byte_len(j)) + " " + str(byte_unpack(j)))
total := 0
for v in byte_unpack(byte_join(["x", byte_pack([1, 2, 3])])):
    total += v
print("somme " + str(total))
