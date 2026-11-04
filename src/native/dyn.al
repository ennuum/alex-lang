# ALEX — native.dyn
#
# Mode dynamique du compilateur natif écrit en ALEX (étape C) : portage fidèle de src/NativeDyn.cpp. Le bytecode
# de la VM — programme fusionné avec les préludes et la bibliothèque standard, exactement ce que `alexc run`
# exécute — est traduit en IR : chaque fonction devient une fonction f(objet, argc, a0..a7, x) ; la pile
# d'opérandes est résolue à la compilation (profondeur connue avant chaque instruction), chaque case de pile et
# chaque locale devient un registre virtuel ; les opcodes deviennent des appels du runtime dynamique
# (runtime/alex/native/dyn*.al, écrit en ALEX), avec chemins rapides en ligne pour + - * et les
# comparaisons d'entiers. Les modules natifs de la VM sont décrits par native.dyn_registry.
#
#   use native.dyn as nd
#   nd.translate(host, merged, cwd)      # host : native.lower.Lowerer en mode dynamique
#
# Erreurs : RuntimeError (bytecode incohérent : pile, sauts, TRY_END orphelin, fonction de fermeture absente).

from core use len, type
from collections use append
use string as _s
use _native_net as _n
use native.ir as ir
use bytecode.format as bf
use resolver as _bm
use native.dyn_registry as _reg

const K_PARAMS := 11
const K_UNDEFINED := 1

# Dernière occurrence de sub dans s (std::string::rfind), -1 si absente.
func _rfind(s, sub):
    i := len(s) - len(sub)
    while i >= 0:
        if _s.substring(s, i, i + len(sub)) == sub:
            return i
        i -= 1
    return -1

func display_name(n):
    q := _rfind(n, "::")
    if q >= 0:
        n = _s.substring(n, q + 2, len(n))
    if n == "$entry" or n == "":
        return "<module>"
    at := _s.find(n, "@")
    if at >= 0:
        base := _s.substring(n, 0, at)
        return "<lambda>" if base == "" or base == "<lambda>" else base
    h := _s.find(n, "#")
    if h >= 0:
        ty := _s.substring(n, 0, h)
        q2 := _rfind(ty, "::")
        if q2 >= 0:
            ty = _s.substring(ty, q2 + 2, len(ty))
        return ty + "." + _s.substring(n, h + 1, len(n))
    return n

func hidden_function(n):
    q := _rfind(n, "::")
    bare := n if q < 0 else _s.substring(n, q + 2, len(n))
    return bare != "" and bare[0] == '$' and bare != "$entry"

# [pops, pushes, ends]
func effect(ins):
    op := ins[0]
    if op in _E01:
        return [0, 1, false]
    if op in _E10:
        return [1, 0, false]
    if op in _E21:
        return [2, 1, false]
    if op in _E11:
        return [1, 1, false]
    if op in _E00:
        return [0, 0, false]
    if op == bf.JUMP_FALSE:
        return [1, 0, false]
    if op == bf.CALL:
        return [ins[1] + 1, 1, false]
    if op == bf.BUILD_LIST or op == bf.BUILD_TUPLE:
        return [ins[1], 1, false]
    if op == bf.BUILD_DICT:
        return [2 * ins[1], 1, false]
    if op == bf.MAKE_CLOSURE:
        return [ins[2], 1, false]
    if op == bf.SET_INDEX or op == bf.LIST_INSERT:
        return [3, 1 if op == bf.LIST_INSERT else 0, false]
    if op == bf.SET_MEMBER or op == bf.DEF_CLASS or op == bf.ADD_INTERFACE or op == bf.CELL_SET:
        return [2, 0, false]
    if op == bf.CHECK_TYPE:
        return [3, 1, false]
    if op == bf.DECLARE_FIELD_TYPE:
        return [3, 0, false]
    if op == bf.GET_SLICE:
        return [4, 1, false]
    if op == bf.RETURN or op == bf.HALT or op == bf.THROW:
        return [0, 0, true]
    if op == bf.RAISE:
        return [2, 0, true]
    if op == bf.CALL_NATIVE:
        return [0, 0, true]
    return [0, 0, false]

const _E01 := {0: true, 1: true, 3: true, 41: true, 43: true, 45: true, 47: true, 65: true}
const _E10 := {2: true, 4: true, 40: true, 42: true, 62: true}
const _E21 := {5: true, 6: true, 7: true, 8: true, 9: true, 10: true, 11: true, 12: true, 13: true, 14: true,
    15: true, 16: true, 17: true, 19: true, 20: true, 21: true, 22: true, 23: true, 33: true, 51: true, 53: true,
    56: true, 60: true, 61: true, 70: true, 73: true, 75: true, 76: true, 78: true, 79: true}
const _E11 := {18: true, 24: true, 35: true, 46: true, 48: true, 49: true, 50: true, 54: true, 63: true, 69: true,
    77: true}
const _E00 := {25: true, 37: true, 38: true, 44: true, 67: true, 68: true}

class Translator:
    func init(host, module, cwd):
        self.h = host
        self.m = module
        self.p = host.prog
        self.cwd = cwd
        self.global_slot = {}
        self.const_slot = {}
        self.const_order = []
        self.ir_func = {}
        self.entry_by_id = {}
        self.native_code = {}
        self.module_builder = {}
        self.fn_ = null
        self.line = 0
        self.modules = {}
        for mm in _reg.MODULES:
            self.modules[mm[0]] = mm[1]

    # ------------------------------------------------------------------ émission
    func reg():
        r := self.fn_.vregs
        self.fn_.vregs = r + 1
        return r

    func label():
        l := self.fn_.labels
        self.fn_.labels = l + 1
        return l

    func emit(i):
        i.line = self.line
        append(self.fn_.code, i)

    func _ins(op, dst=-1, a=-1, b=-1, imm=0):
        i := ir.Ins(op)
        i.dst = dst
        i.a = a
        i.b = b
        i.imm = imm
        return i

    func constant(v):
        d := self.reg()
        self.emit(self._ins(ir.CONST, d, -1, -1, v))
        return d

    func str_const(s):
        d := self.reg()
        self.emit(self._ins(ir.STR_CONST, d, -1, -1, self.h.string_index(s)))
        return d

    func rt(name, args, result=true):
        i := ir.Ins(ir.CALL)
        i.callee = self.h.runtime_function(name)
        i.args = args
        i.dst = self.reg() if result else -1
        d := i.dst
        self.emit(i)
        return d

    func call_ir(f, args, result=true):
        i := ir.Ins(ir.CALL)
        i.callee = f
        i.args = args
        i.dst = self.reg() if result else -1
        d := i.dst
        self.emit(i)
        return d

    func load_global(g):
        d := self.reg()
        self.emit(self._ins(ir.LOAD_GLOBAL, d, -1, -1, g))
        return d

    func store_global(g, v):
        self.emit(self._ins(ir.STORE_GLOBAL, -1, v, -1, g))

    func copy(dst, src):
        self.emit(self._ins(ir.COPY, dst, src))

    func place(l):
        i := ir.Ins(ir.LABEL)
        i.label = l
        self.emit(i)

    func jump(op, l, a=-1):
        i := ir.Ins(op)
        i.label = l
        i.a = a
        self.emit(i)

    func bin(op, a, b):
        d := self.reg()
        self.emit(self._ins(op, d, a, b))
        return d

    func load64(a, off):
        d := self.reg()
        self.emit(self._ins(ir.LOAD64, d, a, -1, off))
        return d

    # [va, vb] après les gardes « deux int » (saut vers slow sinon)
    func int_guard(a, b, slow):
        self.jump(ir.JMP_IF_ZERO, slow, a)
        self.jump(ir.JMP_IF_ZERO, slow, b)
        one := self.constant(1)
        self.jump(ir.JMP_IF_ZERO, slow, self.bin(ir.EQ, self.load64(a, 0), one))
        self.jump(ir.JMP_IF_ZERO, slow, self.bin(ir.EQ, self.load64(b, 0), one))
        va := self.load64(a, 8)
        vb := self.load64(b, 8)
        return [va, vb]

    func fast_arith(op, a, b):
        res := self.reg()
        slow := self.label()
        end := self.label()
        g := self.int_guard(a, b, slow)
        irop := ir.ADD if op == bf.ADD else ir.SUB if op == bf.SUB else ir.MUL
        self.copy(res, self.rt("__dyn_int", [self.bin(irop, g[0], g[1])]))
        self.jump(ir.JMP, end)
        self.place(slow)
        self.copy(res, self.rt("__dyn_arith", [self.constant(op), a, b]))
        self.place(end)
        return res

    func fast_compare(op, a, b):
        res := self.reg()
        slow := self.label()
        end := self.label()
        no := self.label()
        g := self.int_guard(a, b, slow)
        irop := ir.EQ if op == bf.EQ else ir.NE if op == bf.NE else ir.LT if op == bf.LT else ir.LE if op == bf.LE else ir.GT if op == bf.GT else ir.GE
        c := self.bin(irop, g[0], g[1])
        ds := self.load_global(0)
        self.jump(ir.JMP_IF_ZERO, no, c)
        self.copy(res, self.load64(ds, 0))
        self.jump(ir.JMP, end)
        self.place(no)
        self.copy(res, self.load64(ds, 8))
        self.jump(ir.JMP, end)
        self.place(slow)
        self.copy(res, self.rt("__dyn_compare", [self.constant(op), a, b]))
        self.place(end)
        return res

    func jump_false(v, target):
        cont := self.label()
        ds := self.load_global(0)
        self.jump(ir.JMP_IF_NON_ZERO, cont, self.bin(ir.EQ, v, self.load64(ds, 0)))
        self.jump(ir.JMP_IF_NON_ZERO, target, self.bin(ir.EQ, v, self.load64(ds, 8)))
        self.jump(ir.JMP_IF_ZERO, target, self.rt("__dyn_truthy", [v]))
        self.place(cont)

    func func_addr(irf):
        d := self.reg()
        i := ir.Ins(ir.FUNC_ADDR)
        i.dst = d
        i.callee = irf
        self.emit(i)
        return d

    func const_string(k):
        if k >= len(self.m.constants) or self.m.constants[k][0] != bf.T_STRING:
            raise("RuntimeError", "mode dynamique : la constante " + str(k) + " doit être une chaîne")
        return self.m.constants[k][1]

    func global_of(name):
        if name in self.global_slot:
            return self.global_slot[name]
        g := self.h.new_global()
        self.global_slot[name] = g
        return g

    func const_slot_of(k):
        if k in self.const_slot:
            return self.const_slot[k]
        g := self.h.new_global()
        self.const_slot[k] = g
        append(self.const_order, k)
        return g

    func func_name(f):
        return self.const_string(f.name_const)

    # ------------------------------------------------------------------ modules natifs
    func native_code_for(module, ex):
        key := module + "." + ex[0]
        if key in self.native_code:
            return self.native_code[key]
        impl := "__nat_" + ("_native_core" if module == "core" else module) + "__" + ex[0]
        impl = _s.replace(impl, ".", "_")
        code := -1
        if not self.h.has_runtime_function(impl):
            code = self.h.runtime_function("__dyn_native_missing")
        else:
            f := self.h.runtime_function(impl)
            np := self.p.functions[f].params
            if np == K_PARAMS:
                code = f
            else:
                w := ir.IrFunction("$native " + key)
                w.runtime = true
                w.params = K_PARAMS
                w.vregs = K_PARAMS
                code = len(self.p.functions)
                append(self.p.functions, w)
                saved := self.fn_
                self.fn_ = w
                args := []
                i := 0
                while i < np and i < 9:
                    append(args, 1 + i)
                    i += 1
                r := self.call_ir(f, args)
                ret := ir.Ins(ir.RET)
                ret.a = r
                self.emit(ret)
                self.fn_ = saved
        self.native_code[key] = code
        return code

    func export_value(module, ex):
        ck := ex[4]
        if ck == 1:
            return self.constant(0)
        if ck == 2:
            return self.rt("__dyn_bool", [self.constant(ex[5])])
        if ck == 3:
            return self.rt("__dyn_int", [self.constant(ex[5])])
        if ck == 4:
            return self.rt("__dyn_float_bits", [self.constant(ex[6])])
        if ck == 5:
            return self.rt("__dyn_str", [self.str_const(ex[7])])
        if ex[1]:
            if not (ex[2] in self.entry_by_id):
                return self.constant(0)
            return self.load_global(self.global_of(self.func_name(self.entry_by_id[ex[2]])))
        code := self.native_code_for(module, ex)
        return self.rt("__dyn_native_new", [self.func_addr(code), self.str_const(ex[3])])

    func module_builder_for(module):
        if module in self.module_builder:
            return self.module_builder[module]
        w := ir.IrFunction("$module " + module)
        w.runtime = true
        fid := len(self.p.functions)
        append(self.p.functions, w)
        self.module_builder[module] = fid
        saved := self.fn_
        self.fn_ = w
        inst := -1
        if not (module in self.modules):
            inst = self.constant(0)
        else:
            inst = self.rt("__dyn_new_instance", [self.str_const(module)])
            for ex in self.modules[module]:
                self.rt("__dyn_set_member", [inst, self.str_const(ex[0]), self.export_value(module, ex)], false)
        ret := ir.Ins(ir.RET)
        ret.a = inst
        self.emit(ret)
        self.fn_ = saved
        return fid

    # ------------------------------------------------------------------ fonctions
    func _depth_slot(value):
        st := ir.Ins(ir.STORE64)
        st.a = self.load_global(0)
        st.b = value
        st.imm = 80
        self.emit(st)

    func _sig_check():
        flag := self.reg()
        self.emit(self._ins(ir.LOAD64, flag, self.load_global(0), -1, 200))
        skip := self.label()
        self.jump(ir.JMP_IF_ZERO, skip, flag)
        self.rt("__sig_check", [], false)
        self.place(skip)

    func _ret_with(v, handlers, rec_of, depth_in):
        self._depth_slot(depth_in)
        k := len(handlers)
        while k > 0:
            k -= 1
            e := ir.Ins(ir.TRY_END)
            e.a = rec_of[handlers[k]]
            self.emit(e)
        r := ir.Ins(ir.RET)
        r.a = v
        self.emit(r)

    func translate_function(fe):
        self.fn_ = self.p.functions[self.ir_func[fe.function_id]]
        code := bf.decode_code(self.m.code, fe.code_offset, fe.code_length)
        n := len(code)
        at := {}
        i := 0
        while i < n:
            at[code[i][0]] = i
            i += 1
        fname := self.func_name(fe)
        depth := [-1 for j in 0..n]
        handlers := [null for j in 0..n]
        is_target := [false for j in 0..n]
        is_catch := [false for j in 0..n]
        work := []
        if n > 0:
            self._flow(0, 0, [], depth, handlers, work, n, fname)
        while len(work) > 0:
            i = work[len(work) - 1]
            work = work[0:len(work) - 1]
            ins := code[i][1]
            sd := depth[i]
            hs := handlers[i]
            e := effect(ins)
            if sd < e[0]:
                raise("RuntimeError", "mode dynamique : pile insuffisante pour " + bf.opcode_name(ins[0]) + " dans " + fname)
            after := sd - e[0] + e[1]
            op := ins[0]
            if op == bf.JUMP:
                t := self._target(at, ins[1], fname)
                is_target[t] = true
                self._flow(t, after, hs, depth, handlers, work, n, fname)
                continue
            if op == bf.JUMP_FALSE:
                t := self._target(at, ins[1], fname)
                is_target[t] = true
                self._flow(t, after, hs, depth, handlers, work, n, fname)
                self._flow(i + 1, after, hs, depth, handlers, work, n, fname)
                continue
            if op == bf.TRY_BEGIN:
                t := self._target(at, ins[1], fname)
                is_target[t] = true
                is_catch[t] = true
                self._flow(t, sd, hs, depth, handlers, work, n, fname)
                hs2 := [x for x in hs]
                append(hs2, i)
                self._flow(i + 1, after, hs2, depth, handlers, work, n, fname)
                continue
            if op == bf.TRY_END:
                if len(hs) == 0:
                    raise("RuntimeError", "mode dynamique : TRY_END sans TRY_BEGIN dans " + fname)
                self._flow(i + 1, after, hs[0:len(hs) - 1], depth, handlers, work, n, fname)
                continue
            if e[2]:
                continue
            self._flow(i + 1, after, hs, depth, handlers, work, n, fname)
        self.fn_.params = K_PARAMS
        self.fn_.vregs = K_PARAMS
        max_depth := 0
        for d in depth:
            if d > max_depth:
                max_depth = d
        for pr in code:
            pu := effect(pr[1])[1]
            if pu > max_depth:
                max_depth = pu
        local := [self.reg() for j in 0..fe.locals_count]
        S := [self.reg() for j in 0..(max_depth + 8)]
        labels := [self.label() for j in 0..n]
        catch_labels := [-1 for j in 0..n]
        rec_of := {}
        i = 0
        while i < n:
            if code[i][1][0] == bf.TRY_BEGIN:
                top := -1
                k := 0
                while k < 9:
                    top = self.reg()
                    k += 1
                rec_of[i] = top
                self.fn_.has_try = true
            i += 1
        i = 0
        while i < n:
            if is_catch[i]:
                catch_labels[i] = self.label()
            i += 1
        dl := fe.debug_lines
        self.line = 0 if len(dl) == 0 else dl[0][1]
        method := _s.find(fname, "#") >= 0
        slots := (fe.arity_max & 0x7fff) + (1 if (fe.arity_max & 0x8000) != 0 else 0) + (1 if method else 0)
        i = 0
        while i < len(local):
            if i < slots and i < 8:
                self.copy(local[i], 2 + i)
            elif i < slots:
                self.copy(local[i], self.rt("__dyn_xarg", [10, self.constant(i - 8)]))
            else:
                self.copy(local[i], self.constant(0))
            i += 1
        depth_in := self.reg()
        depth_out := self.reg()
        self.emit(self._ins(ir.LOAD64, depth_in, self.load_global(0), -1, 80))
        c := self.reg()
        ge := ir.Ins(ir.GE)
        ge.dst = c
        ge.a = depth_in
        ge.b = self.constant(100000)
        self.emit(ge)
        okl := self.label()
        self.jump(ir.JMP_IF_ZERO, okl, c)
        self.rt("__dyn_recursion_error", [], false)
        self.place(okl)
        add := ir.Ins(ir.ADD)
        add.dst = depth_out
        add.a = depth_in
        add.b = self.constant(1)
        self.emit(add)
        self._depth_slot(depth_out)
        self._sig_check()
        li := 0
        i = 0
        while i < n:
            off := code[i][0]
            ins := code[i][1]
            # ligne : dernière entrée de la table dont le décalage est <= off
            ln := 0
            for pr in dl:
                if pr[0] > off:
                    break
                ln = pr[1]
            self.line = ln
            if is_catch[i]:
                skip := self.label()
                self.jump(ir.JMP, skip)
                self.place(catch_labels[i])
                exc := self.reg()
                self.emit(self._ins(ir.LANDING, exc))
                self._depth_slot(depth_out)
                ev := self.rt("__dyn_exc_box", [exc])
                j := 0
                while j < n:
                    tb := code[j][1]
                    if tb[0] == bf.TRY_BEGIN and self._target(at, tb[1], fname) == i and tb[2] != bf.NO_CONST and tb[2] < len(local):
                        self.copy(local[tb[2]], ev)
                        break
                    j += 1
                self.jump(ir.JMP, labels[i])
                self.place(skip)
            self.place(labels[i])
            if depth[i] < 0:
                i += 1
                continue
            self.op(ins, depth[i], handlers[i], S, local, labels, catch_labels, rec_of, at, i, fname, depth_in)
            i += 1
        self._ret_with(self.constant(0), [], rec_of, depth_in)

    func _target(at, off, fname):
        if not (off in at):
            raise("RuntimeError", "mode dynamique : cible de saut invalide dans " + fname)
        return at[off]

    func _flow(to, d, hs, depth, handlers, work, n, fname):
        if to >= n:
            return
        if depth[to] < 0:
            depth[to] = d
            handlers[to] = hs
            append(work, to)
        elif depth[to] != d:
            raise("RuntimeError", "mode dynamique : profondeur de pile incohérente dans " + fname + " (instruction " + str(to) + ")")

    func op(ins, d, hs, S, local, labels, catch_labels, rec_of, at, i, fname, depth_in):
        op := ins[0]
        a := ins[1]
        pops := effect(ins)[0]
        if op == bf.CONST:
            c := self.m.constants[a]
            if c[0] == bf.T_NULL:
                self.copy(S[d], self.constant(0))
            else:
                self.copy(S[d], self.load_global(self.const_slot_of(a)))
            return
        if op == bf.POP:
            return
        if op == bf.DUP:
            self.copy(S[d], S[d - 1])
            return
        if op == bf.LOAD_LOCAL:
            self.copy(S[d], local[a])
            return
        if op == bf.STORE_LOCAL:
            self.copy(local[a], S[d - 1])
            return
        if op == bf.LOAD_GLOBAL:
            g := self.const_string(a)
            v := self.load_global(self.global_of(g))
            bad := self.reg()
            okl := self.label()
            eq := ir.Ins(ir.EQ)
            eq.dst = bad
            eq.a = v
            eq.b = self.constant(K_UNDEFINED)
            self.emit(eq)
            self.jump(ir.JMP_IF_ZERO, okl, bad)
            self.rt("__dyn_name_error", [self.str_const(g)], false)
            self.place(okl)
            self.copy(S[d], v)
            return
        if op == bf.STORE_GLOBAL:
            self.store_global(self.global_of(self.const_string(a)), S[d - 1])
            return
        push_at := d - pops
        if op == bf.ADD or op == bf.SUB or op == bf.MUL:
            self.copy(S[push_at], self.fast_arith(op, S[d - 2], S[d - 1]))
            return
        if op == bf.DIV or op == bf.FLOORDIV or op == bf.MOD or op == bf.POW:
            self.copy(S[push_at], self.rt("__dyn_arith", [self.constant(op), S[d - 2], S[d - 1]]))
            return
        if op >= bf.EQ and op <= bf.GE:
            self.copy(S[push_at], self.fast_compare(op, S[d - 2], S[d - 1]))
            return
        if op == bf.BAND or op == bf.BOR or op == bf.BXOR or op == bf.SHL or op == bf.SHR:
            self.copy(S[push_at], self.rt("__dyn_bitwise", [self.constant(op), S[d - 2], S[d - 1]]))
            return
        if op == bf.NOT:
            self.copy(S[push_at], self.rt("__dyn_not", [S[d - 1]]))
            return
        if op == bf.BITNOT:
            self.copy(S[push_at], self.rt("__dyn_bitnot", [S[d - 1]]))
            return
        if op == bf.JUMP:
            t := self._target(at, a, fname)
            if t <= i:
                self._sig_check()
            self.jump(ir.JMP, labels[t])
            return
        if op == bf.JUMP_FALSE:
            self.jump_false(S[d - 1], labels[self._target(at, a, fname)])
            return
        if op == bf.CALL:
            argc := a
            callee := S[d - 1 - argc]
            args := [callee, self.constant(argc)]
            k := 0
            while k < 8:
                append(args, S[d - 1 - (argc - 1 - k)] if k < argc else self.constant(0))
                k += 1
            if argc > 8:
                xt := self.rt("__dyn_tuple_new", [self.constant(argc - 8)])
                k = 8
                while k < argc:
                    self.rt("__dyn_tuple_put", [xt, self.constant(k - 8), S[d - 1 - (argc - 1 - k)]], false)
                    k += 1
                append(args, xt)
            else:
                append(args, self.constant(0))
            self.copy(S[push_at], self.rt("__dyn_call", args))
            return
        if op == bf.CALL_SPREAD:
            self.copy(S[push_at], self.rt("__dyn_call_spread", [S[d - 2], S[d - 1]]))
            return
        if op == bf.RETURN or op == bf.HALT:
            self._ret_with(S[d - 1] if d > 0 else self.constant(0), hs, rec_of, depth_in)
            return
        if op == bf.BUILD_LIST or op == bf.BUILD_TUPLE:
            k := a
            nm := "__dyn_list" if op == bf.BUILD_LIST else "__dyn_tuple"
            l := self.rt(nm + "_new", [self.constant(k)])
            j := 0
            while j < k:
                self.rt(nm + "_put", [l, self.constant(j), S[d - 1 - (k - 1 - j)]], false)
                j += 1
            self.copy(S[push_at], l)
            return
        if op == bf.BUILD_DICT:
            k := a
            dd := self.rt("__dyn_dict_new", [])
            j := 0
            while j < k:
                self.rt("__dyn_dict_lit_set", [dd, S[d - 1 - (2 * (k - j) - 1)], S[d - 1 - (2 * (k - j) - 2)]], false)
                j += 1
            self.copy(S[push_at], dd)
            return
        if op == bf.GET_INDEX:
            self.copy(S[push_at], self.rt("__dyn_get_index", [S[d - 2], S[d - 1]]))
            return
        if op == bf.SET_INDEX:
            self.rt("__dyn_set_index", [S[d - 3], S[d - 2], S[d - 1]], false)
            return
        if op == bf.GET_MEMBER:
            self.copy(S[push_at], self.rt("__dyn_get_member", [S[d - 1], self.str_const(self.const_string(a))]))
            return
        if op == bf.SET_MEMBER:
            self.rt("__dyn_set_member", [S[d - 2], self.str_const(self.const_string(a)), S[d - 1]], false)
            return
        if op == bf.TRY_BEGIN:
            tb := ir.Ins(ir.TRY_BEGIN)
            tb.a = rec_of[i]
            tb.label = catch_labels[self._target(at, a, fname)]
            self.emit(tb)
            return
        if op == bf.TRY_END:
            if len(hs) == 0:
                raise("RuntimeError", "mode dynamique : TRY_END orphelin")
            te := ir.Ins(ir.TRY_END)
            te.a = rec_of[hs[len(hs) - 1]]
            self.emit(te)
            return
        if op == bf.THROW:
            self.rt("__dyn_throw", [S[d - 1]], false)
            return
        if op == bf.RAISE:
            self.rt("__dyn_raise", [S[d - 2], S[d - 1]], false)
            return
        if op == bf.PRINT:
            self.rt("__dyn_print", [S[d - 1]], false)
            return
        if op == bf.INPUT:
            self.copy(S[d], self.rt("__dyn_input", []))
            return
        if op == bf.IMPORT:
            mn := self.const_string(a)
            if not (mn in self.modules):
                self.rt("__dyn_import_error", [self.str_const(mn)], false)
                return
            mo := self.call_ir(self.module_builder_for(mn), [])
            for ex in self.modules[mn]:
                self.store_global(self.global_of(ex[0]), self.rt("__dyn_get_member", [mo, self.str_const(ex[0])]))
            return
        if op == bf.IMPORT_MODULE:
            mn := self.const_string(a)
            if not (mn in self.modules):
                self.rt("__dyn_import_error", [self.str_const(mn)], false)
                self.copy(S[d], self.constant(0))
                return
            self.copy(S[d], self.call_ir(self.module_builder_for(mn), []))
            return
        if op == bf.NEW_INSTANCE:
            self.copy(S[d], self.rt("__dyn_new_instance", [self.str_const(self.const_string(a))]))
            return
        if op in SIMPLE_1:
            self.copy(S[push_at], self.rt(SIMPLE_1[op], [S[d - 1]]))
            return
        if op in SIMPLE_2:
            self.copy(S[push_at], self.rt(SIMPLE_2[op], [S[d - 2], S[d - 1]]))
            return
        if op == bf.LIST_INSERT:
            self.copy(S[push_at], self.rt("__dyn_list_insert", [S[d - 3], S[d - 2], S[d - 1]]))
            return
        if op == bf.DEF_CLASS:
            self.rt("__dyn_def_class", [S[d - 2], S[d - 1]], false)
            return
        if op == bf.ADD_INTERFACE:
            self.rt("__dyn_add_interface", [S[d - 2], S[d - 1]], false)
            return
        if op == bf.GET_SUPER:
            self.copy(S[push_at], self.rt("__dyn_get_super", [S[d - 2], S[d - 1], self.str_const(self.const_string(a))]))
            return
        if op == bf.NEW_CELL:
            self.copy(local[a], self.rt("__dyn_cell_new", [S[d - 1]]))
            return
        if op == bf.NEW_CELL_EMPTY:
            self.copy(local[a], self.rt("__dyn_cell_empty", []))
            return
        if op == bf.CELL_SET:
            self.rt("__dyn_cell_set", [S[d - 1], S[d - 2]], false)
            return
        if op == bf.UPVALUE_CELL:
            self.copy(S[d], self.rt("__dyn_upvalue", [0, self.constant(a)]))
            return
        if op == bf.MAKE_CLOSURE:
            nm := self.const_string(a)
            model := null
            for f in self.m.functions:
                if self.func_name(f) == nm:
                    model = f
            if model == null:
                raise("RuntimeError", "mode dynamique : MAKE_CLOSURE : fonction '" + nm + "' introuvable")
            k := ins[2]
            env := -1
            if k > 0:
                env = self.rt("__dyn_tuple_new", [self.constant(k)])
                j := 0
                while j < k:
                    self.rt("__dyn_tuple_put", [env, self.constant(j), S[d - 1 - (k - 1 - j)]], false)
                    j += 1
            else:
                env = self.constant(0)
            dec := bf.decode_code(self.m.code, model.code_offset, model.code_length)
            is_async := len(dec) > 0 and dec[0][1][0] == bf.ASYNC_ENTRY
            self.copy(S[push_at], self.rt("__dyn_func_new", [self.func_addr(self.ir_func[model.function_id]), self.str_const(nm), self.constant(model.arity_min), self.constant(model.arity_max), env, self.constant(1 if is_async else 0)]))
            return
        if op == bf.ASYNC_ENTRY:
            return
        if op == bf.CHECK_TYPE:
            self.rt("__dyn_check_type", [S[d - 3], S[d - 2], S[d - 1]], false)
            return
        if op == bf.DECLARE_FIELD_TYPE:
            self.rt("__dyn_declare_field_type", [S[d - 3], S[d - 2], S[d - 1]], false)
            return
        if op == bf.GET_SLICE:
            self.copy(S[push_at], self.rt("__dyn_get_slice", [S[d - 4], S[d - 3], S[d - 2], S[d - 1]]))
            return
        if op == bf.CALL_NATIVE:
            raise("RuntimeError", "mode dynamique : opcode CALL_NATIVE non pris en charge (comme la VM)")

    # ------------------------------------------------------------------ initialisation
    func build_init(entry_ir):
        init := ir.IrFunction("$dyninit")
        init.runtime = true
        fid := len(self.p.functions)
        append(self.p.functions, init)
        self.fn_ = init
        self.rt("__dyn_init", [], false)
        undef := self.constant(K_UNDEFINED)
        gl := [[nm, self.global_slot[nm]] for nm in self.global_slot]
        gl = _sort_by_second(gl)
        for pr in gl:
            self.store_global(pr[1], undef)
        for k in self.const_order:
            g := self.const_slot[k]
            c := self.m.constants[k]
            v := -1
            t := c[0]
            if t == bf.T_NULL:
                v = self.constant(0)
            elif t == bf.T_BOOL:
                v = self.rt("__dyn_bool", [self.constant(1 if c[1] else 0)])
            elif t == bf.T_INT:
                v = self.rt("__dyn_int", [self.constant(c[1])])
            elif t == bf.T_FLOAT:
                rb := self.reg()
                self.emit(self._ins(ir.CONST, rb, -1, -1, _n.f64_bits(c[1])))
                v = self.rt("__dyn_float_bits", [rb])
            elif t == bf.T_CHAR:
                v = self.rt("__dyn_char", [self.constant(c[1])])
            elif t == bf.T_BYTE:
                v = self.rt("__dyn_byte", [self.constant(c[1])])
            elif t == bf.T_STRING:
                v = self.rt("__dyn_str", [self.str_const(c[1])])
            self.store_global(g, v)
        for fe in self.m.functions:
            dec := bf.decode_code(self.m.code, fe.code_offset, fe.code_length)
            is_async := len(dec) > 0 and dec[0][1][0] == bf.ASYNC_ENTRY
            nm := self.func_name(fe)
            g := self.global_of(nm)
            fv := self.rt("__dyn_func_new", [self.func_addr(self.ir_func[fe.function_id]), self.str_const(nm), self.constant(fe.arity_min), self.constant(fe.arity_max), self.constant(0), self.constant(1 if is_async else 0)])
            self.store_global(g, fv)
            if _s.find(nm, "#") >= 0:
                self.rt("__dyn_reg_method", [self.str_const(nm), self.constant(g)], false)
        inst := self.rt("__dyn_new_instance", [self.str_const("core")])
        for ex in _reg.BOOTSTRAP_CORE:
            v := self.export_value("core", ex)
            self.rt("__dyn_set_member", [inst, self.str_const(ex[0]), v], false)
            if ex[0] == "len" or ex[0] == "to_int":
                self.store_global(self.global_of(ex[0]), v)
        self.store_global(self.global_of("core"), inst)
        efe := self.entry_by_id[self.m.entry_function]
        fobj := self.load_global(self.global_of(self.func_name(efe)))
        args := [fobj, self.constant(0)]
        k := 0
        while k < 9:
            append(args, self.constant(0))
            k += 1
        self.call_ir(entry_ir, args, false)
        self.rt("__dyn_end", [], false)
        self.emit(ir.Ins(ir.RET))
        f0 := self.p.functions[0]
        f0.runtime = true
        cl := ir.Ins(ir.CALL)
        cl.callee = fid
        f0.code = [cl] + f0.code

    func run():
        ds := self.h.new_global()
        if ds != 0:
            raise("RuntimeError", "mode dynamique : la globale 0 doit être l'état du runtime")
        for fe in self.m.functions:
            self.entry_by_id[fe.function_id] = fe
            nm := self.func_name(fe)
            f := ir.IrFunction(display_name(nm))
            f.runtime = hidden_function(nm)
            file := ""
            sc := fe.source_const
            if sc != bf.NO_CONST and sc < len(self.m.constants) and self.m.constants[sc][0] == bf.T_STRING:
                file = self.m.constants[sc][1]
            if file == "":
                file = "<inconnu>"
            if self.cwd != "" and _bm.path_is_under(file, self.cwd):
                file = _rel_to(file, self.cwd)
            f.file = self.h.file_index(file)
            self.ir_func[fe.function_id] = len(self.p.functions)
            append(self.p.functions, f)
        for fe in self.m.functions:
            self.translate_function(fe)
        self.build_init(self.ir_func[self.m.entry_function])

# pathRelativeTo (alex/PathPrefix.hpp)
func _rel_to(path, d):
    n := len(d)
    if not _s.ends_with(d, "/"):
        n += 1
    return "" if n >= len(path) else _s.substring(path, n, len(path))

func _sort_by_second(xs):
    if len(xs) <= 1:
        return xs
    mid := len(xs) // 2
    l := _sort_by_second(xs[0:mid])
    r := _sort_by_second(xs[mid:len(xs)])
    out := []
    i := 0
    j := 0
    while i < len(l) and j < len(r):
        if r[j][1] < l[i][1]:
            append(out, r[j])
            j += 1
        else:
            append(out, l[i])
            i += 1
    while i < len(l):
        append(out, l[i])
        i += 1
    while j < len(r):
        append(out, r[j])
        j += 1
    return out

const SIMPLE_1 := {46: "__dyn_to_string", 48: "__dyn_type_name_v", 49: "__dyn_len", 50: "__dyn_dict_keys",
    54: "__dyn_list_clear", 63: "__dyn_cell_get", 69: "__dyn_await", 77: "__dyn_list_to_tuple"}
const SIMPLE_2 := {51: "__dyn_list_append", 53: "__dyn_list_remove_at", 56: "__dyn_dict_remove_key",
    61: "__dyn_instance_of", 70: "__dyn_exc_matches", 73: "__dyn_contains", 75: "__dyn_del_item",
    76: "__dyn_list_extend", 78: "__dyn_dict_update"}

func translate(host, module, cwd):
    Translator(host, module, cwd).run()
