# ALEX STANDARD LIBRARY — office.pptx_reader
# Lecture des présentations PowerPoint (.pptx, .pptm, .potx, .ppsx) : taille, diapositives (formes, textes, images,
# tableaux, graphiques, groupes aplatis), disposition, fond, notes du présentateur, diapositives masquées,
# couleurs et polices du thème, métadonnées. Les macros ne sont ni lues ni exécutées.
#
#   use office.pptx_reader as reader
#   parts := reader.read("cours.pptx")
#   for s in parts["slides"]:                       # pptx_slides.Slide
#       print(s.title())
#   reader.read_text("cours.pptx")                  # texte de toutes les diapositives (et notes)
#
# read(chemin_ou_octets) -> {"slides", "width", "height", "theme", "metadata", "package"}
# read_text(src, notes=true) -> str   outline(src) -> [{"title", "texts", "notes"}]
# Erreurs : FormatError, PPTXError, XMLError, ArchiveError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.core as core
use office.metadata as metadata
use office.pptx_slides as sl
use office.xlsx_charts as xch

const _LAYOUT_TYPES := {"title": "title", "obj": "title_content", "tx": "title_content", "titleOnly": "title_only", "blank": "blank", "secHead": "section", "twoObj": "two_content", "twoTxTwoObj": "two_content", "objTx": "title_content", "picTx": "title_content", "vertTx": "title_content", "cust": "title_content"}

class _ReadCtx:
    func init(pkg, part):
        self.pkg = pkg
        self.part = part
        self._boxes = null

    # Position d'un espace réservé sans xfrm propre : celle de la disposition, sinon du masque.
    func placeholder_box(ph_type, idx):
        if self._boxes == null:
            self._boxes = []
            lay := self.pkg.target(self.part, core.REL_SLIDE_LAYOUT)
            if lay != null and self.pkg.has_part(lay):
                append(self._boxes, _ph_boxes(self.pkg.read_xml(lay)))
                mas := self.pkg.target(lay, core.REL_SLIDE_MASTER)
                if mas != null and self.pkg.has_part(mas):
                    append(self._boxes, _ph_boxes(self.pkg.read_xml(mas)))
        t := ph_type if ph_type != null else "obj"
        for table in self._boxes:
            if idx != null and contains_key(table, "idx:" + str(idx)):
                return table["idx:" + str(idx)]
            if contains_key(table, "type:" + t):
                return table["type:" + t]
            if (t == "ctrTitle" or t == "title") and contains_key(table, "type:title"):
                return table["type:title"]
            if (t == "obj" or t == "subTitle") and contains_key(table, "type:body"):
                return table["type:body"]
        return null

    func link(rid):
        r := self.pkg.rel(self.part, rid)
        if r == null:
            return null
        if string.ends_with(r["type"], "/slide"):
            return "#" + r["target"]
        return r["target"]

    func image(rid):
        r := self.pkg.rel(self.part, rid)
        if r == null or r["mode"] == "External":
            return null
        t := self.pkg.resolve(self.part, r["target"])
        if not self.pkg.has_part(t):
            return null
        return self.pkg.read_part(t)

    func chart(rid):
        r := self.pkg.rel(self.part, rid)
        if r == null:
            return null
        t := self.pkg.resolve(self.part, r["target"])
        if not self.pkg.has_part(t):
            return null
        try:
            return xch.parse_chart(self.pkg.read_xml(t))
        catch e:
            return null

func _ph_boxes(root):
    out := {}
    for sp in x.find_all(root, "p:sp"):
        ph := x.find(sp, "p:ph")
        xf := x.find(x.first(sp, "p:spPr"), "a:xfrm") if x.first(sp, "p:spPr") != null else null
        if ph == null or xf == null:
            continue
        off := x.first(xf, "a:off")
        ext := x.first(xf, "a:ext")
        box := [x.attr_int(off, "x", 0), x.attr_int(off, "y", 0), x.attr_int(ext, "cx", 0), x.attr_int(ext, "cy", 0)]
        idx := x.attr(ph, "idx", null)
        if idx != null:
            out["idx:" + idx] = box
        out["type:" + x.attr(ph, "type", "obj")] = box
    return out

func _layout_name(pkg, part):
    t := pkg.target(part, core.REL_SLIDE_LAYOUT)
    if t == null or not pkg.has_part(t):
        return "title_content"
    root := pkg.read_xml(t)
    typ := x.attr(root, "type", "cust")
    if contains_key(_LAYOUT_TYPES, typ):
        return _LAYOUT_TYPES[typ]
    return "title_content"

func _notes_text(pkg, part):
    t := pkg.target(part, core.REL_NOTES_SLIDE)
    if t == null or not pkg.has_part(t):
        return null
    root := pkg.read_xml(t)
    for sp in x.find_all(root, "p:sp"):
        ph := x.find(sp, "p:ph")
        if ph != null and x.attr(ph, "type", "") == "body":
            lines := []
            for p in x.find_all(sp, "a:p"):
                parts := []
                for r in x.find_all(p, "a:t"):
                    append(parts, x.text(r))
                append(lines, string.join("", parts))
            t2 := string.trim(string.join("\n", lines))
            return t2 if t2 != "" else null
    return null

func _theme(pkg, main):
    out := {}
    mt := pkg.target(main, core.REL_SLIDE_MASTER)
    if mt == null:
        return out
    tt := pkg.target(mt, core.REL_THEME)
    if tt == null or not pkg.has_part(tt):
        return out
    root := pkg.read_xml(tt)
    out["name"] = x.attr(root, "name", "")
    cs := x.find(root, "a:clrScheme")
    if cs != null:
        accents := []
        k := 1
        while k <= 6:
            a := x.first(cs, "a:accent" + str(k))
            c := x.find(a, "a:srgbClr") if a != null else null
            append(accents, x.attr(c, "val", "000000") if c != null else "000000")
            k = k + 1
        out["colors"] = accents
    mj := x.find(root, "a:majorFont")
    if mj != null:
        out["major_font"] = x.attr(x.first(mj, "a:latin"), "typeface", "Calibri Light")
    mn := x.find(root, "a:minorFont")
    if mn != null:
        out["minor_font"] = x.attr(x.first(mn, "a:latin"), "typeface", "Calibri")
    return out

func read(src):
    pkg := core.open_package(src)
    main := pkg.main_part()
    ct := pkg.content_type(main)
    if ct != null and not string.contains(ct, "presentationml"):
        errors.fail(errors.FORMAT, "ce paquet n'est pas une présentation PowerPoint (" + ct + ")")
    root := pkg.read_xml(main)
    w := 12192000
    h := 6858000
    sz := x.first(root, "p:sldSz")
    if sz != null:
        w = x.attr_int(sz, "cx", w)
        h = x.attr_int(sz, "cy", h)
    slides := []
    lst := x.first(root, "p:sldIdLst")
    if lst != null:
        for sid in x.children(lst, "p:sldId"):
            r := pkg.rel(main, x.attr(sid, "r:id", ""))
            if r == null:
                continue
            part := pkg.resolve(main, r["target"])
            if not pkg.has_part(part):
                continue
            s := sl.parse_slide(pkg.read_xml(part), _ReadCtx(pkg, part), _layout_name(pkg, part), w, h)
            s.notes = _notes_text(pkg, part)
            append(slides, s)
    return {"slides": slides, "width": w, "height": h, "theme": _theme(pkg, main), "metadata": metadata.from_package(pkg), "package": pkg}

func outline(src):
    out := []
    for s in read(src)["slides"]:
        append(out, {"title": s.title(), "texts": s.texts(), "notes": s.notes})
    return out

func read_text(src, notes=true):
    blocks := []
    k := 1
    for s in read(src)["slides"]:
        lines := ["--- Diapositive " + str(k) + " ---"]
        for t in s.texts():
            append(lines, t)
        if notes and s.notes != null:
            append(lines, "[Notes] " + s.notes)
        append(blocks, string.join("\n", lines))
        k = k + 1
    return string.join("\n\n", blocks)
