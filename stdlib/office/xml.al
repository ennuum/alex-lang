# ALEX STANDARD LIBRARY — office.xml
# XML pour les formats bureautiques (OOXML, ODF, SVG, rels...). Même modèle que le module standard `xml`
# (élément = {"tag", "attrs", "children"}, enfant = élément ou str), mais :
#   - analyse et sérialisation natives (plusieurs Mo/s), blancs CONSERVÉS par défaut (indispensable pour Word :
#     <w:t xml:space="preserve"> </w:t>) ;
#   - l'ORDRE des attributs est conservé (pas de tri) ;
#   - recherche par nom local, insensible au préfixe (« p » trouve « w:p » comme « a:p ») ;
#   - fragments bruts {"raw": "<xml .../>"} insérés tels quels à la sérialisation ;
#   - un attribut de valeur null n'est pas écrit (pratique pour les options facultatives).
#
#   use office.xml as x
#   root := x.parse(texte)
#   for p in x.find_all(root, "w:p"):                 # descendants
#       print(x.text(p))
#   x.first(root, "w:body")                           # premier enfant direct portant ce nom
#   x.path(root, "w:body/w:tbl/w:tr")                 # tous les éléments au bout du chemin
#   x.attr(el, "w:val", "défaut")
#   doc := x.el("w:p", {"w:rsidR": null}, [x.el("w:r", null, [x.el("w:t", {"xml:space": "preserve"}, ["Bonjour"])])])
#   x.stringify(doc, true)                            # avec déclaration <?xml ... standalone="yes"?>
#
# ANALYSE      parse(texte, keep_whitespace=true)   parse_bytes(octets, keep_whitespace=true)   is_valid(texte)
# SÉRIALISER   stringify(nœud, declaration=false)   to_bytes(nœud, declaration=true)   pretty(nœud, indent=2)
# CONSTRUIRE   el(tag, attrs=null, children=null)   element(...) (alias)   raw(texte_xml)   text_el(tag, texte, attrs)
# NOMS         local_name("w:p") -> "p"   prefix("w:p") -> "w"   matches(nœud, nom)   is_element(v)
# PARCOURIR    children(nœud, nom=null)  first(nœud, nom)  first_path(nœud, "a/b")  path(nœud, "a/b/c")
#              find(nœud, nom) (premier descendant)  find_all(nœud, nom)  iter(nœud) (tous les éléments)
#              parent_map(racine) -> dict id -> parent (voir find_parent)
# ATTRIBUTS    attr(nœud, nom, défaut=null)  set_attr(nœud, nom, valeur)  remove_attr(nœud, nom)  has_attr(nœud, nom)
#              attr_int(nœud, nom, défaut)  attr_float(...)  attr_bool(nœud, nom, défaut) (1/true/on)
# TEXTE        text(nœud) (texte des descendants)  own_text(nœud) (enfants texte directs)  set_text(nœud, texte)
# MODIFIER     append_child(nœud, enfant)  insert(nœud, i, enfant)  remove(nœud, enfant)  clear(nœud)  replace(nœud, ancien, nouveau)
#              index_of(nœud, enfant)
# ESPACES DE NOMS  NS (préfixe -> URI des formats Office/ODF)  ns(prefixe)  xmlns(prefixes) -> attributs xmlns:*
# ÉCHAPPEMENT  escape(s, attr=false)  unescape(s)
# Erreurs : XMLError (« ligne L, colonne C »), TypeError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use office.errors as errors

# ---------------------------------------------------------------------------------------------- espaces de noms

const NS := {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main", "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships", "wp": "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing", "a": "http://schemas.openxmlformats.org/drawingml/2006/main", "pic": "http://schemas.openxmlformats.org/drawingml/2006/picture", "p": "http://schemas.openxmlformats.org/presentationml/2006/main", "c": "http://schemas.openxmlformats.org/drawingml/2006/chart", "xdr": "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing", "x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main", "mc": "http://schemas.openxmlformats.org/markup-compatibility/2006", "rel": "http://schemas.openxmlformats.org/package/2006/relationships", "ct": "http://schemas.openxmlformats.org/package/2006/content-types", "cp": "http://schemas.openxmlformats.org/package/2006/metadata/core-properties", "dc": "http://purl.org/dc/elements/1.1/", "dcterms": "http://purl.org/dc/terms/", "dcmitype": "http://purl.org/dc/dcmitype/", "xsi": "http://www.w3.org/2001/XMLSchema-instance", "ep": "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties", "vt": "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes", "cust": "http://schemas.openxmlformats.org/officeDocument/2006/custom-properties", "office": "urn:oasis:names:tc:opendocument:xmlns:office:1.0", "style": "urn:oasis:names:tc:opendocument:xmlns:style:1.0", "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0", "table": "urn:oasis:names:tc:opendocument:xmlns:table:1.0", "draw": "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0", "fo": "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0", "svg": "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0", "xlink": "http://www.w3.org/1999/xlink", "meta": "urn:oasis:names:tc:opendocument:xmlns:meta:1.0", "number": "urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0", "presentation": "urn:oasis:names:tc:opendocument:xmlns:presentation:1.0", "chart": "urn:oasis:names:tc:opendocument:xmlns:chart:1.0", "manifest": "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0", "loext": "urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0", "of": "urn:oasis:names:tc:opendocument:xmlns:of:1.2", "smil": "urn:oasis:names:tc:opendocument:xmlns:smil-compatible:1.0", "anim": "urn:oasis:names:tc:opendocument:xmlns:animation:1.0", "w14": "http://schemas.microsoft.com/office/word/2010/wordml", "a14": "http://schemas.microsoft.com/office/drawing/2010/main", "x14ac": "http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac"}

func ns(prefix):
    if not contains_key(NS, prefix):
        raise("ValueError", "office.xml : préfixe d'espace de noms inconnu '" + prefix + "'")
    return NS[prefix]

# Attributs xmlns:* pour une liste de préfixes ; "" désigne l'espace par défaut : xmlns(["", "r"], "x") donne
# {"xmlns": URI de x, "xmlns:r": ...}.
func xmlns(prefixes, default_prefix=null):
    out := {}
    if default_prefix != null:
        out["xmlns"] = ns(default_prefix)
    for p in prefixes:
        if p == "":
            continue
        out["xmlns:" + p] = ns(p)
    return out

# ---------------------------------------------------------------------------------------------- analyse

func parse(text, keep_whitespace=true):
    if type(text) != "str":
        raise("TypeError", "office.xml.parse : chaîne attendue (obtenu '" + type(text) + "')")
    try:
        return _n.xml_parse(text, keep_whitespace)
    catch e:
        errors.rethrow(e, errors.XML, "XML invalide")

func parse_bytes(data, keep_whitespace=true):
    return parse(_n.utf8_decode(data, false), keep_whitespace)

func is_valid(text):
    try:
        parse(text)
    catch e:
        return false
    return true

func stringify(node, declaration=false):
    return _n.xml_serialize(node, declaration)

func to_bytes(node, declaration=true):
    return _n.utf8_encode(_n.xml_serialize(node, declaration))

func _only_text(node):
    for c in node["children"]:
        if type(c) != "str":
            return false
    return true

func _pretty(node, out, level, indent):
    pad := string.repeat(" ", level * indent)
    if type(node) == "str":
        t := string.trim(node)
        if t != "":
            append(out, pad + _n.xml_escape(t, false) + "\n")
        return null
    if type(node) != "dict" or not contains_key(node, "tag"):
        append(out, pad + _n.xml_serialize(node, false) + "\n")
        return null
    if len(node["children"]) == 0 or _only_text(node):
        append(out, pad + _n.xml_serialize(node, false) + "\n")
        return null
    shell := {"tag": node["tag"], "attrs": node["attrs"], "children": [{"raw": "\uE000"}]}
    s := _n.xml_serialize(shell, false)
    cut := string.find(s, "\uE000")
    if cut < 0:
        cut = _n.str_find(s, ">", 0) + 1
        append(out, pad + s + "\n")
        return null
    append(out, pad + _n.str_slice(s, 0, cut) + "\n")
    for c in node["children"]:
        _pretty(c, out, level + 1, indent)
    append(out, pad + _n.str_slice(s, cut + 1, null) + "\n")

# Version indentée (pour l'inspection humaine : les blancs significatifs des textes mixtes sont normalisés).
func pretty(node, indent=2, declaration=false):
    out := []
    if declaration:
        append(out, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
    _pretty(node, out, 0, indent)
    return string.join("", out)

# ---------------------------------------------------------------------------------------------- construction

func el(tag, attrs=null, children=null):
    a := attrs
    if a == null:
        a = {}
    c := children
    if c == null:
        c = []
    elif type(c) == "str" or type(c) == "dict":
        c = [c]
    return {"tag": tag, "attrs": a, "children": c}

func element(tag, attrs=null, children=null):
    return el(tag, attrs, children)

func text_el(tag, text, attrs=null):
    return el(tag, attrs, [text])

func raw(text):
    return {"raw": text}

func is_element(v):
    return type(v) == "dict" and contains_key(v, "tag")

# ---------------------------------------------------------------------------------------------- noms

func local_name(tag):
    p := string.find(tag, ":")
    if p < 0:
        return tag
    return _n.str_slice(tag, p + 1, null)

func prefix(tag):
    p := string.find(tag, ":")
    if p < 0:
        return ""
    return _n.str_slice(tag, 0, p)

# Vrai si l'élément porte ce nom : avec préfixe, comparaison exacte puis par nom local (les préfixes sont libres
# dans un document) ; sans préfixe, comparaison du nom local. "*" correspond à tout élément.
func matches(node, name):
    if not is_element(node):
        return false
    if name == "*":
        return true
    t := node["tag"]
    if t == name:
        return true
    return local_name(t) == local_name(name)

# ---------------------------------------------------------------------------------------------- parcours

func children(node, name=null):
    return _n.xml_children(node, name)

func first(node, name):
    return _n.xml_first(node, name)

func _path_parts(p):
    out := []
    for s in string.split(p, "/"):
        if s != "":
            append(out, s)
    return out

# Tous les éléments atteints par le chemin d'enfants directs "a/b/c" ("*" : tout élément).
func path(node, p):
    current := [node]
    for part in _path_parts(p):
        nxt := []
        for n in current:
            for c in n["children"]:
                if is_element(c) and matches(c, part):
                    append(nxt, c)
        current = nxt
    return current

func first_path(node, p):
    if node == null:
        return null
    current := node
    for part in _path_parts(p):
        current = first(current, part)
        if current == null:
            return null
    return current

# Descendants (profondeur d'abord, ordre du document) portant ce nom.
func find_all(node, name):
    return _n.xml_find_all(node, name)

func find(node, name):
    return _n.xml_find_all(node, name, true)

func _iter(node, out):
    append(out, node)
    for c in node["children"]:
        if is_element(c):
            _iter(c, out)

func iter(node):
    out := []
    _iter(node, out)
    return out

# Parent d'un élément (recherche depuis la racine, par identité ; null si absent ou racine).
func find_parent(root, target):
    for c in root["children"]:
        if is_element(c):
            if _n.same(c, target):
                return root
            r := find_parent(c, target)
            if r != null:
                return r
    return null

# ---------------------------------------------------------------------------------------------- attributs

func _attr_key(node, name):
    a := node["attrs"]
    if contains_key(a, name):
        return name
    ln := local_name(name)
    for k in keys(a):
        if local_name(k) == ln and string.find(k, "xmlns") != 0:
            return k
    return null

func attr(node, name, fallback=null):
    return _n.xml_attr(node, name, fallback)

func has_attr(node, name):
    return node != null and _attr_key(node, name) != null

func attr_int(node, name, fallback=null):
    v := attr(node, name, null)
    if v == null:
        return fallback
    n := _n.num_parse(v)
    if n == null:
        return fallback
    return to_int(n)

func attr_float(node, name, fallback=null):
    v := attr(node, name, null)
    if v == null:
        return fallback
    n := _n.num_parse(v)
    if n == null:
        return fallback
    return to_float(n)

# Booléen OOXML / ODF : "1", "true", "on" -> vrai ; "0", "false", "off", "none" -> faux ; attribut absent -> fallback.
# Un élément de bascule présent sans attribut val (<w:b/>) se teste avec attr_bool(el, "w:val", true).
func attr_bool(node, name, fallback=null):
    v := attr(node, name, null)
    if v == null:
        return fallback
    l := string.lower(v)
    if l == "1" or l == "true" or l == "on" or l == "yes":
        return true
    if l == "0" or l == "false" or l == "off" or l == "no" or l == "none":
        return false
    return fallback

func set_attr(node, name, value):
    node["attrs"][name] = value
    return node

func remove_attr(node, name):
    k := _attr_key(node, name)
    if k == null:
        return node
    collections.remove(node["attrs"], k)
    return node

# ---------------------------------------------------------------------------------------------- texte

func text(node):
    return _n.xml_text(node)

func own_text(node):
    out := []
    for c in node["children"]:
        if type(c) == "str":
            append(out, c)
    return string.join("", out)

func set_text(node, value):
    node["children"] = [value]
    return node

# ---------------------------------------------------------------------------------------------- modification

func append_child(node, child):
    collections.insert(node["children"], len(node["children"]), child)
    return child

func insert(node, i, child):
    collections.insert(node["children"], i, child)
    return child

func index_of(node, child):
    i := 0
    for c in node["children"]:
        if type(c) == "dict" and _n.same(c, child):
            return i
        if type(c) == "str" and type(child) == "str" and c == child:
            return i
        i = i + 1
    return -1

func remove(node, child):
    k := index_of(node, child)
    if k < 0:
        return false
    out := []
    i := 0
    for c in node["children"]:
        if i != k:
            collections.insert(out, len(out), c)
        i = i + 1
    node["children"] = out
    return true

func replace(node, old, new_child):
    k := index_of(node, old)
    if k < 0:
        return false
    node["children"][k] = new_child
    return true

func clear(node):
    node["children"] = []
    return node

# ---------------------------------------------------------------------------------------------- échappement

func escape(s, attr_mode=false):
    return _n.xml_escape(s, attr_mode)

func unescape(s):
    if not string.contains(s, "&"):
        return s
    r := parse("<x>" + s + "</x>", true)
    return text(r)
