# ALEX STANDARD LIBRARY — ui.accessibility
#
# Accessibilité des interfaces ui.view : arbre d'accessibilité (rôle, nom accessible, état, focalisable) calculé
# à partir de l'arbre de la vue, ordre de tabulation, linéarisation telle qu'un lecteur d'écran l'énoncerait,
# et AUDIT selon des règles inspirées des WCAG : boutons et champs sans nom, images sans texte alternatif,
# contraste des couleurs insuffisant (ratio WCAG 2.x), dialogues sans titre, tableaux sans en-têtes, textes
# vides, interface sans élément focalisable.
#
#   use ui.accessibility as a11y
#   arbre := a11y.tree(vue())                       # AccessibleNode (role, name, children...)
#   print(a11y.speak(vue()))                        # « titre Compteur. bouton +1. zone de texte Votre nom. »
#   for p in a11y.audit(vue()):
#       print(p["severity"], p["rule"], p["message"])
#   print(a11y.contrast_ratio("#777777", "#ffffff"))      # 4.48 (AA texte normal : 4.5 requis)
#   print(a11y.focus_order(vue()))                  # noms des éléments focalisables, dans l'ordre
#
# Erreurs : ArgumentError (couleur invalide).

from core use len, type, to_int
from collections use append
use string as _s
use ui.view.node as _n
use math as _math

const ROLES := {"text": "texte", "button": "bouton", "input": "zone de texte", "field": "zone de texte", "textarea": "zone de texte multiligne",
    "code_editor": "éditeur de code", "checkbox": "case à cocher", "radio": "groupe de boutons radio",
    "select": "liste déroulante", "slider": "curseur", "spinbox": "compteur", "image": "image", "canvas": "dessin",
    "progress": "barre de progression", "list_view": "liste", "table": "tableau", "tree": "arborescence",
    "column": "groupe", "row": "groupe", "panel": "région", "scroll": "zone défilante", "tabs": "onglets",
    "split": "séparation", "dialog": "dialogue", "menu_bar": "barre de menus", "menu": "menu", "separator": "séparateur",
    "spacer": "espace"}
const FOCUSABLE := ["button", "input", "field", "textarea", "code_editor", "checkbox", "radio", "select", "slider", "spinbox",
                    "list_view", "table", "tree", "tabs"]
const DECORATIVE := ["spacer", "separator"]

class AccessibleNode:
    func init(role, name, kind, focusable, state, children):
        self.role = role
        self.name = name
        self.kind = kind
        self.focusable = focusable
        self.state = state
        self.children = children

    func walk(fn):
        fn(self)
        for c in self.children:
            c.walk(fn)

    func to_dict():
        return {"role": self.role, "name": self.name, "kind": self.kind, "focusable": self.focusable,
                "state": self.state, "children": [c.to_dict() for c in self.children]}

func _prop(node, k):
    return node.get(k, null)

func accessible_name(node):
    k := node.kind
    for key in ["aria_label", "label", "title", "alt", "content", "placeholder"]:
        v := _prop(node, key)
        if type(v) == "str" and _s.trim(v) != "":
            return _s.trim(v)
    if k == "button" or k == "panel":
        for c in node.children:
            if c.kind == "text":
                return _prop(c, "content")
    return null

func _state(node):
    st := {}
    k := node.kind
    en := _prop(node, "enabled")
    if en == false:
        st["désactivé"] = true
    if k == "checkbox":
        st["coché"] = _prop(node, "checked") == true
    if k == "progress":
        st["valeur"] = _prop(node, "value")
    if k == "slider" or k == "spinbox":
        st["valeur"] = _prop(node, "value")
    if k == "field" or k == "input":
        v := _prop(node, "value")
        if v != null and v != "":
            st["valeur"] = v
        if _prop(node, "password") == true:
            st["masqué"] = true
    return st

func tree(view_or_node):
    node := view_or_node
    if type(node) == "function":
        node = node()
    node = _n.coerce(node)
    role := "inconnu"
    if node.kind in ROLES:
        role = ROLES[node.kind]
    if node.kind == "text" and _prop(node, "style") == "title":
        role = "titre"
    kids := [tree(c) for c in node.children]
    return AccessibleNode(role, accessible_name(node), node.kind, node.kind in FOCUSABLE and _prop(node, "enabled") != false, _state(node), kids)

func focus_order(view_or_node):
    out := []
    tree(view_or_node).walk((a) => append(out, a.name) if a.focusable else null)
    return out

# Linéarisation « lecteur d'écran ».
func speak(view_or_node):
    parts := []
    tree(view_or_node).walk((a) => _say(a, parts))
    return _s.join(" ", parts)

func _say(a, parts):
    if a.kind in DECORATIVE or a.kind == "column" or a.kind == "row" or a.kind == "scroll" or a.kind == "split":
        return
    t := a.role
    if a.name != null:
        if a.kind == "text":
            if a.role == "titre":
                t = "titre " + a.name
            else:
                t = a.name
        else:
            t = a.role + " " + a.name
    for k in a.state:
        v := a.state[k]
        if v == true:
            t += ", " + k
        elif v != false and v != null:
            t += ", " + k + " " + str(v)
    append(parts, t + ".")

# ---- couleurs (WCAG 2.x) ----
func parse_color(c):
    if type(c) == "dict":
        return [c["r"], c["g"], c["b"]]
    if type(c) == "list" or type(c) == "tuple":
        return [c[0], c[1], c[2]]
    t := _s.lower(_s.trim(str(c)))
    if _s.starts_with(t, "#"):
        t = _s.substring(t, 1, len(t))
    if len(t) == 3:
        t = str(t[0]) + str(t[0]) + str(t[1]) + str(t[1]) + str(t[2]) + str(t[2])
    if len(t) != 6 and len(t) != 8:
        raise("ArgumentError", "couleur invalide : '" + str(c) + "'")
    out := []
    i := 0
    while i < 6:
        hi := _s.find("0123456789abcdef", str(t[i]))
        lo := _s.find("0123456789abcdef", str(t[i + 1]))
        if hi < 0 or lo < 0:
            raise("ArgumentError", "couleur invalide : '" + str(c) + "'")
        append(out, hi * 16 + lo)
        i += 2
    return out

func _channel(v):
    s := v / 255.0
    if s <= 0.03928:
        return s / 12.92
    return _pow((s + 0.055) / 1.055, 2.4)

func _pow(x, y):
    return _math.pow(x, y)

func relative_luminance(c):
    rgb := parse_color(c)
    return 0.2126 * _channel(rgb[0]) + 0.7152 * _channel(rgb[1]) + 0.0722 * _channel(rgb[2])

func contrast_ratio(fg, bg):
    a := relative_luminance(fg)
    b := relative_luminance(bg)
    hi := a
    lo := b
    if b > a:
        hi = b
        lo = a
    r := (hi + 0.05) / (lo + 0.05)
    return to_int(r * 100 + 0.5) / 100.0

# Niveau WCAG atteint : "AAA", "AA", "AA (grand texte)" ou "insuffisant".
func contrast_level(fg, bg, large_text=false):
    r := contrast_ratio(fg, bg)
    if large_text:
        if r >= 4.5:
            return "AAA"
        if r >= 3:
            return "AA"
        return "insuffisant"
    if r >= 7:
        return "AAA"
    if r >= 4.5:
        return "AA"
    if r >= 3:
        return "AA (grand texte)"
    return "insuffisant"

func _problem(out, severity, rule, message, kind):
    append(out, {"severity": severity, "rule": rule, "message": message, "kind": kind})

# Audit : liste de {"severity" (erreur | avertissement), "rule", "message", "kind"}.
# colors : paires [premier plan, fond] à vérifier (thème), optionnel.
func audit(view_or_node, colors=null):
    out := []
    node := view_or_node
    if type(node) == "function":
        node = node()
    _audit_node(_n.coerce(node), out)
    if len(focus_order(node)) == 0:
        _problem(out, "avertissement", "clavier", "aucun élément focalisable : l'interface n'est pas utilisable au clavier", "vue")
    if colors != null:
        for pair in colors:
            r := contrast_ratio(pair[0], pair[1])
            if r < 4.5:
                _problem(out, "erreur", "contraste", "contraste " + str(r) + ":1 entre " + str(pair[0]) + " et " + str(pair[1]) + " (4.5:1 requis)", "thème")
    return out

func _audit_node(node, out):
    k := node.kind
    name := accessible_name(node)
    if (k == "button" or k == "input" or k == "field" or k == "textarea" or k == "select" or k == "slider" or k == "spinbox") and name == null:
        _problem(out, "erreur", "nom", k + " sans nom accessible (libellé, texte ou placeholder)", k)
    if k == "image":
        alt := _prop(node, "alt")
        if alt == null or _s.trim(str(alt)) == "":
            _problem(out, "erreur", "alternative", "image sans texte alternatif (alt)", k)
    if k == "dialog" and (name == null):
        _problem(out, "erreur", "titre", "dialogue sans titre", k)
    if k == "table":
        cols := _prop(node, "columns")
        if cols == null or len(cols) == 0:
            _problem(out, "avertissement", "en-têtes", "tableau sans en-têtes de colonnes", k)
    if k == "text":
        c := _prop(node, "content")
        if c != null and _s.trim(str(c)) == "":
            _problem(out, "avertissement", "texte vide", "texte vide (élément inutile pour un lecteur d'écran)", k)
    if (k == "field" or k == "input") and _prop(node, "placeholder") != null and _prop(node, "label") == null:
        _problem(out, "avertissement", "étiquette", "champ nommé seulement par son placeholder (il disparaît à la saisie)", k)
    for c in node.children:
        _audit_node(c, out)

func summary(problems):
    e := len([p for p in problems if p["severity"] == "erreur"])
    w := len(problems) - e
    return str(e) + " erreur(s), " + str(w) + " avertissement(s)"
