#!/usr/bin/env python3
"""Mandataire SOCKS5 minimal (RFC 1928 / 1929) pour tests/network/test_network_system.al : écrit son port, sert
N connexions (argument), relaie les octets. Identifiants exigés si un 2e argument « user:pass » est donné ; le
nom de domaine demandé (ATYP 3) est consigné sur la sortie d'erreur."""
import select
import socket
import struct
import sys
import threading

count = int(sys.argv[1])
cred = sys.argv[2].split(":") if len(sys.argv) > 2 else None
srv = socket.socket()
srv.bind(("127.0.0.1", 0))
srv.listen(5)
print(srv.getsockname()[1], flush=True)


def recvn(s, n):
    b = b""
    while len(b) < n:
        d = s.recv(n - len(b))
        if not d:
            raise EOFError
        b += d
    return b


def handle(c):
    ver, n = recvn(c, 2)
    methods = recvn(c, n)
    if cred:
        if 2 not in methods:
            c.sendall(b"\x05\xff")
            return
        c.sendall(b"\x05\x02")
        recvn(c, 1)
        u = recvn(c, recvn(c, 1)[0]).decode()
        p = recvn(c, recvn(c, 1)[0]).decode()
        ok = [u, p] == cred
        c.sendall(b"\x01" + (b"\x00" if ok else b"\x01"))
        if not ok:
            return
    else:
        c.sendall(b"\x05\x00")
    ver, cmd, _, atyp = recvn(c, 4)
    if atyp == 1:
        host = socket.inet_ntoa(recvn(c, 4))
    elif atyp == 3:
        host = recvn(c, recvn(c, 1)[0]).decode()
        sys.stderr.write("domaine " + host + "\n")
    else:
        host = socket.inet_ntop(socket.AF_INET6, recvn(c, 16))
    port = struct.unpack(">H", recvn(c, 2))[0]
    try:
        up = socket.create_connection(("127.0.0.1" if host == "localhost" else host, port), timeout=5)
    except OSError:
        c.sendall(b"\x05\x05\x00\x01" + b"\x00" * 6)
        return
    c.sendall(b"\x05\x00\x00\x01" + socket.inet_aton("127.0.0.1") + struct.pack(">H", 0))
    socks = [c, up]
    while True:
        r, _, _ = select.select(socks, [], [], 10)
        if not r:
            break
        for s in r:
            d = s.recv(65536)
            if not d:
                up.close()
                return
            (up if s is c else c).sendall(d)


for _ in range(count):
    c, _ = srv.accept()
    try:
        handle(c)
    except Exception:
        pass
    c.close()
