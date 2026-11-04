# Test du module argparse (+ cli) : analyse, sous-commandes, aide, messages, man, complétion.
#
#   - cas de RÉFÉRENCE : tests/argparse/reference.json, produit par tools/argparse/gen_reference.py
#     avec l'argparse de Python (222 analyses, 10 aides) ; les écarts volontaires y sont marqués ;
#   - cas écrits à la main : options, types, erreurs (messages exacts), i18n, configuration ;
#   - sous-processus : codes de sortie réels (exit_on_error=true) ; set ALEX_BIN pour le binaire
#     (défaut ./alex) ;
#   - complétion Bash exécutée pour de vrai (bash requis), Zsh vérifié par `zsh -n`, PowerShell par
#     contrôle structurel (non exécuté) ; man vérifié par `groff -ww` s'il est installé.

from core use len, type
from collections use append, clear, contains, contains_key, keys
use collections as col
use string as s
use os as os
use file as file
use json as json
use process as process
use argparse as argparse
use cli as cli

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

func run(name, fn):
    clear(notes)
    before := stats[1]
    fn()
    if stats[1] > before:
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [OK]     {name}")

func mk(prog="t", opts=null):
    o := {"exit_on_error": false}
    if opts != null:
        for k in keys(opts):
            o[k] = opts[k]
    return argparse.ArgumentParser(prog, o)

# Dernière ligne d'un message (le « prog: erreur: … »), ou "" si le parse réussit.
func err_line(p, argv):
    try:
        p.parse_args(argv)
    catch e:
        if e.type != "ArgparseError":
            return "AUTRE:" + e.type + ":" + e.message
        lines := s.split(e.message, "\n")
        return lines[len(lines) - 1]
    return ""

func ok(p, argv):
    return p.parse_args(argv)

func raises(f, error_type, label):
    got := "aucune erreur"
    try:
        f()
    catch e:
        got = e.type
    check_eq(got, error_type, label)

func ser(v):
    return json.stringify(v)

# ---------------------------------------------------------------------
# Référence Python
# ---------------------------------------------------------------------

func build_from_spec(spec, prog):
    opts := {"exit_on_error": false, "width": 78}
    if contains_key(spec, "prog"):
        prog = spec["prog"]
    if contains_key(spec, "allow_abbrev"):
        opts["allow_abbrev"] = spec["allow_abbrev"]
    if contains_key(spec, "description"):
        opts["description"] = spec["description"]
    if contains_key(spec, "epilog"):
        opts["epilog"] = spec["epilog"]
    p := argparse.ArgumentParser(prog, opts)
    if contains_key(spec, "args"):
        for a in spec["args"]:
            p.add_argument(a["names"], a["opts"])
    if contains_key(spec, "groups"):
        for g in spec["groups"]:
            d := null
            if contains_key(g, "description"):
                d = g["description"]
            gg := p.add_argument_group(g["title"], d)
            for a in g["args"]:
                gg.add_argument(a["names"], a["opts"])
    if contains_key(spec, "mutex"):
        for m in spec["mutex"]:
            mg := p.add_mutually_exclusive_group({"required": m["required"]})
            for a in m["args"]:
                mg.add_argument(a["names"], a["opts"])
    if contains_key(spec, "sub"):
        so := {"dest": spec["sub"]["dest"]}
        for k in ["required", "help", "title", "description"]:
            if contains_key(spec["sub"], k):
                so[k] = spec["sub"][k]
        sp := p.add_subparsers(so)
        for c in spec["sub"]["commands"]:
            po := {}
            for k in ["aliases", "help"]:
                if contains_key(c, k):
                    po[k] = c[k]
            sub := sp.add_parser(c["name"], po)
            if contains_key(c, "args"):
                for a in c["args"]:
                    sub.add_argument(a["names"], a["opts"])
            if contains_key(c, "sub"):
                sp2 := sub.add_subparsers({"dest": c["sub"]["dest"]})
                for c2 in c["sub"]["commands"]:
                    s2 := sp2.add_parser(c2["name"], {})
                    if contains_key(c2, "args"):
                        for a in c2["args"]:
                            s2.add_argument(a["names"], a["opts"])
    return p

ref := [null]

func t_reference_parse():
    r := ref[0]
    i := 0
    for case in r["cases"]:
        p := build_from_spec(r["parsers"][case[0]], "t")
        want := r["expected"][i]
        got := "ERR"
        try:
            got = {"ok": p.parse_args(case[1])}
        catch e:
            if e.type != "ArgparseError":
                got = "CRASH " + e.type + " " + e.message
        label := f"cas {i} {case[0]} {ser(case[1])}"
        if want == "ERR":
            check_eq(got, "ERR", label)
        elif type(got) == "str":
            check_eq(got, ser(want), label)
        else:
            check_eq(ser(got["ok"]), ser(want["ok"]), label)
        i = i + 1
    check_eq(len(r["cases"]), 222, "nombre de cas de référence")

func t_reference_help():
    r := ref[0]
    argparse.set_language("en")
    for name in keys(r["help_specs"]):
        p := build_from_spec(r["help_specs"][name], "t")
        check_eq(p.format_help(), r["help_expected"][name], "aide « " + name + " »")
    argparse.set_language("fr")

# ---------------------------------------------------------------------
# Actions et options
# ---------------------------------------------------------------------

func t_actions():
    p := mk()
    p.add_argument("--t", {"action": "store_true"})
    p.add_argument("--f", {"action": "store_false"})
    p.add_argument("--c", {"action": "store_const", "const": 42})
    p.add_argument("-v", {"action": "count"})
    p.add_argument("--a", {"action": "append"})
    p.add_argument("--k", {"action": "append_const", "const": "K"})
    p.add_argument("--e", {"action": "extend", "nargs": "+"})
    p.add_argument("--b", {"action": "boolean_optional"})
    d := ok(p, [])
    check_eq(d["t"], false, "store_true défaut")
    check_eq(d["f"], true, "store_false défaut")
    check_eq(d["c"], null, "store_const défaut")
    check_eq(d["v"], 0, "count défaut 0")
    check_eq(d["a"], null, "append défaut null")
    check_eq(d["b"], null, "boolean_optional défaut null")
    r := ok(p, ["--t", "--f", "--c", "-vvv", "--a", "1", "--a", "2", "--k", "--e", "x", "y", "--b"])
    check_eq(r["t"], true, "store_true")
    check_eq(r["f"], false, "store_false")
    check_eq(r["c"], 42, "store_const")
    check_eq(r["v"], 3, "count")
    check_eq(r["a"], ["1", "2"], "append")
    check_eq(r["k"], ["K"], "append_const")
    check_eq(r["e"], ["x", "y"], "extend")
    check_eq(r["b"], true, "--b")
    check_eq(ok(p, ["--no-b"])["b"], false, "--no-b")

func t_dest_metavar():
    p := mk()
    a1 := p.add_argument(["-x", "--long-name"], {})
    check_eq(a1.dest, "long_name", "dest = option longue, _ pour -")
    a2 := p.add_argument("-y", {})
    check_eq(a2.dest, "y", "dest option courte")
    a3 := p.add_argument("--z", {"dest": "zed"})
    check_eq(a3.dest, "zed", "dest explicite")
    a4 := p.add_argument("pos", {})
    check_eq(a4.dest, "pos", "dest positionnel")
    check_eq(ok(p, ["--z", "5", "P"])["zed"], "5", "dest dans le résultat")
    h := p.format_help()
    check(s.contains(h, "--long-name LONG_NAME"), "métavar = dest en majuscules")
    q := mk()
    q.add_argument("--o", {"metavar": "FICHIER"})
    check(s.contains(q.format_help(), "--o FICHIER"), "metavar explicite")

func t_set_defaults():
    p := mk()
    p.add_argument("--a", {"default": 1})
    p.set_defaults({"a": 9, "extra": "e"})
    r := ok(p, [])
    check_eq(r["a"], 9, "set_defaults prime sur default")
    check_eq(r["extra"], "e", "clé hors argument")
    check_eq(ok(p, ["--a", "3"])["a"], "3", "valeur explicite prime")
    check_eq(p.get_default("a"), 9, "get_default")
    check_eq(p.get_default("extra"), "e", "get_default hors argument")

func t_env():
    os.setenv("ARGP_TEST_N", "7")
    os.setenv("ARGP_TEST_FLAG", "1")
    p := mk()
    p.add_argument("--n", {"type": "int", "env": "ARGP_TEST_N", "default": 1})
    p.add_argument("--flag", {"action": "store_true", "env": "ARGP_TEST_FLAG"})
    p.add_argument("--req", {"required": true, "env": "ARGP_TEST_N"})
    r := ok(p, [])
    check_eq(r["n"], 7, "env converti par type")
    check_eq(r["flag"], true, "env pour un drapeau")
    check_eq(r["req"], "7", "env satisfait required")
    check_eq(ok(p, ["--n", "3"])["n"], 3, "la ligne de commande prime sur env")
    os.unsetenv("ARGP_TEST_N")
    os.unsetenv("ARGP_TEST_FLAG")
    check_eq(err_line(p, []), "t: erreur: les arguments suivants sont requis : --req", "sans env : required")

func t_parse_known_and_ex():
    p := mk()
    p.add_argument("--a", {})
    r := p.parse_known_args(["--a", "1", "--zz", "q", "extra"])
    check_eq(r[0]["a"], "1", "parse_known_args : connu")
    check_eq(r[1], ["--zz", "q", "extra"], "parse_known_args : extras")
    q := mk()
    sp := q.add_subparsers({"dest": "cmd"})
    c := sp.add_parser("go", {"aliases": ["g"]})
    c.add_argument("--w", {})
    ex := q.parse_args_ex(["g", "--w", "1"])
    check_eq(ex["path"], ["go"], "chemin canonique (alias résolu)")
    check_eq(ex["args"]["cmd"], "go", "dest de la sous-commande = nom canonique")
    check(ex["parser"] == c, "parseur final")
    check_eq(ex["extras"], [], "pas d'extras")

func t_hidden_suppress():
    p := mk()
    p.add_argument("--shown", {"help": "visible"})
    p.add_argument("--secret", {"help": argparse.SUPPRESS})
    p.add_argument("--hid", {"hidden": true})
    p.add_argument("pos", {"hidden": true})
    h := p.format_help()
    check(s.contains(h, "--shown"), "option visible")
    check(not s.contains(h, "--secret"), "SUPPRESS masqué de l'aide")
    check(not s.contains(h, "--hid"), "hidden masqué de l'aide")
    check(not s.contains(p.format_usage(), "pos"), "positionnel caché absent de l'usage")
    check_eq(ok(p, ["--secret", "v", "P"])["secret"], "v", "mais utilisable")

# ---------------------------------------------------------------------
# Types et choix
# ---------------------------------------------------------------------

func even(text):
    if not (text == "2" or text == "4"):
        argparse.fail("pas pair : " + text)
    return 100

func always_bad(text):
    raise("ValueError", "x")

func t_types():
    p := mk()
    p.add_argument("--i", {"type": "int"})
    p.add_argument("--f", {"type": "float"})
    p.add_argument("--b", {"type": "bool"})
    p.add_argument("--p", {"type": "path"})
    p.add_argument("--e", {"type": even})
    p.add_argument("--r", {"type": argparse.int_range(1, 10)})
    p.add_argument("--fr", {"type": argparse.float_range(0.0, 1.0)})
    p.add_argument("--bad", {"type": always_bad})
    p.add_argument("--l", {"type": "int", "nargs": 2})
    r := ok(p, ["--i", "-4", "--f", "2.5", "--b", "Oui" if false else "yes", "--p", "a/b", "--e", "2", "--r", "3", "--fr", "0.5", "--l", "1", "2"])
    check_eq(r["i"], -4, "int négatif")
    check_eq(r["f"], 2.5, "float")
    check_eq(r["b"], true, "bool yes")
    check_eq(r["p"], "a/b", "path")
    check_eq(r["e"], 100, "fonction type=")
    check_eq(r["r"], 3, "int_range")
    check_eq(r["fr"], 0.5, "float_range")
    check_eq(r["l"], [1, 2], "nargs 2 converti")
    check_eq(ok(p, ["--b", "OFF"])["b"], false, "bool insensible à la casse")
    check_eq(err_line(p, ["--i", "abc"]), "t: erreur: argument --i : valeur int invalide : 'abc'", "int invalide")
    check_eq(err_line(p, ["--i", "1.5"]), "t: erreur: argument --i : valeur int invalide : '1.5'", "int refuse 1.5")
    check_eq(err_line(p, ["--f", "x"]), "t: erreur: argument --f : valeur float invalide : 'x'", "float invalide")
    check_eq(err_line(p, ["--b", "peut-être"]), "t: erreur: argument --b : valeur bool invalide : 'peut-être'", "bool invalide")
    check_eq(err_line(p, ["--e", "3"]), "t: erreur: argument --e : pas pair : 3", "ArgumentTypeError : message repris")
    check_eq(err_line(p, ["--r", "11"]), "t: erreur: argument --r : valeur hors de [1, 10] : 11", "int_range hors bornes")
    check_eq(err_line(p, ["--r", "x"]), "t: erreur: argument --r : entier attendu : 'x'", "int_range non entier")
    check_eq(err_line(p, ["--fr", "2"]), "t: erreur: argument --fr : valeur hors de [0.0, 1.0] : 2.0", "float_range")
    check_eq(err_line(p, ["--bad", "z"]), "t: erreur: argument --bad : valeur invalide : 'z'", "exception quelconque")
    check_eq(err_line(p, ["--l", "1", "z"]), "t: erreur: argument --l : valeur int invalide : 'z'", "nargs : un élément invalide")
    q := mk()
    q.add_argument("--n", {"type": "inconnu"})
    raises(() => q.parse_args(["--n", "1"]), "ArgparseConfigError", "type inconnu (chaîne)")

func t_default_conversion():
    p := mk()
    p.add_argument("--n", {"type": "int", "default": "12"})
    p.add_argument("--m", {"type": "int", "default": 5})
    p.add_argument("--s", {"default": "txt"})
    r := ok(p, [])
    check_eq(r["n"], 12, "défaut str converti par type")
    check_eq(r["m"], 5, "défaut non-str inchangé")
    check_eq(r["s"], "txt", "défaut str")
    q := mk()
    q.add_argument("--n", {"type": "int", "default": "zz"})
    check_eq(err_line(q, []), "t: erreur: argument --n : valeur int invalide : 'zz'", "défaut invalide")

func t_choices():
    p := mk()
    p.add_argument("--c", {"choices": ["a", "b"]})
    p.add_argument("--n", {"type": "int", "choices": [1, 2, 3]})
    p.add_argument("--m", {"nargs": "+", "choices": ["x", "y"]})
    check_eq(ok(p, ["--c", "b"])["c"], "b", "choix valide")
    check_eq(err_line(p, ["--c", "z"]), "t: erreur: argument --c : choix invalide : 'z' (choisir parmi 'a', 'b')", "choix invalide")
    check_eq(err_line(p, ["--n", "9"]), "t: erreur: argument --n : choix invalide : 9 (choisir parmi 1, 2, 3)", "choix numériques")
    check_eq(err_line(p, ["--m", "x", "q"]), "t: erreur: argument --m : choix invalide : 'q' (choisir parmi 'x', 'y')", "choix sur chaque valeur")
    check(s.contains(p.format_usage(), "[--c {a,b}]"), "choix dans l'usage")
    check(s.contains(p.format_help(), "--c {a,b}"), "choix dans l'aide")

# ---------------------------------------------------------------------
# Erreurs (messages exacts)
# ---------------------------------------------------------------------

func t_errors():
    p := mk()
    p.add_argument("--n", {"type": "int"})
    p.add_argument("--two", {"nargs": 2})
    p.add_argument("--any", {"nargs": "+"})
    p.add_argument("-f", {"action": "store_true"})
    p.add_argument("x", {})
    p.add_argument("--long", {"action": "store_true"})
    check_eq(err_line(p, []), "t: erreur: les arguments suivants sont requis : x", "positionnel manquant")
    check_eq(err_line(p, ["x", "--n"]), "t: erreur: argument --n : un argument est attendu", "valeur manquante")
    check_eq(err_line(p, ["x", "--two", "1"]), "t: erreur: argument --two : 2 arguments sont attendus", "nargs 2")
    check_eq(err_line(p, ["x", "--any"]), "t: erreur: argument --any : au moins un argument est attendu", "nargs +")
    check_eq(err_line(p, ["x", "--long=1"]), "t: erreur: argument --long : valeur explicite ignorée : '1'", "valeur sur un drapeau")
    check_eq(err_line(p, ["x", "-fz"]), "t: erreur: argument -f : valeur explicite ignorée : 'z'", "grappe invalide")
    check_eq(err_line(p, ["x", "--zzz"]), "t: erreur: arguments non reconnus : --zzz", "option inconnue")
    check_eq(err_line(p, ["x", "y", "z"]), "t: erreur: arguments non reconnus : y z", "positionnels en trop")
    check_eq(err_line(p, ["x", "--l"]), "", "abréviation valide --l -> --long")
    q := mk()
    q.add_argument("--verbose", {"action": "store_true"})
    q.add_argument("--version2", {"action": "store_true"})
    check_eq(err_line(q, ["--ver"]), "t: erreur: option ambiguë : --ver peut désigner --verbose, --version2", "option ambiguë")
    r := mk()
    r.add_argument("--a", {"required": true})
    r.add_argument("--b", {"required": true})
    r.add_argument("p", {})
    check_eq(err_line(r, []), "t: erreur: les arguments suivants sont requis : --a, --b, p", "plusieurs manquants")
    # le message complet commence par l'usage
    try:
        r.parse_args([])
    catch e:
        check(s.starts_with(e.message, "usage : t [-h] --a A --b B p\n"), "le message commence par l'usage")
        check_eq(e.type, "ArgparseError", "type d'exception")
    check_eq(r.last_error, "les arguments suivants sont requis : --a, --b, p", "last_error")

func t_mutex():
    p := mk()
    g := p.add_mutually_exclusive_group()
    g.add_argument("--a", {"action": "store_true"})
    g.add_argument("--b", {"action": "store_true"})
    check_eq(err_line(p, ["--a", "--b"]), "t: erreur: argument --b : incompatible avec l'argument --a", "exclusion mutuelle")
    check_eq(err_line(p, ["--a", "--a"]), "", "même option deux fois : autorisé")
    check_eq(err_line(p, []), "", "aucune : autorisé")
    q := mk()
    rg := q.add_mutually_exclusive_group({"required": true})
    rg.add_argument(["-x", "--ex"], {"action": "store_true"})
    rg.add_argument("-y", {"action": "store_true"})
    check_eq(err_line(q, []), "t: erreur: un des arguments -x/--ex -y est requis", "groupe requis")
    check(s.contains(q.format_usage(), "(-x | -y)"), "usage : groupe requis entre parenthèses")
    check(s.contains(p.format_usage(), "[--a | --b]"), "usage : groupe optionnel entre crochets")
    raises(() => q.add_mutually_exclusive_group().add_argument("pos", {}), "ArgparseConfigError", "positionnel refusé dans un groupe")
    raises(() => q.add_mutually_exclusive_group().add_argument("--r", {"required": true}), "ArgparseConfigError", "required refusé dans un groupe")
    # groupe exclusif dans un groupe d'options : affiché dans ce groupe
    w := mk()
    grp := w.add_argument_group("Réseau", "Options réseau.")
    mg := grp.add_mutually_exclusive_group()
    mg.add_argument("--tcp", {"action": "store_true", "help": "TCP"})
    mg.add_argument("--udp", {"action": "store_true", "help": "UDP"})
    h := w.format_help()
    check(s.contains(h, "Réseau:\n  Options réseau.\n\n  --tcp"), "groupe d'arguments avec description")

func t_config_errors():
    p := mk()
    raises(() => p.add_argument([], {}), "ArgparseConfigError", "aucun nom")
    raises(() => p.add_argument("", {}), "ArgparseConfigError", "nom vide")
    raises(() => p.add_argument(["-a", "b"], {}), "ArgparseConfigError", "mélange option/positionnel")
    raises(() => p.add_argument(["a", "b"], {}), "ArgparseConfigError", "positionnel à plusieurs noms")
    raises(() => p.add_argument("--x", {"action": "inconnue"}), "ArgparseConfigError", "action inconnue")
    raises(() => p.add_argument("--x", {"nargs": 0}), "ArgparseConfigError", "nargs 0")
    raises(() => p.add_argument("--x", {"nargs": "??"}), "ArgparseConfigError", "nargs invalide")
    raises(() => p.add_argument("--x", {"action": "store_true", "nargs": 2}), "ArgparseConfigError", "nargs avec drapeau")
    raises(() => p.add_argument("pos", {"action": "store_true"}), "ArgparseConfigError", "drapeau positionnel")
    raises(() => p.add_argument("--x", {"action": "store_const"}), "ArgparseConfigError", "store_const sans const")
    raises(() => p.add_argument("--x", {"choices": []}), "ArgparseConfigError", "choices vide")
    raises(() => p.add_argument("--x", {"metavar": 3}), "ArgparseConfigError", "metavar invalide")
    raises(() => p.add_argument("pos", {"dest": "d"}), "ArgparseConfigError", "dest sur positionnel")
    raises(() => p.add_argument("--hepl", {"hlep": "faute"}), "ArgparseConfigError", "option inconnue (faute de frappe)")
    raises(() => p.add_argument("--x", 5), "ArgparseConfigError", "options non dict")
    raises(() => p.add_argument("--b", {"action": "boolean_optional", "nargs": 2}), "ArgparseConfigError", "boolean_optional + nargs")
    raises(() => p.add_argument("-b", {"action": "boolean_optional"}), "ArgparseConfigError", "boolean_optional court")
    p.add_argument("--dup", {})
    raises(() => p.add_argument("--dup", {}), "ArgparseConfigError", "option en double")
    raises(() => p.add_argument("-h", {}), "ArgparseConfigError", "-h déjà pris par l'aide")
    raises(() => mk("t", {"inconnu": 1}), "ArgparseConfigError", "option de parseur inconnue")
    sp := p.add_subparsers({"dest": "c"})
    raises(() => p.add_subparsers({}), "ArgparseConfigError", "deux add_subparsers")
    sp.add_parser("go", {"aliases": ["g"]})
    raises(() => sp.add_parser("go", {}), "ArgparseConfigError", "sous-commande en double")
    raises(() => sp.add_parser("g", {}), "ArgparseConfigError", "alias en double")
    raises(() => sp.add_parser("-x", {}), "ArgparseConfigError", "nom commençant par -")
    raises(() => sp.add_parser("z", {"couleur": 1}), "ArgparseConfigError", "option add_parser inconnue")
    raises(() => p.parse_args("pas une liste"), "TypeError", "argv non liste")
    raises(() => p.parse_args([1, 2]), "TypeError", "argv non str")

# ---------------------------------------------------------------------
# Sous-commandes
# ---------------------------------------------------------------------

func t_subcommands():
    p := mk("git")
    p.add_argument("--verbose", {"action": "store_true"})
    sp := p.add_subparsers({"dest": "cmd", "help": "commandes"})
    add := sp.add_parser("add", {"aliases": ["a"], "help": "ajoute"})
    add.add_argument("paths", {"nargs": "+"})
    add.add_argument("-f", {"action": "store_true"})
    rm := sp.add_parser("rm", {"aliases": ["remove", "r"]})
    rm.add_argument("name", {})
    check_eq(add.prog, "git add", "prog d'une sous-commande")
    for nm in ["add", "a"]:
        r := ok(p, [nm, "x", "y", "-f"])
        check_eq(r["cmd"], "add", "nom canonique via " + nm)
        check_eq(r["paths"], ["x", "y"], "positionnels via " + nm)
        check_eq(r["f"], true, "option de sous-commande via " + nm)
    for nm in ["rm", "remove", "r"]:
        check_eq(ok(p, [nm, "n"])["name"], "n", "alias " + nm)
    check_eq(ok(p, ["--verbose", "add", "x"])["verbose"], true, "option avant la sous-commande")
    check_eq(ok(p, ["add", "x"])["cmd"], "add", "dest")
    check_eq(ok(p, [])["cmd"], null, "sous-commande facultative absente")
    check_eq(err_line(p, ["zzz"]), "git: erreur: argument {add,rm} : choix invalide : 'zzz' (choisir parmi 'add', 'rm')", "sous-commande inconnue")
    check_eq(err_line(p, ["add"]), "git add: erreur: les arguments suivants sont requis : paths", "erreur attribuée à la sous-commande")
    try:
        p.parse_args(["add"])
    catch e:
        check(s.starts_with(e.message, "usage : git add [-h] [-f] paths [paths ...]\n"), "usage de la sous-commande")
    check_eq(err_line(p, ["rm", "a", "b"]), "git: erreur: arguments non reconnus : b", "extras remontés au parseur racine")
    check(s.contains(p.format_help(), "add (a)"), "aide : alias entre parenthèses")
    check(s.contains(p.format_help(), "rm (remove, r)"), "aide : plusieurs alias")
    check_eq(ok(p, ["add", "--", "-f", "z"])["paths"], ["-f", "z"], "-- après la sous-commande")

func t_subcommand_required_nested():
    p := mk("tool")
    sp := p.add_subparsers({"dest": "cmd", "required": true})
    rem := sp.add_parser("remote", {})
    rsp := rem.add_subparsers({"dest": "sub", "required": true})
    a := rsp.add_parser("add", {})
    a.add_argument("name", {})
    rsp.add_parser("show", {})
    check_eq(err_line(p, []), "tool: erreur: les arguments suivants sont requis : {remote}", "sous-commande requise")
    check_eq(err_line(p, ["remote"]), "tool remote: erreur: les arguments suivants sont requis : {add,show}", "sous-sous-commande requise")
    r := ok(p, ["remote", "add", "o"])
    check_eq(r["cmd"], "remote", "niveau 1")
    check_eq(r["sub"], "add", "niveau 2")
    check_eq(r["name"], "o", "positionnel niveau 2")
    ex := p.parse_args_ex(["remote", "show"])
    check_eq(ex["path"], ["remote", "show"], "chemin imbriqué")
    check_eq(ex["parser"].prog, "tool remote show", "prog imbriqué")
    deep := rsp.add_parser("deep", {})
    dsp := deep.add_subparsers({"dest": "d"})
    dsp.add_parser("deeper", {})
    check_eq(ok(p, ["remote", "deep", "deeper"])["d"], "deeper", "trois niveaux")

func t_subcommand_defaults():
    p := mk()
    p.add_argument("--lvl", {"default": "0"})
    sp := p.add_subparsers({"dest": "c"})
    a := sp.add_parser("a", {})
    a.add_argument("--lvl", {"default": "sub"})
    check_eq(ok(p, ["a"])["lvl"], "sub", "le défaut de la sous-commande prime sur celui du parent")
    check_eq(ok(p, ["--lvl", "5", "a"])["lvl"], "5", "une valeur explicite du parent n'est jamais écrasée")
    check_eq(ok(p, ["a", "--lvl", "6"])["lvl"], "6", "valeur explicite de la sous-commande")
    check_eq(ok(p, ["--lvl", "5", "a", "--lvl", "6"])["lvl"], "6", "la dernière valeur explicite gagne")

func t_subcommand_abbrev():
    p := mk()
    p.add_argument("--verbose", {"action": "store_true"})
    p.add_argument("--version2", {"action": "store_true"})
    sp := p.add_subparsers({"dest": "c"})
    a := sp.add_parser("a", {})
    a.add_argument("--verify", {"action": "store_true"})
    check_eq(ok(p, ["a", "--ver"])["verify"], true, "abréviation résolue par la sous-commande (pas d'ambiguïté du parent)")
    check_eq(err_line(p, ["--ver", "a"]), "t: erreur: option ambiguë : --ver peut désigner --verbose, --version2", "ambiguïté côté parent")

# ---------------------------------------------------------------------
# Aide, usage, formats
# ---------------------------------------------------------------------

func t_help_basic():
    p := mk("tool", {"description": "Décrit l'outil.", "epilog": "Voir %(prog)s --help.", "width": 60})
    p.add_argument("-v", {"action": "store_true", "help": "bavard"})
    p.add_argument("--out", {"help": "sortie (défaut : %(default)s)", "default": "a.out"})
    p.add_argument("src", {"help": "source"})
    want := "usage : tool [-h] [-v] [--out OUT] src\n\nDécrit l'outil.\n\narguments positionnels:\n  src         source\n\noptions:\n  -h, --help  affiche ce message d'aide et quitte\n  -v          bavard\n  --out OUT   sortie (défaut : a.out)\n\nVoir tool --help.\n"
    check_eq(p.format_help(), want, "aide complète")
    check_eq(p.format_usage(), "usage : tool [-h] [-v] [--out OUT] src\n", "format_usage")
    q := mk("tool", {"usage": "%(prog)s FICHIER..."})
    check_eq(q.format_usage(), "usage : tool FICHIER...\n", "usage personnalisé")
    z := mk("tool", {"add_help": false})
    check_eq(z.format_usage(), "usage : tool\n", "sans -h")

func t_help_options():
    p := mk("t", {"show_defaults": true})
    p.add_argument("--n", {"type": "int", "default": 5, "help": "un nombre"})
    p.add_argument("--s", {"help": "pas de défaut"})
    p.add_argument("--m", {"default": "x", "help": "avec %(default)s déjà"})
    p.add_argument("-q", {"action": "store_true", "help": "drapeau"})
    h := p.format_help()
    check(s.contains(h, "un nombre (défaut : 5)"), "show_defaults ajoute le défaut")
    check(not s.contains(h, "pas de défaut ("), "pas de défaut si null")
    check(not s.contains(h, "avec x déjà (défaut"), "pas de doublon si %(default)s présent")
    check(not s.contains(h, "drapeau (défaut"), "pas pour un drapeau")
    r := mk("t", {"raw_text": true, "description": "ligne 1\n  ligne 2 indentée", "width": 40})
    check(s.contains(r.format_help(), "ligne 1\n  ligne 2 indentée\n"), "raw_text conserve la mise en forme")
    w := mk("t", {"width": 30, "description": "un texte assez long pour être coupé en plusieurs lignes"})
    for l in s.split(w.format_help(), "\n"):
        check(len(l) <= 30, "largeur respectée : " + l)

func t_help_wrap_usage():
    p := mk("tool", {"width": 40})
    p.add_argument("--alpha-option", {"metavar": "ALPHA"})
    p.add_argument("--beta-option", {"metavar": "BETA"})
    p.add_argument("first", {})
    u := p.format_usage()
    for l in s.split(u, "\n"):
        check(len(l) <= 40, "usage <= 40 colonnes : " + l)
    check(s.contains(u, "\n"), "usage coupé en plusieurs lignes")
    check_eq(u, "usage : tool [-h] [--alpha-option ALPHA]\n             [--beta-option BETA]\n             first\n", "coupure alignée")

func t_help_metavars():
    p := mk("t")
    p.add_argument("--two", {"nargs": 2, "metavar": ["A", "B"]})
    p.add_argument("--opt", {"nargs": "?"})
    p.add_argument("--many", {"nargs": "*"})
    p.add_argument("--plus", {"nargs": "+"})
    p.add_argument("x", {"nargs": "?"})
    p.add_argument("y", {"nargs": "*"})
    p.add_argument("z", {"nargs": "+"})
    p.add_argument("w", {"nargs": 2})
    p.add_argument("r", {"nargs": "remainder"})
    u := p.format_usage()
    for part in ["[--two A B]", "[--opt [OPT]]", "[--many [MANY ...]]", "[--plus PLUS [PLUS ...]]", "[x]", "[y ...]", "z [z ...]", "w w", "..."]:
        check(s.contains(u, part), "usage contient " + part)

# ---------------------------------------------------------------------
# Langue
# ---------------------------------------------------------------------

func t_language():
    check_eq(argparse.language(), "fr", "langue par défaut")
    p := mk()
    p.add_argument("--n", {"type": "int"})
    p.add_argument("x", {})
    old := argparse.set_language("en")
    check_eq(old, "fr", "set_language retourne l'ancienne")
    q := mk()
    q.add_argument("--n", {"type": "int"})
    q.add_argument("x", {})
    check_eq(err_line(q, []), "t: error: the following arguments are required: x", "erreur en anglais")
    check_eq(err_line(q, ["--n", "z", "x"]), "t: error: argument --n: invalid int value: 'z'", "type en anglais")
    check(s.contains(q.format_help(), "positional arguments:"), "aide en anglais")
    check(s.starts_with(q.format_usage(), "usage: "), "usage en anglais")
    argparse.set_language("fr")
    check_eq(err_line(p, []), "t: erreur: les arguments suivants sont requis : x", "retour au français")
    raises(() => argparse.set_language("xx"), "ArgumentError", "langue inconnue")

# ---------------------------------------------------------------------
# Aide / version via exceptions
# ---------------------------------------------------------------------

func t_help_version_exceptions():
    p := mk("t", {"version": "%(prog)s 1.5"})
    try:
        p.parse_args(["--help"])
        check(false, "--help doit lever")
    catch e:
        check_eq(e.type, "ArgparseHelp", "type ArgparseHelp")
        check(s.starts_with(e.message, "usage : t [-h] [--version]"), "message = aide complète")
    try:
        p.parse_args(["--version"])
        check(false, "--version doit lever")
    catch e2:
        check_eq(e2.type, "ArgparseVersion", "type ArgparseVersion")
        check_eq(e2.message, "t 1.5\n", "texte de version")
    sp := p.add_subparsers({"dest": "c"})
    sp.add_parser("go", {"help": "va"})
    try:
        p.parse_args(["go", "-h"])
    catch e3:
        check(s.starts_with(e3.message, "usage : t go [-h]"), "-h dans une sous-commande : aide de la sous-commande")

# ---------------------------------------------------------------------
# Sous-processus : codes de sortie réels
# ---------------------------------------------------------------------

func alex_bin():
    return os.getenv("ALEX_BIN", "./alex")

func exec_alex(script, args):
    full := ["run", script]
    for a in args:
        append(full, a)
    return process.run(alex_bin(), full)

func t_exit_codes():
    r0 := exec_alex("tests/argparse/cli_fixture.al", [])
    check_eq(r0.code, 0, "succès : code 0")
    check_eq(json.parse(s.trim(r0.stdout)), {"n": 1, "name": "anon"}, "succès : résultat")
    r1 := exec_alex("tests/argparse/cli_fixture.al", ["--n", "5", "bob"])
    check_eq(json.parse(s.trim(r1.stdout)), {"n": 5, "name": "bob"}, "arguments passés par la ligne de commande")
    r2 := exec_alex("tests/argparse/cli_fixture.al", ["--n", "zz"])
    check_eq(r2.code, 2, "erreur d'usage : code 2")
    check_eq(r2.stdout, "", "erreur d'usage : rien sur stdout")
    check(s.contains(r2.stderr, "fx: erreur: argument --n : valeur int invalide : 'zz'"), "erreur d'usage sur stderr")
    check(s.starts_with(r2.stderr, "usage : fx [-h] [--version] [--n N] [name]"), "usage sur stderr")
    r3 := exec_alex("tests/argparse/cli_fixture.al", ["--help"])
    check_eq(r3.code, 0, "--help : code 0")
    check(s.starts_with(r3.stdout, "usage : fx"), "--help sur stdout")
    check_eq(r3.stderr, "", "--help : stderr vide")
    r4 := exec_alex("tests/argparse/cli_fixture.al", ["--version"])
    check_eq(r4.code, 0, "--version : code 0")
    check_eq(r4.stdout, "fx 9.9\n", "--version sur stdout")
    r5 := exec_alex("tests/argparse/cli_fixture.al", ["--nope"])
    check_eq(r5.code, 2, "option inconnue : code 2")

func t_cli_app_exit():
    a := "tests/argparse/app_fixture.al"
    r := exec_alex(a, ["ok", "3"])
    check_eq(r.code, 0, "cli : succès")
    check_eq(r.stdout, "ok 3\n", "cli : sortie du gestionnaire")
    check_eq(exec_alex(a, ["seven"]).code, 7, "cli : code de retour du gestionnaire")
    check_eq(exec_alex(a, ["7"]).code, 7, "cli : alias")
    b := exec_alex(a, ["boom"])
    check_eq(b.code, 1, "cli : exception du gestionnaire => 1")
    check(s.contains(b.stderr, "app: erreur: échec simulé"), "cli : message d'erreur sur stderr")
    e := exec_alex(a, ["ok", "x"])
    check_eq(e.code, 2, "cli : erreur d'usage => 2")
    g := exec_alex(a, ["group"])
    check_eq(g.code, 2, "cli : groupe sans sous-commande => 2")
    check(s.contains(g.stdout, "inner"), "cli : aide du groupe affichée")
    check_eq(exec_alex(a, ["group", "inner"]).stdout, "inner\n", "cli : sous-commande imbriquée")
    n := exec_alex(a, [])
    check_eq(n.code, 2, "cli : sans commande => 2")
    check(s.contains(n.stdout, "usage : app"), "cli : aide racine")
    h := exec_alex(a, ["help", "group"])
    check_eq(h.code, 0, "cli help")
    check(s.starts_with(h.stdout, "usage : app group"), "cli help <commande>")
    check_eq(exec_alex(a, ["help", "nope"]).code, 1, "cli help inconnue => erreur")

# ---------------------------------------------------------------------
# cli.App (en processus)
# ---------------------------------------------------------------------

calls := []

func h_add(args):
    append(calls, args["paths"])
    return null

func h_code(args):
    return 4

func h_fail(args):
    raise("ValueError", "x")

func t_cli_app():
    clear(calls)
    app := cli.App("t", {"exit_on_error": false, "show_help_on_empty": false})
    c := app.command("add", h_add, {"aliases": ["a"]})
    c.argument("paths", {"nargs": "+"})
    app.command("code", h_code)
    app.command("fail", h_fail)
    grp := app.command("grp", null, {})
    grp.command("sub", h_code)
    check_eq(app.run(["add", "x", "y"]), 0, "null => 0")
    check_eq(calls, [["x", "y"]], "gestionnaire appelé avec le dict")
    check_eq(app.run(["a", "z"]), 0, "alias")
    check_eq(calls, [["x", "y"], ["z"]], "alias exécuté")
    check_eq(app.run(["code"]), 4, "code retourné")
    check_eq(app.run(["fail"]), 1, "exception => 1")
    check_eq(app.run(["grp", "sub"]), 4, "imbriqué")
    check_eq(app.run(["grp"]), 2, "groupe sans gestionnaire")
    check_eq(app.run([]), 2, "racine sans gestionnaire")
    raises(() => app.run(["add"]), "ArgparseError", "erreur d'usage relevée (exit_on_error=false)")
    app2 := cli.App("t", {"exit_on_error": false, "catch_errors": false})
    app2.command("fail", h_fail)
    raises(() => app2.run(["fail"]), "ValueError", "catch_errors=false laisse remonter")
    app3 := cli.App("t", {"exit_on_error": false})
    app3.set_handler(h_code)
    check_eq(app3.run([]), 4, "gestionnaire racine")
    app3.add_builtins()
    app3.add_builtins()
    names := keys(app3.handlers)
    check(contains(names, "t help") and contains(names, "t completion") and contains(names, "t man"), "commandes intégrées")

# ---------------------------------------------------------------------
# Complétion
# ---------------------------------------------------------------------

func comp_parser():
    p := mk("tool")
    p.add_argument("--verbose", {"action": "store_true", "help": "bavard"})
    p.add_argument(["-l", "--level"], {"choices": ["debug", "info"], "help": "niveau"})
    p.add_argument("--out", {"type": "path"})
    p.add_argument("--dir", {"type": "dir"})
    p.add_argument("--free", {"complete": ["alpha", "beta"]})
    p.add_argument("--hid", {"hidden": true})
    sp := p.add_subparsers({"dest": "cmd"})
    add := sp.add_parser("add", {"aliases": ["a"], "help": "Ajoute"})
    add.add_argument("paths", {"nargs": "+", "type": "path"})
    add.add_argument("--mode", {"choices": ["fast", "slow"]})
    rem := sp.add_parser("remote", {"help": "Distants"})
    rsp := rem.add_subparsers({"dest": "r"})
    rsp.add_parser("show", {"help": "Montre"})
    rsp.add_parser("add", {"help": "Ajoute un distant"})
    sp.add_parser("secret", {"hidden": true})
    return p

func have(tool):
    return process.which(tool) != null

func tmp_file(name, text):
    path := os.join(os.tmp_dir(), name)
    file.write(path, text)
    return path

func bash_complete(script_path, words, cwd):
    quoted := []
    for w in words:
        append(quoted, "'" + w + "'")
    code := "source " + script_path + "; COMP_WORDS=(" + s.join(" ", quoted) + "); COMP_CWORD=$((${#COMP_WORDS[@]}-1)); COMPREPLY=(); _tool_complete; echo \"${COMPREPLY[*]}\""
    r := process.run("bash", ["-c", code], null, 10, cwd)
    return s.trim(r.stdout)

# Mots d'une réponse de complétion, triés (l'ordre de compgen -f dépend du système de fichiers).
func sorted_words(text):
    ws := s.split(text, " ")
    ws2 := []
    for w in ws:
        if w != "":
            append(ws2, w)
    col.sort(ws2)
    return s.join(" ", ws2)

func t_completion_bash():
    p := comp_parser()
    script := p.completion("bash")
    check(s.contains(script, "complete -F _tool_complete 'tool'"), "bash : enregistrement")
    check(not s.contains(script, "--hid"), "bash : option cachée absente")
    check(not s.contains(script, "secret"), "bash : sous-commande cachée absente")
    if not have("bash"):
        print("      (bash absent : exécution ignorée)")
        return null
    d := os.join(os.tmp_dir(), "argp_comp_dir")
    if not os.exists(d):
        os.mkdir(d)
    file.write(os.join(d, "fa.txt"), "x")
    file.write(os.join(d, "fb.txt"), "x")
    path := os.join(d, "tool_complete.bash")
    file.write(path, script)
    r := process.run("bash", ["-n", path])
    check_eq(r.code, 0, "bash : syntaxe valide (bash -n)")
    check_eq(bash_complete(path, ["tool", ""], d), "add a remote", "bash : sous-commandes")
    check_eq(bash_complete(path, ["tool", "--"], d), "--help --verbose --level --out --dir --free", "bash : options longues")
    check_eq(bash_complete(path, ["tool", "-"], d), "-h --help --verbose -l --level --out --dir --free", "bash : toutes les options")
    check_eq(bash_complete(path, ["tool", "--l"], d), "--level", "bash : préfixe")
    check_eq(bash_complete(path, ["tool", "--level", ""], d), "debug info", "bash : valeurs d'une option à choix")
    check_eq(bash_complete(path, ["tool", "-l", "i"], d), "info", "bash : option courte + préfixe")
    check_eq(bash_complete(path, ["tool", "--level", "=", "d"], d), "debug", "bash : --opt=valeur découpé par bash")
    check_eq(bash_complete(path, ["tool", "--level="], d), "", "bash : mot collé ne casse pas")
    check_eq(bash_complete(path, ["tool", "--free", ""], d), "alpha beta", "bash : complete=[mots]")
    check_eq(sorted_words(bash_complete(path, ["tool", "--out", "f"], d)), "fa.txt fb.txt", "bash : fichiers (type path)")
    check_eq(bash_complete(path, ["tool", "--dir", ""], d), "", "bash : dossiers (aucun ici)")
    check_eq(sorted_words(bash_complete(path, ["tool", "add", ""], d)), "fa.txt fb.txt tool_complete.bash", "bash : positionnel path => fichiers")
    check_eq(bash_complete(path, ["tool", "add", "--"], d), "--help --mode", "bash : options de la sous-commande")
    check_eq(bash_complete(path, ["tool", "a", "--m"], d), "--mode", "bash : alias de sous-commande")
    check_eq(bash_complete(path, ["tool", "add", "--mode", ""], d), "fast slow", "bash : valeurs dans la sous-commande")
    check_eq(bash_complete(path, ["tool", "--level", "info", "add", "--m"], d), "--mode", "bash : valeur d'option sautée avant la sous-commande")
    check_eq(bash_complete(path, ["tool", "remote", ""], d), "show add", "bash : sous-sous-commandes")
    check_eq(bash_complete(path, ["tool", "remote", "add", "--"], d), "--help", "bash : niveau 3")
    check_eq(bash_complete(path, ["tool", "--verbose", "remote", "s"], d), "show", "bash : drapeau avant la sous-commande")

func t_completion_zsh():
    p := comp_parser()
    script := p.completion("zsh")
    check(s.starts_with(script, "#compdef tool\n"), "zsh : #compdef")
    check(s.contains(script, "_tool_add() {"), "zsh : fonction de sous-commande")
    check(s.contains(script, "_tool_remote_show() {"), "zsh : fonction imbriquée")
    check(s.contains(script, "'(-l --level)'{-l+,--level=}'[niveau]:LEVEL:(debug info)'"), "zsh : option à choix")
    check(s.contains(script, "--out=:OUT:_files"), "zsh : fichiers")
    check(s.contains(script, "_files -/"), "zsh : dossiers")
    check(s.contains(script, "'a:Ajoute'"), "zsh : alias décrits")
    check(not s.contains(script, "secret"), "zsh : sous-commande cachée absente")
    if not have("zsh"):
        print("      (zsh absent : syntaxe non vérifiée)")
        return null
    path := tmp_file("argp__tool", script)
    r := process.run("zsh", ["-n", path])
    check_eq(r.code, 0, "zsh : syntaxe valide (zsh -n) " + r.stderr)
    reg := process.run("zsh", ["-f", "-c", "autoload -Uz compinit; compinit -u -d " + os.join(os.tmp_dir(), "argp_zcompdump") + "; source " + path + "; print -r -- ${_comps[tool]}"])
    check_eq(s.trim(reg.stdout), "_tool", "zsh : compdef enregistre _tool")

# Contrôle structurel d'un script PowerShell : guillemets simples équilibrés, (), {}, [] équilibrés.
func ps_balanced(text):
    depth := {"(": 0, "{": 0, "[": 0}
    pairs := {")": "(", "}": "{", "]": "["}
    in_str := false
    i := 0
    n := len(text)
    while i < n:
        c := s.substring(text, i, i + 1)
        if in_str:
            if c == "'":
                if i + 1 < n and s.substring(text, i + 1, i + 2) == "'":
                    i = i + 1
                else:
                    in_str = false
        elif c == "#":
            while i < n and s.substring(text, i, i + 1) != "\n":
                i = i + 1
        elif c == "'":
            in_str = true
        elif contains_key(depth, c):
            depth[c] = depth[c] + 1
        elif contains_key(pairs, c):
            depth[pairs[c]] = depth[pairs[c]] - 1
            if depth[pairs[c]] < 0:
                return false
        i = i + 1
    return not in_str and depth["("] == 0 and depth["{"] == 0 and depth["["] == 0

func t_completion_powershell():
    p := comp_parser()
    script := p.completion("powershell")
    check(s.contains(script, "Register-ArgumentCompleter -Native -CommandName 'tool'"), "pwsh : enregistrement")
    check(s.contains(script, "'tool|a' = 'tool add'"), "pwsh : alias -> commande")
    check(s.contains(script, "'tool|--level' = @('debug', 'info')"), "pwsh : choix")
    check(s.contains(script, "'tool|--out' = '@file'"), "pwsh : fichiers")
    check(s.contains(script, "[System.Management.Automation.CompletionResult]::new"), "pwsh : CompletionResult")
    check(not s.contains(script, "secret"), "pwsh : sous-commande cachée absente")
    check(ps_balanced(script), "pwsh : () {} [] et guillemets équilibrés")
    check_eq(p.completion("pwsh"), script, "pwsh : alias de nom")
    q := mk("it's")
    q.add_argument("--x", {"help": "l'aide avec 'quotes'"})
    check(ps_balanced(q.completion("powershell")), "pwsh : apostrophes échappées")
    check(s.contains(q.completion("powershell"), "'it''s'"), "pwsh : apostrophe doublée")

func t_completion_misc():
    p := comp_parser()
    raises(() => p.completion("fish"), "ArgumentError", "shell inconnu")
    check(s.contains(p.completion("bash", "autre"), "complete -F _autre_complete 'autre'"), "nom de programme explicite")
    q := mk("my-prog.x")
    check(s.contains(q.completion("bash"), "_my_prog_x_complete"), "identifiant de fonction nettoyé")
    check(s.contains(q.completion("zsh"), "_my_prog_x"), "identifiant zsh nettoyé")
    w := mk("w")
    w.add_argument("--q", {"help": "it's [x] a:b"})
    z := w.completion("zsh")
    check(s.contains(z, "it'\\''s"), "zsh : apostrophe échappée")
    check(s.contains(z, "(x)"), "zsh : crochets remplacés")

# ---------------------------------------------------------------------
# Pages de manuel
# ---------------------------------------------------------------------

func t_manpage():
    p := mk("tool", {"description": "Un outil.\n\nSecond paragraphe.", "version": "%(prog)s 1.2", "epilog": ".commence par un point"})
    p.add_argument("--verbose", {"action": "store_true", "help": "bavard \\ avec antislash"})
    p.add_argument(["-l", "--level"], {"choices": ["debug", "info"], "help": "niveau"})
    p.add_argument("files", {"nargs": "+", "help": "fichiers"})
    sp := p.add_subparsers({"dest": "c"})
    sp.add_parser("add", {"aliases": ["a"], "help": "Ajoute des choses"})
    sp.add_parser("secret", {"hidden": true})
    m := p.format_man(1, "2026-10-07", null, null, "Alice")
    check(s.contains(m, ".TH \"TOOL\" \"1\" \"2026-10-07\" \"tool 1.2\" \"Manuel de tool\""), "man : .TH")
    check(s.contains(m, ".SH NOM\ntool \\- Un outil. Second paragraphe."), "man : NOM")
    check(s.contains(m, ".SH SYNOPSIS\n.B tool\n"), "man : SYNOPSIS")
    check(s.contains(m, "\\fB\\-\\-verbose\\fR"), "man : options en gras avec \\-")
    check(s.contains(m, "\\fB\\-l\\fR \\fI{debug,info}\\fR, \\fB\\-\\-level\\fR \\fI{debug,info}\\fR"), "man : valeurs en italique")
    check(s.contains(m, "bavard \\e avec antislash"), "man : antislash échappé")
    check(s.contains(m, ".SH DESCRIPTION\nUn outil.\n.PP\nSecond paragraphe."), "man : paragraphes")
    check(s.contains(m, ".SH ARGUMENTS\n.TP\n\\fIfiles\\fR\nfichiers"), "man : ARGUMENTS")
    check(s.contains(m, ".SH COMMANDES\n.TP\n\\fBtool\\-add\\fR(1) (a)\nAjoute des choses"), "man : COMMANDES")
    check(s.contains(m, ".SH VOIR AUSSI\n\\fBtool\\-add\\fR(1)"), "man : VOIR AUSSI")
    check(not s.contains(m, "secret"), "man : commande cachée absente")
    check(s.contains(m, ".SH AUTEUR\nAlice"), "man : AUTEUR")
    check(s.contains(m, "\\&.commence par un point"), "man : ligne débutant par . protégée")
    pages := p.man_pages(1, "2026-10-07")
    check_eq(len(keys(pages)), 2, "man_pages : une page par commande visible")
    check(contains_key(pages, "tool.1") and contains_key(pages, "tool-add.1"), "man_pages : noms de fichiers")
    check(s.contains(pages["tool-add.1"], ".TH \"TOOL\\-ADD\" \"1\""), "man : titre sous-commande")
    check(s.contains(pages["tool-add.1"], ".SH VOIR AUSSI\n\\fBtool\\fR(1)"), "man : renvoi au parent")
    argparse.set_language("en")
    e := p.format_man(1, "2026-10-07")
    argparse.set_language("fr")
    check(s.contains(e, ".SH NAME") and s.contains(e, ".SH COMMANDS") and s.contains(e, ".SH SEE ALSO"), "man : sections en anglais")
    check(s.contains(e, "\"tool manual\""), "man : titre du manuel en anglais")
    if have("groff"):
        for k in keys(pages):
            path := tmp_file("argp_" + k, pages[k])
            r := process.run("groff", ["-mandoc", "-ww", "-z", path])
            check_eq(r.code, 0, "groff : " + k + " code")
            check_eq(s.trim(r.stderr), "", "groff : " + k + " sans avertissement")
        e2 := tmp_file("argp_en.1", e)
        r2 := process.run("groff", ["-mandoc", "-ww", "-z", e2])
        check_eq(s.trim(r2.stderr), "", "groff : page anglaise sans avertissement")
    else:
        print("      (groff absent : rendu non vérifié)")

# ---------------------------------------------------------------------

func t_facade():
    check_eq(argparse.version(), "1.0.0", "version")
    p := argparse.parser(prog="x", description="d", exit_on_error=false, add_help=false)
    check_eq(p.prog, "x", "argparse.parser(prog=...)")
    check_eq(p.format_usage(), "usage : x\n", "add_help=false")
    a := argparse.argument(p, "--n", type="int", default=3, help="un n", nargs=null)
    check_eq(a.dest, "n", "argparse.argument(...)")
    check_eq(p.parse_args([])["n"], 3, "défaut via argparse.argument")
    check_eq(p.parse_args(["--n", "9"])["n"], 9, "type via argparse.argument")
    b := argparse.argument(p, "--c", action="store_const", constant="K")
    check_eq(p.parse_args(["--c"])["c"], "K", "constant=")
    q := argparse.ArgumentParser("y", {"exit_on_error": false})
    check(isinstance(q, argparse.ArgumentParser), "isinstance ArgumentParser")
    check_eq(q.prog, "y", "constructeur de la façade")
    default_prog := argparse.ArgumentParser(null, {"exit_on_error": false}).prog
    check_eq(default_prog, "test_argparse", "prog par défaut = nom du script sans .al")

func main():
    f := open_ref()
    ref[0] = f
    run("référence Python : 222 analyses", t_reference_parse)
    run("référence Python : 10 aides", t_reference_help)
    run("actions", t_actions)
    run("dest et metavar", t_dest_metavar)
    run("set_defaults / get_default", t_set_defaults)
    run("variables d'environnement", t_env)
    run("parse_known_args / parse_args_ex", t_parse_known_and_ex)
    run("arguments cachés", t_hidden_suppress)
    run("types", t_types)
    run("conversion des défauts", t_default_conversion)
    run("choices", t_choices)
    run("erreurs : messages exacts", t_errors)
    run("groupes mutuellement exclusifs", t_mutex)
    run("erreurs de configuration", t_config_errors)
    run("sous-commandes et alias", t_subcommands)
    run("sous-commandes requises et imbriquées", t_subcommand_required_nested)
    run("défauts parent / sous-commande", t_subcommand_defaults)
    run("abréviations et sous-commandes", t_subcommand_abbrev)
    run("aide : forme complète", t_help_basic)
    run("aide : options de mise en forme", t_help_options)
    run("usage : coupure de ligne", t_help_wrap_usage)
    run("aide : métavars et nargs", t_help_metavars)
    run("langue", t_language)
    run("aide et version (exceptions)", t_help_version_exceptions)
    run("façade", t_facade)
    run("cli.App en processus", t_cli_app)
    run("codes de sortie réels (argparse)", t_exit_codes)
    run("codes de sortie réels (cli.App)", t_cli_app_exit)
    run("complétion Bash (exécutée)", t_completion_bash)
    run("complétion Zsh", t_completion_zsh)
    run("complétion PowerShell", t_completion_powershell)
    run("complétion : divers", t_completion_misc)
    run("pages de manuel", t_manpage)

func open_ref():
    return json.parse(file.read("tests/argparse/reference.json"))

main()
print(f"argparse : {stats[0]} vérifications OK, {stats[1]} échec(s)")
if stats[1] > 0:
    raise("AssertionError", "test_argparse : échecs")
