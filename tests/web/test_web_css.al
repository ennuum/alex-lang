# ALEX - tests du paquet web.css. Lancer depuis la racine : ./alex run tests/web/test_web_css.al
use testing
use web.css as css
use web.css.color as color
use web.css.units as units
use web.css.value as value
use web.css.property as prop
use web.css.declaration as decl
use web.css.variables as vars
use web.css.functions as fn
use web.css.selector_parser as sp
use web.css.selector as sel
use web.css.css_rule as cr
use web.css.at_rule as at
use web.css.keyframes as kf
use web.css.media_query as mq
use web.css.container_query as cq
use web.css.supports_query as sq
use web.css.stylesheet as ss
use web.css.css_parser as cp
use web.css.css_writer as cw
use web.css.css_minifier as mini
use web.css.css_validate as cv
use web.css.flexbox as fx
use web.css.grid as grid
use web.css.positioning as pos
use web.css.typography as ty
use web.css.backgrounds as bg
use web.css.borders as bd
use web.css.shadows as shd
use web.css.transforms as tf
use web.css.transitions as tr
use web.css.animations as an
use web.css.responsive as rs
use web.css.theme as th
use web.html.html_parser as hp
from core use len
from testing use assert_eq, assert_true, assert_false, assert_null, assert_raises

func near(a, b):
    return a - b < 0.001 and b - a < 0.001

func t_values():
    assert_eq(color.parse("#36c").to_hex(), "#3366cc")
    assert_eq(color.parse("rgb(255 0 0 / 50%)").a, 0.5)
    assert_eq(color.parse("hsl(120 100% 25%)").to_hex(), "#008000")
    assert_true(color.contrast_ratio("#000", "#fff") > 20.9)
    assert_false(color.is_color("rouge"))
    assert_eq(units.to_px(units.parse("2rem")), 32.0)
    assert_eq(fn.evaluate("calc(100% - 2rem)", units.Context(16, 16, 1280, 720, 400)), 368.0)
    assert_eq(fn.evaluate("clamp(16px, 2.5vw, 24px)", units.Context()), 24.0)
    assert_eq(value.normalize("1px   solid\n  red"), "1px solid red")
    assert_eq(prop.canonical("backgroundColor"), "background-color")
    assert_eq(len(prop.expand("margin", "0 auto")), 4)
    assert_eq(decl.parse("color : red !important").important, true)
    assert_eq(decl.value_problem("width", "12"), "nombre sans unité pour une longueur (« 12 »)")
    assert_true(decl.is_valid_value("color", "rgb(1 2 3)"))
    s := vars.Scope({"--a": "1px", "--b": "var(--a) solid"})
    assert_eq(s.resolve("var(--b) var(--c, red)"), "1px solid red")

testing.test("valeurs, couleurs, unités, var()", t_values)

func t_selectors():
    assert_eq(sp.max_specificity("#a .b c:hover"), (1, 2, 1))
    assert_eq(sp.max_specificity(":where(#x) a"), (0, 0, 1))
    assert_false(sp.is_valid("a[)"))
    doc := hp.parse("<ul id=m><li class=a>1</li><li>2</li><li class=a>3</li></ul>")
    assert_eq(len(sel.select(doc, "li.a")), 2)
    assert_eq(sel.first(doc, "li:nth-child(2 of .a)").text_content(), "3")
    assert_eq(len(sel.select(doc, "ul:has(> li.a) li:not(.a)")), 1)

testing.test("sélecteurs", t_selectors)

func t_rules():
    r := cr.StyleRule("a.bouton", {"color": "white", "background_color": "#36c"})
    r.set("color", "#fff", true)
    r.nest("&:hover", {"background-color": "#258"})
    assert_eq(r.get("color"), "#fff")
    assert_eq(r.to_css(cr.Format(false, "", true)), "a.bouton{background-color:#36c;color:#fff!important;&:hover{background-color:#258}}")
    flat := r.flatten()
    assert_eq(flat[1].selector, "a.bouton:hover")
    assert_eq(cr.resolve_nesting("& + &, .x", "a, b"), ":is(a, b) + :is(a, b), :is(a, b) .x")
    m := at.media("(max-width: 600px)", [cr.StyleRule("nav", {"display": "none"})])
    assert_eq(m.to_css(), "@media (max-width: 600px) { nav { display: none; } }")
    assert_eq(at.import_rule("t.css", "screen", "base").to_css(), "@import url(\"t.css\") layer(base) screen;")
    p := cr.StyleRule(".card", {"padding": "1rem"})
    p.add_child(at.media("(min-width: 40em)", [cr.StyleRule("& > h2", {"font-size": "2rem"})]))
    assert_eq(p.flatten()[1].to_css(), "@media (min-width: 40em) { .card > h2 { font-size: 2rem; } }")

testing.test("règles et at-rules", t_rules)

func t_keyframes():
    k := kf.Keyframes("apparition")
    k.frame("from", {"opacity": 0, "transform": "translateY(8px)"}).frame("to", {"opacity": 1, "transform": "translateY(0)"})
    assert_eq(k.at(0.5)["transform"], "translateY(4px)")
    assert_eq(k.at(0.5)["opacity"], "0.5")
    assert_eq(kf.interpolate("10px 0", "20px 4px", 0.25), "12.5px 1px")
    assert_eq(kf.interpolate("block", "none", 0.7), "none")
    assert_eq(kf.interpolate("#000", "#fff", 0.5), "gray")
    assert_eq(len(kf.shake().stops()), 6)
    assert_raises(() => kf.parse_offset("150%"), "CssValueError")

testing.test("@keyframes et interpolation", t_keyframes)

func t_conditions():
    env := mq.Environment(800, 600)
    assert_true(mq.parse("screen and (min-width: 600px), print").matches(env))
    assert_false(mq.matches("(400px <= width < 800px)", env))
    assert_true(mq.matches("(400px <= width <= 800px)", env))
    assert_true(mq.matches("(width >= 50em) and (orientation: landscape)", env))
    assert_true(mq.matches("only screen and ((hover) or (pointer: coarse))", env))
    assert_true(mq.matches("(min-resolution: 2dppx)", mq.mobile_env()))
    assert_false(mq.matches("garbage(((", env))
    assert_false(mq.is_valid("(a) and (b) or (c)"))
    assert_eq(mq.normalize("(width>=600px)"), "(width >= 600px)")
    c := cq.Container(480, 300, "inline-size", ["carte"])
    assert_true(cq.matches("carte (min-width: 400px)", c))
    assert_false(cq.matches("(height > 10px)", c))
    assert_true(cq.matches("style(--theme: sombre)", cq.Container(10, 10, "normal", [], {"--theme": "sombre"})))
    assert_true(sq.supports("((display: grid) and (not (display: inline-grid))) or selector(:has(a))"))
    assert_false(sq.supports("(display: grid) and (color: red) or (x: y)"))
    assert_false(sq.supports("(colour: red)"))
    assert_false(sq.supports("(aspect-ratio: 16 / 9)", sq.Engine(["aspect-ratio"])))

testing.test("@media, @container, @supports", t_conditions)

func t_cascade():
    doc := hp.parse("<html><body><div id=main class=box><p class=note style='margin-left: 3px'>a <em>b</em></p></div></body></html>")
    sh := ss.Stylesheet()
    sh.rule(":root", {"--accent": "tomato", "font-size": "20px"})
    sh.rule("p", {"color": "#333", "margin": "0 0 1em", "font-size": "1.5em"})
    sh.rule("p.note", {"color": "teal"})
    sh.rule("p", {"color": "red !important"})
    sh.rule(".box p", {"border-color": "var(--accent)", "padding": "var(--pad, 2px)"})
    sh.media("(max-width: 600px)").add(cr.StyleRule("p", {"font-size": "14px"}))
    sh.layer("base", [cr.StyleRule("#main p", {"text-align": "center", "line-height": "2"})])
    sh.rule("p", {"text-align": "left"})
    sh.add(at.scope(".box", null, [cr.StyleRule("em", {"font-weight": "900"})]))
    p := sel.first(doc, "p.note")
    st := sh.compute(p, mq.Environment(1000, 800))
    assert_eq(st.get("color"), "red")
    assert_eq(st.get("margin-bottom"), "1em")
    assert_eq(st.get("margin-left"), "3px")
    assert_eq(st.get("margin"), "0 0 1em 3px")
    assert_eq(st.font_size_px, 30.0)
    assert_eq(st.get("border-color"), "tomato")
    assert_eq(st.get("padding-top"), "2px")
    assert_eq(st.get("text-align"), "left")
    assert_eq(st.get("line-height"), "2")
    assert_eq(sh.compute(p, mq.Environment(400, 800)).font_size_px, 14.0)
    em := sel.first(doc, "em")
    se := ss.compute(em, [ss.default_stylesheet(), sh])
    assert_eq(se.get("font-weight"), "900")
    assert_eq(se.get("font-style"), "italic")
    assert_eq(se.get("color"), "red")
    assert_eq(se.variable("accent"), "tomato")
    assert_eq(ss.compute(sel.first(doc, "div"), [ss.default_stylesheet()]).get("display"), "block")
    assert_eq(len(ss.compute_all(doc, sh)), 6)

testing.test("cascade", t_cascade)

func t_parser_writer():
    sheet := cp.parse("a { color: red; &:hover { color: blue } } @media print { nav { display: none } }")
    assert_eq(len(sheet.rules), 2)
    issues := []
    cp.parse("p { color: ; margin: 0 } }", issues)
    assert_eq(issues[0].code, "invalid-declaration")
    assert_eq(len(issues), 2)
    assert_eq(cp.parse_rule("h1, h2 { font-weight: 600 }").selector, "h1, h2")
    assert_eq(cp.parse("@import url(a.css) screen; @layer base;").imports(), ["url(a.css) screen"])
    kfs := cp.parse("@keyframes spin{from{transform:rotate(0)}to{transform:rotate(360deg)}}").find_keyframes("spin")
    assert_eq(len(kfs.frames), 2)
    page := cp.parse("@page :first { margin: 1in; @top-center { content: \"T\" } }")
    assert_eq(page.rules[0].rules[0].name, "top-center")
    assert_raises(() => cp.parse("a { b", null, true), "CssParseError")
    w := cw.Writer(true)
    w.flatten = true
    w.merge_media = true
    out := w.write(cp.parse(".a{color:red; .b &{x:y}} @media print{.a{c:d}} @media print{.e{f:g}}"))
    assert_eq(out, ".a {\n  color: red;\n}\n\n.b .a {\n  x: y;\n}\n\n@media print {\n  .a {\n    c: d;\n  }\n  .e {\n    f: g;\n  }\n}\n")
    assert_eq(cw.from_dict({"body": {"margin": 0}, ".btn": {"color": "red", "&:hover": {"color": "blue"}}}), "body { margin: 0; }\n.btn { color: red; &:hover { color: blue; } }\n")
    assert_eq(cw.inline_style({"color": "red", "font_size": "12px"}), "color: red; font-size: 12px")

testing.test("analyse et écriture", t_parser_writer)

func t_minify_validate():
    assert_eq(mini.minify("a { color: #FFFFFF; margin: 0px 0.5em; }  /* x */ a { padding: 0 }"), "a{color:#fff;margin:0 .5em;padding:0}")
    assert_eq(mini.minify(".x { --c: #FFFFFF ; width: calc(100% - 0px); transition: opacity 0s } .vide {}"), ".x{--c:#FFFFFF;width:calc(100% - 0px);transition:opacity 0s}")
    assert_eq(mini.minify("@media (max-width: 600px){a{b:c}} @media (max-width: 600px){d{e:f}}"), "@media (max-width:600px){a{b:c}d{e:f}}")
    assert_eq(mini.minify("/*! licence */ a{color:red!important;color:blue}"), "/*! licence */a{color:red!important}")
    assert_eq(mini.minify_value("border", "1px solid #ff0000"), "1px solid red")
    r := cv.validate("a { colr: red; width: 12; animation: pop 1s; color: var(--x) } @media screen and {a{b:c}}")
    codes := r.codes()
    assert_true("unknown-property" in codes)
    assert_true("invalid-value" in codes)
    assert_true("undefined-keyframes" in codes)
    assert_true("undefined-variable" in codes)
    assert_true("invalid-media-query" in codes)
    assert_false(r.is_valid())
    assert_true(cv.is_valid("a { color: red; margin: 0 auto }"))
    assert_eq(len(cv.validate_declaration("margin", "0 auto")), 0)

testing.test("minification et validation", t_minify_validate)

func t_layout_builders():
    assert_eq(fx.flex("row", "between", "center", true, "1rem")["justify-content"], "space-between")
    assert_false("flex-direction" in fx.center())
    assert_eq(fx.layout(600, [fx.Item(100), fx.Item(100)], 0, "space-between"), [(0, 100), (500, 100)])
    assert_eq(fx.layout(600, [fx.Item(0, 1, 1, 0, 100), fx.Item(0, 1)], 0), [(0, 100), (100, 500)])
    assert_eq(grid.track_sizes("repeat(auto-fill, minmax(150px, 1fr))", 700, 10), [167.5, 167.5, 167.5, 167.5])
    assert_eq(grid.track_sizes("minmax(300px, 1fr) 3fr", 800), [300.0, 500.0])
    assert_eq(grid.parse_areas("\"a a\" \"b c\"")["a"], (1, 1, 2, 3))
    assert_false(grid.is_valid_areas("\"a b\" \"b a\""))
    assert_eq(pos.default_scale().get("modal"), 50)
    assert_eq(pos.center_absolute()["transform"], "translate(-50%, -50%)")
    assert_eq(ty.fluid(16, 24, 320, 1280), "clamp(1rem, 0.8333rem + 0.8333vw, 1.5rem)")
    assert_eq(ty.fluid_at(16, 24, 800), 20.0)
    assert_eq(ty.weight("semibold"), 600)
    assert_eq(ty.family(["Open Sans", "sans-serif"]), "\"Open Sans\", sans-serif")
    assert_eq(bd.parse("thin dotted rgb(0 0 0 / 50%)"), ("thin", "dotted", "rgb(0 0 0 / 50%)"))
    assert_eq(bd.side("bottom", 2, "dashed", "red"), {"border-bottom": "2px dashed red"})
    assert_eq(bg.image_set({"1x": "a.png", "2x": "b.png"}), "image-set(url(\"a.png\") 1x, url(\"b.png\") 2x)")
    assert_eq(shd.Shadow(0, 4, 12, 0, "#0003").to_css(), "0 4px 12px #0003")
    assert_eq(len(shd.parse("inset 0 1px 0 #fff, 2px 2px red")), 2)
    assert_true(shd.parse("inset 0 1px #fff")[0].inset)

testing.test("flexbox, grid, typographie, bordures, ombres", t_layout_builders)

func t_motion():
    t := tf.Transform().translate(10, 20).rotate(45).scale(2)
    assert_eq(t.to_css(), "translate(10px, 20px) rotate(45deg) scale(2)")
    m := tf.matrix_of("translate(10px, 0) scale(2)")
    assert_eq(m.apply(5, 5), (20.0, 10.0))
    assert_eq(m.to_css(), "matrix(2, 0, 0, 2, 10, 0)")
    assert_eq(m.inverse().apply(20, 10), (5.0, 5.0))
    assert_eq(tf.matrix_of("rotate(90deg)").decompose()["rotate"], 90.0)
    assert_eq(tf.matrix_of("translate(-50%, -50%)", null, (200, 100)).apply(0, 0), (-100.0, -50.0))
    assert_eq(tf.matrix_with_origin("rotate(180deg)", 50, 50).apply(0, 0), (100.0, 100.0))
    assert_true(near(tr.easing("ease-in-out").at(0.5), 0.5))
    assert_true(near(tr.easing("ease").at(0.25), 0.4085))
    assert_true(tr.easing(tr.EASE_OUT_BACK).at(0.5) > 1.0)
    assert_eq(tr.easing("steps(4, jump-end)").at(0.3), 0.25)
    assert_eq(tr.easing("steps(4, jump-start)").at(0.3), 0.5)
    assert_true(near(tr.easing("linear(0, 0.25 75%, 1)").at(0.9), 0.7))
    tt := tr.parse("opacity .3s ease-in 100ms")[0]
    assert_eq(tt.delay, 100.0)
    assert_eq(tt.value_at("0", "1", 50), "0")
    assert_eq(tr.total_duration("opacity 1s, transform 2s 500ms"), 2500.0)
    assert_false(tr.is_valid("opacity 1s 2s 3s"))
    a := an.Animation("apparition", "300ms", "linear", 0, 1, "normal", "both")
    assert_eq(a.state(150)[2], 0.5)
    assert_eq(a.values_at(kf.fade_in(), 150), {"opacity": "0.5"})
    assert_eq(a.values_at(kf.fade_in(), 1000), {"opacity": "1"})
    p := an.parse("pulse 2s ease-in-out 500ms infinite alternate")[0]
    assert_eq(p.iterations, "infinite")
    assert_eq(p.state(100)[0], "avant")
    b := an.Animation("x", "1s", "linear", 0, 2.5, "alternate", "forwards")
    assert_eq(b.state(1250)[2], 0.75)
    assert_eq(b.state(5000), ("après", 2, 0.5))

testing.test("transformations, transitions, animations", t_motion)

func t_responsive_theme():
    bp := rs.Breakpoints()
    assert_eq(bp.up("md"), "(min-width: 768px)")
    assert_eq(bp.down("lg"), "(max-width: 1023.98px)")
    assert_eq(bp.current(900), "md")
    assert_eq(bp.current(100), "base")
    rules := bp.rules(".carte", {"base": {"padding": "1rem"}, "md": {"padding": "2rem"}})
    assert_eq(rules[1].to_css(), "@media (min-width: 768px) { .carte { padding: 2rem; } }")
    assert_eq(rs.Breakpoints(rs.BOOTSTRAP, "em").up("lg"), "(min-width: 62em)")
    t := th.Theme({"color": {"fond": "#fff", "texte": "#1f2937", "accent": "#2563eb", "lien": "{color.accent}"}})
    assert_eq(t.variables()["--color-lien"], "var(--color-accent)")
    assert_eq(t.var("color.accent"), "var(--color-accent)")
    assert_raises(() => t.var("color.inconnue"), "CssValueError")
    t.variant("dark", {"color": {"fond": "#111827", "texte": "#f9fafb"}})
    out := t.to_css()
    assert_true("@media (prefers-color-scheme: dark) { :root:not([data-theme=light])" in out)
    assert_true("[data-theme=dark] {" in out)
    issues := t.contrast_issues([("color.texte", "color.fond"), ("color.accent", "color.fond")])
    assert_eq(len(issues), 1)
    assert_eq(issues[0][3], "dark")
    pal := th.palette("#2563eb")
    assert_eq(pal["500"], "#2563eb")
    assert_eq(len(pal), 11)
    assert_true(color.parse(pal["900"]).luminance() < color.parse(pal["100"]).luminance())

testing.test("responsive et thèmes", t_responsive_theme)

func t_entry():
    sheet := css.parse(":root { --accent: #2563eb; } .carte { padding: 1rem; &:hover { color: red; } @media (width >= 48em) { padding: 2rem; } } .carte h2 { color: var(--accent); font-size: 1.5em; }")
    doc := hp.parse("<div class=carte><h2>Titre</h2></div>")
    h2 := css.select(doc, ".carte h2")[0]
    st := css.compute(h2, sheet, css.environment(1024, 768))
    assert_eq(st.get("color"), "#2563eb")
    assert_eq(st.font_size_px, 24.0)
    assert_eq(st.get("display"), "block")
    carte := css.select(doc, ".carte")[0]
    assert_eq(css.compute(carte, sheet, css.environment(1024, 768)).get("padding-top"), "2rem")
    assert_eq(css.compute(carte, sheet, css.environment(500, 768)).get("padding-top"), "1rem")
    assert_eq(css.minify("a { color: #FFFFFF; margin: 0px }"), "a{color:#fff;margin:0}")
    assert_eq(css.color("hsl(0 100% 50%)").to_hex(), "#ff0000")
    assert_true(css.media_matches("(min-width: 1px)"))
    assert_eq(css.render("a{b:c}", true), "a {\n  b: c;\n}\n")

testing.test("point d'entrée web.css", t_entry)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) web.css en échec")
print("web.css : OK")
