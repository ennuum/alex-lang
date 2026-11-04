# ALEX - tests du paquet web.js. Lancer depuis la racine : ./alex run tests/web/test_web_js.al
use testing
use web.js as js
use web.js.js_types as jt
use web.js.js_value as jv
use web.js.js_expression as je
use web.js.js_statement as st
use web.js.js_function as jf
use web.js.js_object as jo
use web.js.js_array as ja
use web.js.js_import as ji
use web.js.js_export as jx
use web.js.js_module as jm
use web.js.js_generator as jg
use web.js.js_source_map as sm
use web.js.js_validator as val
use web.js.js_formatter as fmt
use web.js.js_minifier as mini
use web.js.js_bridge as jb
use web.js.js_runtime_bridge as rb
use web.js.js_interop as rpc
use web.server.request_dispatch as rd
use web.http.request as hreq
from core use len
from collections use append
from testing use assert_eq, assert_true, assert_false, assert_null, assert_raises

RT := rb.find_runtime()

func t_types_values():
    assert_true(jt.is_identifier("$el"))
    assert_false(jt.is_identifier("class"))
    assert_true(jt.is_identifier_name("class"))
    assert_eq(jt.quote("L'été \"chaud\"\n"), "\"L'été \\\"chaud\\\"\\n\"")
    assert_eq(jt.quote("é😀", "\"", true), "\"\\u00e9\\ud83d\\ude00\"")
    assert_eq(jt.quote("</script>", "\"", false, true), "\"<\\/script>\"")
    assert_eq(jt.number(1.0), "1")
    assert_eq(jt.number(1e300 * 1e10), "Infinity")
    assert_eq(jt.property_key("data-x"), "\"data-x\"")
    assert_eq(jt.safe_identifier("2e classe"), "_2e_classe")
    assert_eq(jt.typeof(jt.UNDEFINED), "undefined")
    assert_eq(jv.to_js({"nom": "Ada", "data-x": [1, 2.5, true, null], "f": jv.Raw("() => 42")}), "{nom: \"Ada\", \"data-x\": [1, 2.5, true, null], f: () => 42}")
    assert_eq(jv.to_js({"a": {"b": [1]}}, "  "), "{\n  a: {\n    b: [\n      1\n    ]\n  }\n}")
    v := jv.from_js("{ nom: 'Ada', // c\n  âge: 0x24, tags: [`a`, 'b',], q: \"\\u00e9\\uD83D\\uDE00\", n: -.5e1, }")
    assert_eq(v["âge"], 36)
    assert_eq(v["tags"], ["a", "b"])
    assert_eq(v["q"], "é😀")
    assert_eq(v["n"], -5.0)
    assert_eq(jv.from_js("[1_000, 0b101, 0o17, undefined]"), [1000, 5, 15, null])
    assert_raises(() => jv.from_js("{a: }"), "JsSyntaxError")
    assert_raises(() => jv.from_js("[1 2]"), "JsSyntaxError")
    assert_eq(jv.to_json_compatible({"a": jt.UNDEFINED, "b": [jt.UNDEFINED]}), {"b": [null]})

testing.test("types et valeurs", t_types_values)

func t_expressions():
    assert_eq(je.ident("document").dot("querySelector").call([je.lit("#app")]).to_js(), "document.querySelector(\"#app\")")
    assert_eq(je.binary("*", je.binary("+", je.ident("a"), je.ident("b")), 2).to_js(), "(a + b) * 2")
    assert_eq(je.binary("-", je.ident("a"), je.binary("-", je.ident("b"), je.ident("c"))).to_js(), "a - (b - c)")
    assert_eq(je.binary("**", je.unary("-", je.ident("a")), 2).to_js(), "(-a) ** 2")
    assert_eq(je.binary("**", 2, je.binary("**", 3, 2)).to_js(), "2 ** 3 ** 2")
    assert_eq(je.binary("??", je.binary("||", je.ident("a"), je.ident("b")), je.ident("c")).to_js(), "(a || b) ?? c")
    assert_eq(je.arrow([], je.object({"a": 1})).to_js(), "() => ({a: 1})")
    assert_eq(je.ident("user").dot("name", true).op("??", "anonyme").to_js(), "user?.name ?? \"anonyme\"")
    assert_eq(je.template(["Bonjour ", "!"], [je.ident("nom")]).to_js(), "`Bonjour ${nom}!`")
    assert_eq(je.new_expr(je.call("f"), []).to_js(), "new (f())()")
    assert_eq(je.conditional(je.ident("ok"), 1, je.conditional(je.ident("b"), 2, 3)).to_js(), "ok ? 1 : b ? 2 : 3")
    assert_eq(je.lit(5).dot("toString").call([]).to_js(), "(5).toString()")
    assert_eq(je.binary("+", je.ident("a"), je.unary("+", je.ident("b"))).to_js(je.compact_style()), "a+ +b")
    assert_eq(je.call("f", [je.sequence([1, 2])]).to_js(), "f((1, 2))")
    assert_raises(() => je.ident("2x"), "JsError")
    assert_raises(() => je.binary("<>", 1, 2), "JsError")

testing.test("expressions", t_expressions)

func t_statements_functions():
    f := jf.function("somme", [jf.param("a"), jf.param("b", 0)], [st.ret(je.ident("a").op("+", je.ident("b")))])
    assert_eq(f.to_js(), "function somme(a, b = 0) {\n  return a + b;\n}")
    assert_eq(f.to_arrow().to_js(), "(a, b = 0) => a + b")
    assert_raises(() => jf.function("f", [jf.rest("r"), "x"]), "JsError")
    c := jf.class_decl("Chien", "Animal")
    c.constructor([jf.param("nom")], [je.raw("super(nom)")])
    c.field("#puces", 0)
    c.method("créer", [], [st.ret(je.new_expr("Chien", ["x"]))], true)
    assert_eq(c.to_js(), "class Chien extends Animal {\n  constructor(nom) {\n    super(nom);\n  }\n\n  #puces = 0;\n\n  static créer() {\n    return new Chien(\"x\");\n  }\n}")
    p := st.Program([
        st.const_decl("items", je.array([1, 2])),
        st.for_of("const", "x", je.ident("items"), [je.log([je.ident("x")])]),
        st.if_stmt(je.ident("a"), [st.ret(je.lit(true))], st.if_stmt(je.ident("b"), [st.ret()], [st.throw_error("non")])),
        st.Switch(je.ident("k"), [(je.lit(1), [st.Break()]), (null, [je.call("autre")])]),
        je.object({"x": 1}),
        jf.iife([je.log(["auto"])], true),
    ])
    out := p.to_js()
    assert_true("for (const x of items) {\n  console.log(x);\n}" in out)
    assert_true("} else if (b) {\n  return;\n} else {\n  throw new Error(\"non\");\n}" in out)
    assert_true("({x: 1});" in out)
    assert_true("(async () => {\n  console.log(\"auto\");\n})();" in out)
    assert_eq(st.Program([st.const_decl("a", 1), st.for_range("i", 0, 3, [st.Continue()])]).to_js(je.compact_style()), "const a=1;for(let i=0;i<3;i++){continue;}")
    assert_eq(st.Program([je.array([1]).method("forEach", [je.ident("f")])]).to_js(je.Style("  ", false)), ";[1].forEach(f)\n")
    assert_raises(() => st.const_decl("x", null), "JsError")
    assert_eq(st.destructure("const", ["a", ("b", "c")], je.ident("o")).to_js(), "const {a, b: c} = o;")

testing.test("instructions, fonctions et classes", t_statements_functions)

func t_objects_arrays():
    assert_eq(jo.freeze({"a": 1}).to_js(), "Object.freeze({a: 1})")
    assert_eq(jo.spread_merge(["a", "b"], {"c": 1}).to_js(), "{...a, ...b, c: 1}")
    assert_eq(jo.key_order({"b": 1, "10": 2, "2": 3}), ["2", "10", "b"])
    assert_eq(jo.get_path({"a": {"b": [{"c": 5}]}}, "a.b[0].c"), 5)
    assert_eq(jo.get_path({"a": 1}, "a.x.y", "def"), "def")
    assert_eq(jo.set_path({}, "a[1].x", 2), {"a": [null, {"x": 2}]})
    assert_eq(jo.deep_merge({"a": {"x": 1}}, {"a": {"y": 2}}), {"a": {"x": 1, "y": 2}})
    assert_eq(jo.describe({"nom": "Ada", "tags": ["x"], "m": [1, "a"]}), "{nom: string, tags: string[], m: Array<number | string>}")
    assert_eq(ja.from_length(3, "(_, i) => i * 2").to_js(), "Array.from({length: 3}, (_, i) => i * 2)")
    assert_eq(ja.typed("Uint8Array", [1, 255]).to_js(), "new Uint8Array([1, 255])")
    assert_eq(ja.chain("items", [("filter", "(x) => x.ok"), ("map", "(x) => x.nom")]).to_js(), "items.filter((x) => x.ok).map((x) => x.nom)")
    l := [1, 2, 3, 4]
    assert_eq(ja.slice(l, -2), [3, 4])
    assert_eq(ja.splice(l, 1, 2, ["x"]), [2, 3])
    assert_eq(l, [1, "x", 4])
    assert_eq(ja.flat([1, [2, [3, [4]]]], 2), [1, 2, 3, [4]])
    assert_eq(ja.sort_default([10, 9, 1]), [1, 10, 9])
    assert_eq(ja.join([1, null, "b", [2, 3]], "-"), "1--b-2,3")
    assert_true(jt.is_undefined(ja.at([1], 5)))

testing.test("objets et tableaux", t_objects_arrays)

func t_modules():
    assert_eq(ji.import_decl("./util.js", "util", [("format", "fmt"), "parse"]).to_js(), "import util, {format as fmt, parse} from \"./util.js\";")
    assert_eq(ji.import_decl("./d.json", "d", null, {"type": "json"}).to_js(), "import d from \"./d.json\" with {type: \"json\"};")
    src := "import a, * as ns from 'x'\nimport {b as c, default as d} from \"y\";\nimport './side.js'\nconst z = import('lazy')"
    ims := ji.parse_imports(src)
    assert_eq(len(ims), 3)
    assert_eq(ims[1].bindings(), {"c": "b", "d": "default"})
    assert_eq(src[ims[0].start:ims[0].end], "import a, * as ns from 'x'")
    assert_true(ims[2].is_side_effect())
    assert_eq(ji.dependencies("import a from 'a'; const b = require('b'); import('c'); export * from 'd'"), ["a", "b", "c", "d"])
    assert_eq(ji.resolve("../../c.js", "src/lib/a.js"), "c.js")
    assert_eq(ji.resolve_with_map("@ui/button", {"@ui/": "/vendor/ui/"}), "/vendor/ui/button")
    assert_eq(jx.export_all("./x.js", "ns").to_js(), "export * as ns from \"./x.js\";")
    assert_eq(jx.export_declaration(st.const_decl("PI", 3.14)).to_js(), "export const PI = 3.14;")
    ex := jx.parse_exports("export const a = 1, {b, c: d} = o;\nexport default function main() {}\nexport {x as y}\nexport * as ns from './n.js'")
    assert_eq(ex[0].exported(), ["a", "b", "d"])
    assert_eq(ex[1].names, ["main"])
    assert_eq(jx.exported_names("export {x as y}; export class C {}"), ["y", "C"])
    m := jm.Module("main.js")
    m.import_from("./util.js", null, ["double"])
    m.add(je.log([je.call("double", [21])]))
    assert_eq(m.to_js(), "import {double} from \"./util.js\";\nconsole.log(double(21));\n")
    files := {"main.js": "import {double, counter, inc} from './util.js'\nimport hello, * as lib from './lib/index.js'\nimport data from './data.json'\ninc(); inc()\nconsole.log(double(21), counter, `${counter}`, hello(), lib.name, lib.sub, data.x)\nexport default 'fin'",
              "util.js": "export const double = (x) => x * 2\nexport let counter = 0\nexport function inc() { counter++ }",
              "lib/index.js": "export * from './sub.js'\nexport default function hello() { return 'salut' }\nexport const name = 'lib'",
              "lib/sub.js": "export const sub = 1",
              "data.json": "{\"x\": 42}"}
    b := jm.Bundle(files, "main.js")
    assert_eq(b.order(), ["util.js", "lib/sub.js", "lib/index.js", "data.json", "main.js"])
    r := b.build()
    assert_true(val.is_valid(r.code))
    assert_eq(r.map.sources, ["util.js", "lib/sub.js", "lib/index.js", "data.json", "main.js"])
    assert_raises(() => jm.Bundle({"a.js": "import './manque.js'"}, "a.js").build(), "JsError")
    assert_eq(jm.graph({"a.js": "import './b.js'", "b.js": ""}), {"a.js": ["b.js"], "b.js": []})
    if RT != null:
        assert_eq(RT.run(r.code).stdout, "42 2 2 salut lib 1 42\n")
        assert_eq(RT.run(jm.Bundle(files, "main.js", null, null, "esm").build().code + "\nconsole.log(typeof fin)").code, 0)

testing.test("importations, exportations, regroupement", t_modules)

func t_generator_sourcemap():
    w := jg.CodeWriter()
    w.line("function f() {", ("src.al", 0, 0))
    w.indent()
    w.line("return 1;", ("src.al", 1, 4))
    w.dedent()
    w.line("}")
    assert_eq(w.text(), "function f() {\n  return 1;\n}\n")
    assert_eq(w.source_map("out.js").encode_mappings(), "AAAA;EACI")
    assert_eq(sm.encode_vlq([0, 0, 0, 0]), "AAAA")
    assert_eq(sm.decode_vlq("IAAIA"), [4, 0, 0, 4, 0])
    assert_eq(sm.decode_vlq(sm.encode_vlq([-17, 1000, 15])), [-17, 1000, 15])
    m := sm.SourceMap("app.min.js")
    s := m.add_source("app.js", "let x = 1;")
    m.add(0, 0, s, 0, 0)
    m.add(0, 4, s, 0, 4, "x")
    m2 := sm.parse(m.to_json())
    assert_eq(m2.original_position(0, 5), {"source": "app.js", "line": 0, "column": 4, "name": "x"})
    assert_eq(sm.find_url("x\n//# sourceMappingURL=a.map\n"), "a.map")
    assert_true(sm.inline_comment(m)[0:50] == "//# sourceMappingURL=data:application/json;charset")
    r := jg.concat([("a.js", "let a = 1;\nlet a2 = 3;"), ("b.js", "let b = 2;\n")], "bundle.js")
    assert_eq(r.code, "let a = 1;\nlet a2 = 3;\nlet b = 2;\n")
    assert_eq(r.map.original_position(2, 0)["source"], "b.js")
    assert_eq(jg.generate([st.const_decl("x", 1), je.log([je.ident("x")])]), "const x = 1;\nconsole.log(x);\n")

testing.test("génération et cartes de sources", t_generator_sourcemap)

func t_validator():
    kinds := []
    for t in val.tokenize("const r = a / b + /ab+c/gi.test(s); x?.y ?? .5; #p in o; `a${ {b: `c${d}`}.b }`"):
        append(kinds, t.kind)
    assert_eq(kinds[4], "punct")
    assert_eq(kinds[7], "regex")
    assert_true("template" in kinds)
    assert_true("private" in kinds)
    r := val.validate("let a = 1;\nlet a = 2;\nel.innerHTML = saisie;\nif (a == 2 {\n eval('x'); setTimeout(\"f()\", 1)\nconst let = 3\nreturn\n  42\n'non fermée\n")
    codes := r.codes()
    for c in ["redeclaration", "security-innerhtml", "security-eval", "reserved-word", "return-newline", "lexical", "unbalanced"]:
        assert_true(c in codes)
    assert_false(r.is_valid())
    assert_true(val.is_valid("x => x * 2"))
    assert_true(val.is_valid("function f() { return `a${b}` }"))
    assert_false(val.is_valid("a = [1, 2"))
    assert_eq(val.free_identifiers("const a = 1; function f(x, y) { return x + y + a + z }"), ["z"])
    assert_true("asi-hazard" in val.validate("let b = a\n(function(){})()").codes())
    assert_raises(() => val.tokenize("'abc", false, true), "JsSyntaxError")

testing.test("analyse lexicale et validation", t_validator)

func t_format_minify():
    assert_eq(fmt.format("function f(a,b){if(a>b){return a}else{return b}}"), "function f(a, b) {\n  if (a > b) {\n    return a\n  } else {\n    return b\n  }\n}\n")
    src := "import {a,b} from './x.js';\nconst o={a:1,b:[1,2,3]};let x=a?b:-c;\n\n\nfor(let i=0;i<10;i++){console.log(i,!x)}\nswitch(k){case 1:a();break;default:b()}\nconst f=async (x)=>{await g(x);return x*2}; // fin\nlabel: for(;;){break label}"
    out := fmt.format(src)
    assert_true("import { a, b } from './x.js';\nconst o = { a: 1, b: [1, 2, 3] };\nlet x = a ? b : -c;\n\nfor (let i = 0; i < 10; i++) {" in out)
    assert_true("switch (k) {\n  case 1:\n    a();\n    break;\n  default:\n    b()\n}" in out)
    assert_true("}; // fin" in out)
    assert_true(fmt.is_formatted(out))
    assert_eq(mini.minify("function f ( a , b ) {\n  // somme\n  return a + b ;\n}"), "function f(a,b){return a+b;}")
    assert_eq(mini.minify("let a = 1\nlet b = a\n(b)"), "let a=1\nlet b=a\n(b)")
    assert_eq(mini.minify("/*! MIT */\nconst x = a + +b - -c + 1.50 + 0.5;\nreturn 0.25\nfoo\n++bar"), "/*! MIT */\nconst x=a+ +b- -c+1.5+.5;return .25\nfoo\n++bar")
    assert_eq(mini.shorten_number("0.50"), ".5")
    assert_eq(mini.shorten_number("0x10"), "0x10")
    assert_true(mini.minify_report("var   x   =   1 ;").ratio < 0.6)
    if RT != null:
        assert_eq(RT.check_syntax(out)[0], true)
        prog := "const o = {a: 1, b: [1, 2]}; let s = 0; for (const k of Object.keys(o)) { s += k.length } console.log(s, `${o.b.length}`, /a+/.test('caa') ? 1 : 2)"
        assert_eq(RT.run(mini.minify(fmt.format(prog))).stdout, RT.run(prog).stdout)

testing.test("mise en forme et minification", t_format_minify)

func t_bridge_runtime():
    assert_eq(jb.json_for_script({"html": "</script><b>&"}), "{\"html\":\"\\u003c/script\\u003e\\u003cb\\u003e\\u0026\"}")
    assert_eq(jb.data_script({"u": "Ada"}, "d"), "<script type=\"application/json\" id=\"d\">{\"u\":\"Ada\"}</script>")
    assert_eq(jb.assign_global("APP.config", {"debug": false}), "window.APP = window.APP || {}; window.APP.config = {debug: false};")
    assert_eq(jb.to_js({"q": jb.Date("2026-10-29T10:00:00Z"), "s": jb.Set([1]), "n": jb.BigInt(10), "b": jb.Bytes("é")}), "{q: new Date(\"2026-10-29T10:00:00Z\"), s: new Set([1]), n: 10n, b: new Uint8Array([195, 169])}")
    assert_eq(jb.inline_script("x('</script>')", "n1"), "<script nonce=\"n1\">x('<\\/script>')</script>")
    assert_eq(jb.csp_hash("console.log('ok')"), "'sha256-z45zR03J8fjhB+XZI75tfFNuEulXqY6Qn0ZMYwFwVws='")
    if RT == null:
        print("  (aucun moteur JavaScript : essais d'exécution ignorés)")
        return
    assert_eq(RT.evaluate("[1, 2, 3].map(x => x * 2)"), [2, 4, 6])
    assert_eq(RT.call("(a, b) => a + b", [20, 22]), 42)
    assert_eq(RT.call("async (u) => (await Promise.resolve(u)).toUpperCase()", ["ada"]), "ADA")
    assert_eq(RT.call("(o) => o.s + o.l.length", [{"s": "</script>\"'", "l": [1, null]}]), "</script>\"'2")
    assert_eq(RT.execute("const [a] = __a; return {n: a.length}", [["x", "y"]]), {"n": 2})
    assert_raises(() => RT.evaluate("null.x"), "JsRuntimeError")
    assert_raises(() => RT.call("() => { while (true) {} }", [], 2), "JsRuntimeError")
    assert_false(RT.check_syntax("let = ;")[0])

testing.test("pont de données et exécution", t_bridge_runtime)

func t_interop():
    reg := rpc.Registry()
    reg.register("somme", (a, b) => a + b, ["a", "b"], null, {"b": 0})
    reg.register("user.saluer", (nom) => "Bonjour " + nom, ["nom"], "Salue")
    reg.register("refus", () => rpc.rpc_error("refusé", 403))
    assert_eq(reg.handle_text("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"somme\",\"params\":[20,22]}"), "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":42}")
    assert_eq(reg.handle(rpc.request("somme", {"a": 1}))["result"], 1)
    assert_eq(reg.handle(rpc.request("inconnue"))["error"]["code"], -32601)
    assert_eq(reg.handle(rpc.request("somme", [1, 2, 3]))["error"]["code"], -32602)
    assert_eq(reg.handle(rpc.request("refus"))["error"], {"code": 403, "message": "refusé"})
    assert_eq(reg.handle_text("{bad")[0:60], "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":")
    assert_eq(reg.handle_text("{\"jsonrpc\":\"2.0\",\"method\":\"somme\",\"params\":[1]}"), "")
    batch := reg.handle([rpc.request("somme", [1, 1], 1), rpc.notification("somme", [1]), rpc.request("user.saluer", ["Ada"], 2)])
    assert_eq(len(batch), 2)
    assert_eq(batch[1]["result"], "Bonjour Ada")
    router := rd.Router()
    reg.mount(router, "/rpc")
    req := hreq.Request("POST", "/rpc", null, "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"somme\",\"params\":[2,3]}")
    resp := router.dispatch(req)
    assert_eq(resp.status, 200)
    assert_eq(resp.body, "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":5}")
    client := reg.client_js("/rpc")
    assert_true("export async function somme(a, b) {" in client)
    assert_true("export const user = Object.freeze({" in client)
    assert_true(val.is_valid(client))
    assert_true("export declare function somme(a: unknown, b?: unknown): Promise<unknown>;" in reg.typescript())
    if RT != null:
        # le client généré, avec un fetch simulé qui appelle le registre via un tableau de réponses préparé
        mock := "globalThis.fetch = async (url, init) => ({ status: 200, json: async () => ({ jsonrpc: '2.0', id: 1, result: JSON.parse(init.body).params.reduce((a, b) => a + b, 0) }) });\n"
        code := mock + _s_replace(client, "export ", "") + "\nconsole.log(await somme(2, 3), await user.saluer(1))"
        assert_eq(RT.run(code).stdout, "5 1\n")

func _s_replace(t, a, b):
    out := t
    while a in out:
        i := 0
        while out[i:i + len(a)] != a:
            i += 1
        out = out[0:i] + b + out[i + len(a):len(out)]
    return out

testing.test("JSON-RPC et client généré", t_interop)

func t_entry():
    assert_eq(js.to_js({"a": [1, js.UNDEFINED]}), "{a: [1, undefined]}")
    assert_eq(js.from_js("{a: 1, b: [2,],}"), {"a": 1, "b": [2]})
    assert_true("security-eval" in js.validate("eval(x)").codes())
    assert_eq(js.format("if(a){b()}"), "if (a) {\n  b()\n}\n")
    assert_eq(js.minify("let x = 1 ;  // c"), "let x=1;")
    r := js.bundle({"a.js": "import {b} from './b.js'; console.log(b)", "b.js": "export const b = 1"}, "a.js")
    assert_true(js.is_valid(r.code))
    assert_eq(js.generate(js.program([js.call("f", [1])])), "f(1);\n")
    if RT != null:
        assert_eq(RT.run(r.code).stdout, "1\n")
        assert_eq(js.evaluate("1 + 1"), 2)

testing.test("point d'entrée web.js", t_entry)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) web.js en échec")
print("web.js : OK")
