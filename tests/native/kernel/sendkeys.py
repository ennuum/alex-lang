#!/usr/bin/env python3
"""Démarre une image sans OS sous QEMU et tape un texte au clavier PS/2 (moniteur QEMU, `sendkey`).

usage : sendkeys.py image.bin fichier-de-touches [disque.img]
(sortie série sur la sortie standard, code de sortie de QEMU)
"""
import os, socket, subprocess, sys, tempfile, time

KEYS = {' ': 'spc', '\n': 'ret', '-': 'minus', '.': 'dot', ',': 'comma', '/': 'slash', '=': 'equal'}
SHIFTED = {'_': 'shift-minus', '?': 'shift-slash', '!': 'shift-1', ':': 'shift-semicolon', '"': 'shift-apostrophe'}

def main():
    image, keys = sys.argv[1], open(sys.argv[2], encoding='utf-8').read()
    sock = os.path.join(tempfile.mkdtemp(), 'mon.sock')
    extra = ['-m', '256M']
    if len(sys.argv) > 3:
        if os.environ.get('ALEX_VIRTIO') == '1': # même disque, branché en virtio-blk
            extra += ['-drive', 'file=' + sys.argv[3] + ',format=raw,if=none,id=vd0', '-device', 'virtio-blk-pci,drive=vd0']
        else:
            extra += ['-drive', 'file=' + sys.argv[3] + ',format=raw,if=ide,index=0']
    qemu = subprocess.Popen([os.environ.get('QEMU', 'qemu-system-x86_64'), '-kernel', image, '-display', 'none',
                             '-no-reboot', '-device', 'isa-debug-exit,iobase=0xf4,iosize=0x04', '-serial', 'stdio',
                             '-monitor', 'unix:' + sock + ',server,nowait'] + extra, stdin=subprocess.DEVNULL)
    for _ in range(100):
        if os.path.exists(sock):
            break
        time.sleep(0.05)
    mon = socket.socket(socket.AF_UNIX)
    mon.connect(sock)
    time.sleep(1.5)  # démarrage
    for ch in keys:
        if ch.isupper():
            name = 'shift-' + ch.lower()
        elif ch in SHIFTED:
            name = SHIFTED[ch]
        else:
            name = KEYS.get(ch, ch)
        mon.sendall(('sendkey ' + name + '\n').encode())
        time.sleep(0.03 if ch != '\n' else 0.4)
    try:
        rc = qemu.wait(timeout=60)
    except subprocess.TimeoutExpired:
        qemu.kill()
        rc = 124
    sys.exit(rc)

main()
