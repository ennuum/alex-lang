# Tape un texte par le moniteur de QEMU (sendkey) : monkeys.py socket fichier-de-touches [délai]
import os, socket, sys, time
KEYS = {' ': 'spc', '\n': 'ret', '-': 'minus', '.': 'dot', ',': 'comma', '/': 'slash', '=': 'equal'}
SHIFTED = {'!': 'shift-1', '?': 'shift-slash', ':': 'shift-semicolon', '_': 'shift-minus'}
sock, keys = sys.argv[1], open(sys.argv[2], encoding='utf-8').read()
delay = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
for _ in range(200):
    if os.path.exists(sock):
        break
    time.sleep(0.05)
mon = socket.socket(socket.AF_UNIX)
mon.connect(sock)
time.sleep(delay)
for ch in keys:
    if ch.isupper():
        name = 'shift-' + ch.lower()
    elif ch in SHIFTED:
        name = SHIFTED[ch]
    else:
        name = KEYS.get(ch, ch)
    mon.sendall(('sendkey ' + name + '\n').encode())
    time.sleep(0.1)
time.sleep(1)
