#!/usr/bin/env python3
"""Tests des commandes d'outillage : alex new, alex test, alex fmt, alex doc, alex run --profile.

Usage : python3 tests/tooling/tools_test.py [chemin/vers/alex]
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ALEX = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "alex"))
ok = ko = 0


def check(name, cond, extra=""):
    global ok, ko
    if cond:
        ok += 1
        print("  ok   " + name)
    else:
        ko += 1
        print("  ÉCHEC " + name + ("  -> " + str(extra)[:800] if extra != "" else ""))


def run(args, cwd=None, timeout=120):
    env = dict(os.environ, ALEX_UI_BACKEND="headless")
    p = subprocess.run([ALEX, *args], cwd=cwd, capture_output=True, timeout=timeout, env=env)
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")


def main():
    tmp = tempfile.mkdtemp(prefix="alex_tools_")
    try:
        # ---- alex new : chaque modèle produit un projet dont les tests passent
        code, out, _ = run(["new", "--list", "--json"])
        templates = json.loads(out)
        ids = [t["id"] for t in templates]
        check("alex new --list --json", {"console", "gui", "cli", "lib", "server", "kernel", "driver"} <= set(ids), ids)
        for t in ids:
            code, out, err = run(["new", t, "p_" + t, "--dir", tmp])
            proj = os.path.join(tmp, "p_" + t)
            check("alex new %s" % t, code == 0 and os.path.isfile(os.path.join(proj, "alex.toml"))
                  and os.path.isfile(os.path.join(proj, ".github", "workflows", "alex.yml")), out + err)
            code, out, err = run(["test", "--json"], cwd=proj)
            summary = json.loads(out.strip().splitlines()[-1]) if out.strip() else {}
            check("modèle %s : tests réussis" % t, code == 0 and summary.get("passed", 0) >= 1
                  and summary.get("failed") == 0 and summary.get("errors") == 0, out + err)
        code, out, err = run(["new", "console", "p_console", "--dir", tmp])
        check("alex new refuse un dossier existant", code != 0 and "existe" in err, err)
        code, out, err = run(["new", "console", "9mauvais", "--dir", tmp])
        check("alex new refuse un nom invalide", code != 0, err)

        # ---- alex test : échecs, erreurs, filtres, JSON, liste
        proj = os.path.join(tmp, "p_console")
        with open(os.path.join(proj, "tests", "test_echecs.al"), "w") as f:
            f.write("use testing\n\nfunc test_faux():\n    testing.assert_eq(1 + 1, 3)\n\n"
                    "func test_erreur():\n    x := [1][5]\n\nfunc test_bon():\n    testing.assert_true(true)\n")
        code, out, _ = run(["test", "--json"], cwd=proj)
        evs = [json.loads(l) for l in out.splitlines() if l.strip()]
        tests = {e["name"]: e for e in evs if e["event"] == "test"}
        check("alex test : échec détecté avec message et ligne",
              tests.get("test_faux", {}).get("status") == "failed" and tests["test_faux"]["line"] == 3
              and "attendu 3" in tests["test_faux"]["message"], tests.get("test_faux"))
        check("alex test : erreur (exception) détectée", tests.get("test_erreur", {}).get("status") == "error", tests.get("test_erreur"))
        check("alex test : code de sortie 1", code == 1, code)
        code, out, _ = run(["test", "--json", "--filter", "bon"], cwd=proj)
        evs = [json.loads(l) for l in out.splitlines() if l.strip()]
        names = [e["name"] for e in evs if e["event"] == "test"]
        check("alex test --filter", "test_bon" in names and "test_faux" not in names, names)
        code, out, _ = run(["test", "--list", "--json"], cwd=proj)
        listed = [t["name"] for l in out.splitlines() for t in json.loads(l)["tests"]]
        check("alex test --list", {"test_faux", "test_erreur", "test_bon", "test_bonjour"} <= set(listed), listed)
        os.unlink(os.path.join(proj, "tests", "test_echecs.al"))

        # ---- alex fmt
        messy = os.path.join(tmp, "sale.al")
        with open(messy, "w") as f:
            f.write("func f():\n\tx := 1   \n\n\n\n\treturn x")
        code, out, _ = run(["fmt", "--check", messy])
        check("alex fmt --check signale", code == 1, out)
        code, out, _ = run(["fmt", messy])
        check("alex fmt corrige", open(messy).read() == "func f():\n    x := 1\n\n\n    return x\n", open(messy).read())
        code, out, _ = run(["fmt", "--check", messy])
        check("alex fmt idempotent", code == 0, out)

        # ---- alex doc
        code, out, _ = run(["doc", "json"])
        check("alex doc json (Markdown)", code == 0 and out.startswith("# json") and "## parse" in out, out[:200])
        code, out, _ = run(["doc", "--json", "network.http"])
        d = json.loads(out)
        names = [e["name"] for e in d["entries"]]
        server = [e for e in d["entries"] if e["name"] == "Server"]
        check("alex doc --json : entrées et membres", "Server" in names and server
              and any(m["name"] == "serve" for m in server[0].get("members", [])), names[:20])
        site = os.path.join(tmp, "site")
        code, out, err = run(["doc", "--html", site])
        pages = os.listdir(site) if os.path.isdir(site) else []
        check("alex doc --html : site complet de la stdlib", code == 0 and "index.html" in pages and len(pages) > 300, err)
        code, out, err = run(["doc", "--html", os.path.join(tmp, "site2"), os.path.join(tmp, "p_lib", "p_lib.al")])
        html = open(os.path.join(tmp, "site2", "p_lib.html")).read() if code == 0 else ""
        check("alex doc --html sur un fichier de projet", "slug" in html and "Nombre de mots" in html, err)

        # ---- alex run --profile
        prog = os.path.join(tmp, "prof.al")
        with open(prog, "w") as f:
            f.write("func fib(n):\n    if n < 2:\n        return n\n    return fib(n - 1) + fib(n - 2)\n\nprint(fib(15))\n")
        report = os.path.join(tmp, "prof.json")
        code, out, err = run(["run", "--profile=" + report, prog])
        data = json.load(open(report)) if os.path.isfile(report) else {}
        fib = [f for f in data.get("functions", []) if f["name"] == "fib"]
        check("alex run --profile : sortie inchangée", out.strip() == "610", out)
        check("alex run --profile : appels exacts (fib(15) = 1973 appels)", fib and fib[0]["calls"] == 1973, fib)
        check("alex run --profile : rapport texte", "Profil ALEX" in err and "fib" in err, err[:300])
        check("alex run --profile : lignes chaudes", any(l["line"] == 4 for l in data.get("lines", [])), data.get("lines"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("%d OK, %d échecs" % (ok, ko))
    return 0 if ko == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
