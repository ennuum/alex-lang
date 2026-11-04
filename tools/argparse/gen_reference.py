#!/usr/bin/env python3
"""Génère tests/argparse/reference.json : résultats de RÉFÉRENCE de l'argparse de Python
(3.12) sur les mêmes parseurs et les mêmes arguments que stdlib/argparse.

    python3 tools/argparse/gen_reference.py          # depuis la racine du projet

Le test tests/argparse/test_argparse.al rejoue chaque cas avec argparse (ALEX) et compare :
  - parse : résultat identique (ou erreur dans les deux cas) ;
  - aide  : texte de format_help() identique (langue "en", largeur 78).
Les écarts VOLONTAIRES d'ALEX sont listés dans OVERRIDES_PARSE / OVERRIDES_HELP avec leur raison ;
leur attendu est celui d'ALEX, pas celui de Python.
"""
import argparse, json, os

os.environ["COLUMNS"] = "80"


class Err(Exception):
    pass


class RaisingParser(argparse.ArgumentParser):
    def error(self, message):
        raise Err(message)


def A(*names, **opts):
    return {"names": list(names), "opts": opts}


TYPES = {"int": int, "float": float}


# --- cas d'analyse -----------------------------------------------------------------------
P = {}
P["basic"] = {"args": [A("-v","--verbose",action="store_true"), A("-q",action="store_false",dest="quiet"), A("-n","--num",type="int"), A("--name",default="x"), A("pos"), A("rest",nargs="*")]}
P["flags"] = {"args": [A("-a",action="store_true"), A("-b",action="store_true"), A("-c",action="store_true"), A("-n",type="int"), A("-s"), A("-v",action="count",default=0)]}
P["nargs"] = {"args": [A("--two",nargs=2,type="int"), A("--many",nargs="+"), A("--any",nargs="*"), A("--opt",nargs="?",const="C",default="D"), A("x"), A("y",nargs="?"), A("z",nargs="*")]}
P["bt"] = {"args": [A("a",nargs="*"), A("b"), A("c",nargs="?")]}
P["bt2"] = {"args": [A("a"), A("b",nargs="+"), A("c")]}
P["interleave"] = {"args": [A("x"), A("y"), A("--o"), A("-f",action="store_true")]}
P["neg"] = {"args": [A("-x",type="int"), A("p",nargs="*",type="int"), A("-f",action="store_true")]}
P["negopt"] = {"args": [A("-1",action="store_true",dest="one"), A("p",nargs="*")]}
P["append"] = {"args": [A("-i",action="append"), A("-I",action="append",type="int"), A("--k",action="append_const",const=7,dest="ks"), A("--e",action="extend",nargs="+"), A("p",nargs="*")]}
P["choices"] = {"args": [A("--c",choices=["a","b"]), A("--n",type="int",choices=[1,2,3]), A("p",choices=["x","y"],nargs="?"), A("--m",nargs="+",choices=["a","b"])]}
P["req"] = {"args": [A("--r",required=True), A("p")]}
P["const"] = {"args": [A("--x",action="store_const",const=5), A("--d",default="dv"), A("--t",type="int",default="12"), A("--f",type="float")]}
P["remainder"] = {"args": [A("-v",action="store_true"), A("cmd"), A("args",nargs="remainder")]}
P["mutex"] = {"args": [A("p",nargs="?")], "mutex": [{"required": False, "args": [A("--a",action="store_true"), A("--b",action="store_true")]}]}
P["mutexr"] = {"args": [], "mutex": [{"required": True, "args": [A("--a",action="store_true"), A("--b")]}]}
P["abbrev"] = {"args": [A("--verbose",action="store_true"), A("--version2",action="store_true"), A("--output"), A("--out2")]}
P["noabbrev"] = {"allow_abbrev": False, "args": [A("--verbose",action="store_true"), A("--output")]}
P["bool"] = {"args": [A("--color",action="boolean_optional"), A("--k",action="boolean_optional",default=True)]}
P["sub"] = {"args": [A("--g",action="store_true"), A("--lvl",default="0")], "sub": {"dest": "cmd", "commands": [
    {"name":"add","aliases":["a"],"args":[A("paths",nargs="+"), A("-f",action="store_true"), A("--lvl",default="sub")]},
    {"name":"rm","aliases":["remove","r"],"args":[A("name"), A("--hard",action="store_true")]},
    {"name":"remote","args":[], "sub": {"dest":"rcmd","commands":[{"name":"add","args":[A("n"),A("u")]},{"name":"show","args":[A("n",nargs="?")]}]}}]}}
P["subreq"] = {"args": [], "sub": {"dest": "cmd", "required": True, "commands": [{"name":"go","args":[A("t",nargs="?")]}]}}
P["pre"] = {"args": [A("x"), A("-q",action="store_true")], "sub": {"dest": "c", "commands": [{"name":"go","args":[A("t")]}]}}
P["dup"] = {"args": [A("-a"), A("-b",action="store_true")]}

C = []
def c(p, *argv): C.append([p, list(argv)])
for a in (["x"], ["-v","x"], ["x","-v"], ["--verbose","--num","5","x"], ["--num=5","x"], ["-n5","x"], ["-n","5","x","a","b"], ["-n","z","x"], [], ["x","y","z"], ["-q","x"], ["--name=","x"], ["--nam","k","x"], ["--bogus","x"], ["-x"], ["--","x"], ["--","-v"], ["x","--","-v","y"], ["-n"], ["-n","--verbose","x"], ["-vn3","x"], ["-nv","x"]): c("basic",*a)
for a in (["-abc"], ["-ab","-c"], ["-an5"], ["-ans"], ["-n5","-a"], ["-s","-a"], ["-sfoo"], ["-vvv"], ["-v","-v"], ["-a","-v","-a"], ["-ac","-v"], ["-abz"], ["-b=1"], ["-n=5"], ["-s=x"], ["-s","-"], ["-s","--"], ["-n","-5"], ["-vn-5"], ["-"], ["-","-a"]): c("flags",*a)
for a in (["x"], ["x","y"], ["x","y","z","w"], ["--two","1","2","x"], ["--two","1","x"], ["--two","1","2","3","x"], ["--many","a","b","x"], ["--many","x"], ["--many","a","--any","b","c","x"], ["--opt","x"], ["--opt","--any","x"], ["x","--opt"], ["x","--opt","v"], ["--opt","v"], ["x","--any"], ["x","--any","a","b"], ["x","y","--any","a","z"], ["x","--many","a","y","z"], ["x","--two","1","2","y","z","w"]): c("nargs",*a)
for a in (["1"], ["1","2"], ["1","2","3"], ["1","2","3","4"], []): c("bt",*a)
for a in (["1","2"], ["1","2","3"], ["1","2","3","4"], ["1","2","3","4","5"], ["1"]): c("bt2",*a)
for a in (["a","b"], ["a","-f","b"], ["-f","a","b"], ["a","b","-f"], ["a","--o","1","b"], ["a"], ["a","b","c"], ["--o","1","a","b"], ["--o","a","b"]): c("interleave",*a)
for a in (["-1"], ["-1","2"], ["-x","-5"], ["-x","-5","-3"], ["-3.5"], ["-x","-.5"], ["-f","-4"], ["-1.5","-f"], ["-x5","-f","-2"], ["-e"], ["-1e5"]): c("neg",*a)
for a in (["-1"], ["-2"], ["-1","a"], ["a","-1"], ["-12"]): c("negopt",*a)
for a in ([], ["-i","a","-i","b"], ["-I","1","-I","2"], ["--k","--k"], ["--e","a","b","--e","c"], ["-i","a","p","q"], ["-I","x"], ["--e"]): c("append",*a)
for a in (["--c","a"], ["--c","z"], ["--n","2"], ["--n","9"], ["--n","x"], ["x"], ["z"], ["--m","a","b"], ["--m","a","z"], []): c("choices",*a)
for a in (["--r","1","p"], ["p"], ["--r","1"], [], ["--r"], ["p","--r","1"]): c("req",*a)
for a in ([], ["--x"], ["--t","3"], ["--f","1.5"], ["--f","1e2"], ["--f",".5"], ["--f","x"], ["--f","5."], ["--t","1_0"], ["--t"," 4"], ["--t","+4"], ["--d","z"]): c("const",*a)
for a in (["run"], ["run","a","b"], ["-v","run","a"], ["run","-v"], ["run","--","a"], ["run","--x","y"], ["-v"], [], ["--","run","a"]): c("remainder",*a)
for a in ([], ["--a"], ["--b"], ["--a","--b"], ["--a","p"], ["p","--b"], ["--a","--a"]): c("mutex",*a)
for a in ([], ["--a"], ["--b","1"], ["--a","--b","1"], ["--b"]): c("mutexr",*a)
for a in (["--verb"], ["--ver"], ["--version"], ["--version2"], ["--v"], ["--out","x"], ["--out=x"], ["--outp","x"], ["--out2","x"], ["--o","x"]): c("abbrev",*a)
for a in (["--verb"], ["--verbose"], ["--out","x"], ["--output","x"], ["--output=x"]): c("noabbrev",*a)
for a in ([], ["--color"], ["--no-color"], ["--no-k"], ["--k"], ["--color","--no-color"]): c("bool",*a)
for a in ([], ["add","x"], ["add","x","y","-f"], ["a","x"], ["add"], ["rm","n"], ["remove","n","--hard"], ["r","n"], ["--g","add","x"], ["add","--g","x"], ["add","x","--g"], ["--lvl","5","add","x"], ["add","--lvl","6","x"], ["--lvl","5","rm","n"], ["remote","add","n","u"], ["remote","show"], ["remote","show","n"], ["remote"], ["remote","zzz"], ["zzz"], ["add","x","--","-f"], ["add","--","x"], ["--","add","x"], ["add","x","--bogus"], ["rm"], ["rm","a","b"], ["-x"], ["--g"], ["add","-f","x","-f"]): c("sub",*a)
for a in ([], ["go"], ["go","t"], ["x"]): c("subreq",*a)
for a in (["x","go","t"], ["go","t"], ["x"], ["-q","x","go","t"], ["x","-q","go","t"], ["x","go","-q"]): c("pre",*a)
for a in (["-a","v"], ["-av"], ["-ab"], ["-ba"], ["-bav"], ["-a"], ["-b","-a","x"], ["-ax"]): c("dup",*a)


# --- cas d'aide ----------------------------------------------------------------------------
H = {}
H["simple"] = {"description": "A simple tool that does things, with a fairly long description that must wrap across several lines of output text.", "epilog": "Epilog text here that is also fairly long and should wrap nicely at the width we configured for the test.",
  "args": [A("-v","--verbose",action="store_true",help="be more verbose"), A("-n","--num",type="int",help="number of things"), A("--name",default="bob",help="a name (default: %(default)s)"), A("--very-long-option-name",metavar="VALUE",help="this option has a very long invocation string"), A("-c","--choice",choices=["alpha","beta","gamma"],help="pick one"), A("src",help="source file"), A("dst",nargs="?",help="optional destination"), A("files",nargs="*",help="more files"), A("others",nargs="+",help="at least one")]}
H["usagewrap"] = {"args": [A("--alpha-option",metavar="ALPHA"), A("--beta-option",metavar="BETA"), A("--gamma-option",metavar="GAMMA"), A("--delta-option",metavar="DELTA"), A("--epsilon-option",metavar="EPSILON"), A("-x",action="store_true"), A("first"), A("second"), A("third",nargs="+")]}
H["mutex"] = {"args": [A("pos")], "mutex": [{"required": False, "args": [A("--a",action="store_true",help="a flag"), A("--b",help="b value")]}, {"required": True, "args": [A("-x",action="store_true"), A("-y",action="store_true")]}]}
H["groups"] = {"args": [A("--top",help="top level")], "groups": [{"title": "Network", "description": "Network related options.", "args": [A("--host",help="host name"), A("--port",type="int",help="port number")]}, {"title": "Files", "args": [A("--out",help="output")]}]}
H["nargs"] = {"args": [A("--two",nargs=2,metavar=("A","B"),help="two things"), A("--opt",nargs="?",help="optional value"), A("--many",nargs="*"), A("--plus",nargs="+"), A("--cnt",action="count",help="counter"), A("--k",action="append",help="repeat me"), A("--bo",action="boolean_optional",help="toggle")]}
H["hidden"] = {"args": [A("--shown",help="visible"), A("--secret",help="==SUPPRESS=="), A("hid",help="==SUPPRESS=="), A("vis")]}
H["sub"] = {"description": "Top.", "args": [A("--g",action="store_true",help="global")], "sub": {"dest": "cmd", "help": "sub-command help", "commands": [{"name":"add","aliases":["a"],"help":"Add things to the thing","args":[A("paths",nargs="+")]},{"name":"remove","aliases":["rm","r"],"help":"Remove things","args":[]},{"name":"remote","help":"Manage a remote that has a very long help string which should wrap onto a second line okay","args":[]}]}}
H["subtitle"] = {"args": [], "sub": {"dest": "cmd", "title": "commands", "description": "available commands", "commands": [{"name":"go","help":"go somewhere","args":[]},{"name":"stop","help":"stop","args":[]}]}}
H["longprog"] = {"prog": "a-very-long-program-name-that-takes-up-lots-of-room-in-the-usage-line-yes", "args": [A("--alpha-option",metavar="ALPHA"), A("--beta-option",metavar="BETA"), A("pos")]}
H["defaults"] = {"args": [A("--n",type="int",default=5,help="n is %(default)s and type %(type)s"), A("--c",choices=["a","b"],help="from %(choices)s"), A("--m",metavar="MM",help="metavar %(metavar)s dest %(dest)s"), A("--pct",help="100%% sure")]}


# Écarts VOLONTAIRES d'ALEX par rapport à Python (index du cas -> attendu ALEX).
OVERRIDES_PARSE = {
    # x? y*: les positionnels optionnels ne sont pas consommés à vide avant une option (Python
    # laisse alors « y z w » en arguments non reconnus).
    61: {"ok": {"any": None, "many": None, "opt": "D", "two": [1, 2], "x": "x", "y": "y", "z": ["z", "w"]}},
    # int() de Python accepte « 1_0 » et les espaces ; ALEX exige [+-]chiffres.
    129: "ERR",
    130: "ERR",
    # une valeur donnée AVANT la sous-commande n'est jamais écrasée par le défaut de la sous-commande
    # (Python : lvl == "sub", la valeur 5 est perdue).
    186: {"ok": {"cmd": "add", "f": False, "g": False, "lvl": "5", "paths": ["x"]}},
    # `-- add x` : tout après -- est positionnel, la sous-commande est reconnue (Python : erreur).
    197: {"ok": {"cmd": "add", "f": False, "g": False, "lvl": "sub", "paths": ["x"]}},
}
OVERRIDES_HELP = {
    # métavar des sous-commandes : noms canoniques sans alias ({add,remove,remote}).
    "sub": """usage: t [-h] [--g] {add,remove,remote} ...

Top.

positional arguments:
  {add,remove,remote}  sub-command help
    add (a)            Add things to the thing
    remove (rm, r)     Remove things
    remote             Manage a remote that has a very long help string which
                       should wrap onto a second line okay

options:
  -h, --help           show this help message and exit
  --g                  global
""",
}


def add(p, a):
    o = dict(a["opts"])
    if "type" in o:
        o["type"] = TYPES[o["type"]]
    if o.get("nargs") == "remainder":
        o["nargs"] = argparse.REMAINDER
    if o.get("help") == "==SUPPRESS==":
        o["help"] = argparse.SUPPRESS
    if o.get("action") == "boolean_optional":
        o["action"] = argparse.BooleanOptionalAction
    if isinstance(o.get("metavar"), list):
        o["metavar"] = tuple(o["metavar"])
    p.add_argument(*a["names"], **o)


def build(s, prog="t", aliasmap=None):
    kw = {}
    if "allow_abbrev" in s:
        kw["allow_abbrev"] = s["allow_abbrev"]
    p = RaisingParser(prog=s.get("prog", prog), description=s.get("description"), epilog=s.get("epilog"), **kw)
    for a in s.get("args", []):
        add(p, a)
    for g in s.get("groups", []):
        gg = p.add_argument_group(g["title"], g.get("description"))
        for a in g["args"]:
            add(gg, a)
    for m in s.get("mutex", []):
        mg = p.add_mutually_exclusive_group(required=m["required"])
        for a in m["args"]:
            add(mg, a)
    if "sub" in s:
        so = s["sub"]
        kws = {"dest": so["dest"], "required": so.get("required", False)}
        if "help" in so:
            kws["help"] = so["help"]
        if "title" in so:
            kws["title"] = so["title"]
            kws["description"] = so.get("description")
        sp = p.add_subparsers(**kws)
        for c in so["commands"]:
            sub = sp.add_parser(c["name"], aliases=c.get("aliases", []), help=c.get("help"))
            for a in c.get("args", []):
                add(sub, a)
            if "sub" in c:
                sp2 = sub.add_subparsers(dest=c["sub"]["dest"], required=c["sub"].get("required", False))
                for c2 in c["sub"]["commands"]:
                    s2 = sp2.add_parser(c2["name"], aliases=c2.get("aliases", []))
                    for a in c2.get("args", []):
                        add(s2, a)
            if aliasmap is not None:
                for al in c.get("aliases", []):
                    aliasmap[al] = c["name"]
    return p


expected = []
for pname, argv in C:
    am = {}
    p = build(P[pname], aliasmap=am)
    try:
        r = vars(p.parse_args(argv))
        for k, v in list(r.items()):
            if isinstance(v, str) and v in am and k in ("cmd", "c", "rcmd"):
                r[k] = am[v]
        expected.append({"ok": r})
    except (Err, SystemExit):
        expected.append("ERR")
for i, v in OVERRIDES_PARSE.items():
    expected[i] = v

help_expected = {}
for name, s in H.items():
    help_expected[name] = OVERRIDES_HELP.get(name) or build(s).format_help()

here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests", "argparse")
os.makedirs(here, exist_ok=True)
with open(os.path.join(here, "reference.json"), "w") as f:
    json.dump({"parsers": P, "cases": C, "expected": expected, "help_specs": H, "help_expected": help_expected,
               "overrides_parse": sorted(OVERRIDES_PARSE), "overrides_help": sorted(OVERRIDES_HELP)}, f, indent=1, sort_keys=True)
print(len(C), "cas d'analyse,", len(H), "cas d'aide ->", os.path.normpath(os.path.join(here, "reference.json")))
