# ALEX STANDARD LIBRARY — web.css.variables
#
# Propriétés personnalisées (« variables CSS », CSS Custom Properties Level 1) : définition, portée, et
# résolution des références var(--nom, repli) — y compris imbriquées et en cascade de replis, avec détection
# des cycles (une variable cyclique est invalide, son repli s'applique).
#
#   use web.css.variables as vars
#   s := vars.Scope({"--fond": "#fff", "--texte": "var(--sombre, #222)", "--pad": "8px"})
#   s.resolve("1px solid var(--texte)")          # 1px solid #222
#   s.resolve("calc(var(--pad) * 2)")             # calc(8px * 2)
#   enfant := s.child({"--fond": "#000"})         # hérite des autres
#   enfant.get("--fond")                          # #000
#   vars.var("couleur", "red")                    # var(--couleur, red)
#   vars.references("var(--a) var(--b, var(--c))")   # ["--a", "--b", "--c"]
#   vars.declarations({"primaire": "#36c"})        # « --primaire: #36c »
#
# Erreurs : CssValueError (resolve strict avec une variable indéfinie sans repli).

from core use len, type
from collections use append, keys
use string as _s
use web.css.css_errors as _err

func _name(n):
    t := str(n)
    if _s.starts_with(t, "--"):
        return t
    return "--" + _s.replace(t, "_", "-")

# Référence var(--nom[, repli]).
func var(name, fallback=null):
    if fallback == null:
        return "var(" + _name(name) + ")"
    return "var(" + _name(name) + ", " + str(fallback) + ")"

class Scope:
    func init(values=null, parent=null):
        self.values = {}
        self.parent = parent
        if values != null:
            for k in keys(values):
                self.values[_name(k)] = str(values[k])

    func set(name, value):
        self.values[_name(name)] = str(value)
        return self

    # Valeur brute (non résolue) dans cette portée ou les parentes, ou null.
    func get(name):
        n := _name(name)
        if n in self.values:
            return self.values[n]
        if self.parent != null:
            return self.parent.get(n)
        return null

    func has(name):
        return self.get(name) != null

    func child(values=null):
        return Scope(values, self)

    # Toutes les variables visibles (les plus proches l'emportent).
    func all():
        out := {}
        if self.parent != null:
            p := self.parent.all()
            for k in keys(p):
                out[k] = p[k]
        for k in keys(self.values):
            out[k] = self.values[k]
        return out

    # Remplace les var() par leurs valeurs ; strict : CssValueError pour une variable indéfinie sans repli
    # (sinon la référence vide « » la remplace, comme une valeur « invalide au moment du calcul »).
    func resolve(text, strict=false):
        return _resolve(self, str(text), [], strict)

    # Valeur résolue d'une variable.
    func value(name, strict=false):
        v := self.get(name)
        if v == null:
            return null
        return _resolve(self, v, [_name(name)], strict)

func _find_close(text, start):
    depth := 1
    i := start
    while i < len(text):
        c := text[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1

func _resolve(scope, text, stack, strict):
    out := []
    i := 0
    n := len(text)
    while i < n:
        if text[i:i + 4] == "var(" and (i == 0 or not _is_name(text[i - 1])):
            close := _find_close(text, i + 4)
            if close < 0:
                append(out, text[i:n])
                break
            inner := text[i + 4:close]
            comma := _top_comma(inner)
            name := _s.trim(inner if comma < 0 else inner[0:comma])
            fallback := null if comma < 0 else _s.trim(inner[comma + 1:len(inner)])
            v := null
            if not (name in stack):
                raw := scope.get(name)
                if raw != null:
                    v = _resolve(scope, raw, stack + [name], strict)
            if v == null and fallback != null:
                v = _resolve(scope, fallback, stack, strict)
            if v == null:
                if strict:
                    _err.value_error("variables.resolve", "variable indéfinie ou cyclique « " + name + " »")
                v = ""
            append(out, v)
            i = close + 1
            continue
        append(out, str(text[i]))
        i += 1
    return _s.join("", out)

func _is_name(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_'

func _top_comma(text):
    depth := 0
    i := 0
    while i < len(text):
        c := text[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        elif c == ',' and depth == 0:
            return i
        i += 1
    return -1

# Noms des variables référencées (replis compris), dans l'ordre.
func references(text):
    out := []
    t := str(text)
    i := 0
    while i < len(t):
        if t[i:i + 4] == "var(":
            j := i + 4
            while j < len(t) and (t[j] == ' '):
                j += 1
            k := j
            while k < len(t) and _is_name(t[k]):
                k += 1
            name := t[j:k]
            if name != "" and not (name in out):
                append(out, name)
            i = j
            continue
        i += 1
    return out

func uses_variables(text):
    return _s.contains(str(text), "var(")

# Déclarations « --nom: valeur » (texte) depuis un dict.
func declarations(values, separator="; "):
    parts := []
    for k in keys(values):
        append(parts, _name(k) + ": " + str(values[k]))
    return _s.join(separator, parts)

# Règle « :root { --a: …; } ».
func root_rule(values, selector=":root"):
    return selector + " { " + declarations(values) + " }"
