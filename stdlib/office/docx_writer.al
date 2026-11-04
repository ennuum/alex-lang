# ALEX STANDARD LIBRARY — office.docx_writer
# Écriture des documents Word (.docx, ECMA-376 / ISO 29500 transitionnel) : document.xml, styles.xml,
# settings.xml, numbering.xml (puces et numérotation multiniveau), en-têtes et pieds de page, images, liens
# hypertexte, propriétés (docProps). Le résultat s'ouvre dans Word, LibreOffice, Google Docs, Pages.
#
#   use office.docx_writer as writer
#   writer.save(doc, "sortie.docx")                  # doc : word.WordDocument (ou tout objet de même forme)
#   octets := writer.to_bytes(doc)
#
# Forme attendue de `doc` : body (blocs Paragraph / Table), styles (StyleSheet), section (dict, voir
#   docx_reader), header / footer / first_header / first_footer (listes de blocs), metadata (Metadata),
#   update_fields (bool : Word recalcule les champs — sommaire — à l'ouverture).
# Fonctions : to_bytes(doc)  save(doc, chemin)  build_package(doc) -> core.Package
#   numbering_xml(listes) -> nœud   settings_xml(update_fields=false) -> nœud
#   BULLETS : caractères de puce par niveau   NUMBER_FORMATS : formats de numérotation par niveau
# Erreurs : DOCXError, TypeError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.core as core
use office.metadata as metadata
use office.docx_styles as styles
use office.docx_paragraphs as dp
use office.docx_tables as dt

const BULLETS := ["•", "◦", "▪", "•", "◦", "▪", "•", "◦", "▪"]
const NUMBER_FORMATS := [["decimal", "%1."], ["lowerLetter", "%2."], ["lowerRoman", "%3."], ["decimal", "%4."], ["lowerLetter", "%5."], ["lowerRoman", "%6."], ["decimal", "%7."], ["lowerLetter", "%8."], ["lowerRoman", "%9."]]

class _Lists:
    func init():
        self.map = {}
        self.order = []

    func num(kind, list_id):
        key := kind + ":" + u.to_text(list_id)
        if contains_key(self.map, key):
            return self.map[key]
        nid := len(self.order) + 1
        self.map[key] = nid
        append(self.order, [nid, kind])
        return nid

class _WriteCtx:
    func init(pkg, part, shared):
        self.pkg = pkg
        self.part = part
        self.shared = shared
        self._links = {}

    func link_rel(url):
        if contains_key(self._links, url):
            return self._links[url]
        rid := self.pkg.add_rel(self.part, core.REL_HYPERLINK, url, true)
        self._links[url] = rid
        return rid

    func image_rel(image):
        key := self.part + "|" + str(_n.crc32(image.data, 0)) + ":" + str(len(image.data))
        imgs := self.shared["images"]
        if contains_key(imgs, key):
            return imgs[key]
        media_key := str(_n.crc32(image.data, 0)) + ":" + str(len(image.data))
        media := self.shared["media"]
        name := null
        if contains_key(media, media_key):
            name = media[media_key]
        else:
            name = self.pkg.unique_name("word/media/image", "." + image.ext)
            self.pkg.write_part(name, image.data, null, false)
            media[media_key] = name
        rid := self.pkg.add_rel(self.part, core.REL_IMAGE, self.pkg.relative(self.part, name))
        imgs[key] = rid
        return rid

    func next_shape_id():
        self.shared["shape"] = self.shared["shape"] + 1
        return self.shared["shape"]

    func next_bookmark_id():
        self.shared["bookmark"] = self.shared["bookmark"] + 1
        return self.shared["bookmark"]

    func list_num(kind, list_id):
        if kind != "bullet" and kind != "number":
            raise("ValueError", "liste : type 'bullet' ou 'number' attendu (obtenu '" + str(kind) + "')")
        return self.shared["lists"].num(kind, list_id)

func _lvl(i, kind):
    kids := [x.el("w:start", {"w:val": "1"})]
    if kind == "bullet":
        append(kids, x.el("w:numFmt", {"w:val": "bullet"}))
        append(kids, x.el("w:lvlText", {"w:val": BULLETS[i]}))
    else:
        append(kids, x.el("w:numFmt", {"w:val": NUMBER_FORMATS[i][0]}))
        append(kids, x.el("w:lvlText", {"w:val": NUMBER_FORMATS[i][1]}))
    append(kids, x.el("w:lvlJc", {"w:val": "left"}))
    append(kids, x.el("w:pPr", null, [x.el("w:ind", {"w:left": str(720 * (i + 1)), "w:hanging": "360"})]))
    return x.el("w:lvl", {"w:ilvl": str(i)}, kids)

func _abstract(ident, kind):
    kids := [x.el("w:multiLevelType", {"w:val": "hybridMultilevel"})]
    i := 0
    while i < 9:
        append(kids, _lvl(i, kind))
        i = i + 1
    return x.el("w:abstractNum", {"w:abstractNumId": str(ident)}, kids)

# numbering.xml : un modèle abstrait de puces (0) et un de numérotation (1) ; chaque liste numérotée a sa
# propre instance (redémarrage à 1).
func numbering_xml(lists):
    kids := [_abstract(0, "bullet"), _abstract(1, "number")]
    for item in lists.order:
        nid := item[0]
        kind := item[1]
        nk := [x.el("w:abstractNumId", {"w:val": "0" if kind == "bullet" else "1"})]
        if kind == "number":
            append(nk, x.el("w:lvlOverride", {"w:ilvl": "0"}, [x.el("w:startOverride", {"w:val": "1"})]))
        append(kids, x.el("w:num", {"w:numId": str(nid)}, nk))
    return x.el("w:numbering", {"xmlns:w": x.NS["w"]}, kids)

func settings_xml(update_fields=false, language="fr-FR"):
    kids := [x.el("w:zoom", {"w:percent": "100"})]
    if update_fields:
        append(kids, x.el("w:updateFields", {"w:val": "true"}))
    append(kids, x.el("w:defaultTabStop", {"w:val": "708"}))
    append(kids, x.el("w:hyphenationZone", {"w:val": "425"}))
    append(kids, x.el("w:characterSpacingControl", {"w:val": "doNotCompress"}))
    append(kids, x.el("w:compat", null, [x.el("w:compatSetting", {"w:name": "compatibilityMode", "w:uri": "http://schemas.microsoft.com/office/word", "w:val": "15"})]))
    append(kids, x.el("w:themeFontLang", {"w:val": language}))
    append(kids, x.el("w:decimalSymbol", {"w:val": ","}) if string.starts_with(language, "fr") else x.el("w:decimalSymbol", {"w:val": "."}))
    append(kids, x.el("w:listSeparator", {"w:val": ";"}) if string.starts_with(language, "fr") else x.el("w:listSeparator", {"w:val": ","}))
    return x.el("w:settings", {"xmlns:w": x.NS["w"], "xmlns:r": x.NS["r"]}, kids)

const _DOC_NS := ["w", "r", "wp", "a", "pic"]

func _tw(pt):
    return str(to_int(u.round_to(to_float(pt) * 20.0, 0)))

func _section_xml(sec, refs):
    kids := []
    for r in refs:
        append(kids, r)
    w := u.get(sec, "page_width", 595.3)
    h := u.get(sec, "page_height", 841.9)
    orient := u.get(sec, "orientation", "portrait")
    if orient == "landscape" and w < h:
        t := w
        w = h
        h = t
    if orient != "landscape" and w > h:
        t := w
        w = h
        h = t
    append(kids, x.el("w:pgSz", {"w:w": _tw(w), "w:h": _tw(h), "w:orient": "landscape" if orient == "landscape" else null}))
    append(kids, x.el("w:pgMar", {"w:top": _tw(u.get(sec, "margin_top", 70.85)), "w:right": _tw(u.get(sec, "margin_right", 70.85)), "w:bottom": _tw(u.get(sec, "margin_bottom", 70.85)), "w:left": _tw(u.get(sec, "margin_left", 70.85)), "w:header": _tw(u.get(sec, "margin_header", 35.4)), "w:footer": _tw(u.get(sec, "margin_footer", 35.4)), "w:gutter": "0"}))
    cols := u.get(sec, "columns", 1)
    append(kids, x.el("w:cols", {"w:space": "708", "w:num": str(cols) if cols > 1 else null}))
    if u.get(sec, "title_page", false):
        append(kids, x.el("w:titlePg"))
    append(kids, x.el("w:docGrid", {"w:linePitch": "360"}))
    return x.el("w:sectPr", null, kids)

func _text_width(sec):
    w := u.get(sec, "page_width", 595.3)
    h := u.get(sec, "page_height", 841.9)
    if u.get(sec, "orientation", "portrait") == "landscape" and w < h:
        w = h
    return to_int(u.round_to((to_float(w) - to_float(u.get(sec, "margin_left", 70.85)) - to_float(u.get(sec, "margin_right", 70.85))) * 20.0, 0))

func _block_xml(b, ctx, width):
    if isinstance(b, dp.Paragraph):
        return b.to_xml(ctx)
    if isinstance(b, dt.Table):
        return b.to_xml(ctx, width)
    errors.fail(errors.DOCX, "bloc inconnu dans le document (Paragraph ou Table attendu)")

func _blocks_xml(blocks, ctx, width, out):
    prev_table := false
    for b in blocks:
        if isinstance(b, dt.Table) and prev_table:
            # deux tableaux consécutifs fusionneraient : paragraphe vide intercalé
            append(out, x.el("w:p"))
        append(out, _block_xml(b, ctx, width))
        prev_table = isinstance(b, dt.Table)
    return prev_table

func _hf_part(pkg, shared, kind, index, blocks, width):
    name := "word/" + kind + str(index) + ".xml"
    ctx := _WriteCtx(pkg, name, shared)
    kids := []
    last_table := _blocks_xml(blocks, ctx, width, kids)
    if len(kids) == 0 or last_table:
        append(kids, x.el("w:p"))
    root_tag := "w:hdr" if kind == "header" else "w:ftr"
    root := x.el(root_tag, x.xmlns(_DOC_NS), kids)
    pkg.write_xml(name, root, core.CT_DOCX_HEADER if kind == "header" else core.CT_DOCX_FOOTER)
    return pkg.add_rel("word/document.xml", core.REL_HEADER if kind == "header" else core.REL_FOOTER, kind + str(index) + ".xml")

func build_package(doc):
    pkg := core.new_package()
    pkg.set_default("rels", core.CT_RELS)
    pkg.set_default("xml", core.CT_XML)
    shared := {"images": {}, "media": {}, "shape": 0, "bookmark": 0, "lists": _Lists()}
    main := "word/document.xml"
    pkg.add_rel("", core.REL_OFFICE_DOCUMENT, main)
    sec := doc.section
    width := _text_width(sec)
    # styles, paramètres
    sheet := doc.styles
    if sheet == null:
        sheet = styles.default_styles()
    pkg.write_xml("word/styles.xml", sheet.to_xml(), core.CT_DOCX_STYLES)
    pkg.add_rel(main, core.REL_STYLES, "styles.xml")
    pkg.write_xml("word/settings.xml", settings_xml(doc.update_fields, sheet.language), core.CT_DOCX_SETTINGS)
    pkg.add_rel(main, core.REL_SETTINGS, "settings.xml")
    # en-têtes / pieds de page
    refs := []
    k := 1
    for spec in [["header", "default", doc.header], ["footer", "default", doc.footer], ["header", "first", doc.first_header], ["footer", "first", doc.first_footer]]:
        blocks := spec[2]
        if blocks != null and len(blocks) > 0:
            rid := _hf_part(pkg, shared, spec[0], k, blocks, width)
            append(refs, x.el("w:" + spec[0] + "Reference", {"w:type": spec[1], "r:id": rid}))
            k = k + 1
    # corps
    ctx := _WriteCtx(pkg, main, shared)
    kids := []
    _blocks_xml(doc.body, ctx, width, kids)
    s2 := u.merge(sec, null)
    if doc.first_header != null and len(doc.first_header) > 0 or doc.first_footer != null and len(doc.first_footer) > 0:
        s2["title_page"] = true
    append(kids, _section_xml(s2, refs))
    root := x.el("w:document", x.xmlns(_DOC_NS), [x.el("w:body", null, kids)])
    pkg.write_xml(main, root, core.CT_DOCX_MAIN)
    # numérotation (après le corps : les listes sont connues)
    if len(shared["lists"].order) > 0:
        pkg.write_xml("word/numbering.xml", numbering_xml(shared["lists"]), core.CT_DOCX_NUMBERING)
        pkg.add_rel(main, core.REL_NUMBERING, "numbering.xml")
    # propriétés
    m := doc.metadata
    if m == null:
        m = metadata.new()
    mm := m.copy()
    now := u.now_iso()
    if mm.created == "":
        mm.created = now
    if mm.modified == "":
        mm.modified = now
    if mm.application == "":
        mm.application = metadata.GENERATOR
    metadata.apply_package(pkg, mm)
    return pkg

func to_bytes(doc):
    return build_package(doc).to_bytes()

func save(doc, path):
    build_package(doc).save(path)
    return path
