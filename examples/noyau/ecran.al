# Écran texte VGA (80 x 25, mémoire 0xB8000) : écriture, défilement, couleurs, curseur matériel.
use hw
from collections use contains_key
from string use ord

const VGA := 753664
const COLS := 80
const ROWS := 25
# Lettres accentuées -> page de code 437 de l'écran.
CP437: dict[char, int] := {'é': 130, 'â': 131, 'à': 133, 'ç': 135, 'ê': 136, 'è': 138, 'î': 140, 'É': 144, 'ô': 147, 'ù': 151}

class Screen:
    row: int := 0
    col: int := 0
    attr: int := 31 # blanc sur bleu

    func clear():
        i := 0
        while i < COLS * ROWS:
            hw.poke16(VGA + 2 * i, 32 + (self.attr << 8))
            i += 1
        self.row = 0
        self.col = 0
        self.cursor()

    func color(fg: int, bg: int):
        self.attr = fg + (bg << 4)

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
        else:
            n := ord(c)
            if n > 126:
                n = 63
                if contains_key(CP437, c):
                    n = CP437[c]
            hw.poke16(VGA + 2 * (self.row * COLS + self.col), n + (self.attr << 8))
            self.col += 1
            if self.col == COLS:
                self.newline()
        self.cursor()

    # Efface le caractère précédent (retour arrière).
    func back():
        if self.col > 0:
            self.col -= 1
            hw.poke16(VGA + 2 * (self.row * COLS + self.col), 32 + (self.attr << 8))
            self.cursor()

    func write(s: str):
        for c in s:
            self.put(c)

    # Ligne à l'écran, copiée sur le port série.
    func line(s: str):
        self.write(s + "\n")
        print(s)

    # Curseur matériel du contrôleur CRT (ports 0x3D4 / 0x3D5).
    func cursor():
        pos := self.row * COLS + self.col
        hw.outb(980, 15)
        hw.outb(981, pos & 255)
        hw.outb(980, 14)
        hw.outb(981, (pos >> 8) & 255)
