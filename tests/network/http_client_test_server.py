#!/usr/bin/env python3
"""Serveur HTTP/1.1 de référence (multi-fils, keep-alive) pour tests/network/test_http_client.al.

Écrit son port sur la sortie standard puis sert jusqu'à /shutdown. Routes :
  /echo               JSON : méthode, chemin, requête, en-têtes, corps, identifiant de connexion
  /conn               identifiant de la connexion TCP (vérifie la réutilisation keep-alive)
  /chunked            corps « chunked » ; /close : corps jusqu'à la fermeture
  /gzip, /deflate     corps compressé (Content-Encoding)
  /redirect/N         chaîne de 302 ; /see-other (303) ; /temporary (307) ; /cross?to=URL (302 ailleurs)
  /status/N           statut N
  /cookie/set?n=v     Set-Cookie ; /cookie/get : en-tête Cookie reçu
  /basic              Basic alice:secret ; /digest : Digest (MD5, qop=auth) alice:secret
  /retry?key=k        503 (Retry-After: 0) aux deux premiers appels de chaque clé, puis 200
  /big                1 Mio d'octets ; /upload : multipart analysé -> JSON
  /slow               attend 2 s ; /closeidle : répond puis ferme la connexion malgré keep-alive
"""
import gzip
import hashlib
import json
import sys
import threading
import time
import zlib
from email import message_from_bytes
from email.policy import HTTP
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

RETRIES = {}
NONCE = "dcd98b7102dd2f0e8b11d0f600bfb0c093"
LOCK = threading.Lock()
CONN_IDS = {}


def conn_id(handler):
    with LOCK:
        key = id(handler.connection)
        if key not in CONN_IDS:
            CONN_IDS[key] = len(CONN_IDS) + 1
        return CONN_IDS[key]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _send(self, status, body, headers=None, length=True):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(status)
        for k, v in (headers or {}).items():
            if isinstance(v, list):
                for x in v:
                    self.send_header(k, x)
            else:
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
        return self.rfile.read(n) if n else b""

    def _digest_ok(self):
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Digest "):
            return False
        parts = {}
        for item in auth[7:].split(","):
            k, _, v = item.strip().partition("=")
            parts[k] = v.strip('"')
        h = lambda s: hashlib.md5(s.encode()).hexdigest()
        ha1 = h(f"alice:{parts.get('realm')}:secret")
        ha2 = h(f"{self.command}:{parts.get('uri')}")
        expected = h(f"{ha1}:{NONCE}:{parts.get('nc')}:{parts.get('cnonce')}:auth:{ha2}")
        return parts.get("response") == expected and parts.get("nonce") == NONCE

    def handle_any(self):
        path, _, query = self.path.partition("?")
        q = parse_qs(query)
        if path == "/echo":
            body = self._body()
            data = {"method": self.command, "path": path, "query": query, "conn": conn_id(self),
                    "headers": {k.lower(): v for k, v in self.headers.items()},
                    "body": body.decode("utf-8", "replace")}
            self._send(200, json.dumps(data), {"Content-Type": "application/json"})
        elif path == "/conn":
            self._send(200, str(conn_id(self)))
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
        elif path == "/closeidle":
            self._send(200, "puis fermeture", {"Content-Type": "text/plain"})
            self.close_connection = True
        elif path == "/gzip":
            self._send(200, gzip.compress(("compressé gzip " * 50).encode()), {"Content-Encoding": "gzip", "Content-Type": "text/plain; charset=utf-8"})
        elif path == "/deflate":
            self._send(200, zlib.compress(("compressé deflate " * 50).encode()), {"Content-Encoding": "deflate", "Content-Type": "text/plain; charset=utf-8"})
        elif path.startswith("/redirect/"):
            n = int(path.rsplit("/", 1)[1])
            self._send(302, "", {"Location": f"/redirect/{n - 1}" if n > 1 else "/echo"})
        elif path == "/see-other":
            self._body()
            self._send(303, "", {"Location": "/echo"})
        elif path == "/temporary":
            self._body()
            self._send(307, "", {"Location": "/echo"})
        elif path == "/cross":
            self._send(302, "", {"Location": q["to"][0]})
        elif path.startswith("/status/"):
            n = int(path.rsplit("/", 1)[1])
            self._send(n, "" if n in (204, 304) else f"statut {n}")
        elif path == "/cookie/set":
            cookies = [f"{k}={v[0]}; Path=/" for k, v in q.items()]
            self._send(200, "ok", {"Set-Cookie": cookies})
        elif path == "/cookie/get":
            self._send(200, self.headers.get("Cookie", ""))
        elif path == "/basic":
            if self.headers.get("Authorization") == "Basic YWxpY2U6c2VjcmV0":
                self._send(200, "bienvenue alice")
            else:
                self._send(401, "non", {"WWW-Authenticate": 'Basic realm="test"'})
        elif path == "/digest":
            if self._digest_ok():
                self._send(200, "digest ok")
            else:
                self._send(401, "non", {"WWW-Authenticate": f'Digest realm="test@alex", qop="auth,auth-int", nonce="{NONCE}", opaque="5ccc069c403ebaf9f0171e9517f40e41"'})
        elif path == "/retry":
            key = q.get("key", ["x"])[0]
            with LOCK:
                RETRIES[key] = RETRIES.get(key, 0) + 1
                n = RETRIES[key]
            if n <= 2:
                self._send(503, "indisponible", {"Retry-After": "0"})
            else:
                self._send(200, f"réussi après {n} essais")
        elif path == "/big":
            self._send(200, bytes(i % 251 for i in range(1 << 20)), {"Content-Type": "application/octet-stream"})
        elif path == "/upload":
            body = self._body()
            ct = self.headers.get("Content-Type")
            msg = message_from_bytes(b"Content-Type: " + ct.encode() + b"\r\n\r\n" + body, policy=HTTP)
            out = {}
            for part in msg.iter_parts():
                name = part.get_param("name", header="content-disposition")
                fn = part.get_filename()
                data = part.get_payload(decode=True)
                if fn:
                    out[name] = {"filename": fn, "size": len(data), "type": part.get_content_type(), "sha256": hashlib.sha256(data).hexdigest()}
                else:
                    out[name] = data.decode("utf-8")
            self._send(200, json.dumps(out), {"Content-Type": "application/json"})
        elif path == "/slow":
            time.sleep(2)
            self._send(200, "lent")
        elif path == "/shutdown":
            self._send(200, "arrêt")
            threading.Thread(target=self.server.shutdown).start()
        else:
            self._send(404, "introuvable")

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = do_PATCH = do_OPTIONS = handle_any


ThreadingHTTPServer.daemon_threads = True
srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print(srv.server_address[1], flush=True)
srv.serve_forever()
sys.exit(0)
