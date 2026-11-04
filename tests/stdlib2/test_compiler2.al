# Tests : compiler.lexer, parser, ast, type_checker, ir, optimizer, codegen, linker, diagnostics, source_map.
from core use len, type
from collections use append
use check as t
use string
use json
use compiler.lexer as lx
use compiler.parser as ps
use compiler.ast as ast
use compiler.type_checker as tc
use compiler.ir as ir
use compiler.optimizer as opt
use compiler.codegen as cg
use compiler.linker as ln
use compiler.diagnostics as dg
use compiler.source_map as sm
from compiler.ast use Visitor

# lexer
toks := lx.tokenize("x := 0x1F + 2.5e3 # c\nif a:\n    b(\"é\\n\", f\"v={x}\", 'c')\n", "demo.al")
types := lx.token_types(toks)
t.eq(types[0], "IDENTIFIER", "ident")
t.eq(types[1], "COLON_EQ", ":=")
t.eq(toks[2].value, 31, "hex")
t.eq(toks[4].value, 2500.0, "float exp")
t.check("INDENT" in types and "DEDENT" in types, "indent/dedent")
t.eq(types[len(types) - 1], "END_OF_FILE", "eof")
t.eq(toks[13].value, "é\n", "échappements")
t.eq(toks[15].type, "FSTRING", "fstring")
t.eq(toks[17].value, 'c', "char")
t.eq(lx.token_types(lx.tokenize("a ..b ** c //= d")), ["IDENTIFIER", "DOT_DOT", "IDENTIFIER", "STAR_STAR", "IDENTIFIER", "SLASH_SLASH_EQ", "IDENTIFIER", "NEWLINE", "END_OF_FILE"], "opérateurs")
t.raises(() => lx.tokenize("x := \"abc\n"), "LexError", "chaîne non terminée")
t.raises(() => lx.tokenize("if a:\n  b\n c\n"), "LexError", "indentation incohérente")
t.raises(() => lx.tokenize("x = 1 ! 2"), "LexError", "!")
t.eq(len(lx.tokenize("# seul\nx\n", "f", true)), 4, "commentaires gardés")
t.eq(len(lx.tokenize("f(1,\n  2)\n")), 8, "continuation implicite")

# parser / ast
e := ps.parse_expression("a + b * 2")
t.eq(ast.dump(e), "(Binary + (Name a) (Binary * (Name b) (Literal 2)))", "priorités")
t.eq(ast.dump(ps.parse_expression("-x ** 2")), "(Binary ** (Unary - (Name x)) (Literal 2))", "unaire puis puissance")
t.eq(ast.dump(ps.parse_expression("not a in b")), "(Unary not (Binary in (Name a) (Name b)))", "not in")
t.eq(ast.dump(ps.parse_expression("a < b <= c")), "(Binary and (Binary < (Name a) (Name b)) (Binary <= (Name b) (Name c)))", "comparaison chaînée")
t.eq(ps.parse_expression("(a, b) => a + b").kind, "Lambda", "lambda")
t.eq(ps.parse_expression("x => x").kind, "Lambda", "lambda simple")
t.eq(ps.parse_expression("s[1:2]").kind, "Slice", "tranche")
t.eq(ps.parse_expression("{1, 2}").kind, "SetLit", "ensemble")
t.eq(ps.parse_expression("{k: v for k in d}").comp, "dict", "compréhension dict")
t.eq(ps.parse_expression("a if c else b").kind, "Ternary", "ternaire")
t.eq(len(ps.parse_expression("f\"x={x} y={y + 1}\"").parts), 4, "fstring parts")
src := "use os as o\nfrom core use len\n@deco\nasync func f(a: int, *r) -> int:\n    with x as y:\n        pass\n    return a\nclass A extends B implements I:\n    n: int\n    func init(n):\n        self.n = n\nenum E:\n    X\n    Y(v)\nmatch v:\n    E.Y(z) if z > 1:\n        print(z)\n    1..3:\n        pass\n    _:\n        pass\ntry:\n    a, *b := xs\ncatch (IoError, ValueError) as e:\n    raise(e)\nfinally:\n    del d[1]\nfor i, j in ps:\n    assert i, \"m\"\n"
p := ps.parse(src, "s.al")
t.eq([s.kind for s in p.body], ["Use", "FromUse", "Func", "Class", "Enum", "Match", "Try", "For"], "instructions")
t.eq(p.body[2].decorators[0].name, "deco", "décorateur")
t.check(p.body[2].is_async and p.body[2].params[1].rest, "async + rest")
t.eq(p.body[3].interfaces, ["I"], "implements")
t.eq(p.body[5].cases[0].pattern.pk, "variant", "motif variante")
t.eq(p.body[6].catches[0].types, ["IoError", "ValueError"], "catch multiple")
t.eq(len(ast.find_all(p, "Name")) > 5, true, "find_all")
t.raises(() => ps.parse("x := (1 + \n"), "LexError", "délimiteur non fermé")
t.raises(() => ps.parse("if x\n    y\n"), "ParseError", "':' manquant")
t.raises(() => ps.parse("a.b := 1\n"), "ParseError", ":= sur membre")
r := ps.try_parse("x = = 1\n", "z.al")
t.check(r[0] == null and r[1].has_errors(), "try_parse")
t.eq(r[1].items[0].line, 1, "ligne du diagnostic")

n := ast.binary("+", ast.literal(1), ast.name("x"))
t.eq(n.left.value, 1, "champ")
t.check(ast.equals(n, n.copy()), "copy/equals")
t.check(ast.equals(ast.from_dict(json.parse(json.stringify(ast.to_dict(p)))), p), "to_dict/from_dict")
t.eq(ast.count(n), 3, "count")

class Compteur extends Visitor:
    func init():
        self.calls = 0
    func visit_Call(c):
        self.calls += 1
        self.generic_visit(c)

cv := Compteur()
cv.visit(ps.parse("f(g(1))\nh()\n"))
t.eq(cv.calls, 3, "visiteur")

# diagnostics / source_map
bag := dg.DiagnosticBag("m.al", "a := 1\nb := zz\n")
bag.error("E0301", "nom 'zz' non défini", 2, 6, 2).note("déclarer zz")
bag.warning("W0101", "x", 1, 1)
txt := bag.render()
t.check(string.contains(txt, "m.al:2:6: erreur[E0301]"), "rendu en-tête")
t.check(string.contains(txt, "     ^~"), "soulignement")
t.eq(bag.codes(), ["W0101", "E0301"], "tri")
t.raises(() => bag.raise_first(), "SemanticError", "raise_first")
f := sm.SourceFile("f.al", "ab\ncd\nef")
t.eq(f.position(4), [2, 2], "position")
t.eq(f.offset(3, 1), 6, "offset")
t.eq(f.line_text(2), "cd", "line_text")
t.eq(sm.decode_vlq(sm.encode_vlq(-17) + sm.encode_vlq(123456)), [-17, 123456], "vlq")
mp := sm.SourceMap("out.al")
mp.add(1, 1, "a.al", 3, 5, "x")
mp.add(2, 3, "a.al", 4, 1)
mp.add(2, 9, "b.al", 1, 1)
t.eq(mp.lookup(2, 5)["line"], 4, "lookup")
t.eq(mp.lookup(2, 20)["file"], "b.al", "lookup fin de ligne")
m2 := sm.from_v3(mp.to_v3())
t.eq(m2.lookup(1, 1)["name"], "x", "v3 aller-retour")
t.eq(m2.size(), 3, "v3 taille")

# type checker
b := tc.check_source("use os\nx := 1\ny := x + \"a\"\nprint(z)\nfunc f(a, b=2):\n    t := 3\n    return a\n    print(1)\nf()\nf(1, 2, 3)\nbreak\nconst K := 1\nK = 2\nw = 5\nclass A:\n    func init(n):\n        self.n = n\na := A(1, 2)\nv: int := \"s\"\n", "d.al")
codes := b.codes()
for c in ["W0102", "E0403", "E0301", "W0101", "W0103", "E0401", "E0305", "E0304", "E0303", "E0402"]:
    t.check(c in codes, "code " + c)
t.eq(len(tc.check_source("func g():\n    return h()\nfunc h() => 1\nprint(g())\n").errors()), 0, "hissage")
t.eq(len(tc.check_source("func f():\n    await x\n").errors()), 2, "await hors async + x")
t.eq(tc.infer_source("[1, 2]"), "list[int]", "inférence liste")
t.eq(tc.infer_source("1 / 2"), "float", "inférence division")
t.eq(tc.infer_source("\"a\" + 'b'"), "str", "inférence str")
t.raises(() => tc.check_or_raise("print(q)\n"), "NameError", "check_or_raise")

# ir + interpréteur
code := "func carre(x) => x * x\nfunc fact(n, acc=1):\n    while n > 1:\n        acc *= n\n        n -= 1\n    return acc\nxs := [carre(i) for i in 0..5 if i % 2 == 0]\nprint(carre(7), fact(5), xs)\ntotal := 0\nfor x in xs:\n    if x > 10:\n        break\n    total += x\nprint(f\"total={total}\")\na, b := 1, 2\nprint(a + b, (y => y + 1)(3), fact(n=4))\nfunc compteur():\n    c := [0]\n    func inc():\n        c[0] += 1\n        return c[0]\n    return inc\nk := compteur()\nk()\nprint(k())\n"
mod := ir.lower(ps.parse(code), "demo")
vm := ir.Interpreter().capture()
vm.run(mod)
t.eq(vm.output, ["49 120 [0, 4, 16]", "total=4", "3 4 24", "2"], "exécution IR")
t.eq(vm.call_function("demo", "fact", [6]), 720, "call_function")
t.check(string.contains(ir.format(mod), "func carre(x):"), "listing")
m3 := ir.from_dict(json.parse(json.stringify(ir.to_dict(mod))))
vm3 := ir.Interpreter().capture()
vm3.run(m3)
t.eq(vm3.output, vm.output, "sérialisation IR")
t.raises(() => ir.lower(ps.parse("class A:\n    pass\n")), "IrError", "classe non prise en charge")
t.raises(() => ir.run(ir.lower(ps.parse("print(inconnu)\n"))), "NameError", "nom inconnu à l'exécution")
t.raises(() => ir.run(ir.lower(ps.parse("raise(\"ValueError\", \"x\")\n"))), "ValueError", "raise")
lim := ir.Interpreter(null, 1000)
t.raises(() => lim.run(ir.lower(ps.parse("while true:\n    pass\n"))), "IrError", "limite d'instructions")

# optimizer
pa := ps.parse("const K := 4\nx := K * 2 + 1\nif false:\n    print(1)\nelse:\n    print(\"a\" + \"b\")\nfunc f():\n    return 1\n    print(2)\ny := 1 // 0\n")
o := opt.Optimizer()
o.run_ast(pa)
t.eq(pa.body[1].value.value, 9, "repliement + const")
t.eq(pa.body[2].then_body[0].expr.args[0].value.value, "ab", "branche constante")
t.eq(len(pa.body[3].body), 1, "code mort")
t.eq(pa.body[4].value.kind, "Binary", "division par zéro non repliée")
t.check(o.stats["folded"] >= 2 and o.stats["dead_code"] == 1, "stats AST")
mi := ir.lower(ps.parse("x := 1\nwhile false:\n    x += 1\nif true:\n    print(x)\n"))
before := mi.instruction_count()
st := opt.optimize_ir(mi)
t.check(mi.instruction_count() < before, "IR réduit")
vm4 := ir.Interpreter().capture()
vm4.run(mi)
t.eq(vm4.output, ["1"], "IR optimisé équivalent")
t.raises(() => opt.Optimizer(5), "ArgumentError", "niveau")

# codegen
t.eq(cg.format_source("x:=1+2\nif x>2 :\n  print( x )\n"), "x := 1 + 2\nif x > 2:\n    print(x)\n", "formatage")
t.eq(cg.format_source("y := (a + b) * c - -d\n"), "y := (a + b) * c - -d\n", "parenthèses minimales")
t.eq(cg.format_source("z := a ** b ** c\nw := (a ** b) ** c\n"), "z := a ** b ** c\nw := (a ** b) ** c\n", "associativité **")
t.check(ast.equals(ps.parse(cg.emit_alex(p)), p), "aller-retour du programme complexe")
mm := cg.emit_alex_mapped(ps.parse("a := 1\n\nb := 2\n"), "x.al")
t.eq(mm[1].lookup(2, 1)["line"], 3, "carte du formatage")
res := cg.compile("func f(n) => n * 2\nprint(f(21))\n", "demo.al")
t.check(res.ok, "compile ok")
t.eq(res.run(true).output, ["42"], "compile + run")
t.check(string.contains(res.summary(), "lexer -> parser"), "phases")
bad := cg.compile("print(q)\n", "q.al")
t.check(not bad.ok and bad.diagnostics.codes() == ["E0301"], "compile avec erreur")
t.check(not cg.compile("x := (\n").ok, "compile erreur de syntaxe")
t.check(not cg.compile("try:\n    pass\ncatch e:\n    pass\n").ok, "construction hors IR -> E0501")
py := cg.emit_python(ps.parse("func f(n):\n    if n == null:\n        return [i * 2 for i in 0..n]\n    return f\"n={n}\"\n"))
t.check(string.contains(py, "def f(n):") and string.contains(py, "for i in range(0, n)") and string.contains(py, "None"), "python")

# linker
l := ln.Linker()
l.add_source("func double(x) => x * 2\nfunc inutile() => 0\n", "outils.al")
l.add_source("from outils use double\nuse outils as o\nprint(double(21), o.double(1))\n", "main.al")
prog := l.link("main")
t.eq(prog.order, ["outils", "main"], "ordre")
t.eq(prog.strip_unused(), ["outils.inutile"], "élimination")
t.check(not string.contains(prog.map_text(), "outils.inutile   "), "carte à jour")
t.eq(prog.run(true).output, ["42 2"], "exécution liée")
t.eq(ln.load_bundle(json.parse(json.stringify(prog.to_dict()))).run(true).output, ["42 2"], "paquet")
l2 := ln.Linker()
l2.add_source("use b\n", "a.al")
l2.add_source("use a\nfrom c use x\n", "b.al")
msg := ""
try:
    l2.link("a")
catch err:
    msg = err.message
t.check(string.contains(msg, "cycle d'import : a -> b -> a") and string.contains(msg, "'c' introuvable"), "cycle + absent")
l3 := ln.Linker()
l3.add_source("x := 1\n", "m1.al")
l3.add_source("from m1 use y\n", "main.al")
t.raises(() => l3.link(), "LinkError", "symbole introuvable")
t.raises(() => ln.Linker().link("rien"), "LinkError", "entrée absente")

t.summary("test_compiler2")
