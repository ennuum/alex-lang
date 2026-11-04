#!/usr/bin/env python3
"""Serveur WebSocket de référence (RFC 6455 écrit à la main, indépendant du module Alex) pour test_websocket.al.
usage : ws_test_server.py [cert.pem key.pem]   (avec certificat : wss://)
Première ligne de stdout : le port. Le chemin de la requête choisit le comportement (voir MODES)."""
import base64, hashlib, json, os, socket, ssl, struct, sys, threading

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
ctx = None
if len(sys.argv) >= 3:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(sys.argv[1], sys.argv[2])
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0))
srv.listen(16)
PORT = srv.getsockname()[1]
print(PORT, flush=True)
stop = threading.Event()


def recv_exact(c, n):
    buf = b""
    while len(buf) < n:
        chunk = c.recv(n - len(buf))
        if not chunk:
            raise EOFError
        buf += chunk
    return buf


def read_frame(c):
    b0, b1 = recv_exact(c, 2)
    n = b1 & 0x7F
    if n == 126:
        n = struct.unpack(">H", recv_exact(c, 2))[0]
    elif n == 127:
        n = struct.unpack(">Q", recv_exact(c, 8))[0]
    key = recv_exact(c, 4) if b1 & 0x80 else None
    data = recv_exact(c, n)
    if key:
        data = bytes(b ^ key[i % 4] for i, b in enumerate(data))
    return bool(b0 & 0x80), b0 & 0x0F, data, bool(b1 & 0x80)


def frame(op, data=b"", fin=True, mask=False):
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


def handshake(c):
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = c.recv(4096)
        if not chunk:
            raise EOFError
        buf += chunk
    head, _, rest = buf.partition(b"\r\n\r\n")
    lines = head.decode().split("\r\n")
    path = lines[0].split()[1]
    h = {}
    for line in lines[1:]:
        k, _, v = line.partition(":")
        h[k.strip().lower()] = v.strip()
    return path, h


def accept_value(key, wrong=False):
    k = key.encode() + (b"x" if wrong else b"")
    return base64.b64encode(hashlib.sha1(k + GUID).digest()).decode()


def reply(c, h, extra="", wrong=False):
    c.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               "Sec-WebSocket-Accept: %s\r\n%s\r\n" % (accept_value(h["sec-websocket-key"], wrong), extra)).encode())


def serve(c):
    try:
        if ctx:
            c = ctx.wrap_socket(c, server_side=True)
        path, h = handshake(c)
        if path == "/reject":
            c.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            return
        if path == "/badaccept":
            reply(c, h, wrong=True)
            return
        if path == "/protocol":
            offered = [x.strip() for x in h.get("sec-websocket-protocol", "").split(",")]
            chosen = "chat" if "chat" in offered else offered[0]
            reply(c, h, "Sec-WebSocket-Protocol: %s\r\n" % chosen)
            c.sendall(frame(1, chosen.encode()))
            read_frame(c)
            return
        if path == "/unoffered":
            reply(c, h, "Sec-WebSocket-Protocol: surprise\r\n")
            return
        reply(c, h)
        if path == "/headers":
            c.sendall(frame(1, json.dumps(h).encode()))
            read_frame(c)
        elif path == "/fragment":
            read_frame(c)
            parts = "héllo wörld".encode()
            c.sendall(frame(1, parts[:3], fin=False) + frame(9, b"mid") + frame(0, parts[3:8], fin=False) + frame(0, parts[8:], fin=True))
            op = read_frame(c)  # pong "mid" puis fermeture du client
            c.sendall(frame(1, ("pong:" + op[2].decode()).encode()))
            read_frame(c)
        elif path == "/big":
            read_frame(c)
            c.sendall(frame(2, bytes(i % 251 for i in range(70000))) + frame(2, b"\x00" * 200) + frame(1, b""))
            read_frame(c)
        elif path == "/badmask":
            c.sendall(frame(1, b"masque", mask=True))
            c.recv(100)
        elif path == "/badutf8":
            c.sendall(frame(1, b"\xff\xfe"))
            c.recv(100)
        elif path == "/ping":
            c.sendall(frame(9, b"abc"))
            _, op, data, _m = read_frame(c)
            c.sendall(frame(1, ("pong-ok:" + data.decode()).encode() if op == 10 else b"pas-de-pong"))
            read_frame(c)
        elif path == "/close":
            c.sendall(frame(8, struct.pack(">H", 1001) + "partir".encode()))
            _, op, data, _m = read_frame(c)
            c.sendall(b"")
        elif path == "/abrupt":
            return
        elif path == "/shutdown":
            stop.set()
            socket.create_connection(("127.0.0.1", PORT)).close()
        else:  # /echo
            buf, kind = b"", 0
            while True:
                fin, op, data, _m = read_frame(c)
                if op == 8:
                    c.sendall(frame(8, data[:2]))
                    break
                if op == 9:
                    c.sendall(frame(10, data))
                    continue
                if op in (1, 2):
                    kind, buf = op, data
                else:
                    buf += data
                if fin:
                    c.sendall(frame(kind, buf))
    except Exception:
        pass
    finally:
        try:
            c.close()
        except Exception:
            pass


while not stop.is_set():
    cl, _ = srv.accept()
    if stop.is_set():
        cl.close()
        break
    threading.Thread(target=serve, args=(cl,), daemon=True).start()
