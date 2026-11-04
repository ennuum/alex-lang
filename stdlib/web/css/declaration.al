# ALEX STANDARD LIBRARY — web.css.declaration
#
# Déclarations CSS « propriété: valeur [!important] » et blocs de déclarations (le contenu d'une règle ou d'un
# attribut style). Analyse tolérante (une déclaration invalide est ignorée, comme dans un navigateur),
# développement des raccourcis, sérialisation.
#
#   use web.css.declaration as d
#   x := d.parse("color : red !important")
#   x.property, x.value, x.important          # color red true
#   str(x)                                    # color: red !important
#   b := d.parse_block("margin: 0 auto; color: #333; ;bad")
#   len(b)                                    # 2
#   d.to_dict(b)                              # {"margin": "0 auto", "color": "#333"}
#   d.expand_all(b)                           # margin-top / -right / -bottom / -left, color
#   d.from_dict({"font_size": "1rem", "color": "red"})   # liste de Declaration
#   d.is_valid_value("color", "rouge")        # false (nature « color » attendue)
#   d.value_problem("width", "12")            # « nombre sans unité pour une longueur »
#
# Erreurs : CssParseError (parse sur une déclaration invalide).

from core use len, type
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.value as _value
use web.css.property as _prop
use web.css.units as _units
use web.css.color as _color

class Declaration:
    func init(property, value, important=false, line=null):
        self.property = _prop.canonical(property)
        self.value = _s.trim(str(value))
        self.important = important
        self.line = line
        self.verbatim = false         # vrai : valeur écrite telle quelle, même en sortie compacte

    func parsed_value():
        return _value.parse(self.value)

    func is_custom():
        return _prop.is_custom(self.property)

    func to_css(compact=false):
        v := self.value
        if compact and not self.is_custom() and not self.verbatim:
            v = _value.normalize(v, true)
        sep := ":" if compact else ": "
        imp := ""
        if self.important:
            imp = "!important" if compact else " !important"
        return self.property + sep + v + imp

    func __str__():
        return self.to_css()

    func __eq__(other):
        return isinstance(other, Declaration) and other.property == self.property and other.value == self.value and other.important == self.important

    func copy():
        d := Declaration(self.property, self.value, self.important, self.line)
        d.verbatim = self.verbatim
        return d

    func is_valid():
        return _prop.is_known(self.property) and is_valid_value(self.property, self.value)

    # Déclarations longues (raccourci développé).
    func expand():
        out := []
        for p in _prop.expand(self.property, self.value):
            append(out, Declaration(p[0], p[1], self.important, self.line))
        return out

# Déclaration depuis « propriété: valeur » ; null si invalide (lenient) ou CssParseError (strict).
func parse(text, strict=true):
    t := _s.trim(str(text))
    if _s.ends_with(t, ";"):
        t = _s.trim(t[0:len(t) - 1])
    c := _s.find(t, ":")
    if c <= 0:
        if strict:
            _err.parse_error("declaration.parse", "« : » manquant dans « " + t + " »")
        return null
    name := _s.trim(t[0:c])
    raw := _s.trim(t[c + 1:len(t)])
    if not _valid_name(name) or (raw == "" and not _s.starts_with(name, "--")):
        if strict:
            _err.parse_error("declaration.parse", "déclaration invalide « " + t + " »")
        return null
    v := _value.parse(raw)
    vtext := raw
    if v.important:
        lower := _s.lower(raw)
        k := len(lower) - 1
        bang := -1
        while k >= 0:
            if lower[k] == '!':
                bang = k
                break
            k -= 1
        vtext = _s.trim(raw[0:bang])
    return Declaration(name, vtext, v.important)

func _valid_name(name):
    if len(name) == 0:
        return false
    for c in name:
        if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_' or _s.ord(c) >= 128):
            return false
    return true

# Découpe sur « ; » hors chaînes, parenthèses et crochets.
func split_declarations(text):
    out := []
    cur := []
    depth := 0
    quote := null
    esc := false
    for c in str(text):
        if esc:
            append(cur, str(c))
            esc = false
            continue
        if c == '\\':
            append(cur, str(c))
            esc = true
            continue
        if quote != null:
            append(cur, str(c))
            if c == quote:
                quote = null
            continue
        if c == '"' or c == '\'':
            quote = c
        elif c == '(' or c == '[' or c == '{':
            depth += 1
        elif c == ')' or c == ']' or c == '}':
            depth -= 1
        if c == ';' and depth == 0:
            append(out, _s.join("", cur))
            cur = []
        else:
            append(cur, str(c))
    append(out, _s.join("", cur))
    return out

# Liste de Declaration d'un bloc (contenu d'un attribut style ou d'une règle) ; les invalides sont ignorées
# (issues : liste facultative qui reçoit le texte des déclarations ignorées).
func parse_block(text, issues=null):
    out := []
    for part in split_declarations(_strip_comments(str(text))):
        if _s.trim(part) == "":
            continue
        d := parse(part, false)
        if d == null:
            if issues != null:
                append(issues, _s.trim(part))
            continue
        append(out, d)
    return out

func _strip_comments(text):
    if not _s.contains(text, "/*"):
        return text
    out := []
    i := 0
    n := len(text)
    while i < n:
        if text[i] == '/' and i + 1 < n and text[i + 1] == '*':
            j := i + 2
            while j < n - 1 and not (text[j] == '*' and text[j + 1] == '/'):
                j += 1
            i = j + 2
            continue
        append(out, str(text[i]))
        i += 1
    return _s.join("", out)

# Déclarations depuis un dict (noms ALEX acceptés : font_size) ; une valeur liste -> séparée par des virgules ;
# null / false ignorées ; « !important » final reconnu.
func from_dict(props):
    out := []
    for k in keys(props):
        v := props[k]
        if v == null or v == false:
            continue
        text := v
        if type(v) == "list" or type(v) == "tuple":
            parts := []
            for x in v:
                append(parts, str(x))
            text = _s.join(", ", parts)
        elif type(v) == "int" or type(v) == "float":
            text = str(v)
        imp := false
        t := _s.trim(str(text))
        if _s.ends_with(_s.lower(t), "!important"):
            imp = true
            t = _s.trim(t[0:len(t) - 10])
        append(out, Declaration(k, t, imp))
    return out

# dict propriété -> valeur (la dernière l'emporte, sauf !important).
func to_dict(decls):
    out := {}
    imp := {}
    for d in decls:
        if d.property in imp and imp[d.property] and not d.important:
            continue
        out[d.property] = d.value
        imp[d.property] = d.important
    return out

# Texte d'un bloc de déclarations.
func to_css(decls, compact=false):
    parts := []
    for d in decls:
        append(parts, d.to_css(compact))
    return _s.join(";" if compact else "; ", parts)

# Raccourcis développés.
func expand_all(decls):
    out := []
    for d in decls:
        for x in d.expand():
            append(out, x)
    return out

# Dernière déclaration d'une propriété (en tenant compte de !important), ou null.
func find(decls, name):
    n := _prop.canonical(name)
    found := null
    for d in decls:
        if d.property == n:
            if found == null or d.important or not found.important:
                found = d
    return found

# ---------------------------------------------------------------- contrôle des valeurs

const _LENGTH_WORDS := ["auto", "none", "normal", "fit-content", "min-content", "max-content", "stretch", "thin", "medium", "thick", "content", "infinite", "contain", "cover"]

# Problème de syntaxe générique (jetons invalides) d'une valeur, ou null.
func _syntax_problem(v):
    depth := 0
    for t in _value.tokenize(v):
        if t.kind == _value.FUNCTION or t.kind == _value.OPEN:
            depth += 1
        elif t.kind == _value.CLOSE:
            depth -= 1
            if depth < 0:
                return "« " + t.value + " » sans ouverture"
            continue
        if t.kind == _value.BAD_STRING:
            return "chaîne non terminée"
        if t.kind == _value.BAD_URL:
            return "url() invalide"
        if t.kind == _value.SEMICOLON:
            return "« ; » inattendu"
        if t.kind == _value.OPEN and t.value == "{":
            return "« { » inattendu"
        if t.kind == _value.CLOSE:
            return "« " + t.value + " » sans ouverture"
        if t.is_delim("!"):
            return "« ! » inattendu"
    return null

func _check_numeric(items, allow_pct, kinds):
    for it in items:
        if isinstance(it, _value.Token):
            k := it.kind
            if k == _value.COMMA or k == _value.IDENT or (k == _value.DELIM and it.value == "/"):
                continue
            if k == _value.NUMBER:
                if "number" in kinds or "integer" in kinds:
                    if "integer" in kinds and not ("number" in kinds) and _s.contains(str(it.value), "."):
                        return "entier attendu, trouvé « " + it.to_css() + " »"
                    continue
                if it.value == 0 or it.value == 0.0 or str(it.value) == "0":
                    continue
                return "nombre sans unité pour une " + ("durée" if "time" in kinds else "longueur") + " (« " + it.to_css() + " »)"
            if k == _value.PERCENTAGE:
                if allow_pct:
                    continue
                return "pourcentage non accepté ici (« " + it.to_css() + " »)"
            if k == _value.DIMENSION:
                uk := _units.kind_of(it.unit)
                if uk == null:
                    return "unité inconnue « " + it.unit + " »"
                if not (uk in kinds):
                    return "unité « " + it.unit + " » inattendue (" + _s.join("/", kinds) + " attendu)"
                continue
            if k == _value.STRING or k == _value.HASH:
                return "valeur inattendue « " + it.to_css() + " »"
        elif isinstance(it, _value.Function):
            continue
        elif isinstance(it, _value.Block):
            if it.open != "[":
                return "bloc inattendu « " + it.to_css() + " »"
    return null

# Raison pour laquelle la valeur ne convient pas à la propriété (selon sa nature), ou null si elle convient.
# Les propriétés inconnues et les valeurs dynamiques (var(), env(), attr()) ne sont contrôlées que sur la syntaxe.
func value_problem(property, value):
    v := _s.trim(str(value))
    n := _prop.canonical(property)
    if v == "":
        return null if _prop.is_custom(n) else "valeur vide"
    p := _syntax_problem(v)
    if p != null:
        return p
    if _prop.is_custom(n) or _prop.is_css_wide(v):
        return null
    low := _s.lower(v)
    if _s.contains(low, "var(") or _s.contains(low, "env(") or _s.contains(low, "attr("):
        return null
    k := _prop.kind(n)
    if k == null or k == "any" or k == "keyword":
        if k == "keyword":
            for it in _value.parse(v).components:
                if isinstance(it, _value.Token) and (it.kind == _value.DIMENSION or it.kind == _value.PERCENTAGE or it.kind == _value.HASH):
                    return "mot-clé attendu, trouvé « " + it.to_css() + " »"
        return null
    items := _value.parse(v).components
    if k == "color":
        if len(items) == 1 and _color.is_color(v):
            return null
        if len(items) == 1 and isinstance(items[0], _value.Function) and items[0].lower_name() in ["color-mix", "light-dark", "color", "lab", "lch", "oklab", "oklch", "rgb", "rgba", "hsl", "hsla", "hwb"]:
            return null
        return "couleur invalide « " + v + " »"
    if k == "length":
        return _check_numeric(items, false, ["length"])
    if k == "length-percentage":
        return _check_numeric(items, true, ["length"])
    if k == "number":
        return _check_numeric(items, true, ["number", "length"])
    if k == "integer":
        return _check_numeric(items, false, ["integer"])
    if k == "time":
        return _check_numeric(items, false, ["time"])
    return null

func is_valid_value(property, value):
    return value_problem(property, value) == null
