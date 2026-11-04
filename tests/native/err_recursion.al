func down(n: int) -> int:
    return down(n + 1) + 1
print("début")
print(down(0))
