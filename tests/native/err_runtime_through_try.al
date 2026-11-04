func ratio(a: int, b: int) -> int:
    return a // b
func guarded(b: int) -> int:
    try:
        return ratio(10, b)
    catch KeyError:
        return -1
    return 0
print(guarded(2))
print(guarded(0))
