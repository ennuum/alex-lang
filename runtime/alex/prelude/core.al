
# ALEX STANDARD LIBRARY — core
#
use core

# Couche pure ALEX du module core.
# Les primitives runtime (type, len, hash, conversions et is_*)
# restent natives dans core.cpp. Tout le reste de ce fichier est ALEX pur.

# -----------------------------------------------------------------------------
# Général
# -----------------------------------------------------------------------------

func identity(value):
    return value

func default_value(value, fallback):
    if core.is_null(value):
        return fallback
    return value

func clamp(value, minimum, maximum):
    if minimum > maximum:
        raise("ValueError", "clamp() : minimum doit être <= maximum")

    if value < minimum:
        return minimum

    if value > maximum:
        return maximum

    return value

func between(value, minimum, maximum):
    return value >= minimum and value <= maximum

func in_range(value, minimum, maximum):
    return between(value, minimum, maximum)

func sign(value):
    if value < 0:
        return -1
    if value > 0:
        return 1
    return 0

func is_zero(value):
    return value == 0

func is_nonzero(value):
    return value != 0

func is_positive(value):
    return value > 0

func is_negative(value):
    return value < 0

# -----------------------------------------------------------------------------
# Prédicats composés
# -----------------------------------------------------------------------------

func is_number(value):
    return core.is_int(value) or core.is_float(value)

func is_numeric(value):
    return is_number(value)

func is_sequence(value):
    return core.is_str(value) or core.is_list(value) or core.is_tuple(value)

func is_collection(value):
    return core.is_list(value) or core.is_tuple(value) or core.is_dict(value)

func is_callable(value):
    return core.is_function(value)

func is_not_null(value):
    return not core.is_null(value)

func is_truthy(value):
    return core.to_bool(value)

func is_falsy(value):
    return not core.to_bool(value)

# -----------------------------------------------------------------------------
# Nombres fondamentaux
# -----------------------------------------------------------------------------

func min2(a, b):
    if a < b:
        return a
    return b

func max2(a, b):
    if a > b:
        return a
    return b

func min3(a, b, c):
    result := a
    if b < result:
        result = b
    if c < result:
        result = c
    return result

func max3(a, b, c):
    result := a
    if b > result:
        result = b
    if c > result:
        result = c
    return result

func is_even(value):
    return value % 2 == 0

func is_odd(value):
    return value % 2 != 0

func abs_integer(value):
    if value < 0:
        return 0 - value
    return value

func gcd(a, b):
    a = abs_integer(a)
    b = abs_integer(b)

    while b != 0:
        remainder := a % b
        a = b
        b = remainder

    return a

func lcm(a, b):
    if a == 0 or b == 0:
        return 0
    return abs_integer((a // gcd(a, b)) * b)

func sum_range(start, stop):
    total := 0
    current := start

    while current <= stop:
        total = total + current
        current = current + 1

    return total

# -----------------------------------------------------------------------------
# Séquences
# -----------------------------------------------------------------------------

func core_contains(sequence, value):
    i := 0
    while i < core.len(sequence):
        if sequence[i] == value:
            return true
        i = i + 1
    return false

func index_of(sequence, value):
    i := 0
    while i < core.len(sequence):
        if sequence[i] == value:
            return i
        i = i + 1
    return -1

func core_count(sequence, value):
    result := 0
    i := 0

    while i < core.len(sequence):
        if sequence[i] == value:
            result = result + 1
        i = i + 1

    return result

func first(sequence, fallback=null):
    if core.len(sequence) == 0:
        return fallback
    return sequence[0]

func last(sequence, fallback=null):
    size := core.len(sequence)
    if size == 0:
        return fallback
    return sequence[size - 1]

func is_empty(value):
    return core.len(value) == 0

func is_not_empty(value):
    return core.len(value) != 0

func all_equal(sequence, value):
    i := 0
    while i < core.len(sequence):
        if sequence[i] != value:
            return false
        i = i + 1
    return true

func any_equal(sequence, value):
    i := 0
    while i < core.len(sequence):
        if sequence[i] == value:
            return true
        i = i + 1
    return false

func all(sequence):
    i := 0
    while i < core.len(sequence):
        if not core.to_bool(sequence[i]):
            return false
        i = i + 1
    return true

func any(sequence):
    i := 0
    while i < core.len(sequence):
        if core.to_bool(sequence[i]):
            return true
        i = i + 1
    return false

func copy_list(sequence):
    result := []
    i := 0

    while i < core.len(sequence):
        __list_append(result, sequence[i])
        i = i + 1

    return result

func reversed_copy(sequence):
    result := []
    i := core.len(sequence) - 1

    while i >= 0:
        __list_append(result, sequence[i])
        i = i - 1

    return result

