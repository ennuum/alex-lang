# ALEX STANDARD LIBRARY — collections
# Public API is ALEX. Native backend is used only for primitive dict operations.

from core use len, type
use _native_collections as _collections_native

func append(l, x):
    __list_append(l, x)

func insert(l, i, x):
    __list_insert(l, i, x)

func clear(l):
    __list_clear(l)

func pop(l, i=null):
    if i == null:
        i = len(l) - 1
    return __list_remove_at(l, i)

func sort(l):
    n := len(l)
    i := 0
    while i < n:
        j := 0
        while j < n - i - 1:
            if l[j] > l[j + 1]:
                tmp := l[j]
                l[j] = l[j + 1]
                l[j + 1] = tmp
            j = j + 1
        i = i + 1

func reverse(l):
    n := len(l)
    i := 0
    while i < n / 2:
        tmp := l[i]
        l[i] = l[n - 1 - i]
        l[n - 1 - i] = tmp
        i = i + 1

func contains(l, x):
    i := 0
    while i < len(l):
        if l[i] == x:
            return true
        i = i + 1
    return false

func index(l, x):
    i := 0
    while i < len(l):
        if l[i] == x:
            return i
        i = i + 1
    return -1

func count(l, x):
    n := 0
    i := 0
    while i < len(l):
        if l[i] == x:
            n = n + 1
        i = i + 1
    return n

func remove(container, x):
    t := type(container)
    if t == "list":
        i := index(container, x)
        if i == -1:
            raise("ArgumentError", "remove(...) : valeur absente de la liste")
        __list_remove_at(container, i)
        return null
    if t == "dict":
        __dict_remove_key(container, x)
        return null
    raise("TypeError", "remove(...) : list ou dict attendu")

func keys(d):
    return _collections_native.keys(d)
func values(d):
    return _collections_native.values(d)
func items(d):
    return _collections_native.items(d)
func get(d, key):
    return _collections_native.get(d, key)
func set(d, key, value):
    if type(d) != "dict":
        return _collections_native.set(d, key, value)
    d[key] = value
    return null
func contains_key(d, key):
    return _collections_native.contains_key(d, key)
