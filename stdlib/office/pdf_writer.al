# ALEX STANDARD LIBRARY — office.pdf_writer
# Écriture PDF : sérialisation des objets, table de références croisées, réécriture complète d'un PDF existant
# (déchiffré, flux d'objets dépliés), import d'objets entre documents, polices (14 polices standard en
# WinAnsiEncoding avec métriques ; TrueType incorporées en Identity-H, sous-ensemble des glyphes utilisés, ToUnicode
# pour la recherche et le copier-coller), images (JPEG direct, PNG avec transparence), dessin vectoriel, texte,
# liens, signets, métadonnées.
#
#   use office.pdf_writer as pw
#   doc := pw.PdfBuilder()
#   c := doc.new_page("A4")                          # Canvas ; origine en bas à gauche, unités en points
#   c.set_font("Helvetica-Bold", 18)
#   c.text(72, 770, "Rapport annuel")
#   c.set_font("Helvetica", 11)
#   h := c.text_box(72, 740, 451, 200, "Un long texte qui sera coupé en lignes...", "justify")
#   c.set_fill("4472C4")
#   c.rect(72, 500, 200, 100, true, false)
#   c.image("logo.png", 400, 700, 120)               # largeur 120 pt, hauteur proportionnelle
#   c.link(72, 480, 200, 15, "https://example.org")
#   doc.add_bookmark("Introduction", 0)
#   doc.info["Title"] = "Rapport"
#   doc.save("rapport.pdf")
#
#   pw.register_font("DejaVu", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", bold_path)   # Unicode complet
#
# OBJETS   serialize(v) -> octets   ObjectWriter : alloc() add(v) set(ref, v) get(ref) import_value(doc, v, memo,
#          skip=null) to_bytes(root, info=null, version="1.7")   rewrite(pdf_reader.PdfFile, info=null) -> octets
#          update_info(doc, info, chemin)   pdf_string(texte) -> PdfString (UTF-16BE si nécessaire)
# POLICES  STANDARD_FONTS  resolve_font(nom, bold=false, italic=false) -> nom de police  register_font(famille,
#          chemin, bold=null, italic=null, bold_italic=null)  text_width(texte, police, taille)  font_metrics(police)
#          -> {"ascent", "descent", "cap"} (unités pour 1000)   wrap_text(texte, largeur, police, taille) -> lignes
#          find_system_font(famille="sans", bold=false, italic=false) -> chemin ou null
# CANVAS   (page) width height  set_font(nom, taille)  set_fill(couleur)  set_stroke(couleur)  set_line_width(w)
#          set_dash(motif=null)  set_opacity(fill=1, stroke=null)  save_state() restore_state()  translate(x, y)
#          rotate(degrés)  scale(sx, sy)  move_to line_to curve_to close_path stroke() fill() fill_stroke() clip()
#          line(x1, y1, x2, y2)  rect(x, y, w, h, fill=false, stroke=true)  rounded_rect(x, y, w, h, r, fill, stroke)
#          circle(cx, cy, r, fill, stroke)  ellipse(cx, cy, rx, ry, fill, stroke)  polygon(points, fill, stroke)
#          text(x, y, texte, align="left")  text_width(texte)  text_box(x, y_haut, w, h, texte, align="left",
#          leading=null) -> hauteur utilisée   rich_line(x, y, segments) (segments : [texte, police, taille, couleur])
#          image(image, x, y, w=null, h=null) -> [w, h]   link(x, y, w, h, url)  link_page(x, y, w, h, index)
#          raw(opérateurs)
# DOCUMENT PdfBuilder(unicode=true) : new_page(size="A4", landscape=false) -> Canvas  pages  info  add_bookmark(titre,
#          page, level=1, y=null)  page_count()  to_bytes()  save(chemin)
# Erreurs : PDFError, UnsupportedError (image non prise en charge), FormatError (police TrueType invalide).

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

# ============================================================================================== sérialisation

func _num(v):
    if type(v) == "int":
        return str(v)
    if type(v) == "bool":
        return "true" if v else "false"
    f := to_float(v)
    if f != f:
        return "0"
    r := u.round_to(f, 4)
    if r == to_float(to_int(r)):
        return str(to_int(r))
    s := u.format_number(r)
    if string.contains(s, "E"):
        return "0"
    return s

const _NAME_SAFE := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.+*:,;=!?@~'`^|"

func _name(n):
    simple := true
    for c in n:
        if string.find(_NAME_SAFE, str(c)) < 0:
            simple = false
            break
    if simple:
        return "/" + n
    out := ["/"]
    for b in _n.utf8_encode(n):
        ch := str(string.chr(b))
        if b > 32 and b < 127 and string.find(_NAME_SAFE, ch) >= 0:
            append(out, ch)
        else:
            append(out, "#" + _n.hex_encode([b], true))
    return string.join("", out)

func _string(data):
    printable := true
    for b in data:
        if b < 32 or b > 126:
            printable = false
            break
    if not printable or len(data) == 0:
        if len(data) == 0:
            return "()"
        return "<" + _n.hex_encode(data, true) + ">"
    s := _n.latin1_decode(data)
    s = string.replace(s, "\\", "\\\\")
    s = string.replace(s, "(", "\\(")
    s = string.replace(s, ")", "\\)")
    return "(" + s + ")"

# Texte -> PdfString : PDFDocEncoding / Latin-1 si possible, sinon UTF-16BE avec BOM.
func pdf_string(text):
    t := u.to_text(text)
    ascii := true
    for c in t:
        o := string.ord(c)
        if o > 126 or o < 32:
            ascii = false
            break
    if ascii:
        return pr.PdfString(_n.utf8_encode(t))
    return pr.PdfString(u.utf16_encode(t, true, true), true)

func _ser(v, out):
    t := type(v)
    if v == null:
        append(out, "null")
    elif t == "int" or t == "float" or t == "bool":
        append(out, _num(v))
    elif t == "str":
        if string.starts_with(v, "/"):
            append(out, _name(_n.str_slice(v, 1, null)))
        else:
            append(out, _string(_n.utf8_encode(v)))
    elif t == "list" or t == "tuple":
        append(out, "[")
        first := true
        for x in v:
            if not first:
                append(out, " ")
            _ser(x, out)
            first = false
        append(out, "]")
    elif t == "dict":
        append(out, "<<")
        for k in keys(v):
            if v[k] == null:
                continue
            append(out, _name(k))
            append(out, " ")
            _ser(v[k], out)
            append(out, " ")
        append(out, ">>")
    elif isinstance(v, pr.Ref):
        append(out, str(v.num) + " " + str(v.gen) + " R")
    elif isinstance(v, pr.PdfString):
        append(out, _string(v.data) if not v.hex else "<" + _n.hex_encode(v.data, true) + ">")
    elif isinstance(v, pr.Stream):
        d := u.merge(v.dict, {"Length": len(v.raw)})
        _ser(d, out)
        append(out, "\nstream\n")
        append(out, v.raw)
        append(out, "\nendstream")
    else:
        append(out, "null")

func _flush(parts):
    out := []
    buf := []
    for p in parts:
        if type(p) == "str":
            append(buf, p)
        else:
            if len(buf) > 0:
                append(out, _n.utf8_encode(string.join("", buf)))
                buf = []
            append(out, p)
    if len(buf) > 0:
        append(out, _n.utf8_encode(string.join("", buf)))
    return u.concat(out)

func serialize(v):
    parts := []
    _ser(v, parts)
    return _flush(parts)

# Flux compressé (FlateDecode) à partir d'octets ou de texte.
func flate_stream(d, data):
    raw := u.bytes_of(data)
    return pr.Stream(u.merge(d, {"Filter": "/FlateDecode"}), compression.zlib_compress(raw, 6))

class ObjectWriter:
    func init():
        self.objects = []

    func alloc():
        append(self.objects, null)
        return pr.Ref(len(self.objects), 0)

    func add(v):
        r := self.alloc()
        self.objects[r.num - 1] = v
        return r

    func set(ref, v):
        self.objects[ref.num - 1] = v
        return ref

    func get(ref):
        return self.objects[ref.num - 1]

    # Copie profonde d'une valeur d'un PdfFile : chaque objet indirect atteint est recopié une seule fois
    # (memo : num source -> Ref cible). skip : clés de dictionnaire ignorées au premier niveau.
    func import_value(doc, v, memo, skip=null):
        if isinstance(v, pr.Ref):
            if contains_key(memo, v.num):
                return memo[v.num]
            target := self.alloc()
            memo[v.num] = target
            obj := doc.object(v.num, v.gen)
            self.objects[target.num - 1] = self.import_value(doc, obj, memo, null)
            return target
        t := type(v)
        if t == "list":
            out := []
            for x in v:
                append(out, self.import_value(doc, x, memo, null))
            return out
        if t == "dict":
            out := {}
            for k in keys(v):
                if skip != null and contains_key(skip, k):
                    continue
                out[k] = self.import_value(doc, v[k], memo, null)
            return out
        if isinstance(v, pr.Stream):
            d := {}
            for k in keys(v.dict):
                if k == "Length":
                    continue
                d[k] = self.import_value(doc, v.dict[k], memo, null)
            return pr.Stream(d, v.raw)
        return v

    func to_bytes(root, info=null, version="1.7", file_id=null):
        parts := [_n.utf8_encode("%PDF-" + version + "\n"), [37, 226, 227, 207, 211, 10]]
        offsets := []
        pos := len(parts[0]) + 6
        k := 1
        for o in self.objects:
            body := serialize(o)
            head := _n.utf8_encode(str(k) + " 0 obj\n")
            tail := _n.utf8_encode("\nendobj\n")
            append(offsets, pos)
            append(parts, head)
            append(parts, body)
            append(parts, tail)
            pos = pos + len(head) + len(body) + len(tail)
            k = k + 1
        xref := ["xref\n0 " + str(len(self.objects) + 1) + "\n0000000000 65535 f \n"]
        for off in offsets:
            append(xref, u.pad_left(str(off), 10, "0") + " 00000 n \n")
        fid := file_id
        if fid == null:
            h := _n.md5(_n.utf8_encode(u.now_iso() + str(len(self.objects)) + str(pos)))
            fid = [pr.PdfString(h, true), pr.PdfString(h, true)]
        tr := {"Size": len(self.objects) + 1, "Root": root, "Info": info, "ID": fid}
        append(xref, "trailer\n")
        append(parts, _n.utf8_encode(string.join("", xref)))
        append(parts, serialize(tr))
        append(parts, _n.utf8_encode("\nstartxref\n" + str(pos) + "\n%%EOF\n"))
        return u.concat(parts)

# Réécrit entièrement un PDF lu (objets atteignables depuis le catalogue) : déchiffré, sans flux d'objets.
# info : dict de textes remplaçant le dictionnaire Info (null : conservé).
func rewrite(doc, info=null):
    w := ObjectWriter()
    memo := {}
    root := w.import_value(doc, u.get(doc.trailer, "Root", null), memo)
    inf := null
    if info != null:
        d := {}
        for k in keys(info):
            v := info[k]
            if v != null:
                d[k] = pdf_string(v) if type(v) == "str" else v
        inf = w.add(d)
    elif contains_key(doc.trailer, "Info"):
        inf = w.import_value(doc, doc.trailer["Info"], memo)
    ver := doc.version if doc.version != null and len(doc.version) == 3 else "1.7"
    return w.to_bytes(root, inf, ver)

func update_info(doc, info, dest):
    merged := doc.info()
    for k in keys(info):
        merged[k] = info[k]
    io.write_bytes(dest, rewrite(doc, merged))
    return dest

# ============================================================================================== polices

const STANDARD_FONTS := {"Helvetica": {"widths": [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, 761, 556, 0, 222, 556, 333, 1000, 556, 556, 333, 1000, 667, 333, 1000, 0, 611, 0, 0, 222, 222, 333, 333, 350, 556, 1000, 333, 1000, 500, 333, 944, 0, 500, 667, 278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333, 400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611, 667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278, 722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611, 556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278, 556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500], "ascent": 718, "descent": -207, "cap": 718, "bbox": [-200, -250, 1000, 950]}, "Helvetica-Bold": {"widths": [278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611, 975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556, 333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611, 611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584, 761, 556, 0, 278, 556, 500, 1000, 556, 556, 333, 1000, 667, 333, 1000, 0, 611, 0, 0, 278, 278, 500, 500, 350, 556, 1000, 333, 1000, 556, 333, 944, 0, 500, 667, 278, 333, 556, 556, 556, 556, 280, 556, 333, 737, 370, 556, 584, 333, 737, 333, 400, 584, 333, 333, 333, 611, 556, 278, 333, 333, 365, 556, 834, 834, 834, 611, 722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278, 722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611, 556, 556, 556, 556, 556, 556, 889, 556, 556, 556, 556, 556, 278, 278, 278, 278, 611, 611, 611, 611, 611, 611, 611, 584, 611, 611, 611, 611, 611, 556, 611, 556], "ascent": 718, "descent": -207, "cap": 718, "bbox": [-200, -250, 1000, 950]}, "Helvetica-Oblique": {"widths": [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, 761, 556, 0, 222, 556, 333, 1000, 556, 556, 333, 1000, 667, 333, 1000, 0, 611, 0, 0, 222, 222, 333, 333, 350, 556, 1000, 333, 1000, 500, 333, 944, 0, 500, 667, 278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333, 400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611, 667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278, 722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611, 556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278, 556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500], "ascent": 718, "descent": -207, "cap": 718, "bbox": [-200, -250, 1000, 950]}, "Helvetica-BoldOblique": {"widths": [278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611, 975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556, 333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611, 611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584, 761, 556, 0, 278, 556, 500, 1000, 556, 556, 333, 1000, 667, 333, 1000, 0, 611, 0, 0, 278, 278, 500, 500, 350, 556, 1000, 333, 1000, 556, 333, 944, 0, 500, 667, 278, 333, 556, 556, 556, 556, 280, 556, 333, 737, 370, 556, 584, 333, 737, 333, 400, 584, 333, 333, 333, 611, 556, 278, 333, 333, 365, 556, 834, 834, 834, 611, 722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278, 722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611, 556, 556, 556, 556, 556, 556, 889, 556, 556, 556, 556, 556, 278, 278, 278, 278, 611, 611, 611, 611, 611, 611, 611, 584, 611, 611, 611, 611, 611, 556, 611, 556], "ascent": 718, "descent": -207, "cap": 718, "bbox": [-200, -250, 1000, 950]}, "Times-Roman": {"widths": [250, 333, 408, 500, 500, 833, 778, 180, 333, 333, 500, 564, 250, 333, 250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, 564, 564, 564, 444, 921, 722, 667, 667, 722, 611, 556, 722, 722, 333, 389, 722, 611, 889, 722, 722, 556, 722, 667, 556, 611, 722, 722, 944, 722, 722, 611, 333, 278, 333, 469, 500, 333, 444, 500, 444, 500, 444, 333, 500, 500, 278, 278, 500, 278, 778, 500, 500, 500, 500, 333, 389, 278, 500, 500, 722, 500, 500, 444, 480, 200, 480, 541, 761, 500, 0, 333, 500, 444, 1000, 500, 500, 333, 1000, 556, 333, 889, 0, 611, 0, 0, 333, 333, 444, 444, 350, 500, 1000, 333, 980, 389, 333, 722, 0, 444, 722, 250, 333, 500, 500, 500, 500, 200, 500, 333, 760, 276, 500, 564, 333, 760, 333, 400, 564, 300, 300, 333, 500, 453, 250, 333, 300, 310, 500, 750, 750, 750, 444, 722, 722, 722, 722, 722, 722, 889, 667, 611, 611, 611, 611, 333, 333, 333, 333, 722, 722, 722, 722, 722, 722, 722, 564, 722, 722, 722, 722, 722, 722, 556, 500, 444, 444, 444, 444, 444, 444, 667, 444, 444, 444, 444, 444, 278, 278, 278, 278, 500, 500, 500, 500, 500, 500, 500, 564, 500, 500, 500, 500, 500, 500, 500, 500], "ascent": 683, "descent": -217, "cap": 662, "bbox": [-200, -250, 1000, 950]}, "Times-Bold": {"widths": [250, 333, 555, 500, 500, 1000, 833, 278, 333, 333, 500, 570, 250, 333, 250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 570, 570, 570, 500, 930, 722, 667, 722, 722, 667, 611, 778, 778, 389, 500, 778, 667, 944, 722, 778, 611, 778, 722, 556, 667, 722, 722, 1000, 722, 722, 667, 333, 278, 333, 581, 500, 333, 500, 556, 444, 556, 444, 333, 500, 556, 278, 333, 556, 278, 833, 556, 500, 556, 556, 444, 389, 333, 556, 500, 722, 500, 500, 444, 394, 220, 394, 520, 761, 500, 0, 333, 500, 500, 1000, 500, 500, 333, 1000, 556, 333, 1000, 0, 667, 0, 0, 333, 333, 500, 500, 350, 500, 1000, 333, 1000, 389, 333, 722, 0, 444, 722, 250, 333, 500, 500, 500, 500, 220, 500, 333, 747, 300, 500, 570, 333, 747, 333, 400, 570, 300, 300, 333, 556, 540, 250, 333, 300, 330, 500, 750, 750, 750, 500, 722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 389, 389, 389, 389, 722, 722, 778, 778, 778, 778, 778, 570, 778, 722, 722, 722, 722, 722, 611, 556, 500, 500, 500, 500, 500, 500, 722, 444, 444, 444, 444, 444, 278, 278, 278, 278, 500, 556, 500, 500, 500, 500, 500, 570, 500, 556, 556, 556, 556, 500, 556, 500], "ascent": 676, "descent": -205, "cap": 662, "bbox": [-200, -250, 1000, 950]}, "Times-Italic": {"widths": [250, 333, 420, 500, 500, 833, 778, 214, 333, 333, 500, 675, 250, 333, 250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 675, 675, 675, 500, 920, 611, 611, 667, 722, 611, 611, 722, 722, 333, 444, 667, 556, 833, 667, 722, 611, 722, 611, 500, 556, 722, 611, 833, 611, 556, 556, 389, 278, 389, 422, 500, 333, 500, 500, 444, 500, 444, 278, 500, 500, 278, 278, 444, 278, 722, 500, 500, 500, 500, 389, 389, 278, 500, 444, 667, 444, 444, 389, 400, 275, 400, 541, 761, 500, 0, 333, 500, 556, 889, 500, 500, 333, 1000, 500, 333, 944, 0, 556, 0, 0, 333, 333, 556, 556, 350, 500, 889, 333, 980, 389, 333, 667, 0, 389, 556, 250, 389, 500, 500, 500, 500, 275, 500, 333, 760, 276, 500, 675, 333, 760, 333, 400, 675, 300, 300, 333, 500, 523, 250, 333, 300, 310, 500, 750, 750, 750, 500, 611, 611, 611, 611, 611, 611, 889, 667, 611, 611, 611, 611, 333, 333, 333, 333, 722, 667, 722, 722, 722, 722, 722, 675, 722, 722, 722, 722, 722, 556, 611, 500, 500, 500, 500, 500, 500, 500, 667, 444, 444, 444, 444, 444, 278, 278, 278, 278, 500, 500, 500, 500, 500, 500, 500, 675, 500, 500, 500, 500, 500, 444, 500, 444], "ascent": 683, "descent": -205, "cap": 662, "bbox": [-200, -250, 1000, 950]}, "Times-BoldItalic": {"widths": [250, 389, 555, 500, 500, 833, 778, 278, 333, 333, 500, 570, 250, 333, 250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 570, 570, 570, 500, 832, 667, 667, 667, 722, 667, 667, 722, 778, 389, 500, 667, 611, 889, 722, 722, 611, 722, 667, 556, 611, 722, 667, 889, 667, 611, 611, 333, 278, 333, 570, 500, 333, 500, 500, 444, 500, 444, 333, 500, 556, 278, 278, 500, 278, 778, 556, 500, 500, 500, 389, 389, 278, 556, 444, 667, 500, 444, 389, 348, 220, 348, 570, 761, 500, 0, 333, 500, 500, 1000, 500, 500, 333, 1000, 556, 333, 944, 0, 611, 0, 0, 333, 333, 500, 500, 350, 500, 1000, 333, 1000, 389, 333, 722, 0, 389, 611, 250, 389, 500, 500, 500, 500, 220, 500, 333, 747, 266, 500, 606, 333, 747, 333, 400, 570, 300, 300, 333, 576, 500, 250, 333, 300, 300, 500, 750, 750, 750, 500, 667, 667, 667, 667, 667, 667, 944, 667, 667, 667, 667, 667, 389, 389, 389, 389, 722, 722, 722, 722, 722, 722, 722, 570, 722, 722, 722, 722, 722, 611, 611, 500, 500, 500, 500, 500, 500, 500, 722, 444, 444, 444, 444, 444, 278, 278, 278, 278, 500, 556, 500, 500, 500, 500, 500, 570, 500, 556, 556, 556, 556, 444, 500, 444], "ascent": 699, "descent": -205, "cap": 662, "bbox": [-200, -250, 1000, 950]}, "Courier": {"widths": [600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 761, 600, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 0, 600, 0, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600], "ascent": 629, "descent": -157, "cap": 562, "bbox": [-200, -250, 1000, 950]}, "Courier-Bold": {"widths": [600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 761, 600, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 0, 600, 0, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600], "ascent": 626, "descent": -142, "cap": 562, "bbox": [-200, -250, 1000, 950]}, "Courier-Oblique": {"widths": [600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 761, 600, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 0, 600, 0, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600], "ascent": 629, "descent": -157, "cap": 562, "bbox": [-200, -250, 1000, 950]}, "Courier-BoldOblique": {"widths": [600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 761, 600, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 0, 600, 0, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 0, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600, 600], "ascent": 626, "descent": -142, "cap": 562, "bbox": [-200, -250, 1000, 950]}}

const _ALIASES := {"helvetica": "Helvetica", "arial": "Helvetica", "sans": "Helvetica", "sans-serif": "Helvetica", "calibri": "Helvetica", "verdana": "Helvetica", "segoe ui": "Helvetica", "liberation sans": "Helvetica", "dejavu sans": "Helvetica", "times": "Times", "times-roman": "Times", "times new roman": "Times", "serif": "Times", "georgia": "Times", "cambria": "Times", "garamond": "Times", "liberation serif": "Times", "courier": "Courier", "courier new": "Courier", "mono": "Courier", "monospace": "Courier", "consolas": "Courier", "liberation mono": "Courier", "dejavu sans mono": "Courier"}

_ttf_families := {}
_ttf_cache := {}

# Nom de police PDF pour une famille et un style. Les familles TrueType enregistrées sont prioritaires.
func resolve_font(name, bold=false, italic=false):
    if name == null:
        name = "Helvetica"
    if contains_key(STANDARD_FONTS, name) and not bold and not italic:
        return name
    low := string.lower(name)
    for fam in keys(_ttf_families):
        if string.lower(fam) == low:
            paths := _ttf_families[fam]
            key := "regular"
            if bold and italic:
                key = "bold_italic"
            elif bold:
                key = "bold"
            elif italic:
                key = "italic"
            if paths[key] != null:
                return "ttf:" + paths[key]
            return "ttf:" + paths["regular"]
    if string.starts_with(name, "ttf:"):
        return name
    base := name
    for suffix in ["-BoldOblique", "-BoldItalic", "-Bold", "-Oblique", "-Italic", "-Roman"]:
        if string.ends_with(base, suffix):
            if string.contains(suffix, "Bold"):
                bold = true
            if string.contains(suffix, "Oblique") or string.contains(suffix, "Italic"):
                italic = true
            base = _n.str_slice(base, 0, len(base) - len(suffix))
    fam := "Helvetica"
    lb := string.lower(base)
    if contains_key(_ALIASES, lb):
        fam = _ALIASES[lb]
    if fam == "Helvetica":
        return "Helvetica-BoldOblique" if bold and italic else ("Helvetica-Bold" if bold else ("Helvetica-Oblique" if italic else "Helvetica"))
    if fam == "Times":
        return "Times-BoldItalic" if bold and italic else ("Times-Bold" if bold else ("Times-Italic" if italic else "Times-Roman"))
    return "Courier-BoldOblique" if bold and italic else ("Courier-Bold" if bold else ("Courier-Oblique" if italic else "Courier"))

func register_font(family, path, bold=null, italic=null, bold_italic=null):
    for p in [path, bold, italic, bold_italic]:
        if p != null and not io.file_exists(p):
            raise("IoError", "police introuvable : " + p)
    _ttf_families[family] = {"regular": path, "bold": bold, "italic": italic, "bold_italic": bold_italic}
    return family

const _SYSTEM_FONT_DIRS := ["/usr/share/fonts/truetype/dejavu/", "/usr/share/fonts/dejavu/", "/usr/share/fonts/TTF/", "/usr/local/share/fonts/", "/Library/Fonts/", "C:/Windows/Fonts/"]

# Police système Unicode (DejaVu, sinon Arial / Times / Courier de Windows ou macOS).
func find_system_font(family="sans", bold=false, italic=false):
    f := string.lower(family)
    style := ""
    names := []
    if f == "serif" or f == "times":
        style = "Serif"
        names = ["DejaVuSerif" + ("-BoldItalic" if bold and italic else ("-Bold" if bold else ("-Italic" if italic else ""))) + ".ttf", "times" + ("bi" if bold and italic else ("bd" if bold else ("i" if italic else ""))) + ".ttf"]
    elif f == "mono" or f == "courier":
        names = ["DejaVuSansMono" + ("-BoldOblique" if bold and italic else ("-Bold" if bold else ("-Oblique" if italic else ""))) + ".ttf", "cour" + ("bi" if bold and italic else ("bd" if bold else ("i" if italic else ""))) + ".ttf"]
    else:
        names = ["DejaVuSans" + ("-BoldOblique" if bold and italic else ("-Bold" if bold else ("-Oblique" if italic else ""))) + ".ttf", "arial" + ("bi" if bold and italic else ("bd" if bold else ("i" if italic else ""))) + ".ttf", "Arial.ttf"]
    for d in _SYSTEM_FONT_DIRS:
        for n in names:
            if io.file_exists(d + n):
                return d + n
    return null

# ---------------------------------------------------------------------- TrueType

class TrueTypeFont:
    func init(path):
        self.path = path
        self.data = io.read_bytes(path)
        d := self.data
        if len(d) < 12:
            errors.fail(errors.FORMAT, "police TrueType invalide : " + path)
        tag0 := u.u32be(d, 0)
        if tag0 == 1953784678:
            errors.fail(errors.UNSUPPORTED, "collection de polices (.ttc) non prise en charge : " + path)
        if tag0 == 1330926671:
            errors.fail(errors.UNSUPPORTED, "police OpenType CFF (.otf) non prise en charge, utilisez une police TrueType : " + path)
        n := u.u16be(d, 4)
        self.tables = {}
        k := 0
        while k < n:
            e := 12 + k * 16
            tag := _n.latin1_decode(_n.bytes_slice(d, e, e + 4))
            self.tables[tag] = [u.u32be(d, e + 8), u.u32be(d, e + 12)]
            k = k + 1
        for req in ["head", "hhea", "hmtx", "cmap", "maxp", "loca", "glyf"]:
            if not contains_key(self.tables, req):
                errors.fail(errors.FORMAT, "police TrueType incomplète (table " + req + " absente) : " + path)
        h := self.tables["head"][0]
        self.units = u.u16be(d, h + 18)
        self.bbox = [_s16(d, h + 36), _s16(d, h + 38), _s16(d, h + 40), _s16(d, h + 42)]
        self.loca_long = _s16(d, h + 50) == 1
        hh := self.tables["hhea"][0]
        self.ascent = _s16(d, hh + 4)
        self.descent = _s16(d, hh + 6)
        self.num_hmetrics = u.u16be(d, hh + 34)
        self.num_glyphs = u.u16be(d, self.tables["maxp"][0] + 4)
        self.cap = self.ascent * 7 // 10
        self.italic_angle = 0
        self.flags = 32
        if contains_key(self.tables, "OS/2"):
            o := self.tables["OS/2"][0]
            ol := self.tables["OS/2"][1]
            if ol >= 72:
                self.ascent = _s16(d, o + 68)
                self.descent = _s16(d, o + 70)
            if ol >= 90 and u.u16be(d, o) >= 2:
                self.cap = _s16(d, o + 88)
        if contains_key(self.tables, "post"):
            p := self.tables["post"][0]
            self.italic_angle = _s16(d, p + 4)
            if u.u32be(d, p + 12) != 0:
                self.flags = self.flags | 1
        if self.italic_angle != 0:
            self.flags = self.flags | 64
        self.name = self._ps_name()
        self._widths = self._read_hmtx()
        self.cmap = self._read_cmap()
        self.used = {}

    func _ps_name():
        if not contains_key(self.tables, "name"):
            return "ALEXFont"
        d := self.data
        b := self.tables["name"][0]
        count := u.u16be(d, b + 2)
        storage := b + u.u16be(d, b + 4)
        k := 0
        while k < count:
            r := b + 6 + k * 12
            pid := u.u16be(d, r)
            nid := u.u16be(d, r + 6)
            if nid == 6:
                ln := u.u16be(d, r + 8)
                off := u.u16be(d, r + 10)
                raw := _n.bytes_slice(d, storage + off, storage + off + ln)
                nm := u.utf16_decode(raw, true) if pid == 3 or pid == 0 else _n.latin1_decode(raw)
                clean := []
                for c in nm:
                    o := string.ord(c)
                    if o > 32 and o < 127 and str(c) != "(" and str(c) != ")" and str(c) != "/" and str(c) != "[" and str(c) != "]":
                        append(clean, str(c))
                if len(clean) > 0:
                    return string.join("", clean)
            k = k + 1
        return "ALEXFont"

    func _read_hmtx():
        d := self.data
        b := self.tables["hmtx"][0]
        out := []
        k := 0
        last := 0
        while k < self.num_hmetrics:
            last = u.u16be(d, b + k * 4)
            append(out, last)
            k = k + 1
        return out

    func advance(gid):
        if gid < len(self._widths):
            return self._widths[gid]
        return self._widths[len(self._widths) - 1] if len(self._widths) > 0 else 0

    func _read_cmap():
        d := self.data
        b := self.tables["cmap"][0]
        n := u.u16be(d, b + 2)
        best := -1
        best_fmt := 0
        k := 0
        while k < n:
            r := b + 4 + k * 8
            pid := u.u16be(d, r)
            eid := u.u16be(d, r + 2)
            off := b + u.u32be(d, r + 4)
            fmt := u.u16be(d, off)
            if fmt == 12 and ((pid == 3 and eid == 10) or pid == 0):
                best = off
                best_fmt = 12
            elif fmt == 4 and best_fmt != 12 and ((pid == 3 and (eid == 1 or eid == 0)) or pid == 0):
                best = off
                best_fmt = 4
            k = k + 1
        out := {}
        if best < 0:
            return out
        if best_fmt == 4:
            segx2 := u.u16be(d, best + 6)
            segs := segx2 // 2
            ends := best + 14
            starts := ends + segx2 + 2
            deltas := starts + segx2
            ranges := deltas + segx2
            s := 0
            while s < segs:
                e := u.u16be(d, ends + s * 2)
                st := u.u16be(d, starts + s * 2)
                delta := u.u16be(d, deltas + s * 2)
                ro := u.u16be(d, ranges + s * 2)
                c := st
                while c <= e and c != 65535:
                    g := 0
                    if ro == 0:
                        g = (c + delta) & 65535
                    else:
                        gi := ranges + s * 2 + ro + (c - st) * 2
                        g = u.u16be(d, gi)
                        if g != 0:
                            g = (g + delta) & 65535
                    if g != 0:
                        out[c] = g
                    c = c + 1
                s = s + 1
        else:
            ng := u.u32be(d, best + 12)
            s := 0
            while s < ng:
                r := best + 16 + s * 12
                sc := u.u32be(d, r)
                ec := u.u32be(d, r + 4)
                sg := u.u32be(d, r + 8)
                if ec - sc > 70000:
                    ec = sc + 70000
                c := sc
                while c <= ec:
                    out[c] = sg + (c - sc)
                    c = c + 1
                s = s + 1
        return out

    func glyph(cp):
        if contains_key(self.cmap, cp):
            return self.cmap[cp]
        return 0

    func has(cp):
        return contains_key(self.cmap, cp)

    # Encode un texte en identifiants de glyphes (2 octets) et note les glyphes utilisés.
    func encode(text):
        out := []
        for c in text:
            cp := string.ord(c)
            g := self.glyph(cp)
            if not contains_key(self.used, g):
                self.used[g] = cp if g != 0 else 65533
            append(out, (g >> 8) & 255)
            append(out, g & 255)
        return out

    func width(text, size):
        w := 0
        for c in text:
            w = w + self.advance(self.glyph(string.ord(c)))
        return to_float(w) * to_float(size) / to_float(self.units)

    func _glyph_range(gid):
        d := self.data
        lb := self.tables["loca"][0]
        if self.loca_long:
            return [u.u32be(d, lb + gid * 4), u.u32be(d, lb + gid * 4 + 4)]
        return [u.u16be(d, lb + gid * 2) * 2, u.u16be(d, lb + gid * 2 + 2) * 2]

    # Sous-ensemble : les glyphes non utilisés (ni composants d'un glyphe utilisé) sont vidés ; les identifiants
    # sont conservés, ce qui garde valides les codes déjà écrits dans les contenus.
    func subset():
        d := self.data
        gb := self.tables["glyf"][0]
        keep := {0: true}
        stack := []
        for g in keys(self.used):
            keep[g] = true
            append(stack, g)
        while len(stack) > 0:
            g := collections.pop(stack)
            if g >= self.num_glyphs:
                continue
            r := self._glyph_range(g)
            if r[1] - r[0] < 10:
                continue
            p := gb + r[0]
            if _s16(d, p) >= 0:
                continue
            q := p + 10
            more := true
            while more:
                flags := u.u16be(d, q)
                comp := u.u16be(d, q + 2)
                if not contains_key(keep, comp):
                    keep[comp] = true
                    append(stack, comp)
                q = q + 4
                q = q + (4 if (flags & 1) != 0 else 2)
                if (flags & 8) != 0:
                    q = q + 2
                elif (flags & 64) != 0:
                    q = q + 4
                elif (flags & 128) != 0:
                    q = q + 8
                more = (flags & 32) != 0
        glyf := []
        loca := []
        pos := 0
        g := 0
        while g < self.num_glyphs:
            append(loca, pos)
            if contains_key(keep, g):
                r := self._glyph_range(g)
                if r[1] > r[0]:
                    gd := _n.bytes_slice(d, gb + r[0], gb + r[1])
                    while len(gd) % 4 != 0:
                        append(gd, 0)
                    append(glyf, gd)
                    pos = pos + len(gd)
            g = g + 1
        append(loca, pos)
        loca_bytes := []
        for v in loca:
            append(loca_bytes, u.pack_u32be(v))
        tables := {}
        for t in ["cvt ", "fpgm", "prep", "hhea", "hmtx", "maxp"]:
            if contains_key(self.tables, t):
                e := self.tables[t]
                tables[t] = _n.bytes_slice(d, e[0], e[0] + e[1])
        head := _n.bytes_slice(d, self.tables["head"][0], self.tables["head"][0] + self.tables["head"][1])
        head[50] = 0
        head[51] = 1
        head[8] = 0
        head[9] = 0
        head[10] = 0
        head[11] = 0
        tables["head"] = head
        tables["loca"] = u.concat(loca_bytes)
        tables["glyf"] = u.concat(glyf)
        return _build_font(tables)

func _s16(d, p):
    v := u.u16be(d, p)
    return v - 65536 if v >= 32768 else v

func _checksum(b):
    s := 0
    n := len(b)
    i := 0
    while i < n:
        v := 0
        k := 0
        while k < 4:
            v = (v << 8) | (b[i + k] if i + k < n else 0)
            k = k + 1
        s = (s + v) & 4294967295
        i = i + 4
    return s

func _build_font(tables):
    tags := u.sort(keys(tables))
    n := len(tags)
    es := 1
    lg := 0
    while es * 2 <= n:
        es = es * 2
        lg = lg + 1
    head := u.concat([[0, 1, 0, 0], u.pack_u16be(n), u.pack_u16be(es * 16), u.pack_u16be(lg), u.pack_u16be(n * 16 - es * 16)])
    offset := 12 + 16 * n
    dir := []
    body := []
    for t in tags:
        data := tables[t]
        append(dir, u.concat([_n.latin1_encode(t), u.pack_u32be(_checksum(data)), u.pack_u32be(offset), u.pack_u32be(len(data))]))
        padded := data
        if len(padded) % 4 != 0:
            padded = u.concat([data, _n.bytes_fill(4 - len(data) % 4, 0)])
        append(body, padded)
        offset = offset + len(padded)
    font := u.concat([head, u.concat(dir), u.concat(body)])
    # ajustement de la somme de contrôle globale (head.checkSumAdjustment)
    total := _checksum(font)
    adj := (2981146554 - total) & 4294967295
    hpos := 12
    for t in tags:
        if t == "head":
            break
        hpos = hpos + 16
    hoff := u.u32be(font, hpos + 8)
    pk := u.pack_u32be(adj)
    font[hoff + 8] = pk[0]
    font[hoff + 9] = pk[1]
    font[hoff + 10] = pk[2]
    font[hoff + 11] = pk[3]
    return font

func load_ttf(path):
    if not contains_key(_ttf_cache, path):
        _ttf_cache[path] = TrueTypeFont(path)
    return _ttf_cache[path]

# ---------------------------------------------------------------------- mesures

func _cp1252_codes(text):
    return u.cp1252_encode(text, 63)

func font_metrics(font):
    if string.starts_with(font, "ttf:"):
        f := load_ttf(_n.str_slice(font, 4, null))
        sc := 1000.0 / to_float(f.units)
        return {"ascent": to_int(to_float(f.ascent) * sc), "descent": to_int(to_float(f.descent) * sc), "cap": to_int(to_float(f.cap) * sc)}
    m := STANDARD_FONTS[font] if contains_key(STANDARD_FONTS, font) else STANDARD_FONTS["Helvetica"]
    return {"ascent": m["ascent"], "descent": m["descent"], "cap": m["cap"]}

func text_width(text, font, size):
    if string.starts_with(font, "ttf:"):
        return load_ttf(_n.str_slice(font, 4, null)).width(text, size)
    m := STANDARD_FONTS[font] if contains_key(STANDARD_FONTS, font) else STANDARD_FONTS["Helvetica"]
    ws := m["widths"]
    w := 0
    for c in _cp1252_codes(text):
        if c >= 32:
            w = w + ws[c - 32]
    return to_float(w) * to_float(size) / 1000.0

# Découpe en lignes tenant dans `width` (coupure aux espaces ; mot trop long coupé ; "\n" respectés).
func wrap_text(text, width, font, size):
    out := []
    for para in string.split(string.replace(u.to_text(text), "\r\n", "\n"), "\n"):
        words := string.split(para, " ")
        line := ""
        for w in words:
            cand := w if line == "" else line + " " + w
            if text_width(cand, font, size) <= width or line == "" and text_width(w, font, size) <= width:
                line = cand
                continue
            if line != "":
                append(out, line)
                line = ""
            # mot plus long que la largeur : coupé
            if text_width(w, font, size) > width:
                piece := ""
                for c in w:
                    if text_width(piece + str(c), font, size) > width and piece != "":
                        append(out, piece)
                        piece = ""
                    piece = piece + str(c)
                line = piece
            else:
                line = w
        append(out, line)
    return out

# ============================================================================================== canvas

func _color_ops(c, stroke):
    if c == null:
        return ""
    rgb := u.color_floats(c)
    return _num(rgb[0]) + " " + _num(rgb[1]) + " " + _num(rgb[2]) + (" RG" if stroke else " rg")

const _KAPPA := 0.5522847498

class Canvas:
    func init(builder, width, height):
        self.builder = builder
        self.width = width
        self.height = height
        self.ops = []
        self.fonts = {}
        self.images = {}
        self.gstates = {}
        self.annots = []
        self.font = "Helvetica"
        self.size = 12.0
        self.fill_color = "000000"
        self.stroke_color = "000000"
        self.leading = null

    func raw(text):
        append(self.ops, text)

    func set_font(name, size=null, bold=false, italic=false):
        self.font = resolve_font(name, bold, italic)
        if size != null:
            self.size = to_float(size)
        return self

    func set_fill(color):
        self.fill_color = color
        append(self.ops, _color_ops(color, false))

    func set_stroke(color):
        self.stroke_color = color
        append(self.ops, _color_ops(color, true))

    func set_line_width(w):
        append(self.ops, _num(w) + " w")

    func set_dash(pattern=null, phase=0):
        if pattern == null or len(pattern) == 0:
            append(self.ops, "[] 0 d")
        else:
            parts := []
            for p in pattern:
                append(parts, _num(p))
            append(self.ops, "[" + string.join(" ", parts) + "] " + _num(phase) + " d")

    func set_line_cap(c):
        append(self.ops, str(c) + " J")

    func set_opacity(fill=1.0, stroke=null):
        s := stroke if stroke != null else fill
        key := _num(fill) + "/" + _num(s)
        if not contains_key(self.gstates, key):
            self.gstates[key] = "GS" + str(len(keys(self.gstates)) + 1)
        append(self.ops, "/" + self.gstates[key] + " gs")

    func save_state():
        append(self.ops, "q")

    func restore_state():
        append(self.ops, "Q")

    func translate(x0, y0):
        append(self.ops, "1 0 0 1 " + _num(x0) + " " + _num(y0) + " cm")

    func scale(sx, sy=null):
        append(self.ops, _num(sx) + " 0 0 " + _num(sy if sy != null else sx) + " 0 0 cm")

    func rotate(deg):
        r := to_float(deg) * math.PI / 180.0
        c := math.cos(r)
        s := math.sin(r)
        append(self.ops, _num(c) + " " + _num(s) + " " + _num(-s) + " " + _num(c) + " 0 0 cm")

    func move_to(x0, y0):
        append(self.ops, _num(x0) + " " + _num(y0) + " m")

    func line_to(x0, y0):
        append(self.ops, _num(x0) + " " + _num(y0) + " l")

    func curve_to(x1, y1, x2, y2, x3, y3):
        append(self.ops, _num(x1) + " " + _num(y1) + " " + _num(x2) + " " + _num(y2) + " " + _num(x3) + " " + _num(y3) + " c")

    func close_path():
        append(self.ops, "h")

    func stroke():
        append(self.ops, "S")

    func fill():
        append(self.ops, "f")

    func fill_stroke():
        append(self.ops, "B")

    func clip():
        append(self.ops, "W n")

    func _paint(fill_, stroke_):
        if fill_ and stroke_:
            append(self.ops, "B")
        elif fill_:
            append(self.ops, "f")
        elif stroke_:
            append(self.ops, "S")
        else:
            append(self.ops, "n")

    func line(x1, y1, x2, y2):
        append(self.ops, _num(x1) + " " + _num(y1) + " m " + _num(x2) + " " + _num(y2) + " l S")

    func rect(x0, y0, w, h, fill_=false, stroke_=true):
        append(self.ops, _num(x0) + " " + _num(y0) + " " + _num(w) + " " + _num(h) + " re")
        self._paint(fill_, stroke_)

    func rounded_rect(x0, y0, w, h, r, fill_=false, stroke_=true):
        rr := to_float(r)
        k := rr * _KAPPA
        self.move_to(x0 + rr, y0)
        self.line_to(x0 + w - rr, y0)
        self.curve_to(x0 + w - rr + k, y0, x0 + w, y0 + rr - k, x0 + w, y0 + rr)
        self.line_to(x0 + w, y0 + h - rr)
        self.curve_to(x0 + w, y0 + h - rr + k, x0 + w - rr + k, y0 + h, x0 + w - rr, y0 + h)
        self.line_to(x0 + rr, y0 + h)
        self.curve_to(x0 + rr - k, y0 + h, x0, y0 + h - rr + k, x0, y0 + h - rr)
        self.line_to(x0, y0 + rr)
        self.curve_to(x0, y0 + rr - k, x0 + rr - k, y0, x0 + rr, y0)
        self.close_path()
        self._paint(fill_, stroke_)

    func ellipse(cx, cy, rx, ry, fill_=false, stroke_=true):
        kx := to_float(rx) * _KAPPA
        ky := to_float(ry) * _KAPPA
        self.move_to(cx + rx, cy)
        self.curve_to(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry)
        self.curve_to(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy)
        self.curve_to(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry)
        self.curve_to(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy)
        self.close_path()
        self._paint(fill_, stroke_)

    func circle(cx, cy, r, fill_=false, stroke_=true):
        self.ellipse(cx, cy, r, r, fill_, stroke_)

    # Secteur de disque (graphiques en secteurs) : angles en degrés, sens trigonométrique.
    func wedge(cx, cy, r, start_deg, end_deg, fill_=true, stroke_=false):
        self.move_to(cx, cy)
        a := to_float(start_deg)
        e := to_float(end_deg)
        step := 30.0
        x0 := cx + r * math.cos(a * math.PI / 180.0)
        y0 := cy + r * math.sin(a * math.PI / 180.0)
        self.line_to(x0, y0)
        while a < e - 0.001:
            b := a + step if a + step < e else e
            t1 := a * math.PI / 180.0
            t2 := b * math.PI / 180.0
            k := 4.0 / 3.0 * math.tan((t2 - t1) / 4.0)
            self.curve_to(cx + r * (math.cos(t1) - k * math.sin(t1)), cy + r * (math.sin(t1) + k * math.cos(t1)), cx + r * (math.cos(t2) + k * math.sin(t2)), cy + r * (math.sin(t2) - k * math.cos(t2)), cx + r * math.cos(t2), cy + r * math.sin(t2))
            a = b
        self.close_path()
        self._paint(fill_, stroke_)

    func polygon(points, fill_=false, stroke_=true):
        first := true
        for p in points:
            if first:
                self.move_to(p[0], p[1])
                first = false
            else:
                self.line_to(p[0], p[1])
        self.close_path()
        self._paint(fill_, stroke_)

    func text_width(text, font=null, size=null):
        return text_width(text, font if font != null else self.font, size if size != null else self.size)

    # Police effective pour un texte : police standard si tout le texte tient en Windows-1252, sinon police
    # Unicode de secours (si le constructeur l'autorise et qu'une police système est trouvée).
    func _effective_font(text, font):
        if string.starts_with(font, "ttf:") or not self.builder.unicode:
            return font
        ok := true
        for c in text:
            o := string.ord(c)
            if o > 255 and o != 8364 and o != 8218 and o != 402 and o != 8222 and o != 8230 and o != 8224 and o != 8225 and o != 710 and o != 8240 and o != 352 and o != 8249 and o != 338 and o != 381 and o != 8216 and o != 8217 and o != 8220 and o != 8221 and o != 8226 and o != 8211 and o != 8212 and o != 732 and o != 8482 and o != 353 and o != 8250 and o != 339 and o != 382 and o != 376:
                ok = false
                break
        if ok:
            return font
        fam := "mono" if string.starts_with(font, "Courier") else ("serif" if string.starts_with(font, "Times") else "sans")
        path := find_system_font(fam, string.contains(font, "Bold"), string.contains(font, "Oblique") or string.contains(font, "Italic"))
        if path == null:
            path = find_system_font("sans")
        if path == null:
            return font
        return "ttf:" + path

    func _font_res(font):
        if not contains_key(self.fonts, font):
            self.fonts[font] = self.builder.font_resource(font)
        return self.fonts[font]

    func _encode(text, font):
        if string.starts_with(font, "ttf:"):
            return "<" + _n.hex_encode(load_ttf(_n.str_slice(font, 4, null)).encode(text), true) + ">"
        return _string(_cp1252_codes(text))

    func text(x0, y0, text, align="left", color=null):
        t := u.to_text(text)
        f := self._effective_font(t, self.font)
        w := text_width(t, f, self.size)
        xx := to_float(x0)
        if align == "center":
            xx = xx - w / 2.0
        elif align == "right":
            xx = xx - w
        res := self._font_res(f)
        col := ""
        if color != null:
            col = _color_ops(color, false) + " "
        append(self.ops, "BT " + col + "/" + res + " " + _num(self.size) + " Tf " + _num(xx) + " " + _num(y0) + " Td " + self._encode(t, f) + " Tj ET")
        if color != null:
            append(self.ops, _color_ops(self.fill_color, false))
        return w

    # Ligne composée de segments [texte, police, taille, couleur] (couleur facultative). Renvoie la largeur.
    func rich_line(x0, y0, segments, word_spacing=0.0):
        parts := ["BT"]
        if word_spacing != 0:
            append(parts, _num(word_spacing) + " Tw")
        append(parts, _num(x0) + " " + _num(y0) + " Td")
        total := 0.0
        for seg in segments:
            t := u.to_text(seg[0])
            if t == "":
                continue
            f := self._effective_font(t, seg[1])
            res := self._font_res(f)
            if len(seg) > 3 and seg[3] != null:
                append(parts, _color_ops(seg[3], false))
            else:
                append(parts, _color_ops(self.fill_color, false))
            append(parts, "/" + res + " " + _num(seg[2]) + " Tf " + self._encode(t, f) + " Tj")
            total = total + text_width(t, f, seg[2])
        if word_spacing != 0:
            append(parts, "0 Tw")
        append(parts, "ET")
        append(self.ops, string.join(" ", parts))
        append(self.ops, _color_ops(self.fill_color, false))
        return total

    # Texte coupé en lignes dans un cadre dont `top` est le bord SUPÉRIEUR. align : left center right justify.
    # Renvoie la hauteur utilisée (les lignes au-delà de h sont omises si h n'est pas null).
    func text_box(x0, top, w, h, text, align="left", leading=null):
        lead := leading if leading != null else self.size * 1.25
        f := self._effective_font(u.to_text(text), self.font)
        lines := wrap_text(text, w, f, self.size)
        m := font_metrics(f)
        y := to_float(top) - to_float(m["ascent"]) * self.size / 1000.0
        used := 0.0
        k := 0
        for line in lines:
            if h != null and used + lead > to_float(h) + 0.01 and k > 0:
                break
            last := k == len(lines) - 1
            if align == "justify" and not last and string.contains(line, " "):
                gaps := string.count(line, " ")
                extra := (to_float(w) - text_width(line, f, self.size)) / to_float(gaps)
                if extra < 0:
                    extra = 0.0
                self.rich_line(x0, y, [[line, f, self.size]], extra)
            elif align == "center":
                self.text(to_float(x0) + to_float(w) / 2.0, y, line, "center")
            elif align == "right":
                self.text(to_float(x0) + to_float(w), y, line, "right")
            else:
                self.rich_line(x0, y, [[line, f, self.size]])
            y = y - lead
            used = used + lead
            k = k + 1
        return used

    # Image (chemin, octets ou core.Image) au point (x, y) = coin INFÉRIEUR gauche. w / h en points ; une seule
    # dimension : proportions conservées ; aucune : 72 ppp (taille naturelle).
    func image(img, x0, y0, w=null, h=null):
        im := core.load_image(img)
        res := self.builder.image_resource(im)
        self.images[res] = true
        ww := w
        hh := h
        nat_w := to_float(im.width) * 72.0 / to_float(im.dpi_x if im.dpi_x > 0 else 72)
        nat_h := to_float(im.height) * 72.0 / to_float(im.dpi_y if im.dpi_y > 0 else 72)
        if ww == null and hh == null:
            ww = nat_w
            hh = nat_h
        elif ww == null:
            ww = to_float(hh) * nat_w / nat_h
        elif hh == null:
            hh = to_float(ww) * nat_h / nat_w
        append(self.ops, "q " + _num(ww) + " 0 0 " + _num(hh) + " " + _num(x0) + " " + _num(y0) + " cm /" + res + " Do Q")
        return [to_float(ww), to_float(hh)]

    func link(x0, y0, w, h, url):
        append(self.annots, {"rect": [x0, y0, x0 + w, y0 + h], "uri": url})

    func link_page(x0, y0, w, h, index, top=null):
        append(self.annots, {"rect": [x0, y0, x0 + w, y0 + h], "page": index, "top": top})

    func content():
        return string.join("\n", self.ops)

# ============================================================================================== document

class PdfBuilder:
    func init(unicode=true):
        self.pages = []
        self.info = {"Producer": "ALEX Office", "Creator": "ALEX Office"}
        self.bookmarks = []
        self.unicode = unicode
        self._font_names = {}
        self._image_names = {}
        self._images = {}
        self.page_layout = null

    func new_page(size="A4", landscape=false):
        wh := core.page_size(size, landscape)
        c := Canvas(self, wh[0], wh[1])
        append(self.pages, c)
        return c

    func page_count():
        return len(self.pages)

    func add_bookmark(title, page, level=1, top=null):
        append(self.bookmarks, {"title": title, "page": page, "level": level, "top": top})

    func font_resource(font):
        if not contains_key(self._font_names, font):
            self._font_names[font] = "F" + str(len(keys(self._font_names)) + 1)
        return self._font_names[font]

    func image_resource(im):
        key := str(_n.crc32(im.data, 0)) + ":" + str(len(im.data))
        if not contains_key(self._image_names, key):
            self._image_names[key] = "Im" + str(len(keys(self._image_names)) + 1)
            self._images[key] = im
        return self._image_names[key]

    # ---------------------------------------------------------- objets
    func _font_obj(w, font):
        if not string.starts_with(font, "ttf:"):
            return w.add({"Type": "/Font", "Subtype": "/Type1", "BaseFont": "/" + font, "Encoding": "/WinAnsiEncoding"})
        f := load_ttf(_n.str_slice(font, 4, null))
        sc := 1000.0 / to_float(f.units)
        tag := ""
        h := _n.crc32(_n.utf8_encode(f.path + str(len(keys(f.used)))), 0)
        k := 0
        while k < 6:
            tag = tag + str(string.chr(65 + h % 26))
            h = h // 26
            k = k + 1
        base := tag + "+" + f.name
        sub := f.subset()
        font_file := w.add(flate_stream({"Length1": len(sub)}, sub))
        desc := w.add({"Type": "/FontDescriptor", "FontName": "/" + base, "Flags": f.flags, "FontBBox": [to_int(to_float(f.bbox[0]) * sc), to_int(to_float(f.bbox[1]) * sc), to_int(to_float(f.bbox[2]) * sc), to_int(to_float(f.bbox[3]) * sc)], "ItalicAngle": f.italic_angle, "Ascent": to_int(to_float(f.ascent) * sc), "Descent": to_int(to_float(f.descent) * sc), "CapHeight": to_int(to_float(f.cap) * sc), "StemV": 80, "FontFile2": font_file})
        gids := u.sort(keys(f.used))
        warr := []
        for g in gids:
            append(warr, g)
            append(warr, [to_int(to_float(f.advance(g)) * sc)])
        cid := w.add({"Type": "/Font", "Subtype": "/CIDFontType2", "BaseFont": "/" + base, "CIDSystemInfo": {"Registry": pr.PdfString(_n.utf8_encode("Adobe")), "Ordering": pr.PdfString(_n.utf8_encode("Identity")), "Supplement": 0}, "FontDescriptor": desc, "W": warr, "CIDToGIDMap": "/Identity", "DW": 500})
        # ToUnicode
        lines := ["/CIDInit /ProcSet findresource begin", "12 dict begin", "begincmap", "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def", "/CMapName /Adobe-Identity-UCS def", "/CMapType 2 def", "1 begincodespacerange", "<0000> <FFFF>", "endcodespacerange"]
        chunk := []
        for g in gids:
            cp := f.used[g]
            append(chunk, "<" + _n.hex_encode([(g >> 8) & 255, g & 255], true) + "> <" + _n.hex_encode(u.utf16_encode(str(string.chr(cp)), true), true) + ">")
            if len(chunk) == 100:
                append(lines, str(len(chunk)) + " beginbfchar")
                for c in chunk:
                    append(lines, c)
                append(lines, "endbfchar")
                chunk = []
        if len(chunk) > 0:
            append(lines, str(len(chunk)) + " beginbfchar")
            for c in chunk:
                append(lines, c)
            append(lines, "endbfchar")
        for l in ["endcmap", "CMapName currentdict /CMap defineresource pop", "end", "end"]:
            append(lines, l)
        tu := w.add(flate_stream({}, string.join("\n", lines)))
        return w.add({"Type": "/Font", "Subtype": "/Type0", "BaseFont": "/" + base, "Encoding": "/Identity-H", "DescendantFonts": [cid], "ToUnicode": tu})

    func _image_obj(w, im):
        if im.format == "jpeg":
            comps := u.get(im.info, "components", 3)
            cs := "/DeviceRGB" if comps == 3 else ("/DeviceGray" if comps == 1 else "/DeviceCMYK")
            d := {"Type": "/XObject", "Subtype": "/Image", "Width": im.width, "Height": im.height, "ColorSpace": cs, "BitsPerComponent": 8, "Filter": "/DCTDecode"}
            if comps == 4:
                d["Decode"] = [1, 0, 1, 0, 1, 0, 1, 0]
            return w.add(pr.Stream(d, im.data))
        if im.format == "png":
            p := _n.png_decode(im.data)
            cs := "/DeviceRGB" if p["channels"] == 3 else "/DeviceGray"
            d := {"Type": "/XObject", "Subtype": "/Image", "Width": p["width"], "Height": p["height"], "ColorSpace": cs, "BitsPerComponent": 8}
            if p["alpha"] != null:
                d["SMask"] = w.add(flate_stream({"Type": "/XObject", "Subtype": "/Image", "Width": p["width"], "Height": p["height"], "ColorSpace": "/DeviceGray", "BitsPerComponent": 8}, p["alpha"]))
            return w.add(flate_stream(d, p["color"]))
        errors.fail(errors.UNSUPPORTED, "format d'image non pris en charge dans un PDF : " + im.format + " (JPEG ou PNG)")

    func to_bytes():
        if len(self.pages) == 0:
            self.new_page()
        w := ObjectWriter()
        catalog := w.alloc()
        pages_ref := w.alloc()
        page_refs := []
        for c in self.pages:
            append(page_refs, w.alloc())
        # contenus d'abord : ils déterminent les glyphes utilisés des polices TrueType
        contents := []
        for c in self.pages:
            append(contents, w.add(flate_stream({}, c.content())))
        font_refs := {}
        for f in keys(self._font_names):
            font_refs[f] = self._font_obj(w, f)
        img_refs := {}
        for key in keys(self._images):
            img_refs[self._image_names[key]] = self._image_obj(w, self._images[key])
        i := 0
        for c in self.pages:
            res := {"ProcSet": ["/PDF", "/Text", "/ImageB", "/ImageC"]}
            if len(keys(c.fonts)) > 0:
                fd := {}
                for f in keys(c.fonts):
                    fd[c.fonts[f]] = font_refs[f]
                res["Font"] = fd
            if len(keys(c.images)) > 0:
                xd := {}
                for nm in keys(c.images):
                    xd[nm] = img_refs[nm]
                res["XObject"] = xd
            if len(keys(c.gstates)) > 0:
                gd := {}
                for key in keys(c.gstates):
                    parts := string.split(key, "/")
                    gd[c.gstates[key]] = {"Type": "/ExtGState", "ca": u.parse_number(parts[0]), "CA": u.parse_number(parts[1])}
                res["ExtGState"] = gd
            pd := {"Type": "/Page", "Parent": pages_ref, "MediaBox": [0, 0, c.width, c.height], "Resources": res, "Contents": contents[i]}
            if len(c.annots) > 0:
                annots := []
                for a in c.annots:
                    ad := {"Type": "/Annot", "Subtype": "/Link", "Rect": a["rect"], "Border": [0, 0, 0]}
                    if contains_key(a, "uri"):
                        ad["A"] = {"S": "/URI", "URI": pr.PdfString(_n.utf8_encode(a["uri"]))}
                    else:
                        pi := a["page"]
                        if pi >= 0 and pi < len(page_refs):
                            ad["Dest"] = [page_refs[pi], "/XYZ", null, a["top"], null]
                    append(annots, w.add(ad))
                pd["Annots"] = annots
            w.set(page_refs[i], pd)
            i = i + 1
        w.set(pages_ref, {"Type": "/Pages", "Kids": page_refs, "Count": len(page_refs)})
        cat := {"Type": "/Catalog", "Pages": pages_ref}
        ol := outline_tree(w, self.bookmarks, page_refs)
        if ol != null:
            cat["Outlines"] = ol
            cat["PageMode"] = "/UseOutlines"
        if self.page_layout != null:
            cat["PageLayout"] = "/" + self.page_layout
        w.set(catalog, cat)
        info := {}
        for k in keys(self.info):
            v := self.info[k]
            if v != null and v != "":
                info[k] = pdf_string(v) if type(v) == "str" else v
        if not contains_key(info, "CreationDate"):
            info["CreationDate"] = pr.PdfString(_n.utf8_encode(_pdf_now()))
        return w.to_bytes(catalog, w.add(info), "1.7")

    func save(path):
        io.write_bytes(path, self.to_bytes())
        return path

# Arbre de signets : bookmarks = [{"title", "page", "level", "top"}] (niveaux 1, 2, 3...) -> Ref de /Outlines ou null.
func outline_tree(w, bookmarks, page_refs):
    if len(bookmarks) == 0 or len(page_refs) == 0:
        return null
    root := w.alloc()
    items := []
    for b in bookmarks:
        append(items, {"ref": w.alloc(), "b": b, "children": []})
    stack := []
    tops := []
    for it in items:
        lvl := u.get(it["b"], "level", 1)
        while len(stack) > 0 and u.get(stack[len(stack) - 1]["b"], "level", 1) >= lvl:
            collections.pop(stack)
        if len(stack) == 0:
            append(tops, it)
        else:
            append(stack[len(stack) - 1]["children"], it)
        append(stack, it)
    _link_outline(w, tops, root, page_refs)
    w.set(root, {"Type": "/Outlines", "First": tops[0]["ref"], "Last": tops[len(tops) - 1]["ref"], "Count": len(items)})
    return root

func _link_outline(w, siblings, parent_ref, page_refs):
    k := 0
    for it in siblings:
        b := it["b"]
        pi := u.get(b, "page", 0)
        if pi < 0 or pi >= len(page_refs):
            pi = 0
        top := u.get(b, "top", null)
        d := {"Title": pdf_string(b["title"]), "Parent": parent_ref, "Dest": [page_refs[pi], "/XYZ", null, top, null]}
        if k > 0:
            d["Prev"] = siblings[k - 1]["ref"]
        if k + 1 < len(siblings):
            d["Next"] = siblings[k + 1]["ref"]
        if len(it["children"]) > 0:
            d["First"] = it["children"][0]["ref"]
            d["Last"] = it["children"][len(it["children"]) - 1]["ref"]
            d["Count"] = len(it["children"])
            _link_outline(w, it["children"], it["ref"], page_refs)
        w.set(it["ref"], d)
        k = k + 1

func _pdf_now():
    iso := u.now_iso()
    return "D:" + string.replace(string.replace(string.replace(string.replace(iso, "-", ""), ":", ""), "T", ""), "Z", "Z")
