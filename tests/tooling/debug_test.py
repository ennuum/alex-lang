#!/usr/bin/env python3
"""Tests du débogueur `alex debug --protocol 2` (protocole utilisé par ALEX Studio).

Usage : python3 tests/tooling/debug_test.py [chemin/vers/alex]
"""
import json
import os
import queue
import subprocess
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ALEX = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "alex")
PROG = os.path.join(HERE, "dbg", "prog.al")

ok = 0
ko = 0


def check(name, cond, extra=""):
    global ok, ko
    if cond:
        ok += 1
        print("  ok   " + name)
    else:
        ko += 1
        print("  ÉCHEC " + name + ("  -> " + json.dumps(extra, ensure_ascii=False)[:600] if extra != "" else ""))


class Session:
    def __init__(self, *flags, args=()):
        env = dict(os.environ, ALEX_UI_BACKEND="headless")
        self.p = subprocess.Popen([ALEX, "debug", "--protocol", "2", *flags, PROG, *args], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        self.q = queue.Queue()
        self.output = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.p.stdout:
            try:
                ev = json.loads(line.decode("utf-8"))
            except ValueError:
                ev = {"event": "garbage", "text": line.decode("utf-8", "replace")}
            if ev.get("event") == "output":
                self.output.append(ev)
            self.q.put(ev)
        self.q.put({"event": "eof"})

    def send(self, **cmd):
        self.p.stdin.write((json.dumps(cmd) + "\n").encode())
        self.p.stdin.flush()

    def wait(self, kind, timeout=20):
        """Prochain événement du type demandé (les autres sont ignorés)."""
        while True:
            try:
                ev = self.q.get(timeout=timeout)
            except queue.Empty:
                return {"event": "timeout"}
            if ev["event"] == kind or ev["event"] in ("eof", "compile_error") and kind != ev["event"]:
                return ev

    def close(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        try:
            return self.p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.p.kill()
            return -1


def local(frame, name):
    for v in frame["locals"]:
        if v["name"] == name:
            return v
    return None


def line_of(text):
    with open(PROG, encoding="utf-8") as f:
        for i, l in enumerate(f, 1):
            if text in l:
                return i
    raise KeyError(text)


def main():
    L_DEPOSE = line_of("self.solde = self.solde + montant")
    L_TOTAL_CALL = line_of("t := total([1, 2, 3])")
    L_SOMME = line_of("somme = somme + v")
    L_INPUT = line_of("nom := input()")
    L_DIV = line_of("x := 10 / (t - 6)")

    # ---------------------------------------------------------------- session 1 : points d'arrêt, inspection
    s = Session()
    ev = s.wait("paused")
    check("arrêt d'entrée sur la première ligne du programme", ev.get("reason") == "entry"
          and ev.get("file", "").endswith("prog.al") and ev.get("line", 0) > 0, ev)
    s.send(command="breakpoints.set", file=PROG, breakpoints=[
        {"line": L_DEPOSE, "condition": "montant == 30"},
        {"line": L_TOTAL_CALL},
    ])
    ack = s.wait("ack")
    check("breakpoints.set vérifiés", ack.get("lines") == [L_DEPOSE, L_TOTAL_CALL], ack)
    s.send(command="continue")
    ev = s.wait("paused")
    frames = ev.get("frames", [])
    top = frames[-1] if frames else {}
    check("point d'arrêt conditionnel (montant == 30)", ev.get("reason") == "breakpoint" and ev.get("line") == L_DEPOSE
          and (local(top, "montant") or {}).get("value") == "30", ev)
    check("pile d'appels : <module> > main > Compte.deposer",
          [f["function"] for f in frames] == ["<module>", "main", "Compte.deposer"], [f["function"] for f in frames])
    main_frame = frames[1] if len(frames) > 1 else {}
    c = local(main_frame, "c") or {}
    check("variables nommées du frame appelant (c : Compte)", c.get("type") == "Compte" and "ref" in c, main_frame)
    check("globales du programme (LIMITE)", any(g["name"] == "LIMITE" and g["value"] == "100"
                                                for g in ev.get("globals", [])), ev.get("globals"))
    s.send(command="variables", ref=c.get("ref", 0), id=7)
    ev2 = s.wait("variables")
    names = {v["name"]: v for v in ev2.get("variables", [])}
    check("dépliage d'un objet : champs historique, nom, solde",
          set(names) == {"historique", "nom", "solde"} and names["nom"]["value"] == '"Alice"' and ev2.get("id") == 7,
          ev2)
    hist = names.get("historique", {})
    s.send(command="variables", ref=hist.get("ref", 0))
    ev3 = s.wait("variables")
    check("dépliage d'une liste", [v["value"] for v in ev3.get("variables", [])] == ["0", "10", "20", "30"], ev3)
    s.send(command="evaluate", expression="self.solde + montant * 2")
    r = s.wait("evaluate")
    check("évaluation dans le frame courant", r.get("result") == "100" and r.get("type") == "int", r)
    s.send(command="evaluate", expression="len(c.historique) > 3 and c.nom == \"Alice\"", frame=1)
    r = s.wait("evaluate")
    check("évaluation dans un autre frame", r.get("result") == "true", r)
    s.send(command="evaluate", expression="notes[\"info\"] - LIMITE", frame=1)
    r = s.wait("evaluate")
    check("évaluation : dictionnaire et globale", r.get("result") == "-82", r)
    s.send(command="evaluate", expression="inconnu + 1")
    r = s.wait("evaluate")
    check("évaluation : erreur explicite", "error" in r and "inconnu" in r["error"], r)
    s.send(command="evaluate", expression="c.deposer(5)", frame=1)
    r = s.wait("evaluate")
    check("évaluation : appels à effet de bord refusés", "error" in r, r)

    # step over / into / out
    s.send(command="step", mode="over")
    ev = s.wait("paused")
    check("pas à pas principal (ligne suivante)", ev.get("reason") == "step" and ev.get("line") == L_DEPOSE + 1, ev)
    s.send(command="step", mode="out")
    ev = s.wait("paused")
    check("sortir de la fonction -> retour dans main", ev.get("frames", [{}])[-1].get("function") == "main", ev)
    s.send(command="continue")
    ev = s.wait("paused")
    check("deuxième point d'arrêt (appel de total)", ev.get("line") == L_TOTAL_CALL, ev)
    s.send(command="step", mode="into")
    ev = s.wait("paused")
    check("entrer dans total()", ev.get("frames", [{}])[-1].get("function") == "total", ev)
    s.send(command="step", mode="out")
    ev = s.wait("paused")
    check("retour sans redéclencher le point d'arrêt de la ligne appelante",
          ev.get("reason") == "step" and ev.get("frames", [{}])[-1].get("function") == "main", ev)
    s.send(command="continue")
    ev = s.wait("input")
    check("demande d'entrée du programme", ev.get("event") == "input", ev)
    s.send(command="input", text="Bob")
    ev = s.wait("exception")
    out = "".join(o["text"] for o in s.output)
    check("sortie du programme transportée (stdout)", "bonjour Bob\n6\n" in out, out)
    check("exception non rattrapée signalée", "ZeroDivision" in ev.get("message", ""), ev)
    code = s.close()
    check("code de sortie 1 après exception", code == 1, code)

    # ---------------------------------------------------------------- session 2 : journal, compteur, exception
    s = Session("--break-on-exception")
    s.wait("paused")
    s.send(command="breakpoints.set", file=PROG, breakpoints=[
        {"line": L_SOMME, "logMessage": "somme={somme} v={v}"},
        {"line": L_DEPOSE, "hitCount": 4},
    ])
    s.wait("ack")
    s.send(command="continue")
    ev = s.wait("paused")
    top = ev.get("frames", [{}])[-1]
    check("compteur de passages (4e appel)", ev.get("line") == L_DEPOSE and (local(top, "montant") or {}).get("value")
          == "30", ev)
    s.send(command="continue")
    ev = s.wait("input")
    logs = [o["text"] for o in s.output if o.get("category") == "log"]
    check("points de journalisation sans arrêt", logs == ["somme=0 v=1\n", "somme=1 v=2\n", "somme=3 v=3\n"], logs)
    s.send(command="input", text="Zoé")
    ev = s.wait("paused")
    check("arrêt sur exception non rattrapée, pile intacte",
          ev.get("reason") == "exception" and ev.get("line") == L_DIV
          and ev.get("exception", {}).get("type") == "ZeroDivisionError"
          and (local(ev["frames"][-1], "t") or {}).get("value") == "6", ev)
    s.send(command="continue")
    ev = s.wait("exception")
    check("puis fin sur l'exception", ev.get("exitCode") == 1, ev)
    s.close()

    # ---------------------------------------------------------------- session 3 : pause pendant l'exécution, arrêt
    s = Session()
    s.wait("paused")
    s.send(command="breakpoints.set", file=PROG, breakpoints=[])
    s.send(command="continue")
    ev = s.wait("input")
    s.send(command="pause")
    s.send(command="stop")
    ev = s.wait("stopped")
    check("stop pendant une attente d'entrée", ev.get("event") == "stopped", ev)
    code = s.close()
    check("code de sortie 0 après stop", code == 0, code)

    # ---------------------------------------------------------------- erreur de compilation
    bad = os.path.join(HERE, "dbg", "_bad.al")
    with open(bad, "w") as f:
        f.write("func f(:\n")
    p = subprocess.run([ALEX, "debug", "--protocol", "2", bad], capture_output=True, timeout=20)
    os.unlink(bad)
    ev = json.loads(p.stdout.decode().splitlines()[0])
    check("erreur de compilation signalée dans le protocole", ev.get("event") == "compile_error", ev)

    print("%d OK, %d échecs" % (ok, ko))
    return 0 if ko == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
