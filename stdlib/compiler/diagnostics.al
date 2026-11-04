# ALEX STANDARD LIBRARY — compiler.diagnostics
#
# Diagnostics du compilateur : erreurs, avertissements et notes, avec position (fichier, ligne, colonne,
# étendue), code (« E0101 », « W0201 »...), notes complémentaires, et un rendu lisible qui cite la ligne fautive
# et la souligne (^~~~), à la manière de rustc / clang.
#
#   use compiler.diagnostics as dg
#   bag := dg.DiagnosticBag("main.al", source)
#   bag.error("E0201", "nom 'x' non défini", 3, 5, 1)
#   bag.warning("W0101", "variable 'tmp' inutilisée", 7, 5, 3).note("préfixer par _ pour l'ignorer")
#   print(bag.render())          # main.al:3:5: erreur[E0201]: nom 'x' non défini
#                                #     3 |     y := x + 1
#                                #       |          ^
#   if bag.has_errors():
#       bag.raise_first()        # lève l'erreur du premier diagnostic (SemanticError, ParseError...)
#
# Les familles de codes : E01xx lexique, E02xx syntaxe, E03xx noms/portées, E04xx types, E05xx IR/édition des
# liens ; W01xx avertissements de style ou de code mort. Le type d'erreur levé dépend de la phase (`phase`).
# Erreurs : LexError, ParseError, SemanticError, TypeError, LinkError (selon la phase du diagnostic).

from core use len, type
from collections use append
use string as _s

const ERROR := "error"
const WARNING := "warning"
const NOTE := "note"
const INFO := "info"

const LEX_ERROR := "LexError"
const PARSE_ERROR := "ParseError"
const SEMANTIC_ERROR := "SemanticError"
const TYPE_ERROR := "TypeError"
const LINK_ERROR := "LinkError"
const IR_ERROR := "IrError"

_LABELS := {"error": "erreur", "warning": "avertissement", "note": "note", "info": "info"}
_RANK := {"error": 0, "warning": 1, "info": 2, "note": 3}

class Diagnostic:
    func init(severity, code, message, file="<source>", line=0, column=0, length=1, phase=null):
        self.severity = severity
        self.code = code
        self.message = message
        self.file = file
        self.line = line
        self.column = column
        self.length = length
        self.phase = phase
        self.notes = []

    func note(text):
        append(self.notes, text)
        return self

    func is_error():
        return self.severity == ERROR

    func location():
        return self.file + ":" + str(self.line) + ":" + str(self.column)

    # Une ligne : « fichier:ligne:col: erreur[CODE]: message ».
    func header():
        lab := self.severity
        if self.severity in _LABELS:
            lab = _LABELS[self.severity]
        c := ""
        if self.code != null and self.code != "":
            c = "[" + self.code + "]"
        return self.location() + ": " + lab + c + ": " + self.message

    # Rendu complet avec la ligne de source et le soulignement.
    func render(source=null):
        out := [self.header()]
        if source != null and self.line > 0:
            lines := _s.split(source, "\n")
            if self.line <= len(lines):
                text := lines[self.line - 1]
                num := str(self.line)
                pad := _s.repeat(" ", len(num))
                append(out, pad + " |")
                append(out, num + " | " + text)
                col := self.column
                if col < 1:
                    col = 1
                n := self.length
                if n < 1:
                    n = 1
                append(out, pad + " | " + _s.repeat(" ", col - 1) + "^" + _s.repeat("~", n - 1))
        for nt in self.notes:
            append(out, "  = note : " + nt)
        return _s.join("\n", out)

    func to_dict():
        return {"severity": self.severity, "code": self.code, "message": self.message, "file": self.file,
                "line": self.line, "column": self.column, "length": self.length, "notes": self.notes}

    func __str__():
        return self.header()

    # Lève l'erreur correspondant à ce diagnostic (type selon la phase).
    func raise_it():
        p := self.phase
        if p == null:
            p = SEMANTIC_ERROR
        raise(p, self.header())

class DiagnosticBag:
    func init(file="<source>", source=null):
        self.file = file
        self.source = source
        self.items = []
        self.max_errors = 100

    func add(d):
        append(self.items, d)
        return d

    func report(severity, code, message, line=0, column=0, length=1, phase=null):
        return self.add(Diagnostic(severity, code, message, self.file, line, column, length, phase))

    func error(code, message, line=0, column=0, length=1, phase=null):
        return self.report(ERROR, code, message, line, column, length, phase)

    func warning(code, message, line=0, column=0, length=1):
        return self.report(WARNING, code, message, line, column, length, null)

    func info(code, message, line=0, column=0):
        return self.report(INFO, code, message, line, column, 1, null)

    func errors():
        return [d for d in self.items if d.severity == ERROR]

    func warnings():
        return [d for d in self.items if d.severity == WARNING]

    func has_errors():
        return len(self.errors()) > 0

    func count():
        return len(self.items)

    func codes():
        return [d.code for d in self.sorted()]

    func extend(other):
        for d in other.items:
            append(self.items, d)
        return self

    # Diagnostics triés : position, puis gravité.
    func sorted():
        out := self.items[:]
        i := 1
        while i < len(out):
            v := out[i]
            j := i - 1
            while j >= 0 and _after(out[j], v):
                out[j + 1] = out[j]
                j -= 1
            out[j + 1] = v
            i += 1
        return out

    func render(with_summary=true):
        parts := [d.render(self.source) for d in self.sorted()]
        if with_summary and len(self.items) > 0:
            append(parts, summary(self.items))
        return _s.join("\n\n", parts)

    func raise_first():
        es := [d for d in self.sorted() if d.severity == ERROR]
        if len(es) > 0:
            es[0].raise_it()

    func to_list():
        return [d.to_dict() for d in self.sorted()]

func _after(a, b):
    if a.file != b.file:
        return a.file > b.file
    if a.line != b.line:
        return a.line > b.line
    if a.column != b.column:
        return a.column > b.column
    return _RANK[a.severity] > _RANK[b.severity]

func summary(items):
    e := 0
    w := 0
    for d in items:
        if d.severity == ERROR:
            e += 1
        elif d.severity == WARNING:
            w += 1
    return str(e) + " erreur(s), " + str(w) + " avertissement(s)"

# Diagnostic à partir d'une erreur ALEX levée par le compilateur natif (« fichier:ligne:col: message »).
func from_error(e, file="<source>"):
    msg := e.message
    line := 0
    col := 0
    parts := _s.split(msg, ":")
    if len(parts) >= 4:
        try:
            line = to_int_safe(_s.trim(parts[1]))
            col = to_int_safe(_s.trim(parts[2]))
            if line > 0:
                file = parts[0]
                msg = _s.trim(_s.join(":", parts[3:]))
        catch err:
            line = 0
    return Diagnostic(ERROR, e.type, msg, file, line, col, 1, e.type)

func to_int_safe(t):
    n := 0
    if len(t) == 0:
        return 0
    for c in t:
        if c < '0' or c > '9':
            return 0
        n = n * 10 + (_s.ord(c) - 48)
    return n
