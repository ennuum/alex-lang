#!/usr/bin/env python3
"""Client TLS de référence pour tests/network/test_tls.al : se connecte à un serveur Alex.
usage : tls_test_client.py port cafile mode
  line   connexion vérifiée (cafile), ALPN http/1.1, envoie « salut é », imprime « réponse|alpn|version|chiffrement »
  badca  connexion avec les autorités du système (le certificat de test n'y est pas) : imprime « refused » si refusée
  plain  parle en clair à un serveur TLS : envoie une requête HTTP et imprime ce qui revient (rien, ou une alerte)
"""
import socket, ssl, sys

port, cafile, mode = int(sys.argv[1]), sys.argv[2], sys.argv[3]
if mode == "plain":
    c = socket.create_connection(("127.0.0.1", port))
    c.sendall(b"GET / HTTP/1.0\r\n\r\n")
    c.settimeout(3)
    try:
        data = c.recv(100)
    except Exception:
        data = b""
    print("recu=%d" % len(data))
    c.close()
    sys.exit(0)
ctx = ssl.create_default_context(cafile=cafile if mode == "line" else None)
ctx.set_alpn_protocols(["http/1.1"])
try:
    raw = socket.create_connection(("127.0.0.1", port), timeout=5)
    t = ctx.wrap_socket(raw, server_hostname="localhost")
except ssl.SSLError:
    print("refused")
    sys.exit(0)
t.sendall("salut é\n".encode())
line = t.makefile("rb").readline().decode().rstrip("\n")
print("|".join([line, str(t.selected_alpn_protocol()), t.version(), t.cipher()[0]]))
try:
    t.unwrap()
except Exception:
    pass
t.close()
