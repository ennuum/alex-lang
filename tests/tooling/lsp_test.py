#!/usr/bin/env python3
"""Tests du serveur de langage `alex lsp` : session JSON-RPC réelle sur stdin/stdout.

Usage : python3 tests/tooling/lsp_test.py [chemin/vers/alex]
Affiche « N OK, M échecs » (format vérifié par tests/run_checked.sh).
"""
import json
import os
import pathlib
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ALEX = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "alex")
WS = os.path.join(HERE, "ws")

ok = 0
ko = 0


def check(name, cond, extra=""):
    global ok, ko
    if cond:
        ok += 1
        print("  ok   " + name)
    else:
        ko += 1
        print("  ÉCHEC " + name + ("  -> " + str(extra)[:400] if extra != "" else ""))


class Client:
    def __init__(self):
        self.p = subprocess.Popen([ALEX, "lsp", WS], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE)
        self.next_id = 1
        self.notifications = []

    def send(self, obj):
        body = json.dumps(obj).encode("utf-8")
        self.p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.p.stdin.flush()

    def read(self):
        headers = {}
        while True:
            line = self.p.stdout.readline()
            if not line:
                raise EOFError("serveur terminé")
            line = line.decode().strip()
            if not line:
                break
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
        n = int(headers["content-length"])
        return json.loads(self.p.stdout.read(n).decode("utf-8"))

    def request(self, method, params):
        rid = self.next_id
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        while True:
            m = self.read()
            if m.get("id") == rid and "method" not in m:
                return m
            self.notifications.append(m)

    def change(self, u, version, text):
        # les publications déjà reçues pour u concernent l'ancien texte
        self.notifications = [m for m in self.notifications
                              if not (m.get("method") == "textDocument/publishDiagnostics" and m["params"]["uri"] == u)]
        self.notify("textDocument/didChange", {"textDocument": {"uri": u, "version": version},
                                               "contentChanges": [{"text": text}]})

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def diagnostics_for(self, uri, timeout=10.0):
        """Attend la prochaine publication de diagnostics pour uri."""
        for i, m in enumerate(self.notifications):
            if m.get("method") == "textDocument/publishDiagnostics" and m["params"]["uri"] == uri:
                del self.notifications[i]
                return m["params"]["diagnostics"]
        end = time.time() + timeout
        while time.time() < end:
            m = self.read()
            if m.get("method") == "textDocument/publishDiagnostics" and m["params"]["uri"] == uri:
                return m["params"]["diagnostics"]
            self.notifications.append(m)
        return None


def uri(path):
    # URI standard : file:///home/... sous Linux, file:///D:/... sous Windows
    return pathlib.Path(os.path.abspath(path)).as_uri()


def pos(line, ch):
    return {"line": line, "character": ch}


def find(text, needle, nth=0):
    """Position (ligne, colonne) de la n-ième occurrence de needle."""
    idx = -1
    for _ in range(nth + 1):
        idx = text.index(needle, idx + 1)
    before = text[:idx]
    line = before.count("\n")
    col = idx - (before.rfind("\n") + 1)
    return line, col


def main():
    c = Client()
    r = c.request("initialize", {"processId": None, "rootUri": uri(WS),
                                 "capabilities": {"general": {"positionEncodings": ["utf-16"]}}})
    caps = r["result"]["capabilities"]
    check("initialize : capacités", caps.get("hoverProvider") and caps.get("definitionProvider")
          and caps["completionProvider"]["triggerCharacters"] == ["."], caps)
    check("initialize : encodage utf-16", caps.get("positionEncoding") == "utf-16")
    c.notify("initialized", {})

    main_path = os.path.join(WS, "main.al")
    forme_path = os.path.join(WS, "geo", "forme.al")
    main_text = open(main_path, encoding="utf-8").read()
    forme_text = open(forme_path, encoding="utf-8").read()
    mu, fu = uri(main_path), uri(forme_path)

    c.notify("textDocument/didOpen", {"textDocument": {"uri": mu, "languageId": "alex", "version": 1,
                                                       "text": main_text}})
    d = c.diagnostics_for(mu)
    check("diagnostics : fichier correct (seulement l'import json inutilisé)",
          d is not None and len([x for x in d if x["severity"] == 1]) == 0
          and any(x.get("code") == "unused-import" for x in d), d)

    # --- complétion de membres de module
    l, col = find(main_text, "forme.point")
    r = c.request("textDocument/completion", {"textDocument": {"uri": mu}, "position": pos(l, col + 6)})
    labels = [i["label"] for i in r["result"]["items"]]
    check("complétion forme. -> point, Point, Cercle", "point" in labels and "Point" in labels and "Cercle" in labels,
          labels[:20])

    # --- complétion de membres d'objet typé par inférence (p := forme.point(...) -> Point)
    l, col = find(main_text, "p.norme")
    r = c.request("textDocument/completion", {"textDocument": {"uri": mu}, "position": pos(l, col + 2)})
    labels = [i["label"] for i in r["result"]["items"]]
    check("complétion p. -> norme, x, y", "norme" in labels and "x" in labels, labels[:20])

    l, col = find(main_text, "c.aire", 1)
    r = c.request("textDocument/completion", {"textDocument": {"uri": mu}, "position": pos(l, col + 2)})
    labels = [i["label"] for i in r["result"]["items"]]
    check("complétion c. (classe dérivée) -> aire, rayon, norme (héritée)",
          "aire" in labels and "rayon" in labels and "norme" in labels, labels[:20])

    # --- complétion générale : variables locales, fonctions, mots-clés, extraits
    l, col = find(main_text, "    print(surface_totale")
    r = c.request("textDocument/completion", {"textDocument": {"uri": mu}, "position": pos(l, 4)})
    items = r["result"]["items"]
    labels = [i["label"] for i in items]
    check("complétion générale : locales + fonctions + mots-clés + builtins",
          "p" in labels and "c" in labels and "surface_totale" in labels and "while" in labels and "print" in labels,
          labels[:40])

    # --- complétion d'import
    c.change(mu, 2, "use geo.\n" + main_text)
    r = c.request("textDocument/completion", {"textDocument": {"uri": mu}, "position": pos(0, 8)})
    labels = [i["label"] for i in r["result"]["items"]]
    check("complétion « use geo. » -> forme", "forme" in labels, labels)
    c.change(mu, 3, "use coll\n" + main_text)
    r = c.request("textDocument/completion", {"textDocument": {"uri": mu}, "position": pos(0, 8)})
    labels = [i["label"] for i in r["result"]["items"]]
    check("complétion « use coll » -> collections (stdlib)", "collections" in labels, labels[:30])
    c.change(mu, 4, main_text)

    # --- survol
    l, col = find(main_text, "forme.Cercle")
    r = c.request("textDocument/hover", {"textDocument": {"uri": mu}, "position": pos(l, col + 7)})
    md = (r.get("result") or {}).get("contents", {}).get("value", "")
    check("survol Cercle : signature de classe", "Cercle" in md and "Point" in md, md)
    l, col = find(main_text, "p.norme")
    r = c.request("textDocument/hover", {"textDocument": {"uri": mu}, "position": pos(l, col + 3)})
    md = (r.get("result") or {}).get("contents", {}).get("value", "")
    check("survol p.norme : documentation", "Distance" in md, md)

    # --- aide à la signature
    l, col = find(main_text, "forme.Cercle(0, 0")
    r = c.request("textDocument/signatureHelp", {"textDocument": {"uri": mu},
                                                 "position": pos(l, col + len("forme.Cercle(0, 0, "))})
    res = r.get("result") or {}
    check("signature Cercle(x, y, r) paramètre actif 2",
          res.get("activeParameter") == 2 and "r" in [p["label"] for p in res["signatures"][0]["parameters"]], res)

    # --- définition inter-fichiers
    l, col = find(main_text, "c.aire", 1)
    r = c.request("textDocument/definition", {"textDocument": {"uri": mu}, "position": pos(l, col + 3)})
    locs = r["result"]
    al, acol = find(forme_text, "aire")
    check("définition c.aire -> geo/forme.al", len(locs) == 1 and locs[0]["uri"] == fu
          and locs[0]["range"]["start"]["line"] == al, locs)
    l, col = find(main_text, "surface_totale([c])")
    r = c.request("textDocument/definition", {"textDocument": {"uri": mu}, "position": pos(l, col + 2)})
    locs = r["result"]
    check("définition fonction locale", len(locs) == 1 and locs[0]["range"]["start"]["line"] == 3, locs)

    # --- références
    c.notify("textDocument/didOpen", {"textDocument": {"uri": fu, "languageId": "alex", "version": 1,
                                                       "text": forme_text}})
    c.diagnostics_for(fu)
    l, col = find(forme_text, "func aire")
    r = c.request("textDocument/references", {"textDocument": {"uri": fu}, "position": pos(l, col + 6),
                                              "context": {"includeDeclaration": True}})
    refs = r["result"]
    check("références aire : déclaration + 2 usages dans main.al (dont un objet non typé)",
          len(refs) == 3 and sum(1 for x in refs if x["uri"] == mu) == 2, refs)
    l, col = find(forme_text, "self.rayon * self.rayon")
    r = c.request("textDocument/documentHighlight", {"textDocument": {"uri": fu}, "position": pos(l, col + 6)})
    check("surbrillance rayon : 3 occurrences", len(r["result"]) == 3, r["result"])

    # --- renommage
    r = c.request("textDocument/prepareRename", {"textDocument": {"uri": fu}, "position": pos(l, col + 6)})
    check("prepareRename rayon", (r.get("result") or {}).get("placeholder") == "rayon", r)
    l, col = find(forme_text, "func aire")
    r = c.request("textDocument/rename", {"textDocument": {"uri": fu}, "position": pos(l, col + 6),
                                          "newName": "surface"})
    ch = (r.get("result") or {}).get("changes", {})
    n = sum(len(v) for v in ch.values())
    check("renommage aire -> surface : 3 modifications dans 2 fichiers", n == 3 and len(ch) == 2, r)
    r = c.request("textDocument/rename", {"textDocument": {"uri": fu}, "position": pos(l, col + 6),
                                          "newName": "while"})
    check("renommage vers un mot-clé refusé", "error" in r, r)
    l2, col2 = find(forme_text, "math.sqrt")
    r = c.request("textDocument/rename", {"textDocument": {"uri": fu}, "position": pos(l2, col2 + 6),
                                          "newName": "racine"})
    check("renommage d'un symbole de la stdlib refusé", "error" in r, r)

    # --- symboles
    r = c.request("textDocument/documentSymbol", {"textDocument": {"uri": fu}})
    syms = r["result"]
    names = [s["name"] for s in syms]
    point = [s for s in syms if s["name"] == "Point"]
    check("symboles du document : Point, Cercle, point + méthodes imbriquées",
          names[:3] == ["Point", "Cercle", "point"] or set(["Point", "Cercle", "point"]) <= set(names), names)
    check("symboles : Point contient norme", point and "norme" in [x["name"] for x in point[0].get("children", [])],
          point)
    r = c.request("workspace/symbol", {"query": "cerc"})
    check("symboles de l'espace de travail : cerc -> Cercle", any(s["name"] == "Cercle" for s in r["result"]),
          r["result"])

    # --- diagnostics d'erreurs
    bad = main_text.replace("total = total + c.aire()", "total = total + inconnu")
    c.change(mu, 5, bad)
    d = c.diagnostics_for(mu)
    errs = [x for x in d or [] if x["severity"] == 1]
    l, col = find(bad, "inconnu")
    check("diagnostic NameError positionné", len(errs) == 1 and errs[0]["range"]["start"]["line"] == l
          and errs[0]["range"]["start"]["character"] == col, d)

    bad2 = main_text.replace("func main():", "func main(:")
    c.change(mu, 6, bad2)
    d = c.diagnostics_for(mu)
    errs = [x for x in d or [] if x["severity"] == 1]
    l, col = find(bad2, "func main(:")
    check("diagnostic de syntaxe sur la bonne ligne", len(errs) >= 1 and errs[0]["range"]["start"]["line"] == l, d)
    # l'index reste utilisable malgré l'erreur de syntaxe (réparation)
    l, col = find(bad2, "p.norme")
    r = c.request("textDocument/completion", {"textDocument": {"uri": mu}, "position": pos(l, col + 2)})
    labels = [i["label"] for i in r["result"]["items"]]
    check("complétion malgré une erreur de syntaxe ailleurs", "norme" in labels, labels[:10])

    # --- actions rapides
    bad3 = main_text.replace("    total := 0.0\n", "    total := 0.0\n    m := factorial(3)\n")
    c.change(mu, 7, bad3)
    d = c.diagnostics_for(mu)
    errs = [x for x in d or [] if x["severity"] == 1]
    r = c.request("textDocument/codeAction", {"textDocument": {"uri": mu}, "range": errs[0]["range"] if errs else
                                              {"start": pos(0, 0), "end": pos(0, 0)},
                                              "context": {"diagnostics": errs}})
    titles = [a["title"] for a in r.get("result") or []]
    check("action rapide : importer factorial", any("factorial" in t for t in titles), (d, titles))
    unused = [x for x in (d or []) if x.get("code") == "unused-import"]
    r = c.request("textDocument/codeAction", {"textDocument": {"uri": mu}, "range": unused[0]["range"] if unused
                                              else {"start": pos(0, 0), "end": pos(0, 0)},
                                              "context": {"diagnostics": unused}})
    titles = [a["title"] for a in r.get("result") or []]
    check("action rapide : supprimer l'import inutilisé", any("upprimer" in t for t in titles), titles)

    # --- mise en forme
    messy = "func f():\n\tx := 1   \n\n\n\n\treturn x"
    c.change(mu, 8, messy)
    r = c.request("textDocument/formatting", {"textDocument": {"uri": mu},
                                              "options": {"tabSize": 4, "insertSpaces": True}})
    edits = r["result"]
    check("mise en forme", len(edits) == 1 and edits[0]["newText"] == "func f():\n    x := 1\n\n\n    return x\n",
          edits)

    # --- UTF-16 : colonnes après des caractères accentués / hors BMP
    utf = "func f():\n    ok := 1\n    t := {\"é😀\": ok}\n    return t\n"
    c.change(mu, 9, utf)
    # « ok » de la ligne 2 : 4 + len('t := {"') + é (1) + 😀 (2 unités UTF-16) + len('": ') = 17
    r = c.request("textDocument/definition", {"textDocument": {"uri": mu}, "position": pos(2, 17)})
    locs = r["result"]
    check("positions UTF-16 converties (définition)", len(locs) == 1 and locs[0]["range"]["start"] == pos(1, 4), locs)
    r = c.request("textDocument/documentHighlight", {"textDocument": {"uri": mu}, "position": pos(1, 5)})
    starts = sorted((h["range"]["start"]["line"], h["range"]["start"]["character"]) for h in r["result"])
    check("positions UTF-16 converties (surbrillance)", starts == [(1, 4), (2, 17)], starts)
    bad_utf = "func f():\n    été := 1\n"
    c.change(mu, 10, bad_utf)
    d = c.diagnostics_for(mu)
    check("message d'erreur en UTF-8 valide", d is not None and len(d) >= 1, d)

    # --- méthode inconnue, arrêt
    r = c.request("alex/inexistant", {})
    check("méthode inconnue -> -32601", r.get("error", {}).get("code") == -32601, r)
    r = c.request("shutdown", None)
    check("shutdown", "result" in r and r["result"] is None, r)
    c.notify("exit", None)
    try:
        code = c.p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        c.p.kill()
        code = -1
    check("exit code 0", code == 0, code)

    print("%d OK, %d échecs" % (ok, ko))
    return 0 if ko == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
