from collections use append
from core use len

func _blen(s: str) -> int:
    return __load64(__str_addr(s))

func _bytes(s: str) -> int:
    return __str_addr(s) + 8

func _make(p: int, n: int) -> str:
    r := __rt_str_new(n)
    __copy(r + 8, p, n)
    return __as_str(r)

# Position en octets de `sub` dans s à partir de l'octet `start`, ou -1.
func _find_from(s: str, sub: str, start: int) -> int:
    p := _bytes(s)
    n := _blen(s)
    q := _bytes(sub)
    m := _blen(sub)
    i := start
    while i + m <= n:
        j := 0
        while j < m and __load8(p + i + j) == __load8(q + j):
            j += 1
        if j == m:
            return i
        i += 1
    return -1

# Nombre de points de code dans les n premiers octets en p.
func _cps(p: int, n: int) -> int:
    k := 0
    i := 0
    while i < n:
        if (__load8(p + i) & 192) != 128:
            k += 1
        i += 1
    return k

# Décalage en octets du point de code k (n octets au total ; n si k est la longueur).
func _offset(p: int, n: int, k: int) -> int:
    count := 0
    i := 0
    while i < n:
        if (__load8(p + i) & 192) != 128:
            if count == k:
                return i
            count += 1
        i += 1
    return n

func _map_ascii(s: str, mode: int) -> str:
    n := _blen(s)
    p := _bytes(s)
    r := __rt_str_new(n)
    first := true
    start_word := true
    i := 0
    while i < n:
        c := __load8(p + i)
        if c < 128:
            space := c == 32 or c == 9 or c == 10 or c == 13
            up := false
            low := false
            if mode == 0:
                up = true
            elif mode == 1:
                low = true
            elif mode == 2:
                up = first
                low = not first
            else:
                up = start_word and not space
                low = not start_word and not space
            if up and c >= 97 and c <= 122:
                c -= 32
            elif low and c >= 65 and c <= 90:
                c += 32
            start_word = space
        else:
            start_word = false
        first = false
        __store8(r + 8 + i, c)
        i += 1
    return __as_str(r)

func upper(s: str) -> str:
    return _map_ascii(s, 0)

func lower(s: str) -> str:
    return _map_ascii(s, 1)

func capitalize(s: str) -> str:
    return _map_ascii(s, 2)

func title(s: str) -> str:
    return _map_ascii(s, 3)

func _is_ws(c: int) -> bool:
    return c == 32 or c == 9 or c == 10 or c == 13

func trim(s: str) -> str:
    p := _bytes(s)
    a := 0
    b := _blen(s)
    while a < b and _is_ws(__load8(p + a)):
        a += 1
    while b > a and _is_ws(__load8(p + b - 1)):
        b -= 1
    return _make(p + a, b - a)

func strip(s: str) -> str:
    return trim(s)

func count(s: str, sub: str) -> int:
    if _blen(sub) == 0:
        raise("ArgumentError", "count(...) : la sous-chaîne ne peut pas être vide")
    n := 0
    i := _find_from(s, sub, 0)
    while i >= 0:
        n += 1
        i = _find_from(s, sub, i + _blen(sub))
    return n

func repeat(s: str, n: int) -> str:
    if n < 0:
        raise("ArgumentError", "repeat(...) : n doit être >= 0")
    m := _blen(s)
    r := __rt_str_new(m * n)
    i := 0
    while i < n:
        __copy(r + 8 + i * m, _bytes(s), m)
        i += 1
    return __as_str(r)

func find(s: str, sub: str) -> int:
    if _blen(sub) == 0:
        return 0
    i := _find_from(s, sub, 0)
    if i < 0:
        return -1
    return _cps(_bytes(s), i)

func substring(s: str, start: int, end: int) -> str:
    p := _bytes(s)
    n := _blen(s)
    total := _cps(p, n)
    if start < 0 or end < start or end > total:
        raise("IndexError", "substring(" + str(start) + ", " + str(end) + ") hors limites (longueur " + str(total) + ", §10)")
    a := _offset(p, n, start)
    b := _offset(p, n, end)
    return _make(p + a, b - a)

func split(s: str, sep: str) -> list[str]:
    if _blen(sep) == 0:
        raise("ArgumentError", "split(...) : le séparateur ne peut pas être vide")
    out: list[str] := []
    start := 0
    while true:
        pos := _find_from(s, sep, start)
        if pos < 0:
            append(out, _make(_bytes(s) + start, _blen(s) - start))
            return out
        append(out, _make(_bytes(s) + start, pos - start))
        start = pos + _blen(sep)
    return out

func join(sep: str, values: list[str]) -> str:
    sb := __rt_sb_new()
    i := 0
    for v in values:
        if i > 0:
            __rt_sb_add(sb, sep)
        __rt_sb_add(sb, v)
        i += 1
    return __rt_sb_str(sb)

func replace(s: str, old: str, new: str) -> str:
    if _blen(old) == 0:
        raise("ArgumentError", "replace(...) : la sous-chaîne à remplacer ne peut pas être vide")
    sb := __rt_sb_new()
    start := 0
    while true:
        pos := _find_from(s, old, start)
        if pos < 0:
            __rt_sb_add(sb, _make(_bytes(s) + start, _blen(s) - start))
            return __rt_sb_str(sb)
        __rt_sb_add(sb, _make(_bytes(s) + start, pos - start))
        __rt_sb_add(sb, new)
        start = pos + _blen(old)
    return s

func starts_with(s: str, prefix: str) -> bool:
    m := _blen(prefix)
    if m > _blen(s):
        return false
    i := 0
    while i < m:
        if __load8(_bytes(s) + i) != __load8(_bytes(prefix) + i):
            return false
        i += 1
    return true

func ends_with(s: str, suffix: str) -> bool:
    m := _blen(suffix)
    n := _blen(s)
    if m > n:
        return false
    i := 0
    while i < m:
        if __load8(_bytes(s) + n - m + i) != __load8(_bytes(suffix) + i):
            return false
        i += 1
    return true

func contains(s: str, sub: str) -> bool:
    return _blen(sub) == 0 or _find_from(s, sub, 0) >= 0

func chr(code: int) -> char:
    if code < 0 or code > 1114111 or (code >= 55296 and code <= 57343):
        raise("ValueError", "chr(" + str(code) + ") : point de code Unicode invalide")
    return __code_char(code)

func ord(c: char) -> int:
    return __char_code(c)

func slice(s: str, start: int? = null, stop: int? = null, step: int = 1) -> str:
    if step == 0:
        raise("ValueError", "slice(...) : le pas ne peut pas être nul")
    chars: list[char] := []
    for ch in s:
        append(chars, ch)
    n := len(chars)
    lo := 0
    hi := n
    if step < 0:
        lo = -1
        hi = n - 1
    b := lo
    e := hi
    if step < 0:
        b = hi
        e = lo
    if start != null:
        b = start
        if b < 0:
            b += n
            if b < lo:
                b = lo
        elif b > hi:
            b = hi
    if stop != null:
        e = stop
        if e < 0:
            e += n
            if e < lo:
                e = lo
        elif e > hi:
            e = hi
    sb := __rt_sb_new()
    i := b
    if step > 0:
        while i < e:
            __rt_sb_add(sb, str(chars[i]))
            i += step
    else:
        while i > e:
            __rt_sb_add(sb, str(chars[i]))
            i += step
    return __rt_sb_str(sb)

# ---- accès aux octets (données binaires : réseau, fichiers) ----
# Les fonctions précédentes comptent en points de code UTF-8 ; celles-ci en octets, sans interprétation.

# Nombre d'octets de s.
func byte_len(s: str) -> int:
    return _blen(s)

# Octet n° i de s (0 à 255).
func byte_at(s: str, i: int) -> int:
    if i < 0 or i >= _blen(s):
        raise("IndexError", "byte_at(" + str(i) + ") hors limites (" + str(_blen(s)) + " octets)")
    return __load8(_bytes(s) + i)

# Octets [start, end) de s (bornes ramenées dans la chaîne).
func byte_slice(s: str, start: int, end: int) -> str:
    n := _blen(s)
    a := start
    b := end
    if a < 0:
        a = 0
    if b > n:
        b = n
    if b <= a:
        return ""
    return _make(_bytes(s) + a, b - a)

# Position en octets de sub dans s à partir de l'octet start, ou -1.
func byte_find(s: str, sub: str, start: int = 0) -> int:
    if start < 0:
        return _find_from(s, sub, 0)
    return _find_from(s, sub, start)

# Chaîne d'un seul octet de valeur n (0 à 255), y compris 0 et les valeurs supérieures à 127.
func byte_char(n: int) -> str:
    r := __rt_str_new(1)
    __store8(r + 8, n & 255)
    return __as_str(r)

# Chaîne dont les octets sont les valeurs de l (chacune ramenée à 0..255).
func byte_pack(l: list[int]) -> str:
    n := len(l)
    r := __rt_str_new(n)
    i := 0
    while i < n:
        __store8(r + 8 + i, l[i] & 255)
        i += 1
    return __as_str(r)

# Liste des octets de s (valeurs 0 à 255).
func byte_unpack(s: str) -> list[int]:
    out: list[int] := []
    p := _bytes(s)
    n := _blen(s)
    i := 0
    while i < n:
        append(out, __load8(p + i))
        i += 1
    return out

# Concaténation de parts en une seule allocation (temps linéaire).
func byte_join(parts: list[str]) -> str:
    total := 0
    for x in parts:
        total += _blen(x)
    r := __rt_str_new(total)
    off := 0
    for x in parts:
        m := _blen(x)
        __copy(r + 8 + off, _bytes(x), m)
        off += m
    return __as_str(r)
