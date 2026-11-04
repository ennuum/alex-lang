# ALEX STANDARD LIBRARY — network.xml_writer
#
# Écriture XML : échappement, écrivain en flux (XmlWriter) qui garantit un document bien formé (noms valides,
# balises équilibrées, caractères interdits refusés), indentation facultative, et sérialisation d'un arbre
# (network.xml_parser / network.xml).
#
#   escape(texte) / escape_attr(valeur)
#   w := XmlWriter(indent=2) ; w.declaration() ; w.start("a", {"x": "1"}) ; w.text("é") ; w.end() ; w.to_string()
#   serialize(nœud, indent=null, declaration=false)
#
# Erreurs : XmlError (nom invalide, balise non fermée, caractère interdit).
#
# Exemple
#   use network.xml_writer as xw
#   w := xw.XmlWriter(2)
#   w.declaration()
#   w.start("flux", {"xmlns": "http://www.w3.org/2005/Atom"})
#   w.element("title", "Nouvelles & annonces")
#   w.end()
#   print(w.to_string())

from core use len, type
from collections use append, keys, contains_key
use string as _s

func _fail(message):
    raise("XmlError", "xml_writer : " + message)

# Vrai si le caractère est permis en XML 1.0 (#x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]).
func is_xml_char(c):
    o := _s.ord(c)
    if o == 9 or o == 10 or o == 13:
        return true
    if o < 32:
        return false
    if o >= 55296 and o <= 57343:
        return false
    return o != 65534 and o != 65535

func _check_chars(s, what):
    if _plain(s):
        return
    for c in s:
        o := _s.ord(c)
        if o < 32 and o != 9 and o != 10 and o != 13:
            _fail(what + " : caractère interdit en XML (U+" + _hex4(o) + ")")
        if o == 65534 or o == 65535:
            _fail(what + " : caractère interdit en XML (U+" + _hex4(o) + ")")

const _HEXU := "0123456789ABCDEF"

# Vrai si s ne contient aucun caractère de contrôle (cas courant, vérifié d'un coup).
func _plain(s):
    for c in s:
        if c < ' ':
            if c != '\n' and c != '\t' and c != '\r':
                return false
        elif c >= '\uFFFE':
            return false
    return true

func _hex4(o):
    return str(_HEXU[(o >> 12) & 15]) + str(_HEXU[(o >> 8) & 15]) + str(_HEXU[(o >> 4) & 15]) + str(_HEXU[o & 15])

func _is_name_start(c):
    o := _s.ord(c)
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c == ':' or (o >= 192 and o != 215 and o != 247 and not (o >= 768 and o <= 879) and o != 894 and not (o >= 8192 and o <= 8203) and not (o >= 8206 and o <= 8303) and not (o >= 8592 and o <= 11263) and not (o >= 12272 and o <= 12288) and not (o >= 55296 and o <= 63743) and not (o >= 64976 and o <= 65007) and o != 65534 and o != 65535)

func _is_name_char(c):
    if _is_name_start(c):
        return true
    o := _s.ord(c)
    return (c >= '0' and c <= '9') or c == '-' or c == '.' or o == 183 or (o >= 768 and o <= 879) or o == 8255 or o == 8256

_NAMES := {}     # noms déjà validés (les mêmes balises reviennent sans cesse)

# Vrai si s est un nom XML valide (« Name » de la recommandation).
func is_name(s):
    if type(s) != "str" or s == "":
        return false
    if contains_key(_NAMES, s):
        return true
    if not _is_name_start(s[0]):
        return false
    for c in s:
        if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_' or c == '.' or c == ':'):
            if not _is_name_char(c):
                return false
    if len(_NAMES) < 10000:
        _NAMES[s] = true
    return true

func check_name(s):
    if not is_name(s):
        _fail("nom XML invalide « " + str(s) + " »")
    return s

# Échappe & < > dans un texte (et « ]]> »).
func escape(text):
    t := str(text)
    if not (_s.contains(t, "&") or _s.contains(t, "<") or _s.contains(t, ">") or _s.contains(t, "\r")):
        return t
    t = _s.replace(t, "&", "&amp;")
    t = _s.replace(t, "<", "&lt;")
    t = _s.replace(t, ">", "&gt;")
    return _s.replace(t, "\r", "&#13;")

# Échappe une valeur d'attribut (guillemets, sauts de ligne et tabulations conservés par des références).
func escape_attr(value):
    t := escape(value)
    t = _s.replace(t, "\"", "&quot;")
    t = _s.replace(t, "\n", "&#10;")
    return _s.replace(t, "\t", "&#9;")

func _attrs_text(attrs):
    if attrs == null:
        return ""
    out := []
    for k in keys(attrs):
        check_name(k)
        v := attrs[k]
        if v == null:
            continue
        if v == true:
            v = "true"
        elif v == false:
            v = "false"
        sv := str(v)
        _check_chars(sv, "attribut « " + k + " »")
        append(out, " " + k + "=\"" + escape_attr(sv) + "\"")
    return _s.join("", out)

class XmlWriter:
    # indent : null (tout sur une ligne, texte intact) ou nombre d'espaces par niveau. Avec indentation, un
    # élément qui contient du texte reste sur une ligne (le texte n'est jamais modifié).
    func init(indent=null):
        self.indent = indent
        self.parts = []
        self.stack = []           # [nom, a_des_enfants, a_du_texte]
        self.open_tag = false     # « <a ... » écrit, « > » pas encore
        self.root_done = false
        self.started = false

    func _pad(depth):
        if self.indent == null:
            return ""
        return "\n" + " " * (self.indent * depth)

    func _close_open_tag():
        if self.open_tag:
            append(self.parts, ">")
            self.open_tag = false

    func _before_child():
        if len(self.stack) == 0:
            if self.root_done:
                _fail("un document n'a qu'un élément racine")
            return
        top := self.stack[len(self.stack) - 1]
        self._close_open_tag()
        top[1] = true

    # Déclaration « <?xml version="1.0" encoding="UTF-8"?> » (à écrire en premier).
    func declaration(version="1.0", encoding="UTF-8", standalone=null):
        if self.started:
            _fail("la déclaration XML doit venir en premier")
        d := "<?xml version=\"" + version + "\""
        if encoding != null:
            d += " encoding=\"" + encoding + "\""
        if standalone != null:
            if standalone:
                d += " standalone=\"yes\""
            else:
                d += " standalone=\"no\""
        append(self.parts, d + "?>")
        if self.indent != null:
            append(self.parts, "\n")
        self.started = true
        return self

    func doctype(name, public_id=null, system_id=null):
        d := "<!DOCTYPE " + check_name(name)
        if public_id != null:
            d += " PUBLIC \"" + public_id + "\" \"" + system_id + "\""
        elif system_id != null:
            d += " SYSTEM \"" + system_id + "\""
        append(self.parts, d + ">")
        if self.indent != null:
            append(self.parts, "\n")
        self.started = true
        return self

    func start(tag, attrs=null):
        check_name(tag)
        self._before_child()
        if len(self.stack) > 0 or len(self.parts) > 0:
            top_text := len(self.stack) > 0 and self.stack[len(self.stack) - 1][2]
            if not top_text and (len(self.stack) > 0):
                append(self.parts, self._pad(len(self.stack)))
        append(self.parts, "<" + tag + _attrs_text(attrs))
        append(self.stack, [tag, false, false])
        self.open_tag = true
        self.started = true
        return self

    # Ferme l'élément ouvert (tag : contrôle facultatif du nom).
    func end(tag=null):
        if len(self.stack) == 0:
            _fail("end() sans élément ouvert")
        top := self.stack[len(self.stack) - 1]
        if tag != null and tag != top[0]:
            _fail("fermeture de « " + tag + " » alors que « " + top[0] + " » est ouvert")
        self.stack = self.stack[0:len(self.stack) - 1]
        if self.open_tag:
            append(self.parts, "/>")
            self.open_tag = false
        else:
            if top[1] and not top[2]:
                append(self.parts, self._pad(len(self.stack)))
            append(self.parts, "</" + top[0] + ">")
        if len(self.stack) == 0:
            self.root_done = true
        return self

    func text(data):
        if data == null:
            return self
        t := str(data)
        if t == "":
            return self
        if len(self.stack) == 0:
            if _s.trim(t) != "":
                _fail("texte hors de l'élément racine")
            return self
        _check_chars(t, "texte")
        self._close_open_tag()
        top := self.stack[len(self.stack) - 1]
        top[2] = true
        append(self.parts, escape(t))
        return self

    func cdata(data):
        if len(self.stack) == 0:
            _fail("CDATA hors de l'élément racine")
        t := str(data)
        _check_chars(t, "CDATA")
        self._close_open_tag()
        self.stack[len(self.stack) - 1][2] = true
        append(self.parts, "<![CDATA[" + _s.replace(t, "]]>", "]]]]><![CDATA[>") + "]]>")
        return self

    func comment(data):
        t := str(data)
        if _s.contains(t, "--") or _s.ends_with(t, "-"):
            _fail("commentaire : « -- » interdit")
        _check_chars(t, "commentaire")
        if len(self.stack) > 0:
            self._before_child()
            if not self.stack[len(self.stack) - 1][2]:
                append(self.parts, self._pad(len(self.stack)))
        elif self.started and self.indent != null:
            append(self.parts, "\n")
        append(self.parts, "<!--" + t + "-->")
        self.started = true
        return self

    func pi(target, data=null):
        check_name(target)
        if _s.lower(target) == "xml":
            _fail("instruction de traitement « xml » réservée")
        d := ""
        if data != null:
            if _s.contains(str(data), "?>"):
                _fail("instruction de traitement : « ?> » interdit")
            d = " " + str(data)
        if len(self.stack) > 0:
            self._before_child()
            if not self.stack[len(self.stack) - 1][2]:
                append(self.parts, self._pad(len(self.stack)))
        append(self.parts, "<?" + target + d + "?>")
        self.started = true
        return self

    # Élément complet : <tag attrs>texte</tag> (ou <tag/> sans texte).
    func element(tag, text=null, attrs=null):
        self.start(tag, attrs)
        if text != null:
            self.text(text)
        return self.end()

    # Texte déjà formé, écrit tel quel (aucun contrôle).
    func raw(data):
        self._close_open_tag()
        if len(self.stack) > 0:
            self.stack[len(self.stack) - 1][2] = true
        append(self.parts, str(data))
        return self

    # Ferme tous les éléments encore ouverts.
    func close_all():
        while len(self.stack) > 0:
            self.end()
        return self

    func depth():
        return len(self.stack)

    # Document produit (erreur si des éléments sont encore ouverts).
    func to_string():
        if len(self.stack) > 0:
            _fail("élément « " + self.stack[len(self.stack) - 1][0] + " » non fermé")
        out := _s.join("", self.parts)
        if self.indent != null and not _s.ends_with(out, "\n"):
            out += "\n"
        return out

    func str():
        return self.to_string()

# ---------------------------------------------------------------- sérialisation d'un arbre

# Sérialise un nœud (élément, document, texte...) produit par network.xml_parser. indent : null (exact) ou nombre
# d'espaces (les éléments à contenu mixte gardent leur texte intact).
func serialize(node, indent=null, declaration=false, encoding="UTF-8"):
    w := XmlWriter(indent)
    if declaration:
        w.declaration("1.0", encoding)
    _write_node(w, node)
    out := _s.join("", w.parts)
    if indent != null and not _s.ends_with(out, "\n"):
        out += "\n"
    return out

func _write_node(w, node):
    k := node.kind
    if k == "document":
        for c in node.children:
            _write_node(w, c)
        return
    if k == "element":
        mixed := false
        for c in node.children:
            if c.kind == "text" or c.kind == "cdata":
                if w.indent == null or _s.trim(c.data) != "":
                    mixed = true
        w.start(node.tag, node.attrs)
        if mixed and len(w.stack) > 0:
            w.stack[len(w.stack) - 1][2] = true
        for c in node.children:
            if (c.kind == "text") and w.indent != null and not mixed and _s.trim(c.data) == "":
                continue
            _write_node(w, c)
        w.end()
        return
    if k == "text":
        if len(w.stack) == 0:
            return
        w.text(node.data)
        return
    if k == "cdata":
        w.cdata(node.data)
        return
    if k == "comment":
        w.comment(node.data)
        return
    if k == "pi":
        w.pi(node.target, node.data)
        return
    _fail("nœud inconnu « " + str(k) + " »")
