func sign(n: int) -> int:
    if n > 0:
        return 1
    if n < 0:
        return -1
print(sign(5))
print(sign(0))
