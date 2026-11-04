# ALEX STANDARD LIBRARY — ui.ui_renderer
#
# Rendus d'une interface ui.view SANS écran, pour les tests, la documentation et l'export :
#   render_text(vue, l, h)   l'écran réel produit par le moteur terminal (tui) sur un terminal virtuel
#   render_screen_html(...)  le même écran en HTML (couleurs comprises)
#   to_html(vue)             export HTML SÉMANTIQUE (flexbox, boutons, champs, tableaux...) d'une page statique
#   outline(vue)             plan indenté de l'arbre (genre, texte, identifiant)
#   to_dict / to_json / from_dict   sérialisation de l'arbre (les fonctions de rappel sont omises)
#   diff(a, b)               différences entre deux arbres (tests de non-régression d'interface)
#   register(nom, fn) / render(nom, vue)   moteurs de rendu nommés supplémentaires
#
#   use ui.view as v
#   use ui.ui_renderer as ur
#   func vue():
#       return v.column([v.text("Bonjour", style="title"), v.button("OK", null)], padding=1)
#   print(ur.render_text(vue, 40, 6))       # lignes du terminal virtuel
#   io.write_file("apercu.html", ur.to_html(vue, "Aperçu"))
#   print(ur.outline(vue))                  # column / text « Bonjour » (title) / button « OK »
#   print(ur.diff(vue_avant(), vue_apres()))
#
# Erreurs : ArgumentError (moteur inconnu), TypeError (vue invalide).

from core use len, type
from collections use append
use string as _s
use json as _json
use ui.view.node as _n
use tui as _TUI

func _node(view_or_node):
    n := view_or_node
    if type(n) == "function":
        n = n()
    return _n.coerce(n)

# ---- rendu réel par le moteur terminal ----

func render_text(view, width=80, height=24, theme="dark"):
    v := view
    if type(view) != "function":
        nd := view
        v = () => nd
    app := _TUI.TestApp(v, width, height, theme)
    return app.lines()

func render_screen_html(view, width=80, height=24, theme="dark"):
    v := view
    if type(view) != "function":
        nd := view
        v = () => nd
    return _TUI.TestApp(v, width, height, theme).html()

# ---- plan ----
func _label(n):
    for k in ["content", "label", "title", "value", "placeholder", "alt"]:
        v := n.get(k, null)
        if type(v) == "str" and v != "":
            return v
    return null

func outline(view_or_node):
    lines := []
    _outline(_node(view_or_node), 0, lines)
    return _s.join("\n", lines)

func _outline(n, depth, lines):
    t := _s.repeat("  ", depth) + n.kind
    l := _label(n)
    if l != null:
        t += " « " + l + " »"
    st := n.get("style", null)
    if st != null:
        t += " (" + str(st) + ")"
    if n.id != null:
        t += " #" + str(n.id)
    append(lines, t)
    for c in n.children:
        _outline(c, depth + 1, lines)

# ---- sérialisation ----
func _clean(v):
    t := type(v)
    if t == "function":
        return null
    if t == "list" or t == "tuple":
        return [_clean(x) for x in v]
    if t == "dict":
        out := {}
        for k in v:
            if type(v[k]) != "function":
                out[k] = _clean(v[k])
        return out
    if _n.is_node(v):
        return to_dict(v)
    if t == "char":
        return str(v)
    return v

func to_dict(view_or_node):
    n := _node(view_or_node)
    props := {}
    for k in n.props:
        if type(n.props[k]) != "function":
            props[k] = _clean(n.props[k])
    return {"kind": n.kind, "props": props, "children": [to_dict(c) for c in n.children]}

func to_json(view_or_node, indent=null):
    return _json.stringify(to_dict(view_or_node), indent)

func from_dict(d):
    return _n.Node(d["kind"], d["props"], [from_dict(c) for c in d["children"]])

# ---- différences ----
func diff(a, b):
    out := []
    _diff(to_dict(a), to_dict(b), "racine", out)
    return out

func _diff(x, y, path, out):
    if x["kind"] != y["kind"]:
        append(out, path + " : genre " + x["kind"] + " -> " + y["kind"])
        return
    for k in x["props"]:
        if not (k in y["props"]):
            append(out, path + "." + k + " : supprimé")
        elif not (x["props"][k] == y["props"][k]):
            append(out, path + "." + k + " : " + str(x["props"][k]) + " -> " + str(y["props"][k]))
    for k in y["props"]:
        if not (k in x["props"]):
            append(out, path + "." + k + " : ajouté (" + str(y["props"][k]) + ")")
    nx := len(x["children"])
    ny := len(y["children"])
    i := 0
    while i < nx and i < ny:
        _diff(x["children"][i], y["children"][i], path + "/" + x["children"][i]["kind"] + "[" + str(i) + "]", out)
        i += 1
    while i < nx:
        append(out, path + "/" + x["children"][i]["kind"] + "[" + str(i) + "] : retiré")
        i += 1
    while i < ny:
        append(out, path + "/" + y["children"][i]["kind"] + "[" + str(i) + "] : ajouté")
        i += 1

# ---- HTML sémantique ----
func escape(text):
    t := str(text)
    t = _s.replace(t, "&", "&amp;")
    t = _s.replace(t, "<", "&lt;")
    t = _s.replace(t, ">", "&gt;")
    t = _s.replace(t, "\"", "&quot;")
    return t

const CSS := "body{font-family:system-ui,sans-serif;margin:16px;background:#fff;color:#1d1f23}.col{display:flex;flex-direction:column;gap:8px}.row{display:flex;flex-direction:row;gap:8px;align-items:center}.title{font-size:1.4em;font-weight:600}.subtitle{font-size:1.15em;font-weight:600}.muted{color:#666}.error{color:#b00020}.success{color:#1b7f3a}.warning{color:#9a6700}.code{font-family:monospace}fieldset{border:1px solid #ccc;border-radius:6px}button.primary{font-weight:600}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:2px 6px}.dialog{border:2px solid #444;border-radius:8px;padding:12px;max-width:40em}"

func to_html(view_or_node, title="Interface ALEX"):
    body := _html(_node(view_or_node))
    return "<!doctype html>\n<html lang=\"fr\"><head><meta charset=\"utf-8\"><title>" + escape(title) + "</title><style>" + CSS + "</style></head>\n<body>\n" + body + "\n</body></html>\n"

func _attrs(n):
    out := ""
    if n.id != null:
        out += " id=\"" + escape(n.id) + "\""
    return out

func _kids(n):
    return _s.join("\n", [_html(c) for c in n.children])

func _html(n):
    k := n.kind
    a := _attrs(n)
    if k == "text":
        cls := n.get("style", null)
        tag := "p"
        if cls == "title":
            tag = "h1"
        elif cls == "subtitle":
            tag = "h2"
        c := ""
        if cls != null and tag == "p":
            c = " class=\"" + escape(cls) + "\""
        return "<" + tag + a + c + ">" + escape(n.get("content", "")) + "</" + tag + ">"
    if k == "button":
        c := ""
        if n.get("primary", false):
            c = " class=\"primary\""
        dis := ""
        if n.get("enabled", true) == false:
            dis = " disabled"
        return "<button" + a + c + dis + ">" + escape(n.get("label", "")) + "</button>"
    if k == "input" or k == "field":
        t := "text"
        if n.get("password", false):
            t = "password"
        return "<input" + a + " type=\"" + t + "\" value=\"" + escape(n.get("value", "")) + "\" placeholder=\"" + escape(n.get("placeholder", "")) + "\" aria-label=\"" + escape(n.get("placeholder", "")) + "\">"
    if k == "textarea" or k == "code_editor":
        return "<textarea" + a + ">" + escape(n.get("value", "")) + "</textarea>"
    if k == "checkbox":
        ch := ""
        if n.get("checked", false):
            ch = " checked"
        return "<label" + a + "><input type=\"checkbox\"" + ch + "> " + escape(n.get("label", "")) + "</label>"
    if k == "radio" or k == "select":
        opts := n.get("options", [])
        sel := n.get("selected", 0)
        if k == "select":
            items := []
            i := 0
            for o in opts:
                s := ""
                if i == sel:
                    s = " selected"
                append(items, "<option" + s + ">" + escape(o) + "</option>")
                i += 1
            return "<select" + a + ">" + _s.join("", items) + "</select>"
        items := []
        i := 0
        for o in opts:
            s := ""
            if i == sel:
                s = " checked"
            append(items, "<label><input type=\"radio\" name=\"r" + str(n.path) + "\"" + s + "> " + escape(o) + "</label>")
            i += 1
        return "<div" + a + " class=\"row\" role=\"radiogroup\">" + _s.join("", items) + "</div>"
    if k == "slider" or k == "spinbox":
        t := "range"
        if k == "spinbox":
            t = "number"
        return "<input" + a + " type=\"" + t + "\" min=\"" + str(n.get("min", 0)) + "\" max=\"" + str(n.get("max", 100)) + "\" value=\"" + str(n.get("value", 0)) + "\">"
    if k == "progress":
        return "<progress" + a + " max=\"1\" value=\"" + str(n.get("value", 0)) + "\"></progress>"
    if k == "image":
        return "<img" + a + " src=\"" + escape(n.get("path", "")) + "\" alt=\"" + escape(n.get("alt", "")) + "\" width=\"" + str(n.get("px_width", 64)) + "\">"
    if k == "separator":
        return "<hr" + a + ">"
    if k == "spacer":
        return "<div" + a + " style=\"flex:" + str(n.get("flex", 1)) + "\"></div>"
    if k == "list_view":
        return "<ul" + a + ">" + _s.join("", ["<li>" + escape(x) + "</li>" for x in n.get("items", [])]) + "</ul>"
    if k == "table":
        head := "<tr>" + _s.join("", ["<th>" + escape(c) + "</th>" for c in n.get("columns", [])]) + "</tr>"
        rows := _s.join("", ["<tr>" + _s.join("", ["<td>" + escape(c) + "</td>" for c in r]) + "</tr>" for r in n.get("rows", [])])
        return "<table" + a + ">" + head + rows + "</table>"
    if k == "column" or k == "scroll" or k == "split":
        return "<div" + a + " class=\"col\">\n" + _kids(n) + "\n</div>"
    if k == "row":
        return "<div" + a + " class=\"row\">\n" + _kids(n) + "\n</div>"
    if k == "panel":
        leg := ""
        if n.get("title", null) != null:
            leg = "<legend>" + escape(n.get("title", "")) + "</legend>"
        return "<fieldset" + a + ">" + leg + "\n" + _kids(n) + "\n</fieldset>"
    if k == "dialog":
        btns := _s.join("", ["<button>" + escape(b[0]) + "</button>" for b in n.get("buttons", [])])
        return "<div" + a + " class=\"dialog\" role=\"dialog\" aria-label=\"" + escape(n.get("title", "")) + "\"><h2>" + escape(n.get("title", "")) + "</h2>\n" + _kids(n) + "\n<div class=\"row\">" + btns + "</div></div>"
    if k == "tabs":
        return "<div" + a + " class=\"col\" role=\"tablist\">\n" + _kids(n) + "\n</div>"
    return "<div" + a + " data-kind=\"" + escape(k) + "\">\n" + _kids(n) + "\n</div>"

# ---- moteurs nommés ----
_renderers := {}

func register(name, fn):
    if type(fn) != "function":
        raise("TypeError", "register : fonction attendue")
    _renderers[name] = fn

func renderers():
    return ["text", "screen_html", "html", "outline", "json"] + [k for k in _renderers]

func render(name, view, width=80, height=24):
    if name == "text":
        return _s.join("\n", render_text(view, width, height))
    if name == "screen_html":
        return render_screen_html(view, width, height)
    if name == "html":
        return to_html(view)
    if name == "outline":
        return outline(view)
    if name == "json":
        return to_json(view)
    if name in _renderers:
        f := _renderers[name]
        return f(_node(view))
    raise("ArgumentError", "moteur de rendu inconnu : " + name)
