#!/usr/bin/env python3
"""Client WebSocket de référence (RFC 6455 à la main) contre le serveur Alex. usage : ws_test_client.py port mode
Imprime une ligne de résultat que test_websocket.al compare."""
import base64, json, os, socket, struct, sys

port, mode = int(sys.argv[1]), sys.argv[2]
c = socket.create_connection(("127.0.0.1", port), timeout=10)


def recv_exact(n):
    buf = b""
    while len(buf) < n:
        chunk = c.recv(n - len(buf))
        if not chunk:
            raise EOFError
        buf += chunk
    return buf


def frame(op, data=b"", fin=True, mask=True):
    out = bytes([(0x80 if fin else 0) | op])
    n = len(data)
    m = 0x80 if mask else 0
    if n < 126:
        out += bytes([m | n])
    elif n < 65536:
        out += bytes([m | 126]) + struct.pack(">H", n)
    else:
        out += bytes([m | 127]) + struct.pack(">Q", n)
    if mask:
        key = os.urandom(4)
        out += key + bytes(b ^ key[i % 4] for i, b in enumerate(data))
    else:
        out += data
    return out


def read_frame():
    b0, b1 = recv_exact(2)
    n = b1 & 0x7F
    if n == 126:
        n = struct.unpack(">H", recv_exact(2))[0]
    elif n == 127:
        n = struct.unpack(">Q", recv_exact(8))[0]
    return bool(b0 & 0x80), b0 & 0x0F, recv_exact(n)


def open_ws(path="/ws", extra=""):
    key = base64.b64encode(os.urandom(16)).decode()
    c.sendall(("GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n%s\r\n" % (path, port, key, extra)).encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        buf += c.recv(4096)
    return buf.decode()


def close_code():
    while True:
        _fin, op, data = read_frame()
        if op == 8:
            return struct.unpack(">H", data[:2])[0] if len(data) >= 2 else 1005


if mode == "badhandshake":
    c.sendall(b"GET /ws HTTP/1.1\r\nHost: x\r\n\r\n")
    print(c.recv(200).decode().split("\r\n")[0])
elif mode == "badpath":
    print(open_ws("/nope").split("\r\n")[0])
elif mode == "proto":
    r = open_ws("/ws", "Sec-WebSocket-Protocol: autre, chat\r\n")
    print([l for l in r.split("\r\n") if l.lower().startswith("sec-websocket-protocol")][0].split(": ")[1])
else:
    resp = open_ws()
    assert resp.startswith("HTTP/1.1 101"), resp
    out = []
    if mode == "basic":
        c.sendall(frame(1, "salut é".encode()))
        out.append(read_frame()[2].decode())
        c.sendall(frame(1, b"ab", fin=False) + frame(0, b"cd"))
        out.append(read_frame()[2].decode())
        c.sendall(frame(9, b"p1"))
        _f, op, data = read_frame()
        out.append("op%d:%s" % (op, data.decode()))
        c.sendall(frame(8, struct.pack(">H", 1000) + b"fin"))
        _f, op, data = read_frame()
        out.append("close:%d" % struct.unpack(">H", data[:2])[0])
    elif mode == "unmasked":
        c.sendall(frame(1, b"x", mask=False))
        out.append("close:%d" % close_code())
    elif mode == "badutf8":
        c.sendall(frame(1, b"\xff\xfe"))
        out.append("close:%d" % close_code())
    elif mode == "toobig":
        c.sendall(frame(2, b"\x01" * 2000))
        out.append("close:%d" % close_code())
    elif mode == "badopcode":
        c.sendall(frame(3, b"?"))
        out.append("close:%d" % close_code())
    elif mode == "badclosecode":
        c.sendall(frame(8, struct.pack(">H", 1005)))
        out.append("close:%d" % close_code())
    print("|".join(out))
