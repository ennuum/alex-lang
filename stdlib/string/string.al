# ALEX STANDARD LIBRARY — string
# Public string API. Implementation is ALEX; UTF-8 primitives live in the runtime.
# Annotations (docs/TYPES.md) : scalaires précis ; conteneurs non paramétrés (pas de marquage des listes de l'appelant).

use _native_string as _string_native

func upper(s: str) -> str:
    return _string_native.upper(s)

func lower(s: str) -> str:
    return _string_native.lower(s)

func capitalize(s: str) -> str:
    return _string_native.capitalize(s)

func title(s: str) -> str:
    return _string_native.title(s)

func trim(s: str) -> str:
    return _string_native.trim(s)

func strip(s: str) -> str:
    return _string_native.strip(s)

func count(s: str, sub: str) -> int:
    return _string_native.count(s, sub)

func repeat(s: str, n: int) -> str:
    return _string_native.repeat(s, n)

func find(s: str, sub: str) -> int:
    return _string_native.find(s, sub)

func substring(s: str, start: int, end: int) -> str:
    return _string_native.substring(s, start, end)

func split(s: str, sep: str) -> list:
    return _string_native.split(s, sep)

func join(sep: str, values: list) -> str:
    return _string_native.join(sep, values)

func replace(s: str, old: str, new: str) -> str:
    return _string_native.replace(s, old, new)

func starts_with(s: str, prefix: str) -> bool:
    return _string_native.starts_with(s, prefix)

func ends_with(s: str, suffix: str) -> bool:
    return _string_native.ends_with(s, suffix)

func contains(s: str, sub: str) -> bool:
    return _string_native.contains(s, sub)

# chr(code) -> char : le caractère de point de code `code` (0..0x10FFFF, hors substituts).
func chr(code: int) -> char:
    return _string_native.chr(code)

# ord(c) -> int : point de code d'un char (ou d'une str d'un seul caractère).
func ord(c) -> int:
    return _string_native.ord(c)

# slice(s, start=null, stop=null, step=1) : s[start:stop:step] en points de code.
# Indices négatifs acceptés, bornes hors limites ramenées dans la chaîne, pas négatif = à l'envers.
func slice(s: str, start: int? = null, stop: int? = null, step: int = 1) -> str:
    return _string_native.slice(s, start, stop, step)

# ---- accès aux octets (données binaires : réseau, fichiers, cryptographie) ----
# Les fonctions précédentes comptent en points de code UTF-8 ; celles-ci en octets, sans interprétation.

# Nombre d'octets de s.
func byte_len(s: str) -> int:
    return _string_native.byte_len(s)

# Octet n° i de s (0 à 255) ; IndexError hors limites.
func byte_at(s: str, i: int) -> int:
    return _string_native.byte_at(s, i)

# Octets [start, end) de s (bornes ramenées dans la chaîne).
func byte_slice(s: str, start: int, end: int) -> str:
    return _string_native.byte_slice(s, start, end)

# Position en octets de sub dans s à partir de l'octet start, ou -1.
func byte_find(s: str, sub: str, start: int = 0) -> int:
    return _string_native.byte_find(s, sub, start)

# Chaîne d'un seul octet de valeur n (0 à 255), y compris 0 et les valeurs supérieures à 127.
func byte_char(n: int) -> str:
    return _string_native.byte_char(n)

# Chaîne dont les octets sont les valeurs de l (chacune ramenée à 0..255).
func byte_pack(l: list) -> str:
    return _string_native.byte_pack(l)

# Liste des octets de s (valeurs 0 à 255).
func byte_unpack(s: str) -> list:
    return _string_native.byte_unpack(s)

# Concaténation de parts en une seule allocation (temps linéaire).
func byte_join(parts: list) -> str:
    return _string_native.byte_join(parts)
