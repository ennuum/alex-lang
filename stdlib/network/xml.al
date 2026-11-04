# ALEX STANDARD LIBRARY — network.xml
#
# XML de haut niveau pour les échanges réseau (flux Atom/RSS, SOAP, XML-RPC, configurations...) : analyse,
# construction, recherche, sérialisation, conversion depuis / vers des valeurs ALEX (dict / list), forme canonique
# simple. Repose sur network.xml_parser (analyse, arbre) et network.xml_writer (écriture).
#
#   parse(texte) -> Document        fromstring(texte) -> Element (racine)        load(chemin) / save(chemin, nœud)
#   element("a", {"x": "1"}, [enfants ou texte])     sub(parent, "b", attrs, texte)
#   to_string(nœud, indent)         pretty(nœud)
#   select(nœud, "a/b[@c='d']")     select_one, text_of, values
#   to_dict(élément) / from_dict(nom, valeur)        conversion « à la xmltodict » (@attributs, #text)
#   canonicalize(texte)             forme canonique simplifiée (attributs triés, espaces de noms conservés)
#   escape / unescape
#
# Erreurs : XmlError.
#
# Exemple
#   use network.xml as xml
#   doc := xml.parse(réponse_atom)
#   ns := {"a": "http://www.w3.org/2005/Atom"}
#   for e in doc.find_all("a:entry", ns):
#       print(e.find_text("a:title", "", ns))
#   racine := xml.element("commande", {"id": "42"}, [xml.element("article", null, ["café"])])
#   print(xml.to_string(racine))      # <commande id="42"><article>café</article></commande>

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use io as _io
use network.xml_parser as _xp
use network.xml_writer as _xw

func parse(text, keep_whitespace=false, namespaces=true):
    return _xp.parse(text, keep_whitespace, namespaces)

# Élément racine d'un texte XML.
func fromstring(text, keep_whitespace=false):
    return _xp.parse(text, keep_whitespace).root

func load(path, keep_whitespace=false):
    return _xp.parse(_n.from_bytes(_io.read_bytes(path)), keep_whitespace)

# Écrit un document ou un élément dans un fichier (déclaration XML et UTF-8).
func save(path, node, indent=2):
    _io.write_file(path, to_string(node, indent, true))

func is_well_formed(text):
    return _xp.is_well_formed(text)

# Nouvel élément ; children : liste d'Element, de str (texte) ou un texte seul.
func element(tag, attrs=null, children=null):
    _xw.check_name(tag)
    a := {}
    if attrs != null:
        for k in keys(attrs):
            if attrs[k] != null:
                _xw.check_name(k)
                a[k] = _attr_value(attrs[k])
    el := _xp.Element(tag, a)
    if children != null:
        if type(children) == "str" or type(children) == "int" or type(children) == "float":
            el.append(_xp.Text(str(children)))
        else:
            for c in children:
                if type(c) == "str":
                    el.append(_xp.Text(c))
                elif c != null:
                    el.append(c)
    return el

func _attr_value(v):
    if v == true:
        return "true"
    if v == false:
        return "false"
    return str(v)

# Ajoute un sous-élément à parent et le rend.
func sub(parent, tag, attrs=null, text=null):
    children := null
    if text != null:
        children = [str(text)]
    return parent.append(element(tag, attrs, children))

func text_node(data):
    return _xp.Text(str(data))

func cdata(data):
    return _xp.CData(str(data))

func comment(data):
    return _xp.Comment(str(data))

# Sérialise un nœud (Document : déclaration incluse par défaut). indent : null (exact) ou nombre d'espaces.
func to_string(node, indent=null, declaration=null):
    decl := declaration
    if decl == null:
        decl = node.kind == "document"
    return _xw.serialize(node, indent, decl)

func pretty(node, indent=2):
    return to_string(node, indent)

# Éléments sélectionnés par un chemin (voir network.xml_parser.select_path).
func select(node, path, namespaces=null):
    n := node
    if n.kind == "document":
        n = n.root
    return _xp.select_path(n, path, namespaces)

func select_one(node, path, namespaces=null):
    r := select(node, path, namespaces)
    if len(r) == 0:
        return null
    return r[0]

# Texte du premier élément du chemin, ou default.
func text_of(node, path, default=null, namespaces=null):
    e := select_one(node, path, namespaces)
    if e == null:
        return default
    return e.text()

# Textes de tous les éléments du chemin.
func values(node, path, namespaces=null):
    out := []
    for e in select(node, path, namespaces):
        append(out, e.text())
    return out

func escape(text):
    return _xw.escape(text)

func escape_attr(text):
    return _xw.escape_attr(text)

# Remplace les entités prédéfinies et les références numériques.
func unescape(text):
    if not _s.contains(text, "&"):
        return text
    return _xp.parse("<x>" + _s.replace(_s.replace(text, "<", "&lt;"), "]]>", "]]&gt;") + "</x>").root.text()

# ---------------------------------------------------------------- conversion dict <-> XML

# Valeur ALEX d'un élément : attributs sous « @nom », texte sous « #text » (ou valeur str seule s'il n'y a ni
# attribut ni enfant), enfants répétés regroupés en list. force_list : noms d'éléments toujours en list.
func to_dict(el, force_list=null, strip_ns=true):
    return {_name(el, strip_ns): _value(el, force_list, strip_ns)}

func _name(el, strip_ns):
    if strip_ns:
        return el.local
    return el.tag

func _value(el, force_list, strip_ns):
    kids := el.elements()
    text := _s.trim(el.own_text())
    if len(kids) == 0 and len(el.attrs) == 0:
        if text == "":
            return null
        return text
    d := {}
    for k in keys(el.attrs):
        if _s.starts_with(k, "xmlns") and strip_ns:
            continue
        d["@" + k] = el.attrs[k]
    order := []
    groups := {}
    for c in kids:
        nm := _name(c, strip_ns)
        if not contains_key(groups, nm):
            groups[nm] = []
            append(order, nm)
        append(groups[nm], _value(c, force_list, strip_ns))
    for nm in order:
        vals := groups[nm]
        forced := false
        if force_list != null:
            for f in force_list:
                if f == nm:
                    forced = true
        if len(vals) > 1 or forced:
            d[nm] = vals
        else:
            d[nm] = vals[0]
    if text != "":
        d["#text"] = text
    return d

# Élément depuis une valeur ALEX (inverse de to_dict) : dict (« @attr », « #text », enfants), list (éléments
# répétés), ou scalaire (texte).
func from_dict(tag, value):
    el := element(tag)
    _fill(el, value)
    return el

func _fill(el, value):
    t := type(value)
    if value == null:
        return
    if t == "dict":
        for k in keys(value):
            v := value[k]
            if _s.starts_with(k, "@"):
                el.set(_s.substring(k, 1, len(k)), _attr_value(v))
            elif k == "#text":
                el.append(_xp.Text(str(v)))
            elif type(v) == "list":
                for item in v:
                    c := element(k)
                    _fill(c, item)
                    el.append(c)
            else:
                c := element(k)
                _fill(c, v)
                el.append(c)
        return
    if t == "list":
        for item in value:
            c := element("item")
            _fill(c, item)
            el.append(c)
        return
    el.append(_xp.Text(_attr_value(value)))

# ---------------------------------------------------------------- forme canonique

# Forme canonique simplifiée (inspirée de C14N) : sans déclaration ni DOCTYPE, attributs triés, éléments vides en
# <a></a>, texte et commentaires conservés (sauf with_comments=false), fins de ligne « \n ». Deux documents
# équivalents ont la même forme (comparaison, signature).
func canonicalize(text, with_comments=true):
    doc := _xp.parse(text, true)
    out := []
    _canon(doc.root, out, with_comments)
    return _s.join("", out)

func _canon(node, out, with_comments):
    k := node.kind
    if k == "element":
        append(out, "<" + node.tag)
        names := []
        for a in keys(node.attrs):
            append(names, a)
        _sort(names)
        # déclarations d'espaces de noms d'abord, puis attributs
        for a in names:
            if a == "xmlns" or _s.starts_with(a, "xmlns:"):
                append(out, " " + a + "=\"" + _canon_attr(node.attrs[a]) + "\"")
        for a in names:
            if not (a == "xmlns" or _s.starts_with(a, "xmlns:")):
                append(out, " " + a + "=\"" + _canon_attr(node.attrs[a]) + "\"")
        append(out, ">")
        for c in node.children:
            _canon(c, out, with_comments)
        append(out, "</" + node.tag + ">")
    elif k == "text" or k == "cdata":
        t := _s.replace(_s.replace(_s.replace(node.data, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
        append(out, _s.replace(t, "\r", "&#xD;"))
    elif k == "comment" and with_comments:
        append(out, "<!--" + node.data + "-->")
    elif k == "pi":
        if node.data == "":
            append(out, "<?" + node.target + "?>")
        else:
            append(out, "<?" + node.target + " " + node.data + "?>")

func _canon_attr(v):
    t := _s.replace(_s.replace(_s.replace(v, "&", "&amp;"), "<", "&lt;"), "\"", "&quot;")
    return _s.replace(_s.replace(_s.replace(t, "\t", "&#x9;"), "\n", "&#xA;"), "\r", "&#xD;")

func _sort(xs):
    i := 1
    while i < len(xs):
        x := xs[i]
        j := i - 1
        while j >= 0 and xs[j] > x:
            xs[j + 1] = xs[j]
            j -= 1
        xs[j + 1] = x
        i += 1
