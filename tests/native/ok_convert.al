# Conversions de chaînes : to_int comme std::stoll, to_float arrondi correct comme std::stod (VM).
from core use to_float, to_int
print(to_int("42"), to_int(" -7"), to_int("+3"), to_int("-9223372036854775808"), to_float("-0"), to_float("  .5e-3"))
print(to_float("1.7976931348623157e308"), to_float("2.5E+2"), to_float("007.50"))
print(to_float("0.1") + to_float("0.2"), to_float("123456789012345678901234567890e-10"), to_float("4.35"), to_float("nan"), to_float("-INF"))
print(to_int("0012") + 1, to_float("1e22") == 10000000000000000000000.0)
