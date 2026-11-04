# ALEX STANDARD LIBRARY — web.html.semantic_elements
#
# Éléments de structure et de texte (WHATWG HTML §4.3 à §4.5) : sections, titres, paragraphes, texte enrichi,
# citations, figures, détails dépliables, dialogues. Chaque fonction accepte le contenu et les attributs dans
# l'ordre que l'on préfère : p("texte"), p("texte", {"class": "x"}), p({"class": "x"}, ["a", em("b")]).
#
#   use web.html.semantic_elements as se
#   page := se.main([
#       se.article({"id": "a1"}, [
#           se.header(se.h1("Titre")),
#           se.p(["Texte ", se.strong("important"), " et ", se.code("x := 1"), "."]),
#           se.figure(img, "Légende"),
#           se.details("Plus d'informations", se.p("Contenu caché")),
#       ]),
#   ])
#   se.heading(2, "Sous-titre")      # <h2>
#   se.time("2024-05-01", "1er mai") # <time datetime="2024-05-01">
#   se.code_block("print(1)", "alex")   # <pre><code class="language-alex">…</code></pre>
#
# Erreurs : HtmlError (niveau de titre hors de 1..6), HtmlTagError.

from core use len, type
use web.html.html_errors as _err
use web.html.element_factory as _f
use web.html.element as _el

func _m(tag, a, b):
    return _f.make(tag, a, b)

# ---------------------------------------------------------------- sections

func header(a=null, b=null):
    return _m("header", a, b)

func footer(a=null, b=null):
    return _m("footer", a, b)

func nav(a=null, b=null):
    return _m("nav", a, b)

func main(a=null, b=null):
    return _m("main", a, b)

func article(a=null, b=null):
    return _m("article", a, b)

func section(a=null, b=null):
    return _m("section", a, b)

func aside(a=null, b=null):
    return _m("aside", a, b)

func search(a=null, b=null):
    return _m("search", a, b)

func address(a=null, b=null):
    return _m("address", a, b)

func hgroup(a=null, b=null):
    return _m("hgroup", a, b)

func div(a=null, b=null):
    return _m("div", a, b)

func span(a=null, b=null):
    return _m("span", a, b)

# ---------------------------------------------------------------- titres

func h1(a=null, b=null):
    return _m("h1", a, b)

func h2(a=null, b=null):
    return _m("h2", a, b)

func h3(a=null, b=null):
    return _m("h3", a, b)

func h4(a=null, b=null):
    return _m("h4", a, b)

func h5(a=null, b=null):
    return _m("h5", a, b)

func h6(a=null, b=null):
    return _m("h6", a, b)

# Titre de niveau 1 à 6.
func heading(level, a=null, b=null):
    if type(level) != "int" or level < 1 or level > 6:
        _err.html_error("semantic_elements.heading", "niveau de titre entre 1 et 6 attendu (obtenu " + str(level) + ")")
    return _m("h" + str(level), a, b)

# ---------------------------------------------------------------- texte

func p(a=null, b=null):
    return _m("p", a, b)

func br():
    return _el.Element("br")

func hr(attributes=null):
    return _el.Element("hr", attributes)

func wbr():
    return _el.Element("wbr")

func strong(a=null, b=null):
    return _m("strong", a, b)

func em(a=null, b=null):
    return _m("em", a, b)

func b(x=null, y=null):
    return _m("b", x, y)

func i(x=null, y=null):
    return _m("i", x, y)

func u(x=null, y=null):
    return _m("u", x, y)

func s(x=null, y=null):
    return _m("s", x, y)

func small(a=null, b=null):
    return _m("small", a, b)

func mark(a=null, b=null):
    return _m("mark", a, b)

func sub(a=null, b=null):
    return _m("sub", a, b)

func sup(a=null, b=null):
    return _m("sup", a, b)

func code(a=null, b=null):
    return _m("code", a, b)

func kbd(a=null, b=null):
    return _m("kbd", a, b)

func samp(a=null, b=null):
    return _m("samp", a, b)

func cite(a=null, b=null):
    return _m("cite", a, b)

func dfn(a=null, b=null):
    return _m("dfn", a, b)

func q(a=null, b=null):
    return _m("q", a, b)

func pre(a=null, b=null):
    return _m("pre", a, b)

# Abréviation avec sa forme longue (title).
func abbr(text, title, attributes=null):
    return _el.Element("abbr", _f.merge_attributes({"title": title}, attributes), text)

# Date / heure lisible par une machine : datetime au format ISO 8601.
func time(datetime, text=null, attributes=null):
    return _el.Element("time", _f.merge_attributes({"datetime": datetime}, attributes), text if text != null else datetime)

# Valeur lisible par une machine (<data value>).
func data(value, text, attributes=null):
    return _el.Element("data", _f.merge_attributes({"value": str(value)}, attributes), text)

func inserted(a=null, b=null):
    return _m("ins", a, b)

func deleted(a=null, b=null):
    return _m("del", a, b)

# Bloc de code : <pre><code class="language-…">…</code></pre> (le code est échappé).
func code_block(source, language=null, attributes=null):
    attrs := {"class": "language-" + language} if language != null else null
    return _el.Element("pre", attributes, [_el.Element("code", attrs, source)])

# Citation longue, avec source (URL) et légende facultatives.
func blockquote(content, cite_url=null, caption=null, attributes=null):
    attrs := _f.merge_attributes({"cite": cite_url}, attributes)
    bq := _el.Element("blockquote", attrs, content)
    if caption == null:
        return bq
    return _el.Element("figure", null, [bq, _el.Element("figcaption", null, caption)])

# ---------------------------------------------------------------- figures, interactifs

# Figure avec légende facultative.
func figure(content, caption=null, attributes=null):
    f := _el.Element("figure", attributes, content)
    if caption != null:
        f.append(_el.Element("figcaption", null, caption))
    return f

# Bloc dépliable : <details><summary>…</summary>…</details>.
func details(summary_content, content=null, open=false, attributes=null):
    attrs := _f.merge_attributes({"open": open}, attributes)
    d := _el.Element("details", attrs, [_el.Element("summary", null, summary_content)])
    if content != null:
        d.append(content)
    return d

# Boîte de dialogue ; modal=false : ouverte d'emblée (attribut open).
func dialog(content, open=false, attributes=null):
    return _el.Element("dialog", _f.merge_attributes({"open": open}, attributes), content)

# Barre de progression / jauge.
func progress(value=null, max=1.0, label=null, attributes=null):
    attrs := _f.merge_attributes({"value": value, "max": max}, attributes)
    return _el.Element("progress", attrs, label)

func meter(value, min=0, max=1, low=null, high=null, optimum=null, label=null, attributes=null):
    attrs := _f.merge_attributes({"value": value, "min": min, "max": max, "low": low, "high": high, "optimum": optimum}, attributes)
    return _el.Element("meter", attrs, label)

# Annotation ruby (prononciation) : ruby("漢字", "かんじ").
func ruby(base, annotation):
    return _el.Element("ruby", null, [base, _el.Element("rp", null, "("), _el.Element("rt", null, annotation), _el.Element("rp", null, ")")])

# Fil d'Ariane accessible : liste de (texte, href) ; le dernier est la page courante.
func breadcrumb(items, label="Fil d'Ariane"):
    ol := _el.Element("ol")
    n := len(items)
    k := 0
    for it in items:
        k += 1
        if k == n:
            ol.append(_el.Element("li", null, [_el.Element("span", {"aria-current": "page"}, it[0])]))
        else:
            ol.append(_el.Element("li", null, [_el.Element("a", {"href": it[1]}, it[0])]))
    return _el.Element("nav", {"aria-label": label}, [ol])
