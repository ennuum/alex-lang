#!/usr/bin/env python3
"""`alex edit` dans un vrai terminal : ouverture d'un fichier, saisie, Ctrl+S, F5 (sortie du programme),
Ctrl+Q. Vérifie le fichier enregistré et le rétablissement du terminal."""
import os, pty, sys, time, select, struct, fcntl, termios, tempfile, shutil

ALEX = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "./alex")
d = tempfile.mkdtemp(prefix="alex_edit_pty_")
path = os.path.join(d, "essai.al")
with open(path, "w") as f:
    f.write("x := 6\n")

COLS, ROWS = 100, 30
pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
    os.environ["TERM"] = "xterm-256color"
    os.chdir(d)
    os.execv(ALEX, [ALEX, "edit", "essai.al"])

raw = b""
def pump(t):
    global raw
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                raw += os.read(fd, 65536)
            except OSError:
                return

def wait_for(s, t=8.0):
    end = time.time() + t
    while time.time() < end:
        pump(0.1)
        if s.encode() in raw:
            return True
    return False

checks, fails = 0, []
def check(cond, label):
    global checks
    checks += 1
    if not cond:
        fails.append(label)

def send(b, t=0.3):
    os.write(fd, b)
    pump(t)

check(wait_for("essai.al") and wait_for("Fichiers"), "alex edit : premier affichage")
send(b"\x1b[1;5F")                        # Ctrl+Fin
send(b"print(x * 7)")
send(b"\x13", 0.6)                        # Ctrl+S
check(wait_for("Enregistr"), "Ctrl+S : message d'enregistrement")
send(b"\x1b[15~")                         # F5
check(wait_for("42") and wait_for("code de sortie 0"), "F5 : sortie du programme")
send(b"\x11", 0.8)                        # Ctrl+Q
pump(1.0)
try:
    os.waitpid(pid, 0)
except ChildProcessError:
    pass
with open(path) as f:
    content = f.read()
check(content == "x := 6\nprint(x * 7)", "fichier enregistré : %r" % content)
check(b"\x1b[?1049l" in raw, "terminal rétabli")
shutil.rmtree(d, ignore_errors=True)
print("alex edit (pty) : %d vérifications OK, %d échec(s)" % (checks - len(fails), len(fails)))
for f in fails:
    print("  ÉCHEC", f)
if fails:
    print(repr(raw[-800:]))
sys.exit(1 if fails else 0)
