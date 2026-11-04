# ALEX STANDARD LIBRARY — web.js
#
# Point d'entrée du paquet web.js : produire, analyser, valider, mettre en forme, minifier, regrouper et
# exécuter du JavaScript depuis ALEX, et relier une page web à des fonctions ALEX.
#
# | Module                                      | Rôle                                                       |
# |---------------------------------------------|------------------------------------------------------------|
# | web.js (ce module)                          | raccourcis : to_js, from_js, validate, format, minify, bundle |
# | web.js.js_types / js_value                  | lexique, chaînes, nombres, undefined ; valeurs ALEX <-> JS  |
# | web.js.js_expression / js_statement / js_function | AST : expressions, instructions, fonctions, classes  |
# | web.js.js_object / js_array                 | littéraux, Object.* / Array.*, sémantique JS sur dict / list |
# | web.js.js_import / js_export / js_module    | modules ES : construction, analyse, graphe, regroupement   |
# | web.js.js_generator / js_source_map         | génération indentée avec positions, cartes de sources v3   |
# | web.js.js_validator / js_formatter / js_minifier | jetons, validation et sécurité, mise en forme, minification |
# | web.js.js_bridge                            | données ALEX dans une page (JSON sûr, globales, CSP)       |
# | web.js.js_runtime_bridge                    | exécution dans node / bun / deno, valeurs en retour       |
# | web.js.js_interop                           | JSON-RPC 2.0 : registre, serveur, client JS généré         |
# | web.js.js_errors                            | erreurs et Issue                                           |
#
#   use web.js as js
#   js.to_js({"nom": "Ada", "tags": ["x"]})          # {nom: "Ada", tags: ["x"]}
#   js.from_js("{a: 1, b: [2,],}")                   # {"a": 1, "b": [2]}
#   js.validate("eval(x)").warnings()                # [security-eval …]
#   js.format("if(a){b()}")                          # if (a) {\n  b()\n}\n
#   js.minify("let x = 1 ;  // c")                   # let x=1;
#   js.bundle({"a.js": "import {b} from './b.js'; console.log(b)", "b.js": "export const b = 1"}, "a.js").code
#   js.evaluate("1 + 1")                             # 2 (si node, bun ou deno est installé)
#
# Erreurs : JsError, JsSyntaxError, JsValueError, JsRuntimeError, JsBridgeError.

from core use len, type
use web.js.js_errors as _err
use web.js.js_types as _t
use web.js.js_value as _jv
use web.js.js_expression as _e
use web.js.js_statement as _st
use web.js.js_function as _fn
use web.js.js_validator as _val
use web.js.js_formatter as _fmt
use web.js.js_minifier as _mini
use web.js.js_module as _mod
use web.js.js_generator as _gen
use web.js.js_bridge as _bridge
use web.js.js_runtime_bridge as _rt

const UNDEFINED := _t.UNDEFINED

func to_js(value, indent=null):
    return _jv.to_js(value, indent)

func from_js(text):
    return _jv.from_js(text)

func raw(code):
    return _jv.Raw(code)

func quote(text):
    return _t.quote(text)

func is_identifier(name):
    return _t.is_identifier(name)

# ---------------------------------------------------------------- AST

func ident(name):
    return _e.ident(name)

func lit(value):
    return _e.lit(value)

func expr(value):
    return _e.expr(value)

func call(callee, args=null):
    return _e.call(callee, args)

func program(body=null):
    return _st.Program(body)

func function(name=null, params=null, body=null, is_async=false):
    return _fn.function(name, params, body, is_async)

func generate(node, style=null):
    return _gen.generate(node, style)

# ---------------------------------------------------------------- outils

func tokenize(source, keep_comments=false):
    return _val.tokenize(source, keep_comments)

func validate(source, opts=null):
    return _val.validate(source, opts)

func is_valid(source):
    return _val.is_valid(source)

func format(source, indent="  "):
    return _fmt.format(source, _fmt.Options(indent))

func minify(source):
    return _mini.minify(source)

func bundle(files, entry, format_name="iife", externals=null):
    return _mod.bundle(files, entry, format_name, externals)

func json_for_script(value):
    return _bridge.json_for_script(value)

func data_script(value, id):
    return _bridge.data_script(value, id)

# ---------------------------------------------------------------- exécution

func runtime(prefer=null):
    return _rt.find_runtime(prefer)

func evaluate(expression, timeout=30):
    return _rt.evaluate(expression, timeout)

func call_js(function_source, args=null, timeout=30):
    return _rt.call(function_source, args, timeout)
