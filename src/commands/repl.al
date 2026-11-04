# ALEX — commands.repl
#
# `alexc repl` : boucle interactive, comme celle de l'alex de référence (cmdRepl) — une instruction par ligne,
# chaque ligne compilée seule (sans graphe de modules) puis fusionnée avec les préludes ; une ligne qui n'est
# qu'une expression devient `return <expr>` et sa valeur est affichée si elle n'est pas null ; les globales sont
# conservées d'une ligne à l'autre.
#
# Répartition : la machine virtuelle (`alexvm --repl req rep`) lit les lignes sur l'entrée standard (même tampon
# qu'input()) et exécute les modules ; alexc compile chaque ligne reçue par le tube nommé req et répond sur rep
# (« R chemin.albc » ou « E » après avoir affiché l'erreur).
#
#   use commands.repl as cr
#   m := cr.compile_line("x + 1")      # module .albc (préludes compris)
#   code := cr.run()
#
# Commandes (traitées par alexc, jamais compilées) : help, help <module> (documentation, comme `alexc doc`),
# exit / quit (fermer les canaux : la VM voit la fin du flux et s'arrête).
#
# Erreurs : celles du compilateur pour compile_line ; run n'en lève pas.

from core use len, type
use string as _s
use os as _os
use io as _io
use process as _pr
use _native_fd as _fd
use commands.common as cc
use parser as _bp
use ast as _ba
use bytecode.compiler as _bc
use bytecode.format as _bf
use resolver as _bm
use commands.doc as _doc

_preludes := [null]

func _quit_keys():
    return "Ctrl+Z puis Entrée" if _os.platform() == "windows" else "Ctrl+D"

func _help_text():
    return ("Commandes du REPL :\n" +
            "  help              cette aide\n" +
            "  help <module>     documentation d'un module de la bibliothèque standard (help string, help os...)\n" +
            "  exit, quit        quitter (aussi " + _quit_keys() + ")\n" +
            "Une instruction par ligne ; les variables définies restent disponibles d'une ligne à l'autre.\n" +
            "Une expression seule affiche sa valeur : 2 + 3, len(\"abc\"), som * 2.\n" +
            "Liste des modules : alexc doc --list.\n")

# Commande du REPL portée par la ligne : ["help", module], ["exit", ""] ou null (instruction ALEX ordinaire).
func command_of(line):
    t := _s.trim(line)
    if t == "exit" or t == "exit()" or t == "quit" or t == "quit()":
        return ["exit", ""]
    if t == "help" or t == "help()" or t == "?":
        return ["help", ""]
    arg := null
    if _s.starts_with(t, "help "):
        arg = _s.trim(_s.substring(t, 5, len(t)))
    elif _s.starts_with(t, "help(") and _s.ends_with(t, ")"):
        arg = _s.trim(_s.substring(t, 5, len(t) - 1))
    if arg == null or arg == "":
        return null
    if len(arg) >= 2 and (arg[0] == '"' or arg[0] == '\'') and arg[len(arg) - 1] == arg[0]:
        arg = _s.substring(arg, 1, len(arg) - 1)
    return ["help", arg]

func _help(arg):
    if arg == "":
        cc.out(_help_text())
        return
    try:
        if _doc.run([arg], cc.stdlib_root()) != 0:
            cc.err("  liste des modules : alexc doc --list\n")
    catch e:
        cc.err(str(e) + "\n")

func _prelude_modules():
    if _preludes[0] == null:
        rt := _bm.runtime_dir(cc.stdlib_root())
        core := _bm.compile_prelude(_bm.prelude_source(rt + "/alex/prelude/core.al"), "<prelude:core>")
        colls := _bm.compile_prelude(_bm.prelude_source(rt + "/alex/prelude/collections.al"), "<prelude:collections>")
        _preludes[0] = [core, colls]
    return _preludes[0]

func compile_line(line):
    program := _bp.parse_text(line + "\n", "<repl>")
    if len(program.top_level) == 1 and program.top_level[0].kind == "ExpressionStmt":
        es := program.top_level[0]
        ret := _ba.node("ReturnStmt", es.line, es.column)
        ret.value = es.expr
        program.top_level[0] = ret
    m := _bc.compile(program, _bc.CompileOptions())
    p := _prelude_modules()
    return _bf.merge_modules([p[0], p[1], m])[0]

func _read_line(fd, buf):
    while true:
        k := _s.find(buf[0], "\n")
        if k >= 0:
            line := _s.substring(buf[0], 0, k)
            buf[0] = _s.substring(buf[0], k + 1, len(buf[0]))
            return line
        chunk := _fd.read(fd, 65536, null)
        if type(chunk) != "str" or chunk == "":
            return null
        buf[0] = buf[0] + chunk

func run():
    print("ALEX REPL (P9) — une instruction par ligne ; help pour l'aide, exit ou " + _quit_keys() + " pour quitter.")
    cc.flush()
    vm := cc.vm_path()
    if not _os.isfile(vm):
        cc.err("machine virtuelle introuvable : " + vm + " (ALEX_VM, ou `alex vm -o " + vm + "`)\n")
        return 1
    dir := _os.join(_os.tmp_dir(), "alexc-repl-" + str(_os.pid()))
    _os.mkdir_all(dir)
    req := cc.fifo_path(dir, "req")
    rep := cc.fifo_path(dir, "rep")
    albc := dir + "/ligne.albc"
    _fd.mkfifo(req, 384)
    _fd.mkfifo(rep, 384)
    # le cadre courant reste à la VM : stdin, stdout et stderr hérités
    pid := _os.spawn(vm, ["--repl", req, rep])
    fr := _fd.open_fifo(req, false, 10.0)
    fw := _fd.open_fifo(rep, true, 10.0)
    code := 0
    if fr < 0 or fw < 0:
        cc.err("alexc repl : communication avec la machine virtuelle impossible\n")
        code = 1
    else:
        buf := [""]
        while true:
            line := _read_line(fr, buf)
            if line == null:
                break
            c := command_of(line)
            if c != null and c[0] == "exit":
                break
            if c != null:
                _help(c[1])
                cc.flush()
                _fd.write(fw, "E\n", null)
                continue
            reply := "E\n"
            try:
                _io.write_bytes(albc, _bf.write_module(compile_line(line)))
                reply = "R " + albc + "\n"
            catch e:
                cc.flush()
                cc.err(str(e) + "\n")
            _fd.write(fw, reply, null)
        _fd.close(fr)
        _fd.close(fw)
    c := _os.wait(pid)
    if code == 0:
        code = c
    for p in [req, rep, albc]:
        try:
            _os.remove(p)
        catch e:
            pass
    try:
        _os.rmdir(dir)
    catch e:
        pass
    return code
