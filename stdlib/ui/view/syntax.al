# ALEX STANDARD LIBRARY — ui.view.syntax
#
# Coloration syntaxique pour l'éditeur de code (ui.view.code_editor) : découpe une ligne en segments
# [début, fin, rôle] qui la couvrent entièrement (indices de caractères). Rôles : code_text,
# syn_keyword, syn_string, syn_comment, syn_number, syn_function, syn_builtin, syn_constant, syn_type,
# syn_op. Langages : "alex", "python", "json", "text" (aucune coloration).
#
#   use ui.view.syntax as syntax
#   syntax.tokens("func f(x):  # carré", "alex")
#   # [[0, 4, "syn_keyword"], [4, 5, "code_text"], [5, 6, "syn_function"], ...]
#
# Constructions sur plusieurs lignes : chaînes entre triples guillemets de Python (\"\"\" et ''', avec les
# préfixes f, r, b) et commentaires /* ... */ d'Alex. Pour les colorer, on passe d'une ligne à la suivante
# l'état « encore dans » :
#
#   r := syntax.tokens_from(ligne, "python", "")       # [segments, état de fin de ligne]
#   r2 := syntax.tokens_from(suivante, "python", r[1])  # r[1] : "" (hors construction), "tq_d" (dans \"\"\"),
#                                                       #   "tq_s" (dans '''), "block" (dans /* */)
#   syntax.states(lignes, "python")                     # état au début de chaque ligne
#
# syntax.words(langage) : mots-clés, constantes et fonctions prédéfinies (pour la complétion).

from core use len, type
from collections use append, contains_key, keys, sort
use string as _s

func _set(words):
    d := {}
    for w in words:
        d[w] = true
    return d

const _ALEX_KW := _set(["and", "as", "async", "await", "break", "finally", "catch", "class", "const", "continue", "else", "elif", "enum", "extends", "for", "from", "func", "if", "import", "in", "interface", "let", "match", "not", "or", "return", "self", "struct", "super", "try", "use", "while", "yield", "implements"])
const _ALEX_CONST := _set(["true", "false", "null"])
const _ALEX_BUILTIN := _set(["print", "input", "len", "type", "str", "raise", "to_int", "to_float", "to_bool", "append", "insert", "pop", "keys", "values", "items", "contains_key", "sort", "reverse", "range", "abs", "min", "max", "hash", "assert", "arity"])
const _PY_KW := _set(["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "self", "match", "case"])
const _PY_CONST := _set(["True", "False", "None"])
const _PY_BUILTIN := _set(["print", "input", "len", "type", "str", "int", "float", "bool", "list", "dict", "set", "tuple", "range", "enumerate", "zip", "map", "filter", "sorted", "min", "max", "abs", "sum", "open", "isinstance", "super", "repr", "any", "all"])
const _OPS := "+-*/%=<>!&|^~:.,;?@"

func languages():
    return ["alex", "python", "json", "text"]

# Langage d'après l'extension d'un nom de fichier.
func language_of(path):
    p := _s.lower(str(path))
    if _s.ends_with(p, ".al"):
        return "alex"
    if _s.ends_with(p, ".py"):
        return "python"
    if _s.ends_with(p, ".json"):
        return "json"
    return "text"

func _is_alpha(c):
    o := _s.ord(c)
    return (o >= 97 and o <= 122) or (o >= 65 and o <= 90) or o == 95 or o >= 192

func _is_digit(c):
    o := _s.ord(c)
    return o >= 48 and o <= 57

func _is_word(c):
    return _is_alpha(c) or _is_digit(c)

# Mots-clés, constantes et fonctions prédéfinies du langage (triés, sans doublon).
func words(language="alex"):
    sets := []
    if language == "alex":
        sets = [_ALEX_KW, _ALEX_CONST, _ALEX_BUILTIN]
    elif language == "python":
        sets = [_PY_KW, _PY_CONST, _PY_BUILTIN]
    elif language == "json":
        sets = [_set(["true", "false", "null"])]
    seen := {}
    for d in sets:
        for k in keys(d):
            seen[k] = true
    out := keys(seen)
    sort(out)
    return out

# Position juste après le terminateur de la construction `state`, cherché à partir de i ; -1 s'il n'est pas
# sur cette ligne.
func _find_close(line, i, state):
    n := len(line)
    if state == "block":
        while i + 1 < n:
            if line[i] == '*' and line[i + 1] == '/':
                return i + 2
            i += 1
        return -1
    q := '"' if state == "tq_d" else '\''
    while i < n:
        if line[i] == '\\':
            i += 2
            continue
        if line[i] == q and i + 2 < n and line[i + 1] == q and line[i + 2] == q:
            return i + 3
        i += 1
    return -1

# Segments [début, fin, rôle] couvrant la ligne.
func tokens(line, language="alex"):
    return tokens_from(line, language, "")[0]

# Comme tokens, avec l'état au début de la ligne (voir l'en-tête) : retourne [segments, état à la fin].
func tokens_from(line, language="alex", state=""):
    n := len(line)
    out := []
    if language == "text":
        if n > 0:
            append(out, [0, n, "code_text"])
        return [out, ""]
    if language == "json":
        state = ""
    if n == 0:
        return [out, state]
    kw := _ALEX_KW
    consts := _ALEX_CONST
    builtins := _ALEX_BUILTIN
    if language == "python":
        kw = _PY_KW
        consts = _PY_CONST
        builtins = _PY_BUILTIN
    if language == "json":
        kw = {}
        builtins = {}
        consts = _set(["true", "false", "null"])
    i := 0
    plain := 0
    prev_word := ""
    end_state := ""
    if state != "":
        # la ligne commence à l'intérieur d'une chaîne / d'un commentaire de la ligne précédente
        k := _find_close(line, 0, state)
        role0 := "syn_comment" if state == "block" else "syn_string"
        if k < 0:
            append(out, [0, n, role0])
            return [out, state]
        append(out, [0, k, role0])
        i = k
        plain = k
    while i < n:
        c := line[i]
        start := i
        role := null
        if c == '#' and language != "json":
            role = "syn_comment"
            i = n
        elif c == '/' and language == "alex" and i + 1 < n and line[i + 1] == '*':
            k := _find_close(line, i + 2, "block")
            if k < 0:
                i = n
                end_state = "block"
            else:
                i = k
            role = "syn_comment"
        elif (c == '"' or c == '\'') and language == "python" and i + 2 < n and line[i + 1] == c and line[i + 2] == c:
            tag := "tq_d" if c == '"' else "tq_s"
            k := _find_close(line, i + 3, tag)
            if k < 0:
                i = n
                end_state = tag
            else:
                i = k
            role = "syn_string"
        elif c == '"' or (c == '\'' and language != "json"):
            q := c
            i += 1
            while i < n and line[i] != q:
                if line[i] == '\\':
                    i += 1
                i += 1
            i = i + 1 if i < n else n
            role = "syn_string"
        elif (c == 'f' or c == 'r' or c == 'b') and i + 1 < n and (line[i + 1] == '"' or line[i + 1] == '\'') and language != "json":
            q := line[i + 1]
            if language == "python" and i + 3 < n and line[i + 2] == q and line[i + 3] == q:
                tag := "tq_d" if q == '"' else "tq_s"
                k := _find_close(line, i + 4, tag)
                if k < 0:
                    i = n
                    end_state = tag
                else:
                    i = k
            else:
                i += 2
                while i < n and line[i] != q:
                    if line[i] == '\\':
                        i += 1
                    i += 1
                i = i + 1 if i < n else n
            role = "syn_string"
        elif _is_digit(c) or (c == '-' and language == "json" and i + 1 < n and _is_digit(line[i + 1])):
            i += 1
            while i < n and (_is_word(line[i]) or line[i] == '.'):
                if (line[i] == 'e' or line[i] == 'E') and i + 1 < n and (line[i + 1] == '-' or line[i + 1] == '+'):
                    i += 1
                i += 1
            role = "syn_number"
        elif _is_alpha(c):
            while i < n and _is_word(line[i]):
                i += 1
            word := _s.slice(line, start, i)
            j := i
            while j < n and line[j] == ' ':
                j += 1
            if contains_key(kw, word):
                role = "syn_keyword"
            elif contains_key(consts, word):
                role = "syn_constant"
            elif prev_word == "func" or prev_word == "def":
                role = "syn_function"
            elif prev_word == "class" or prev_word == "extends" or prev_word == "struct" or prev_word == "enum" or prev_word == "interface":
                role = "syn_type"
            elif _s.ord(c) >= 65 and _s.ord(c) <= 90 and language != "json":
                role = "syn_type"
            elif j < n and line[j] == '(':
                role = "syn_builtin" if contains_key(builtins, word) else "syn_function"
            else:
                role = null
            prev_word = word
        elif _s.contains(_OPS, str(c)):
            i += 1
            role = "syn_op"
        else:
            i += 1
        if role != null:
            if plain < start:
                append(out, [plain, start, "code_text"])
            append(out, [start, i, role])
            plain = i
        if c != ' ' and not _is_alpha(c):
            prev_word = ""
    if plain < n:
        append(out, [plain, n, "code_text"])
    return [out, end_state]

# État (voir l'en-tête) au début de chaque ligne de lines : une liste de len(lines) + 1 éléments (le dernier
# est l'état à la fin du texte). Utile hors de l'éditeur ; l'éditeur, lui, met ces états en cache.
func states(lines, language="alex"):
    out := [""]
    st := ""
    for l in lines:
        st = tokens_from(l, language, st)[1]
        append(out, st)
    return out
