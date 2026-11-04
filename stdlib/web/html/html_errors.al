# ALEX STANDARD LIBRARY — web.html.html_errors
#
# Erreurs du paquet web.html, et Issue : un problème non bloquant relevé par l'analyseur (mode tolérant) ou par
# le validateur (web.html.html_validate).
#
#   HtmlError            usage invalide de l'API (nœud inattendu, enfant d'un élément vide...)
#   HtmlParseError       document mal formé, en analyse stricte (html_parser.parse(texte, true))
#   HtmlAttributeError   nom d'attribut invalide (espace, guillemet, « = », « > »...)
#   HtmlTagError         nom de balise invalide
#   HtmlValidationError  document invalide (html_validate.check)
#
#   use web.html.html_errors as he
#   try:
#       doc := parser.parse(texte, true)
#   catch e:
#       print(he.explain(e.type), e.message)

from core use len, type

const HTML := "HtmlError"
const PARSE := "HtmlParseError"
const ATTRIBUTE := "HtmlAttributeError"
const TAG := "HtmlTagError"
const VALIDATION := "HtmlValidationError"

const ERROR := "error"
const WARNING := "warning"
const INFO := "info"

func kinds():
    return [HTML, PARSE, ATTRIBUTE, TAG, VALIDATION]

func is_html_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func explain(error_type):
    if error_type == HTML:
        return "usage invalide de l'API HTML"
    if error_type == PARSE:
        return "document HTML mal formé"
    if error_type == ATTRIBUTE:
        return "nom d'attribut HTML invalide"
    if error_type == TAG:
        return "nom de balise HTML invalide"
    if error_type == VALIDATION:
        return "document HTML non conforme"
    return "erreur " + str(error_type)

func html_error(fn, message):
    raise(HTML, fn + " : " + message)

func parse_error(fn, message):
    raise(PARSE, fn + " : " + message)

func attribute_error(fn, message):
    raise(ATTRIBUTE, fn + " : " + message)

func tag_error(fn, message):
    raise(TAG, fn + " : " + message)

func validation_error(fn, message):
    raise(VALIDATION, fn + " : " + message)

# Problème relevé : niveau (error, warning, info), code stable (« img-alt »), message, emplacement.
class Issue:
    func init(level, code, message, where=null, line=null):
        self.level = level
        self.code = code
        self.message = message
        self.where = where      # chemin de l'élément (« html > body > img:nth(2) ») ou null
        self.line = line        # ligne du source (analyseur), ou null

    func is_error():
        return self.level == ERROR

    func __str__():
        out := self.level + " [" + self.code + "] " + self.message
        if self.where != null:
            out = out + " (" + self.where + ")"
        if self.line != null:
            out = out + " ligne " + str(self.line)
        return out

    func to_dict():
        return {"level": self.level, "code": self.code, "message": self.message, "where": self.where, "line": self.line}

func error_issue(code, message, where=null, line=null):
    return Issue(ERROR, code, message, where, line)

func warning_issue(code, message, where=null, line=null):
    return Issue(WARNING, code, message, where, line)

func info_issue(code, message, where=null, line=null):
    return Issue(INFO, code, message, where, line)

func count_errors(issues):
    n := 0
    for i in issues:
        if i.level == ERROR:
            n += 1
    return n
