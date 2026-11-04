# ALEX — native.inline
#
# Intégration (inlining) des petites fonctions feuilles du runtime dans leurs appelants, sur l'IR du compilateur
# natif écrit en ALEX : portage fidèle de src/NativeInline.cpp. Seules les fonctions du runtime sans appel, sans
# exception, sans erreur d'exécution et sans accès au cadre, de 40 instructions au plus, sont intégrées ; trois
# passes au plus (une fonction dont tous les appels ont été intégrés devient à son tour une feuille).
#
#   use native.inline as ni
#   ni.inline_small_functions(prog)       # modifie l'IrProgram en place
#
# Erreurs : aucune.

from core use len, type
from collections use append
use native.ir as ir

const MAX_BODY := 40

const FORBIDDEN := {38: true, 79: true, 93: true, 55: true, 56: true, 50: true, 10: true, 11: true, 12: true,
    8: true, 9: true, 70: true, 71: true, 72: true, 73: true, 74: true, 75: true, 64: true, 65: true, 66: true,
    85: true, 84: true, 86: true, 87: true, 92: true, 80: true, 83: true, 82: true, 81: true, 52: true, 53: true,
    54: true, 57: true, 76: true, 77: true, 51: true, 62: true, 63: true, 49: true, 69: true, 97: true}

func _dead(code, k):
    if k == 0:
        return false
    p := code[k - 1].op
    return (p == ir.RET or p == ir.JMP) and code[k].op != ir.LABEL

# Modules « # alex: inline » (hors runtime) : décalages permis (leur erreur d'exécution reste signalée, à la
# ligne de l'instruction intégrée), corps un peu plus longs.
const MAX_BODY_INLINE := 64

func inlinable(f):
    if not (f.runtime or f.inline) or f.has_try:
        return false
    lax := f.inline and not f.runtime
    n := 0
    k := 0
    code := f.code
    while k < len(code):
        ins := code[k]
        if not _dead(code, k):
            if ins.op in FORBIDDEN and not (lax and (ins.op == ir.SHL or ins.op == ir.SHR)):
                return false
            if ins.op != ir.LABEL:
                n += 1
        k += 1
    return n <= (MAX_BODY_INLINE if lax else MAX_BODY)

func _vr(v, base):
    return v if v < 0 else base + v

# snap : [code, params, vregs, labels] de chaque fonction au début de la passe
func inline_into(caller, snap, ok, me):
    changed := false
    out := []
    for cl in caller.code:
        if cl.op != ir.CALL or cl.callee < 0 or cl.callee == me or not ok[cl.callee]:
            append(out, cl)
            continue
        f := snap[cl.callee]
        fcode := f[0]
        if len(cl.args) != f[1]:
            append(out, cl)
            continue
        changed = true
        base := caller.vregs
        caller.vregs += f[2]
        lbase := caller.labels
        caller.labels += f[3]
        lend := caller.labels
        caller.labels += 1
        p := 0
        while p < f[1]:
            c := ir.Ins(ir.COPY)
            c.dst = base + p
            c.a = cl.args[p]
            c.line = cl.line
            append(out, c)
            p += 1
        k := 0
        while k < len(fcode):
            ins := fcode[k]
            if ins.op == ir.FAIL and _dead(fcode, k):
                k += 1
                continue
            if ins.op == ir.RET:
                if cl.dst >= 0:
                    c := null
                    if ins.a >= 0:
                        c = ir.Ins(ir.COPY)
                        c.dst = cl.dst
                        c.a = _vr(ins.a, base)
                    else:
                        c = ir.Ins(ir.CONST)
                        c.dst = cl.dst
                        c.imm = 0
                    c.line = cl.line
                    append(out, c)
                if k + 1 < len(fcode):
                    j := ir.Ins(ir.JMP)
                    j.label = lend
                    j.line = cl.line
                    append(out, j)
                k += 1
                continue
            c := ins.copy()
            c.dst = _vr(ins.dst, base)
            c.a = _vr(ins.a, base)
            c.b = _vr(ins.b, base)
            c.args = [_vr(a, base) for a in ins.args]
            if c.label >= 0:
                c.label += lbase
            c.line = cl.line
            append(out, c)
            k += 1
        if len(fcode) == 0 or fcode[len(fcode) - 1].op != ir.RET:
            if cl.dst >= 0:
                c := ir.Ins(ir.CONST)
                c.dst = cl.dst
                c.imm = 0
                append(out, c)
        lab := ir.Ins(ir.LABEL)
        lab.label = lend
        append(out, lab)
    if changed:
        caller.code = out
    return changed

func inline_small_functions(p):
    pass_ := 0
    while pass_ < 3:
        ok := [inlinable(f) for f in p.functions]
        anyok := false
        for x in ok:
            anyok = anyok or x
        if not anyok:
            return
        snap := [[f.code, f.params, f.vregs, f.labels] for f in p.functions]
        changed := false
        i := 0
        while i < len(p.functions):
            changed = inline_into(p.functions[i], snap, ok, i) or changed
            i += 1
        if not changed:
            return
        pass_ += 1
