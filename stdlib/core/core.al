# ALEX STANDARD LIBRARY — core
#
use _native_core as _core_native

# Couche pure ALEX du module _core_native.
# Les primitives runtime (type, len, hash, conversions et is_*)
# restent natives dans _core_native.cpp. Tout le reste de ce fichier est ALEX pur.

# -----------------------------------------------------------------------------
# Général
# -----------------------------------------------------------------------------
# Runtime primitives exposed through the public ALEX core API.
func type(value):
    return _core_native.type(value)
func len(value):
    return __len(value) # opcode LEN : list/tuple/str/dict, ou la méthode __len__ d'une instance
func hash(value):
    return _core_native.hash(value)
func to_int(value):
    return _core_native.to_int(value)

# Conversions vers les entiers dimensionnés : réduction modulo 2^n (complément à deux pour les signés).
func to_i8(value: int) -> i8:
    return _core_native.wrap_int(value, 8, true)
func to_i16(value: int) -> i16:
    return _core_native.wrap_int(value, 16, true)
func to_i32(value: int) -> i32:
    return _core_native.wrap_int(value, 32, true)
func to_u8(value: int) -> u8:
    return _core_native.wrap_int(value, 8, false)
func to_u16(value: int) -> u16:
    return _core_native.wrap_int(value, 16, false)
func to_u32(value: int) -> u32:
    return _core_native.wrap_int(value, 32, false)
func to_u64(value: int) -> u64:
    return _core_native.wrap_int(value, 64, false)
func to_float(value):
    return _core_native.to_float(value)
func to_bool(value):
    return _core_native.to_bool(value)
func is_null(value):
    return _core_native.is_null(value)
func is_int(value):
    return _core_native.is_int(value)
func is_float(value):
    return _core_native.is_float(value)
func is_bool(value):
    return _core_native.is_bool(value)
func is_str(value):
    return _core_native.is_str(value)
func is_list(value):
    return _core_native.is_list(value)
func is_dict(value):
    return _core_native.is_dict(value)
func is_tuple(value):
    return _core_native.is_tuple(value)
func is_function(value):
    return _core_native.is_function(value)
# [minimum, maximum] d'arguments d'une fonction Alex (méthode liée : sans self) ; null pour une fonction native.
func arity(f):
    return _core_native.arity(f)


func identity(value):
    return value

func default_value(value, fallback):
    if _core_native.is_null(value):
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
    return _core_native.is_int(value) or _core_native.is_float(value)

func is_numeric(value):
    return is_number(value)

func is_sequence(value):
    return _core_native.is_str(value) or _core_native.is_list(value) or _core_native.is_tuple(value)

func is_collection(value):
    return _core_native.is_list(value) or _core_native.is_tuple(value) or _core_native.is_dict(value)

func is_callable(value):
    return _core_native.is_function(value)

func is_not_null(value):
    return not _core_native.is_null(value)

func is_truthy(value):
    return _core_native.to_bool(value)

func is_falsy(value):
    return not _core_native.to_bool(value)

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
    while i < _core_native.len(sequence):
        if sequence[i] == value:
            return true
        i = i + 1
    return false

func index_of(sequence, value):
    i := 0
    while i < _core_native.len(sequence):
        if sequence[i] == value:
            return i
        i = i + 1
    return -1

func core_count(sequence, value):
    result := 0
    i := 0

    while i < _core_native.len(sequence):
        if sequence[i] == value:
            result = result + 1
        i = i + 1

    return result

func first(sequence, fallback=null):
    if _core_native.len(sequence) == 0:
        return fallback
    return sequence[0]

func last(sequence, fallback=null):
    size := _core_native.len(sequence)
    if size == 0:
        return fallback
    return sequence[size - 1]

func is_empty(value):
    return _core_native.len(value) == 0

func is_not_empty(value):
    return _core_native.len(value) != 0

func all_equal(sequence, value):
    i := 0
    while i < _core_native.len(sequence):
        if sequence[i] != value:
            return false
        i = i + 1
    return true

func any_equal(sequence, value):
    i := 0
    while i < _core_native.len(sequence):
        if sequence[i] == value:
            return true
        i = i + 1
    return false

func all(sequence):
    i := 0
    while i < _core_native.len(sequence):
        if not _core_native.to_bool(sequence[i]):
            return false
        i = i + 1
    return true

func any(sequence):
    i := 0
    while i < _core_native.len(sequence):
        if _core_native.to_bool(sequence[i]):
            return true
        i = i + 1
    return false

func copy_list(sequence):
    result := []
    i := 0

    while i < _core_native.len(sequence):
        __list_append(result, sequence[i])
        i = i + 1

    return result

func reversed_copy(sequence):
    result := []
    i := _core_native.len(sequence) - 1

    while i >= 0:
        __list_append(result, sequence[i])
        i = i - 1

    return result
