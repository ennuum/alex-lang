# Index hors limites sur un tuple (index variable) : IndexError avec la taille, comme la VM.
func pick(t: tuple[int, int, int], i: int) -> int:
    return t[i]
print(pick((1, 2, 3), 2))
print(pick((1, 2, 3), 3))
