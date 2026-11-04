# ALEX STANDARD LIBRARY — compiler.optimizer
#
# Optimisations sur l'arbre (compiler.ast) et sur l'IR (compiler.ir), sans changer le sens du programme :
#   AST : repliement des constantes (1 + 2 * 3 -> 7, "a" + "b", not true, comparaisons), propagation des
#         `const` de module dont la valeur est littérale, conditionnelles et if / while à condition constante,
#         suppression du code mort après return / break / continue / raise.
#   IR  : repliement CONST CONST BINARY, sauts conditionnels sur constante, saut vers l'instruction suivante,
#         enchaînement de sauts (jump threading), code inatteignable, étiquettes inutilisées, paires
#         ENTER/EXIT vides, CONST/LOAD suivis de POP, NOP.
#
#   use compiler.optimizer as opt
#   prog2 := opt.optimize_ast(prog)                  # modifie et renvoie l'arbre
#   st := opt.optimize_ir(module_ir)                 # {"before": 120, "after": 87, "folded": 9, ...}
#   o := opt.Optimizer(2)                            # niveau 0 (rien), 1 (AST), 2 (AST + IR, défaut)
#   o.run_ast(prog) ; o.run_ir(module_ir) ; print(o.stats)
#
# Une opération qui échouerait à l'exécution (division par zéro, types incompatibles) n'est jamais repliée :
# l'erreur reste à l'exécution, au même endroit.
# Erreurs : ArgumentError (niveau invalide).

from core use len, type
from collections use append
use string as _s
use compiler.ast as _ast
use compiler.ir as _ir

const FOLDABLE := ["+", "-", "*", "/", "//", "%", "**", "==", "!=", "<", "<=", ">", ">=", "&", "|", "^", "<<", ">>"]
const SCALARS := ["int", "float", "str", "bool", "char", "null"]

func _is_lit(n):
    return n != null and _ast.is_node(n) and n.kind == "Literal"

func _lit_of(v, n):
    return _ast.literal(v, n.line, n.column)

func _safe(op, a, b):
    ta := type(a)
    tb := type(b)
    if not (ta in SCALARS) or not (tb in SCALARS):
        return false
    num_a := ta == "int" or ta == "float"
    num_b := tb == "int" or tb == "float"
    if op == "/" or op == "//" or op == "%":
        if not (num_a and num_b) or b == 0:
            return false
    if op == "**":
        if not (num_a and num_b) or b < 0 or b > 64:
            return false
    if op == "<<" or op == ">>":
        if ta != "int" or tb != "int" or b < 0 or b > 62:
            return false
    if op == "&" or op == "|" or op == "^":
        if not (ta == "int" and tb == "int"):
            return false
    if op == "+" or op == "-" or op == "*":
        if num_a and num_b:
            return true
        if op == "+" and ta == "str" and tb == "str":
            return true
        return false
    if op == "<" or op == "<=" or op == ">" or op == ">=":
        return (num_a and num_b) or (ta == "str" and tb == "str") or (ta == "char" and tb == "char")
    return true

func _truthy_lit(v):
    if v == null or v == false:
        return false
    t := type(v)
    if t == "int" or t == "float":
        return v != 0
    if t == "str":
        return len(v) > 0
    return true

class Optimizer:
    func init(level=2):
        if type(level) != "int" or level < 0 or level > 2:
            raise("ArgumentError", "Optimizer : niveau 0, 1 ou 2 attendu")
        self.level = level
        self.stats = {"folded": 0, "dead_code": 0, "branches": 0, "consts": 0, "ir_before": 0, "ir_after": 0,
                      "ir_folded": 0, "ir_removed": 0}

    # ---------------- AST ----------------
    func run_ast(program):
        if self.level < 1:
            return program
        consts := self.module_consts(program)
        if len(consts) > 0:
            _ast.transform(program, (n) => self.propagate(n, consts))
        _ast.transform(program, (n) => self.fold(n))
        _ast.transform(program, (n) => self.prune(n))
        return program

    func module_consts(program):
        out := {}
        declared := {}
        _ast.walk(program, (n) => _count_decl(n, declared))
        for s in program.body:
            if s.kind == "Const" and _is_lit(s.value) and declared[s.name] == 1:
                out[s.name] = s.value.value
        return out

    func propagate(n, consts):
        if n.kind == "Name" and n.name in consts:
            self.stats["consts"] += 1
            return _lit_of(consts[n.name], n)
        return n

    func fold(n):
        k := n.kind
        if k == "Binary":
            if n.op == "and" and _is_lit(n.left):
                self.stats["folded"] += 1
                if _truthy_lit(n.left.value):
                    return n.right
                return n.left
            if n.op == "or" and _is_lit(n.left):
                self.stats["folded"] += 1
                if _truthy_lit(n.left.value):
                    return n.left
                return n.right
            if _is_lit(n.left) and _is_lit(n.right) and n.op in FOLDABLE and _safe(n.op, n.left.value, n.right.value):
                try:
                    v := _ir.binary_op(n.op, n.left.value, n.right.value)
                    self.stats["folded"] += 1
                    return _lit_of(v, n)
                catch e:
                    return n
        elif k == "Unary":
            if _is_lit(n.operand):
                v := n.operand.value
                t := type(v)
                if n.op == "not":
                    self.stats["folded"] += 1
                    return _lit_of(not _truthy_lit(v), n)
                if (n.op == "-" or n.op == "+") and (t == "int" or t == "float"):
                    self.stats["folded"] += 1
                    return _lit_of(_ir.unary_op(n.op, v), n)
                if n.op == "~" and t == "int":
                    self.stats["folded"] += 1
                    return _lit_of(~v, n)
        elif k == "Ternary":
            if _is_lit(n.cond):
                self.stats["branches"] += 1
                if _truthy_lit(n.cond.value):
                    return n.then_expr
                return n.else_expr
        elif k == "FString":
            if len([p for p in n.parts if _ast.is_node(p) and not _is_lit(p)]) == 0:
                self.stats["folded"] += 1
                return _lit_of(_s.join("", [_part_text(p) for p in n.parts]), n)
        return n

    func prune(n):
        k := n.kind
        if k == "If":
            if _is_lit(n.cond):
                self.stats["branches"] += 1
                if _truthy_lit(n.cond.value):
                    n.elifs = []
                    n.else_body = null
                    return n
                # condition fausse : premier elif devient le if
                if len(n.elifs) > 0:
                    first := n.elifs[0]
                    n.cond = first.cond
                    n.then_body = first.body
                    n.elifs = n.elifs[1:]
                    return self.prune(n)
                if n.else_body == null:
                    return null
                return _ast.Node("If", n.line, n.column, {"cond": _ast.literal(true, n.line, n.column),
                                 "then_body": n.else_body, "elifs": [], "else_body": null})
        elif k == "While":
            if _is_lit(n.cond) and not _truthy_lit(n.cond.value) and n.else_body == null:
                self.stats["branches"] += 1
                return null
        for f in ["body", "then_body", "else_body", "finally_body"]:
            if n.has(f):
                v := n.get(f)
                if type(v) == "list":
                    n.set(f, self.cut_dead(v))
        return n

    func cut_dead(stmts):
        out := []
        for s in stmts:
            append(out, s)
            if s.kind == "Return" or s.kind == "Break" or s.kind == "Continue" or _is_raise(s):
                self.stats["dead_code"] += len(stmts) - len(out)
                return out
        return out

    # ---------------- IR ----------------
    func run_ir(m):
        if self.level < 2:
            return self.stats
        self.stats["ir_before"] += m.instruction_count()
        m.main.code = self.code(m.main.code)
        for k in m.order:
            f := m.functions[k]
            f.code = self.code(f.code)
            for d in f.defaults:
                f.defaults[d] = self.code(f.defaults[d])
        self.stats["ir_after"] += m.instruction_count()
        self.stats["ir_removed"] = self.stats["ir_before"] - self.stats["ir_after"]
        return self.stats

    func code(code):
        cur := code
        changed := true
        rounds := 0
        while changed and rounds < 10:
            before := len(cur)
            nfold := self.stats["ir_folded"]
            cur = self.peephole(cur)
            cur = self.thread_jumps(cur)
            cur = self.unreachable(cur)
            cur = self.unused_labels(cur)
            changed = len(cur) != before or self.stats["ir_folded"] != nfold
            rounds += 1
        return cur

    func peephole(code):
        out := []
        i := 0
        n := len(code)
        while i < n:
            ins := code[i]
            op := ins.op
            if op == "NOP":
                i += 1
                continue
            # CONST a ; CONST b ; BINARY op
            if op == "BINARY" and len(out) >= 2 and out[len(out) - 1].op == "CONST" and out[len(out) - 2].op == "CONST":
                a := out[len(out) - 2].arg
                b := out[len(out) - 1].arg
                if ins.arg in FOLDABLE and _safe(ins.arg, a, b):
                    ok := true
                    v := null
                    try:
                        v = _ir.binary_op(ins.arg, a, b)
                    catch e:
                        ok = false
                    if ok:
                        out = out[:len(out) - 2]
                        append(out, _ir.Instr("CONST", v, ins.line))
                        self.stats["ir_folded"] += 1
                        i += 1
                        continue
            if op == "UNARY" and len(out) >= 1 and out[len(out) - 1].op == "CONST":
                v := out[len(out) - 1].arg
                t := type(v)
                if ins.arg == "not" or ((ins.arg == "-" or ins.arg == "+") and (t == "int" or t == "float")):
                    out[len(out) - 1] = _ir.Instr("CONST", _ir.unary_op(ins.arg, v), ins.line)
                    self.stats["ir_folded"] += 1
                    i += 1
                    continue
            # CONST c ; JUMP_IF_FALSE / JUMP_IF_TRUE
            if (op == "JUMP_IF_FALSE" or op == "JUMP_IF_TRUE") and len(out) >= 1 and out[len(out) - 1].op == "CONST":
                c := _truthy_lit(out[len(out) - 1].arg)
                out = out[:len(out) - 1]
                if (op == "JUMP_IF_FALSE" and not c) or (op == "JUMP_IF_TRUE" and c):
                    append(out, _ir.Instr("JUMP", ins.arg, ins.line))
                self.stats["ir_folded"] += 1
                i += 1
                continue
            # CONST / LOAD / DUP suivi de POP
            if op == "POP" and len(out) >= 1 and (out[len(out) - 1].op == "CONST" or out[len(out) - 1].op == "LOAD" or out[len(out) - 1].op == "DUP"):
                out = out[:len(out) - 1]
                i += 1
                continue
            # ENTER ; EXIT
            if op == "EXIT" and len(out) >= 1 and out[len(out) - 1].op == "ENTER":
                out = out[:len(out) - 1]
                i += 1
                continue
            # JUMP L ; LABEL L
            if op == "JUMP" and i + 1 < n and code[i + 1].op == "LABEL" and code[i + 1].arg == ins.arg:
                i += 1
                continue
            append(out, ins)
            i += 1
        return out

    func thread_jumps(code):
        target := {}
        i := 0
        n := len(code)
        while i < n:
            if code[i].op == "LABEL":
                j := i + 1
                while j < n and code[j].op == "LABEL":
                    j += 1
                if j < n and code[j].op == "JUMP":
                    target[code[i].arg] = code[j].arg
            i += 1
        if len(target) == 0:
            return code
        out := []
        for ins in code:
            if (ins.op == "JUMP" or ins.op == "JUMP_IF_FALSE" or ins.op == "JUMP_IF_TRUE") and ins.arg in target:
                dest := ins.arg
                guard := 0
                while dest in target and guard < 20 and target[dest] != dest:
                    dest = target[dest]
                    guard += 1
                append(out, _ir.Instr(ins.op, dest, ins.line))
            else:
                append(out, ins)
        return out

    func unreachable(code):
        out := []
        dead := false
        for ins in code:
            if ins.op == "LABEL":
                dead = false
            if dead:
                continue
            append(out, ins)
            if ins.op == "JUMP" or ins.op == "RETURN":
                dead = true
        return out

    func unused_labels(code):
        used := {}
        for ins in code:
            if ins.op == "JUMP" or ins.op == "JUMP_IF_FALSE" or ins.op == "JUMP_IF_TRUE" or ins.op == "AND_JUMP" or ins.op == "OR_JUMP" or ins.op == "FOR_ITER":
                used[ins.arg] = true
        return [ins for ins in code if ins.op != "LABEL" or ins.arg in used]

func _count_decl(n, declared):
    k := n.kind
    if k == "Const" or k == "VarDecl" or k == "Func" or k == "Param":
        nm := n.name
        if nm in declared:
            declared[nm] += 1
        else:
            declared[nm] = 1
    elif k == "Assign" and n.target.kind == "Name":
        nm := n.target.name
        if nm in declared:
            declared[nm] += 1
        else:
            declared[nm] = 1

func _part_text(p):
    if _ast.is_node(p):
        return str(p.value)
    return p

func _is_raise(s):
    return s.kind == "ExprStmt" and s.expr.kind == "Call" and s.expr.callee.kind == "Name" and s.expr.callee.name == "raise"

func optimize_ast(program, level=2):
    return Optimizer(level).run_ast(program)

func optimize_ir(m, level=2):
    return Optimizer(level).run_ir(m)
