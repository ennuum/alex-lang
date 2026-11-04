# ALEX STANDARD LIBRARY — office.metadata
# Propriétés de document (titre, auteur, mots-clés, dates...) pour OOXML (docProps/core.xml, app.xml, custom.xml),
# ODF (meta.xml) et PDF (dictionnaire Info), avec un modèle unique : Metadata.
#
#   use office.metadata as meta
#   m := meta.read("rapport.docx")                    # aussi .xlsx .pptx .odt .ods .odp .pdf
#   print(m.title + " — " + m.creator)
#   m.title = "Rapport annuel"
#   m.keywords = "bilan, 2026"
#   m.custom["Projet"] = "Atlas"                      # propriétés personnalisées : str, int, float, bool
#   meta.write("rapport.docx", m)                     # réécrit le fichier (ou meta.write(src, m, "copie.docx"))
#
# Metadata : title subject creator keywords description last_modified_by revision created modified category
#   language content_status identifier version  ·  application company manager template pages words characters
#   ·  custom (dict nom -> valeur)  ·  to_dict()  update(dict)  copy()
#   Les dates sont des textes W3CDTF « AAAA-MM-JJTHH:MM:SSZ » (utils.iso_datetime / utils.now_iso).
# Fonctions : new(champs=null)  read(chemin)  write(chemin, m, sortie=null)
#   from_package(pkg) / apply_package(pkg, m)            (paquet OPC, voir core.Package)
#   from_odf(archive) / odf_meta(m) -> nœud XML / apply_odf(archive, m)
#   from_pdf_info(dict) / to_pdf_info(m)                 (clés PDF : Title Author Subject Keywords Creator Producer
#                                                         CreationDate ModDate, dates « D:AAAAMMJJHHMMSSZ »)
#   pdf_date(iso) / iso_from_pdf_date(texte)
# Erreurs : FormatError (format sans métadonnées connues), XMLError, ArchiveError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use io
use office.errors as errors
use office.utils as u
use office.xml as x
use office.archive as zip
use office.core as core
use office.pdf_reader as _pdfr
use office.pdf_writer as _pdfw

const _FIELDS := ["title", "subject", "creator", "keywords", "description", "last_modified_by", "revision", "created", "modified", "category", "language", "content_status", "identifier", "version", "application", "company", "manager", "template", "pages", "words", "characters"]
const GENERATOR := "ALEX Office"

class Metadata:
    func init():
        self.title = ""
        self.subject = ""
        self.creator = ""
        self.keywords = ""
        self.description = ""
        self.last_modified_by = ""
        self.revision = ""
        self.created = ""
        self.modified = ""
        self.category = ""
        self.language = ""
        self.content_status = ""
        self.identifier = ""
        self.version = ""
        self.application = GENERATOR
        self.company = ""
        self.manager = ""
        self.template = ""
        self.pages = null
        self.words = null
        self.characters = null
        self.custom = {}

    func get(name):
        d := self.to_dict()
        return d[name]

    func to_dict():
        return {"title": self.title, "subject": self.subject, "creator": self.creator, "keywords": self.keywords, "description": self.description, "last_modified_by": self.last_modified_by, "revision": self.revision, "created": self.created, "modified": self.modified, "category": self.category, "language": self.language, "content_status": self.content_status, "identifier": self.identifier, "version": self.version, "application": self.application, "company": self.company, "manager": self.manager, "template": self.template, "pages": self.pages, "words": self.words, "characters": self.characters, "custom": u.deep_copy(self.custom)}

    # Met à jour à partir d'un dict (clés de to_dict ; "author" est accepté pour creator).
    func update(d):
        for k in keys(d):
            v := d[k]
            if k == "title":
                self.title = u.to_text(v)
            elif k == "subject":
                self.subject = u.to_text(v)
            elif k == "creator" or k == "author":
                self.creator = u.to_text(v)
            elif k == "keywords":
                if type(v) == "list":
                    self.keywords = string.join(", ", v)
                else:
                    self.keywords = u.to_text(v)
            elif k == "description" or k == "comments":
                self.description = u.to_text(v)
            elif k == "last_modified_by":
                self.last_modified_by = u.to_text(v)
            elif k == "revision":
                self.revision = u.to_text(v)
            elif k == "created":
                self.created = _date_text(v)
            elif k == "modified":
                self.modified = _date_text(v)
            elif k == "category":
                self.category = u.to_text(v)
            elif k == "language":
                self.language = u.to_text(v)
            elif k == "content_status":
                self.content_status = u.to_text(v)
            elif k == "identifier":
                self.identifier = u.to_text(v)
            elif k == "version":
                self.version = u.to_text(v)
            elif k == "application":
                self.application = u.to_text(v)
            elif k == "company":
                self.company = u.to_text(v)
            elif k == "manager":
                self.manager = u.to_text(v)
            elif k == "template":
                self.template = u.to_text(v)
            elif k == "pages":
                self.pages = v
            elif k == "words":
                self.words = v
            elif k == "characters":
                self.characters = v
            elif k == "custom":
                for ck in keys(v):
                    self.custom[ck] = v[ck]
            else:
                raise("ValueError", "metadata : champ inconnu '" + k + "'")
        return self

    func copy():
        m := Metadata()
        m.update(self.to_dict())
        return m

func _date_text(v):
    if v == null or v == "":
        return ""
    if type(v) == "dict":
        return u.iso_datetime(v)
    return u.to_text(v)

func new(fields=null):
    m := Metadata()
    if fields != null:
        m.update(fields)
    return m

# ---------------------------------------------------------------------------------------------- OOXML

const _CORE_MAP := [["title", "dc:title"], ["subject", "dc:subject"], ["creator", "dc:creator"], ["keywords", "cp:keywords"], ["description", "dc:description"], ["last_modified_by", "cp:lastModifiedBy"], ["revision", "cp:revision"], ["created", "dcterms:created"], ["modified", "dcterms:modified"], ["category", "cp:category"], ["language", "dc:language"], ["content_status", "cp:contentStatus"], ["identifier", "dc:identifier"], ["version", "cp:version"]]
const _APP_MAP := [["application", "Application"], ["company", "Company"], ["manager", "Manager"], ["template", "Template"], ["pages", "Pages"], ["words", "Words"], ["characters", "Characters"]]
const _FMTID := "{D5CDD505-2E9C-101B-9397-08002B2CF9AE}"

func _vt_value(node):
    for c in x.children(node):
        ln := x.local_name(c["tag"])
        t := x.text(c)
        if ln == "i1" or ln == "i2" or ln == "i4" or ln == "i8" or ln == "int" or ln == "ui1" or ln == "ui2" or ln == "ui4" or ln == "ui8" or ln == "uint":
            v := _n.num_parse(t)
            return to_int(v) if v != null else t
        if ln == "r4" or ln == "r8" or ln == "decimal":
            v := _n.num_parse(t)
            return to_float(v) if v != null else t
        if ln == "bool":
            return string.lower(t) == "true" or t == "1"
        return t
    return x.text(node)

func from_package(pkg):
    m := Metadata()
    m.application = ""
    cp := pkg.target("", core.REL_CORE_PROPS)
    if cp == null and pkg.has_part("docProps/core.xml"):
        cp = "docProps/core.xml"
    if cp != null and pkg.has_part(cp):
        root := pkg.read_xml(cp)
        for pair in _CORE_MAP:
            el := x.first(root, pair[1])
            if el != null:
                m.update({pair[0]: string.trim(x.text(el))})
    ap := pkg.target("", core.REL_EXT_PROPS)
    if ap == null and pkg.has_part("docProps/app.xml"):
        ap = "docProps/app.xml"
    if ap != null and pkg.has_part(ap):
        root := pkg.read_xml(ap)
        for pair in _APP_MAP:
            el := x.first(root, pair[1])
            if el != null:
                t := string.trim(x.text(el))
                if pair[0] == "pages" or pair[0] == "words" or pair[0] == "characters":
                    v := _n.num_parse(t)
                    m.update({pair[0]: to_int(v) if v != null else null})
                else:
                    m.update({pair[0]: t})
    cu := pkg.target("", core.REL_CUSTOM_PROPS)
    if cu != null and pkg.has_part(cu):
        root := pkg.read_xml(cu)
        for p in x.children(root, "property"):
            m.custom[x.attr(p, "name", "")] = _vt_value(p)
    return m

func _core_xml(m):
    d := m.to_dict()
    kids := []
    for pair in _CORE_MAP:
        v := d[pair[0]]
        if v == null or v == "":
            continue
        attrs := {}
        if pair[0] == "created" or pair[0] == "modified":
            attrs = {"xsi:type": "dcterms:W3CDTF"}
        append(kids, x.el(pair[1], attrs, [u.to_text(v)]))
    attrs := {"xmlns:cp": x.NS["cp"], "xmlns:dc": x.NS["dc"], "xmlns:dcterms": x.NS["dcterms"], "xmlns:dcmitype": x.NS["dcmitype"], "xmlns:xsi": x.NS["xsi"]}
    return x.el("cp:coreProperties", attrs, kids)

func _app_xml(m, extra=null):
    d := m.to_dict()
    kids := []
    for pair in _APP_MAP:
        v := d[pair[0]]
        if v == null or v == "":
            continue
        append(kids, x.el(pair[1], null, [u.to_text(v)]))
    if extra != null:
        for e in extra:
            append(kids, e)
    return x.el("Properties", {"xmlns": x.NS["ep"], "xmlns:vt": x.NS["vt"]}, kids)

func _custom_xml(m):
    kids := []
    pid := 2
    for name in keys(m.custom):
        v := m.custom[name]
        t := type(v)
        val := null
        if t == "bool":
            val = x.el("vt:bool", null, ["true" if v else "false"])
        elif t == "int":
            val = x.el("vt:i4" if v >= -2147483648 and v <= 2147483647 else "vt:i8", null, [str(v)])
        elif t == "float":
            val = x.el("vt:r8", null, [u.format_number(v)])
        elif u.is_date_dict(v):
            val = x.el("vt:filetime", null, [u.iso_datetime(v)])
        else:
            val = x.el("vt:lpwstr", null, [u.to_text(v)])
        append(kids, x.el("property", {"fmtid": _FMTID, "pid": str(pid), "name": name}, [val]))
        pid = pid + 1
    return x.el("Properties", {"xmlns": x.NS["cust"], "xmlns:vt": x.NS["vt"]}, kids)

func _ensure_rel(pkg, rel_type, target):
    if len(pkg.rels_of_type("", rel_type)) == 0:
        pkg.add_rel("", rel_type, target)

# Écrit core.xml, app.xml (en conservant les éléments inconnus de app.xml) et custom.xml dans un paquet OPC.
func apply_package(pkg, m):
    pkg.write_xml("docProps/core.xml", _core_xml(m), core.CT_CORE_PROPS)
    _ensure_rel(pkg, core.REL_CORE_PROPS, "docProps/core.xml")
    extra := []
    if pkg.has_part("docProps/app.xml"):
        try:
            old := pkg.read_xml("docProps/app.xml")
            known := {}
            for pair in _APP_MAP:
                known[pair[1]] = true
            for c in x.children(old):
                if not contains_key(known, x.local_name(c["tag"])):
                    append(extra, c)
        catch e:
            extra = []
    pkg.write_xml("docProps/app.xml", _app_xml(m, extra), core.CT_EXT_PROPS)
    _ensure_rel(pkg, core.REL_EXT_PROPS, "docProps/app.xml")
    if len(keys(m.custom)) > 0:
        pkg.write_xml("docProps/custom.xml", _custom_xml(m), core.CT_CUSTOM_PROPS)
        _ensure_rel(pkg, core.REL_CUSTOM_PROPS, "docProps/custom.xml")

# ---------------------------------------------------------------------------------------------- ODF

const _ODF_MAP := [["title", "dc:title"], ["description", "dc:description"], ["subject", "dc:subject"], ["creator", "meta:initial-creator"], ["last_modified_by", "dc:creator"], ["created", "meta:creation-date"], ["modified", "dc:date"], ["language", "dc:language"], ["revision", "meta:editing-cycles"], ["application", "meta:generator"]]

func from_odf(archive):
    m := Metadata()
    m.application = ""
    if not archive.contains("meta.xml"):
        return m
    root := x.parse(archive.read_text("meta.xml"))
    om := x.first(root, "office:meta")
    if om == null:
        return m
    for pair in _ODF_MAP:
        el := x.first(om, pair[1])
        if el != null:
            m.update({pair[0]: string.trim(x.text(el))})
    kws := []
    for k in x.children(om, "meta:keyword"):
        append(kws, string.trim(x.text(k)))
    m.keywords = string.join(", ", kws)
    stats := x.first(om, "meta:document-statistic")
    if stats != null:
        m.pages = x.attr_int(stats, "meta:page-count", null)
        m.words = x.attr_int(stats, "meta:word-count", null)
        m.characters = x.attr_int(stats, "meta:character-count", null)
    for ud in x.children(om, "meta:user-defined"):
        name := x.attr(ud, "meta:name", "")
        vt := x.attr(ud, "meta:value-type", "string")
        t := x.text(ud)
        if vt == "float":
            v := _n.num_parse(t)
            m.custom[name] = v if v != null else t
        elif vt == "boolean":
            m.custom[name] = t == "true"
        else:
            m.custom[name] = t
    return m

func odf_meta(m):
    d := m.to_dict()
    kids := []
    for pair in _ODF_MAP:
        v := d[pair[0]]
        if pair[0] == "application" and (v == null or v == ""):
            v = GENERATOR
        if v == null or v == "":
            continue
        txt := u.to_text(v)
        if pair[0] == "created" or pair[0] == "modified":
            if string.ends_with(txt, "Z"):
                txt = _n.str_slice(txt, 0, len(txt) - 1)
        append(kids, x.el(pair[1], null, [txt]))
    if m.keywords != "":
        for k in string.split(m.keywords, ","):
            if string.trim(k) != "":
                append(kids, x.el("meta:keyword", null, [string.trim(k)]))
    for name in keys(m.custom):
        v := m.custom[name]
        t := type(v)
        vt := "string"
        if t == "int" or t == "float":
            vt = "float"
        elif t == "bool":
            vt = "boolean"
        append(kids, x.el("meta:user-defined", {"meta:name": name, "meta:value-type": vt}, [u.to_text(v)]))
    root := x.el("office:document-meta", {"xmlns:office": x.NS["office"], "xmlns:meta": x.NS["meta"], "xmlns:dc": x.NS["dc"], "xmlns:xlink": x.NS["xlink"], "office:version": "1.3"}, [x.el("office:meta", null, kids)])
    return root

func apply_odf(archive, m):
    archive.write("meta.xml", x.to_bytes(odf_meta(m), true))
    if archive.contains("META-INF/manifest.xml"):
        man := archive.read_text("META-INF/manifest.xml")
        if not string.contains(man, "\"meta.xml\""):
            man = string.replace(man, "</manifest:manifest>", "<manifest:file-entry manifest:full-path=\"meta.xml\" manifest:media-type=\"text/xml\"/></manifest:manifest>")
            archive.write("META-INF/manifest.xml", _n.utf8_encode(man))

# ---------------------------------------------------------------------------------------------- PDF

# "2026-03-15T10:20:30Z" -> "D:20260315102030Z"
func pdf_date(iso):
    if iso == null or iso == "":
        return ""
    f := u.date_parts(iso)
    return "D:" + u.pad_left(str(f["year"]), 4, "0") + u.pad_left(str(f["month"]), 2, "0") + u.pad_left(str(f["day"]), 2, "0") + u.pad_left(str(f["hour"]), 2, "0") + u.pad_left(str(f["minute"]), 2, "0") + u.pad_left(str(f["second"]), 2, "0") + "Z"

# "D:20260315102030+01'00'" -> "2026-03-15T09:20:30Z" (converti en UTC quand le décalage est donné).
func iso_from_pdf_date(s):
    if s == null:
        return ""
    t := string.trim(s)
    if string.starts_with(t, "D:"):
        t = _n.str_slice(t, 2, null)
    digits := ""
    rest := ""
    i := 0
    for c in t:
        o := string.ord(c)
        if o >= 48 and o <= 57 and rest == "":
            digits = digits + str(c)
        else:
            rest = rest + str(c)
        i = i + 1
    if len(digits) < 4:
        return ""
    def_ := "00000101000000"
    full := digits + _n.str_slice(def_, len(digits) if len(digits) < 14 else 14, null)
    y := to_int(_n.str_slice(full, 0, 4))
    mo := to_int(_n.str_slice(full, 4, 6))
    d := to_int(_n.str_slice(full, 6, 8))
    h := to_int(_n.str_slice(full, 8, 10))
    mi := to_int(_n.str_slice(full, 10, 12))
    se := to_int(_n.str_slice(full, 12, 14))
    if mo < 1:
        mo = 1
    if d < 1:
        d = 1
    off := 0
    r := string.replace(rest, "'", "")
    if len(r) >= 3 and (string.starts_with(r, "+") or string.starts_with(r, "-")):
        oh := _n.num_parse(_n.str_slice(r, 1, 3))
        om := 0
        if len(r) >= 5:
            v := _n.num_parse(_n.str_slice(r, 3, 5))
            if v != null:
                om = v
        if oh != null:
            off = oh * 60 + om
            if string.starts_with(r, "-"):
                off = -off
    try:
        serial := u.date_to_serial(y, mo, d, h, mi, se)
        if off != 0:
            serial = to_float(serial) - to_float(off) / 1440.0
        return u.iso_datetime(u.serial_to_date(serial))
    catch e:
        return ""

func from_pdf_info(info):
    m := Metadata()
    m.application = ""
    if info == null:
        return m
    m.title = u.get(info, "Title", "")
    m.creator = u.get(info, "Author", "")
    m.subject = u.get(info, "Subject", "")
    m.keywords = u.get(info, "Keywords", "")
    m.application = u.get(info, "Creator", "")
    m.created = iso_from_pdf_date(u.get(info, "CreationDate", ""))
    m.modified = iso_from_pdf_date(u.get(info, "ModDate", ""))
    for k in keys(info):
        if k != "Title" and k != "Author" and k != "Subject" and k != "Keywords" and k != "Creator" and k != "Producer" and k != "CreationDate" and k != "ModDate" and k != "Trapped":
            if type(info[k]) == "str":
                m.custom[k] = info[k]
    return m

func to_pdf_info(m):
    out := {}
    if m.title != "":
        out["Title"] = m.title
    if m.creator != "":
        out["Author"] = m.creator
    if m.subject != "":
        out["Subject"] = m.subject
    if m.keywords != "":
        out["Keywords"] = m.keywords
    out["Creator"] = m.application if m.application != "" else GENERATOR
    out["Producer"] = GENERATOR
    if m.created != "":
        out["CreationDate"] = pdf_date(m.created)
    if m.modified != "":
        out["ModDate"] = pdf_date(m.modified)
    for k in keys(m.custom):
        out[k] = u.to_text(m.custom[k])
    return out

# ---------------------------------------------------------------------------------------------- fichiers

func read(path):
    fmt := core.detect_format(path)
    if fmt == "docx" or fmt == "xlsx" or fmt == "pptx":
        return from_package(core.open_package(path))
    if fmt == "odt" or fmt == "ods" or fmt == "odp":
        return from_odf(zip.open(path))
    if fmt == "pdf":
        return from_pdf_info(_pdf_info(path))
    errors.fail(errors.FORMAT, "metadata.read : format sans métadonnées prises en charge : " + fmt)

# Réécrit les métadonnées de `path` (dans `out` si donné). « modified » est mis à l'heure courante s'il est vide.
func write(path, m, out=null):
    dest := out
    if dest == null:
        dest = path
    mm := m.copy()
    if mm.modified == "":
        mm.modified = u.now_iso()
    fmt := core.detect_format(path)
    if fmt == "docx" or fmt == "xlsx" or fmt == "pptx":
        pkg := core.open_package(path)
        apply_package(pkg, mm)
        pkg.save(dest)
        return dest
    if fmt == "odt" or fmt == "ods" or fmt == "odp":
        a := zip.open(path)
        apply_odf(a, mm)
        a.save(dest)
        return dest
    if fmt == "pdf":
        _pdf_set_info(path, to_pdf_info(mm), dest)
        return dest
    errors.fail(errors.FORMAT, "metadata.write : format non pris en charge : " + fmt)

func _pdf_info(path):
    return _pdfr.open(path).info()

func _pdf_set_info(path, info, dest):
    _pdfw.update_info(_pdfr.open(path), info, dest)
