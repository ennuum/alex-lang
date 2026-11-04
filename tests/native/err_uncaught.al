func deep(n: int) -> int:
    if n == 0:
        raise("Boom", "explosion")
    return deep(n - 1)
try:
    deep(2)
catch Other as e:
    print("jamais")
