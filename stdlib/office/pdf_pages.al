# ALEX STANDARD LIBRARY — office.pdf_pages
# Opérations sur les pages de PDF existants : rotation, recadrage, suppression, réorganisation, extraction,
# insertion de pages blanches, inversion, mise à l'échelle vers un format, tampon de texte, filigrane,
# numérotation, superposition d'une page d'un autre PDF. Le résultat est un nouveau PDF (déchiffré, compact) ;
# liens, annotations et signets sont conservés quand leurs pages cibles le sont.
#
#   use office.pdf_pages as pages
#   pages.rotate("scan.pdf", "scan-droit.pdf", 90)                 # toutes les pages
#   pages.delete_pages("doc.pdf", "court.pdf", [0, 5])             # indices à partir de 0
#   pages.reorder("doc.pdf", "ordre.pdf", [2, 0, 1])
#   pages.watermark("doc.pdf", "brouillon.pdf", "BROUILLON")
#   pages.number_pages("doc.pdf", "numerote.pdf", "Page {page} / {total}")
#   pages.info("doc.pdf")                                          # [{"index", "width", "height", "rotation"}]
#
# Les fonctions prennent src (chemin, octets ou pdf_reader.PdfFile) et out (chemin ; null : renvoie les octets).
# pages : null (toutes), un indice, une liste d'indices ou un texte « 1-3,5,8- » (numéros à partir de 1).
#   info(src)  page_count(src)  parse_pages("1-3,5", total) -> indices
#   rotate(src, out, degrees, pages=null)  set_rotation(src, out, degrees, pages=null)
#   crop(src, out, box, pages=null)  (box : [x0, y0, x1, y1] en points, ou marges [g, b, d, h] avec margins=true)
#   delete_pages(src, out, pages)  keep_pages / extract(src, out, pages)  reorder(src, out, ordre)  reverse(src, out)
#   insert_blank(src, out, after, size=null)  duplicate(src, out, index, count=1)
#   scale_to(src, out, size="A4", landscape=false)   (contenu mis à l'échelle et centré)
#   stamp_text(src, out, texte, x, y, size=12, color="000000", pages=null, rotation=0, opacity=1.0, font="Helvetica")
#   watermark(src, out, texte, opacity=0.15, color="808080", size=null, pages=null)
#   number_pages(src, out, format="{page} / {total}", position="bottom-center", size=9, start=1, pages=null)
#   overlay(src, out, overlay_src, overlay_page=0, pages=null, under=false)
# PageComposer : add_page(doc, index, rotate=null) -> indice  add_blank(w, h)  add_form_page(doc, index, w, h)
#   stamp(i, opérateurs, polices)  add_bookmark(titre, page, level=1)  copy_outlines(doc, correspondance)
#   to_bytes(info=null)  save(chemin, info=null)
# Erreurs : PDFError, IndexError, ValueError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use math
use office.errors as errors
use office.utils as u
use office.core as core
use office.compression as compression
use office.pdf_reader as pr
use office.pdf_writer as pw

func _open(src, password=""):
    if isinstance(src, pr.PdfFile):
        return src
    return pr.open(src, password)

# « 1-3,5,8- » -> indices (0..) ; accepte aussi un entier ou une liste d'indices.
func parse_pages(spec, total):
    if spec == null:
        out := []
        k := 0
        while k < total:
            append(out, k)
            k = k + 1
        return out
    if type(spec) == "int":
        i := spec + total if spec < 0 else spec
        if i < 0 or i >= total:
            raise("IndexError", "page " + str(spec) + " absente (" + str(total) + " pages)")
        return [i]
    if type(spec) == "list":
        out := []
        for i in spec:
            for j in parse_pages(i, total):
                append(out, j)
        return out
    out := []
    for part in string.split(u.to_text(spec), ","):
        p := string.trim(part)
        if p == "":
            continue
        if string.contains(p, "-"):
            ab := string.split(p, "-")
            a := string.trim(ab[0])
            b := string.trim(ab[1])
            lo := 1 if a == "" else to_int(u.parse_number(a))
            hi := total if b == "" else to_int(u.parse_number(b))
            if lo < 1 or hi > total or lo > hi:
                raise("ValueError", "plage de pages invalide : '" + p + "' (" + str(total) + " pages)")
            k := lo
            while k <= hi:
                append(out, k - 1)
                k = k + 1
        else:
            n := u.parse_number(p)
            if n == null or n < 1 or n > total:
                raise("ValueError", "numéro de page invalide : '" + p + "' (" + str(total) + " pages)")
            append(out, to_int(n) - 1)
    return out

func _ident(doc):
    # identité d'un document pour les tables de correspondance (un objet par document)
    return str(len(doc.data)) + ":" + str(_n.crc32(_n.bytes_slice(doc.data, 0, 2048), 0))

class PageComposer:
    func init():
        self.w = pw.ObjectWriter()
        self.pages = []
        self.memos = {}
        self.bookmarks = []
        self._fonts = {}
        self.pages_ref = self.w.alloc()

    func _memo(doc):
        key := _ident(doc)
        if not contains_key(self.memos, key):
            m := {}
            for p in doc.pages():
                if p.ref != null:
                    m[p.ref.num] = null
            # le nœud racine des pages ne doit jamais être recopié
            pr_root := u.get(doc.catalog, "Pages", null)
            if pr.is_ref(pr_root):
                m[pr_root.num] = null
            self.memos[key] = m
        return self.memos[key]

    func add_page(doc, index, rotate=null):
        p := doc.page(index)
        memo := self._memo(doc)
        ref := self.w.alloc()
        if p.ref != null:
            memo[p.ref.num] = ref
        d := {}
        for k in keys(p.dict):
            if k != "Parent" and k != "B" and k != "Thumb":
                d[k] = p.dict[k]
        for k in ["Resources", "MediaBox", "CropBox", "Rotate"]:
            if not contains_key(d, k) and contains_key(p.inherited, k):
                d[k] = p.inherited[k]
        if not contains_key(d, "MediaBox"):
            d["MediaBox"] = [0, 0, 612, 792]
        nd := self.w.import_value(doc, d, memo)
        nd["Parent"] = self.pages_ref
        nd["Type"] = "/Page"
        if rotate != null:
            nd["Rotate"] = rotate % 360
        self.w.set(ref, nd)
        append(self.pages, ref)
        return len(self.pages) - 1

    func add_blank(width=595.28, height=841.89):
        ref := self.w.add({"Type": "/Page", "Parent": self.pages_ref, "MediaBox": [0, 0, width, height], "Resources": {}, "Contents": self.w.add(pw.flate_stream({}, ""))})
        append(self.pages, ref)
        return len(self.pages) - 1

    func page_dict(i):
        return self.w.get(self.pages[i])

    # Page d'un autre document importée comme formulaire (XObject) : utilisable dans un contenu par /Nom Do.
    func form_xobject(doc, index):
        p := doc.page(index)
        memo := self._memo(doc)
        box := p.crop_box()
        res := self.w.import_value(doc, p.resources(), memo)
        content := p.contents()
        return self.w.add(pw.flate_stream({"Type": "/XObject", "Subtype": "/Form", "BBox": [box[0], box[1], box[2], box[3]], "Resources": res}, content))

    # Nouvelle page w × h dont le contenu est la page source mise à l'échelle et centrée.
    func add_form_page(doc, index, width, height):
        p := doc.page(index)
        form := self.form_xobject(doc, index)
        box := p.crop_box()
        bw := box[2] - box[0]
        bh := box[3] - box[1]
        rot := p.rotation()
        sw := bh if rot == 90 or rot == 270 else bw
        sh := bw if rot == 90 or rot == 270 else bh
        s := to_float(width) / sw
        if to_float(height) / sh < s:
            s = to_float(height) / sh
        tx := (to_float(width) - sw * s) / 2.0
        ty := (to_float(height) - sh * s) / 2.0
        # rotation de la page source appliquée au formulaire
        m := ""
        if rot == 90:
            m = "0 -1 1 0 0 " + pw._num(bw) + " cm "
        elif rot == 180:
            m = "-1 0 0 -1 " + pw._num(bw) + " " + pw._num(bh) + " cm "
        elif rot == 270:
            m = "0 1 -1 0 " + pw._num(bh) + " 0 cm "
        ops := "q " + pw._num(s) + " 0 0 " + pw._num(s) + " " + pw._num(tx) + " " + pw._num(ty) + " cm " + m + "1 0 0 1 " + pw._num(-box[0]) + " " + pw._num(-box[1]) + " cm /P0 Do Q"
        ref := self.w.add({"Type": "/Page", "Parent": self.pages_ref, "MediaBox": [0, 0, width, height], "Resources": {"XObject": {"P0": form}}, "Contents": self.w.add(pw.flate_stream({}, ops))})
        append(self.pages, ref)
        return len(self.pages) - 1

    func _font_ref(name):
        if not contains_key(self._fonts, name):
            self._fonts[name] = self.w.add({"Type": "/Font", "Subtype": "/Type1", "BaseFont": "/" + name, "Encoding": "/WinAnsiEncoding"})
        return self._fonts[name]

    # Ajoute des opérateurs de contenu au-dessus (ou en dessous, under=true) d'une page. resources : dict à fusionner
    # dans les ressources de la page, par catégorie ({"Font": {...}, "XObject": {...}, "ExtGState": {...}}).
    func stamp(i, ops, resources=null, under=false):
        d := self.page_dict(i)
        res := d["Resources"] if contains_key(d, "Resources") else {}
        if pr.is_ref(res):
            res = self.w.get(res)
        res = u.merge(res, null)
        if resources != null:
            for cat in keys(resources):
                sub := res[cat] if contains_key(res, cat) else {}
                if pr.is_ref(sub):
                    sub = self.w.get(sub)
                sub = u.merge(sub, resources[cat])
                res[cat] = sub
        d["Resources"] = res
        cur := d["Contents"] if contains_key(d, "Contents") else null
        parts := []
        if cur != null:
            if type(cur) == "list":
                parts = cur
            else:
                parts = [cur]
        new_ref := self.w.add(pw.flate_stream({}, ops))
        if under:
            d["Contents"] = _prepend(new_ref, parts)
        else:
            qa := self.w.add(pw.flate_stream({}, "q"))
            qb := self.w.add(pw.flate_stream({}, "Q"))
            out := [qa]
            for p in parts:
                append(out, p)
            append(out, qb)
            append(out, new_ref)
            d["Contents"] = out

    func add_bookmark(title, page, level=1, top=null):
        append(self.bookmarks, {"title": title, "page": page, "level": level, "top": top})

    # Recopie les signets d'un document ; mapping : indice de page source -> indice de page composée.
    func copy_outlines(doc, mapping, level_offset=0):
        for o in doc.outlines():
            pi := o["page"]
            if contains_key(mapping, pi):
                self.add_bookmark(o["title"], mapping[pi], o["level"] + level_offset)

    func to_bytes(info=null):
        self.w.set(self.pages_ref, {"Type": "/Pages", "Kids": self.pages, "Count": len(self.pages)})
        cat := {"Type": "/Catalog", "Pages": self.pages_ref}
        ol := pw.outline_tree(self.w, self.bookmarks, self.pages)
        if ol != null:
            cat["Outlines"] = ol
            cat["PageMode"] = "/UseOutlines"
        root := self.w.add(cat)
        inf := {"Producer": pw.pdf_string("ALEX Office")}
        if info != null:
            for k in keys(info):
                v := info[k]
                if v != null:
                    inf[k] = pw.pdf_string(v) if type(v) == "str" else v
        return self.w.to_bytes(root, self.w.add(inf), "1.7")

    func save(path, info=null):
        io.write_bytes(path, self.to_bytes(info))
        return path

func _prepend(x, l):
    out := [x]
    for v in l:
        append(out, v)
    return out

func _finish(comp, out, doc):
    info := doc.info() if doc != null else null
    data := comp.to_bytes(info)
    if out == null:
        return data
    io.write_bytes(out, data)
    return out

# Compose une sortie à partir d'une liste d'indices (avec rotation facultative par page) en conservant les signets.
func _compose(doc, indices, rotations=null):
    comp := PageComposer()
    mapping := {}
    k := 0
    for i in indices:
        rot := null
        if rotations != null and contains_key(rotations, i):
            rot = rotations[i]
        j := comp.add_page(doc, i, rot)
        if not contains_key(mapping, i):
            mapping[i] = j
        k = k + 1
    comp.copy_outlines(doc, mapping)
    return comp

func info(src, password=""):
    doc := _open(src, password)
    out := []
    for p in doc.pages():
        append(out, {"index": p.index, "width": p.width(), "height": p.height(), "rotation": p.rotation(), "media_box": p.media_box(), "crop_box": p.crop_box()})
    return out

func page_count(src, password=""):
    return _open(src, password).page_count()

func rotate(src, out, degrees, pages=null, password=""):
    if degrees % 90 != 0:
        raise("ValueError", "rotation multiple de 90° attendue (obtenu " + str(degrees) + ")")
    doc := _open(src, password)
    sel := {}
    for i in parse_pages(pages, doc.page_count()):
        sel[i] = true
    rots := {}
    for p in doc.pages():
        if contains_key(sel, p.index):
            rots[p.index] = (p.rotation() + degrees) % 360
    return _finish(_compose(doc, parse_pages(null, doc.page_count()), rots), out, doc)

func set_rotation(src, out, degrees, pages=null, password=""):
    doc := _open(src, password)
    rots := {}
    for i in parse_pages(pages, doc.page_count()):
        rots[i] = degrees % 360
    return _finish(_compose(doc, parse_pages(null, doc.page_count()), rots), out, doc)

func crop(src, out, box, pages=null, margins=false, password=""):
    doc := _open(src, password)
    comp := _compose(doc, parse_pages(null, doc.page_count()))
    for i in parse_pages(pages, doc.page_count()):
        p := doc.page(i)
        b := box
        if margins:
            mb := p.crop_box()
            b = [mb[0] + box[0], mb[1] + box[1], mb[2] - box[2], mb[3] - box[3]]
        d := comp.page_dict(i)
        d["CropBox"] = [b[0], b[1], b[2], b[3]]
    return _finish(comp, out, doc)

func delete_pages(src, out, pages, password=""):
    doc := _open(src, password)
    drop := {}
    for i in parse_pages(pages, doc.page_count()):
        drop[i] = true
    keep := []
    for p in doc.pages():
        if not contains_key(drop, p.index):
            append(keep, p.index)
    if len(keep) == 0:
        errors.fail(errors.PDF, "impossible de supprimer toutes les pages")
    return _finish(_compose(doc, keep), out, doc)

func extract(src, out, pages, password=""):
    doc := _open(src, password)
    idx := parse_pages(pages, doc.page_count())
    if len(idx) == 0:
        errors.fail(errors.PDF, "aucune page sélectionnée")
    return _finish(_compose(doc, idx), out, doc)

func keep_pages(src, out, pages, password=""):
    return extract(src, out, pages, password)

func reorder(src, out, order, password=""):
    doc := _open(src, password)
    return _finish(_compose(doc, parse_pages(order, doc.page_count())), out, doc)

func reverse(src, out, password=""):
    doc := _open(src, password)
    idx := []
    k := doc.page_count() - 1
    while k >= 0:
        append(idx, k)
        k = k - 1
    return _finish(_compose(doc, idx), out, doc)

func duplicate(src, out, index, count=1, password=""):
    doc := _open(src, password)
    idx := []
    for p in doc.pages():
        append(idx, p.index)
        if p.index == index:
            k := 0
            while k < count:
                append(idx, p.index)
                k = k + 1
    return _finish(_compose(doc, idx), out, doc)

# Insère une page blanche après la page `after` (-1 : en tête). size : null = même format que la page voisine.
func insert_blank(src, out, after, size=null, password=""):
    doc := _open(src, password)
    comp := PageComposer()
    mapping := {}
    if after < 0:
        wh := core.page_size(size) if size != null else [doc.page(0).width(), doc.page(0).height()]
        comp.add_blank(wh[0], wh[1])
    for p in doc.pages():
        mapping[p.index] = comp.add_page(doc, p.index)
        if p.index == after:
            wh := core.page_size(size) if size != null else [p.width(), p.height()]
            comp.add_blank(wh[0], wh[1])
    comp.copy_outlines(doc, mapping)
    return _finish(comp, out, doc)

func scale_to(src, out, size="A4", landscape=false, password=""):
    doc := _open(src, password)
    wh := core.page_size(size, landscape)
    comp := PageComposer()
    mapping := {}
    for p in doc.pages():
        mapping[p.index] = comp.add_form_page(doc, p.index, wh[0], wh[1])
    comp.copy_outlines(doc, mapping)
    return _finish(comp, out, doc)

# ---------------------------------------------------------------------------------------------- tampons

func _text_ops(text, x0, y0, size, color, rotation, font_res, font, opacity_res=null):
    rgb := u.color_floats(color)
    r := to_float(rotation) * math.PI / 180.0
    c := math.cos(r)
    s := math.sin(r)
    gs := ("/" + opacity_res + " gs ") if opacity_res != null else ""
    enc := pw._string(u.cp1252_encode(u.to_text(text), 63))
    return "q " + gs + pw._num(rgb[0]) + " " + pw._num(rgb[1]) + " " + pw._num(rgb[2]) + " rg BT /" + font_res + " " + pw._num(size) + " Tf " + pw._num(c) + " " + pw._num(s) + " " + pw._num(-s) + " " + pw._num(c) + " " + pw._num(x0) + " " + pw._num(y0) + " Tm " + enc + " Tj ET Q"

func _stamp_all(doc, out, pages, maker):
    comp := _compose(doc, parse_pages(null, doc.page_count()))
    sel := parse_pages(pages, doc.page_count())
    total := doc.page_count()
    for i in sel:
        p := doc.page(i)
        r := maker(comp, p, i, total)
        comp.stamp(i, r[0], r[1])
    return _finish(comp, out, doc)

# Coordonnées d'origine de la page (coin inférieur gauche de la boîte visible) et dimensions non pivotées.
func _box(p):
    return p.crop_box()

func stamp_text(src, out, text, x0, y0, size=12, color="000000", pages=null, rotation=0, opacity=1.0, font="Helvetica", password=""):
    doc := _open(src, password)
    fname := pw.resolve_font(font)
    if string.starts_with(fname, "ttf:"):
        fname = "Helvetica"
    maker := (comp, p, i, total) => _stamp_maker(comp, p, text, x0, y0, size, color, rotation, opacity, fname)
    return _stamp_all(doc, out, pages, maker)

func _stamp_maker(comp, p, text, x0, y0, size, color, rotation, opacity, fname):
    b := _box(p)
    res := {"Font": {"AlexF1": comp._font_ref(fname)}}
    gs := null
    if opacity < 1.0:
        res["ExtGState"] = {"AlexGS1": {"Type": "/ExtGState", "ca": opacity, "CA": opacity}}
        gs = "AlexGS1"
    return [_text_ops(text, b[0] + to_float(x0), b[1] + to_float(y0), size, color, rotation, "AlexF1", fname, gs), res]

func watermark(src, out, text, opacity=0.15, color="808080", size=null, pages=null, password=""):
    doc := _open(src, password)
    maker := (comp, p, i, total) => _watermark_maker(comp, p, text, opacity, color, size)
    return _stamp_all(doc, out, pages, maker)

func _watermark_maker(comp, p, text, opacity, color, size):
    b := _box(p)
    w := b[2] - b[0]
    h := b[3] - b[1]
    diag := (w * w + h * h) ** 0.5
    sz := size
    if sz == null:
        tw := pw.text_width(text, "Helvetica-Bold", 100.0)
        sz = 100.0 * diag * 0.7 / (tw if tw > 0 else 1.0)
    angle := math.atan2(h, w) * 180.0 / math.PI
    tw := pw.text_width(text, "Helvetica-Bold", sz)
    r := angle * math.PI / 180.0
    cx := b[0] + w / 2.0 - (tw / 2.0) * math.cos(r) + (sz * 0.35) * math.sin(r)
    cy := b[1] + h / 2.0 - (tw / 2.0) * math.sin(r) - (sz * 0.35) * math.cos(r)
    res := {"Font": {"AlexWM": comp._font_ref("Helvetica-Bold")}, "ExtGState": {"AlexWMGS": {"Type": "/ExtGState", "ca": opacity, "CA": opacity}}}
    return [_text_ops(text, cx, cy, sz, color, angle, "AlexWM", "Helvetica-Bold", "AlexWMGS"), res]

func number_pages(src, out, fmt="{page} / {total}", position="bottom-center", size=9, start=1, pages=null, color="000000", margin=28, password=""):
    doc := _open(src, password)
    maker := (comp, p, i, total) => _number_maker(comp, p, i, total, fmt, position, size, start, color, margin)
    return _stamp_all(doc, out, pages, maker)

func _number_maker(comp, p, i, total, fmt, position, size, start, color, margin):
    b := _box(p)
    text := string.replace(string.replace(fmt, "{page}", str(i + start)), "{total}", str(total + start - 1))
    tw := pw.text_width(text, "Helvetica", size)
    w := b[2] - b[0]
    h := b[3] - b[1]
    x0 := b[0] + w / 2.0 - tw / 2.0
    if string.ends_with(position, "left"):
        x0 = b[0] + margin
    elif string.ends_with(position, "right"):
        x0 = b[2] - margin - tw
    y0 := b[1] + margin
    if string.starts_with(position, "top"):
        y0 = b[3] - margin - size
    res := {"Font": {"AlexPN": comp._font_ref("Helvetica")}}
    return [_text_ops(text, x0, y0, size, color, 0, "AlexPN", "Helvetica"), res]

func overlay(src, out, overlay_src, overlay_page=0, pages=null, under=false, password=""):
    doc := _open(src, password)
    ov := _open(overlay_src)
    comp := _compose(doc, parse_pages(null, doc.page_count()))
    form := comp.form_xobject(ov, overlay_page)
    ob := ov.page(overlay_page).crop_box()
    for i in parse_pages(pages, doc.page_count()):
        b := doc.page(i).crop_box()
        ops := "q 1 0 0 1 " + pw._num(b[0] - ob[0]) + " " + pw._num(b[1] - ob[1]) + " cm /AlexOV Do Q"
        comp.stamp(i, ops, {"XObject": {"AlexOV": form}}, under)
    return _finish(comp, out, doc)
