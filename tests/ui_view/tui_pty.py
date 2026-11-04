#!/usr/bin/env python3
"""ui.view dans un vrai terminal : tui.run sous un pseudo-terminal (saisie brute, souris SGR, écran
alternatif, redimensionnement), écran relu par pyte (émulateur de terminal) s'il est installé."""
import os, pty, sys, time, select, struct, fcntl, termios, signal

ALEX = sys.argv[1] if len(sys.argv) > 1 else "./alex"
try:
    import pyte
except ImportError:
    pyte = None

COLS, ROWS = 60, 14
pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
    os.environ["TERM"] = "xterm-256color"
    os.environ["COLORTERM"] = "truecolor"
    os.execv(ALEX, [ALEX, "run", "tests/ui_view/tui_pty_app.al"])

raw = b""
screen = stream = None


class MiniScreen:
    """Émulateur minimal (si pyte manque) : positionnement du curseur CSI H, effacement CSI 2J, texte ;
    les autres séquences (couleurs, modes) sont ignorées. Suffit pour relire l'écran de tui.run."""

    def __init__(self, cols, rows):
        self.cols, self.rows = cols, rows
        self.grid = [[" "] * cols for _ in range(rows)]
        self.x = self.y = 0
        self.pending = b""

    def resize(self, rows, cols):
        g = [[" "] * cols for _ in range(rows)]
        for y in range(min(rows, self.rows)):
            for x in range(min(cols, self.cols)):
                g[y][x] = self.grid[y][x]
        self.grid, self.rows, self.cols = g, rows, cols

    @property
    def display(self):
        return ["".join(r) for r in self.grid]

    def feed(self, data):
        data = self.pending + data
        self.pending = b""
        text = data.decode("utf-8", "replace")
        i, n = 0, len(text)
        while i < n:
            c = text[i]
            if c == "\x1b":
                if i + 1 >= n:
                    self.pending = text[i:].encode()
                    return
                if text[i + 1] == "[":
                    j = i + 2
                    while j < n and not ("@" <= text[j] <= "~"):
                        j += 1
                    if j >= n:
                        self.pending = text[i:].encode()
                        return
                    args, cmd = text[i + 2:j], text[j]
                    if cmd == "H" or cmd == "f":
                        parts = [p for p in args.split(";")]
                        r = int(parts[0]) if parts and parts[0].isdigit() else 1
                        col = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 1
                        self.y, self.x = min(self.rows - 1, r - 1), min(self.cols - 1, col - 1)
                    elif cmd == "J" and args == "2":
                        self.grid = [[" "] * self.cols for _ in range(self.rows)]
                    i = j + 1
                    continue
                if text[i + 1] == "]":
                    j = text.find("\x07", i)
                    i = n if j < 0 else j + 1
                    continue
                i += 2
                continue
            if c == "\r":
                self.x = 0
            elif c == "\n":
                self.y = min(self.rows - 1, self.y + 1)
            elif c >= " ":
                if self.x < self.cols:
                    self.grid[self.y][self.x] = c
                self.x += 1
            i += 1


if pyte:
    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.ByteStream(screen)
else:
    screen = MiniScreen(COLS, ROWS)
    stream = screen

def pump(t):
    global raw
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return
            raw += data
            if stream:
                stream.feed(data)

def text():
    return "\n".join(screen.display) if screen else raw.decode("utf-8", "replace")

def wait_for(s, t=8.0):
    end = time.time() + t
    while time.time() < end:
        pump(0.1)
        if s in text():
            return True
    return False

checks, fails = 0, []
def check(cond, label):
    global checks
    checks += 1
    if not cond:
        fails.append(label)

def send(b, t=0.25):
    os.write(fd, b)
    pump(t)

def click(x, y):
    send(b"\x1b[<0;%d;%dM" % (x + 1, y + 1), 0.05)
    send(b"\x1b[<0;%d;%dm" % (x + 1, y + 1))

def find(s):
    if not screen:
        return None
    for y, line in enumerate(screen.display):
        k = line.find(s)
        if k >= 0:
            return k, y
    return None

check(wait_for("Compteur 0"), "premier affichage")
check(b"\x1b[?1049h" in raw and b"\x1b[?1006h" in raw, "écran alternatif et souris SGR activés")
send(b"\r")
check(wait_for("Compteur 1"), "Entrée sur le bouton (saisie brute)")
send(b"\t")
send("Zoé".encode())
check(wait_for("Zoé"), "Tab puis saisie UTF-8")
if screen:
    p = find("Plus")
    check(p is not None, "bouton à l'écran")
    if p:
        click(p[0] + 1, p[1])
        check(wait_for("Compteur 2"), "clic souris (SGR 1006)")
    q = find("prune")
    if q:
        click(q[0], q[1])
        pump(0.3)
send(b"\x1b[B")
# redimensionnement : le contenu suit (SIGWINCH)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 16, 70, 0, 0))
if screen:
    screen.resize(16, 70)
os.kill(pid, signal.SIGWINCH)
pump(1.0)
check(wait_for("Compteur 2" if screen else "Compteur"), "affichage après redimensionnement")
# F10 ouvre le menu, Marquer termine avec une valeur
send(b"\x1b[21~")
check(wait_for("Marquer"), "F10 ouvre le menu")
send(b"\x1b[B\r", 0.5)
pump(1.5)
try:
    os.waitpid(pid, 0)
except ChildProcessError:
    pass
out = raw.decode("utf-8", "replace")
check(b"\x1b[?1049l" in raw and b"\x1b[?25h" in raw, "terminal rétabli (écran normal, curseur visible)")
final = [l for l in out.splitlines() if "ETAT" in l]
check(len(final) == 1, "état final affiché après la sortie")
if final:
    f = final[0]
    check("n=2" in f or (not screen and "n=1" in f), "compteur final")
    check("nom=Zoé" in f, "texte saisi")
    check("fin=marque" in f, "valeur de fin (app.stop)")
    if screen:
        check("fruit=kiwi" in f, "liste : clic sur prune puis ↓ → kiwi")
print("ui.view (pty%s) : %d vérifications OK, %d échec(s)" % ("" if pyte else ", émulateur intégré", checks - len(fails), len(fails)))
for f in fails:
    print("  ÉCHEC", f)
if fails:
    print(text())
    print(repr(out[-500:]))
sys.exit(1 if fails else 0)
