# Test de la couche terminal bas niveau : tui.width, tui.style, tui.input, tui.screen (+ émulateur),
# tui.terminal (terminal virtuel), tui.markup et tui.inline (composants en ligne, clavier virtuel).

from core use len, type
from collections use append
use string as s
use random
use tui.width as w
use tui.style as st
use tui.input as inp
use tui.screen as screen
use tui.terminal as terminal
use tui.markup as mk
use tui.inline as il

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

func keys(evs):
    return [e["key"] if e["type"] == "key" else e["type"] for e in evs]

func test_width():
    check_eq([w.of("abc"), w.of("日本"), w.of("été"), w.of("é"), w.of("😀")], [3, 4, 3, 1, 2], "largeurs (CJK, combinant, émoji)")
    check_eq(w.truncate("bonjour", 5), "bonj…", "truncate")
    check_eq(w.truncate("日本語", 5), "日本…", "truncate d'un texte large")
    check_eq(w.pad("ab", 5, "right"), "   ab", "pad à droite")
    check_eq(w.wrap("un texte assez long", 8), ["un texte", "assez", "long"], "wrap")

func test_style():
    check_eq(st.style("red", null, true), "1;31", "style nommé + gras")
    check_eq(st.style("#ff8800", "blue"), "38;2;255;136;0;44", "couleur 24 bits + fond")
    check_eq(st.downgrade("38;2;255;0;0", "256"), "38;5;196", "réduction en 256 couleurs")
    check_eq(st.downgrade("1;38;2;255;0;0;48;5;21", "none"), "1", "sans couleurs : attributs seulement")
    d := st.decode("1;38;2;10;20;30;48;5;196;7")
    check_eq([d["bold"], d["fg"], d["bg"], d["reverse"]], [true, "#0a141e", "#ff0000", true], "decode")

func test_input():
    evs := inp.decode("a\r\t\x7f\e[A\e[1;5C\e[Z\e[3~\e[5;2~\eOP\exé\x03")
    check_eq(keys(evs), ["a", "enter", "tab", "backspace", "up", "ctrl+right", "shift+tab", "delete", "shift+page_up", "f1", "alt+x", "é", "ctrl+c"], "touches et modificateurs")
    m := inp.decode("\e[<0;5;3M\e[<32;6;3M\e[<0;6;3m\e[<64;1;1M")
    check_eq([[e["action"], e["x"], e["y"]] for e in m], [["down", 4, 2], ["drag", 5, 2], ["up", 5, 2], ["wheel", 0, 0]], "souris SGR")
    check_eq(m[3]["dy"], 1, "molette vers le haut")
    p := inp.decode("\e[200~coll\né\e[201~")
    check_eq([p[0]["type"], p[0]["text"]], ["paste", "coll\né"], "collage")
    d := inp.Decoder()
    check_eq([len(d.feed("\e[")), d.waiting(), keys(d.feed("B"))], [0, true, ["down"]], "séquence en deux morceaux")
    d.feed("\e")
    check_eq(keys(d.flush()), ["escape"], "Échap seul")

func test_screen():
    b := screen.Buffer(20, 5)
    b.box(0, 0, 20, 5, "", "round", "Titre")
    b.text(2, 2, "日本 été", st.style("green"))
    check_eq(b.lines()[0], "╭─ Titre ──────────╮", "cadre avec titre")
    check_eq(b.lines()[2], "│ 日本 été         │", "texte large dans le tampon")
    b.push_clip(2, 3, 3, 1)
    b.text(0, 3, "abcdefgh")
    b.pop_clip()
    check_eq(b.lines()[3], "│ cde              │", "découpe")
    # rendu différentiel rejoué par l'émulateur : même écran, mêmes styles
    vt := terminal.VirtualTerminal(30, 8, true)
    buf := screen.Buffer(30, 8)
    ok := true
    random.seed(7)
    for frame in 0..30:
        for k in 0..5:
            words := ["ab", "日本", "été", "x", "😀ok", "──"]
            buf.text(random.randint(0, 29), random.randint(0, 7), words[random.randint(0, 5)], st.style(random.randint(0, 15)))
        vt.present(buf)
        if vt.emulator.lines() != buf.lines():
            ok = false
    check(ok, "render_diff + émulateur : 30 images identiques")
    check(len(vt.output[len(vt.output) - 1]) < 400, "seules les cellules modifiées sont réécrites")
    html := screen.to_html(buf)
    check(s.starts_with(html, "<pre") and s.contains(html, "</span>"), "capture HTML")

func test_terminal():
    vt := terminal.VirtualTerminal(20, 4)
    vt.key("ctrl+s")
    vt.type_text("a b")
    vt.click(3, 1)
    vt.feed("\e[B")
    evs := [vt.read() for i in 0..7]
    check_eq([e["key"] if e["type"] == "key" else e["action"] for e in evs], ["ctrl+s", "a", "space", "b", "down", "up", "down"], "injection d'événements")
    check_eq(vt.read(), null, "file vide")
    b := screen.Buffer(20, 4)
    b.text(5, 2, "trouvé")
    vt.present(b)
    check_eq([vt.contains("trouvé"), vt.find("trouvé")], [true, [5, 2]], "contains / find")

func test_markup():
    check_eq(mk.strip("[bold red]Erreur[/] : [i]x[/i] \\[pas une balise]"), "Erreur : x [pas une balise]", "strip et échappement")
    check_eq(mk.width("[bold]日本[/]"), 4, "largeur sans balises")
    r := mk.render("[bold green]ok[/] [black on yellow]!![/]", "truecolor")
    check(s.contains(r, "\e[0;1;32m") and s.contains(r, "ok") and s.contains(r, "\e[0;30;43m"), "render en ANSI")
    check_eq(mk.render("[red]x[/]", "none"), "x", "sans couleurs : texte nu")
    b := screen.Buffer(10, 1)
    mk.draw(b, 0, 0, "[red]a[/]b")
    check_eq([b.lines()[0], b.style_at(0, 0), b.style_at(1, 0)], ["ab", "31", ""], "draw dans un tampon")

func test_inline():
    il.use_virtual(["down", "down", "enter"])
    check_eq(il.select("Langage ?", ["Alex", "Python", "Rust", "Go"]), 2, "select : ↓ ↓ Entrée")
    check_eq(il.screen_lines(), ["✔ Langage ? Rust"], "select : ligne finale")
    il.use_virtual(["text:ru", "enter"])
    check_eq(il.select("Langage ?", ["Alex", "Python", "Rust", "Go"]), 2, "select : filtre par saisie")
    il.use_virtual(["escape"])
    check_eq(il.select("?", ["a", "b"]), null, "select : Échap annule")
    il.use_virtual(["space", "down", "down", "space", "enter"])
    check_eq(il.multi_select("Options ?", ["a", "b", "c"]), [0, 2], "multi_select")
    il.use_virtual(["text:12a", "enter", "backspace", "enter"])
    check_eq(il.number("Âge ?", null, 0, 150, true), 12, "number : saisie invalide refusée puis corrigée")
    il.use_virtual(["text:py", "tab", "enter"])
    check_eq(il.prompt("Langage", null, null, false, ["python", "pytorch", "rust"]), "pyt", "prompt : Tab complète le préfixe commun")
    il.use_virtual(["enter"])
    check_eq(il.confirm("Continuer ?", true), true, "confirm : Entrée = défaut")
    il.use_virtual(["n"])
    check_eq(il.confirm("Continuer ?", true), false, "confirm : n")
    il.use_virtual(["text:abc", "left", "ctrl+w", "enter"])
    check_eq(il.prompt("Mot de passe", null, null, true), "c", "prompt mot de passe : édition")
    check_eq(il.screen_lines(), ["✔ Mot de passe •"], "mot de passe masqué")
    il.use_virtual([], 60)
    t := mk.strip(il.table([["Alex", 1, 3.14159], ["Python", 22, 2.5]], ["Nom", "N", "Valeur"]))
    check_eq(s.split(t, "\n"), ["╭────────┬────┬────────╮", "│ Nom    │  N │ Valeur │", "├────────┼────┼────────┤", "│ Alex   │  1 │   3.14 │", "│ Python │ 22 │    2.5 │", "╰────────┴────┴────────╯"], "table")
    check_eq(s.split(mk.strip(il.tree(["racine", ["a", ["b", ["c", "d"]], "e"]])), "\n"), ["racine", "├── a", "├── b", "│   ├── c", "│   └── d", "└── e"], "tree")
    check_eq(s.split(mk.strip(il.panel("Bonjour\nligne 2", "Titre")), "\n")[0], "╭─ Titre ─╮", "panel")
    check_eq(mk.strip(il.rule("Section", 30)), "────────── Section ───────────", "rule")
    check_eq(s.split(il.columns(["un", "deux", "trois", "quatre", "cinq"], 20), "\n"), ["un      quatre", "deux    cinq", "trois"], "columns")
    pb := il.ProgressBar(200, "Copie")
    pb.set(50)
    check(s.contains(mk.strip(pb.line()), "25%") or s.contains(mk.strip(pb.line()), "25 %"), "ProgressBar : pourcentage")
    il.use_terminal()

func main():
    test_width()
    test_style()
    test_input()
    test_screen()
    test_terminal()
    test_markup()
    test_inline()
    print(f"tui (bas niveau) : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_tui : échecs")

main()
