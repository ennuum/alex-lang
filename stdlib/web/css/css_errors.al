# ALEX STANDARD LIBRARY — web.css.css_errors
#
# Erreurs du paquet web.css, et Issue : un problème non bloquant relevé par l'analyseur (récupération d'erreur,
# comme un navigateur) ou par le validateur (web.css.css_validate).
#
#   CssError            usage invalide de l'API
#   CssParseError       feuille de style mal formée, en analyse stricte
#   CssSelectorError    sélecteur invalide
#   CssValueError       valeur invalide (couleur, longueur, fonction...)
#   CssValidationError  feuille non conforme (css_validate.check)
#
#   use web.css.css_errors as ce
#   try:
#       c := color.parse("#ggg")
#   catch e:
#       print(ce.explain(e.type), e.message)

from core use len, type

const CSS := "CssError"
const PARSE := "CssParseError"
const SELECTOR := "CssSelectorError"
const VALUE := "CssValueError"
const VALIDATION := "CssValidationError"

const ERROR := "error"
const WARNING := "warning"
const INFO := "info"

func kinds():
    return [CSS, PARSE, SELECTOR, VALUE, VALIDATION]

func is_css_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func explain(error_type):
    if error_type == CSS:
        return "usage invalide de l'API CSS"
    if error_type == PARSE:
        return "feuille de style mal formée"
    if error_type == SELECTOR:
        return "sélecteur CSS invalide"
    if error_type == VALUE:
        return "valeur CSS invalide"
    if error_type == VALIDATION:
        return "feuille de style non conforme"
    return "erreur " + str(error_type)

func css_error(fn, message):
    raise(CSS, fn + " : " + message)

func parse_error(fn, message):
    raise(PARSE, fn + " : " + message)

func selector_error(fn, message):
    raise(SELECTOR, fn + " : " + message)

func value_error(fn, message):
    raise(VALUE, fn + " : " + message)

func validation_error(fn, message):
    raise(VALIDATION, fn + " : " + message)

# Problème relevé : niveau (error, warning, info), code stable, message, emplacement (sélecteur, ligne).
class Issue:
    func init(level, code, message, where=null, line=null):
        self.level = level
        self.code = code
        self.message = message
        self.where = where
        self.line = line

    func is_error():
        return self.level == ERROR

    func __str__():
        out := self.level + " [" + self.code + "] " + self.message
        if self.where != null:
            out = out + " (" + str(self.where) + ")"
        if self.line != null:
            out = out + " ligne " + str(self.line)
        return out

    func to_dict():
        return {"level": self.level, "code": self.code, "message": self.message, "where": self.where, "line": self.line}

func count_errors(issues):
    n := 0
    for i in issues:
        if i.level == ERROR:
            n += 1
    return n
