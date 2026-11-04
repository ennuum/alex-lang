# ALEX STANDARD LIBRARY — web.css
#
# Point d'entrée du paquet web.css : analyser, construire, calculer, valider et produire du CSS, en ALEX pur.
#
# | Module                                    | Rôle                                                          |
# |-------------------------------------------|---------------------------------------------------------------|
# | web.css (ce module)                       | raccourcis : parse, rule, stylesheet, compute, minify, validate |
# | web.css.css_parser / css_writer           | analyse tolérante (CSS Syntax 3, imbrication) / écriture       |
# | web.css.stylesheet                        | feuille de style et CASCADE (style calculé d'un élément)       |
# | web.css.css_rule / at_rule / keyframes    | règles, at-rules, @keyframes (interpolation)                   |
# | web.css.declaration / property / value    | déclarations, base de ~250 propriétés, jetons et valeurs       |
# | web.css.selector / selector_parser        | sélecteurs : analyse, spécificité, correspondance              |
# | web.css.media_query / container_query / supports_query | conditions et leur évaluation       |
# | web.css.color / units / functions / variables | couleurs, unités, calc() & co, var()                     |
# | web.css.css_minifier / css_validate       | minification, validation (Issue)                              |
# | web.css.flexbox / grid / positioning / typography / backgrounds / borders / shadows / transforms /     |
# |   transitions / animations / responsive / theme | constructeurs et calculs spécialisés                  |
# | web.css.css_errors                        | erreurs et Issue                                              |
#
#   use web.css as css
#   sheet := css.parse("p { color: #333 } .note { color: teal }")
#   sheet.rule("a:hover", {"text_decoration": "underline"})
#   css.render(sheet, true)                       # texte indenté
#   css.minify("a { color: #FFFFFF; margin: 0px }")   # a{color:#fff;margin:0}
#   css.validate("a { colr: red }").warnings()    # [unknown-property …]
#   style := css.compute(element, sheet, css.environment(390, 844))   # style calculé
#   css.color("hsl(220 80% 50%)").to_hex()
#   css.matches(element, "nav > a.actif")
#
# Erreurs : CssError, CssParseError, CssSelectorError, CssValueError, CssValidationError.

from core use len, type
use web.css.css_errors as _err
use web.css.css_parser as _parser
use web.css.css_writer as _writer
use web.css.css_minifier as _mini
use web.css.css_validate as _validate
use web.css.stylesheet as _sheet
use web.css.css_rule as _rule
use web.css.at_rule as _at
use web.css.keyframes as _kf
use web.css.declaration as _decl
use web.css.selector as _sel
use web.css.media_query as _mq
use web.css.supports_query as _sq
use web.css.color as _color
use web.css.units as _units
use web.css.functions as _fn
use web.css.value as _value

# ---------------------------------------------------------------- analyse et écriture

func parse(text, issues=null, strict=false):
    return _parser.parse(text, issues, strict)

func parse_declarations(text):
    return _parser.parse_declarations(text)

func stylesheet(rules=null, origin="author"):
    return _sheet.Stylesheet(rules, origin)

func rule(selector, declarations=null):
    return _rule.StyleRule(selector, declarations)

func media(query, rules=null):
    return _at.media(query, rules)

func keyframes(name, frames=null):
    return _kf.Keyframes(name, frames)

func from_dict(spec, pretty=false):
    return _writer.from_dict(spec, _writer.Writer(pretty))

# Texte CSS (feuille, règle, liste de règles ou texte) ; pretty : indenté.
func render(target, pretty=false):
    if type(target) == "str":
        return _writer.write(_parser.parse(target), _writer.Writer(pretty))
    return _writer.write(target, _writer.Writer(pretty))

func pretty(text):
    return render(text, true)

func minify(css, opts=null):
    return _mini.minify(css, opts)

func validate(css, opts=null):
    return _validate.validate(css, opts)

func is_valid(css):
    return _validate.is_valid(css)

func inline_style(props):
    return _writer.inline_style(props)

# ---------------------------------------------------------------- cascade et sélecteurs

func environment(width=1280, height=720, media_type="screen", dpr=1, color_scheme="light"):
    return _mq.Environment(width, height, media_type, dpr, color_scheme)

# Style calculé ; sheets : Stylesheet, liste ou texte CSS ; user_agent : ajoute la feuille par défaut.
func compute(element, sheets, env=null, user_agent=true):
    lst := []
    if user_agent:
        lst = [_sheet.default_stylesheet()]
    if type(sheets) == "str":
        lst = lst + [_parser.parse(sheets)]
    elif isinstance(sheets, _sheet.Stylesheet):
        lst = lst + [sheets]
    else:
        lst = lst + sheets
    return _sheet.compute(element, lst, env)

func matches(element, selector):
    return _sel.matches(element, selector)

func select(root, selector):
    return _sel.select(root, selector)

func specificity(selector):
    return _sel.specificity(selector)

func media_matches(query, env=null):
    return _mq.matches(query, env)

func supports(condition):
    return _sq.supports(condition)

# ---------------------------------------------------------------- valeurs

func color(text):
    return _color.parse(text)

func evaluate(expression, ctx=null):
    return _fn.evaluate(expression, ctx)

func normalize_value(text):
    return _value.normalize(text)

func is_valid_value(property, value):
    return _decl.is_valid_value(property, value)
