# web.js — JavaScript depuis ALEX

`web.js` permet à un programme ALEX de **produire**, **analyser**, **valider**, **mettre en forme**,
**minifier**, **regrouper** et **exécuter** du JavaScript, et de relier une page web à des fonctions ALEX par
JSON-RPC. Tout est écrit en ALEX ; l'exécution (facultative) passe par un moteur installé : Node.js, Bun ou
Deno.

## Architecture

```text
stdlib/web/js/
├── js.al                 point d'entrée : to_js, from_js, validate, format, minify, bundle, evaluate…
├── js_types.al           mots réservés, identifiants, chaînes et nombres JS, undefined, typeof
├── js_value.al           valeurs ALEX -> littéraux JS ; lecture tolérante de littéraux JS (JSON5 et plus)
├── js_expression.al      AST des expressions, parenthèses minimales (priorités ECMAScript), Style
├── js_statement.al       AST des instructions : déclarations, if, boucles, switch, try, programme, ASI
├── js_function.al        fonctions (async, générateurs, paramètres), classes (champs #privés, static)
├── js_object.al          littéraux objets, Object.*, ordre des clés JS, chemins a.b[0], fusion profonde
├── js_array.al           tableaux, Array.from, tableaux typés, sémantique slice / splice / sort de JS
├── js_import.al          importations : construction, analyse avec positions, dépendances, résolution
├── js_export.al          exportations : construction, analyse avec positions et noms
├── js_module.al          Module, graphe, Bundle (iife / cjs / esm, liaisons vivantes, import() dynamique)
├── js_generator.al       CodeWriter (positions suivies), generate(), concaténation avec carte de sources
├── js_source_map.al      cartes de sources v3 : VLQ, construction, lecture, recherche, composition
├── js_validator.al       analyseur lexical complet ES2024 et validation (syntaxe, sécurité, ASI, style)
├── js_formatter.al       mise en forme par jetons (indentation, espaces, lignes vides)
├── js_minifier.al        minification par jetons (sauts de ligne ASI gardés, licences « /*! » gardées)
├── js_bridge.al          données ALEX dans une page : JSON sûr dans <script>, globales, Date/Map/Set, CSP
├── js_runtime_bridge.al  exécution dans node / bun / deno, évaluation avec retour de valeur
├── js_interop.al         JSON-RPC 2.0 : registre, montage sur web.server, client JS et .d.ts générés
├── js_errors.al          JsError, JsSyntaxError, JsValueError, JsRuntimeError, JsBridgeError, Issue
└── README.md
```

## Produire du JavaScript

Valeurs ALEX directement :

```al
use web.js as js
print(js.to_js({"nom": "Ada", "data-x": [1, 2.5, true, null], "rappel": js.raw("() => 42")}))
# {nom: "Ada", "data-x": [1, 2.5, true, null], rappel: () => 42}
```

AST, avec les parenthèses exactement nécessaires :

```al
use web.js.js_expression as je
use web.js.js_statement as st
use web.js.js_function as jf

somme := jf.function("somme", [jf.param("a"), jf.param("b", 0)], [st.ret(je.ident("a").op("+", je.ident("b")))])
prog := st.Program([
    st.const_decl("items", je.array([1, 2, 3])),
    st.for_of("const", "x", je.ident("items"), [je.log([je.call("somme", [je.ident("x"), 1])])]),
    somme,
])
print(prog.to_js())                    # lisible, indenté
print(prog.to_js(je.compact_style()))  # compact
```

## Analyser, valider, transformer

```al
r := js.validate("let a = 1;\nlet a = 2;\nel.innerHTML = saisie;")
for i in r.issues:
    print(i)
# error [redeclaration] « a » déjà déclaré ligne 1 ligne 2:5
# warning [security-innerhtml] affectation de innerHTML : risque d'injection (XSS) …

print(js.format("function f(a,b){if(a>b){return a}else{return b}}"))
print(js.minify("function f ( a , b ) {\n  // somme\n  return a + b ;\n}"))   # function f(a,b){return a+b;}
```

Le validateur signale : erreurs lexicales (chaînes, gabarits, commentaires, expressions régulières non
fermés), parenthèses déséquilibrées, déclarations `let` / `const` / `class` en double, mots réservés, risques
d'insertion automatique de points-virgules, `return` suivi d'un saut de ligne, et en sécurité : `eval`,
`new Function`, `setTimeout("…")`, `innerHTML` / `outerHTML` / `insertAdjacentHTML`, `document.write`,
URL `javascript:`. Ce n'est pas un analyseur syntaxique complet : pour une vérification exhaustive,
`js_runtime_bridge.Runtime.check_syntax` délègue à `node --check`.

## Regrouper des modules

```al
use web.js.js_module as jm
files := {
    "main.js": "import {double, counter, inc} from './util.js'\ninc()\nconsole.log(double(21), counter)",
    "util.js": "export const double = (x) => x * 2\nexport let counter = 0\nexport function inc() { counter++ }",
}
r := jm.Bundle(files, "main.js").build()
# r.code : script autonome (affiche « 42 1 » : les liaisons d'exportation restent vivantes)
# r.map  : carte de sources (r.map.to_json())
```

Pris en charge : importations par défaut, nommées, espaces de noms, effets de bord ; `export` de
déclarations, de listes, `export default`, réexportations `export … from`, `export * [as ns]` ; `import()`
dynamique littéral ; modules JSON ; dépendances externes vers une expression globale
(`{"react": "window.React"}`) ; cycles. Formats : `iife` (avec nom global facultatif), `cjs`, `esm`.

## Relier une page à ALEX

```al
use web.js.js_interop as rpc
use web.server.request_dispatch as rd

reg := rpc.Registry()
reg.register("somme", (a, b) => a + b, ["a", "b"])
router := rd.Router()
reg.mount(router, "/rpc")
client := reg.client_js("/rpc")      # module ES : export async function somme(a, b) { … }
```

Les données passent du serveur à la page sans risque d'injection avec `js_bridge.json_for_script` et
`js_bridge.data_script` ; `js_bridge.csp_hash` donne l'empreinte d'un script en ligne pour la politique CSP.

## Exécuter

```al
use web.js.js_runtime_bridge as rb
rt := rb.find_runtime()              # node, bun ou deno ; ALEX_JS_RUNTIME pour imposer un chemin
if rt != null:
    print(rt.evaluate("[1, 2, 3].map(x => x * 2)"))      # [2, 4, 6]
    print(rt.call("(a, b) => a + b", [20, 22]))           # 42
```

Chaque exécution est un processus isolé avec un délai maximal ; les arguments sont transmis en JSON, jamais
interpolés dans le code ; une exception JavaScript devient `JsRuntimeError` (message et pile).

## Tests

```sh
make test-web        # comprend tests/web/test_web_js.al (les essais d'exécution sont ignorés sans moteur)
```
