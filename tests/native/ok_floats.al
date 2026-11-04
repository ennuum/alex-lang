# Flottants : arithmétique, mélange int/float, comparaisons (NaN), affichage %.15g, conversions.
from core use to_int, to_float
z := 0.0
big := 1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
inf := big * big
nan := inf - inf
print(z, -z, 0.0 * -1.0, inf, -inf, nan)
print(nan == nan, nan != nan, nan < 1.0, nan >= 1.0, 1.0 < inf)
print(0.1 + 0.2, 1.0 / 3.0, 2.0 / 3.0, 100.0, 1234567.0, 0.0001, 0.00001)
print(123456789012345.0, 1234567890123456.0, 99999999999999.95, 999999999999999.5)
print(7 / 2, 7 // 2.0, -7 // 2.0, 7.5 % 2, -7.5 % 2, 7.5 % -2, 5 % 2.5)
print(3 == 3.0, 3 < 3.5, 2.5 > 2, 1 + 0.5, 2 * 1.5, 10 - 0.25)
print(to_int(2.9), to_int(-2.9), to_int(1.0), to_float(7), to_float(-3))
print(not 0.0, not 0.5)
if 0.0:
    print("faux")
x := 1.0
i := 0
while i < 60:
    x = x * 2.0
    i += 1
print(x, x + 1.0, to_int(x))
func area(r: float) -> float:
    return 3.141592653589793 * r * r
print(area(2.0), area(0.5))
total := 0.0
for k in 1..1000:
    total += 1.0 / to_float(k * k)
print(total)
