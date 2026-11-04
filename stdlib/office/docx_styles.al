# ALEX STANDARD LIBRARY — office.docx_styles
# Styles WordprocessingML (word/styles.xml) : modèle Style, jeu de styles par défaut (Normal, Titre 1..6, Titre,
# Sous-titre, Citation, Légende, Liste, Code, Lien hypertexte, Grille du tableau...), lecture et écriture.
#
#   use office.docx_styles as styles
#   s := styles.Style("Alerte", "Alerte", "paragraph")
#   s.based_on = "Normal"
#   s.bold = true
#   s.color = "C00000"
#   doc.styles.add(s)                                  # voir word.WordDocument
#   styles.heading_id(2)                               # "Heading2"
#
# Style(id, name, type="paragraph")  champs : id name type ("paragraph" | "character" | "table" | "numbering")
#   based_on next link ui_priority quick (affiché dans la galerie) · police : font size (pt) bold italic underline
#   strike color caps small_caps highlight · paragraphe : align space_before space_after (pt) line_spacing
#   (multiple, ex. 1.15, ou "14pt" exact) indent_left indent_right indent_first (pt) keep_next keep_lines
#   outline_level (0 = niveau 1) page_break_before · table : borders (bool) cell_margin (pt)
#   to_xml() -> nœud w:style   from_xml(nœud) -> Style
# StyleSheet : add(style)  get(id)  find(nom_ou_id)  has(id)  ids()  remove(id)  default_font  default_size  language
#   to_xml() -> nœud w:styles   resolve(id) -> dict des propriétés effectives (héritage based_on)
# Fonctions : default_styles(font="Calibri", size=11, language="fr-FR") -> StyleSheet
#   parse(texte_xml) -> StyleSheet   heading_id(niveau)   run_props_xml(dict) / para_props_xml(dict) (partagées
#   avec docx_paragraphs)   read_run_props(nœud_rPr) / read_para_props(nœud_pPr) -> dict
# Erreurs : DOCXError, ValueError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use office.errors as errors
use office.utils as u
use office.xml as x

func heading_id(level):
    if type(level) != "int" or level < 1 or level > 9:
        raise("ValueError", "niveau de titre 1..9 attendu (obtenu " + str(level) + ")")
    return "Heading" + str(level)

func _pt_to_twips(v):
    return to_int(u.round_to(u.to_unit(u.length(v, "pt"), "tw"), 0))

func _half_points(v):
    return to_int(u.round_to(u.emu_to_pt(u.length(v, "pt")) * 2.0, 0))

func _w(tag, val):
    return x.el(tag, {"w:val": val})

func _on(tag, flag):
    if flag:
        return x.el(tag)
    return x.el(tag, {"w:val": "0"})

const _HIGHLIGHTS := ["black", "blue", "cyan", "green", "magenta", "red", "yellow", "white", "darkBlue", "darkCyan", "darkGreen", "darkMagenta", "darkRed", "darkYellow", "darkGray", "lightGray"]

func _highlight_name(c):
    for h in _HIGHLIGHTS:
        if string.lower(h) == string.lower(c):
            return h
    hexv := u.color_hex(c)
    if hexv == "FFFF00":
        return "yellow"
    if hexv == "00FF00":
        return "green"
    if hexv == "00FFFF":
        return "cyan"
    if hexv == "FF00FF":
        return "magenta"
    if hexv == "FF0000":
        return "red"
    if hexv == "0000FF":
        return "blue"
    if hexv == "D3D3D3" or hexv == "C0C0C0":
        return "lightGray"
    if hexv == "808080":
        return "darkGray"
    if hexv == "000000":
        return "black"
    if hexv == "FFFFFF":
        return "white"
    return "yellow"

# Propriétés de caractère (dict) -> w:rPr (ordre du schéma ECMA-376). Clés reconnues : style font size bold italic
# underline strike double_strike caps small_caps hidden color highlight superscript subscript spacing language
# (une valeur null ou absente est ignorée ; false est écrit explicitement pour annuler un style hérité).
func run_props_xml(p):
    kids := []
    g := (k) => u.get(p, k, null) if p != null else null
    if g("style") != null:
        append(kids, _w("w:rStyle", g("style")))
    if g("font") != null:
        f := g("font")
        append(kids, x.el("w:rFonts", {"w:ascii": f, "w:hAnsi": f, "w:eastAsia": f, "w:cs": f}))
    if p != null and contains_key(p, "bold") and p["bold"] != null:
        append(kids, _on("w:b", p["bold"]))
        append(kids, _on("w:bCs", p["bold"]))
    if p != null and contains_key(p, "italic") and p["italic"] != null:
        append(kids, _on("w:i", p["italic"]))
        append(kids, _on("w:iCs", p["italic"]))
    if p != null and contains_key(p, "caps") and p["caps"] != null:
        append(kids, _on("w:caps", p["caps"]))
    if p != null and contains_key(p, "small_caps") and p["small_caps"] != null:
        append(kids, _on("w:smallCaps", p["small_caps"]))
    if p != null and contains_key(p, "strike") and p["strike"] != null:
        append(kids, _on("w:strike", p["strike"]))
    if p != null and contains_key(p, "double_strike") and p["double_strike"] != null:
        append(kids, _on("w:dstrike", p["double_strike"]))
    if p != null and contains_key(p, "hidden") and p["hidden"] != null:
        append(kids, _on("w:vanish", p["hidden"]))
    if g("color") != null:
        append(kids, _w("w:color", u.color_hex(g("color"))))
    if g("spacing") != null:
        append(kids, _w("w:spacing", str(_pt_to_twips(g("spacing")))))
    if g("size") != null:
        hp := str(_half_points(g("size")))
        append(kids, _w("w:sz", hp))
        append(kids, _w("w:szCs", hp))
    if g("highlight") != null:
        append(kids, _w("w:highlight", _highlight_name(g("highlight"))))
    if p != null and contains_key(p, "underline") and p["underline"] != null:
        un := p["underline"]
        if un == true:
            un = "single"
        elif un == false:
            un = "none"
        append(kids, _w("w:u", un))
    if g("superscript") == true:
        append(kids, _w("w:vertAlign", "superscript"))
    elif g("subscript") == true:
        append(kids, _w("w:vertAlign", "subscript"))
    if g("language") != null:
        append(kids, _w("w:lang", g("language")))
    if len(kids) == 0:
        return null
    return x.el("w:rPr", null, kids)

func _align_val(a):
    if a == null:
        return null
    l := string.lower(a)
    if l == "left" or l == "gauche" or l == "start":
        return "left"
    if l == "center" or l == "centre" or l == "centré":
        return "center"
    if l == "right" or l == "droite" or l == "end":
        return "right"
    if l == "justify" or l == "both" or l == "justifié" or l == "justifie":
        return "both"
    if l == "distribute":
        return "distribute"
    raise("ValueError", "alignement inconnu : '" + a + "' (left, center, right, justify)")

# Propriétés de paragraphe (dict) -> w:pPr. Clés : style keep_next keep_lines page_break_before num_id num_level
# border_bottom shading space_before space_after line_spacing indent_left indent_right indent_first align
# outline_level tabs (liste de [position_pt, "left"|"center"|"right"|"decimal"]) run (dict : marque de paragraphe)
func para_props_xml(p, run=null):
    kids := []
    g := (k) => u.get(p, k, null) if p != null else null
    if g("style") != null:
        append(kids, _w("w:pStyle", g("style")))
    if g("keep_next") != null:
        append(kids, _on("w:keepNext", g("keep_next")))
    if g("keep_lines") != null:
        append(kids, _on("w:keepLines", g("keep_lines")))
    if g("page_break_before") != null:
        append(kids, _on("w:pageBreakBefore", g("page_break_before")))
    if g("num_id") != null:
        append(kids, x.el("w:numPr", null, [_w("w:ilvl", str(u.get(p, "num_level", 0))), _w("w:numId", str(g("num_id")))]))
    if g("border_bottom") != null:
        bc := g("border_bottom")
        col := "auto" if bc == true else u.color_hex(bc)
        append(kids, x.el("w:pBdr", null, [x.el("w:bottom", {"w:val": "single", "w:sz": "6", "w:space": "1", "w:color": col})]))
    if g("shading") != null:
        append(kids, x.el("w:shd", {"w:val": "clear", "w:color": "auto", "w:fill": u.color_hex(g("shading"))}))
    if g("tabs") != null:
        tabs := []
        for t in g("tabs"):
            kind := "left"
            pos := t
            if type(t) == "list":
                pos = t[0]
                if len(t) > 1:
                    kind = t[1]
            append(tabs, x.el("w:tab", {"w:val": kind, "w:pos": str(_pt_to_twips(pos))}))
        append(kids, x.el("w:tabs", null, tabs))
    sp := {}
    if g("space_before") != null:
        sp["w:before"] = str(_pt_to_twips(g("space_before")))
    if g("space_after") != null:
        sp["w:after"] = str(_pt_to_twips(g("space_after")))
    if g("line_spacing") != null:
        ls := g("line_spacing")
        if type(ls) == "str":
            sp["w:line"] = str(_pt_to_twips(ls))
            sp["w:lineRule"] = "exact"
        else:
            sp["w:line"] = str(to_int(u.round_to(to_float(ls) * 240.0, 0)))
            sp["w:lineRule"] = "auto"
    if len(keys(sp)) > 0:
        append(kids, x.el("w:spacing", sp))
    ind := {}
    if g("indent_left") != null:
        ind["w:left"] = str(_pt_to_twips(g("indent_left")))
    if g("indent_right") != null:
        ind["w:right"] = str(_pt_to_twips(g("indent_right")))
    if g("indent_first") != null:
        f := _pt_to_twips(g("indent_first"))
        if f < 0:
            ind["w:hanging"] = str(-f)
        else:
            ind["w:firstLine"] = str(f)
    if len(keys(ind)) > 0:
        append(kids, x.el("w:ind", ind))
    if g("align") != null:
        append(kids, _w("w:jc", _align_val(g("align"))))
    if g("outline_level") != null:
        append(kids, _w("w:outlineLvl", str(g("outline_level"))))
    rp := run
    if rp == null:
        rp = g("run")
    if rp != null:
        r := run_props_xml(rp)
        if r != null:
            append(kids, r)
    if len(kids) == 0:
        return null
    return x.el("w:pPr", null, kids)

func _twips_to_pt(v):
    if v == null:
        return null
    n := _n.num_parse(v)
    if n == null:
        return null
    return to_float(n) / 20.0

func _toggle(el):
    if el == null:
        return null
    return x.attr_bool(el, "w:val", true)

# w:rPr -> dict de propriétés (mêmes clés que run_props_xml).
func read_run_props(rpr):
    p := {}
    if rpr == null:
        return p
    for c in x.children(rpr):
        ln := x.local_name(c["tag"])
        if ln == "rStyle":
            p["style"] = x.attr(c, "w:val")
        elif ln == "rFonts":
            f := x.attr(c, "w:ascii", null)
            if f == null:
                f = x.attr(c, "w:hAnsi", null)
            if f != null:
                p["font"] = f
        elif ln == "b":
            p["bold"] = _toggle(c)
        elif ln == "i":
            p["italic"] = _toggle(c)
        elif ln == "caps":
            p["caps"] = _toggle(c)
        elif ln == "smallCaps":
            p["small_caps"] = _toggle(c)
        elif ln == "strike":
            p["strike"] = _toggle(c)
        elif ln == "dstrike":
            p["double_strike"] = _toggle(c)
        elif ln == "vanish":
            p["hidden"] = _toggle(c)
        elif ln == "color":
            v := x.attr(c, "w:val", "auto")
            if v != "auto":
                p["color"] = string.upper(v)
        elif ln == "sz":
            n := _n.num_parse(x.attr(c, "w:val", ""))
            if n != null:
                p["size"] = to_float(n) / 2.0
        elif ln == "highlight":
            p["highlight"] = x.attr(c, "w:val")
        elif ln == "u":
            v := x.attr(c, "w:val", "single")
            p["underline"] = false if v == "none" else (true if v == "single" else v)
        elif ln == "vertAlign":
            v := x.attr(c, "w:val", "")
            if v == "superscript":
                p["superscript"] = true
            elif v == "subscript":
                p["subscript"] = true
        elif ln == "lang":
            p["language"] = x.attr(c, "w:val")
        elif ln == "spacing":
            p["spacing"] = _twips_to_pt(x.attr(c, "w:val"))
    return p

func _align_read(v):
    if v == "both":
        return "justify"
    if v == "start":
        return "left"
    if v == "end":
        return "right"
    return v

# w:pPr -> dict de propriétés (mêmes clés que para_props_xml).
func read_para_props(ppr):
    p := {}
    if ppr == null:
        return p
    for c in x.children(ppr):
        ln := x.local_name(c["tag"])
        if ln == "pStyle":
            p["style"] = x.attr(c, "w:val")
        elif ln == "keepNext":
            p["keep_next"] = _toggle(c)
        elif ln == "keepLines":
            p["keep_lines"] = _toggle(c)
        elif ln == "pageBreakBefore":
            p["page_break_before"] = _toggle(c)
        elif ln == "numPr":
            p["num_id"] = x.attr_int(x.first(c, "w:numId"), "w:val", null)
            p["num_level"] = x.attr_int(x.first(c, "w:ilvl"), "w:val", 0)
        elif ln == "shd":
            f := x.attr(c, "w:fill", "auto")
            if f != "auto":
                p["shading"] = string.upper(f)
        elif ln == "spacing":
            if x.has_attr(c, "w:before"):
                p["space_before"] = _twips_to_pt(x.attr(c, "w:before"))
            if x.has_attr(c, "w:after"):
                p["space_after"] = _twips_to_pt(x.attr(c, "w:after"))
            if x.has_attr(c, "w:line"):
                rule := x.attr(c, "w:lineRule", "auto")
                n := _n.num_parse(x.attr(c, "w:line"))
                if n != null:
                    if rule == "auto":
                        p["line_spacing"] = to_float(n) / 240.0
                    else:
                        p["line_spacing"] = u.format_number(to_float(n) / 20.0) + "pt"
        elif ln == "ind":
            l := x.attr(c, "w:left", x.attr(c, "w:start", null))
            r := x.attr(c, "w:right", x.attr(c, "w:end", null))
            if l != null:
                p["indent_left"] = _twips_to_pt(l)
            if r != null:
                p["indent_right"] = _twips_to_pt(r)
            if x.has_attr(c, "w:hanging"):
                p["indent_first"] = -_twips_to_pt(x.attr(c, "w:hanging"))
            elif x.has_attr(c, "w:firstLine"):
                p["indent_first"] = _twips_to_pt(x.attr(c, "w:firstLine"))
        elif ln == "jc":
            p["align"] = _align_read(x.attr(c, "w:val"))
        elif ln == "outlineLvl":
            p["outline_level"] = x.attr_int(c, "w:val", null)
        elif ln == "pBdr":
            bt := x.first(c, "w:bottom")
            if bt != null and x.attr(bt, "w:val", "none") != "none" and x.attr(bt, "w:val", "none") != "nil":
                col := x.attr(bt, "w:color", "auto")
                p["border_bottom"] = true if col == "auto" else string.upper(col)
        elif ln == "rPr":
            p["run"] = read_run_props(c)
    return p

# ---------------------------------------------------------------------------------------------- Style

const _RUN_KEYS := ["font", "size", "bold", "italic", "underline", "strike", "color", "caps", "small_caps", "highlight"]
const _PARA_KEYS := ["align", "space_before", "space_after", "line_spacing", "indent_left", "indent_right", "indent_first", "keep_next", "keep_lines", "outline_level", "page_break_before", "border_bottom", "shading"]

class Style:
    func init(ident, name=null, kind="paragraph"):
        self.id = ident
        self.name = name if name != null else ident
        self.type = kind
        self.based_on = null
        self.next = null
        self.link = null
        self.ui_priority = null
        self.quick = false
        self.default = false
        self.font = null
        self.size = null
        self.bold = null
        self.italic = null
        self.underline = null
        self.strike = null
        self.color = null
        self.caps = null
        self.small_caps = null
        self.highlight = null
        self.align = null
        self.space_before = null
        self.space_after = null
        self.line_spacing = null
        self.indent_left = null
        self.indent_right = null
        self.indent_first = null
        self.keep_next = null
        self.keep_lines = null
        self.outline_level = null
        self.page_break_before = null
        self.border_bottom = null
        self.shading = null
        self.borders = false
        self.cell_margin = null
        self.extra = []

    func run_props():
        d := self._dict()
        out := {}
        for k in _RUN_KEYS:
            if d[k] != null:
                out[k] = d[k]
        return out

    func para_props():
        d := self._dict()
        out := {}
        for k in _PARA_KEYS:
            if d[k] != null:
                out[k] = d[k]
        return out

    func _dict():
        return {"font": self.font, "size": self.size, "bold": self.bold, "italic": self.italic, "underline": self.underline, "strike": self.strike, "color": self.color, "caps": self.caps, "small_caps": self.small_caps, "highlight": self.highlight, "align": self.align, "space_before": self.space_before, "space_after": self.space_after, "line_spacing": self.line_spacing, "indent_left": self.indent_left, "indent_right": self.indent_right, "indent_first": self.indent_first, "keep_next": self.keep_next, "keep_lines": self.keep_lines, "outline_level": self.outline_level, "page_break_before": self.page_break_before, "border_bottom": self.border_bottom, "shading": self.shading}

    func set_props(d):
        for k in keys(d):
            v := d[k]
            if k == "font":
                self.font = v
            elif k == "size":
                self.size = v
            elif k == "bold":
                self.bold = v
            elif k == "italic":
                self.italic = v
            elif k == "underline":
                self.underline = v
            elif k == "strike":
                self.strike = v
            elif k == "color":
                self.color = v
            elif k == "caps":
                self.caps = v
            elif k == "small_caps":
                self.small_caps = v
            elif k == "highlight":
                self.highlight = v
            elif k == "align":
                self.align = v
            elif k == "space_before":
                self.space_before = v
            elif k == "space_after":
                self.space_after = v
            elif k == "line_spacing":
                self.line_spacing = v
            elif k == "indent_left":
                self.indent_left = v
            elif k == "indent_right":
                self.indent_right = v
            elif k == "indent_first":
                self.indent_first = v
            elif k == "keep_next":
                self.keep_next = v
            elif k == "keep_lines":
                self.keep_lines = v
            elif k == "outline_level":
                self.outline_level = v
            elif k == "page_break_before":
                self.page_break_before = v
            elif k == "border_bottom":
                self.border_bottom = v
            elif k == "shading":
                self.shading = v
        return self

    func to_xml():
        attrs := {"w:type": self.type, "w:default": "1" if self.default else null, "w:styleId": self.id}
        kids := [_w("w:name", self.name)]
        if self.based_on != null:
            append(kids, _w("w:basedOn", self.based_on))
        if self.next != null:
            append(kids, _w("w:next", self.next))
        if self.link != null:
            append(kids, _w("w:link", self.link))
        if self.ui_priority != null:
            append(kids, _w("w:uiPriority", str(self.ui_priority)))
        if self.quick:
            append(kids, x.el("w:qFormat"))
        for e in self.extra:
            append(kids, e)
        if self.type == "paragraph":
            pp := para_props_xml(self.para_props())
            if pp != null:
                append(kids, pp)
        if self.type == "table":
            tbl := []
            if self.borders:
                b := []
                for side in ["w:top", "w:left", "w:bottom", "w:right", "w:insideH", "w:insideV"]:
                    append(b, x.el(side, {"w:val": "single", "w:sz": "4", "w:space": "0", "w:color": "auto"}))
                append(tbl, x.el("w:tblBorders", null, b))
            m := self.cell_margin
            if m == null:
                m = 5.4
            tw := str(_pt_to_twips(m))
            append(tbl, x.el("w:tblCellMar", null, [x.el("w:top", {"w:w": "0", "w:type": "dxa"}), x.el("w:left", {"w:w": tw, "w:type": "dxa"}), x.el("w:bottom", {"w:w": "0", "w:type": "dxa"}), x.el("w:right", {"w:w": tw, "w:type": "dxa"})]))
            append(kids, x.el("w:tblPr", null, tbl))
        if self.type != "table" and self.type != "numbering":
            rp := run_props_xml(self.run_props())
            if rp != null:
                append(kids, rp)
        return x.el("w:style", attrs, kids)

func from_xml(node):
    s := Style(x.attr(node, "w:styleId", ""), null, x.attr(node, "w:type", "paragraph"))
    n := x.first(node, "w:name")
    if n != null:
        s.name = x.attr(n, "w:val", s.id)
    s.default = x.attr_bool(node, "w:default", false)
    b := x.first(node, "w:basedOn")
    if b != null:
        s.based_on = x.attr(b, "w:val")
    nx := x.first(node, "w:next")
    if nx != null:
        s.next = x.attr(nx, "w:val")
    lk := x.first(node, "w:link")
    if lk != null:
        s.link = x.attr(lk, "w:val")
    up := x.first(node, "w:uiPriority")
    if up != null:
        s.ui_priority = x.attr_int(up, "w:val", null)
    s.quick = x.first(node, "w:qFormat") != null
    s.set_props(read_para_props(x.first(node, "w:pPr")))
    s.set_props(read_run_props(x.first(node, "w:rPr")))
    tp := x.first(node, "w:tblPr")
    if tp != null:
        s.borders = x.first(tp, "w:tblBorders") != null
    return s

# ---------------------------------------------------------------------------------------------- feuille de styles

class StyleSheet:
    func init(font="Calibri", size=11, language="fr-FR"):
        self.default_font = font
        self.default_size = size
        self.language = language
        self.space_after = 8
        self.line_spacing = 1.08
        self._styles = {}
        self._order = []
        self.latent = null

    func add(style):
        if not contains_key(self._styles, style.id):
            append(self._order, style.id)
        self._styles[style.id] = style
        return style

    func has(ident):
        return contains_key(self._styles, ident)

    func get(ident):
        if contains_key(self._styles, ident):
            return self._styles[ident]
        return null

    # Par identifiant, puis par nom (insensible à la casse) : find("heading 1") trouve "Heading1".
    func find(name_or_id):
        if contains_key(self._styles, name_or_id):
            return self._styles[name_or_id]
        low := string.lower(name_or_id)
        for k in self._order:
            s := self._styles[k]
            if string.lower(s.name) == low or string.lower(s.id) == low:
                return s
        return null

    func ids():
        out := []
        for k in self._order:
            append(out, k)
        return out

    func styles():
        out := []
        for k in self._order:
            append(out, self._styles[k])
        return out

    func remove(ident):
        if not contains_key(self._styles, ident):
            return false
        collections.remove(self._styles, ident)
        order := []
        for k in self._order:
            if k != ident:
                append(order, k)
        self._order = order
        return true

    # Propriétés effectives d'un style (héritage based_on, du plus général au plus particulier).
    func resolve(ident):
        chain := []
        cur := ident
        guard := 0
        while cur != null and contains_key(self._styles, cur) and guard < 32:
            collections.insert(chain, 0, self._styles[cur])
            cur = self._styles[cur].based_on
            guard = guard + 1
        out := {"font": self.default_font, "size": self.default_size}
        for s in chain:
            for k in keys(s.run_props()):
                out[k] = s.run_props()[k]
            for k in keys(s.para_props()):
                out[k] = s.para_props()[k]
        return out

    func to_xml():
        f := self.default_font
        defaults := x.el("w:docDefaults", null, [x.el("w:rPrDefault", null, [x.el("w:rPr", null, [x.el("w:rFonts", {"w:ascii": f, "w:eastAsia": f, "w:hAnsi": f, "w:cs": f}), _w("w:sz", str(_half_points(self.default_size))), _w("w:szCs", str(_half_points(self.default_size))), x.el("w:lang", {"w:val": self.language, "w:eastAsia": "en-US", "w:bidi": "ar-SA"})])]), x.el("w:pPrDefault", null, [x.el("w:pPr", null, [x.el("w:spacing", {"w:after": str(_pt_to_twips(self.space_after)), "w:line": str(to_int(u.round_to(self.line_spacing * 240.0, 0))), "w:lineRule": "auto"})])])])
        kids := [defaults]
        if self.latent != null:
            append(kids, self.latent)
        for k in self._order:
            append(kids, self._styles[k].to_xml())
        return x.el("w:styles", {"xmlns:w": x.NS["w"], "xmlns:r": x.NS["r"]}, kids)

func _style(ident, name, kind="paragraph", based_on="Normal", props=null):
    s := Style(ident, name, kind)
    if kind == "paragraph" and ident != "Normal":
        s.based_on = based_on
        s.next = "Normal"
    if props != null:
        s.set_props(props)
    s.quick = true
    return s

# Jeu de styles complet, proche de celui de Word (identifiants anglais, comme Word quelle que soit la langue).
func default_styles(font="Calibri", size=11, language="fr-FR", heading_font=null, heading_color="2F5496"):
    sheet := StyleSheet(font, size, language)
    hf := heading_font if heading_font != null else font
    normal := Style("Normal", "Normal", "paragraph")
    normal.default = true
    normal.quick = true
    sheet.add(normal)
    sizes := [16, 13, 12, 11, 11, 11, 11, 11, 11]
    lvl := 1
    while lvl <= 9:
        h := _style("Heading" + str(lvl), "heading " + str(lvl), "paragraph", "Normal", {"font": hf, "size": sizes[lvl - 1], "color": heading_color, "keep_next": true, "keep_lines": true, "space_before": 12 if lvl == 1 else 2, "space_after": 0, "outline_level": lvl - 1, "bold": true if lvl >= 3 else null, "italic": true if lvl == 4 else null})
        h.ui_priority = 9
        sheet.add(h)
        lvl = lvl + 1
    t := _style("Title", "Title", "paragraph", "Normal", {"font": hf, "size": 28, "space_after": 0, "line_spacing": 1.0, "spacing": null})
    t.ui_priority = 10
    sheet.add(t)
    st := _style("Subtitle", "Subtitle", "paragraph", "Normal", {"size": 14, "color": "5A5A5A", "space_after": 8})
    st.ui_priority = 11
    sheet.add(st)
    q := _style("Quote", "Quote", "paragraph", "Normal", {"italic": true, "color": "404040", "align": "center", "space_before": 10, "space_after": 8, "indent_left": 43.2, "indent_right": 43.2})
    q.ui_priority = 29
    sheet.add(q)
    sheet.add(_style("Caption", "caption", "paragraph", "Normal", {"italic": true, "size": 9, "color": "44546A", "space_after": 10, "line_spacing": 1.0}))
    lp := _style("ListParagraph", "List Paragraph", "paragraph", "Normal", {"indent_left": 36})
    lp.ui_priority = 34
    sheet.add(lp)
    sheet.add(_style("NoSpacing", "No Spacing", "paragraph", "Normal", {"space_after": 0, "line_spacing": 1.0}))
    code := _style("Code", "Code", "paragraph", "Normal", {"font": "Consolas", "size": 9.5, "space_after": 0, "line_spacing": 1.0, "shading": "F2F2F2"})
    sheet.add(code)
    toc_h := _style("TOCHeading", "TOC Heading", "paragraph", "Heading1", {"outline_level": 9})
    sheet.add(toc_h)
    k := 1
    while k <= 3:
        sheet.add(_style("TOC" + str(k), "toc " + str(k), "paragraph", "Normal", {"indent_left": (k - 1) * 11, "space_after": 5}))
        k = k + 1
    hd := _style("Header", "header", "paragraph", "Normal", {"space_after": 0, "line_spacing": 1.0, "tabs": null})
    sheet.add(hd)
    sheet.add(_style("Footer", "footer", "paragraph", "Normal", {"space_after": 0, "line_spacing": 1.0}))
    dpf := Style("DefaultParagraphFont", "Default Paragraph Font", "character")
    dpf.default = true
    dpf.ui_priority = 1
    sheet.add(dpf)
    link := Style("Hyperlink", "Hyperlink", "character")
    link.based_on = "DefaultParagraphFont"
    link.color = "0563C1"
    link.underline = true
    sheet.add(link)
    strong := Style("Strong", "Strong", "character")
    strong.based_on = "DefaultParagraphFont"
    strong.bold = true
    strong.quick = true
    sheet.add(strong)
    em := Style("Emphasis", "Emphasis", "character")
    em.based_on = "DefaultParagraphFont"
    em.italic = true
    em.quick = true
    sheet.add(em)
    ic := Style("InlineCode", "Inline Code", "character")
    ic.based_on = "DefaultParagraphFont"
    ic.font = "Consolas"
    sheet.add(ic)
    tn := Style("TableNormal", "Normal Table", "table")
    tn.default = true
    sheet.add(tn)
    tg := Style("TableGrid", "Table Grid", "table")
    tg.based_on = "TableNormal"
    tg.borders = true
    sheet.add(tg)
    nl := Style("NoList", "No List", "numbering")
    nl.default = true
    sheet.add(nl)
    return sheet

# Analyse word/styles.xml.
func parse(text):
    root := x.parse(text)
    sheet := StyleSheet()
    dd := x.first(root, "w:docDefaults")
    if dd != null:
        rpr := x.first_path(dd, "w:rPrDefault/w:rPr")
        if rpr != null:
            rp := read_run_props(rpr)
            if contains_key(rp, "font"):
                sheet.default_font = rp["font"]
            if contains_key(rp, "size"):
                sheet.default_size = rp["size"]
            lang := x.first(rpr, "w:lang")
            if lang != null:
                sheet.language = x.attr(lang, "w:val", sheet.language)
        ppr := x.first_path(dd, "w:pPrDefault/w:pPr")
        if ppr != null:
            pp := read_para_props(ppr)
            if contains_key(pp, "space_after"):
                sheet.space_after = pp["space_after"]
            if contains_key(pp, "line_spacing") and type(pp["line_spacing"]) == "float":
                sheet.line_spacing = pp["line_spacing"]
    sheet.latent = x.first(root, "w:latentStyles")
    for s in x.children(root, "w:style"):
        sheet.add(from_xml(s))
    return sheet
