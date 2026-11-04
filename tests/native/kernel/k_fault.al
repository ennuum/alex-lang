# Sans OS : un défaut de page devient une erreur avec trace (fonction et ligne fautives).
use hw
func read_far(addr: int) -> int:
    return hw.peek64(addr)
print("avant")
print(read_far(17179869184)) # 16 Gio : hors de la mémoire en correspondance
print("jamais")
