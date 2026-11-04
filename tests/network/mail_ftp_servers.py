#!/usr/bin/env python3
"""Serveurs de référence SMTP, POP3, IMAP et FTP (bibliothèque standard de Python) pour
tests/network/test_mail_ftp.al. Chacun écrit son port sur la sortie standard, sert UNE session cliente (deux
pour FTP), puis écrit un compte rendu JSON dans le fichier donné.

  mail_ftp_servers.py smtp|pop3|imap|ftp CERT KEY RAPPORT.json

Identifiants acceptés : alice / secret. Les montées en TLS (STARTTLS, STLS, AUTH TLS) utilisent CERT et KEY.
"""
import base64
import hashlib
import hmac
import json
import os
import socket
import ssl
import sys
import threading
import time

MODE, CERT, KEY, REPORT = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
CTX = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
CTX.load_cert_chain(CERT, KEY)
report = {"commands": []}


class Conn:
    def __init__(self, sock):
        self.sock = sock
        self.buf = b""

    def tls(self):
        self.sock = CTX.wrap_socket(self.sock, server_side=True)

    def line(self):
        while b"\r\n" not in self.buf:
            d = self.sock.recv(65536)
            if not d:
                return None
            self.buf += d
        l, self.buf = self.buf.split(b"\r\n", 1)
        return l

    def exact(self, n):
        while len(self.buf) < n:
            d = self.sock.recv(65536)
            if not d:
                raise EOFError
            self.buf += d
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, data):
        if isinstance(data, str):
            data = data.encode()
        self.sock.sendall(data)


def listen():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    s.listen(5)
    print(s.getsockname()[1], flush=True)
    return s


def b64(s):
    return base64.b64encode(s.encode() if isinstance(s, str) else s).decode()


# ---------------------------------------------------------------- SMTP
def smtp():
    srv = listen()
    sock, _ = srv.accept()
    c = Conn(sock)
    c.send("220 mock.test ESMTP prêt\r\n")
    secure = False
    authed = False
    msgs = []
    env = {}
    while True:
        l = c.line()
        if l is None:
            break
        cmd = l.decode("utf-8", "replace")
        report["commands"].append(cmd.split(" ")[0].upper() if not cmd.startswith("AUTH") else " ".join(cmd.split(" ")[:2]))
        u = cmd.upper()
        if u.startswith("EHLO"):
            caps = ["mock.test", "SIZE 100000", "8BITMIME", "SMTPUTF8", "AUTH PLAIN LOGIN CRAM-MD5"]
            if not secure:
                caps.append("STARTTLS")
            caps.append("PIPELINING")
            c.send("".join(("250-" if i < len(caps) - 1 else "250 ") + x + "\r\n" for i, x in enumerate(caps)))
        elif u == "STARTTLS":
            c.send("220 on y va\r\n")
            c.tls()
            secure = True
            report["tls"] = True
        elif u.startswith("AUTH PLAIN "):
            ok = base64.b64decode(cmd[11:]) == b"\0alice\0secret"
            authed = ok
            c.send("235 bienvenue\r\n" if ok else "535 refusé\r\n")
        elif u == "AUTH LOGIN":
            c.send("334 VXNlcm5hbWU6\r\n")
            user = base64.b64decode(c.line()).decode()
            c.send("334 UGFzc3dvcmQ6\r\n")
            pw = base64.b64decode(c.line()).decode()
            authed = user == "alice" and pw == "secret"
            c.send("235 ok\r\n" if authed else "535 non\r\n")
        elif u == "AUTH CRAM-MD5":
            chal = b"<12345.67890@mock.test>"
            c.send("334 " + b64(chal) + "\r\n")
            resp = base64.b64decode(c.line()).decode()
            user, dig = resp.split(" ")
            authed = user == "alice" and dig == hmac.new(b"secret", chal, hashlib.md5).hexdigest()
            c.send("235 ok\r\n" if authed else "535 non\r\n")
        elif u.startswith("MAIL FROM:"):
            if not authed:
                c.send("530 authentification requise\r\n")
                continue
            env = {"from": cmd[10:], "rcpt": []}
            c.send("250 expéditeur ok\r\n")
        elif u.startswith("RCPT TO:"):
            to = cmd[8:]
            if "refuse" in to:
                c.send("550 boîte inconnue\r\n")
            else:
                env["rcpt"].append(to)
                c.send("250 destinataire ok\r\n")
        elif u == "DATA":
            c.send("354 envoyez\r\n")
            lines = []
            while True:
                x = c.line()
                if x == b".":
                    break
                if x.startswith(b".."):
                    x = x[1:]
                lines.append(x)
            env["data"] = b"\r\n".join(lines).decode("utf-8", "replace") + "\r\n"
            msgs.append(env)
            c.send("250 2.0.0 mis en file\r\n")
        elif u == "RSET" or u == "NOOP":
            c.send("250 ok\r\n")
        elif u == "QUIT":
            c.send("221 au revoir\r\n")
            break
        else:
            c.send("502 commande inconnue\r\n")
    report["messages"] = msgs


# ---------------------------------------------------------------- POP3
POP_MSGS = [
    b"From: a@x.org\r\nTo: b@y.org\r\nSubject: un\r\n\r\nPremier message\r\n",
    b"From: c@x.org\r\nTo: b@y.org\r\nSubject: =?UTF-8?Q?deux_=C3=A9t=C3=A9?=\r\n\r\nLigne\r\n.point au debut\r\nfin\r\n",
    b"From: d@x.org\r\nSubject: trois\r\n\r\n" + b"x" * 5000 + b"\r\n",
]


def pop3():
    srv = listen()
    sock, _ = srv.accept()
    c = Conn(sock)
    ts = "<1896.697170952@mock.test>"
    c.send("+OK POP3 prêt " + ts + "\r\n")
    authed = False
    deleted = set()
    user = None
    while True:
        l = c.line()
        if l is None:
            break
        cmd = l.decode()
        parts = cmd.split(" ")
        k = parts[0].upper()
        report["commands"].append(k)
        if k == "CAPA":
            c.send("+OK capacités\r\nUSER\r\nUIDL\r\nTOP\r\nSTLS\r\nSASL PLAIN\r\n.\r\n")
        elif k == "STLS":
            c.send("+OK go\r\n")
            c.tls()
            report["tls"] = True
        elif k == "USER":
            user = parts[1]
            c.send("+OK\r\n")
        elif k == "PASS":
            authed = user == "alice" and cmd[5:] == "secret"
            c.send("+OK connecté\r\n" if authed else "-ERR refusé\r\n")
        elif k == "APOP":
            authed = parts[1] == "alice" and parts[2] == hashlib.md5((ts + "secret").encode()).hexdigest()
            c.send("+OK apop\r\n" if authed else "-ERR non\r\n")
        elif not authed:
            c.send("-ERR non authentifié\r\n")
        elif k == "STAT":
            live = [i for i in range(len(POP_MSGS)) if i not in deleted]
            c.send("+OK %d %d\r\n" % (len(live), sum(len(POP_MSGS[i]) for i in live)))
        elif k == "LIST":
            out = "".join("%d %d\r\n" % (i + 1, len(m)) for i, m in enumerate(POP_MSGS) if i not in deleted)
            c.send("+OK\r\n" + out + ".\r\n")
        elif k == "UIDL":
            out = "".join("%d uid-%d\r\n" % (i + 1, i + 1) for i in range(len(POP_MSGS)) if i not in deleted)
            c.send("+OK\r\n" + out + ".\r\n")
        elif k in ("RETR", "TOP"):
            n = int(parts[1]) - 1
            if n < 0 or n >= len(POP_MSGS) or n in deleted:
                c.send("-ERR pas de tel message\r\n")
                continue
            data = POP_MSGS[n]
            if k == "TOP":
                head, body = data.split(b"\r\n\r\n", 1)
                data = head + b"\r\n\r\n" + b"".join(x + b"\r\n" for x in body.split(b"\r\n")[: int(parts[2])])
            lines = data.split(b"\r\n")
            if lines and lines[-1] == b"":
                lines = lines[:-1]
            stuffed = b"".join((b"." + x if x.startswith(b".") else x) + b"\r\n" for x in lines)
            c.send(b"+OK\r\n" + stuffed + b".\r\n")
        elif k == "DELE":
            deleted.add(int(parts[1]) - 1)
            c.send("+OK supprimé\r\n")
        elif k == "RSET":
            deleted.clear()
            c.send("+OK\r\n")
        elif k == "NOOP":
            c.send("+OK\r\n")
        elif k == "QUIT":
            report["deleted"] = sorted(d + 1 for d in deleted)
            c.send("+OK au revoir\r\n")
            break
        else:
            c.send("-ERR inconnu\r\n")


# ---------------------------------------------------------------- IMAP
IMAP_MSGS = {
    101: (b"From: Ada <ada@x.org>\r\nTo: bob@y.org\r\nSubject: =?UTF-8?B?w6l0w6k=?=\r\nDate: Sun, 11 Oct 2026 10:00:00 +0000\r\n\r\nCorps un\r\n", ["\\Seen"]),
    102: (b"From: carl@x.org\r\nTo: bob@y.org\r\nSubject: deux\r\n\r\nCorps deux\r\n", []),
    103: (b"From: dan@x.org\r\nSubject: trois\r\n\r\n" + "Données {5}\r\n".encode() + b"fin\r\n", []),
}


def imap_args(c, first):
    """Ligne de commande complète (littéraux « {n} » / « {n+} » lus en ligne)."""
    out = first
    lits = []
    while out.endswith(b"}"):
        k = out.rfind(b"{")
        n = out[k + 1:-1]
        plus = n.endswith(b"+")
        if plus:
            n = n[:-1]
        if not plus:
            c.send("+ prêt\r\n")
        lits.append(c.exact(int(n)))
        out = out[:k] + b"\x00LIT" + str(len(lits) - 1).encode() + b"\x00" + (c.line() or b"")
    return out, lits


def imap_tokens(s):
    toks = []
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == " ":
            i += 1
        elif ch == '"':
            j = i + 1
            buf = ""
            while s[j] != '"':
                if s[j] == "\\":
                    j += 1
                buf += s[j]
                j += 1
            toks.append(buf)
            i = j + 1
        elif ch == "\x00":
            j = s.index("\x00", i + 1)
            toks.append(("LIT", int(s[i + 4:j])))
            i = j + 1
        else:
            j = i
            depth = 0
            while j < len(s) and (s[j] != " " or depth > 0):
                if s[j] in "([":
                    depth += 1
                elif s[j] in ")]":
                    depth -= 1
                j += 1
            toks.append(s[i:j])
            i = j
    return toks


def imap():
    srv = listen()
    sock, _ = srv.accept()
    c = Conn(sock)
    c.send("* OK [CAPABILITY IMAP4rev1 STARTTLS] serveur IMAP de test\r\n")
    secure = False
    flags = {u: list(f) for u, (_, f) in IMAP_MSGS.items()}
    boxes = {"INBOX": list(IMAP_MSGS), "Archives": [], "&AMk-t&AOk-": []}
    appended = []
    while True:
        l = c.line()
        if l is None:
            break
        line, lits = imap_args(c, l)
        text = line.decode("utf-8", "replace")
        toks = imap_tokens(text)
        tag = toks[0]
        cmd = toks[1].upper()
        args = toks[2:]
        if cmd == "UID":
            cmd = "UID " + args[0].upper()
            args = args[1:]
        report["commands"].append(cmd)
        caps = "IMAP4rev1 IDLE MOVE UIDPLUS" + ("" if secure else " STARTTLS")
        if cmd == "CAPABILITY":
            c.send("* CAPABILITY " + caps + "\r\n" + tag + " OK capacités\r\n")
        elif cmd == "STARTTLS":
            c.send(tag + " OK début TLS\r\n")
            c.tls()
            secure = True
            report["tls"] = True
        elif cmd == "LOGIN":
            user = args[0]
            pw = args[1]
            if isinstance(pw, tuple):
                pw = lits[pw[1]].decode()
            ok = user == "alice" and pw == "secret"
            c.send(tag + (" OK [CAPABILITY " + caps + "] connecté\r\n" if ok else " NO refusé\r\n"))
        elif cmd == "LIST":
            out = "".join('* LIST (\\HasNoChildren) "/" "%s"\r\n' % b for b in boxes)
            c.send(out + tag + " OK LIST terminé\r\n")
        elif cmd in ("SELECT", "EXAMINE"):
            box = args[0]
            n = len(boxes.get(box, []))
            c.send("* %d EXISTS\r\n* 0 RECENT\r\n* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n* OK [PERMANENTFLAGS (\\Deleted \\Seen \\*)] ok\r\n* OK [UIDVALIDITY 42] ok\r\n* OK [UIDNEXT 104] ok\r\n%s OK [READ-WRITE] sélectionné\r\n" % (n, tag))
        elif cmd == "STATUS":
            box = args[0]
            c.send('* STATUS "%s" (MESSAGES %d UNSEEN 1 UIDNEXT 104)\r\n%s OK\r\n' % (box, len(boxes.get(box, [])), tag))
        elif cmd == "UID SEARCH":
            crit = " ".join(a for a in args if isinstance(a, str)).upper()
            uids = [u for u in boxes["INBOX"] if "UNSEEN" not in crit or "\\Seen" not in flags[u]]
            c.send("* SEARCH " + " ".join(map(str, uids)) + "\r\n" + tag + " OK SEARCH terminé\r\n")
        elif cmd == "UID FETCH":
            ids = [int(x) for x in args[0].split(",")]
            items = args[1].upper()
            out = b""
            for seq, u in enumerate(boxes["INBOX"], 1):
                if u not in ids:
                    continue
                data, _ = IMAP_MSGS[u]
                parts = ["UID %d" % u]
                if "FLAGS" in items:
                    parts.append("FLAGS (%s)" % " ".join(flags[u]))
                if "RFC822.SIZE" in items:
                    parts.append("RFC822.SIZE %d" % len(data))
                if "ENVELOPE" in items:
                    parts.append('ENVELOPE ("Sun, 11 Oct 2026 10:00:00 +0000" "=?UTF-8?B?w6l0w6k=?=" (("Ada" NIL "ada" "x.org")) NIL NIL (("Bob" NIL "bob" "y.org")) NIL NIL NIL "<m1@x.org>")')
                head = "* %d FETCH (%s" % (seq, " ".join(parts))
                if "BODY.PEEK[]" in items or "BODY[]" in items:
                    out += (head + " BODY[] {%d}\r\n" % len(data)).encode() + data + b")\r\n"
                elif "BODY.PEEK[HEADER]" in items:
                    h = data.split(b"\r\n\r\n")[0] + b"\r\n\r\n"
                    out += (head + " BODY[HEADER] {%d}\r\n" % len(h)).encode() + h + b")\r\n"
                else:
                    out += (head + ")\r\n").encode()
            c.send(out + (tag + " OK FETCH terminé\r\n").encode())
        elif cmd == "UID STORE":
            ids = [int(x) for x in args[0].split(",")]
            mode = args[1].upper()
            fl = args[2].strip("()").split(" ")
            for u in ids:
                if mode.startswith("+"):
                    flags[u] = sorted(set(flags[u]) | set(fl))
                elif mode.startswith("-"):
                    flags[u] = [x for x in flags[u] if x not in fl]
            report["flags"] = {str(k): v for k, v in flags.items()}
            c.send(tag + " OK STORE terminé\r\n")
        elif cmd == "UID MOVE":
            ids = [int(x) for x in args[0].split(",")]
            dest = args[1]
            for u in ids:
                boxes["INBOX"].remove(u)
                boxes[dest].append(u)
            report["moved"] = {"ids": ids, "to": dest}
            c.send("* OK [COPYUID 42 %s 1]\r\n* 1 EXPUNGE\r\n%s OK MOVE terminé\r\n" % (args[0], tag))
        elif cmd == "APPEND":
            box = args[0]
            data = lits[args[-1][1]]
            appended.append({"box": box, "flags": args[1] if len(args) > 2 else "", "data": data.decode("utf-8", "replace")})
            report["appended"] = appended
            c.send(tag + " OK [APPENDUID 42 200] APPEND terminé\r\n")
        elif cmd == "IDLE":
            c.send("+ en attente\r\n")
            time.sleep(0.3)
            c.send("* 4 EXISTS\r\n")
            d = c.line()
            report["idle_done"] = d.decode()
            c.send(tag + " OK IDLE terminé\r\n")
        elif cmd == "CREATE":
            boxes[args[0]] = []
            report["created"] = args[0]
            c.send(tag + " OK CREATE terminé\r\n")
        elif cmd == "NOOP":
            c.send(tag + " OK\r\n")
        elif cmd == "LOGOUT":
            c.send("* BYE au revoir\r\n" + tag + " OK LOGOUT terminé\r\n")
            break
        else:
            c.send(tag + " BAD commande inconnue\r\n")


# ---------------------------------------------------------------- FTP
FILES = {"/pub/lisezmoi.txt": "Bonjour FTP\n".encode(), "/pub/données.bin": bytes(range(256)) * 10}
DIRS = {"/", "/pub"}


def ftp_session(c, srv_host):
    c.send("220-Serveur FTP de test\r\n220 prêt\r\n")
    cwd = "/"
    protect = False
    data_listener = None
    active = None
    rename_from = None
    rest = 0
    authed = False
    user = None

    def resolve(p):
        if p.startswith("/"):
            path = p
        else:
            path = (cwd.rstrip("/") + "/" + p) if cwd != "/" else "/" + p
        parts = []
        for x in path.split("/"):
            if x in ("", "."):
                continue
            if x == "..":
                if parts:
                    parts.pop()
            else:
                parts.append(x)
        return "/" + "/".join(parts)

    def open_data():
        nonlocal data_listener, active
        if active:
            s = socket.create_connection(active)
            active = None
        else:
            s, _ = data_listener.accept()
            data_listener.close()
            data_listener = None
        if protect:
            s = CTX.wrap_socket(s, server_side=True)
        return s

    def listing(d, mlsd):
        out = []
        for path in sorted(set(FILES) | DIRS):
            if path == d or not path.startswith(d.rstrip("/") + "/") or "/" in path[len(d.rstrip("/")) + 1:]:
                continue
            name = path.rsplit("/", 1)[1]
            if mlsd:
                if path in DIRS:
                    out.append("type=dir;modify=20261011120000; " + name)
                else:
                    out.append("type=file;size=%d;modify=20261011120000; %s" % (len(FILES[path]), name))
            else:
                if path in DIRS:
                    out.append("drwxr-xr-x 2 ftp ftp 4096 Oct 11 12:00 " + name)
                else:
                    out.append("-rw-r--r-- 1 ftp ftp %d Oct 11 12:00 %s" % (len(FILES[path]), name))
        return "".join(x + "\r\n" for x in out).encode()

    while True:
        l = c.line()
        if l is None:
            return
        cmd = l.decode("utf-8")
        k, _, arg = cmd.partition(" ")
        k = k.upper()
        report["commands"].append(k)
        if k == "AUTH":
            c.send("234 AUTH TLS ok\r\n")
            c.tls()
            report["tls"] = True
        elif k == "USER":
            user = arg
            c.send("331 mot de passe ?\r\n")
        elif k == "PASS":
            authed = (user == "alice" and arg == "secret") or user == "anonymous"
            c.send("230 connecté\r\n" if authed else "530 refusé\r\n")
        elif k == "PBSZ":
            c.send("200 PBSZ=0\r\n")
        elif k == "PROT":
            protect = arg.upper() == "P"
            report["prot"] = arg
            c.send("200 PROT ok\r\n")
        elif k == "FEAT":
            c.send("211-Extensions :\r\n MLST type*;size*;modify*;\r\n SIZE\r\n MDTM\r\n UTF8\r\n EPSV\r\n AUTH TLS\r\n211 fin\r\n")
        elif k == "OPTS":
            c.send("200 ok\r\n")
        elif not authed:
            c.send("530 connectez-vous\r\n")
        elif k == "PWD":
            c.send('257 "%s" est le dossier courant\r\n' % cwd.replace('"', '""'))
        elif k == "CWD":
            p = resolve(arg)
            if p in DIRS:
                cwd = p
                c.send("250 ok\r\n")
            else:
                c.send("550 dossier introuvable\r\n")
        elif k == "CDUP":
            cwd = resolve("..")
            c.send("250 ok\r\n")
        elif k == "TYPE":
            c.send("200 type " + arg + "\r\n")
        elif k == "EPSV":
            data_listener = socket.socket()
            data_listener.bind((srv_host, 0))
            data_listener.listen(1)
            c.send("229 mode passif étendu (|||%d|)\r\n" % data_listener.getsockname()[1])
        elif k == "PASV":
            data_listener = socket.socket()
            data_listener.bind((srv_host, 0))
            data_listener.listen(1)
            p = data_listener.getsockname()[1]
            c.send("227 Entering Passive Mode (10,9,8,7,%d,%d)\r\n" % (p >> 8, p & 255))
        elif k == "EPRT":
            parts = arg.split(arg[0])
            active = (parts[2], int(parts[3]))
            report["active"] = True
            c.send("200 EPRT ok\r\n")
        elif k == "PORT":
            n = arg.split(",")
            active = (".".join(n[:4]), int(n[4]) * 256 + int(n[5]))
            c.send("200 PORT ok\r\n")
        elif k in ("LIST", "NLST", "MLSD"):
            d = resolve(arg) if arg else cwd
            c.send("150 liste\r\n")
            s = open_data()
            if k == "NLST":
                s.sendall(b"".join(x.split(b" ")[-1] + b"\r\n" for x in listing(d, True).split(b"\r\n") if x))
            else:
                s.sendall(listing(d, k == "MLSD"))
            s.close()
            c.send("226 terminé\r\n")
        elif k == "RETR":
            p = resolve(arg)
            if p not in FILES:
                c.send("550 fichier introuvable\r\n")
                if data_listener:
                    data_listener.close()
                    data_listener = None
                continue
            c.send("150 envoi\r\n")
            s = open_data()
            s.sendall(FILES[p][rest:])
            rest = 0
            s.close()
            c.send("226 terminé\r\n")
        elif k in ("STOR", "APPE"):
            p = resolve(arg)
            c.send("150 réception\r\n")
            s = open_data()
            data = b""
            while True:
                d = s.recv(65536)
                if not d:
                    break
                data += d
            s.close()
            FILES[p] = (FILES.get(p, b"") if k == "APPE" else b"") + data
            report.setdefault("stored", {})[p] = len(FILES[p])
            c.send("226 reçu\r\n")
        elif k == "REST":
            rest = int(arg)
            c.send("350 reprise à %d\r\n" % rest)
        elif k == "SIZE":
            p = resolve(arg)
            c.send(("213 %d\r\n" % len(FILES[p])) if p in FILES else "550 inconnu\r\n")
        elif k == "MDTM":
            c.send("213 20261011120000\r\n" if resolve(arg) in FILES else "550 inconnu\r\n")
        elif k == "MKD":
            DIRS.add(resolve(arg))
            c.send('257 "%s" créé\r\n' % resolve(arg))
        elif k == "RMD":
            DIRS.discard(resolve(arg))
            c.send("250 supprimé\r\n")
        elif k == "DELE":
            p = resolve(arg)
            if p in FILES:
                del FILES[p]
                c.send("250 supprimé\r\n")
            else:
                c.send("550 inconnu\r\n")
        elif k == "RNFR":
            rename_from = resolve(arg)
            c.send("350 prêt\r\n")
        elif k == "RNTO":
            FILES[resolve(arg)] = FILES.pop(rename_from)
            c.send("250 renommé\r\n")
        elif k == "NOOP":
            c.send("200 ok\r\n")
        elif k == "QUIT":
            c.send("221 au revoir\r\n")
            return
        else:
            c.send("502 inconnu\r\n")


def ftp():
    srv = listen()
    for _ in range(2):
        sock, _ = srv.accept()
        ftp_session(Conn(sock), "127.0.0.1")
    report["files"] = sorted(FILES)
    report["dirs"] = sorted(DIRS)


try:
    {"smtp": smtp, "pop3": pop3, "imap": imap, "ftp": ftp}[MODE]()
except Exception as e:
    report["exception"] = repr(e)
with open(REPORT, "w") as f:
    json.dump(report, f, ensure_ascii=False)
