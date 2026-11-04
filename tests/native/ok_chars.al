# Caractères : s[i] et for c in s donnent des char (point de code), comme la VM.
from collections use contains_key
s := "héllo"
c := s[1]
print(c)
print(c == 'é', c == "é", s[0] == 'h')
for ch in "ab":
    print(ch, ch == 'a')
print('x')
print(str('x') + "y")
print('a' < 'b')
x := 'z'
print(f"{x}!")
l := ['a', 'b']
print(l)
count := 0
for ch in "été, ça va ? 😀":
    if ch == 'é' or ch == 'ç':
        count += 1
print(count, '😀', "😀"[0] == '😀')
d: dict[char, int] := {}
for ch in "abracadabra":
    if contains_key(d, ch):
        d[ch] += 1
    else:
        d[ch] = 1
print(d)
match 'b':
    'a':
        print("a")
    'b':
        print("b")
