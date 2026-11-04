# ALEX — commands.debug
#
# `alexc debug fichier.al|fichier.albc` (protocole 1) et
# `alexc debug --protocol 2 [--break-on-exception] fichier [arguments...]` (protocole 2, ALEX Studio et adaptateur
# DAP) : débogueur en JSON Lines sur stdout/stdin, comme l'alex de référence (cmdDebug, cmdDebug2, DebugInspector).
#
# Répartition : la machine virtuelle (`alexvm --debug`, runtime/vm/vm.al, section « Débogueur ») exécute le
# programme et décide des arrêts (entrée, pause, pas à pas, points d'arrêt, exception) ; ce frontal parle le
# protocole avec l'IDE, garde les options des points d'arrêt (condition, compteur, journal), construit les
# événements et évalue les expressions (évaluateur sans effet de bord, sur les valeurs que la VM lui décrit). Entre
# les deux, deux tubes nommés (voir la section de la VM pour le format des messages).
#
#   use commands.debug as cd
#   code := cd.run(["--protocol", "2", "prog.al"], "stdlib")
#
# Erreurs : aucune levée par run en protocole 2 (événements compile_error / exception) ; erreurs de compilation
# propagées en protocole 1.

from core use len, type, to_int, to_float
from collections use append
use string as _s
use os as _os
use io as _io
use math as _math
use process as _pr
use _native_fd as _fd
use _native_net as _net
use commands.common as cc
use parser as _bp
use bytecode.format as _bf
use resolver as _bm
use commands.pkg as _pkg

# ------------------------------------------------------------------------------------------------ canal avec la VM

func _esc(s):
    out := []
    for c in s:
        if c == '\\':
            append(out, "\\\\")
        elif c == '\t':
            append(out, "\\t")
        elif c == '\n':
            append(out, "\\n")
        elif c == '\r':
            append(out, "\\r")
        else:
            append(out, str(c))
    return _s.join("", out)

func _unesc(s):
    out := []
    i := 0
    n := len(s)
    while i < n:
        c := s[i]
        if c == '\\' and i + 1 < n:
            e := s[i + 1]
            i += 2
            if e == 't':
                append(out, "\t")
            elif e == 'n':
                append(out, "\n")
            elif e == 'r':
                append(out, "\r")
            else:
                append(out, str(e))
            continue
        append(out, str(c))
        i += 1
    return _s.join("", out)

class Channel:
    func init(rfd, wfd):
        self.rfd = rfd
        self.wfd = wfd
        self.buf = ""
        self.eof = false

    func send(fields):
        _fd.write(self.wfd, _s.join("\t", [_esc(str(f)) for f in fields]) + "\n", null)

    # Événement suivant (liste de champs), null si rien n'arrive avant `timeout` (secondes) ou à la fin du flux.
    func next(timeout):
        while true:
            k := _s.find(self.buf, "\n")
            if k >= 0:
                line := _s.substring(self.buf, 0, k)
                self.buf = _s.substring(self.buf, k + 1, len(self.buf))
                return [_unesc(f) for f in _s.split(line, "\t")]
            if self.eof:
                return null
            chunk := _fd.read(self.rfd, 65536, timeout)
            if chunk == null:
                return null
            if type(chunk) != "str" or chunk == "":
                self.eof = true
                return null
            self.buf = self.buf + chunk

func _fail(m):
    raise("Debug", m)

# ------------------------------------------------------------------------------------------------ session

class Session:
    func init(ch, proc, proto):
        self.ch = ch
        self.proc = proc
        self.proto = proto
        self.pending = []      # événements reçus pendant l'attente d'une réponse
        self.finished = null   # [genre, message] à la fin

    # Requête pendant un arrêt : réponse (texte) ou Debug levée avec le message d'erreur.
    func query(fields):
        self.ch.send(fields)
        while true:
            ev := self.ch.next(null)
            if ev == null:
                _fail("programme terminé")
            if ev[0] == "R":
                return ev[1] if len(ev) > 1 else ""
            if ev[0] == "!":
                _fail(ev[1] if len(ev) > 1 else "")
            append(self.pending, ev)

    func qjson(fields):
        return cc.json_parse(self.query(fields))

    func event(timeout):
        if len(self.pending) > 0:
            ev := self.pending[0]
            self.pending = self.pending[1:len(self.pending)]
            return ev
        return self.ch.next(timeout)

# ------------------------------------------------------------------------------------------------ évaluateur
# Valeurs (EV::of) : ["N"] ["B", b] ["I", n] ["F", x] ["S", texte] ["V", h, type].

func _ev_of(raw):
    if raw[0] == "F":
        return ["F", _net.bits_f64(to_int(raw[1]))]
    if raw[0] == "I":
        return ["I", to_int(raw[1])]
    return raw

func _is_num(e):
    return e[0] == "I" or e[0] == "F"

func _num(e):
    return to_float(e[1])

func _truthy(e):
    k := e[0]
    if k == "N":
        return false
    if k == "B":
        return e[1]
    if k == "I":
        return e[1] != 0
    if k == "F":
        return e[1] != 0.0
    if k == "S":
        return e[1] != ""
    return true

func _kind_name(e):
    k := e[0]
    if k == "N":
        return "null"
    if k == "B":
        return "bool"
    if k == "I":
        return "int"
    if k == "F":
        return "float"
    if k == "S":
        return "str"
    return e[2]

func _float_str(x):
    return str(x * 1.0)

func quoted(s):
    out := ["\""]
    for c in s:
        if c == '"':
            append(out, "\\\"")
        elif c == '\\':
            append(out, "\\\\")
        elif c == '\n':
            append(out, "\\n")
        elif c == '\t':
            append(out, "\\t")
        else:
            append(out, str(c))
    append(out, "\"")
    return _s.join("", out)

func _enc(e):
    k := e[0]
    if k == "N":
        return "N"
    if k == "B":
        return "B\t" + ("1" if e[1] else "0")
    if k == "I":
        return "I\t" + str(e[1])
    if k == "F":
        return "F\t" + str(_net.f64_bits(e[1]))
    if k == "S":
        return "S\t" + _esc(e[1])
    return "V\t" + str(e[1])

class Evaluator:
    func init(sess, frame):
        self.sess = sess
        self.frame = frame

    func eval(text):
        prog := _bp.parse_text(text, "<évaluation>")
        if len(prog.top_level) != 1 or prog.top_level[0].kind != "ExpressionStmt":
            _fail("une seule expression attendue")
        return self.expr(prog.top_level[0].expr)

    func display(a):
        k := a[0]
        if k == "N":
            return "null"
        if k == "B":
            return "true" if a[1] else "false"
        if k == "I":
            return str(a[1])
        if k == "F":
            return _float_str(a[1])
        if k == "S":
            return a[1]
        return cc.json_parse(self.sess.query(["D", a[1]]))

    func equal(a, b):
        if _is_num(a) and _is_num(b):
            return _num(a) == _num(b)
        if a[0] != b[0]:
            return false
        k := a[0]
        if k == "N":
            return true
        if k == "B" or k == "S":
            return a[1] == b[1]
        if k == "V":
            return self.sess.query(["E", a[1], b[1]]) == "1"
        return false

    func expr(e):
        if e == null:
            _fail("expression vide")
        k := e.kind
        if k == "Literal":
            lk := e.literal_kind
            if lk == "Integer":
                return ["I", to_int(e.value)]
            if lk == "Float":
                return ["F", to_float(e.value)]
            if lk == "Boolean":
                return ["B", e.value == true]
            if lk == "Null":
                return ["N"]
            if lk == "String" or lk == "Char":
                return ["S", str(e.value)]
        elif k == "Identifier":
            return _ev_of(self.sess.qjson(["N", self.frame, e.name]))
        elif k == "MemberExpr":
            o := self.expr(e.object)
            if o[0] == "V":
                return _ev_of(self.sess.qjson(["M", o[1], e.member]))
            _fail("membre '" + e.member + "' inaccessible sur une valeur de type " + _kind_name(o))
        elif k == "IndexExpr":
            o := self.expr(e.object)
            ix := self.expr(e.index)
            if o[0] == "S":
                if ix[0] != "I":
                    _fail("indice entier attendu")
                n := len(o[1])
                i := ix[1] + n if ix[1] < 0 else ix[1]
                if i < 0 or i >= n:
                    _fail("indice hors limites")
                return ["S", str(o[1][i])]
            if o[0] != "V":
                _fail("valeur non indexable")
            return _ev_of(self.sess.qjson(["X", o[1], _enc(ix)]))
        elif k == "UnaryExpr":
            x := self.expr(e.operand)
            if e.op == "Not":
                return ["B", not _truthy(x)]
            if e.op == "Minus":
                if x[0] == "I":
                    return ["I", -x[1]]
                if x[0] == "F":
                    return ["F", -x[1]]
            if e.op == "Plus" and _is_num(x):
                return x
            _fail("opérateur unaire non pris en charge ici")
        elif k == "ConditionalExpr":
            if _truthy(self.expr(e.condition)):
                return self.expr(e.then_expr)
            return self.expr(e.else_expr)
        elif k == "BinaryExpr":
            return self.binary(e)
        elif k == "CallExpr":
            if e.callee.kind != "Identifier" or len(e.arguments) != 1:
                _fail("seuls len(x), str(x) et type(x) sont évaluables (pas d'effet de bord)")
            f := e.callee.name
            a := self.expr(e.arguments[0].value)
            if f == "len":
                if a[0] == "S":
                    return ["I", len(a[1])]
                if a[0] == "V":
                    try:
                        return ["I", to_int(self.sess.query(["L", a[1]]))]
                    catch err:
                        _fail("len() : valeur sans longueur")
                _fail("len() : valeur sans longueur")
            if f == "str":
                return ["S", self.display(a)]
            if f == "type":
                return ["S", _kind_name(a)]
            _fail("seuls len(x), str(x) et type(x) sont évaluables (pas d'effet de bord)")
        _fail("expression non prise en charge par l'évaluateur du débogueur")

    func binary(b):
        op := b.op
        if op == "And":
            l := self.expr(b.left)
            return self.expr(b.right) if _truthy(l) else l
        if op == "Or":
            l := self.expr(b.left)
            return l if _truthy(l) else self.expr(b.right)
        l := self.expr(b.left)
        r := self.expr(b.right)
        if op == "Eq":
            return ["B", self.equal(l, r)]
        if op == "Ne":
            return ["B", not self.equal(l, r)]
        if op == "Lt" or op == "Le" or op == "Gt" or op == "Ge":
            c := 0
            if _is_num(l) and _is_num(r):
                c = -1 if _num(l) < _num(r) else (1 if _num(l) > _num(r) else 0)
            elif l[0] == "S" and r[0] == "S":
                c = -1 if l[1] < r[1] else (1 if l[1] > r[1] else 0)
            else:
                _fail("comparaison entre " + _kind_name(l) + " et " + _kind_name(r))
            if op == "Lt":
                return ["B", c < 0]
            if op == "Le":
                return ["B", c <= 0]
            if op == "Gt":
                return ["B", c > 0]
            return ["B", c >= 0]
        if op == "Add" and l[0] == "S" and r[0] == "S":
            return ["S", l[1] + r[1]]
        if op == "Add" or op == "Sub" or op == "Mul" or op == "Div" or op == "FloorDiv" or op == "Mod" or op == "Pow":
            if not _is_num(l) or not _is_num(r):
                _fail("opération arithmétique entre " + _kind_name(l) + " et " + _kind_name(r))
            ints := l[0] == "I" and r[0] == "I"
            if op == "Add":
                return ["I", l[1] + r[1]] if ints else ["F", _num(l) + _num(r)]
            if op == "Sub":
                return ["I", l[1] - r[1]] if ints else ["F", _num(l) - _num(r)]
            if op == "Mul":
                return ["I", l[1] * r[1]] if ints else ["F", _num(l) * _num(r)]
            if op == "Div":
                if _num(r) == 0.0:
                    _fail("division par zéro")
                return ["F", _num(l) / _num(r)]
            if op == "FloorDiv":
                if _num(r) == 0.0:
                    _fail("division par zéro")
                if ints:
                    q := l[1] // r[1]
                    return ["I", q]
                return ["F", _math.floor(_num(l) / _num(r)) * 1.0]
            if op == "Mod":
                if _num(r) == 0.0:
                    _fail("division par zéro")
                if ints:
                    return ["I", l[1] % r[1]]
                return ["F", _num(l) - _num(r) * _math.floor(_num(l) / _num(r))]
            p := _math.pow(_num(l), _num(r))
            if ints and r[1] >= 0:
                return ["I", to_int(p)]
            return ["F", p]
        _fail("opérateur non pris en charge par l'évaluateur du débogueur")

func _err_text(e, raw):
    # erreurs de syntaxe : message brut (sans « SyntaxError: <évaluation>:l:c: ») pour evaluate
    if raw and e.type == "SyntaxError":
        m := e.message
        pre := "<évaluation>:"
        if _s.starts_with(m, pre):
            rest := _s.substring(m, len(pre), len(m))
            k := _s.find(rest, ": ")
            if k >= 0:
                return _s.substring(rest, k + 2, len(rest))
        return m
    if e.type == "Debug":
        return e.message
    if raw:
        return e.message
    return str(e)

func evaluate(sess, expression, frame):
    ev := Evaluator(sess, frame)
    r := ev.eval(expression)
    j := {}
    if r[0] == "V":
        q := sess.qjson(["R", r[1]])
        j["result"] = q[0]
        j["type"] = q[1]
        if q[2] != 0:
            j["ref"] = q[2]
    else:
        j["result"] = quoted(r[1]) if r[0] == "S" else ev.display(r)
        j["type"] = _kind_name(r)
    return j

func condition(sess, expression):
    try:
        return _truthy(Evaluator(sess, -1).eval(expression))
    catch e:
        return true

func interpolate(sess, message):
    out := []
    i := 0
    n := len(message)
    while i < n:
        if message[i] == '{':
            rest := _s.substring(message, i, n)
            close := _s.find(rest, "}")
            if close >= 0:
                ex := _s.substring(rest, 1, close)
                try:
                    ev := Evaluator(sess, -1)
                    r := ev.eval(ex)
                    if r[0] == "V":
                        append(out, sess.qjson(["Q", r[1]])[0])
                    else:
                        append(out, ev.display(r))
                catch e:
                    append(out, "<" + _err_text(e, false) + ">")
                i += close + 1
                continue
        append(out, str(message[i]))
        i += 1
    return _s.join("", out)

func function_display(raw):
    n := raw
    q := _rfind(n, "::")
    if q >= 0:
        n = _s.substring(n, q + 2, len(n))
    at := _s.find(n, "@")
    if at >= 0:
        n = _s.substring(n, 0, at)
    n = _s.replace(n, "#", ".")
    return "<module>" if n == "$entry" else n

func _rfind(s, sub):
    i := len(s) - len(sub)
    while i >= 0:
        if _s.substring(s, i, i + len(sub)) == sub:
            return i
        i -= 1
    return -1

# ------------------------------------------------------------------------------------------------ lancement

func _emit(j):
    cc.out(cc.json_dump(j) + "\n")

func _compile(path, stdlib):
    if cc.ends_with(path, ".albc"):
        return path
    _pkg.check_project_requirement()
    tmp := _os.join(_os.tmp_dir(), "alexc-debug-" + str(_os.pid()) + ".albc")
    _io.write_bytes(tmp, _bf.write_module(_bm.build_program(path)))
    return tmp

func _start(path, albc, args, proto, entry, lib, exc):
    vm := cc.vm_path()
    if not _os.isfile(vm):
        raise("RuntimeError", "machine virtuelle introuvable : " + vm + " (ALEX_VM, ou `alex vm -o " + vm + "`)")
    dir := _os.join(_os.tmp_dir(), "alexc-debug-" + str(_os.pid()))
    _os.mkdir_all(dir)
    cmd := cc.fifo_path(dir, "cmd")
    evt := cc.fifo_path(dir, "evt")
    _fd.mkfifo(cmd, 384)
    _fd.mkfifo(evt, 384)
    vargs := ["--debug", cmd, evt, str(proto), entry, lib, "1" if exc else "0", "--script", path, albc] + args
    _os.setenv("ALEX_EXE", cc.self_path())
    _os.setenv("ALEX_QUIET_RUN", "1")
    cc.flush()
    proc := _pr.Command(vm, vargs).stdin("null").spawn()
    rfd := _fd.open_fifo(evt, false, 10.0)
    wfd := _fd.open_fifo(cmd, true, 10.0)
    if rfd < 0 or wfd < 0:
        raise("RuntimeError", "communication avec la machine virtuelle impossible")
    return [Session(Channel(rfd, wfd), proc, proto), [cmd, evt, dir]]

func _cleanup(sess, files, tmp_albc, albc):
    code := sess.proc.wait()
    sess.proc.close()
    for p in [files[0], files[1]]:
        try:
            _os.remove(p)
        catch e:
            code = code
    try:
        _os.rmdir(files[2])
    catch e:
        code = code
    if albc != tmp_albc:
        try:
            _os.remove(albc)
        catch e:
            code = code
    return code

func run(args, stdlib):
    v2 := false
    brk := false
    file := ""
    rest := []
    i := 0
    while i < len(args):
        a := args[i]
        if file != "":
            append(rest, a)
        elif a == "--protocol" and i + 1 < len(args):
            i += 1
            v2 = args[i] == "2"
        elif a == "--protocol=2":
            v2 = true
        elif a == "--break-on-exception":
            brk = true
        else:
            file = a
        i += 1
    if v2:
        if file == "":
            cc.err("usage: alexc debug --protocol 2 [--break-on-exception] fichier.al [args...]\n")
            return 1
        return debug2(file, rest, brk, stdlib)
    if len(args) < 1:
        cc.err("usage: alexc debug fichier.al|fichier.albc\n")
        return 1
    return debug1(args[0], stdlib)

# ------------------------------------------------------------------------------------------------ protocole 1

func _p1_event(kind, message, file, line, frames):
    _emit({"event": kind, "message": message, "file": file, "line": line, "frames": frames})

# Commande du protocole 1 (alex::debug::parseCommand) : [nom, fichier, ligne, mode] ou [null, erreur].
func parse_command(line):
    sf := (key) => _string_field(line, key)
    name := sf("command")
    if name[0] != null:
        return [null, name[0]]
    n := name[1]
    if n == null:
        return [null, "champ string 'command' absent ou invalide"]
    if n == "continue" or n == "pause" or n == "stop":
        return [n, "", 0, ""]
    if n == "step":
        m := sf("mode")
        if m[0] != null:
            return [null, m[0]]
        if m[1] == null:
            return [null, "champ 'mode' requis pour step"]
        if m[1] != "into" and m[1] != "over" and m[1] != "out":
            return [null, "mode step attendu: into, over ou out"]
        return [n, "", 0, m[1]]
    if n == "breakpoint.add" or n == "breakpoint.remove":
        f := sf("file")
        if f[0] != null:
            return [null, f[0]]
        if f[1] == null:
            return [null, "champ 'file' requis"]
        p := _s.find(line, "\"line\"")
        if p >= 0:
            q := _s.find(_s.substring(line, p + 6, len(line)), ":")
            p = -1 if q < 0 else p + 6 + q
        if p < 0:
            return [null, "champ 'line' requis"]
        p += 1
        while p < len(line) and (line[p] == ' ' or line[p] == '\t'):
            p += 1
        if p == len(line) or line[p] < '0' or line[p] > '9':
            return [null, "'line' doit être un entier positif"]
        v := 0
        while p < len(line) and line[p] >= '0' and line[p] <= '9':
            v = v * 10 + (_s.ord(line[p]) - 48)
            p += 1
            if v > 4294967295:
                return [null, "'line' hors limites"]
        if v == 0:
            return [null, "'line' doit être supérieur à zéro"]
        return [n, f[1], v, ""]
    return [null, "commande inconnue: " + n]

# [erreur, valeur] : valeur null si le champ est absent.
func _string_field(line, key):
    needle := "\"" + key + "\""
    p := _s.find(line, needle)
    if p < 0:
        return [null, null]
    rest := _s.substring(line, p + len(needle), len(line))
    c := _s.find(rest, ":")
    if c < 0:
        return [null, null]
    rest = _s.substring(rest, c + 1, len(rest))
    q := _s.find(rest, "\"")
    if q < 0:
        return [null, null]
    out := []
    esc := false
    i := q + 1
    while i < len(rest):
        ch := rest[i]
        if esc:
            if ch == 'n':
                append(out, "\n")
            elif ch == 'r':
                append(out, "\r")
            elif ch == 't':
                append(out, "\t")
            elif ch == '"':
                append(out, "\"")
            elif ch == '\\':
                append(out, "\\")
            else:
                return ["échappement JSON non pris en charge", null]
            esc = false
        elif ch == '\\':
            esc = true
        elif ch == '"':
            return [null, _s.join("", out)]
        else:
            append(out, str(ch))
        i += 1
    return ["chaîne JSON incomplète", null]

func _stdin_line(st):
    while true:
        k := _s.find(st[0], "\n")
        if k >= 0:
            line := _s.substring(st[0], 0, k)
            st[0] = _s.substring(st[0], k + 1, len(st[0]))
            return line
        if st[1]:
            if st[0] == "":
                return null
            line := st[0]
            st[0] = ""
            return line
        chunk := _fd.read(0, 65536, null)
        if type(chunk) != "str" or chunk == "":
            st[1] = true
        else:
            st[0] = st[0] + chunk

func debug1(path, stdlib):
    albc := _compile(path, stdlib)
    started := _start(path, albc, [], 1, "", "", false)
    sess := started[0]
    stdin := ["", false]
    first := true
    result := null
    while result == null:
        ev := sess.event(null)
        if ev == null:
            result = ["exception", "unknown runtime exception"]
            break
        if ev[0] == "X":
            result = [ev[1], ev[2] if len(ev) > 2 else ""]
            break
        if ev[0] != "P":
            continue
        frames := sess.qjson(["F1"])
        _p1_event("paused", "ready" if first else "breakpoint/step", ev[2], to_int(ev[3]), frames)
        first = false
        resumed := false
        while not resumed:
            line := _stdin_line(stdin)
            if line == null:
                sess.ch.send(["q"])
                resumed = true
                break
            if line == "":
                continue
            c := parse_command(line)
            if c[0] == null:
                _p1_event("error", c[1], "", 0, [])
                continue
            n := c[0]
            if n == "breakpoint.add":
                sess.ch.send(["ba", c[1], c[2]])
                _p1_event("breakpoint", "added", "", 0, [])
            elif n == "breakpoint.remove":
                sess.ch.send(["br", c[1], c[2]])
                _p1_event("breakpoint", "removed", "", 0, [])
            elif n == "pause":
                sess.ch.send(["p"])
                _p1_event("status", "pause requested", "", 0, [])
            elif n == "stop":
                sess.ch.send(["q"])
                resumed = true
            elif n == "continue":
                sess.ch.send(["c"])
                resumed = true
            elif n == "step":
                sess.ch.send(["s", c[3]])
                resumed = true
    code := _cleanup(sess, started[1], path, albc)
    if result[0] == "stopped":
        _p1_event("stopped", "debug session stopped", "", 0, [])
        return 0
    if result[0] == "terminated":
        _p1_event("terminated", "program finished", "", 0, [])
        return 0
    _p1_event("exception", result[1], "", 0, [])
    return 1

# ------------------------------------------------------------------------------------------------ protocole 2

func _get(cmd, key):
    if type(cmd) == "dict" and (key in cmd):
        return cmd[key]
    return null

func _str_of(v, default=""):
    return v if type(v) == "str" else default

func _int_of(v, default=0):
    t := type(v)
    if t == "int":
        return v
    if t == "float":
        return to_int(v)
    if t == "bool":
        return 1 if v else 0
    return default

func _bool_of(v, default):
    if type(v) == "bool":
        return v
    if type(v) == "int" or type(v) == "float":
        return v != 0
    return default

class Debug2:
    func init(sess, stdlib):
        self.sess = sess
        self.paused = false
        self.announced = false
        self.pause_info = null
        self.result = null
        self.stop_requested = false
        self.commands = []
        self.deferred = []
        self.stdin_closed = false
        self.stdin_buf = ""
        self.options = {}
        self.next_id = 1

    func handle_event(ev):
        k := ev[0]
        if k == "O":
            _emit({"event": "output", "category": "stdout", "text": ev[1]})
        elif k == "I":
            _emit({"event": "input"})
        elif k == "P":
            self.paused = true
            self.pause_info = ev
        elif k == "H":
            self.breakpoint_hit(to_int(ev[1]), ev[2], to_int(ev[3]))
        elif k == "X":
            self.result = [ev[1], ev[2] if len(ev) > 2 else ""]

    func breakpoint_hit(id, file, line):
        o := self.options[id] if id in self.options else null
        hit := true
        if o != null:
            if o["condition"] != "" and not condition(self.sess, o["condition"]):
                hit = false
            if hit:
                o["hits"] += 1
                if o["hitCount"] > 0 and o["hits"] != o["hitCount"]:
                    hit = false
            if hit and o["logMessage"] != "":
                _emit({"event": "output", "category": "log", "text": interpolate(self.sess, o["logMessage"]) + "\n", "file": file, "line": line})
                hit = false
        self.sess.ch.send(["y" if hit else "n"])

    func pump(timeout):
        while self.result == null:
            ev := self.sess.event(timeout)
            if ev == null:
                if self.sess.ch.eof:
                    self.result = ["exception", "la machine virtuelle s'est arrêtée"]
                return
            self.handle_event(ev)
            timeout = 0

    func read_stdin(timeout):
        if self.stdin_closed:
            return
        chunk := _fd.read(0, 65536, timeout)
        if chunk == null:
            return
        if type(chunk) != "str" or chunk == "":
            self.stdin_closed = true
            if self.stdin_buf != "":
                append(self.commands, self.stdin_buf)
                self.stdin_buf = ""
            return
        self.stdin_buf = self.stdin_buf + chunk
        while true:
            k := _s.find(self.stdin_buf, "\n")
            if k < 0:
                break
            line := _s.substring(self.stdin_buf, 0, k)
            self.stdin_buf = _s.substring(self.stdin_buf, k + 1, len(self.stdin_buf))
            if cc.ends_with(line, "\r"):
                line = _s.substring(line, 0, len(line) - 1)
            append(self.commands, line)

    func request_stop(self_):
        self.stop_requested = true
        self.sess.ch.send(["q"])

    func announce():
        ev := self.pause_info
        reason := ev[1] if ev[1] != "" else "pause"
        j := {"event": "paused", "reason": reason, "file": ev[2], "line": to_int(ev[3])}
        if reason == "exception":
            j["exception"] = {"type": ev[4], "message": ev[5]}
        frames := self.sess.qjson(["F"])
        for f in frames:
            f["function"] = function_display(f["function"])
        j["frames"] = frames
        j["globals"] = self.sess.qjson(["G"])
        _emit(j)
        self.announced = true
        self.commands = self.deferred + self.commands
        self.deferred = []

    func loop():
        while self.result == null:
            self.pump(0)
            if self.result != null:
                break
            if self.paused and not self.announced:
                self.announce()
            if len(self.commands) == 0:
                self.read_stdin(0.015)
                if len(self.commands) == 0:
                    if self.stdin_closed and not self.stop_requested:
                        self.request_stop(null)
                    continue
            line := self.commands[0]
            self.commands = self.commands[1:len(self.commands)]
            if line == "":
                continue
            cmd := null
            try:
                cmd = cc.json_parse(line)
            catch e:
                _emit({"event": "error", "message": e.message})
                continue
            n := _str_of(_get(cmd, "command"))
            if (n == "continue" or n == "step" or n == "variables" or n == "evaluate") and not (self.paused and self.announced):
                append(self.deferred, line)
                continue
            self.command(n, cmd)

    func command(name, cmd):
        reply := {"event": "ack", "command": name}
        has_id := type(cmd) == "dict" and ("id" in cmd)
        if has_id:
            reply["id"] = cmd["id"]
        paused := self.paused and self.announced
        try:
            if name == "continue" or name == "step":
                if not paused:
                    _fail("programme non arrêté")
                if name == "step":
                    m := _str_of(_get(cmd, "mode"), "over")
                    self.sess.ch.send(["s", "into" if m == "into" else "out" if m == "out" else "over"])
                else:
                    self.sess.ch.send(["c"])
                self.announced = false
                self.paused = false
                _emit(reply)
            elif name == "pause":
                self.sess.ch.send(["p"])
                _emit(reply)
            elif name == "stop":
                _emit(reply)
                self.request_stop(null)
            elif name == "breakpoint.add" or name == "breakpoint.remove":
                self.sess.ch.send(["ba" if name == "breakpoint.add" else "br", _str_of(_get(cmd, "file")), _int_of(_get(cmd, "line"))])
                _emit(reply)
            elif name == "breakpoints.set":
                file := _str_of(_get(cmd, "file"))
                self.sess.ch.send(["bc", file])
                lines := []
                bps := _get(cmd, "breakpoints")
                for b in (bps if type(bps) == "list" else []):
                    o := {"condition": _str_of(_get(b, "condition")), "hitCount": _int_of(_get(b, "hitCount")),
                          "logMessage": _str_of(_get(b, "logMessage")), "hits": 0}
                    ln := _int_of(_get(b, "line"))
                    id := self.next_id
                    self.next_id += 1
                    self.options[id] = o
                    self.sess.ch.send(["bo", id, file, ln])
                    append(lines, ln)
                reply["lines"] = lines
                _emit(reply)
            elif name == "exceptions":
                self.sess.ch.send(["be", "1" if _bool_of(_get(cmd, "break"), true) else "0"])
                _emit(reply)
            elif name == "variables":
                if not paused:
                    _fail("programme non arrêté")
                j := {"event": "variables"}
                if has_id:
                    j["id"] = cmd["id"]
                j["ref"] = _get(cmd, "ref")
                j["variables"] = self.sess.qjson(["K", _int_of(_get(cmd, "ref"))])
                _emit(j)
            elif name == "evaluate":
                j := {"event": "evaluate"}
                if has_id:
                    j["id"] = cmd["id"]
                expr := _str_of(_get(cmd, "expression"))
                j["expression"] = expr
                try:
                    if not paused:
                        _fail("programme non arrêté")
                    r := evaluate(self.sess, expr, _int_of(_get(cmd, "frame"), -1))
                    for k in r:
                        j[k] = r[k]
                catch e:
                    j["error"] = _err_text(e, true)
                _emit(j)
            elif name == "input":
                self.sess.ch.send(["i", _str_of(_get(cmd, "text"))])
                _emit(reply)
            else:
                _fail("commande inconnue : " + name)
        catch e:
            j := {"event": "error", "command": name}
            if has_id:
                j["id"] = cmd["id"]
            j["message"] = e.message
            _emit(j)

func debug2(path, args, brk, stdlib):
    albc := ""
    try:
        albc = _compile(path, stdlib)
    catch e:
        _emit({"event": "compile_error", "message": str(e)})
        return 1
    started := _start(path, albc, args, 2, path, stdlib, brk)
    sess := started[0]
    d := Debug2(sess, stdlib)
    _emit({"event": "started"})
    d.loop()
    _cleanup(sess, started[1], path, albc)
    kind := d.result[0]
    if kind == "stopped" or kind == "terminated":
        _emit({"event": kind, "exitCode": 0})
        return 0
    _emit({"event": "exception", "message": d.result[1], "exitCode": 1})
    return 1
