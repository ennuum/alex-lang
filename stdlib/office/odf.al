# ALEX STANDARD LIBRARY — office.odf
# OpenDocument (ISO/IEC 26300, ODF 1.3) : socle commun à odt, ods et odp — paquet ZIP (« mimetype » stocké en
# premier, META-INF/manifest.xml), parties XML (content.xml, styles.xml, meta.xml, settings.xml), styles
# automatiques dédoublonnés, longueurs, texte avec espaces significatifs (text:s, text:tab, text:line-break),
# propriétés de texte, lecture générique du texte de tout document ODF.
#
#   use office.odf as odf
#   pkg := odf.open("compte-rendu.odt")
#   pkg.mimetype                              # "application/vnd.oasis.opendocument.text"
#   root := pkg.content()                     # nœud office:document-content
#   odf.text("compte-rendu.odt")              # texte brut (odt, ods, odp)
#   odf.kind("tableur.ods")                   # "ods"
#
# OdfPackage : mimetype archive metadata
#   content() / styles() / settings() -> nœuds XML (null si absents)   read(nom) -> octets   has(nom)
#   set_xml(nom, nœud)   add_file(nom, octets, media_type)   add_object(dossier, racine, media_type) (sous-document)   files() -> noms (hors manifeste et mimetype)
#   to_bytes() / save(chemin)   (manifeste regénéré, mimetype stocké en tête, meta.xml depuis metadata)
# Fonctions : new(mimetype) -> OdfPackage   open(chemin_ou_octets) -> OdfPackage   kind(src) -> "odt" | "ods" | "odp" | ...
#   text(src) -> str   document_root(tag, extra_ns=null) -> nœud racine avec tous les espaces de noms ODF
#   to_pt(longueur) -> points (« 2cm », « 0.5in », « 12pt », « 10mm », « 1pc », « 96px »)   length(pt, unit="cm") -> texte
#   text_nodes(texte) -> enfants XML (espaces multiples, tabulations, sauts de ligne encodés)
#   node_text(nœud) -> texte (text:s, text:tab, text:line-break décodés, espaces repliés)
#   text_props(fmt) -> attributs style:text-properties   read_text_props(nœud) -> fmt
#   StyleBank(prefixe) : add(famille, enfants, parent=null, attrs=null) -> nom (styles identiques partagés)  nodes()
#   StyleIndex(racines...) : styles relus (automatiques et communs) avec héritage : get(nom) props(nom, kind)
#   text_fmt(nom) para_parent_chain(nom) list_ordered(nom_liste, niveau)
#   chart_xml(kind, titre, catégories, séries, opts=null) -> contenu d'un objet graphique ODF
#   read_chart(racine) -> {"kind", "title", "categories", "series", "stacked", "legend"}
# MIME_ODT MIME_ODS MIME_ODP MIME_ODG
# Erreurs : ODFError, FormatError, ArchiveError, XMLError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use office.errors as errors
use office.utils as u
use office.xml as x
use office.archive as zip
use office.metadata as metadata

const MIME_ODT := "application/vnd.oasis.opendocument.text"
const MIME_ODS := "application/vnd.oasis.opendocument.spreadsheet"
const MIME_ODP := "application/vnd.oasis.opendocument.presentation"
const MIME_ODG := "application/vnd.oasis.opendocument.graphics"
const VERSION := "1.3"

const _ROOT_NS := ["office", "style", "text", "table", "draw", "fo", "xlink", "dc", "meta", "number", "svg", "chart", "presentation", "of", "loext", "smil", "anim"]

func document_root(tag, extra=null):
    attrs := {}
    for p in _ROOT_NS:
        attrs["xmlns:" + p] = x.NS[p]
    attrs["office:version"] = VERSION
    if extra != null:
        for k in keys(extra):
            attrs[k] = extra[k]
    return x.el(tag, attrs, [])

# ---------------------------------------------------------------------------------------------- paquet

class OdfPackage:
    func init(mimetype=MIME_ODT):
        self.mimetype = mimetype
        self.archive = zip.new()
        self.metadata = metadata.new()
        self.media = {}
        self._xml = {}

    func has(name):
        return contains_key(self._xml, name) or self.archive.contains(name)

    func read(name):
        if contains_key(self._xml, name):
            return x.to_bytes(self._xml[name], true)
        return self.archive.read(name)

    func _part(name):
        if contains_key(self._xml, name):
            return self._xml[name]
        if not self.archive.contains(name):
            return null
        node := null
        try:
            node = x.parse(self.archive.read_text(name), true)
        catch e:
            errors.rethrow(e, errors.ODF, name + " illisible")
        self._xml[name] = node
        return node

    func content():
        return self._part("content.xml")

    func styles():
        return self._part("styles.xml")

    func settings():
        return self._part("settings.xml")

    func set_xml(name, node):
        self._xml[name] = node
        self.media[name] = "text/xml"

    # Sous-document (objet incorporé : graphique...) : « Object N/content.xml ».
    func add_object(folder, content_root, media_type="application/vnd.oasis.opendocument.chart"):
        self.set_xml(folder + "/content.xml", content_root)
        self.media[folder + "/"] = media_type
        return folder

    func add_file(name, data, media_type):
        self.archive.write(name, data, not (string.starts_with(media_type, "image/png") or string.starts_with(media_type, "image/jpeg")))
        self.media[name] = media_type

    func files():
        out := []
        for n in self.archive.names():
            if n != "mimetype" and n != "META-INF/manifest.xml" and not contains_key(self._xml, n):
                append(out, n)
        for n in keys(self._xml):
            append(out, n)
        return out

    func _manifest():
        kids := [x.el("manifest:file-entry", {"manifest:full-path": "/", "manifest:version": VERSION, "manifest:media-type": self.mimetype})]
        for n in self.files():
            if n == "meta.xml" or string.ends_with(n, "/"):
                continue
            mt := u.get(self.media, n, null)
            if mt == null:
                mt = "text/xml" if string.ends_with(n, ".xml") else u.mime_for_extension(_ext(n))
            append(kids, x.el("manifest:file-entry", {"manifest:full-path": n, "manifest:media-type": mt}))
        for n in keys(self.media):
            if string.ends_with(n, "/"):
                append(kids, x.el("manifest:file-entry", {"manifest:full-path": n, "manifest:media-type": self.media[n]}))
        append(kids, x.el("manifest:file-entry", {"manifest:full-path": "meta.xml", "manifest:media-type": "text/xml"}))
        return x.el("manifest:manifest", {"xmlns:manifest": x.NS["manifest"], "manifest:version": VERSION}, kids)

    func to_bytes():
        out := zip.new()
        out.write("mimetype", _n.utf8_encode(self.mimetype), false)
        order := ["content.xml", "styles.xml", "settings.xml"]
        for n in order:
            if contains_key(self._xml, n):
                out.write(n, x.to_bytes(self._xml[n], true))
            elif self.archive.contains(n):
                out.write(n, self.archive.read(n))
        for n in keys(self._xml):
            if n != "content.xml" and n != "styles.xml" and n != "settings.xml" and n != "meta.xml":
                out.write(n, x.to_bytes(self._xml[n], true))
        for n in self.archive.names():
            if n == "mimetype" or n == "META-INF/manifest.xml" or n == "meta.xml" or contains_key(self._xml, n):
                continue
            skip := false
            for o in order:
                if n == o:
                    skip = true
            if skip:
                continue
            e := self.archive.info(n)
            out.write(n, self.archive.read(n), e.method != 0)
        mm := self.metadata
        if mm.created == null or mm.created == "":
            mm.created = u.now_iso()
        mm.modified = u.now_iso()
        out.write("meta.xml", x.to_bytes(metadata.odf_meta(mm), true))
        out.write("META-INF/manifest.xml", x.to_bytes(self._manifest(), true))
        return out.to_bytes()

    func save(path):
        io.write_bytes(path, self.to_bytes())
        return path

func _ext(name):
    k := -1
    i := 0
    for c in name:
        if str(c) == ".":
            k = i
        i = i + 1
    return _n.str_slice(name, k + 1, null) if k >= 0 else ""

func new(mimetype=MIME_ODT):
    return OdfPackage(mimetype)

func open(src):
    a := null
    try:
        a = zip.open(src) if type(src) == "str" else zip.from_bytes(src)
    catch e:
        errors.rethrow(e, errors.FORMAT, "pas un document OpenDocument (archive ZIP attendue)")
    mt := ""
    if a.contains("mimetype"):
        mt = string.trim(a.read_text("mimetype"))
    elif a.contains("META-INF/manifest.xml"):
        man := x.parse(a.read_text("META-INF/manifest.xml"))
        for fe in x.find_all(man, "manifest:file-entry"):
            if x.attr(fe, "manifest:full-path", "") == "/":
                mt = x.attr(fe, "manifest:media-type", "")
    if not string.starts_with(mt, "application/vnd.oasis.opendocument"):
        if not a.contains("content.xml"):
            errors.fail(errors.FORMAT, "pas un document OpenDocument (mimetype « " + mt + " »)")
    p := OdfPackage(mt)
    p.archive = a
    p.metadata = metadata.from_odf(a)
    if a.contains("META-INF/manifest.xml"):
        try:
            man := x.parse(a.read_text("META-INF/manifest.xml"))
            for fe in x.find_all(man, "manifest:file-entry"):
                path := x.attr(fe, "manifest:full-path", "")
                if path != "/" and path != "":
                    p.media[path] = x.attr(fe, "manifest:media-type", "")
        catch e:
            p.media = {}
    return p

func kind(src):
    p := open(src)
    mt := p.mimetype
    if string.starts_with(mt, MIME_ODT):
        return "odt"
    if string.starts_with(mt, MIME_ODS):
        return "ods"
    if string.starts_with(mt, MIME_ODP):
        return "odp"
    if string.starts_with(mt, MIME_ODG):
        return "odg"
    return "odf"

# ---------------------------------------------------------------------------------------------- longueurs

func to_pt(v, fallback=null):
    if v == null:
        return fallback
    t := type(v)
    if t == "int" or t == "float":
        return to_float(v)
    s := string.trim(string.lower(u.to_text(v)))
    units := [["cm", 72.0 / 2.54], ["mm", 72.0 / 25.4], ["in", 72.0], ["pt", 1.0], ["pc", 12.0], ["px", 0.75], ["%", null]]
    for pair in units:
        if string.ends_with(s, pair[0]):
            n := _n.num_parse(string.trim(_n.str_slice(s, 0, len(s) - len(pair[0]))))
            if n == null or pair[1] == null:
                return fallback
            return to_float(n) * pair[1]
    n := _n.num_parse(s)
    if n == null:
        return fallback
    return to_float(n)

func length(pt, unit="cm"):
    v := to_float(pt)
    if unit == "cm":
        return u.format_number(u.round_to(v * 2.54 / 72.0, 4)) + "cm"
    if unit == "mm":
        return u.format_number(u.round_to(v * 25.4 / 72.0, 3)) + "mm"
    if unit == "in":
        return u.format_number(u.round_to(v / 72.0, 4)) + "in"
    return u.format_number(u.round_to(v, 2)) + "pt"

# ---------------------------------------------------------------------------------------------- texte

# Texte -> enfants XML : espaces multiples (text:s), tabulations (text:tab), sauts de ligne (text:line-break).
func text_nodes(s):
    out := []
    buf := ""
    spaces := 0
    cs := u.chars(u.to_text(s))
    i := 0
    n := len(cs)
    at_start := true
    while i < n:
        c := cs[i]
        if c == " ":
            k := i
            while k < n and cs[k] == " ":
                k = k + 1
            count := k - i
            if at_start or k == n:
                if buf != "":
                    append(out, buf)
                    buf = ""
                append(out, x.el("text:s", {"text:c": str(count)} if count > 1 else null, []))
            else:
                buf = buf + " "
                if count > 1:
                    append(out, buf)
                    buf = ""
                    append(out, x.el("text:s", {"text:c": str(count - 1)} if count > 2 else null, []))
            i = k
            at_start = false
            continue
        if c == "\t" or c == "\n" or c == "\r":
            if buf != "":
                append(out, buf)
                buf = ""
            if c == "\t":
                append(out, x.el("text:tab", null, []))
            elif c == "\n":
                append(out, x.el("text:line-break", null, []))
            i = i + 1
            at_start = c != "\t"
            continue
        buf = buf + c
        at_start = false
        i = i + 1
    if buf != "":
        append(out, buf)
    return out

func _collapse(t):
    s := string.replace(string.replace(string.replace(t, "\r", " "), "\n", " "), "\t", " ")
    while string.contains(s, "  "):
        s = string.replace(s, "  ", " ")
    return s

func node_text(node):
    return _n.odf_text(node)

# ---------------------------------------------------------------------------------------------- propriétés

func text_props(fmt):
    a := {}
    if fmt == null:
        return a
    if u.get(fmt, "bold", false) == true:
        a["fo:font-weight"] = "bold"
        a["style:font-weight-asian"] = "bold"
        a["style:font-weight-complex"] = "bold"
    if u.get(fmt, "italic", false) == true:
        a["fo:font-style"] = "italic"
        a["style:font-style-asian"] = "italic"
        a["style:font-style-complex"] = "italic"
    ul := u.get(fmt, "underline", false)
    if ul == true or (type(ul) == "str" and ul != "none" and ul != ""):
        a["style:text-underline-style"] = "solid"
        a["style:text-underline-width"] = "auto"
        a["style:text-underline-color"] = "font-color"
        if ul == "double":
            a["style:text-underline-type"] = "double"
    if u.get(fmt, "strike", false) == true:
        a["style:text-line-through-style"] = "solid"
        a["style:text-line-through-type"] = "single"
    if u.get(fmt, "color", null) != null:
        a["fo:color"] = "#" + u.color_hex(fmt["color"])
    if u.get(fmt, "size", null) != null:
        a["fo:font-size"] = u.format_number(fmt["size"]) + "pt"
        a["style:font-size-asian"] = u.format_number(fmt["size"]) + "pt"
        a["style:font-size-complex"] = u.format_number(fmt["size"]) + "pt"
    if u.get(fmt, "font", null) != null:
        a["style:font-name"] = fmt["font"]
        a["fo:font-family"] = "'" + string.replace(fmt["font"], "'", "") + "'"
    if u.get(fmt, "highlight", null) != null:
        a["fo:background-color"] = "#" + u.color_hex(fmt["highlight"])
    if u.get(fmt, "superscript", false) == true:
        a["style:text-position"] = "super 58%"
    elif u.get(fmt, "subscript", false) == true:
        a["style:text-position"] = "sub 58%"
    if u.get(fmt, "caps", false) == true:
        a["fo:text-transform"] = "uppercase"
    return a

func read_text_props(tp):
    f := {}
    if tp == null:
        return f
    w := x.attr(tp, "fo:font-weight", null)
    if w != null:
        f["bold"] = w == "bold" or w == "600" or w == "700" or w == "800" or w == "900"
    st := x.attr(tp, "fo:font-style", null)
    if st != null:
        f["italic"] = st == "italic" or st == "oblique"
    ul := x.attr(tp, "style:text-underline-style", null)
    if ul != null:
        f["underline"] = ul != "none"
    lt := x.attr(tp, "style:text-line-through-style", null)
    if lt != null:
        f["strike"] = lt != "none"
    col := x.attr(tp, "fo:color", null)
    if col != null and string.starts_with(col, "#"):
        f["color"] = string.upper(_n.str_slice(col, 1, null))
    sz := x.attr(tp, "fo:font-size", null)
    if sz != null and not string.ends_with(sz, "%"):
        f["size"] = to_pt(sz)
    fn := x.attr(tp, "style:font-name", null)
    if fn == null:
        fam := x.attr(tp, "fo:font-family", null)
        if fam != null:
            fn = string.replace(string.replace(fam, "'", ""), "\"", "")
    if fn != null:
        f["font"] = fn
    bg := x.attr(tp, "fo:background-color", null)
    if bg != null and string.starts_with(bg, "#"):
        f["highlight"] = string.upper(_n.str_slice(bg, 1, null))
    pos := x.attr(tp, "style:text-position", null)
    if pos != null:
        if string.starts_with(pos, "super") or (string.starts_with(pos, "3") and not string.starts_with(pos, "0")):
            f["superscript"] = true
        elif string.starts_with(pos, "sub") or string.starts_with(pos, "-"):
            f["subscript"] = true
    return f

# ---------------------------------------------------------------------------------------------- styles automatiques

const _PREFIXES := {"paragraph": "P", "text": "T", "table": "Ta", "table-column": "co", "table-row": "ro", "table-cell": "ce", "graphic": "gr", "presentation": "pr", "drawing-page": "dp"}

# Banque de styles automatiques : deux demandes identiques renvoient le même nom (P1, T1, ce1...).
class StyleBank:
    func init():
        self._keys = {}
        self._nodes = []
        self._count = {}

    func add(family, children, parent=null, attrs=null, prefix=null):
        node := x.el("style:style", {"style:name": "", "style:family": family}, children)
        if parent != null:
            node["attrs"]["style:parent-style-name"] = parent
        if attrs != null:
            for k in keys(attrs):
                node["attrs"][k] = attrs[k]
        key := family + "|" + x.stringify(node)
        if contains_key(self._keys, key):
            return self._keys[key]
        pf := prefix
        if pf == null:
            pf = u.get(_PREFIXES, family, "S")
        n := u.get(self._count, pf, 0) + 1
        self._count[pf] = n
        name := pf + str(n)
        node["attrs"]["style:name"] = name
        self._keys[key] = name
        append(self._nodes, node)
        return name

    func add_node(node):
        append(self._nodes, node)
        return node

    func nodes():
        return self._nodes

# ---------------------------------------------------------------------------------------------- index des styles

func _style_name_of(node):
    return x.attr(node, "style:name", x.attr(node, "text:name", null))

class StyleIndex:
    func init(roots):
        self.styles = {}
        self.auto = {}
        self.lists = {}
        self.data_styles = {}
        self.page_layouts = {}
        self.masters = {}
        self.defaults = {}
        for r in roots:
            if r == null:
                continue
            for sec in x.children(r):
                ln := x.local_name(sec["tag"])
                if ln == "styles" or ln == "automatic-styles" or ln == "master-styles":
                    for s in x.children(sec):
                        self._add(s, ln == "automatic-styles")

    func _add(s, is_auto):
        ln := x.local_name(s["tag"])
        name := _style_name_of(s)
        if ln == "style":
            if name != null:
                fam := x.attr(s, "style:family", "")
                self.styles[fam + ":" + name] = s
                if is_auto:
                    self.auto[fam + ":" + name] = true
        elif ln == "default-style":
            self.defaults[x.attr(s, "style:family", "")] = s
        elif ln == "list-style":
            if name != null:
                self.lists[name] = s
        elif ln == "page-layout":
            if name != null:
                self.page_layouts[name] = s
        elif ln == "master-page":
            if name != null:
                self.masters[name] = s
        elif ln == "number-style" or ln == "currency-style" or ln == "percentage-style" or ln == "date-style" or ln == "time-style" or ln == "boolean-style" or ln == "text-style":
            if name != null:
                self.data_styles[name] = s

    func get(family, name):
        if name == null:
            return null
        return u.get(self.styles, family + ":" + name, null)

    func is_auto(family, name):
        return contains_key(self.auto, family + ":" + str(name))

    # Chaîne des noms (le style, son parent, le parent du parent...)
    func chain(family, name):
        out := []
        cur := name
        guard := 0
        while cur != null and guard < 20:
            append(out, cur)
            s := self.get(family, cur)
            if s == null:
                break
            cur = x.attr(s, "style:parent-style-name", null)
            guard = guard + 1
        return out

    # Propriétés fusionnées (parents d'abord) pour l'élément enfant `kind` (ex. "style:text-properties").
    func props(family, name, kind):
        merged := {}
        ch := self.chain(family, name)
        k := len(ch) - 1
        dflt := u.get(self.defaults, family, null)
        if dflt != null:
            p := x.first(dflt, kind)
            if p != null:
                for a in keys(p["attrs"]):
                    merged[a] = p["attrs"][a]
        while k >= 0:
            s := self.get(family, ch[k])
            if s != null:
                p := x.first(s, kind)
                if p != null:
                    for a in keys(p["attrs"]):
                        merged[a] = p["attrs"][a]
            k = k - 1
        return merged

    func text_fmt(family, name, inherit=true):
        if name == null:
            return {}
        if not inherit:
            s := self.get(family, name)
            if s == null:
                return {}
            return read_text_props(x.first(s, "style:text-properties"))
        return read_text_props(x.el("style:text-properties", self.props(family, name, "style:text-properties"), []))

    func display_name(family, name):
        s := self.get(family, name)
        if s == null:
            return name
        return x.attr(s, "style:display-name", name)

    # Vrai si le niveau `level` (0..) de la liste `list_name` est numéroté.
    func list_ordered(list_name, level):
        ls := u.get(self.lists, list_name, null)
        if ls == null:
            return false
        for lv in x.children(ls):
            if x.attr_int(lv, "text:level", 1) == level + 1:
                return x.local_name(lv["tag"]) == "list-level-style-number"
        return false

# ---------------------------------------------------------------------------------------------- texte générique

func text(src):
    p := src if isinstance(src, OdfPackage) else open(src)
    root := p.content()
    if root == null:
        return ""
    body := x.first(root, "office:body")
    if body == null:
        return ""
    out := []
    _gen_text(body, out)
    lines := []
    for l in out:
        append(lines, l)
    return string.join("\n", lines)

func _gen_text(node, out):
    for c in x.children(node):
        ln := x.local_name(c["tag"])
        if ln == "p" or ln == "h":
            frames := x.find_all(c, "draw:text-box")
            if len(frames) > 0:
                t := string.trim(node_text(c))
                if t != "":
                    append(out, t)
                for fb in frames:
                    _gen_text(fb, out)
            else:
                append(out, node_text(c))
        elif ln == "table-row":
            cells := []
            for cell in x.children(c):
                cl := x.local_name(cell["tag"])
                if cl == "table-cell" or cl == "covered-table-cell":
                    rep := x.attr_int(cell, "table:number-columns-repeated", 1)
                    parts := []
                    for p in x.children(cell, "text:p"):
                        append(parts, node_text(p))
                    v := string.join("\n", parts)
                    if v == "" and rep > 1:
                        rep = 1
                    k := 0
                    while k < rep and k < 1024:
                        append(cells, v)
                        k = k + 1
            while len(cells) > 0 and cells[len(cells) - 1] == "":
                collections.pop(cells)
            if len(cells) > 0:
                append(out, string.join("\t", cells))
        elif ln == "notes" or ln == "forms" or ln == "tracked-changes" or ln == "sequence-decls" or ln == "named-expressions" or ln == "calculation-settings" or ln == "database-ranges":
            continue
        else:
            _gen_text(c, out)

# ---------------------------------------------------------------------------------------------- graphiques

const CHART_CLASSES := {"column": "chart:bar", "bar": "chart:bar", "line": "chart:line", "area": "chart:area", "pie": "chart:circle", "doughnut": "chart:ring", "scatter": "chart:scatter"}
const CHART_COLORS := ["4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47", "264478", "9E480E", "636363", "997300"]

func _cell_addr(col, row):
    return "local-table.$" + u.column_letter(col) + "$" + str(row)

func _chart_cell(v):
    t := type(v)
    if t == "int" or t == "float":
        return x.el("table:table-cell", {"office:value-type": "float", "office:value": str(v)}, [x.el("text:p", null, [u.format_number(v)])])
    if v == null:
        return x.el("table:table-cell", null, [])
    return x.el("table:table-cell", {"office:value-type": "string"}, [x.el("text:p", null, [u.to_text(v)])])

# Document graphique ODF (contenu de « Object N/content.xml »). series : [{"name", "values", "color"}] ;
# opts : legend ("bottom" "right" "top" "left" ou false) stacked data_labels x_title y_title width height (pt).
func chart_xml(kind, title, categories, series, opts=null):
    o := opts if opts != null else {}
    cls := u.get(CHART_CLASSES, kind, "chart:bar")
    bank := StyleBank()
    root := document_root("office:document-content")
    w := u.get(o, "width", 453.0)
    h := u.get(o, "height", 255.0)
    chs := bank.add("chart", [x.el("style:graphic-properties", {"draw:stroke": "none", "draw:fill": "none"}, [])], null, null, "ch")
    cp := {"chart:include-hidden-cells": "false"}
    if kind == "bar":
        cp["chart:vertical"] = "true"
    if u.get(o, "stacked", false):
        cp["chart:stacked"] = "true"
    if kind == "line" or kind == "scatter":
        cp["chart:symbol-type"] = "automatic"
    if kind == "doughnut":
        cp["chart:hole-size"] = "50%"
    pas := bank.add("chart", [x.el("style:chart-properties", cp, [])], null, null, "ch")
    chart := x.el("chart:chart", {"svg:width": length(w), "svg:height": length(h), "chart:class": cls, "chart:style-name": chs}, [])
    if title != null and title != "":
        append(chart["children"], x.el("chart:title", null, [x.el("text:p", null, [u.to_text(title)])]))
    leg := u.get(o, "legend", "bottom")
    if leg != false and leg != null and leg != "none":
        append(chart["children"], x.el("chart:legend", {"chart:legend-position": leg, "style:legend-expansion": "high" if leg == "left" or leg == "right" else "wide"}, []))
    n := len(categories)
    plot := x.el("chart:plot-area", {"chart:style-name": pas, "chart:data-source-has-labels": "both"}, [])
    if kind != "pie" and kind != "doughnut":
        axs := bank.add("chart", [x.el("style:chart-properties", {"chart:display-label": "true", "chart:tick-marks-major-outer": "true", "chart:logarithmic": "false", "chart:reverse-direction": "false", "text:line-break": "false"}, []), x.el("style:graphic-properties", {"svg:stroke-color": "#B3B3B3"}, []), x.el("style:text-properties", {"fo:font-size": "10pt", "fo:color": "#595959"}, [])], null, null, "ch")
        wall := bank.add("chart", [x.el("style:graphic-properties", {"draw:stroke": "none", "draw:fill": "none"}, [])], null, null, "ch")
        append(plot["children"], x.el("chart:wall", {"chart:style-name": wall}, []))
        xa := x.el("chart:axis", {"chart:dimension": "x", "chart:name": "primary-x", "chart:style-name": axs}, [])
        if u.get(o, "x_title", null) != null:
            append(xa["children"], x.el("chart:title", null, [x.el("text:p", null, [o["x_title"]])]))
        if kind != "scatter" and n > 0:
            append(xa["children"], x.el("chart:categories", {"table:cell-range-address": _cell_addr(1, 2) + ":." + "$A$" + str(n + 1)}, []))
        append(plot["children"], xa)
        ya := x.el("chart:axis", {"chart:dimension": "y", "chart:name": "primary-y", "chart:style-name": axs}, [])
        if u.get(o, "y_title", null) != null:
            append(ya["children"], x.el("chart:title", null, [x.el("text:p", null, [o["y_title"]])]))
        grs := bank.add("chart", [x.el("style:graphic-properties", {"svg:stroke-color": "#D9D9D9"}, [])], null, null, "ch")
        append(ya["children"], x.el("chart:grid", {"chart:class": "major", "chart:style-name": grs}, []))
        append(plot["children"], ya)
    k := 0
    for s in series:
        col := k + 2
        color := u.get(s, "color", null)
        if color == null:
            color = CHART_COLORS[k % len(CHART_COLORS)]
        gp := {"draw:fill-color": "#" + u.color_hex(color), "svg:stroke-color": "#" + u.color_hex(color)}
        if kind == "line" or kind == "scatter":
            gp["svg:stroke-width"] = "0.08cm"
        scp := {}
        if u.get(o, "data_labels", false):
            scp["chart:data-label-number"] = "value"
        kids := []
        if len(keys(scp)) > 0:
            append(kids, x.el("style:chart-properties", scp, []))
        append(kids, x.el("style:graphic-properties", gp, []))
        ss := bank.add("chart", kids, null, null, "ch")
        lc := u.column_letter(col)
        ser := x.el("chart:series", {"chart:style-name": ss, "chart:values-cell-range-address": "local-table.$" + lc + "$2:.$" + lc + "$" + str(n + 1), "chart:label-cell-address": "local-table.$" + lc + "$1", "chart:class": cls}, [])
        if kind == "scatter" and n > 0:
            append(ser["children"], x.el("chart:domain", {"table:cell-range-address": "local-table.$A$2:.$A$" + str(n + 1)}, []))
        if (kind == "pie" or kind == "doughnut") and n > 0:
            j := 0
            while j < n:
                pc := CHART_COLORS[j % len(CHART_COLORS)]
                dps := bank.add("chart", [x.el("style:graphic-properties", {"draw:fill-color": "#" + pc, "svg:stroke-color": "#FFFFFF"}, [])], null, null, "ch")
                append(ser["children"], x.el("chart:data-point", {"chart:style-name": dps}, []))
                j = j + 1
        elif n > 0:
            append(ser["children"], x.el("chart:data-point", {"chart:repeated": str(n)}, []))
        append(plot["children"], ser)
        k = k + 1
    append(chart["children"], plot)
    # table locale
    tbl := x.el("table:table", {"table:name": "local-table"}, [x.el("table:table-header-columns", null, [x.el("table:table-column", null, [])]), x.el("table:table-columns", null, [x.el("table:table-column", {"table:number-columns-repeated": str(len(series) if len(series) > 0 else 1)}, [])])])
    hdr := x.el("table:table-row", null, [x.el("table:table-cell", null, [x.el("text:p", null, [])])])
    for s in series:
        append(hdr["children"], _chart_cell(u.to_text(u.get(s, "name", ""))))
    append(tbl["children"], x.el("table:table-header-rows", null, [hdr]))
    rows := x.el("table:table-rows", null, [])
    i := 0
    while i < n:
        r := x.el("table:table-row", null, [_chart_cell(categories[i])])
        for s in series:
            vals := u.get(s, "values", [])
            append(r["children"], _chart_cell(vals[i] if i < len(vals) else null))
        append(rows["children"], r)
        i = i + 1
    append(tbl["children"], rows)
    append(chart["children"], tbl)
    append(root["children"], x.el("office:automatic-styles", null, bank.nodes()))
    append(root["children"], x.el("office:body", null, [x.el("office:chart", null, [chart])]))
    return root

func _local_cell_value(cell):
    vt := x.attr(cell, "office:value-type", null)
    if vt == "float" or vt == "percentage" or vt == "currency":
        v := _n.num_parse(x.attr(cell, "office:value", "0"))
        return v
    t := node_text(x.first(cell, "text:p"))
    if vt == null and t == "":
        return null
    return t

# Relit un document graphique ODF -> {"kind", "title", "categories", "series", "stacked", "legend"} ou null.
func read_chart(root):
    chart := x.find(root, "chart:chart")
    if chart == null:
        return null
    cls := x.attr(chart, "chart:class", "chart:bar")
    idx := StyleIndex([root])
    plot := x.first(chart, "chart:plot-area")
    cp := idx.props("chart", x.attr(plot, "chart:style-name", null), "style:chart-properties") if plot != null else {}
    kind := "column"
    for k in keys(CHART_CLASSES):
        if CHART_CLASSES[k] == cls and kind == "column":
            kind = k
    if cls == "chart:bar":
        kind = "bar" if u.get(cp, "chart:vertical", "false") == "true" else "column"
    t := x.first(chart, "chart:title")
    leg := x.first(chart, "chart:legend")
    # table locale -> grille
    grid := []
    tbl := x.find(chart, "table:table")
    if tbl != null:
        for r in x.find_all(tbl, "table:table-row"):
            line := []
            for c in x.children(r, "table:table-cell"):
                rep := x.attr_int(c, "table:number-columns-repeated", 1)
                v := _local_cell_value(c)
                j := 0
                while j < rep and j < 256:
                    append(line, v)
                    j = j + 1
            append(grid, line)
    cats := []
    series := []
    if len(grid) > 0:
        hdr := grid[0]
        i := 1
        while i < len(grid):
            append(cats, grid[i][0] if len(grid[i]) > 0 else null)
            i = i + 1
        c := 1
        while c < len(hdr):
            vals := []
            i = 1
            while i < len(grid):
                append(vals, grid[i][c] if c < len(grid[i]) else null)
                i = i + 1
            s := {"name": u.to_text(hdr[c]) if hdr[c] != null else "Série " + str(c), "values": vals}
            append(series, s)
            c = c + 1
    # couleurs des séries
    k := 0
    if plot != null:
        for s in x.children(plot, "chart:series"):
            gp := idx.props("chart", x.attr(s, "chart:style-name", null), "style:graphic-properties")
            col := u.get(gp, "draw:fill-color", null)
            if col != null and k < len(series) and kind != "pie" and kind != "doughnut":
                series[k]["color"] = string.upper(_n.str_slice(col, 1, null))
            k = k + 1
    return {"kind": kind, "title": node_text(x.first(t, "text:p")) if t != null else null, "categories": cats, "series": series, "stacked": u.get(cp, "chart:stacked", "false") == "true", "legend": x.attr(leg, "chart:legend-position", "bottom") if leg != null else false}
