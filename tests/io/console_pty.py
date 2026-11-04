#!/usr/bin/env python3
"""Test de la saisie interactive de io.console (read_key, read_password) dans un pseudo-terminal."""
import os, pty, sys, time, select

ALEX = sys.argv[1] if len(sys.argv) > 1 else "./alex"
pid, fd = pty.fork()
if pid == 0:
    os.execv(ALEX, [ALEX, "run", "tests/io/console_keys.al"])

buf = b""
def wait_for(token, timeout=10.0):
    global buf
    end = time.time() + timeout
    while token not in buf:
        left = end - time.time()
        if left <= 0:
            raise SystemExit(f"ÉCHEC : '{token.decode()}' absent ; reçu {buf!r}")
        r, _, _ = select.select([fd], [], [], left)
        if r:
            try:
                buf += os.read(fd, 4096)
            except OSError:
                break

wait_for(b"PRET true")
for seq in [b"\x1b[A", b"a", "é".encode(), b"\x03", b"\x1b"]:
    os.write(fd, seq)
    time.sleep(0.15)
wait_for(b"MDP: ")
time.sleep(0.1)
os.write(fd, b"sesamx\x7fe\r")
wait_for(b"DELAI")
time.sleep(0.2)
try:
    while select.select([fd], [], [], 0.3)[0]:
        buf += os.read(fd, 4096)
except OSError:
    pass
# L'écho du terminal doit être rétabli après le programme.
os.waitpid(pid, 0)

text = buf.decode("utf-8", "replace").replace("\r", "")
expected = ["TOUCHE up", "TOUCHE a", "TOUCHE é", "TOUCHE ctrl+c", "TOUCHE escape", "SECRET [sesame]", "DELAI null"]
failures = [e for e in expected if e not in text]
if "sesam" in text.split("MDP: ")[-1].split("SECRET")[0]:
    failures.append("le mot de passe a été affiché (écho)")
ok = len(expected) + 1 - len(failures)
print(f"console (pty) : {ok} vérifications OK, {len(failures)} échec(s)")
for f in failures:
    print("  ÉCHEC", f)
if failures:
    print(repr(text))
sys.exit(1 if failures else 0)
