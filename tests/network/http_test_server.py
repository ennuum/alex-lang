#!/usr/bin/env python3
"""Serveur HTTP de référence pour tests/network/test_http.al (bibliothèque standard de Python).

Écoute sur 127.0.0.1, port choisi par le système, écrit le port sur la sortie standard, puis sert jusqu'à
/shutdown. Routes :
  /echo           JSON : méthode, chemin, requête, en-têtes reçus, corps
  /chunked        corps envoyé en « Transfer-Encoding: chunked »
  /close          corps sans Content-Length, terminé par la fermeture de la connexion
  /redirect/N     302 vers /redirect/N-1, puis /echo ; /redirect-loop : boucle infinie
  /see-other      303 vers /echo ; /temporary : 307 vers /echo ; /relative : 302 vers « echo?rel=1 »
  /status/N       statut N, corps « statut N »
  /slow           attend 3 s avant de répondre
  /utf8           texte UTF-8 ; /binary : octets 0..255
  /shutdown       arrête le serveur
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _send(self, status, body, headers=None, length=True):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(status)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        if length:
            self.send_header("Content-Length", str(len(body)))
        else:
            self.send_header("Connection", "close")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)
        if not length:
            self.close_connection = True

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n).decode("utf-8", "replace") if n else ""

    def handle_any(self):
        path, _, query = self.path.partition("?")
        if path == "/echo":
            data = {"method": self.command, "path": path, "query": query,
                    "headers": {k.lower(): v for k, v in self.headers.items()}, "body": self._body()}
            self._send(200, json.dumps(data), {"Content-Type": "application/json"})
        elif path == "/chunked":
            self.send_response(200)
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            for part in ["morceau 1, ", "morceau 2 — été, ", "fin"]:
                b = part.encode("utf-8")
                self.wfile.write(f"{len(b):x};ext=1\r\n".encode() + b + b"\r\n")
            self.wfile.write(b"0\r\nX-Trailer: oui\r\n\r\n")
        elif path == "/close":
            self._send(200, "corps jusqu'à la fermeture", length=False)
        elif path.startswith("/redirect/"):
            n = int(path.rsplit("/", 1)[1])
            self._send(302, "", {"Location": f"/redirect/{n - 1}" if n > 1 else "/echo"})
        elif path == "/redirect-loop":
            self._send(302, "", {"Location": "/redirect-loop"})
        elif path == "/see-other":
            self._body()
            self._send(303, "", {"Location": "/echo"})
        elif path == "/temporary":
            self._body()
            self._send(307, "", {"Location": "/echo"})
        elif path == "/relative":
            self._send(302, "", {"Location": "echo?rel=1"})
        elif path.startswith("/status/"):
            n = int(path.rsplit("/", 1)[1])
            self._send(n, "" if n in (204, 304) else f"statut {n}")
        elif path == "/slow":
            time.sleep(3)
            self._send(200, "lent")
        elif path == "/utf8":
            self._send(200, "Bonjour, ça marche : 日本語 ✓", {"Content-Type": "text/plain; charset=utf-8"})
        elif path == "/binary":
            self._send(200, bytes(range(256)), {"Content-Type": "application/octet-stream"})
        elif path == "/shutdown":
            self._send(200, "arrêt")
            threading.Thread(target=self.server.shutdown).start()
        else:
            self._send(404, "introuvable")

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = do_PATCH = handle_any


srv = HTTPServer(("127.0.0.1", 0), Handler)
print(srv.server_address[1], flush=True)
srv.serve_forever()
sys.exit(0)
