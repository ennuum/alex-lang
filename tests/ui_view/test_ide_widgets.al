from core use len
from collections use append, contains_key
use ui.view as v
use gui
use testing
use os
use _native_ui as _ui

etat := {"code": "use math\n\nfunc aire(r):\n    return math.PI * r * r\n\nfunc main():\n    x := aire(2)\n    print(x)\n\nmain()\n", "bps": [{"line": 4}, {"line": 7, "condition": "r > 1"}], "gutter": [], "def": null, "cur": null, "goto": null}

func gutter(l):
    append(etat["gutter"], l)

func provider(l, c, prefix, member):
    if member:
        return [{"label": "PI", "detail": "const float"}, {"label": "sqrt", "detail": "func sqrt(x)", "insert": "sqrt(${1:x})"}]
    return ["aire", "main"]

func hover(l, c):
    return "```alex\nfunc aire(r)\n```\nCalcule l'aire du disque."

func definition(l, c):
    etat["def"] = [l, c]

func change(t):
    etat["code"] = t

func cursor(l, c):
    etat["cur"] = [l, c]

func vue():
    return v.column([
        v.row([v.image("tools/branding/alex_logo_48.png", 40, 40, alt="ALEX"), v.text("Test IDE", style="title")]),
        v.code_editor(etat["code"], change, on_cursor=cursor, breakpoints=etat["bps"], on_gutter=gutter, exec_line=7,
                      markers=[{"line": 8, "col": 11, "end_col": 12, "kind": "warning", "message": "variable"}, {"line": 4, "col": 12, "end_col": 14, "kind": "error", "message": "type"}],
                      highlights=[[3, 6, 10], [7, 10, 14]], completion_provider=provider, on_hover=hover, on_definition=definition, goto=etat["goto"], id="ed"),
        v.canvas((p) => p.fill(4, 4, p.width - 8, 20, "#1e6bff", 6), px_height=28),
    ], padding=1)

t := gui.TestApp(vue, 820, 520, "studio")
# clic dans la colonne des points d'arrêt, ligne 3
ed := t.app.find("aire")
os.mkdir_all("/tmp/alex_ide_widgets")
t.screenshot("/tmp/alex_ide_widgets/ide1.png")
func test_gutter():
    n := null
    for p in t.app.placed:
        if p.kind == "code_editor":
            n = p
    lh := t.app.s.line_height("mono")
    y := n.y + 1 + 4 + 2 * lh + lh // 2
    t.click(n.x + 6, y)
    testing.assert_eq(etat["gutter"], [3])

func test_completion_member():
    etat["goto"] = [4, 21, 1]
    t.step()
    testing.assert_eq(etat["cur"], [4, 21])
    t.app.focus = "r.1"
    for p in t.app.placed:
        if p.kind == "code_editor":
            t.app.focus = p.path
    t.press("end")
    t.type(" + math.")
    t.screenshot("/tmp/alex_ide_widgets/ide2.png")
    testing.assert_true(t.contains("sqrt"))
    testing.assert_true(t.contains("func sqrt(x)"))
    t.press("down")
    t.press("enter")
    testing.assert_true(etat["code"] != null)

func test_hover():
    n := null
    for p in t.app.placed:
        if p.kind == "code_editor":
            n = p
    lh := t.app.s.line_height("mono")
    cw := t.app.s.text_width("M", "mono")
    # survol de « aire » à la ligne 7
    x := n.x + 1 + t.app.widget(n)._gutter(t.app, n, 11) + 10 * cw
    y := n.y + 1 + 4 + 6 * lh + lh // 2
    _ui.inject_mouse(t.win, "move", x, y, 1, 0)
    t.step()
    os.sleep(0.5)
    t.step()
    t.screenshot("/tmp/alex_ide_widgets/ide_hover.png")
    testing.assert_true(t.contains("Calcule l'aire du disque."))

func test_ctrl_click():
    n := null
    for p in t.app.placed:
        if p.kind == "code_editor":
            n = p
    lh := t.app.s.line_height("mono")
    cw := t.app.s.text_width("M", "mono")
    x := n.x + 1 + t.app.widget(n)._gutter(t.app, n, 11) + 10 * cw
    y := n.y + 1 + 4 + 6 * lh + lh // 2
    _ui.inject_mouse(t.win, "click", x, y, 1, 2)
    t.step()
    testing.assert_eq(etat["def"][0], 7)
    testing.assert_true(etat["def"][1] >= 10 and etat["def"][1] <= 13)

func test_image_canvas():
    testing.assert_true(t.contains("Test IDE"))

testing.test("gouttière", test_gutter)
testing.test("survol", test_hover)
testing.test("ctrl+clic", test_ctrl_click)
testing.test("image et canvas", test_image_canvas)
testing.test("complétion membre", test_completion_member)
echecs := testing.run(true)
sm := testing.summary()
print("composants IDE : " + str(sm["passed"]) + " OK, " + str(echecs) + " échecs")
