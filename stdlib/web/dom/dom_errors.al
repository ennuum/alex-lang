# ALEX STANDARD LIBRARY — web.dom.dom_errors
#
# Exceptions DOM (DOMException) : chaque erreur porte comme type le NOM standard de l'exception
# (HierarchyRequestError, NotFoundError…), son code historique et un message en français.
#
#   use web.dom.dom_errors as de
#   try:
#       parent.remove_child(etranger)
#   catch e:
#       e.type                       # NotFoundError
#       de.code_of(e.type)           # 8
#       de.is_dom_error(e.type)      # true
#
#   DomError                 usage invalide de l'API ALEX (argument de mauvais type…)
#   HierarchyRequestError    insertion qui rendrait l'arbre invalide (un nœud dans son propre descendant…)
#   NotFoundError            nœud absent de l'emplacement attendu
#   InvalidCharacterError    nom (balise, attribut) invalide
#   SyntaxError              sélecteur CSS ou valeur invalide
#   InvalidStateError        objet dans un état incompatible (événement déjà distribué…)
#   NotSupportedError        opération non prise en charge
#   IndexSizeError           indice ou longueur hors limites
#   InUseAttributeError      attribut déjà rattaché à un autre élément
#   NamespaceError           espace de noms incohérent
#   AbortError, TimeoutError opération interrompue / délai dépassé

from core use len, type

const DOM := "DomError"
const HIERARCHY := "HierarchyRequestError"
const NOT_FOUND := "NotFoundError"
const INVALID_CHARACTER := "InvalidCharacterError"
const SYNTAX := "SyntaxError"
const INVALID_STATE := "InvalidStateError"
const NOT_SUPPORTED := "NotSupportedError"
const INDEX_SIZE := "IndexSizeError"
const IN_USE_ATTRIBUTE := "InUseAttributeError"
const NAMESPACE := "NamespaceError"
const WRONG_DOCUMENT := "WrongDocumentError"
const ABORT := "AbortError"
const TIMEOUT := "TimeoutError"

const _CODES := {"IndexSizeError": 1, "HierarchyRequestError": 3, "WrongDocumentError": 4, "InvalidCharacterError": 5, "NotFoundError": 8, "NotSupportedError": 9, "InUseAttributeError": 10, "InvalidStateError": 11, "SyntaxError": 12, "NamespaceError": 14, "AbortError": 20, "TimeoutError": 23}

func kinds():
    return [DOM, HIERARCHY, NOT_FOUND, INVALID_CHARACTER, SYNTAX, INVALID_STATE, NOT_SUPPORTED, INDEX_SIZE, IN_USE_ATTRIBUTE, NAMESPACE, WRONG_DOCUMENT, ABORT, TIMEOUT]

func is_dom_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

# Code numérique historique (DOMException.code), 0 s'il n'y en a pas.
func code_of(name):
    if name in _CODES:
        return _CODES[name]
    return 0

func explain(name):
    if name == HIERARCHY:
        return "insertion invalide dans l'arbre"
    if name == NOT_FOUND:
        return "nœud introuvable"
    if name == INVALID_CHARACTER:
        return "nom contenant un caractère invalide"
    if name == SYNTAX:
        return "syntaxe invalide"
    if name == INVALID_STATE:
        return "état invalide"
    if name == NOT_SUPPORTED:
        return "opération non prise en charge"
    if name == INDEX_SIZE:
        return "indice hors limites"
    if name == IN_USE_ATTRIBUTE:
        return "attribut déjà utilisé"
    if name == ABORT:
        return "opération interrompue"
    if name == TIMEOUT:
        return "délai dépassé"
    return "erreur DOM"

func fail(name, fn, message):
    raise(name, fn + " : " + message)

func dom_error(fn, message):
    raise(DOM, fn + " : " + message)

func hierarchy(fn, message):
    raise(HIERARCHY, fn + " : " + message)

func not_found(fn, message):
    raise(NOT_FOUND, fn + " : " + message)

func invalid_character(fn, message):
    raise(INVALID_CHARACTER, fn + " : " + message)

func syntax(fn, message):
    raise(SYNTAX, fn + " : " + message)

func invalid_state(fn, message):
    raise(INVALID_STATE, fn + " : " + message)

func not_supported(fn, message):
    raise(NOT_SUPPORTED, fn + " : " + message)

func index_size(fn, message):
    raise(INDEX_SIZE, fn + " : " + message)

func in_use_attribute(fn, message):
    raise(IN_USE_ATTRIBUTE, fn + " : " + message)
