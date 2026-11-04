# ALEX STANDARD LIBRARY — web.css.theme
#
# Thèmes et jetons de conception (design tokens) : arbre de jetons -> propriétés personnalisées, variantes
# (sombre, contraste élevé…) appliquées par préférence système et/ou attribut data-theme, références var(),
# palettes générées depuis une couleur, vérification des contrastes, thème par défaut complet.
#
#   use web.css.theme as th
#   t := th.Theme({"color": {"fond": "#fff", "texte": "#1f2937", "accent": "#2563eb"}, "space": {"1": "4px", "2": "8px"}})
#   t.variables()                    # {"--color-fond": "#fff", "--color-texte": "#1f2937", ..., "--space-1": "4px"}
#   t.var("color.accent")            # var(--color-accent)
#   t.variant("dark", {"color": {"fond": "#111827", "texte": "#f9fafb"}})
#   t.to_css()                       # :root {...} @media (prefers-color-scheme: dark) { :root:not([data-theme=light]) {...} } [data-theme=dark] {...}
#   th.palette("#2563eb")            # {"50": "#…", ..., "500": "#2563eb", ..., "900": "#…"}
#   t.contrast_issues([("color.texte", "color.fond")])   # [] si le contraste AA est respecté
#   th.default_theme().to_css()
#
# Erreurs : CssValueError (jeton inconnu, couleur invalide).

from core use len, type, to_float
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.color as _color
use web.css.css_rule as _rule
use web.css.at_rule as _at
use web.css.stylesheet as _sheet
use web.css.css_writer as _writer

func _slug(k):
    t := _s.lower(str(k))
    out := []
    for c in t:
        if (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-' or c == '_' or _s.ord(c) >= 128:
            append(out, str(c))
        else:
            append(out, "-")
    return _s.join("", out)

# Aplatit un arbre de jetons : {"color": {"fond": …}} -> {"color.fond": …}.
func flatten(tree, prefix=""):
    out := {}
    for k in keys(tree):
        v := tree[k]
        path := str(k) if prefix == "" else prefix + "." + str(k)
        if type(v) == "dict":
            sub := flatten(v, path)
            for sk in keys(sub):
                out[sk] = sub[sk]
        else:
            out[path] = str(v)
    return out

func _deep_merge(base, extra):
    out := {}
    for k in keys(base):
        out[k] = base[k]
    for k in keys(extra):
        if k in out and type(out[k]) == "dict" and type(extra[k]) == "dict":
            out[k] = _deep_merge(out[k], extra[k])
        else:
            out[k] = extra[k]
    return out

# Nom de propriété personnalisée d'un chemin de jeton (« color.fond » -> --color-fond).
func variable_name(path, prefix=""):
    parts := []
    for p in _s.split(path, "."):
        append(parts, _slug(p))
    return "--" + prefix + _s.join("-", parts)

class Theme:
    # prefix : préfixe des variables (« ds- » -> --ds-color-fond) ; selector : portée (:root par défaut).
    func init(tokens=null, prefix="", selector=":root"):
        self.tokens = tokens if tokens != null else {}
        self.prefix = prefix
        self.selector = selector
        self.variants = []            # (nom, jetons partiels, requête média ou null)

    func set(path, value):
        parts := _s.split(path, ".")
        node := self.tokens
        i := 0
        while i < len(parts) - 1:
            p := parts[i]
            if not (p in node) or type(node[p]) != "dict":
                node[p] = {}
            node = node[p]
            i += 1
        node[parts[len(parts) - 1]] = value
        return self

    func get(path):
        flat := flatten(self.tokens)
        if path in flat:
            return flat[path]
        _err.value_error("Theme.get", "jeton inconnu « " + str(path) + " »")

    func has(path):
        return path in flatten(self.tokens)

    func var(path, fallback=null):
        if not self.has(path):
            _err.value_error("Theme.var", "jeton inconnu « " + str(path) + " »")
        n := variable_name(path, self.prefix)
        if fallback == null:
            return "var(" + n + ")"
        return "var(" + n + ", " + str(fallback) + ")"

    func paths():
        return keys(flatten(self.tokens))

    # Variables CSS (dict) ; une valeur peut référencer un autre jeton par « {chemin} ».
    func variables(tokens=null):
        flat := flatten(tokens if tokens != null else self.tokens)
        out := {}
        for k in keys(flat):
            out[variable_name(k, self.prefix)] = self._refs(flat[k])
        return out

    func _refs(v):
        t := str(v)
        if not _s.contains(t, "{"):
            return t
        out := []
        i := 0
        n := len(t)
        while i < n:
            if t[i] == '{':
                j := _s.find(t[i + 1:n], "}")
                if j >= 0:
                    append(out, "var(" + variable_name(t[i + 1:i + 1 + j], self.prefix) + ")")
                    i = i + j + 2
                    continue
            append(out, str(t[i]))
            i += 1
        return _s.join("", out)

    # Variante : jetons remplacés ; media : requête qui l'active automatiquement (null : data-theme seul).
    func variant(name, overrides, media="auto"):
        m := media
        if media == "auto":
            m = "(prefers-color-scheme: dark)" if name == "dark" else ("(prefers-contrast: more)" if name == "high-contrast" else null)
        append(self.variants, (name, overrides, m))
        return self

    # Jetons résolus d'une variante (base fusionnée).
    func resolved(name=null):
        if name == null:
            return self.tokens
        for v in self.variants:
            if v[0] == name:
                return _deep_merge(self.tokens, v[1])
        _err.value_error("Theme.resolved", "variante inconnue « " + str(name) + " »")

    func rules():
        out := [_rule.StyleRule(self.selector, self.variables())]
        names := []
        for v in self.variants:
            append(names, v[0])
        for v in self.variants:
            vars := self.variables(v[1])
            if v[2] != null:
                others := []
                for n in names:
                    if n != v[0]:
                        append(others, n)
                sel := self.selector + ":not([data-theme=" + ("light" if v[0] == "dark" else "default") + "])"
                if len(others) > 0:
                    nots := []
                    for o in others:
                        append(nots, "[data-theme=" + o + "]")
                    sel = sel + ":not(" + _s.join(", ", nots) + ")"
                append(out, _at.media(v[2], [_rule.StyleRule(sel, vars)]))
            attr_sel := "[data-theme=" + v[0] + "]"
            if self.selector != ":root":
                attr_sel = self.selector + attr_sel
            append(out, _rule.StyleRule(attr_sel, vars))
        if len(self.variants) > 0:
            schemes := ["light"]
            for v in self.variants:
                if v[0] == "dark":
                    append(schemes, "dark")
            if len(schemes) > 1:
                out[0].set("color-scheme", _s.join(" ", schemes))
        return out

    func stylesheet():
        return _sheet.Stylesheet(self.rules())

    func to_css(pretty=false):
        return _writer.write(self.rules(), _writer.Writer(pretty))

    # Paires (texte, fond) dont le contraste est insuffisant : liste de (texte, fond, ratio, variante).
    func contrast_issues(pairs, level="AA", large_text=false):
        out := []
        names := [null]
        for v in self.variants:
            append(names, v[0])
        for n in names:
            flat := flatten(self.resolved(n))
            for p in pairs:
                if not (p[0] in flat) or not (p[1] in flat):
                    continue
                fg := _color.try_parse(flat[p[0]])
                bg := _color.try_parse(flat[p[1]])
                if fg == null or bg == null:
                    continue
                if not _color.is_readable(fg, bg, level, large_text):
                    append(out, (p[0], p[1], _color.contrast_ratio(fg, bg), n if n != null else "base"))
        return out

# Palette 50..950 autour d'une couleur (500 = la couleur) : tons éclaircis vers le blanc, assombris vers le noir
# en HSL (teinte et saturation conservées).
func palette(base):
    c := _color.parse(base) if type(base) == "str" else base
    hsl := c.hsl()
    l := hsl[2]
    lighter := [("50", 0.95), ("100", 0.88), ("200", 0.75), ("300", 0.58), ("400", 0.32)]
    darker := [("600", 0.85), ("700", 0.7), ("800", 0.55), ("900", 0.42), ("950", 0.28)]
    out := {}
    for s in lighter:
        out[s[0]] = _color.from_hsl(hsl[0], hsl[1], l + (97.0 - l) * s[1]).to_hex()
    out["500"] = c.to_hex()
    for s in darker:
        out[s[0]] = _color.from_hsl(hsl[0], hsl[1], l * s[1]).to_hex()
    return out

# Jetons d'échelle d'espacement (base px, multiplicateurs).
func spacing_scale(base=4, steps=null):
    st := steps if steps != null else [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24]
    out := {}
    for k in st:
        out[str(k)] = "0" if k == 0 else _rem(base * k)
    return out

func _rem(px):
    v := to_float(px) / 16.0
    t := str(v)
    if _s.ends_with(t, ".0"):
        t = t[0:len(t) - 2]
    return t + "rem"

# Thème complet prêt à l'emploi (couleurs, police, espacements, rayons, ombres) avec variante sombre.
func default_theme(accent="#2563eb"):
    t := Theme({
        "color": {"bg": "#ffffff", "surface": "#f8fafc", "text": "#0f172a", "muted": "#475569", "border": "#e2e8f0", "accent": accent, "accent-text": _color.parse(accent).text_color().to_hex(), "danger": "#dc2626", "success": "#16a34a", "warning": "#d97706"},
        "font": {"sans": "system-ui, -apple-system, \"Segoe UI\", Roboto, sans-serif", "mono": "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"},
        "space": spacing_scale(),
        "radius": {"sm": "4px", "md": "8px", "lg": "12px", "full": "9999px"},
        "shadow": {"sm": "0 1px 2px rgb(0 0 0 / 5%)", "md": "0 4px 6px -1px rgb(0 0 0 / 10%), 0 2px 4px -2px rgb(0 0 0 / 10%)"}
    })
    p := palette(accent)
    t.variant("dark", {"color": {"bg": "#0b1120", "surface": "#111827", "text": "#e5e7eb", "muted": "#9ca3af", "border": "#1f2937", "accent": p["400"]}})
    return t
