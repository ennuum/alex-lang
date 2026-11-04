# ALEX STANDARD LIBRARY — office.errors
# Types d'erreur de la bibliothèque bureautique et utilitaires pour les lever, les vérifier et les traduire.
#
#   use office.errors as errors
#   errors.fail(errors.PDF, "objet 12 introuvable")          # raise("PDFError", "objet 12 introuvable")
#   errors.check(n > 0, errors.XLSX, "feuille vide")
#   try:
#       ...
#   catch e:
#       if errors.is_office_error(e):
#           print(errors.describe(e))                         # « PDFError: objet 12 introuvable »
#
# fail(kind, message)  check(cond, kind, message)  check_type(v, attendu, où, libellé)  is_office_error(e)
# describe(e)  rethrow(e, kind, contexte)  ignore(e) (erreur volontairement ignorée)  kinds()
#
# FAMILLES (valeur de e.type)
#   OfficeError       erreur générique de la bibliothèque
#   FormatError       format non reconnu, fichier qui n'est pas du type annoncé
#   ArchiveError      archive ZIP invalide, entrée absente, CRC faux, chiffrement non pris en charge
#   CompressionError  flux DEFLATE / zlib / gzip invalide
#   XMLError          XML mal formé (message avec « ligne L, colonne C »)
#   PDFError          PDF illisible ou opération PDF impossible
#   DOCXError XLSXError PPTXError ODFError   erreurs propres à chaque format
#   FormulaError      formule de tableur mal écrite (les erreurs de CALCUL sont des valeurs : #DIV/0!, #N/A...)
#   TemplateError     gabarit mal formé
#   ConversionError   conversion impossible entre deux formats
#   UnsupportedError  fonctionnalité volontairement non prise en charge (chiffrement, macros...)
# Les erreurs de programmation gardent les types standard : TypeError (mauvais type d'argument), ValueError
# (valeur hors domaine), KeyError, IndexError, IoError.

from core use type
from collections use append

const OFFICE := "OfficeError"
const FORMAT := "FormatError"
const ARCHIVE := "ArchiveError"
const COMPRESSION := "CompressionError"
const XML := "XMLError"
const PDF := "PDFError"
const DOCX := "DOCXError"
const XLSX := "XLSXError"
const PPTX := "PPTXError"
const ODF := "ODFError"
const FORMULA := "FormulaError"
const TEMPLATE := "TemplateError"
const CONVERSION := "ConversionError"
const UNSUPPORTED := "UnsupportedError"

const _KINDS := ["OfficeError", "FormatError", "ArchiveError", "CompressionError", "XMLError", "PDFError", "DOCXError", "XLSXError", "PPTXError", "ODFError", "FormulaError", "TemplateError", "ConversionError", "UnsupportedError"]

# Liste de tous les types d'erreur de la bibliothèque.
func kinds():
    out := []
    for k in _KINDS:
        append(out, k)
    return out

# Lève une erreur `kind` avec `message`.
func fail(kind, message):
    raise(kind, message)

# Lève `kind` si `condition` est fausse.
func check(condition, kind, message):
    if not condition:
        raise(kind, message)

# TypeError si type(value) n'est pas l'un des noms de `expected` (str ou liste de str).
#   errors.check_type(path, "str", "word.open", "path")
func check_type(value, expected, where, label):
    t := type(value)
    names := expected
    if type(expected) == "str":
        names = [expected]
    for n in names:
        if n == t:
            return value
        if n == "number" and (t == "int" or t == "float"):
            return value
        if n == "bytes" and t == "list":
            return value
        if n == "sequence" and (t == "list" or t == "tuple"):
            return value
    shown := ""
    i := 0
    for n in names:
        if i > 0:
            shown = shown + " ou "
        shown = shown + n
        i = i + 1
    raise("TypeError", where + " : " + label + " doit être " + shown + " (obtenu '" + t + "')")

# Vrai si l'erreur interceptée appartient à la bibliothèque.
func is_office_error(e):
    for k in _KINDS:
        if e.type == k:
            return true
    return false

# « Type: message ».
func describe(e):
    return e.type + ": " + e.message

# Relance `e` en la traduisant : les erreurs de données des primitives (ValueError, ArgumentError) deviennent
# `kind` avec le préfixe `context` ; les erreurs de la bibliothèque et les autres erreurs sont relancées telles
# quelles (une erreur de programmation ne doit pas être maquillée).
func rethrow(e, kind, context):
    if e.type == "ValueError" or e.type == "ArgumentError":
        raise(kind, context + " : " + e.message)
    raise(e)

# Ignore volontairement une erreur interceptée (élément facultatif illisible : on continue sans lui).
func ignore(e):
    return null
