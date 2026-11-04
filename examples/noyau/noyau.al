# Mini-noyau Alex : démarre sans système d'exploitation (Multiboot, mode long), écrit sur l'écran texte VGA
# et sur le port série, lit l'horloge CMOS, utilise le ramasse-miettes, les classes, les enums et les
# exceptions.
#
#   alexc build --native --freestanding examples/noyau/noyau.al -o noyau.bin
#   qemu-system-x86_64 -kernel noyau.bin -serial stdio -device isa-debug-exit,iobase=0xf4,iosize=0x04
use hw
from collections use append, contains_key
from core use len
from string use ord

const VGA := 753664 # 0xB8000 : 80 x 25 cellules (caractère, attribut)
const COLS := 80
const ROWS := 25
CP437: dict[char, int] := {'é': 130, 'â': 131, 'à': 133, 'ç': 135, 'ê': 136, 'è': 138, 'î': 140, 'É': 144, 'ô': 147, 'ù': 151}

enum Color:
    Black
    Blue
    Green
    Cyan
    Red
    White

func code(c: Color) -> int:
    match c:
        Color.Black:
            return 0
        Color.Blue:
            return 1
        Color.Green:
            return 2
        Color.Cyan:
            return 3
        Color.Red:
            return 4
        Color.White:
            return 15
    return 7

class Screen:
    row: int := 0
    col: int := 0
    attr: int := 15

    func clear():
        i := 0
        while i < COLS * ROWS:
            hw.poke16(VGA + 2 * i, 32 + (self.attr << 8))
            i += 1
        self.row = 0
        self.col = 0

    func color(fg: Color, bg: Color):
        self.attr = code(fg) + (code(bg) << 4)

    func scroll():
        i := 0
        while i < COLS * (ROWS - 1):
            hw.poke16(VGA + 2 * i, hw.peek16(VGA + 2 * (i + COLS)))
            i += 1
        while i < COLS * ROWS:
            hw.poke16(VGA + 2 * i, 32 + (self.attr << 8))
            i += 1
        self.row = ROWS - 1

    func newline():
        self.col = 0
        self.row += 1
        if self.row == ROWS:
            self.scroll()

    func put(c: char):
        if c == '\n':
            self.newline()
            return
        n := ord(c)
        if n > 126:
            n = 63 # page de code 437 de l'écran VGA ; « ? » si absent
            if contains_key(CP437, c):
                n = CP437[c]
        hw.poke16(VGA + 2 * (self.row * COLS + self.col), n + (self.attr << 8))
        self.col += 1
        if self.col == COLS:
            self.newline()

    func write(s: str):
        for c in s:
            self.put(c)

    func line(s: str):
        self.write(s + "\n")
        print(s) # copie sur le port série

func bcd(v: int) -> int:
    return (v >> 4) * 10 + (v & 15)

func cmos(reg: int) -> int:
    hw.outb(112, reg) # 0x70 : sélection du registre
    return hw.inb(113) # 0x71 : donnée

func primes(n: int) -> list[int]:
    out: list[int] := []
    for k in 2..n:
        prime := true
        for p in out:
            if p * p > k:
                break
            if k % p == 0:
                prime = false
                break
        if prime:
            append(out, k)
    return out

screen := Screen()
screen.color(Color.White, Color.Blue)
screen.clear()
screen.line("Alex : noyau 64 bits démarré sans système d'exploitation")
screen.color(Color.Cyan, Color.Blue)
screen.line(f"mémoire physique : {hw.memory_end() // 1048576} Mio")
h := bcd(cmos(4))
m := bcd(cmos(2))
screen.line(f"horloge CMOS lue : {h >= 0 and h < 24 and m >= 0 and m < 60}")
t0 := hw.asm_value("0f 31 48 c1 e2 20 48 09 d0") # rdtsc : edx:eax -> rax
ps := primes(20000)
t1 := hw.asm_value("0f 31 48 c1 e2 20 48 09 d0")
screen.color(Color.Green, Color.Blue)
screen.line(f"{len(ps)} nombres premiers < 20000, le dernier : {ps[len(ps) - 1]}")
screen.line(f"compteur de cycles croissant : {t1 > t0}")

# Le ramasse-miettes fonctionne aussi sans OS : 300 000 chaînes temporaires.
total := 0
for i in 0..300000:
    s := "objet " + str(i)
    total += len(s)
screen.line(f"octets alloués puis récupérés : {total}")

try:
    raise("NoyauError", "exception levée et rattrapée")
catch e:
    screen.color(Color.Red, Color.Blue)
    screen.line(f"{e.type} : {e.message}")

for i in 0..12:
    screen.write(f"défilement {i}\n")
checksum := 0
i := 0
while i < COLS * ROWS:
    checksum = (checksum * 31 + hw.peek16(VGA + 2 * i)) % 1000000007
    i += 1
print(f"écran : dernière ligne = {hw.peek8(VGA + 2 * COLS * (ROWS - 2))}, empreinte {checksum}")
screen.line("arrêt.")
hw.exit(0)
