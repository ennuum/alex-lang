#!/usr/bin/env python3
"""Serveur TLS de référence pour tests/network/test_tls.al (bibliothèque standard Python, OpenSSL).

usage : tls_test_server.py cert.pem key.pem
Écrit son port sur la première ligne de stdout, puis sert les connexions (un fil par connexion) jusqu'à /shutdown.

Protocole en lignes (premier octet autre que « GET ») :
  echo <texte>   renvoie <texte>          info    renvoie « version|alpn|chiffrement »
  big <n>        n octets 'x' puis « \n » bye     ferme proprement (close_notify)
  abort          coupe sans close_notify  recv <n> lit n octets et renvoie leur longueur
HTTP (GET) : /hello /chunked /untilclose /truncated /headers /redirect-other /redirect-same /big /shutdown
"""
import json, os, socket, ssl, sys, threading

cert, key = sys.argv[1], sys.argv[2]
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
ctx.set_alpn_protocols(["h2", "http/1.1"])
ctx.minimum_version = ssl.TLSVersion.TLSv1_2
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0))
srv.listen(32)
PORT = srv.getsockname()[1]
print(PORT, flush=True)
stop = threading.Event()


def respond(t, status, headers, body):
    head = f"HTTP/1.1 {status}\r\n" + "".join(f"{k}: {v}\r\n" for k, v in headers.items()) + "\r\n"
    t.sendall(head.encode() + body)


def clean_close(t):
    try:
        t.unwrap()
    except Exception:
        pass
    t.close()


def http(t, f, line):
    path = line.split()[1].decode()
    hdrs = {}
    while True:
        h = f.readline()
        if h in (b"\r\n", b"\n", b""):
            break
        k, v = h.decode().split(":", 1)
        hdrs[k.strip().lower()] = v.strip()
    if path == "/hello":
        body = "bonjour TLS ✓".encode()
        respond(t, "200 OK", {"Content-Length": len(body), "Content-Type": "text/plain; charset=utf-8", "Connection": "close"}, body)
        clean_close(t)
    elif path == "/chunked":
        respond(t, "200 OK", {"Transfer-Encoding": "chunked", "Connection": "close"}, b"")
        t.sendall(b"5\r\nhello\r\n7\r\n, wor\xc3\xa9\r\n0\r\n\r\n")
        clean_close(t)
    elif path == "/untilclose":
        respond(t, "200 OK", {"Connection": "close"}, b"corps jusqu'a la fermeture propre")
        clean_close(t)
    elif path == "/truncated":
        respond(t, "200 OK", {"Connection": "close"}, b"corps coupe")
        os.close(t.detach())      # coupure sans close_notify (detach renvoie le descripteur)
    elif path == "/headers":
        body = json.dumps(hdrs).encode()
        respond(t, "200 OK", {"Content-Length": len(body), "Content-Type": "application/json", "Connection": "close"}, body)
        clean_close(t)
    elif path == "/redirect-other":
        respond(t, "302 Found", {"Location": f"https://localhost:{PORT}/headers", "Content-Length": 0, "Connection": "close"}, b"")
        clean_close(t)
    elif path == "/redirect-same":
        respond(t, "302 Found", {"Location": "/headers", "Content-Length": 0, "Connection": "close"}, b"")
        clean_close(t)
    elif path == "/big":
        body = bytes(i % 251 for i in range(300000))
        respond(t, "200 OK", {"Content-Length": len(body), "Connection": "close"}, body)
        clean_close(t)
    elif path == "/shutdown":
        respond(t, "200 OK", {"Content-Length": 2, "Connection": "close"}, b"ok")
        clean_close(t)
        stop.set()
        socket.create_connection(("127.0.0.1", PORT)).close()
    else:
        respond(t, "404 Not Found", {"Content-Length": 0, "Connection": "close"}, b"")
        clean_close(t)


def lines(t, f):
    while True:
        line = f.readline()
        if not line:
            break
        cmd, _, arg = line.decode().rstrip("\r\n").partition(" ")
        if cmd == "echo":
            t.sendall((arg + "\n").encode())
        elif cmd == "info":
            t.sendall(f"{t.version()}|{t.selected_alpn_protocol()}|{t.cipher()[0]}\n".encode())
        elif cmd == "big":
            t.sendall(b"x" * int(arg) + b"\n")
        elif cmd == "recv":
            n = int(arg)
            got = f.read(n)
            t.sendall(f"{len(got)}\n".encode())
        elif cmd == "bye":
            clean_close(t)
            return
        elif cmd == "abort":
            os.close(t.detach())
            return


def serve(c):
    try:
        t = ctx.wrap_socket(c, server_side=True)
    except Exception:
        c.close()
        return
    try:
        f = t.makefile("rb")
        first = f.readline()
        if first.startswith(b"GET "):
            http(t, f, first)
        else:
            f2 = first  # première ligne déjà lue : la traiter comme les suivantes
            class Chain:
                def __init__(self):
                    self.first = f2
                def readline(self):
                    if self.first is not None:
                        x, self.first = self.first, None
                        return x
                    return f.readline()
                def read(self, n):
                    return f.read(n)
            lines(t, Chain())
    except Exception:
        pass


while not stop.is_set():
    c, _ = srv.accept()
    if stop.is_set():
        c.close()
        break
    threading.Thread(target=serve, args=(c,), daemon=True).start()
