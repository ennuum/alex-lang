# ALEX STANDARD LIBRARY — web.css.responsive
#
# Conception adaptative : points de rupture nommés (requêtes up / down / between / only), règles par point de
# rupture depuis un dict, valeurs fluides, attribut sizes des images, et point de rupture actif pour une largeur.
#
#   use web.css.responsive as rs
#   bp := rs.Breakpoints()                      # sm 640, md 768, lg 1024, xl 1280, 2xl 1536 (px)
#   bp.up("md")                                 # (min-width: 768px)
#   bp.down("lg")                               # (max-width: 1023.98px)
#   bp.between("sm", "lg")                      # (min-width: 640px) and (max-width: 1023.98px)
#   bp.current(900)                             # md
#   rules := bp.rules(".carte", {"base": {"padding": "1rem"}, "md": {"padding": "2rem"}})
#   # [.carte { padding: 1rem; }, @media (min-width: 768px) { .carte { padding: 2rem; } }]
#   rs.sizes([("(min-width: 1024px)", "33vw"), ("(min-width: 640px)", "50vw")], "100vw")
#   rs.fluid_space(8, 32)                       # clamp() entre 8 et 32 px
#
# Erreurs : CssValueError (point de rupture inconnu).

from core use len, type, to_float
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.units as _units
use web.css.css_rule as _rule
use web.css.at_rule as _at
use web.css.media_query as _mq
use web.css.typography as _ty

const DEFAULT := {"sm": 640, "md": 768, "lg": 1024, "xl": 1280, "2xl": 1536}
const BOOTSTRAP := {"sm": 576, "md": 768, "lg": 992, "xl": 1200, "xxl": 1400}

class Breakpoints:
    # points : dict nom -> largeur minimale (px) ; unit : "px" ou "em" (requêtes en em, plus robustes au zoom).
    func init(points=null, unit="px"):
        self.points = points if points != null else DEFAULT
        self.unit = unit
        self.names = _sorted_names(self.points)

    func width(name):
        if not (name in self.points):
            _err.value_error("Breakpoints", "point de rupture inconnu « " + str(name) + " »")
        return to_float(self.points[name])

    func _fmt(px):
        if self.unit == "em":
            return _units.format_number(px / 16.0) + "em"
        return _units.format_number(px) + "px"

    func up(name):
        return "(min-width: " + self._fmt(self.width(name)) + ")"

    # Strictement en dessous du point (0,02 px de marge pour les écrans à densité fractionnaire).
    func down(name):
        return "(max-width: " + self._fmt(self.width(name) - 0.02) + ")"

    func between(low, high):
        return self.up(low) + " and " + self.down(high)

    # Uniquement dans l'intervalle de ce point (jusqu'au suivant).
    func only(name):
        nxt := self.next(name)
        if nxt == null:
            return self.up(name)
        return self.between(name, nxt)

    func next(name):
        i := 0
        while i < len(self.names):
            if self.names[i] == name:
                return self.names[i + 1] if i + 1 < len(self.names) else null
            i += 1
        _err.value_error("Breakpoints", "point de rupture inconnu « " + str(name) + " »")

    # Point actif pour une largeur (le plus grand dont la largeur minimale est atteinte), ou "base".
    func current(width):
        w := to_float(width)
        best := "base"
        for n in self.names:
            if w >= self.width(n):
                best = n
        return best

    func matches(name, env):
        return _mq.matches(self.up(name), env)

    # Règles mobile d'abord depuis un dict point -> déclarations (« base » : sans requête).
    func rules(selector, by_point):
        out := []
        if "base" in by_point:
            append(out, _rule.StyleRule(selector, by_point["base"]))
        for n in self.names:
            if n in by_point:
                append(out, _at.media(self.up(n), [_rule.StyleRule(selector, by_point[n])]))
        return out

    # Variante desktop d'abord : « base » pour les grands écrans, chaque point pour en dessous.
    func rules_down(selector, by_point):
        out := []
        if "base" in by_point:
            append(out, _rule.StyleRule(selector, by_point["base"]))
        i := len(self.names) - 1
        while i >= 0:
            n := self.names[i]
            if n in by_point:
                append(out, _at.media(self.down(n), [_rule.StyleRule(selector, by_point[n])]))
            i -= 1
        return out

    func variables(prefix="--bp-"):
        out := {}
        for n in self.names:
            out[prefix + n] = self._fmt(self.width(n))
        return out

func _sorted_names(points):
    names := []
    for k in keys(points):
        append(names, k)
    i := 1
    while i < len(names):
        cur := names[i]
        j := i - 1
        while j >= 0 and to_float(points[names[j]]) > to_float(points[cur]):
            names[j + 1] = names[j]
            j -= 1
        names[j + 1] = cur
        i += 1
    return names

# Attribut sizes d'une image : liste de (requête, taille) puis taille par défaut.
func sizes(conditions, default="100vw"):
    parts := []
    for c in conditions:
        append(parts, c[0] + " " + c[1])
    append(parts, default)
    return _s.join(", ", parts)

# Attribut srcset : dict largeur (px) -> chemin.
func srcset(sources):
    parts := []
    for k in keys(sources):
        append(parts, str(sources[k]) + " " + str(k) + "w")
    return _s.join(", ", parts)

# Espacement fluide (clamp) entre deux tailles px sur une plage d'écrans.
func fluid_space(min_px, max_px, min_vw=320, max_vw=1280):
    return _ty.fluid(min_px, max_px, min_vw, max_vw)

# Conteneur centré à largeur maximale avec gouttières.
func container(max_width="72rem", gutter="1rem"):
    return {"width": "100%", "max-width": str(max_width), "margin-inline": "auto", "padding-inline": str(gutter)}

# Média adaptatif (images, vidéos) qui ne déborde jamais.
func fluid_media():
    return {"max-width": "100%", "height": "auto", "display": "block"}

# Conteneur de requêtes (container queries) nommé.
func query_container(name=null):
    d := {"container-type": "inline-size"}
    if name != null:
        d["container-name"] = name
    return d

func hide_below(bp, name):
    return _at.media(bp.down(name), [_rule.StyleRule(".hide-below-" + name, {"display": "none"})])

# Classes utilitaires d'affichage par point de rupture (.hidden-md-up ...).
func visibility_utilities(bp=null):
    b := bp if bp != null else Breakpoints()
    out := []
    for n in b.names:
        append(out, _at.media(b.up(n), [_rule.StyleRule(".hidden-" + n + "-up", {"display": "none !important"})]))
        append(out, _at.media(b.down(n), [_rule.StyleRule(".hidden-" + n + "-down", {"display": "none !important"})]))
    return out
