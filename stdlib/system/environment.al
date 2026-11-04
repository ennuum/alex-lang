# ALEX STANDARD LIBRARY — system.environment
#
# Environnement du programme : variables d'environnement (lecture typée, développement de « $NOM »,
# modification temporaire), arguments de la ligne de commande, chemins de l'utilisateur.
#
# Les variables concernent le PROCESSUS ALEX et ses futurs fils, jamais le shell qui l'a lancé.
#
# Exemple
#   use system.environment as env
#   port := env.get_int("PORT", 8080)
#   debug := env.get_bool("DEBUG", false)
#   print(env.expand("${HOME}/projets/$PROJET"))
#   env.with_vars({"LANG": "C"}, () => process.run("date"))
#
# Erreurs : TypeError (nom ou valeur non str), ArgumentError (valeur illisible par get_int / get_bool).

from core use len, type, to_int
from collections use append, keys, sort, contains_key
use string as _s
use os as _os
use process as _proc

func _need_name(fn, name):
    if type(name) != "str" or name == "":
        raise("TypeError", "environment." + fn + " : nom de variable (str non vide) attendu")

# ---------------------------------------------------------------- variables
# Valeur de la variable, ou fallback si elle est absente.
func get(name, fallback=null):
    _need_name("get", name)
    return _os.getenv(name, fallback)

# Définit la variable (value : str, ou un nombre / booléen converti en texte).
func set(name, value):
    _need_name("set", name)
    t := type(value)
    if t == "bool":
        if value:
            value = "1"
        else:
            value = "0"
    elif t == "int" or t == "float":
        value = str(value)
    elif t != "str":
        raise("TypeError", "environment.set : valeur str attendue (obtenu '" + t + "')")
    _os.setenv(name, value)

# Supprime la variable (sans erreur si elle est absente).
func unset(name):
    _need_name("unset", name)
    _os.unsetenv(name)

func has(name):
    _need_name("has", name)
    return _os.hasenv(name)

# Copie de tout l'environnement : dict nom -> valeur.
func all():
    return _os.env()

# Noms des variables, triés.
func names():
    out := keys(_os.env())
    sort(out)
    return out

# Entier : fallback si la variable est absente ou vide ; ArgumentError si elle n'est pas un entier.
func get_int(name, fallback=null):
    v := get(name)
    if v == null or _s.trim(v) == "":
        return fallback
    text := _s.trim(v)
    digits := text
    if _s.starts_with(text, "-") or _s.starts_with(text, "+"):
        digits = _s.slice(text, 1)
    ok := digits != ""
    for c in digits:
        if c < '0' or c > '9':
            ok = false
    if not ok:
        raise("ArgumentError", "environment.get_int : " + name + "='" + v + "' n'est pas un entier")
    return to_int(text)

# Booléen : 1/true/yes/on/oui et 0/false/no/off/non (sans casse) ; fallback si absente ou vide.
func get_bool(name, fallback=null):
    v := get(name)
    if v == null or _s.trim(v) == "":
        return fallback
    w := _s.lower(_s.trim(v))
    if w == "1" or w == "true" or w == "yes" or w == "on" or w == "oui" or w == "vrai":
        return true
    if w == "0" or w == "false" or w == "no" or w == "off" or w == "non" or w == "faux":
        return false
    raise("ArgumentError", "environment.get_bool : " + name + "='" + v + "' n'est pas un booléen")

# Liste : la valeur découpée par sep (séparateur des listes de chemins par défaut : ":" ou ";"),
# éléments vides retirés ; [] si absente.
func get_list(name, sep=null):
    v := get(name)
    if v == null:
        return []
    if sep == null:
        sep = path_list_separator()
    out := []
    for part in _s.split(v, sep):
        if part != "":
            append(out, part)
    return out

# Séparateur des listes de chemins (PATH) : ";" sous Windows, ":" ailleurs.
func path_list_separator():
    if _os.platform() == "windows":
        return ";"
    return ":"

# Répertoires de PATH, dans l'ordre de recherche.
func path_dirs():
    return get_list("PATH")

# Chemin complet du programme trouvé dans PATH, ou null.
func find_program(name):
    return _proc.which(name)

func _is_name_char(c, first):
    if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_':
        return true
    return not first and c >= '0' and c <= '9'

# Remplace $NOM, ${NOM} et ${NOM:-défaut} par la valeur des variables ("" si absente) ; « $$ » donne « $ ».
# vars : dict prioritaire sur l'environnement (facultatif).
func expand(text, vars=null):
    if type(text) != "str":
        raise("TypeError", "environment.expand : str attendue")
    out := ""
    i := 0
    n := len(text)
    while i < n:
        c := text[i]
        if c != '$' or i + 1 >= n:
            out += str(c)
            i += 1
            continue
        nxt := text[i + 1]
        if nxt == '$':
            out += "$"
            i += 2
            continue
        if nxt == '{':
            close := i + 2
            while close < n and text[close] != '}':
                close += 1
            if close >= n:
                out += _s.slice(text, i)
                break
            inner := _s.slice(text, i + 2, close)
            fallback_value := null
            k := _s.find(inner, ":-")
            if k >= 0:
                fallback_value = _s.slice(inner, k + 2)
                inner = _s.slice(inner, 0, k)
            out += _lookup(inner, vars, fallback_value)
            i = close + 1
            continue
        if _is_name_char(nxt, true):
            j := i + 1
            while j < n and _is_name_char(text[j], false):
                j += 1
            out += _lookup(_s.slice(text, i + 1, j), vars, null)
            i = j
            continue
        out += "$"
        i += 1
    return out

func _lookup(name, vars, fallback_value):
    v := null
    if vars != null and contains_key(vars, name):
        v = str(vars[name])
    else:
        v = _os.getenv(name)
    if (v == null or v == "") and fallback_value != null:
        return fallback_value
    if v == null:
        return ""
    return v

# Exécute fn() avec des variables modifiées (valeur null : supprimée), puis rétablit l'environnement d'avant.
# Renvoie le résultat de fn().
func with_vars(vars, fn):
    if type(vars) != "dict":
        raise("TypeError", "environment.with_vars : dict nom -> valeur attendu")
    saved := {}
    for name in keys(vars):
        saved[name] = _os.getenv(name)
    try:
        for name in keys(vars):
            if vars[name] == null:
                unset(name)
            else:
                set(name, vars[name])
        return fn()
    finally:
        for name in keys(saved):
            if saved[name] == null:
                _os.unsetenv(name)
            else:
                _os.setenv(name, saved[name])

# ---------------------------------------------------------------- programme et utilisateur
# Arguments après le script ; argv() : avec le chemin du script en tête.
func args():
    return _os.args()

func argv():
    return _os.argv()

# Chemin du script lancé.
func program():
    a := _os.argv()
    if len(a) == 0:
        return null
    return a[0]

func home():
    return _os.home()

func username():
    return _os.username()

func cwd():
    return _os.cwd()

func tmp_dir():
    return _os.tmp_dir()

func pid():
    return _os.pid()
