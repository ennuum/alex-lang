# ALEX STANDARD LIBRARY — web.js.js_errors
#
# Erreurs du paquet web.js, et Issue : un problème relevé par le validateur (web.js.js_validator) avec sa
# position (ligne, colonne).
#
#   JsError          usage invalide de l'API
#   JsSyntaxError    source JavaScript mal formée (analyse lexicale, import / export, valeur littérale)
#   JsValueError     valeur ALEX non convertible en JavaScript (ou l'inverse)
#   JsRuntimeError   échec d'exécution dans un moteur externe (node, bun, deno), avec la pile JS
#   JsBridgeError    appel RPC invalide (méthode inconnue, paramètres), moteur introuvable
#
#   use web.js.js_errors as je
#   try:
#       v := js_value.from_js("{a: }")
#   catch e:
#       print(je.explain(e.type), e.message)

from core use len, type

const JS := "JsError"
const SYNTAX := "JsSyntaxError"
const VALUE := "JsValueError"
const RUNTIME := "JsRuntimeError"
const BRIDGE := "JsBridgeError"

const ERROR := "error"
const WARNING := "warning"
const INFO := "info"

func kinds():
    return [JS, SYNTAX, VALUE, RUNTIME, BRIDGE]

func is_js_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func explain(error_type):
    if error_type == JS:
        return "usage invalide de l'API JavaScript"
    if error_type == SYNTAX:
        return "source JavaScript mal formée"
    if error_type == VALUE:
        return "valeur non convertible"
    if error_type == RUNTIME:
        return "erreur d'exécution JavaScript"
    if error_type == BRIDGE:
        return "erreur de pont ALEX ↔ JavaScript"
    return "erreur " + str(error_type)

func js_error(fn, message):
    raise(JS, fn + " : " + message)

func syntax_error(fn, message, line=null, column=null):
    where := ""
    if line != null:
        where = " (ligne " + str(line) + (", colonne " + str(column) if column != null else "") + ")"
    raise(SYNTAX, fn + " : " + message + where)

func value_error(fn, message):
    raise(VALUE, fn + " : " + message)

func runtime_error(fn, message):
    raise(RUNTIME, fn + " : " + message)

func bridge_error(fn, message):
    raise(BRIDGE, fn + " : " + message)

# Problème relevé : niveau (error, warning, info), code stable, message, ligne et colonne (à partir de 1).
class Issue:
    func init(level, code, message, line=null, column=null):
        self.level = level
        self.code = code
        self.message = message
        self.line = line
        self.column = column

    func is_error():
        return self.level == ERROR

    func __str__():
        out := self.level + " [" + self.code + "] " + self.message
        if self.line != null:
            out = out + " ligne " + str(self.line)
            if self.column != null:
                out = out + ":" + str(self.column)
        return out

    func to_dict():
        return {"level": self.level, "code": self.code, "message": self.message, "line": self.line, "column": self.column}

func count_errors(issues):
    n := 0
    for i in issues:
        if i.level == ERROR:
            n += 1
    return n
