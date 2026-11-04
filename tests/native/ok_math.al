# Module math natif : mêmes algorithmes que stdlib/math/math.al, résultats identiques.
use math
from math use sqrt, PI
print(math.sqrt(16.0))
print(sqrt(2.0), math.sqrt(12345.678), math.sqrt(0.0001))
print(math.exp(1.0), math.exp(-3.5), math.exp(10.0))
print(math.floor(2.5), math.ceil(2.5), math.round(-2.5), math.trunc(-2.7))
print(math.sin(1.0), math.cos(1.0), math.tan(0.5), math.atan(0.3), math.atan2(1.0, -1.0))
print(math.sin(100.0), math.cos(-7.25), math.sin(3000000.0))
print(math.abs(-3), math.abs(-2.5), math.min(3, 4), math.max(2.5, 1.0))
print(math.pow(2.0, 0.5), math.pow(2.5, 3.0))
print(math.ln(10.0), math.log10(1000.0), math.log(8.0, 2.0), math.log2(10.0))
print(PI, math.E, math.INF, math.NAN, -math.INF)
print(math.gcd(12, 18), math.lcm(4, 6), math.factorial(10), math.fibonacci(50))
print(math.sign(-2.0), math.clamp(15, 0, 10), math.isnan(math.NAN), math.hypot(3.0, 4.0))
print(math.sinh(1.0), math.cosh(0.5), math.tanh(0.3), math.asin(0.5), math.acos(0.5))
print(math.cbrt(27.0), math.cbrt(-10.0), math.radians(180.0), math.degrees(1.0))
print(math.min3(3, 1, 2), math.max3(1.5, 2.5, 0.5), math.lerp(0.0, 10.0, 0.25))
print(math.floor(-0.5), math.is_even(4), math.is_odd(4))
total := 0.0
for i in 0..50:
    x := i * 0.37 - 9.0
    total += math.sin(x) * math.cos(x / 3.0) + math.exp(x / 10.0) - math.sqrt(math.abs(x))
print(total)
print(math.pow(1.0001, 10000.0), math.ln(0.5), math.atan(5.0))
