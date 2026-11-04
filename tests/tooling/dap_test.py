#!/usr/bin/env python3
"""Tests de l'adaptateur DAP de l'extension VS Code (editors/vscode/src/dap.js) : session DAP réelle
(Content-Length) sur `alex debug --protocol 2`. Ignoré si node est absent.

Usage : python3 tests/tooling/dap_test.py [chemin/vers/alex]
"""
import json
import os
import queue
import shutil
import subprocess
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ALEX = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "alex"))
PROG = os.path.join(HERE, "dbg", "prog.al")
DAP = os.path.join(ROOT, "editors", "vscode", "src", "dap.js")
ok = ko = 0


def check(name, cond, extra=""):
    global ok, ko
    if cond:
        ok += 1
        print("  ok   " + name)
    else:
        ko += 1
        print("  ÉCHEC " + name + ("  -> " + json.dumps(extra, ensure_ascii=False)[:500] if extra != "" else ""))


class Client:
    def __init__(self):
        self.p = subprocess.Popen(["node", DAP], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=dict(os.environ, ALEX_UI_BACKEND="headless"))
        self.q = queue.Queue()
        self.seq = 1
        self.events = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        f = self.p.stdout
        while True:
            line = f.readline()
            if not line:
                self.q.put(None)
                return
            if not line.startswith(b"Content-Length"):
                continue
            n = int(line.split(b":")[1])
            f.readline()
            self.q.put(json.loads(f.read(n).decode("utf-8")))

    def request(self, command, args=None):
        s = self.seq
        self.seq += 1
        body = json.dumps({"seq": s, "type": "request", "command": command, "arguments": args or {}}).encode()
        self.p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.p.stdin.flush()
        while True:
            m = self.q.get(timeout=20)
            if m is None:
                raise EOFError
            if m["type"] == "response" and m["request_seq"] == s:
                return m
            self.events.append(m)

    def wait_event(self, name, timeout=20):
        for i, e in enumerate(self.events):
            if e.get("event") == name:
                del self.events[i]
                return e
        while True:
            m = self.q.get(timeout=timeout)
            if m is None:
                return None
            if m.get("type") == "event" and m.get("event") == name:
                return m
            self.events.append(m)


def line_of(text):
    with open(PROG, encoding="utf-8") as f:
        for i, l in enumerate(f, 1):
            if text in l:
                return i


def main():
    if shutil.which("node") is None:
        print("adaptateur DAP : ignoré (node absent)")
        print("0 OK, 0 échecs")
        return 0
    c = Client()
    r = c.request("initialize", {"adapterID": "alex", "linesStartAt1": True, "columnsStartAt1": True})
    caps = r["body"]
    check("initialize : capacités", caps["supportsConditionalBreakpoints"] and caps["supportsLogPoints"], caps)
    r = c.request("launch", {"program": PROG, "cwd": os.path.dirname(PROG), "alexPath": ALEX})
    check("launch", r["success"], r)
    check("événement initialized", c.wait_event("initialized") is not None)
    ln = line_of("self.solde = self.solde + montant")
    r = c.request("setBreakpoints", {"source": {"path": PROG}, "breakpoints": [{"line": ln, "condition": "montant == 20"}]})
    check("setBreakpoints vérifiés", r["body"]["breakpoints"][0]["verified"], r)
    c.request("setExceptionBreakpoints", {"filters": []})
    c.request("configurationDone")
    st = c.wait_event("stopped")
    check("arrêt sur point d'arrêt conditionnel", st and st["body"]["reason"] == "breakpoint", st)
    r = c.request("stackTrace", {"threadId": 1})
    frames = r["body"]["stackFrames"]
    check("pile : Compte.deposer en tête", frames[0]["name"] == "Compte.deposer" and frames[0]["line"] == ln, frames)
    r = c.request("scopes", {"frameId": frames[0]["id"]})
    scopes = r["body"]["scopes"]
    check("scopes Locales + Globales", [s["name"] for s in scopes] == ["Locales", "Globales"], scopes)
    r = c.request("variables", {"variablesReference": scopes[0]["variablesReference"]})
    vs = {v["name"]: v for v in r["body"]["variables"]}
    check("variables locales (self, montant)", vs.get("montant", {}).get("value") == "20" and vs["self"]["variablesReference"] > 0, vs)
    r = c.request("variables", {"variablesReference": vs["self"]["variablesReference"]})
    champs = [v["name"] for v in r["body"]["variables"]]
    check("dépliage de self", champs == ["historique", "nom", "solde"], champs)
    r = c.request("evaluate", {"expression": "self.solde * 2", "frameId": frames[0]["id"], "context": "hover"})
    check("evaluate", r["success"] and r["body"]["result"] == "40", r)
    r = c.request("evaluate", {"expression": "nimporte", "frameId": frames[0]["id"], "context": "watch"})
    check("evaluate : erreur", not r["success"], r)
    c.request("next", {"threadId": 1})
    st = c.wait_event("stopped")
    check("pas à pas principal", st["body"]["reason"] == "step", st)
    c.request("continue", {"threadId": 1})
    # le programme lit une ligne : la console de débogage la fournit
    out = c.wait_event("output")
    while out is not None and "saisie" not in out["body"]["output"]:
        out = c.wait_event("output")
    r = c.request("evaluate", {"expression": "Bob", "context": "repl"})
    check("saisie du programme par la console", r["success"], r)
    t = c.wait_event("terminated", 30)
    check("fin de session", t is not None)
    sortie = "".join(e["body"]["output"] for e in c.events if e.get("event") == "output")
    check("sortie du programme transmise", "bonjour Bob" in sortie, sortie[-300:])
    c.p.stdin.close()
    c.p.wait(timeout=10)
    print("%d OK, %d échecs" % (ok, ko))
    return 0 if ko == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
