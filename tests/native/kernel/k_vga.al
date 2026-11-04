# Sans OS : écran texte VGA (écriture, relecture, défilement), ports (CMOS), mémoire 16/32/64 bits, asm en ligne.
use hw
const VGA := 753664
func put(row: int, col: int, text: str, attr: int):
    i := 0
    for c in text:
        hw.poke16(VGA + 2 * (row * 80 + col + i), 65 + (i % 26) + (attr << 8))
        i += 1
func scroll():
    i := 0
    while i < 80 * 24:
        hw.poke16(VGA + 2 * i, hw.peek16(VGA + 2 * (i + 80)))
        i += 1
for r in 0..25:
    put(r, 0, "ligne", r % 16)
scroll()
print(hw.peek8(VGA), hw.peek8(VGA + 1), hw.peek16(VGA + 2 * 80 * 23 + 2))
base := hw.memory_end() - 4096
hw.poke64(base, -1)
hw.poke32(base, 305419896)
print(hw.peek32(base), hw.peek16(base), hw.peek8(base), hw.peek64(base) == -4294967296 + 305419896)
hw.outb(112, 10) # CMOS registre A : bit 7 = mise à jour en cours, fréquence 0x26 par défaut
print(hw.inb(113) & 127)
x := hw.asm_value("48 c7 c0 2a 00 00 00") # mov rax, 42
hw.asm("90 90") # nop nop
print(x, hw.memory_end() > 64 * 1048576)
