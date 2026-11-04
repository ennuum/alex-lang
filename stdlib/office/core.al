# ALEX STANDARD LIBRARY — office.core
# Socle commun de la bibliothèque bureautique :
#   - détection de format (signature, contenu d'une archive ZIP, extension) ;
#   - paquets OPC (Open Packaging Conventions, ECMA-376 partie 2), le conteneur de DOCX / XLSX / PPTX :
#     [Content_Types].xml, relations (_rels/*.rels), parties, résolution des cibles relatives ;
#   - images (dimensions, taille d'affichage en EMU conservant les proportions) ;
#   - formats de page.
#
#   use office.core as core
#   core.detect_format("rapport.docx")              # "docx"
#   pkg := core.open_package("rapport.docx")
#   main := pkg.main_part()                         # "word/document.xml"
#   doc := pkg.read_xml(main)
#   for r in pkg.rels(main):                        # [{"id", "type", "target", "mode"}, ...]
#       print(r["id"] + " -> " + pkg.resolve(main, r["target"]))
#   rid := pkg.add_rel(main, core.REL_IMAGE, "media/image1.png")
#   pkg.write_part("word/media/image1.png", octets)  # type de contenu par extension
#   pkg.save("copie.docx")
#
# FORMATS   VERSION  detect_format(chemin_ou_octets) -> "docx" "xlsx" "pptx" "odt" "ods" "odp" "pdf" "csv" "tsv"
#   "json" "xml" "html" "txt" "md" "zip" "png" "jpeg" "gif" ... "unknown"   extension_of(chemin)
# PAQUET    open_package(chemin_ou_octets)  new_package()  Package :
#   parts()  has_part(n)  read_part(n)  read_text(n)  read_xml(n)  write_part(n, data, content_type=null)
#   write_text(n, t, ct)  write_xml(n, nœud, ct)  remove_part(n)  content_type(n)  set_content_type(n, ct)
#   set_default(ext, ct)  rels(n)  rel(n, id)  rels_of_type(n, type)  target(n, type) (première cible résolue)
#   add_rel(n, type, cible, external=false, id=null) -> id   remove_rel(n, id)   resolve(n, cible)  relative(de, vers)
#   main_part(type=REL_OFFICE_DOCUMENT)  unique_name("word/media/image", ".png")  to_bytes()  save(chemin)
#   (n = "" désigne le paquet lui-même : relations de _rels/.rels)
# IMAGES    Image : load_image(chemin_ou_octets) -> Image(data, info) ; img.width / height (px), ext, mime,
#   img.size_emu(width=null, height=null) -> [cx, cy] (largeur et/ou hauteur imposées, proportions conservées ;
#   longueurs en EMU ou texte « 5cm », voir utils.length)
# PAGES     PAGE_SIZES : "A3" "A4" "A5" "Letter" "Legal" "Tabloid" -> [largeur, hauteur] en points
#   page_size(nom_ou_liste, landscape=false) -> [l, h] en points
# Erreurs : FormatError, ArchiveError, XMLError.

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

const VERSION := "1.0.0"

# ---------------------------------------------------------------------------------------------- relations OPC

const REL_OFFICE_DOCUMENT := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
const REL_CORE_PROPS := "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"
const REL_EXT_PROPS := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties"
const REL_CUSTOM_PROPS := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties"
const REL_THUMBNAIL := "http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"
const REL_STYLES := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"
const REL_NUMBERING := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering"
const REL_SETTINGS := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings"
const REL_FONT_TABLE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable"
const REL_THEME := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme"
const REL_IMAGE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"
const REL_HYPERLINK := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink"
const REL_HEADER := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
const REL_FOOTER := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
const REL_FOOTNOTES := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes"
const REL_WORKSHEET := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
const REL_SHARED_STRINGS := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings"
const REL_DRAWING := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing"
const REL_CHART := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart"
const REL_PACKAGE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/package"
const REL_SLIDE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide"
const REL_SLIDE_LAYOUT := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout"
const REL_SLIDE_MASTER := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster"
const REL_NOTES_SLIDE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide"
const REL_NOTES_MASTER := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster"
const REL_PRES_PROPS := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps"
const REL_VIEW_PROPS := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps"
const REL_TABLE_STYLES := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles"
const REL_COMMENTS := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments"
const REL_TABLE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/table"
const REL_WEB_SETTINGS := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/webSettings"

# ---------------------------------------------------------------------------------------------- types de contenu

const CT_RELS := "application/vnd.openxmlformats-package.relationships+xml"
const CT_XML := "application/xml"
const CT_CORE_PROPS := "application/vnd.openxmlformats-package.core-properties+xml"
const CT_EXT_PROPS := "application/vnd.openxmlformats-officedocument.extended-properties+xml"
const CT_CUSTOM_PROPS := "application/vnd.openxmlformats-officedocument.custom-properties+xml"
const CT_THEME := "application/vnd.openxmlformats-officedocument.theme+xml"
const CT_DOCX_MAIN := "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"
const CT_DOCX_STYLES := "application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"
const CT_DOCX_SETTINGS := "application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"
const CT_DOCX_NUMBERING := "application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"
const CT_DOCX_FONT_TABLE := "application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"
const CT_DOCX_HEADER := "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"
const CT_DOCX_FOOTER := "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"
const CT_DOCX_WEB_SETTINGS := "application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml"
const CT_XLSX_MAIN := "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"
const CT_XLSX_SHEET := "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"
const CT_XLSX_SST := "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"
const CT_XLSX_STYLES := "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"
const CT_DRAWING := "application/vnd.openxmlformats-officedocument.drawing+xml"
const CT_CHART := "application/vnd.openxmlformats-officedocument.drawingml.chart+xml"
const CT_PPTX_MAIN := "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"
const CT_PPTX_SLIDE := "application/vnd.openxmlformats-officedocument.presentationml.slide+xml"
const CT_PPTX_LAYOUT := "application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"
const CT_PPTX_MASTER := "application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"
const CT_PPTX_NOTES := "application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"
const CT_PPTX_NOTES_MASTER := "application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml"
const CT_PPTX_PRES_PROPS := "application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"
const CT_PPTX_VIEW_PROPS := "application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"
const CT_PPTX_TABLE_STYLES := "application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"
const CT_XLSX_PACKAGE := "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

# ---------------------------------------------------------------------------------------------- détection

func extension_of(p):
    base := p
    k := string.find(base, "/")
    while k >= 0:
        base = _n.str_slice(base, k + 1, null)
        k = string.find(base, "/")
    d := -1
    i := 0
    for c in base:
        if str(c) == ".":
            d = i
        i = i + 1
    if d <= 0:
        return ""
    return string.lower(_n.str_slice(base, d + 1, null))

func _zip_kind(a):
    if a.contains("mimetype"):
        mt := string.trim(a.read_text("mimetype"))
        if mt == "application/vnd.oasis.opendocument.text" or mt == "application/vnd.oasis.opendocument.text-template":
            return "odt"
        if mt == "application/vnd.oasis.opendocument.spreadsheet" or mt == "application/vnd.oasis.opendocument.spreadsheet-template":
            return "ods"
        if mt == "application/vnd.oasis.opendocument.presentation" or mt == "application/vnd.oasis.opendocument.presentation-template":
            return "odp"
        if mt == "application/epub+zip":
            return "epub"
    if a.contains("[Content_Types].xml"):
        ct := a.read_text("[Content_Types].xml")
        # partie principale d'abord (un document peut contenir un classeur incorporé, un graphique...)
        if string.contains(ct, "presentationml.presentation.main") or string.contains(ct, "presentationml.slideshow.main") or string.contains(ct, "presentationml.template.main"):
            return "pptx"
        if string.contains(ct, "wordprocessingml.document.main") or string.contains(ct, "wordprocessingml.template.main"):
            return "docx"
        if string.contains(ct, "spreadsheetml.sheet.main") or string.contains(ct, "spreadsheetml.template.main") or string.contains(ct, "ms-excel.sheet.macroEnabled.main"):
            return "xlsx"
        if string.contains(ct, "wordprocessingml"):
            return "docx"
        if string.contains(ct, "presentationml"):
            return "pptx"
        if string.contains(ct, "spreadsheetml"):
            return "xlsx"
    if a.contains("word/document.xml"):
        return "docx"
    if a.contains("xl/workbook.xml"):
        return "xlsx"
    if a.contains("ppt/presentation.xml"):
        return "pptx"
    return "zip"

func _text_kind(head, ext):
    t := string.trim(head)
    low := string.lower(t)
    if string.starts_with(low, "<!doctype html") or string.starts_with(low, "<html") or (string.contains(low, "<html") and string.contains(low, "<body")):
        return "html"
    if string.starts_with(t, "<?xml") or string.starts_with(t, "<"):
        if string.contains(low, "<svg"):
            return "svg"
        return "xml"
    if string.starts_with(t, "{") or string.starts_with(t, "["):
        if ext == "json" or ext == "":
            return "json"
    if ext == "csv" or ext == "tsv" or ext == "md" or ext == "txt" or ext == "json" or ext == "html" or ext == "htm" or ext == "xml":
        if ext == "htm":
            return "html"
        return ext
    first_line := t
    nl := string.find(t, "\n")
    if nl >= 0:
        first_line = _n.str_slice(t, 0, nl)
    if string.count(first_line, "\t") >= 1:
        return "tsv"
    if string.count(first_line, ",") >= 1 or string.count(first_line, ";") >= 1:
        return "csv"
    return "txt"

# Format d'un fichier (chemin) ou d'un contenu (octets). La signature prime sur l'extension.
func detect_format(src):
    ext := ""
    data := src
    if type(src) == "str":
        ext = extension_of(src)
        if not io.file_exists(src):
            errors.fail(errors.FORMAT, "fichier introuvable : " + src)
        data = io.read_bytes(src)
    elif type(src) != "list":
        raise("TypeError", "detect_format : chemin ou octets attendus")
    n := len(data)
    if n >= 5 and data[0] == 37 and data[1] == 80 and data[2] == 68 and data[3] == 70 and data[4] == 45:
        return "pdf"
    if n >= 4 and data[0] == 80 and data[1] == 75 and (data[2] == 3 or data[2] == 5):
        try:
            return _zip_kind(zip.from_bytes(data))
        catch e:
            return "zip"
    if n >= 8 and data[0] == 208 and data[1] == 207 and data[2] == 17 and data[3] == 224:
        return "ole"
    img := u.image_info(_n.bytes_slice(data, 0, 4096 if n > 4096 else n))
    if img != null and img["format"] != "svg":
        return img["format"]
    if n >= 4 and data[0] == 31 and data[1] == 139:
        return "gzip"
    head := u.decode_text(_n.bytes_slice(data, 0, 4096 if n > 4096 else n))
    return _text_kind(head, ext)

# ---------------------------------------------------------------------------------------------- paquet OPC

func _rels_path(part):
    if part == "" or part == "/":
        return "_rels/.rels"
    p := string.replace(part, "\\", "/")
    while string.starts_with(p, "/"):
        p = _n.str_slice(p, 1, null)
    k := -1
    i := 0
    for c in p:
        if str(c) == "/":
            k = i
        i = i + 1
    if k < 0:
        return "_rels/" + p + ".rels"
    return _n.str_slice(p, 0, k) + "/_rels/" + _n.str_slice(p, k + 1, null) + ".rels"

func _dir_of(part):
    k := -1
    i := 0
    for c in part:
        if str(c) == "/":
            k = i
        i = i + 1
    if k < 0:
        return ""
    return _n.str_slice(part, 0, k)

# Normalise un chemin de partie : pas de « / » initial, « . » et « .. » résolus.
func normalize_part(p):
    segs := []
    for s in string.split(string.replace(p, "\\", "/"), "/"):
        if s == "" or s == ".":
            continue
        if s == "..":
            if len(segs) > 0:
                collections.pop(segs)
            continue
        append(segs, s)
    return string.join("/", segs)

class Package:
    func init(archive):
        self.archive = archive
        self._defaults = {}
        self._overrides = {}
        self._rels = {}
        self._dirty_rels = {}
        self._load_content_types()

    func _load_content_types():
        a := self.archive
        if not a.contains("[Content_Types].xml"):
            return null
        root := x.parse(a.read_text("[Content_Types].xml"))
        for c in x.children(root):
            if x.matches(c, "Default"):
                self._defaults[string.lower(x.attr(c, "Extension", ""))] = x.attr(c, "ContentType", "")
            elif x.matches(c, "Override"):
                self._overrides[normalize_part(x.attr(c, "PartName", ""))] = x.attr(c, "ContentType", "")

    # ---------------------------------------------------------- parties
    func parts():
        out := []
        for n in self.archive.names():
            if n != "[Content_Types].xml" and not string.ends_with(n, "/"):
                append(out, n)
        return out

    func has_part(name):
        return self.archive.contains(normalize_part(name))

    func read_part(name):
        return self.archive.read(normalize_part(name))

    func read_text(name):
        return self.archive.read_text(normalize_part(name))

    func read_xml(name):
        n := normalize_part(name)
        try:
            return x.parse(self.archive.read_text(n))
        catch e:
            if e.type == "XMLError":
                errors.fail(errors.XML, "partie " + n + " : " + e.message)
            raise(e)

    func content_type(name):
        n := normalize_part(name)
        if contains_key(self._overrides, n):
            return self._overrides[n]
        ext := extension_of(n)
        if contains_key(self._defaults, ext):
            return self._defaults[ext]
        return null

    func set_content_type(name, ct):
        self._overrides[normalize_part(name)] = ct

    func set_default(ext, ct):
        self._defaults[string.lower(ext)] = ct

    # Écrit une partie. content_type : type « Override » ; sans lui, le type par défaut de l'extension est
    # déclaré si besoin (images, xml, rels...).
    func write_part(name, data, content_type=null, compress=true):
        n := normalize_part(name)
        self.archive.write(n, data, compress)
        if content_type != null:
            self._overrides[n] = content_type
        else:
            ext := extension_of(n)
            if not contains_key(self._defaults, ext) and not contains_key(self._overrides, n):
                if ext == "xml":
                    self._defaults[ext] = CT_XML
                elif ext == "rels":
                    self._defaults[ext] = CT_RELS
                else:
                    self._defaults[ext] = u.mime_for_extension(ext)

    func write_text(name, text, content_type=null):
        self.write_part(name, _n.utf8_encode(text), content_type)

    func write_xml(name, node, content_type=null):
        self.write_part(name, _n.utf8_encode(x.stringify(node, true)), content_type)

    func remove_part(name):
        n := normalize_part(name)
        if self.archive.contains(n):
            self.archive.remove(n)
        if contains_key(self._overrides, n):
            collections.remove(self._overrides, n)
        rp := _rels_path(n)
        if self.archive.contains(rp):
            self.archive.remove(rp)
        if contains_key(self._rels, n):
            collections.remove(self._rels, n)

    # Nom de partie libre : unique_name("word/media/image", ".png") -> "word/media/image3.png".
    func unique_name(stem, ext):
        k := 1
        while true:
            n := stem + str(k) + ext
            if not self.archive.contains(n):
                return n
            k = k + 1

    # ---------------------------------------------------------- relations
    func rels(part):
        key := normalize_part(part)
        if contains_key(self._rels, key):
            return self._rels[key]
        out := []
        rp := _rels_path(key)
        if self.archive.contains(rp):
            root := x.parse(self.archive.read_text(rp))
            for r in x.children(root, "Relationship"):
                append(out, {"id": x.attr(r, "Id", ""), "type": x.attr(r, "Type", ""), "target": x.attr(r, "Target", ""), "mode": x.attr(r, "TargetMode", null)})
        self._rels[key] = out
        return out

    func rel(part, rid):
        for r in self.rels(part):
            if r["id"] == rid:
                return r
        return null

    func rels_of_type(part, rel_type):
        out := []
        for r in self.rels(part):
            if r["type"] == rel_type or string.ends_with(r["type"], "/" + rel_type):
                append(out, r)
        return out

    # Cible résolue (chemin de partie) de la première relation d'un type ; null si aucune.
    func target(part, rel_type):
        rs := self.rels_of_type(part, rel_type)
        if len(rs) == 0:
            return null
        return self.resolve(part, rs[0]["target"])

    # Chemin de partie désigné par `target` (relative à la partie source, ou absolue « /... »).
    func resolve(part, target):
        if string.starts_with(target, "/"):
            return normalize_part(target)
        base := _dir_of(normalize_part(part))
        if base == "":
            return normalize_part(target)
        return normalize_part(base + "/" + target)

    # Cible relative de la partie `from_part` vers la partie `to_part`.
    func relative(from_part, to_part):
        a := string.split(_dir_of(normalize_part(from_part)), "/")
        b := string.split(normalize_part(to_part), "/")
        if len(a) == 1 and a[0] == "":
            return normalize_part(to_part)
        i := 0
        while i < len(a) and i < len(b) - 1 and a[i] == b[i]:
            i = i + 1
        parts := []
        k := i
        while k < len(a):
            append(parts, "..")
            k = k + 1
        while i < len(b):
            append(parts, b[i])
            i = i + 1
        return string.join("/", parts)

    func add_rel(part, rel_type, target, external=false, rid=null):
        rs := self.rels(part)
        idv := rid
        if idv == null:
            used := {}
            for r in rs:
                used[r["id"]] = true
            k := len(rs) + 1
            while contains_key(used, "rId" + str(k)):
                k = k + 1
            idv = "rId" + str(k)
        else:
            for r in rs:
                if r["id"] == idv:
                    errors.fail(errors.FORMAT, "identifiant de relation déjà utilisé : " + idv)
        mode := null
        if external:
            mode = "External"
        append(rs, {"id": idv, "type": rel_type, "target": target, "mode": mode})
        self._dirty_rels[normalize_part(part)] = true
        return idv

    func remove_rel(part, rid):
        rs := self.rels(part)
        out := []
        for r in rs:
            if r["id"] != rid:
                append(out, r)
        self._rels[normalize_part(part)] = out
        self._dirty_rels[normalize_part(part)] = true

    # Partie principale (document Word, classeur, présentation) désignée par _rels/.rels.
    func main_part(rel_type=REL_OFFICE_DOCUMENT):
        t := self.target("", rel_type)
        if t == null:
            errors.fail(errors.FORMAT, "paquet OPC sans partie principale (relation officeDocument absente)")
        return t

    # ---------------------------------------------------------- sérialisation
    func _flush():
        for key in keys(self._dirty_rels):
            rs := self._rels[key]
            items := []
            for r in rs:
                attrs := {"Id": r["id"], "Type": r["type"], "Target": r["target"]}
                if r["mode"] != null:
                    attrs["TargetMode"] = r["mode"]
                append(items, x.el("Relationship", attrs))
            root := x.el("Relationships", {"xmlns": x.NS["rel"]}, items)
            self.archive.write(_rels_path(key), x.to_bytes(root, true))
            if not contains_key(self._defaults, "rels"):
                self._defaults["rels"] = CT_RELS
        self._dirty_rels = {}
        if not contains_key(self._defaults, "xml"):
            self._defaults["xml"] = CT_XML
        items := []
        for ext in keys(self._defaults):
            append(items, x.el("Default", {"Extension": ext, "ContentType": self._defaults[ext]}))
        for n in keys(self._overrides):
            if self.archive.contains(n):
                append(items, x.el("Override", {"PartName": "/" + n, "ContentType": self._overrides[n]}))
        root := x.el("Types", {"xmlns": x.NS["ct"]}, items)
        data := x.to_bytes(root, true)
        if self.archive.contains("[Content_Types].xml"):
            self.archive.write("[Content_Types].xml", data)
        else:
            # [Content_Types].xml en tête d'archive (exigé par certains lecteurs)
            old := self.archive
            fresh := zip.new()
            fresh.fixed_time = old.fixed_time
            fresh.write("[Content_Types].xml", data)
            for n in old.names():
                rec := old._recs[n]
                append(fresh._order, n)
                fresh._recs[n] = rec
            fresh._source = old._source
            self.archive = fresh

    func to_bytes():
        self._flush()
        return self.archive.to_bytes()

    func save(path):
        io.write_bytes(path, self.to_bytes())

func open_package(src):
    a := null
    if type(src) == "str":
        if not io.file_exists(src):
            raise("IoError", "fichier introuvable : " + src)
        a = zip.open(src)
    elif type(src) == "list":
        a = zip.from_bytes(src)
    else:
        a = src
    if not a.contains("[Content_Types].xml"):
        errors.fail(errors.FORMAT, "ce n'est pas un paquet Office Open XML ([Content_Types].xml absent)")
    return Package(a)

func new_package():
    return Package(zip.new())

# ---------------------------------------------------------------------------------------------- images

class Image:
    func init(data, info):
        self.data = data
        self.info = info
        self.width = info["width"]
        self.height = info["height"]
        self.ext = info["ext"]
        self.mime = info["mime"]
        self.format = info["format"]
        self.dpi_x = info["dpi_x"]
        self.dpi_y = info["dpi_y"]

    # Taille d'affichage [cx, cy] en EMU. Sans contrainte : taille naturelle (pixels à la résolution de l'image).
    # Avec une seule dimension : l'autre suit les proportions.
    func size_emu(width=null, height=null):
        nat_w := to_float(self.width) * 914400.0 / to_float(self.dpi_x if self.dpi_x > 0 else 96)
        nat_h := to_float(self.height) * 914400.0 / to_float(self.dpi_y if self.dpi_y > 0 else 96)
        if nat_w <= 0:
            nat_w = 914400.0
        if nat_h <= 0:
            nat_h = 914400.0
        if width == null and height == null:
            return [to_int(nat_w), to_int(nat_h)]
        if width != null and height != null:
            return [u.length(width), u.length(height)]
        if width != null:
            w := u.length(width)
            return [w, to_int(to_float(w) * nat_h / nat_w)]
        h := u.length(height)
        return [to_int(to_float(h) * nat_w / nat_h), h]

# Charge une image (chemin, octets ou Image) ; FormatError si le format n'est pas reconnu.
func load_image(src):
    if type(src) == "str":
        data := io.read_bytes(src)
        info := u.image_info(data)
        if info == null:
            errors.fail(errors.FORMAT, "format d'image non reconnu : " + src)
        return Image(data, info)
    if type(src) == "list":
        info := u.image_info(src)
        if info == null:
            errors.fail(errors.FORMAT, "format d'image non reconnu")
        return Image(src, info)
    if isinstance(src, Image):
        return src
    raise("TypeError", "image : chemin, octets ou Image attendus")

# ---------------------------------------------------------------------------------------------- pages

const PAGE_SIZES := {"A3": [841.89, 1190.55], "A4": [595.28, 841.89], "A5": [419.53, 595.28], "A6": [297.64, 419.53], "B5": [498.9, 708.66], "LETTER": [612.0, 792.0], "LEGAL": [612.0, 1008.0], "TABLOID": [792.0, 1224.0], "EXECUTIVE": [522.0, 756.0]}

# Taille de page [largeur, hauteur] en points : nom ("A4", "letter"...) ou [l, h] (nombres en points ou textes
# « 21cm »). landscape échange les dimensions si besoin.
func page_size(spec="A4", landscape=false):
    w := 0.0
    h := 0.0
    if type(spec) == "str":
        k := string.upper(string.trim(spec))
        if not contains_key(PAGE_SIZES, k):
            raise("ValueError", "format de page inconnu : '" + spec + "' (A3, A4, A5, A6, B5, Letter, Legal, Tabloid, Executive)")
        w = PAGE_SIZES[k][0]
        h = PAGE_SIZES[k][1]
    else:
        w = u.emu_to_pt(u.length(spec[0], "pt"))
        h = u.emu_to_pt(u.length(spec[1], "pt"))
    if landscape and w < h:
        return [h, w]
    if not landscape and w > h and type(spec) == "str":
        return [h, w]
    return [w, h]
