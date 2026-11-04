# ALEX STANDARD LIBRARY — argparse.text
#
# Utilitaires de texte internes à argparse (pas de tranches ni de regex en ALEX :
# tout passe par substring/ord). Les noms commençant par `_` sont privés.

from core use len, type, to_int, to_float
from collections use append
use string as _s

func char_at(text, i):
    return _s.substring(text, i, i + 1)

# Suffixe de `text` à partir de l'indice `start` (start peut valoir len(text)).
func from_index(text, start):
    if start >= len(text):
        return ""
    return _s.substring(text, start, len(text))

# Préfixe de `text` de `n` caractères (n borné à la longueur).
func head(text, n):
    if n >= len(text):
        return text
    if n <= 0:
        return ""
    return _s.substring(text, 0, n)

func starts_with(text, prefix):
    return _s.starts_with(text, prefix)

func spaces(n):
    if n <= 0:
        return ""
    return _s.repeat(" ", n)

# Complète à droite avec des espaces jusqu'à `width`.
func pad(text, width):
    return text + spaces(width - len(text))

func quote(text):
    return "'" + text + "'"

func join(sep, items):
    return _s.join(sep, items)

# Liste de str : chaque élément passé par str().
func stringify(items):
    out := []
    for x in items:
        append(out, str(x))
    return out

func contains_text(text, part):
    return _s.contains(text, part)

func find_text(text, part):
    return _s.find(text, part)

func replace_all(text, old, new):
    return _s.replace(text, old, new)

func upper(text):
    return _s.upper(text)

func lower(text):
    return _s.lower(text)

# Indice du premier `sep` dans `text`, ou -1.
func index_of(text, sep):
    return _s.find(text, sep)

# [avant, après] autour de la première occurrence de `sep` ; null si absent.
func split_once(text, sep):
    i := _s.find(text, sep)
    if i < 0:
        return null
    return [head(text, i), from_index(text, i + len(sep))]

func is_digit_code(code):
    return code >= 48 and code <= 57

func is_digits(text):
    if len(text) == 0:
        return false
    i := 0
    while i < len(text):
        if not is_digit_code(_s.ord(char_at(text, i))):
            return false
        i = i + 1
    return true

# [+-]?chiffres+ (aucun espace, aucun séparateur).
func is_int_text(text):
    if len(text) == 0:
        return false
    body := text
    c := char_at(text, 0)
    if c == "+" or c == "-":
        body = from_index(text, 1)
    return is_digits(body)

# Décimal Python-like : [+-]? (chiffres [. chiffres*] | . chiffres+) ([eE][+-]?chiffres+)?  ou inf/nan.
func is_float_text(text):
    if len(text) == 0:
        return false
    low := _s.lower(text)
    body := low
    c := char_at(low, 0)
    if c == "+" or c == "-":
        body = from_index(low, 1)
    if body == "inf" or body == "infinity" or body == "nan":
        return true
    mant := body
    exp := null
    e := _s.find(body, "e")
    if e >= 0:
        mant = head(body, e)
        exp = from_index(body, e + 1)
    if exp != null:
        eb := exp
        ec := ""
        if len(exp) > 0:
            ec = char_at(exp, 0)
        if ec == "+" or ec == "-":
            eb = from_index(exp, 1)
        if not is_digits(eb):
            return false
    dot := _s.find(mant, ".")
    if dot < 0:
        return is_digits(mant)
    left := head(mant, dot)
    right := from_index(mant, dot + 1)
    if left == "" and right == "":
        return false
    if left != "" and not is_digits(left):
        return false
    if right != "" and not is_digits(right):
        return false
    return true

# ^-\d+$ | ^-\d*\.\d+$  (ce que argparse considère comme un nombre négatif).
func looks_like_negative_number(text):
    if len(text) < 2 or char_at(text, 0) != "-":
        return false
    body := from_index(text, 1)
    if is_digits(body):
        return true
    dot := _s.find(body, ".")
    if dot < 0:
        return false
    left := head(body, dot)
    right := from_index(body, dot + 1)
    if left != "" and not is_digits(left):
        return false
    return is_digits(right)

# Mots séparés par des blancs (espace, \n, \t, \r) ; jamais de mot vide.
func words(text):
    t := replace_all(replace_all(replace_all(text, "\n", " "), "\t", " "), "\r", " ")
    out := []
    for w in _s.split(t, " "):
        if w != "":
            append(out, w)
    return out

# Retour à la ligne à `width` colonnes (les blancs sont normalisés comme textwrap) ;
# un mot plus long que la largeur n'est jamais coupé. Retourne la liste des lignes.
func wrap(text, width):
    ws := words(text)
    lines := []
    if len(ws) == 0:
        return lines
    cur := ""
    for w in ws:
        if cur == "":
            cur = w
        elif len(cur) + 1 + len(w) <= width:
            cur = cur + " " + w
        else:
            append(lines, cur)
            cur = w
    append(lines, cur)
    return lines

# Lignes d'un texte brut (conserve les sauts de ligne, ni retour ni normalisation).
func raw_lines(text):
    return _s.split(text, "\n")

func lines_text(lines):
    return _s.join("\n", lines)

# Conversion stricte vers int / float (lève ValueError si le texte n'est pas valide).
func parse_int(text):
    if not is_int_text(text):
        raise("ValueError", "entier invalide")
    return to_int(text)

func parse_float(text):
    if not is_float_text(text):
        raise("ValueError", "nombre invalide")
    return to_float(text)

# ---------------------------------------------------------------------
# Messages (français par défaut ; "en" pour les messages d'argparse de Python)
# ---------------------------------------------------------------------

_LANG := {"code": "fr"}

_MSGS := {
    "fr": {
        "usage": "usage : ",
        "positional": "arguments positionnels",
        "options": "options",
        "help_desc": "affiche ce message d'aide et quitte",
        "version_desc": "affiche la version et quitte",
        "required": "les arguments suivants sont requis : {0}",
        "mutex_required": "un des arguments {0} est requis",
        "not_allowed": "incompatible avec l'argument {0}",
        "arg_prefix": "argument {0} : {1}",
        "invalid_type": "valeur {0} invalide : {1}",
        "invalid_value": "valeur invalide : {0}",
        "invalid_choice": "choix invalide : {0} (choisir parmi {1})",
        "expected_one": "un argument est attendu",
        "expected_n": "{0} arguments sont attendus",
        "expected_one_or_more": "au moins un argument est attendu",
        "ignored_explicit": "valeur explicite ignorée : {0}",
        "ambiguous": "option ambiguë : {0} peut désigner {1}",
        "unrecognized": "arguments non reconnus : {0}",
        "error": "erreur",
        "default_fmt": "(défaut : {0})",
        "man_name": "NOM",
        "man_synopsis": "SYNOPSIS",
        "man_description": "DESCRIPTION",
        "man_options": "OPTIONS",
        "man_arguments": "ARGUMENTS",
        "man_commands": "COMMANDES",
        "man_see_also": "VOIR AUSSI",
        "man_version": "VERSION",
        "man_author": "AUTEUR",
        "man_manual": "Manuel de {0}"
    },
    "en": {
        "usage": "usage: ",
        "positional": "positional arguments",
        "options": "options",
        "help_desc": "show this help message and exit",
        "version_desc": "show program's version number and exit",
        "required": "the following arguments are required: {0}",
        "mutex_required": "one of the arguments {0} is required",
        "not_allowed": "not allowed with argument {0}",
        "arg_prefix": "argument {0}: {1}",
        "invalid_type": "invalid {0} value: {1}",
        "invalid_value": "invalid value: {0}",
        "invalid_choice": "invalid choice: {0} (choose from {1})",
        "expected_one": "expected one argument",
        "expected_n": "expected {0} arguments",
        "expected_one_or_more": "expected at least one argument",
        "ignored_explicit": "ignored explicit argument {0}",
        "ambiguous": "ambiguous option: {0} could match {1}",
        "unrecognized": "unrecognized arguments: {0}",
        "error": "error",
        "default_fmt": "(default: {0})",
        "man_name": "NAME",
        "man_synopsis": "SYNOPSIS",
        "man_description": "DESCRIPTION",
        "man_options": "OPTIONS",
        "man_arguments": "ARGUMENTS",
        "man_commands": "COMMANDS",
        "man_see_also": "SEE ALSO",
        "man_version": "VERSION",
        "man_author": "AUTHOR",
        "man_manual": "{0} manual"
    }
}

# Langue des messages : "fr" (défaut) ou "en". Retourne l'ancienne.
func set_language(code):
    if code != "fr" and code != "en":
        raise("ArgumentError", "argparse.set_language() : langue \"fr\" ou \"en\" attendue")
    old := _LANG["code"]
    _LANG["code"] = code
    return old

func language():
    return _LANG["code"]

func msg(key):
    return _MSGS[_LANG["code"]][key]

# msg(key) avec {0} {1} ... remplacés par `values`.
func fmt(key, values):
    t := msg(key)
    i := 0
    for v in values:
        t = replace_all(t, "{" + str(i) + "}", str(v))
        i = i + 1
    return t
